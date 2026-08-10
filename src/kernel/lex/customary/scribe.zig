//! The one writer of a book: a customary as somebody wrote it, pressed into the
//! bytes `book.zig` proves and `engine.zig` runs.
//!
//! It runs at **mint**, never at load. That is the whole reason the wire format
//! is indices and fixed-width rows rather than the names a human types: every
//! `"probe": "at_newline"` becomes a number here, once, and a scanner starting up
//! over a folio does no string comparison at all. It is also why every fault is
//! this file's to raise - a misspelled probe name is a rule that would silently
//! never match, which this area holds to be worse than a refusal.
//!
//! The source shape is the offline simulator's, exactly (`tool/customary.py`), and
//! deliberately: rung 1 proved the algebra by executing these files, so the engine
//! reading a *different* dialect of them would prove nothing. Keys the simulator
//! ignores - `note`, `cohort`, `organs`, `registers` - are documentation and are
//! ignored here too; anything else unknown is a fault, because a key nobody reads
//! is a fact somebody meant to state.
//!
//! Values are emitted children-first, which is what makes `book.proveValue`'s
//! "every child index is strictly below its parent's" hold for free and what makes
//! evaluation a walk that cannot revisit.

const std = @import("std");
const book = @import("book.zig");
const organs = @import("organs.zig");

const json = std.json;

/// A sentence about what stopped the press, for a CLI to print. Fixed-size and
/// self-owned: the alternative borrows from a JSON tree that is freed before the
/// caller reads it.
pub const Note = struct {
    buf: [224]u8 = undefined,
    len: usize = 0,

    pub fn text(n: *const Note) []const u8 {
        return n.buf[0..n.len];
    }
};

pub const Error = error{
    /// Not JSON, or not an object at the top.
    CustomaryBadJson,
    /// A key, phase, opcode, comparison, value or slice spelling this binary does
    /// not define. Refused rather than skipped: see the header.
    CustomaryUnknownWord,
    /// A test or action whose arity or argument types are not what its opcode
    /// takes.
    CustomaryBadShape,
    /// A probe, class, kind or register name no declaration resolves.
    CustomaryUnknownName,
    /// More than 32 distinct `groups` names, which is the width of a rule's
    /// bitset. Rules answering for a 33rd group could not be scored.
    CustomaryTooManyGroups,
    /// A count past what the format spends on it.
    CustomaryTooLarge,
} || std.mem.Allocator.Error;

pub const alignment = @alignOf(book.Head);

/// Keys the engine reads.
const spoken = [_][]const u8{ "tab", "budget", "asks", "trivia", "opaque", "kinds", "probes", "classes", "rules" };
/// Keys the source may carry that say nothing to the engine: the grammar's own
/// name (the folio already knows it), the cohort the transcription came from, and
/// the prose that makes a book readable. Refusing anything *else* is the point of
/// the list - a key nobody reads is a fact somebody meant to state.
const prose = [_][]const u8{ "grammar", "note", "notes", "cohort", "organs", "registers" };

/// Press one customary. The bytes are `gpa`'s and are a whole book: handing them
/// straight to `book.read` proves them, and `mint` does exactly that before it
/// writes one into a folio.
pub fn press(gpa: std.mem.Allocator, source: []const u8, say: ?*Note) Error![]align(alignment) u8 {
    var parsed = json.parseFromSlice(json.Value, gpa, source, .{}) catch {
        blame(say, "not JSON", .{});
        return Error.CustomaryBadJson;
    };
    defer parsed.deinit();
    const root = switch (parsed.value) {
        .object => |o| o,
        else => {
            blame(say, "the top of a customary is an object", .{});
            return Error.CustomaryBadJson;
        },
    };

    var s: Scribe = .{ .gpa = gpa, .say = say };
    defer s.deinit();
    try s.read(root);
    return s.emit();
}

/// Everything the layout needs before a byte is written: the name tables, the
/// rows, and the arena every span points into.
const Scribe = struct {
    gpa: std.mem.Allocator,
    say: ?*Note = null,

    kinds: std.StringHashMapUnmanaged(u8) = .empty,
    probes: std.StringHashMapUnmanaged(u32) = .empty,
    classes: std.StringHashMapUnmanaged(u32) = .empty,
    /// Group name -> which bit of a rule's `groups` it is.
    groups: std.StringHashMapUnmanaged(u32) = .empty,
    /// Interned spans, so a probe name spelled in thirty rules is one string.
    spans: std.StringHashMapUnmanaged(book.Span) = .empty,

    text: std.ArrayList(u8) = .empty,
    rules: std.ArrayList(book.RuleRow) = .empty,
    tests: std.ArrayList(book.TestRow) = .empty,
    acts: std.ArrayList(book.ActRow) = .empty,
    vals: std.ArrayList(book.ValRow) = .empty,
    probe_rows: std.ArrayList(book.ProbeRow) = .empty,
    class_rows: std.ArrayList(book.ClassRow) = .empty,
    arms: std.ArrayList(book.ArmRow) = .empty,

    tab: u32 = 8,
    budget: i32 = -1,
    trivia: i32 = -1,
    flags: u32 = 0,
    opaque_kinds: u32 = 0,
    /// The rule being read, so a fault can say which one.
    at: []const u8 = "",

    fn deinit(s: *Scribe) void {
        s.kinds.deinit(s.gpa);
        s.probes.deinit(s.gpa);
        s.classes.deinit(s.gpa);
        s.groups.deinit(s.gpa);
        s.spans.deinit(s.gpa);
        s.text.deinit(s.gpa);
        s.rules.deinit(s.gpa);
        s.tests.deinit(s.gpa);
        s.acts.deinit(s.gpa);
        s.vals.deinit(s.gpa);
        s.probe_rows.deinit(s.gpa);
        s.class_rows.deinit(s.gpa);
        s.arms.deinit(s.gpa);
    }

    // ------------------------------------------------------------- the source

    /// The declarations first, then the rules, because a rule names them.
    fn read(s: *Scribe, root: json.ObjectMap) Error!void {
        var it = root.iterator();
        while (it.next()) |kv| {
            const key = kv.key_ptr.*;
            for (spoken ++ prose) |known| {
                if (std.mem.eql(u8, key, known)) break;
            } else {
                s.blameAt("unknown top-level key `{s}`", .{key});
                return Error.CustomaryUnknownWord;
            }
        }

        if (root.get("tab")) |v| s.tab = @intCast(try s.whole(v));
        if (root.get("budget")) |v| s.budget = @intCast(try s.whole(v));
        if (root.get("asks")) |v| {
            const how = try s.word(v);
            if (std.mem.eql(u8, how, "token")) {
                s.flags |= book.Head.asks_token;
            } else if (!std.mem.eql(u8, how, "line")) {
                s.blameAt("unknown ask points `{s}`", .{how});
                return Error.CustomaryUnknownWord;
            }
        }

        if (root.get("kinds")) |v| {
            var kit = (try s.fields(v)).iterator();
            while (kit.next()) |kv| {
                const n = try s.whole(kv.value_ptr.*);
                if (n < 1 or n > 31) {
                    s.blameAt("kind `{s}` is {d}; a kind is 1..31 so it fits a bitset", .{ kv.key_ptr.*, n });
                    return Error.CustomaryBadShape;
                }
                try s.kinds.put(s.gpa, kv.key_ptr.*, @intCast(n));
            }
        }
        if (root.get("opaque")) |v| for (try s.list(v)) |k| {
            s.opaque_kinds |= @as(u32, 1) << @intCast(try s.kind(k));
        };
        if (root.get("probes")) |v| {
            var pit = (try s.fields(v)).iterator();
            while (pit.next()) |kv| {
                try s.probes.put(s.gpa, kv.key_ptr.*, @intCast(s.probe_rows.items.len));
                try s.probe_rows.append(s.gpa, .{ .pattern = try s.intern(try s.word(kv.value_ptr.*)) });
            }
        }
        // After `probes`, because it names one of them.
        if (root.get("trivia")) |v| s.trivia = @intCast(try s.probe(v));
        if (root.get("classes")) |v| {
            var cit = (try s.fields(v)).iterator();
            while (cit.next()) |kv| {
                const at: u32 = @intCast(s.arms.items.len);
                for (try s.list(kv.value_ptr.*)) |arm| {
                    const pair = try s.list(arm);
                    if (pair.len != 2) {
                        s.blameAt("class `{s}`: an arm is [pattern, terminal]", .{kv.key_ptr.*});
                        return Error.CustomaryBadShape;
                    }
                    try s.arms.append(s.gpa, .{
                        .pattern = try s.intern(try s.word(pair[0])),
                        .name = try s.intern(try s.word(pair[1])),
                    });
                }
                try s.classes.put(s.gpa, kv.key_ptr.*, @intCast(s.class_rows.items.len));
                try s.class_rows.append(s.gpa, .{ .at = at, .len = @intCast(s.arms.items.len - at) });
            }
        }

        const rules = try s.list(root.get("rules") orelse {
            s.blameAt("a customary with no `rules` is not a scanner", .{});
            return Error.CustomaryBadShape;
        });
        // Two passes over the rules, because a `fires` test in the first rule may
        // name a group only the last rule answers for.
        for (rules) |r| if ((try s.fields(r)).get("groups")) |g| {
            for (try s.list(g)) |name| _ = try s.groupBit(try s.word(name));
        };
        for (rules) |r| try s.rule(try s.fields(r));
    }

    /// One rule: its guard, its actions, and the two fields that say how it is
    /// reached.
    fn rule(s: *Scribe, r: json.ObjectMap) Error!void {
        s.at = if (r.get("name")) |n| (s.word(n) catch "?") else "?";
        const when = try s.phase(try s.word(r.get("phase") orelse {
            s.blameAt("no `phase`", .{});
            return Error.CustomaryBadShape;
        }));

        var groups: u32 = 0;
        if (r.get("groups")) |g| for (try s.list(g)) |name| {
            groups |= @as(u32, 1) << @intCast(try s.groupBit(try s.word(name)));
        };

        const test_at: u32 = @intCast(s.tests.items.len);
        if (r.get("when")) |w| for (try s.list(w)) |t| try s.check(try s.list(t));
        const act_at: u32 = @intCast(s.acts.items.len);
        if (r.get("then")) |a| for (try s.list(a)) |x| try s.deed(try s.list(x));

        try s.rules.append(s.gpa, .{
            .name = try s.intern(s.at),
            .phase = @intFromEnum(when),
            .kind = if (r.get("kind")) |k| @intCast(try s.kind(k)) else -1,
            .closes = if (r.get("closes")) |k| @intCast(try s.kind(k)) else -1,
            .groups = groups,
            .test_at = test_at,
            .test_len = @intCast(s.tests.items.len - test_at),
            .act_at = act_at,
            .act_len = @intCast(s.acts.items.len - act_at),
        });
    }

    /// One test. The shapes are the simulator's, argument for argument.
    fn check(s: *Scribe, t: []const json.Value) Error!void {
        if (t.len == 0) return Error.CustomaryBadShape;
        const op = try s.word(t[0]);
        var row: book.TestRow = .{
            .op = 0,
            .cmp = @intFromEnum(book.Cmp.none),
            .flags = 0,
            .probe_a = book.none,
            .probe_b = book.none,
            .kinds = 0,
            .group = book.none,
            .reg = book.none,
            .v0 = book.none,
            .v1 = book.none,
            .v2 = book.none,
            .name = .empty,
        };

        // A nullary fact, and the largest family: eight line facts plus `fresh`.
        const bare = [_]struct { []const u8, book.Test }{
            .{ "bol", .bol },     .{ "not_bol", .not_bol },
            .{ "blank", .blank }, .{ "not_blank", .not_blank },
            .{ "lull", .lull },   .{ "not_lull", .not_lull },
            .{ "broke", .broke }, .{ "not_broke", .not_broke },
            .{ "eof", .eof },     .{ "not_eof", .not_eof },
            .{ "fresh", .fresh },
        };
        for (bare) |b| if (std.mem.eql(u8, op, b[0])) {
            row.op = @intFromEnum(b[1]);
            return s.tests.append(s.gpa, row);
        };

        // The permission set. `sole` is not a fourth spelling of `wanted`: it
        // asks whether the state would take this terminal and nothing else.
        const asking = [_]struct { []const u8, book.Test }{
            .{ "wanted", .wanted }, .{ "not_wanted", .not_wanted },
            .{ "named", .named },   .{ "not_named", .not_named },
            .{ "sole", .sole },
        };
        for (asking) |b| if (std.mem.eql(u8, op, b[0])) {
            if (t.len != 2) return s.shape(op);
            row.op = @intFromEnum(b[1]);
            row.name = try s.intern(try s.word(t[1]));
            return s.tests.append(s.gpa, row);
        };

        // One value against a comparison, which is most of what a scanner asks.
        const measured = [_]struct { []const u8, book.Test }{
            .{ "lead", .lead },
            .{ "frames.depth", .frames_depth },
            .{ "marks.depth", .marks_depth },
            .{ "frames.top.width", .frames_top_width },
            .{ "marks.top.count", .marks_top_count },
        };
        for (measured) |b| if (std.mem.eql(u8, op, b[0])) {
            if (t.len != 3) return s.shape(op);
            row.op = @intFromEnum(b[1]);
            row.cmp = @intFromEnum(try s.cmp(try s.word(t[1])));
            row.v0 = try s.value(t[2]);
            return s.tests.append(s.gpa, row);
        };

        if (std.mem.eql(u8, op, "probe") or std.mem.eql(u8, op, "probe_at")) {
            if (t.len != 2) return s.shape(op);
            row.op = @intFromEnum(book.Test.probe);
            row.probe_a = try s.probe(t[1]);
        } else if (std.mem.eql(u8, op, "no_probe")) {
            if (t.len != 2) return s.shape(op);
            row.op = @intFromEnum(book.Test.no_probe);
            row.probe_a = try s.probe(t[1]);
        } else if (std.mem.eql(u8, op, "nest")) {
            if (t.len != 3) return s.shape(op);
            row.op = @intFromEnum(book.Test.nest);
            row.probe_a = try s.probe(t[1]);
            row.probe_b = try s.probe(t[2]);
        } else if (std.mem.eql(u8, op, "soak")) {
            row.op = @intFromEnum(book.Test.soak);
            var i: usize = 1;
            while (i < t.len) : (i += 1) {
                const w = try s.word(t[i]);
                if (std.mem.eql(u8, w, "one")) {
                    row.flags |= book.TestRow.one;
                } else if (std.mem.eql(u8, w, "to")) {
                    i += 1;
                    if (i == t.len) return s.shape(op);
                    row.flags |= book.TestRow.to;
                    row.v0 = try s.value(t[i]);
                } else if (std.mem.eql(u8, w, "from")) {
                    i += 1;
                    if (i == t.len) return s.shape(op);
                    row.flags |= book.TestRow.from;
                    row.v1 = try s.value(t[i]);
                } else {
                    s.blameAt("soak: unknown word `{s}`", .{w});
                    return Error.CustomaryUnknownWord;
                }
            }
        } else if (std.mem.eql(u8, op, "pass")) {
            if (t.len < 2) return s.shape(op);
            row.op = @intFromEnum(book.Test.pass);
            row.v0 = try s.value(t[1]);
            var i: usize = 2;
            while (i < t.len) : (i += 1) {
                const w = s.word(t[i]) catch break;
                if (std.mem.eql(u8, w, "after")) {
                    row.flags |= book.TestRow.after;
                } else if (std.mem.eql(u8, w, "until")) {
                    i += 1;
                    if (i == t.len) return s.shape(op);
                    row.flags |= book.TestRow.until;
                    row.v1 = try s.value(t[i]);
                } else {
                    // Not a modifier, so it is the comparison that turns this
                    // binding pass into a guard - and the last two arguments.
                    if (i + 2 != t.len) return s.shape(op);
                    row.cmp = @intFromEnum(try s.cmp(w));
                    row.v2 = try s.value(t[i + 1]);
                    break;
                }
            }
        } else if (std.mem.eql(u8, op, "frames.top.kind") or std.mem.eql(u8, op, "marks.top.kind")) {
            if (t.len != 3) return s.shape(op);
            row.op = @intFromEnum(if (op[0] == 'f') book.Test.frames_top_kind else book.Test.marks_top_kind);
            row.cmp = @intFromEnum(book.Cmp.in);
            row.kinds = try s.kindSet(try s.word(t[1]), t[2]);
        } else if (std.mem.eql(u8, op, "frames.at.kind")) {
            if (t.len != 4) return s.shape(op);
            row.op = @intFromEnum(book.Test.frames_at_kind);
            row.cmp = @intFromEnum(book.Cmp.in);
            row.v0 = try s.value(t[1]);
            row.kinds = try s.kindSet(try s.word(t[2]), t[3]);
        } else if (std.mem.eql(u8, op, "frames.at.width")) {
            if (t.len != 4) return s.shape(op);
            row.op = @intFromEnum(book.Test.frames_at_width);
            row.v0 = try s.value(t[1]);
            row.cmp = @intFromEnum(try s.cmp(try s.word(t[2])));
            row.v1 = try s.value(t[3]);
        } else if (std.mem.eql(u8, op, "marks.top.tag") or std.mem.eql(u8, op, "marks.has.tag")) {
            row.op = @intFromEnum(if (op[6] == 't')
                book.Test.marks_top_tag
            else
                book.Test.marks_has_tag);
            var i: usize = 1;
            while (i < t.len) : (i += 1) {
                const w = try s.word(t[i]);
                if (std.mem.eql(u8, w, "folded")) {
                    row.flags |= book.TestRow.folded;
                } else if (std.mem.eql(u8, w, "group")) {
                    i += 1;
                    if (i == t.len) return s.shape(op);
                    row.flags |= book.TestRow.grouped;
                    row.v0 = try s.value(t[i]);
                } else {
                    s.blameAt("{s}: unknown word `{s}`", .{ op, w });
                    return Error.CustomaryUnknownWord;
                }
            }
        } else if (std.mem.eql(u8, op, "frames.has") or std.mem.eql(u8, op, "marks.has")) {
            if (t.len != 2) return s.shape(op);
            row.op = @intFromEnum(if (op[0] == 'f') book.Test.frames_has else book.Test.marks_has);
            row.kinds = @as(u32, 1) << @intCast(try s.kind(t[1]));
        } else if (std.mem.eql(u8, op, "reg")) {
            if (t.len != 4) return s.shape(op);
            row.op = @intFromEnum(book.Test.reg);
            row.reg = try s.register(t[1]);
            row.cmp = @intFromEnum(try s.cmp(try s.word(t[2])));
            row.v0 = try s.value(t[3]);
        } else if (std.mem.eql(u8, op, "fires") or std.mem.eql(u8, op, "no_fires")) {
            if (t.len < 2) return s.shape(op);
            row.op = @intFromEnum(if (op[0] == 'f') book.Test.fires else book.Test.no_fires);
            row.group = try s.groupBit(try s.word(t[1]));
            if (t.len > 2) {
                const w = try s.word(t[2]);
                if (std.mem.eql(u8, w, "after")) {
                    row.flags |= book.TestRow.after;
                } else if (std.mem.eql(u8, w, "from")) {
                    if (t.len < 4) return s.shape(op);
                    row.flags |= book.TestRow.from;
                    row.v0 = try s.value(t[3]);
                    row.v1 = if (t.len > 4) try s.value(t[4]) else try s.constant(0);
                } else {
                    s.blameAt("{s}: unknown word `{s}`", .{ op, w });
                    return Error.CustomaryUnknownWord;
                }
            }
        } else {
            s.blameAt("unknown test `{s}`", .{op});
            return Error.CustomaryUnknownWord;
        }
        return s.tests.append(s.gpa, row);
    }

    /// One action.
    fn deed(s: *Scribe, a: []const json.Value) Error!void {
        if (a.len == 0) return Error.CustomaryBadShape;
        const op = try s.word(a[0]);
        var row: book.ActRow = .{
            .op = 0,
            .stack = @intFromEnum(book.Stack.frames),
            .kind = -1,
            .class = -1,
            .reg = book.none,
            .slice = @intFromEnum(book.Slice.none),
            .slice_group = 0,
            .v0 = book.none,
            .v1 = book.none,
            .name = .empty,
        };
        if (std.mem.eql(u8, op, "refuse")) {
            row.op = @intFromEnum(book.Action.refuse);
        } else if (std.mem.eql(u8, op, "abstain")) {
            row.op = @intFromEnum(book.Action.abstain);
        } else if (std.mem.eql(u8, op, "emit")) {
            if (a.len < 2) return s.shape(op);
            row.op = @intFromEnum(book.Action.emit);
            row.name = try s.intern(try s.word(a[1]));
            if (a.len > 3 and isWord(a[2], "classified")) {
                row.class = @intCast(try s.class(a[3]));
            } else if (a.len > 2) {
                row.v0 = try s.value(a[2]);
            }
        } else if (std.mem.eql(u8, op, "skip")) {
            if (a.len != 2) return s.shape(op);
            row.op = @intFromEnum(book.Action.skip);
            row.v0 = try s.value(a[1]);
        } else if (std.mem.eql(u8, op, "set")) {
            if (a.len != 3) return s.shape(op);
            row.op = @intFromEnum(book.Action.set);
            row.reg = try s.register(a[1]);
            row.v0 = try s.value(a[2]);
        } else if (std.mem.eql(u8, op, "push")) {
            if (a.len < 4) return s.shape(op);
            row.op = @intFromEnum(book.Action.push);
            // The two stacks read their arguments in the order their entries
            // are shaped: a frame is (width, kind) and a mark is (kind, count).
            if (isWord(a[1], "frames")) {
                row.v0 = try s.value(a[2]);
                row.kind = @intCast(try s.kind(a[3]));
            } else if (isWord(a[1], "marks")) {
                row.stack = @intFromEnum(book.Stack.marks);
                row.kind = @intCast(try s.kind(a[2]));
                row.v0 = try s.value(a[3]);
                if (a.len > 4) try s.tag(&row, a[4]);
            } else return s.shape(op);
        } else if (std.mem.eql(u8, op, "pop")) {
            if (a.len < 2) return s.shape(op);
            row.op = @intFromEnum(book.Action.pop);
            if (isWord(a[1], "marks")) {
                row.stack = @intFromEnum(book.Stack.marks);
            } else if (!isWord(a[1], "frames")) return s.shape(op);
            if (a.len > 2) {
                if (!isWord(a[2], "until") or a.len != 4) return s.shape(op);
                row.kind = @intCast(try s.kind(a[3]));
            }
        } else {
            s.blameAt("unknown action `{s}`", .{op});
            return Error.CustomaryUnknownWord;
        }
        return s.acts.append(s.gpa, row);
    }

    /// Where the bytes a `push marks` remembers come from.
    fn tag(s: *Scribe, row: *book.ActRow, v: json.Value) Error!void {
        switch (v) {
            .string => |lit| if (std.mem.eql(u8, lit, "match")) {
                row.slice = @intFromEnum(book.Slice.match);
            } else {
                row.slice = @intFromEnum(book.Slice.literal);
                row.name = try s.intern(lit);
            },
            .array => |xs| {
                if (xs.items.len != 2 or !isWord(xs.items[0], "group")) return s.shape("push marks");
                row.slice = @intFromEnum(book.Slice.group);
                row.slice_group = @intCast(try s.whole(xs.items[1]));
            },
            else => return s.shape("push marks"),
        }
    }

    // ------------------------------------------------------------- the values

    /// One value expression, as an index into the pool. Children are emitted
    /// first, which is `book.proveValue`'s whole termination argument.
    fn value(s: *Scribe, v: json.Value) Error!u32 {
        switch (v) {
            .integer => |n| return s.constant(@intCast(n)),
            .string => |name| {
                const flat = [_]struct { []const u8, book.Val }{
                    .{ "lead", .lead },
                    .{ "column", .column },
                    .{ "width", .width },
                    .{ "eaten", .width },
                    .{ "cursor", .cursor },
                    .{ "frames.top.width", .frames_top_width },
                    .{ "frames.depth", .frames_depth },
                    .{ "marks.depth", .marks_depth },
                    .{ "marks.top.count", .marks_top_count },
                };
                for (flat) |f| if (std.mem.eql(u8, name, f[0])) return s.node(f[1], 0, 0);
                if (std.mem.startsWith(u8, name, "pass.")) {
                    inline for (std.enums.values(book.Pass)) |p| {
                        if (std.mem.eql(u8, name["pass.".len..], @tagName(p))) {
                            return s.node(.pass, @intFromEnum(p), 0);
                        }
                    }
                }
                s.blameAt("unknown value `{s}`", .{name});
                return Error.CustomaryUnknownWord;
            },
            .array => |xs| {
                if (xs.items.len == 0) return Error.CustomaryBadShape;
                const head = try s.word(xs.items[0]);
                const arity: usize = if (std.mem.eql(u8, head, "span") or
                    std.mem.eql(u8, head, "number") or
                    std.mem.eql(u8, head, "reg") or
                    std.mem.eql(u8, head, "frames.at.width")) 2 else 3;
                if (xs.items.len != arity) return s.shape(head);
                if (std.mem.eql(u8, head, "span")) return s.node(.span, @intCast(try s.whole(xs.items[1])), 0);
                if (std.mem.eql(u8, head, "number")) return s.node(.number, @intCast(try s.whole(xs.items[1])), 0);
                if (std.mem.eql(u8, head, "reg")) {
                    return s.node(.reg, @intCast(try s.register(xs.items[1])), 0);
                }
                if (std.mem.eql(u8, head, "frames.at.width")) {
                    return s.node(.frames_at_width, @intCast(try s.value(xs.items[1])), 0);
                }
                const binary = [_]struct { []const u8, book.Val }{
                    .{ "+", .add }, .{ "-", .sub }, .{ "max", .max }, .{ "min", .min },
                };
                for (binary) |b| if (std.mem.eql(u8, head, b[0])) {
                    const lhs: i32 = @intCast(try s.value(xs.items[1]));
                    const rhs: i32 = @intCast(try s.value(xs.items[2]));
                    return s.node(b[1], lhs, rhs);
                };
                s.blameAt("unknown value `{s}`", .{head});
                return Error.CustomaryUnknownWord;
            },
            else => {
                s.blameAt("a value is a number, a name, or a list", .{});
                return Error.CustomaryBadShape;
            },
        }
    }

    fn constant(s: *Scribe, n: i32) Error!u32 {
        return s.node(.constant, n, 0);
    }

    /// Append a value node, reusing an identical one. The pool is small and every
    /// rule spells `0` and `"width"`, so interning is most of its size.
    fn node(s: *Scribe, tag_: book.Val, a: i32, b: i32) Error!u32 {
        const row: book.ValRow = .{ .tag = @intFromEnum(tag_), .a = a, .b = b };
        for (s.vals.items, 0..) |had, i| {
            if (std.meta.eql(had, row)) return @intCast(i);
        }
        try s.vals.append(s.gpa, row);
        return fits(s.vals.items.len - 1);
    }

    // -------------------------------------------------------------- the names

    fn kind(s: *Scribe, v: json.Value) Error!u8 {
        switch (v) {
            .integer => |n| {
                if (n < 1 or n > 31) return Error.CustomaryBadShape;
                return @intCast(n);
            },
            .string => |name| return s.kinds.get(name) orelse {
                s.blameAt("unknown organ kind `{s}`", .{name});
                return Error.CustomaryUnknownName;
            },
            else => return Error.CustomaryBadShape,
        }
    }

    /// A kind test's admissible set: `"=" k` is the one-element case of `"in" [..]`,
    /// which is why both land in the same bitset.
    fn kindSet(s: *Scribe, how: []const u8, v: json.Value) Error!u32 {
        if (std.mem.eql(u8, how, "=")) return @as(u32, 1) << @intCast(try s.kind(v));
        if (!std.mem.eql(u8, how, "in")) {
            s.blameAt("a kind test compares with `=` or `in`, not `{s}`", .{how});
            return Error.CustomaryUnknownWord;
        }
        var set: u32 = 0;
        for (try s.list(v)) |k| set |= @as(u32, 1) << @intCast(try s.kind(k));
        return set;
    }

    fn probe(s: *Scribe, v: json.Value) Error!u32 {
        const name = try s.word(v);
        return s.probes.get(name) orelse {
            s.blameAt("probes unknown `{s}`", .{name});
            return Error.CustomaryUnknownName;
        };
    }

    fn class(s: *Scribe, v: json.Value) Error!u32 {
        const name = try s.word(v);
        return s.classes.get(name) orelse {
            s.blameAt("unknown class `{s}`", .{name});
            return Error.CustomaryUnknownName;
        };
    }

    fn register(s: *Scribe, v: json.Value) Error!u32 {
        const n = try s.whole(v);
        if (n < 0 or n >= organs.regs_max) {
            s.blameAt("register {d} is past the {d} this engine has", .{ n, organs.regs_max });
            return Error.CustomaryUnknownName;
        }
        return @intCast(n);
    }

    /// Which bit of a rule's `groups` a name is, minting one on first sight.
    fn groupBit(s: *Scribe, name: []const u8) Error!u32 {
        if (s.groups.get(name)) |bit| return bit;
        const bit: u32 = s.groups.count();
        if (bit >= 32) {
            s.blameAt("more than 32 rule groups; `{s}` has no bit left", .{name});
            return Error.CustomaryTooManyGroups;
        }
        try s.groups.put(s.gpa, name, bit);
        return bit;
    }

    fn phase(s: *Scribe, name: []const u8) Error!book.Phase {
        inline for (std.enums.values(book.Phase)) |p| {
            if (std.mem.eql(u8, name, @tagName(p))) return p;
        }
        s.blameAt("unknown phase `{s}`", .{name});
        return Error.CustomaryUnknownWord;
    }

    fn cmp(s: *Scribe, name: []const u8) Error!book.Cmp {
        const spellings = [_]struct { []const u8, book.Cmp }{
            .{ "=", .eq },  .{ "==", .eq }, .{ "!=", .ne }, .{ "<", .lt },
            .{ "<=", .le }, .{ ">", .gt },  .{ ">=", .ge },
        };
        for (spellings) |x| if (std.mem.eql(u8, name, x[0])) return x[1];
        s.blameAt("unknown comparison `{s}`", .{name});
        return Error.CustomaryUnknownWord;
    }

    fn intern(s: *Scribe, str: []const u8) Error!book.Span {
        if (str.len == 0) return .empty;
        if (s.spans.get(str)) |had| return had;
        const at = fits(s.text.items.len);
        try s.text.appendSlice(s.gpa, str);
        const span: book.Span = .{ .off = at, .len = fits(str.len) };
        try s.spans.put(s.gpa, str, span);
        return span;
    }

    // ------------------------------------------------------- reading the tree

    fn word(s: *Scribe, v: json.Value) Error![]const u8 {
        return switch (v) {
            .string => |x| x,
            else => {
                s.blameAt("expected a name", .{});
                return Error.CustomaryBadShape;
            },
        };
    }

    fn whole(s: *Scribe, v: json.Value) Error!i64 {
        return switch (v) {
            .integer => |n| n,
            else => {
                s.blameAt("expected a whole number", .{});
                return Error.CustomaryBadShape;
            },
        };
    }

    fn list(s: *Scribe, v: json.Value) Error![]const json.Value {
        return switch (v) {
            .array => |x| x.items,
            else => {
                s.blameAt("expected a list", .{});
                return Error.CustomaryBadShape;
            },
        };
    }

    fn fields(s: *Scribe, v: json.Value) Error!json.ObjectMap {
        return switch (v) {
            .object => |x| x,
            else => {
                s.blameAt("expected an object", .{});
                return Error.CustomaryBadShape;
            },
        };
    }

    fn shape(s: *Scribe, op: []const u8) Error {
        s.blameAt("`{s}` does not take those arguments", .{op});
        return Error.CustomaryBadShape;
    }

    fn blameAt(s: *Scribe, comptime fmt: []const u8, args: anytype) void {
        if (s.at.len == 0) return blame(s.say, fmt, args);
        var buf: [160]u8 = undefined;
        const said = std.fmt.bufPrint(&buf, fmt, args) catch buf[0..];
        blame(s.say, "{s}: {s}", .{ s.at, said });
    }

    // --------------------------------------------------------------- the bytes

    /// The section, laid out exactly as `book.read` walks it.
    fn emit(s: *Scribe) Error![]align(alignment) u8 {
        const head: book.Head = .{
            .magic = book.magic,
            .version = book.version,
            .flags = s.flags,
            .tab = s.tab,
            .budget = s.budget,
            .trivia = s.trivia,
            .opaque_kinds = s.opaque_kinds,
            .rules = fits(s.rules.items.len),
            .tests = fits(s.tests.items.len),
            .acts = fits(s.acts.items.len),
            .vals = fits(s.vals.items.len),
            .probes = fits(s.probe_rows.items.len),
            .classes = fits(s.class_rows.items.len),
            .arms = fits(s.arms.items.len),
            .text = fits(s.text.items.len),
        };
        const parts = [_][]const u8{
            std.mem.asBytes(&head),
            std.mem.sliceAsBytes(s.rules.items),
            std.mem.sliceAsBytes(s.tests.items),
            std.mem.sliceAsBytes(s.acts.items),
            std.mem.sliceAsBytes(s.vals.items),
            std.mem.sliceAsBytes(s.probe_rows.items),
            std.mem.sliceAsBytes(s.class_rows.items),
            std.mem.sliceAsBytes(s.arms.items),
            s.text.items,
        };
        var total: usize = 0;
        for (parts) |p| total += p.len;
        const out = try s.gpa.alignedAlloc(u8, .fromByteUnits(alignment), total);
        var at: usize = 0;
        for (parts) |p| {
            @memcpy(out[at..][0..p.len], p);
            at += p.len;
        }
        return out;
    }
};

fn isWord(v: json.Value, want: []const u8) bool {
    return v == .string and std.mem.eql(u8, v.string, want);
}

/// A count the format has room for. A customary past `u32` is not a problem to
/// solve quietly.
fn fits(n: usize) u32 {
    return std.math.cast(u32, n) orelse std.debug.panic("customary too large: {d}", .{n});
}

fn blame(say: ?*Note, comptime fmt: []const u8, args: anytype) void {
    const n = say orelse return;
    const said = std.fmt.bufPrint(&n.buf, fmt, args) catch n.buf[0..];
    n.len = said.len;
}

// ------------------------------------------------------------------ the proofs

const testing = std.testing;

/// The smallest book that is a scanner: one rule, one probe, one answer.
const one =
    \\{ "grammar": "t", "tab": 4,
    \\  "probes": { "dash": "-+" },
    \\  "rules": [ { "name": "dash", "phase": "opening",
    \\               "when": [["bol"], ["probe", "dash"]],
    \\               "then": [["emit", "_dash", "width"]] } ] }
;

test "a pressed book reads back, and reads back the same" {
    const bytes = try press(testing.allocator, one, null);
    defer testing.allocator.free(bytes);
    const got = try book.read(bytes);
    try testing.expectEqual(@as(u32, 4), got.tab());
    try testing.expectEqual(@as(usize, 1), got.rules.len);
    try testing.expectEqual(@as(usize, 2), got.tests.len);
    try testing.expectEqualStrings("dash", got.ruleName(0));
    try testing.expectEqualStrings("-+", got.str(got.probes[0].pattern));
    try testing.expectEqualStrings("_dash", got.str(got.acts[0].name));
    try testing.expectEqual(@as(?u32, null), got.budget());
}

test "every name a rule reaches for has to resolve" {
    const bad =
        \\{ "grammar": "t", "rules": [ { "name": "r", "phase": "opening",
        \\  "when": [["probe", "nope"]], "then": [] } ] }
    ;
    var note: Note = .{};
    try testing.expectError(Error.CustomaryUnknownName, press(testing.allocator, bad, &note));
    try testing.expectEqualStrings("r: probes unknown `nope`", note.text());
}

test "an unknown test is refused rather than skipped" {
    const bad =
        \\{ "grammar": "t", "rules": [ { "name": "r", "phase": "opening",
        \\  "when": [["vibes"]], "then": [] } ] }
    ;
    var note: Note = .{};
    try testing.expectError(Error.CustomaryUnknownWord, press(testing.allocator, bad, &note));
    try testing.expectEqualStrings("r: unknown test `vibes`", note.text());
}

test "a matched rule needs a kind and only a matched rule may carry one" {
    const bad =
        \\{ "grammar": "t", "kinds": { "item": 1 },
        \\  "rules": [ { "name": "r", "phase": "opening", "kind": "item",
        \\  "when": [], "then": [] } ] }
    ;
    const bytes = try press(testing.allocator, bad, null);
    defer testing.allocator.free(bytes);
    // The rule shape is the *book's* invariant, so the press writes what it was
    // told and `read` is what refuses it. One owner per rule, checked once.
    try testing.expectError(book.Error.CustomaryBadRule, book.read(bytes));
}

test "value children land below their parent, so evaluation cannot revisit" {
    const src =
        \\{ "grammar": "t", "rules": [ { "name": "r", "phase": "opening",
        \\  "when": [["lead", ">=", ["+", ["-", 4, 1], "column"]]], "then": [] } ] }
    ;
    const bytes = try press(testing.allocator, src, null);
    defer testing.allocator.free(bytes);
    const got = try book.read(bytes);
    const top = got.tests[0].v0;
    try testing.expect(got.vals[top].a < @as(i32, @intCast(top)));
    try testing.expect(got.vals[top].b < @as(i32, @intCast(top)));
}

test "a top-level key nobody reads is a fact somebody meant to state" {
    const bad =
        \\{ "grammar": "t", "tabb": 4, "rules": [] }
    ;
    var note: Note = .{};
    try testing.expectError(Error.CustomaryUnknownWord, press(testing.allocator, bad, &note));
    try testing.expectEqualStrings("unknown top-level key `tabb`", note.text());
}

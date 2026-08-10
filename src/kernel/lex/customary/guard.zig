//! What a rule asks before it answers: the tests, and the values they compare.
//!
//! Every test is total - it holds or it does not, it cannot fail - which is the
//! property that keeps `outside.step`'s contract intact once a customary arrives:
//! a hand answers or it does not, and there was never a third thing for it to
//! do. So an index past a stack's depth is `false` rather than an error, a value
//! reading an absent register is zero, and a probe irregex could not compile was
//! refused at bind and cannot be reached from here at all.
//!
//! Three of the tests bind as well as ask, and that is the design rather than an
//! accident of it. `probe`, `soak` and `nest` all report **how far they read**,
//! the next test in the same guard starts from there, and the rule's `emit` takes
//! that as its width. A guard is therefore a little left-to-right program over
//! one cursor, which is exactly the shape the C has - `advance` moves a lexer and
//! everything after it sees the new position - and the reason the algebra needs
//! no explicit cursor arithmetic.
//!
//! `Bound` is that cursor plus what the tests saw. It lives for one attempt at
//! one rule and is thrown away when the rule declines, which is what makes
//! scoring a guard free of consequence.

const std = @import("std");
const irregex = @import("irregex");
const book = @import("book.zig");
const organs = @import("organs.zig");
const engine = @import("engine.zig");

const Ask = engine.Ask;

/// The most capture slots a probe may have, which is irregex's own ceiling
/// (`2 * (31 + 1)`): a pattern past it is refused at bind rather than truncated
/// at match. Here rather than in `engine.zig` because matching is what owns it.
pub const slots_max = 64;

/// How deep a value expression may nest before it is read as zero. `book.read`
/// already proves the pool is a DAG with strictly decreasing child indices, so
/// this is not what makes evaluation terminate - it is what keeps a book with a
/// thousand-deep chain of additions from terminating on the stack. The eight's
/// deepest expression is three.
pub const deep_max = 32;

/// A ceiling standing in for "no target", so `soak` with no `to` reads as a soak
/// to a column no line reaches. The C spells this as two loops; one loop with an
/// unreachable bound is the same thing said once.
const unbounded: i64 = 1 << 30;

/// What a guard read, as it read it.
pub const Bound = struct {
    /// Bytes this guard has claimed so far, and the rule's width when it emits.
    /// Null rather than zero because "no test read anything" and "a test read
    /// nothing" are the same answer here but not the same fact, and `soak`
    /// distinguishes them when it picks the column to start counting from.
    eaten: ?u32 = null,
    /// What a `soak` in this guard arrived at. Null means the line's own.
    lead: ?u32 = null,
    /// Which frame a `pass` has its cursor on, for a `matched` rule.
    cursor: u32 = 0,
    /// Set by the `abstain` action: this ask is over, and the rules behind this
    /// one do not get to answer at an offset it has accounted for.
    abstain: bool = false,
    /// The six numbers the last `pass` in this guard reported.
    ran: ?[6]u32 = null,
    /// The capture slots of the guard's **first** probe, which is the match a
    /// `span` value and a `slice` read. First rather than last: a rule's later
    /// probes are look-ahead about what follows, and the text the rule is *about*
    /// is what its opening probe matched.
    slots: [slots_max]isize = undefined,
    caught: usize = 0,

    /// The bytes one capture group of that match covered, empty for a group that
    /// did not participate.
    pub fn group(b: *const Bound, bytes: []const u8, k: u32) []const u8 {
        const lo = 2 * @as(usize, k);
        if (b.caught == 0 or lo + 1 >= b.caught) return "";
        const s = b.slots[lo];
        const e = b.slots[lo + 1];
        if (s < 0 or e < s or @as(usize, @intCast(e)) > bytes.len) return "";
        return bytes[@intCast(s)..@intCast(e)];
    }

    /// Where the next test in this guard starts reading.
    fn cursorAt(b: *const Bound, at: u32) u32 {
        return at + (b.eaten orelse 0);
    }
};

/// Whether one test holds, binding whatever it read into `b`.
pub fn holds(
    a: *Ask,
    t: book.TestRow,
    i: usize,
    o: *const organs.Organs,
    at: u32,
    f: organs.Facts,
    b: *Bound,
) bool {
    const cmp: book.Cmp = @enumFromInt(t.cmp);
    return switch (@as(book.Test, @enumFromInt(t.op))) {
        // A probe reads where the rule has read to, never where it began, so a
        // soak and a probe in one guard compose without either knowing about the
        // other.
        .probe => probe(a, t.probe_a, at, b),
        // The negation binds nothing on purpose: a probe that must *not* match has
        // no captures to hand the actions, and passing `b` would let a failed match
        // leave slots behind.
        .no_probe => matches(a, t.probe_a, b.cursorAt(at), null) == null,
        .nest => nest(a, t, at, b),
        .soak => soak(a, t, o, at, f, b),
        .pass => pass(a, t, cmp, o, at, f, b),

        .bol => f.bol,
        .not_bol => !f.bol,
        .blank => f.blank,
        .not_blank => !f.blank,
        .lull => f.lull,
        .not_lull => !f.lull,
        .broke => f.broke,
        .not_broke => !f.broke,
        .eof => f.eof,
        .not_eof => !f.eof,
        .fresh => a.fresh,

        // The permission set, which is the one input the offline simulator could
        // not model and this side has for free.
        .wanted => a.wanted.isSet(a.e.asks[i]),
        .not_wanted => !a.wanted.isSet(a.e.asks[i]),
        .named => a.named.isSet(a.e.asks[i]),
        .not_named => !a.named.isSet(a.e.asks[i]),
        // Nothing competes with this terminal at all: the state would take it and
        // would take nothing else. kotlin's automatic semicolon reads this to tell
        // "a statement may end here" from "a statement may end here *or* carry on".
        .sole => a.wanted.isSet(a.e.asks[i]) and a.wanted.count() == 1,

        // A soak earlier in the same guard is what this reads: the test and the
        // `lead` *value* have to mean the same thing or a matcher soaks to a
        // target and then compares against the budget it started from.
        .lead => cmp.holds(b.lead orelse f.lead, value(a, t.v0, o, f, b)),
        .frames_depth => cmp.holds(o.frameDepth(), value(a, t.v0, o, f, b)),
        .marks_depth => cmp.holds(o.markDepth(), value(a, t.v0, o, f, b)),

        .frames_top_kind => if (o.frameTop()) |top| admits(t.kinds, top.kind) else false,
        .marks_top_kind => if (o.markTop()) |top| admits(t.kinds, top.kind) else false,
        .frames_top_width => if (o.frameTop()) |top|
            cmp.holds(top.width, value(a, t.v0, o, f, b))
        else
            false,
        .marks_top_count => if (o.markTop()) |top|
            cmp.holds(top.count, value(a, t.v0, o, f, b))
        else
            false,

        // Indexed addressing, forced by markdown and by nothing else in the
        // eight: its matching pass walks the open blocks outward under a cursor it
        // keeps in `s->matched`, so the element under test is not the top.
        .frames_at_kind => if (frame(o, value(a, t.v0, o, f, b))) |got|
            admits(t.kinds, got.kind)
        else
            false,
        .frames_at_width => if (frame(o, value(a, t.v0, o, f, b))) |got|
            cmp.holds(got.width, value(a, t.v1, o, f, b))
        else
            false,

        // The bytes at the offset - or one capture group's text - against a
        // remembered tag. A heredoc's close reads `at` rather than the guard's
        // cursor, because the tag *is* what the rule is looking at; html's
        // closing name reads the group instead, because it sits past a `</` and
        // a prefix comparison would let `</division>` close a `div`.
        .marks_top_tag => tag(a, t, o, at, f, b, .top),
        .marks_has_tag => tag(a, t, o, at, f, b, .any),

        .frames_has => hasKind(o.frames[0..o.frame_len], t.kinds),
        .marks_has => hasKind(o.marks[0..o.mark_len], t.kinds),
        .reg => cmp.holds(o.regs[t.reg], value(a, t.v0, o, f, b)),

        .fires => scored(a, t, o, at, f, b),
        .no_fires => !scored(a, t, o, at, f, b),
    };
}

fn admits(kinds: u32, got: u8) bool {
    return got < 32 and kinds & (@as(u32, 1) << @intCast(got)) != 0;
}

fn hasKind(entries: anytype, kinds: u32) bool {
    for (entries) |e| if (admits(kinds, e.kind)) return true;
    return false;
}

fn frame(o: *const organs.Organs, i: i64) ?organs.Frame {
    if (i < 0 or i >= o.frameDepth()) return null;
    return o.frameAt(@intCast(i));
}

/// Run a probe, and say where it ended.
fn matches(a: *Ask, which: u32, off: u32, into: ?*Bound) ?u32 {
    if (off > a.bytes.len) return null;
    var caps = &a.e.probes[which];
    const width = caps.nslots();
    var slots: [slots_max]isize = undefined;
    if (!caps.matchAt(a.bytes, off, slots[0..width])) return null;
    const end = slots[1];
    if (end < 0) return null;
    if (into) |b| if (b.caught == 0) {
        @memcpy(b.slots[0..width], slots[0..width]);
        b.caught = width;
    };
    return @intCast(@as(usize, @intCast(end)) - off);
}

/// How far probe `which` reaches from `off`, binding nothing.
///
/// The sweep's inter-token skip needs a width and no captures, and it runs
/// before any rule exists to hold them - so it asks the same matcher the guards
/// ask, through the one door that answers without a `Bound` to write into.
pub fn reach(a: *Ask, which: u32, off: u32) ?u32 {
    return matches(a, which, off, null);
}

fn probe(a: *Ask, which: u32, at: u32, b: *Bound) bool {
    const took = matches(a, which, b.cursorAt(at), b) orelse return false;
    b.eaten = (b.eaten orelse 0) + took;
    return true;
}

/// A balanced run: from where the guard has read to, count the opener the rule
/// already matched as depth one and read forward until it is paid off.
///
/// Nested block comments are not a regular language, so no probe can spell this
/// - and the census saw the counter (swift keeps its comment depth on the C
/// stack, kotlin and scala in a local) without saying who increments it. This is
/// who. Bounded by the bytes it claims, like every other guard, and the depth
/// never outlives the rule: an unterminated comment ends at end of input, which
/// is what all three C scanners decided to do. Always holds - what it reports is
/// how far it got.
fn nest(a: *Ask, t: book.TestRow, at: u32, b: *Bound) bool {
    var off = b.cursorAt(at);
    var depth: u32 = 1;
    while (off < a.bytes.len and depth > 0) {
        // Neither probe binds the guard's match: a nested run is about the bytes
        // between its ends, and `span` should read the opener the rule itself
        // matched rather than whichever delimiter this loop stopped on.
        if (matches(a, t.probe_b, off, null)) |took| {
            depth -= 1;
            off += took;
            // A delimiter that claims nothing would leave the cursor where it
            // was; one more byte is the only way forward and the run is
            // malformed either way.
            if (depth > 0 and took == 0) off += 1;
        } else if (matches(a, t.probe_a, off, null)) |took| {
            depth += 1;
            off += @max(took, 1);
        } else off += 1;
    }
    b.eaten = off - at;
    return true;
}

/// Blanks, up to a target an organ entry may name - `while (s->indentation <
/// list_item_indentation(block))`. A guard rather than an action because what
/// follows it is a *test* on how far the budget got, and always holds for the
/// same reason `nest` does.
fn soak(a: *Ask, t: book.TestRow, o: *const organs.Organs, at: u32, f: organs.Facts, b: *Bound) bool {
    const want = if (t.flags & book.TestRow.to != 0) value(a, t.v0, o, f, b) else unbounded;
    const limit: i64 = if (t.flags & book.TestRow.one != 0) 1 else unbounded;
    var col: i64 = if (t.flags & book.TestRow.from != 0)
        value(a, t.v1, o, f, b)
    else if (b.lead) |got|
        got
    else
        carriedLead(a, o, f);
    var off = b.cursorAt(at);
    var eaten: i64 = 0;
    const tab: i64 = a.e.tab();
    while (off < a.bytes.len and eaten < limit and col < want) : (off += 1) {
        const c = a.bytes[off];
        if (c != ' ' and c != '\t') break;
        col = if (c == '\t') col + tab - @mod(col, tab) else col + 1;
        eaten += 1;
    }
    b.eaten = off - at;
    b.lead = @intCast(@max(col, 0));
    return true;
}

/// Where a soak starts counting when nothing has bound a column yet: the budget
/// this grammar carries, or the line's own indentation for one with no budget.
fn carriedLead(a: *Ask, o: *const organs.Organs, f: organs.Facts) i64 {
    return if (a.e.program.budget() != null) a.carried(o) else f.lead;
}

/// One bounded pass of the matchers over the open frames, from a stated cursor.
///
/// `after` runs it on the *next* line - past what this guard has already eaten,
/// blanks soaked, budget starting from those blanks - which is the C's look-ahead
/// simulate rather than its committing loop.
///
/// Bare, it binds and holds, exactly like `soak`: the C's look-ahead runs
/// unconditionally and only its *result* decides anything, so a rule that wants
/// the numbers without the verdict asks for the pass and reads `pass.ran` in its
/// actions. A comparison is what makes it a guard.
fn pass(
    a: *Ask,
    t: book.TestRow,
    cmp: book.Cmp,
    o: *const organs.Organs,
    at: u32,
    f: organs.Facts,
    b: *Bound,
) bool {
    const start = value(a, t.v0, o, f, b);
    var off = at;
    var lead: ?u32 = null;
    if (t.flags & book.TestRow.after != 0) {
        const soaked = organs.soak(a.bytes, b.cursorAt(at), a.e.tab(), 0);
        off = soaked[0];
        lead = soaked[1];
    }
    const until: ?u32 = if (t.flags & book.TestRow.until != 0)
        @intCast(@max(value(a, t.v1, o, f, b), 0))
    else
        null;
    b.ran = a.pass(o, off, @intCast(@max(start, 0)), lead, until);
    if (cmp == .none) return true;
    return cmp.holds(b.ran.?[@intFromEnum(book.Pass.ran)], value(a, t.v2, o, f, b));
}

/// Which marks a tag comparison is against: the innermost, or any of them.
const Reach = enum { top, any };

fn tag(
    a: *Ask,
    t: book.TestRow,
    o: *const organs.Organs,
    at: u32,
    f: organs.Facts,
    b: *const Bound,
    reach_: Reach,
) bool {
    const folded = t.flags & book.TestRow.folded != 0;
    // The grouped form compares whole: the group's own text against the whole
    // remembered tag, so a longer name cannot pass on its prefix. The offset
    // form has no end to compare to and reads exactly as many bytes as the tag
    // is long, which is what a heredoc's close needs.
    const got: ?[]const u8 = if (t.flags & book.TestRow.grouped != 0)
        b.group(a.bytes, @intCast(@max(value(a, t.v0, o, f, b), 0)))
    else
        null;
    const same = struct {
        fn one(want: []const u8, saw: ?[]const u8, bytes: []const u8, from: u32, fold: bool) bool {
            const seen = saw orelse blk: {
                if (from + want.len > bytes.len) return false;
                break :blk bytes[from..][0..want.len];
            };
            if (saw != null and seen.len != want.len) return false;
            return if (fold) std.ascii.eqlIgnoreCase(seen, want) else std.mem.eql(u8, seen, want);
        }
    }.one;
    return switch (reach_) {
        .top => o.mark_len > 0 and same(o.markTopText(), got, a.bytes, at, folded),
        .any => for (0..o.mark_len) |i| {
            if (same(o.markText(@intCast(i)), got, a.bytes, at, folded)) break true;
        } else false,
    };
}

/// Score a named group of rules here without committing any of them.
///
/// markdown calls its own `scan` with a constant permission set to ask "would a
/// block start on this line?"; the constant array is a named set of rules, and
/// this is that question with the recursion flattened.
///
/// `after` scores past what this rule's own probe already matched, which is how
/// markdown asks "would a block start on the *next* line?" - it consumes the
/// newline first, then scans. `from` anchors it at a stated offset with a stated
/// indentation instead, and the offset that matters is where a `pass` in the same
/// guard stopped: the C's look-ahead is one lexer walking forward - it soaks the
/// blanks, *matches the open blocks*, consuming their markers, and only then
/// scans for an interrupt. A `>` on the next line of an open block quote is that
/// block's continuation, and the interrupt scan never sees it, because the match
/// already ate it.
fn scored(a: *Ask, t: book.TestRow, o: *const organs.Organs, at: u32, f: organs.Facts, b: *Bound) bool {
    if (t.flags & book.TestRow.from != 0) {
        const off: u32 = @intCast(@max(value(a, t.v0, o, f, b), 0));
        const lead: u32 = @intCast(@max(value(a, t.v1, o, f, b), 0));
        return a.scored(t.group, o, @min(off, @as(u32, @intCast(a.bytes.len))), lead);
    }
    const from = if (t.flags & book.TestRow.after != 0) b.cursorAt(at) else at;
    const soaked = organs.soak(a.bytes, @min(from, @as(u32, @intCast(a.bytes.len))), a.e.tab(), 0);
    return a.scored(t.group, o, soaked[0], soaked[1]);
}

/// One node of a rule's value expressions.
///
/// `which` is an index into the pool, or `book.none` for a slot the encoder left
/// empty - which reads as zero rather than as an error, because a test that did
/// not want a second operand is not a malformed test.
pub fn value(a: *Ask, which: u32, o: *const organs.Organs, f: organs.Facts, b: *const Bound) i64 {
    return valueAt(a, which, o, f, b, 0);
}

fn valueAt(a: *Ask, which: u32, o: *const organs.Organs, f: organs.Facts, b: *const Bound, deep: u8) i64 {
    if (which == book.none or deep > deep_max) return 0;
    const v = a.e.program.vals[which];
    const kid = struct {
        fn at(ask: *Ask, i: i32, org: *const organs.Organs, fa: organs.Facts, bd: *const Bound, d: u8) i64 {
            return if (i < 0) 0 else valueAt(ask, @intCast(i), org, fa, bd, d + 1);
        }
    };
    return switch (@as(book.Val, @enumFromInt(v.tag))) {
        .constant => v.a,
        .lead => b.lead orelse f.lead,
        .column => f.column,
        .width => b.eaten orelse 0,
        .cursor => b.cursor,
        // How wide one group of the guard's match was. The count a scanner keeps
        // is nearly always the length of a run it just read - swift's `#`s,
        // kotlin's `$`s, a fence's backticks - and reading it off the match is how
        // a rule states that without arithmetic.
        .span => @intCast(b.group(a.bytes, @intCast(@max(v.a, 0))).len),
        // The figure the group spells rather than its length. Truncated at the
        // first byte that is not a digit and saturating rather than wrapping, so
        // a group the probe let through unconstrained cannot make an offset out
        // of a number the file chose.
        .number => figure(b.group(a.bytes, @intCast(@max(v.a, 0)))),
        .pass => if (b.ran) |got| got[@intCast(@max(v.a, 0))] else 0,
        .reg => o.regs[@intCast(v.a)],
        .frames_top_width => if (o.frameTop()) |top| top.width else 0,
        .frames_depth => o.frameDepth(),
        .marks_depth => o.markDepth(),
        .marks_top_count => if (o.markTop()) |top| top.count else 0,
        .frames_at_width => if (frame(o, kid.at(a, v.a, o, f, b, deep))) |got| got.width else 0,
        .add => kid.at(a, v.a, o, f, b, deep) + kid.at(a, v.b, o, f, b, deep),
        .sub => kid.at(a, v.a, o, f, b, deep) - kid.at(a, v.b, o, f, b, deep),
        .max => @max(kid.at(a, v.a, o, f, b, deep), kid.at(a, v.b, o, f, b, deep)),
        .min => @min(kid.at(a, v.a, o, f, b, deep), kid.at(a, v.b, o, f, b, deep)),
    };
}

/// The leading decimal run of `text` as a number, capped where a column stops
/// being a column.
fn figure(text: []const u8) i64 {
    var out: i64 = 0;
    for (text) |c| {
        if (c < '0' or c > '9') break;
        out = @min(out * 10 + (c - '0'), std.math.maxInt(u16));
    }
    return out;
}

test "a figure reads the digits it has and stops where they stop" {
    try std.testing.expectEqual(@as(i64, 0), figure(""));
    try std.testing.expectEqual(@as(i64, 4), figure("4"));
    try std.testing.expectEqual(@as(i64, 12), figure("12x"));
    try std.testing.expectEqual(@as(i64, 0), figure("x9"));
    try std.testing.expectEqual(@as(i64, std.math.maxInt(u16)), figure("99999999999999999999"));
}

test "a bound reports the width of a group it never captured as zero" {
    var b: Bound = .{};
    try std.testing.expectEqual(@as(usize, 0), b.group("abc", 1).len);
    b.caught = 4;
    b.slots[0] = 0;
    b.slots[1] = 3;
    b.slots[2] = -1;
    b.slots[3] = -1;
    try std.testing.expectEqualStrings("abc", b.group("abc", 0));
    try std.testing.expectEqual(@as(usize, 0), b.group("abc", 1).len);
}

test "a guard's cursor is where the last binding test stopped" {
    var b: Bound = .{};
    try std.testing.expectEqual(@as(u32, 7), b.cursorAt(7));
    b.eaten = 3;
    try std.testing.expectEqual(@as(u32, 10), b.cursorAt(7));
}

//! The writer: a pressed grammar in, one sealed buffer of folio bytes out.
//!
//! Two passes, because the header has to say how long the file is before the
//! file exists. The first runs every string into one arena and counts every
//! section; the second lays the sections out at eight-aligned offsets, fills
//! them, and seals the lot. Nothing is appended and nothing is patched
//! afterwards, so there is no window in which a half-built folio carries a valid
//! seal.
//!
//! Every press-side value is converted explicitly - a `switch` over the press's
//! action verbs, a `switch` over its shapes, a field-by-field copy of every
//! record. That is deliberately more code than memcpy'ing the structs. Somebody
//! else is editing the press right now, and the whole point of having a format
//! is that a change over there stops here as a compile error instead of
//! arriving in a stranger's file as a number that used to mean something.

const std = @import("std");
const forme = @import("forme.zig");
const leaf = @import("leaf.zig");
const g = @import("../press/grammar.zig");
const lr0 = @import("../press/lr0.zig");
const press = @import("../press/press.zig");
const lex = @import("../kernel/lex/scanner.zig");

const cell = forme.cell;

pub const Error = error{
    /// Some count does not fit in the `u32` the format spends on it. A grammar
    /// that size is not a problem to solve quietly.
    GrammarTooLarge,
    /// A production's steps are not parallel to its right-hand side, which the
    /// press promises they are. Loud, because the alternative is writing a
    /// rename onto the wrong child.
    StepsNotParallel,
} || std.mem.Allocator.Error;

/// The bytes of a folio for this grammar and this pressing.
///
/// Eight-aligned, because the reader views records where they lie and a
/// misaligned buffer would make that undefined rather than merely slow. Free it
/// with `gpa.free`.
pub fn pack(
    gpa: std.mem.Allocator,
    gr: *const g.Grammar,
    result: *const press.Result,
) Error![]align(leaf.section_align) u8 {
    var plan = try Plan.of(gpa, gr, result);
    defer plan.deinit(gpa);
    return plan.emit(gpa, gr, result);
}

/// This grammar's terminal slate, determinized here so that nobody has to do it
/// at load. Empty for a grammar with nothing lexable, and empty rather than
/// fatal for anything the format cannot write down: the section is an answer we
/// can always work out again, so refusing to publish one is a slower folio and
/// never a wrong one.
///
/// This is the one place the writer does real work rather than laying out work
/// already done. It is worth it here for the same reason it is not worth it at
/// load: a folio is written once and read every time a parse starts.
fn slate(gpa: std.mem.Allocator, gr: *const g.Grammar) Error![]const u8 {
    // Two facts wore one answer here. A grammar with nothing lexable is real and
    // common - yaml declares 113 externals and not one pattern - and publishing
    // an empty section for it is right. Running out of memory is not that, and
    // collapsing the two meant a folio written under pressure came back merely
    // slower, with the writer reporting success. A machine failure fails; a
    // property of the grammar degrades.
    var sc = lex.Scanner.compile(gpa, gr) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return &.{},
    } orelse return &.{};
    defer sc.deinit();
    return sc.freeze(gpa) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return &.{},
    } orelse &.{};
}

/// Everything the layout needs before a single section byte is written: where
/// each string landed, and how many records each section holds.
const Plan = struct {
    text: std.ArrayList(u8) = .empty,
    title: leaf.Span = .{ .off = 0, .len = 0 },
    names: []leaf.Span = &.{},
    patterns: []leaf.PatternRecord = &.{},
    aliases: []leaf.AliasRecord = &.{},
    fields: []leaf.Span = &.{},
    /// Every distinct step, and one id per body position pointing into it.
    /// A grammar has a few dozen things to say about its children and tens of
    /// thousands of places to say them, nearly all of which say nothing.
    steps: std.ArrayList(leaf.StepRecord) = .empty,
    stepref: std.ArrayList(u32) = .empty,
    body_len: u32 = 0,
    complete_len: u32 = 0,
    party_len: u32 = 0,
    /// The table, already interned. Built here rather than while filling,
    /// because the directory has to know how many groups there are before a
    /// group is written.
    table: forme.Forme = undefined,
    locked: bool = false,
    /// This grammar's slate, already determinized. Empty when the grammar has
    /// no lexable terminal at all, or when the slate holds an automaton the
    /// format refuses - a folio without one costs startup, never correctness.
    lexicon: []const u8 = &.{},

    fn of(gpa: std.mem.Allocator, gr: *const g.Grammar, result: *const press.Result) Error!Plan {
        var p: Plan = .{};
        errdefer p.deinit(gpa);
        p.table = try forme.lock(gpa, gr, result);
        p.locked = true;
        p.lexicon = try slate(gpa, gr);
        p.names = try gpa.alloc(leaf.Span, gr.names.len);
        p.patterns = try gpa.alloc(leaf.PatternRecord, gr.patterns.len);
        p.aliases = try gpa.alloc(leaf.AliasRecord, gr.aliases.len);
        p.fields = try gpa.alloc(leaf.Span, gr.field_names.len);

        p.title = try p.intern(gpa, gr.name);
        for (gr.names, 0..) |name, i| p.names[i] = try p.intern(gpa, name);
        for (gr.patterns, 0..) |pat, i| p.patterns[i] = try p.pattern(gpa, pat);
        for (gr.aliases, 0..) |alias, i| {
            const at = try p.intern(gpa, alias.name);
            p.aliases[i] = .{ .off = at.off, .len = at.len, .named = @intFromBool(alias.named) };
        }
        for (gr.field_names, 0..) |name, i| p.fields[i] = try p.intern(gpa, name);

        var seen: std.AutoHashMapUnmanaged(u64, u32) = .empty;
        defer seen.deinit(gpa);
        for (gr.productions) |prod| {
            if (prod.steps.len != prod.rhs.len) return Error.StepsNotParallel;
            p.body_len = try add(p.body_len, prod.rhs.len);
            for (prod.steps) |st| {
                const rec: leaf.StepRecord = .{
                    .alias = st.alias orelse leaf.none,
                    .field = st.field orelse leaf.none,
                };
                const slot = try seen.getOrPut(gpa, @as(u64, rec.alias) << 32 | rec.field);
                if (!slot.found_existing) {
                    slot.value_ptr.* = try fits(p.steps.items.len);
                    try p.steps.append(gpa, rec);
                }
                try p.stepref.append(gpa, slot.value_ptr.*);
            }
        }
        for (result.collection.states) |st| {
            p.complete_len = try add(p.complete_len, st.complete.len);
        }
        for (result.tables.conflicts) |k| p.party_len = try add(p.party_len, k.party.len);
        return p;
    }

    /// A nonterminal has no pattern at all, which is not the same fact as
    /// `.external` - that one is a scanner we do not have, and a consumer has
    /// to be able to refuse over it.
    fn pattern(p: *Plan, gpa: std.mem.Allocator, pat: ?g.Pattern) Error!leaf.PatternRecord {
        const spelling: []const u8, const kind: leaf.PatternKind = switch (pat orelse
            return .{ .kind = @intFromEnum(leaf.PatternKind.none), .off = 0, .len = 0 })
        {
            .literal => |s| .{ s, .literal },
            .regex => |s| .{ s, .regex },
            .external => return .{ .kind = @intFromEnum(leaf.PatternKind.external), .off = 0, .len = 0 },
        };
        const at = try p.intern(gpa, spelling);
        return .{ .kind = @intFromEnum(kind), .off = at.off, .len = at.len };
    }

    fn intern(p: *Plan, gpa: std.mem.Allocator, s: []const u8) Error!leaf.Span {
        const off = try fits(p.text.items.len);
        try p.text.appendSlice(gpa, s);
        _ = try fits(p.text.items.len);
        return .{ .off = off, .len = try fits(s.len) };
    }

    fn deinit(p: *Plan, gpa: std.mem.Allocator) void {
        p.text.deinit(gpa);
        gpa.free(p.names);
        gpa.free(p.patterns);
        gpa.free(p.aliases);
        gpa.free(p.fields);
        p.steps.deinit(gpa);
        p.stepref.deinit(gpa);
        gpa.free(p.lexicon);
        if (p.locked) p.table.deinit();
    }

    fn count(p: *const Plan, k: leaf.Kind, gr: *const g.Grammar, result: *const press.Result) u32 {
        const states: u32 = @intCast(result.collection.states.len);
        return switch (k) {
            .text => @intCast(p.text.items.len),
            .name, .pattern, .lexis, .shape, .owner => @intCast(gr.names.len),
            .supertype => @intCast(gr.supertypes.len),
            .extra => @intCast(gr.extras.len),
            .alias => @intCast(gr.aliases.len),
            .field => @intCast(gr.field_names.len),
            .production => @intCast(gr.productions.len),
            .rhs, .stepref => p.body_len,
            .step => @intCast(p.steps.items.len),
            .row => states,
            .row_span => @intCast(p.table.row_span.len),
            .groupref => @intCast(p.table.groupref.len),
            .group => @intCast(p.table.group.len),
            .set_span => @intCast(p.table.set_span.len),
            .setsym => @intCast(p.table.setsym.len),
            .odd => @intCast(p.table.odd.len),
            .complete_span => states + 1,
            .complete => p.complete_len,
            .conflict => @intCast(result.tables.conflicts.len),
            .party => p.party_len,
            .frayed => @intCast(result.tables.frayed.len),
            .lexicon => @intCast(p.lexicon.len),
        };
    }

    /// How wide a section's records are. Only the narrow ones have a choice,
    /// and each is measured against what its ids point at rather than against
    /// how many of them there are.
    fn stride(p: *const Plan, k: leaf.Kind, gr: *const g.Grammar, result: *const press.Result) u16 {
        return leaf.strideFor(k, switch (k) {
            .groupref => @intCast(p.table.group.len),
            .setsym => result.tables.width + (@as(u32, @intCast(gr.names.len)) - gr.terminal_count),
            .stepref => @intCast(p.steps.items.len),
            else => 0,
        });
    }

    fn emit(
        p: *const Plan,
        gpa: std.mem.Allocator,
        gr: *const g.Grammar,
        result: *const press.Result,
    ) Error![]align(leaf.section_align) u8 {
        var dir: [leaf.kind_count]leaf.Entry = undefined;
        var at: u64 = leaf.align8(leaf.header_len + leaf.kind_count * leaf.entry_len);
        for (std.enums.values(leaf.Kind)) |k| {
            const n = p.count(k, gr, result);
            const wide = p.stride(k, gr, result);
            dir[@intFromEnum(k)] = .{ .kind = k, .stride = wide, .count = n, .offset = at };
            at = leaf.align8(at + @as(u64, n) * wide);
        }
        const file_len = try fitsUsize(at + leaf.signet.len);

        // Zeroed, so the padding between sections is a fact rather than
        // whatever the allocator last left there. Pressing the same grammar
        // twice has to produce the same bytes, or the seal is the only thing
        // in the file that ever changes.
        const buf = try gpa.alignedAlloc(u8, comptime .fromByteUnits(leaf.section_align), file_len);
        errdefer gpa.free(buf);
        @memset(buf, 0);

        const head: leaf.Head = .{
            .version = leaf.version,
            .section_count = leaf.kind_count,
            .symbol_count = @intCast(gr.names.len),
            .terminal_count = gr.terminal_count,
            .state_count = @intCast(result.collection.states.len),
            .width = result.tables.width,
            .end = result.tables.end,
            .production_count = @intCast(gr.productions.len),
            .start = gr.start,
            .word = gr.word orelse leaf.none,
            .unfolded = result.unfolded,
            .title = p.title,
            .schema = leaf.schema(),
            .file_len = file_len,
        };
        head.write(buf[0..leaf.header_len]);
        for (dir, 0..) |e, i| e.write(buf[leaf.header_len + i * leaf.entry_len ..][0..leaf.entry_len]);

        for (dir) |e| {
            const off: usize = @intCast(e.offset);
            p.fill(e, buf[off..][0 .. @as(usize, e.count) * e.stride], gr, result);
        }
        leaf.signet.sealAt(buf, file_len - leaf.signet.len);
        return buf;
    }

    fn fill(
        p: *const Plan,
        e: leaf.Entry,
        out: []u8,
        gr: *const g.Grammar,
        result: *const press.Result,
    ) void {
        var w: Writer = .{ .out = out, .narrow = e.stride == 2 };
        switch (e.kind) {
            .text => @memcpy(out, p.text.items),
            .lexicon => @memcpy(out, p.lexicon),
            .name => for (p.names) |s| w.span(s),
            .pattern => for (p.patterns) |r| {
                w.put(r.kind);
                w.put(r.off);
                w.put(r.len);
            },
            .lexis => for (gr.lexis) |lx| {
                w.put(if (lx.immediate) leaf.LexisRecord.immediate else 0);
                w.putSigned(lx.prec);
            },
            .shape => for (gr.shapes) |s| w.put(@intFromEnum(shapeOf(s))),
            .owner => for (gr.owner) |s| w.put(s),
            .supertype => for (gr.supertypes) |s| w.put(s),
            .extra => for (gr.extras) |s| w.put(s),
            .alias => for (p.aliases) |r| {
                w.put(r.off);
                w.put(r.len);
                w.put(r.named);
            },
            .field => for (p.fields) |s| w.span(s),
            .production => {
                var off: u32 = 0;
                for (gr.productions) |prod| {
                    w.put(prod.lhs);
                    w.put(off);
                    w.put(@intCast(prod.rhs.len));
                    off += @intCast(prod.rhs.len);
                }
            },
            .rhs => for (gr.productions) |prod| {
                for (prod.rhs) |s| w.put(s);
            },
            .stepref => for (p.stepref.items) |id| w.id(id),
            .step => for (p.steps.items) |st| {
                w.put(st.alias);
                w.put(st.field);
            },
            .row => for (p.table.row) |r| w.put(r),
            .row_span => for (p.table.row_span) |n| w.put(n),
            .groupref => for (p.table.groupref) |id| w.id(id),
            .group => for (p.table.group) |rec| {
                w.put(rec.cell);
                w.put(rec.set);
            },
            .set_span => for (p.table.set_span) |n| w.put(n),
            .setsym => for (p.table.setsym) |col| w.id(col),
            .odd => for (p.table.odd) |rec| {
                w.put(rec.state);
                w.put(rec.symbol);
                w.put(rec.target);
            },
            .complete_span => w.spans(result.collection.states, completeCount),
            .complete => for (result.collection.states) |st| {
                for (st.complete) |prod| w.put(prod);
            },
            .conflict => {
                var off: u32 = 0;
                for (result.tables.conflicts) |x| {
                    w.put(x.state);
                    w.put(x.terminal);
                    w.put(@intFromEnum(switch (x.kind) {
                        .shift_reduce => leaf.ConflictKind.shift_reduce,
                        .reduce_reduce => leaf.ConflictKind.reduce_reduce,
                    }));
                    w.put(@intFromEnum(switch (x.class) {
                        .repetition => leaf.ConflictClass.repetition,
                        .declared => leaf.ConflictClass.declared,
                        .residual => leaf.ConflictClass.residual,
                    }));
                    w.put(cell(x.chosen));
                    w.put(cell(x.other));
                    w.put(off);
                    w.put(@intCast(x.party.len));
                    off += @intCast(x.party.len);
                }
            },
            .party => for (result.tables.conflicts) |x| {
                for (x.party) |s| w.put(s);
            },
            .frayed => for (result.tables.frayed) |x| {
                w.put(x.state);
                w.put(x.terminal);
                w.put(@intFromEnum(switch (x.harm) {
                    .read_dropped => leaf.Harm.read_dropped,
                    .fold_dropped => leaf.Harm.fold_dropped,
                }));
            },
        }
    }
};

fn shapeOf(s: g.Shape) leaf.ShapeKind {
    return switch (s) {
        .named => .named,
        .anonymous => .anonymous,
        .hidden => .hidden,
        .invented => .invented,
    };
}

fn completeCount(st: lr0.State) usize {
    return st.complete.len;
}

/// A cursor over one section. Little-endian on every host, which is the only
/// reason a folio written on one machine reads on another.
const Writer = struct {
    out: []u8,
    /// Set for a narrow section, where every record is one id at half width.
    narrow: bool = false,
    at: usize = 0,

    fn put(w: *Writer, v: u32) void {
        std.mem.writeInt(u32, w.out[w.at..][0..4], v, .little);
        w.at += 4;
    }

    /// A bare id, at whatever width the directory promised for this section.
    fn id(w: *Writer, v: u32) void {
        if (!w.narrow) return w.put(v);
        std.mem.writeInt(u16, w.out[w.at..][0..2], @intCast(v), .little);
        w.at += 2;
    }

    fn putSigned(w: *Writer, v: i32) void {
        std.mem.writeInt(i32, w.out[w.at..][0..4], v, .little);
        w.at += 4;
    }

    fn span(w: *Writer, s: leaf.Span) void {
        w.put(s.off);
        w.put(s.len);
    }

    /// A prefix-sum span table: `n + 1` entries whose last is the total, so a
    /// state's slice is two loads and never a bounds question.
    fn spans(w: *Writer, states: []const lr0.State, comptime lenOf: fn (lr0.State) usize) void {
        var total: u32 = 0;
        w.put(total);
        for (states) |st| {
            total += @intCast(lenOf(st));
            w.put(total);
        }
    }
};

fn add(base: u32, n: usize) Error!u32 {
    return fits(@as(u64, base) + n);
}

fn fits(n: u64) Error!u32 {
    if (n > std.math.maxInt(u32)) return Error.GrammarTooLarge;
    return @intCast(n);
}

fn fitsUsize(n: u64) Error!usize {
    if (n > std.math.maxInt(usize)) return Error.GrammarTooLarge;
    return @intCast(n);
}

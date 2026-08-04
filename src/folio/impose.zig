//! The writer: a pressed grammar in, one sealed buffer of folio bytes out.
//!
//! Two passes, because the header has to say how long the file is before the
//! file exists. The first runs every string into one arena and counts every
//! section; the second lays the sections out at eight-aligned offsets, fills
//! them, and seals the lot. Nothing is appended and nothing is patched
//! afterwards, so there is no window in which a half-built folio carries a valid
//! seal.
//!
//! Every press-side value is converted explicitly — a `switch` over the press's
//! action verbs, a `switch` over its shapes, a field-by-field copy of every
//! record. That is deliberately more code than memcpy'ing the structs. Somebody
//! else is editing the press right now, and the whole point of having a format
//! is that a change over there stops here as a compile error instead of
//! arriving in a stranger's file as a number that used to mean something.

const std = @import("std");
const leaf = @import("leaf.zig");
const g = @import("../press/grammar.zig");
const lr0 = @import("../press/lr0.zig");
const press = @import("../press/press.zig");

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

/// Everything the layout needs before a single section byte is written: where
/// each string landed, and how many records each section holds.
const Plan = struct {
    text: std.ArrayList(u8) = .empty,
    title: leaf.Span = .{ .off = 0, .len = 0 },
    names: []leaf.Span = &.{},
    patterns: []leaf.PatternRecord = &.{},
    aliases: []leaf.AliasRecord = &.{},
    fields: []leaf.Span = &.{},
    body_len: u32 = 0,
    edge_len: u32 = 0,
    complete_len: u32 = 0,
    kernel_len: u32 = 0,

    fn of(gpa: std.mem.Allocator, gr: *const g.Grammar, result: *const press.Result) Error!Plan {
        var p: Plan = .{};
        errdefer p.deinit(gpa);
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

        for (gr.productions) |prod| {
            if (prod.steps.len != prod.rhs.len) return Error.StepsNotParallel;
            p.body_len = try add(p.body_len, prod.rhs.len);
        }
        for (result.collection.states) |st| {
            p.edge_len = try add(p.edge_len, st.edges.len);
            p.complete_len = try add(p.complete_len, st.complete.len);
            p.kernel_len = try add(p.kernel_len, st.kernel.len);
        }
        return p;
    }

    /// A nonterminal has no pattern at all, which is not the same fact as
    /// `.external` — that one is a scanner we do not have, and a consumer has
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
            .rhs, .step => p.body_len,
            .action => @intCast(result.tables.action.len),
            .goto_span, .complete_span, .kernel_span => states + 1,
            .goto_edge => p.edge_len,
            .complete => p.complete_len,
            .kernel => p.kernel_len,
        };
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
            dir[@intFromEnum(k)] = .{ .kind = k, .stride = leaf.strideOf(k), .count = n, .offset = at };
            at = leaf.align8(at + @as(u64, n) * leaf.strideOf(k));
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
            p.fill(e.kind, buf[off..][0 .. @as(usize, e.count) * e.stride], gr, result);
        }
        leaf.signet.sealAt(buf, file_len - leaf.signet.len);
        return buf;
    }

    fn fill(
        p: *const Plan,
        k: leaf.Kind,
        out: []u8,
        gr: *const g.Grammar,
        result: *const press.Result,
    ) void {
        var w: Writer = .{ .out = out };
        switch (k) {
            .text => @memcpy(out, p.text.items),
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
            .step => for (gr.productions) |prod| {
                for (prod.steps) |st| {
                    w.put(st.alias orelse leaf.none);
                    w.put(st.field orelse leaf.none);
                }
            },
            // The one place the two action encodings meet. A verb the press
            // grows later lands here as a missing switch prong, not as a cell
            // that reads back as something else.
            .action => for (result.tables.action) |a| w.put(@bitCast(leaf.Action{
                .verb = switch (a.kind) {
                    .err => .err,
                    .shift => .shift,
                    .reduce => .reduce,
                    .accept => .accept,
                },
                .value = a.value,
            })),
            .goto_span => w.spans(result.collection.states, edgeCount),
            .goto_edge => for (result.collection.states) |st| {
                for (st.edges) |e| {
                    w.put(e.symbol);
                    w.put(e.target);
                }
            },
            .complete_span => w.spans(result.collection.states, completeCount),
            .complete => for (result.collection.states) |st| {
                for (st.complete) |prod| w.put(prod);
            },
            .kernel_span => w.spans(result.collection.states, kernelCount),
            .kernel => for (result.collection.states) |st| {
                for (st.kernel) |item| {
                    w.put(item.prod);
                    w.put(item.dot);
                }
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

fn edgeCount(st: lr0.State) usize {
    return st.edges.len;
}

fn completeCount(st: lr0.State) usize {
    return st.complete.len;
}

fn kernelCount(st: lr0.State) usize {
    return st.kernel.len;
}

/// A cursor over one section. Little-endian on every host, which is the only
/// reason a folio written on one machine reads on another.
const Writer = struct {
    out: []u8,
    at: usize = 0,

    fn put(w: *Writer, v: u32) void {
        std.mem.writeInt(u32, w.out[w.at..][0..4], v, .little);
        w.at += 4;
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

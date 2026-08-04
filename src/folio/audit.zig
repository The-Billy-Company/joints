//! What `open` checks after the layout adds up: that every number inside a
//! section means something.
//!
//! The split is not cosmetic. Layout validation answers "can these bytes be
//! read at all"; this answers "can they be *believed*", and only the second one
//! needs the sections to already be viewable. Keeping them apart is also what
//! lets the layout half stay short enough to read in one sitting, which for the
//! half that stands between a hostile file and a pointer seems worth insisting
//! on.
//!
//! Two rules about what belongs here. Everything that could become an
//! out-of-range index, an out-of-arena slice, or an undefined tag is checked —
//! those are the ones that turn a bad file into a bad memory access, and the
//! accessors do no checking precisely because this pass did. Nothing that is
//! merely unusual is checked: a nonterminal carrying a pattern is odd and is
//! not unsafe, and a reader that refuses a folio its own writer would produce
//! is a worse bug than the one it was guarding against.
//!
//! It costs a linear sweep of the action table, which on the largest real
//! grammar is a couple of million cells and a few milliseconds. That is the
//! price of the accessors being branchless, paid once at open rather than on
//! every cell of every parse.

const std = @import("std");
const leaf = @import("leaf.zig");
const collate = @import("collate.zig");

const Error = leaf.Error;
const Folio = collate.Folio;

/// Every section's count against the header, and the header against itself.
pub fn counts(f: *const Folio) Error!void {
    const h = f.head;
    if (h.terminal_count > h.symbol_count) return Error.FolioBadSymbol;
    if (h.symbol_count == 0 or h.production_count == 0 or h.state_count == 0) return Error.FolioBadCount;
    if (h.width == 0 or h.end >= h.width) return Error.FolioBadCount;
    if (h.start >= h.symbol_count) return Error.FolioBadSymbol;
    if (h.word != leaf.none and h.word >= h.terminal_count) return Error.FolioBadSymbol;

    for ([_]leaf.Kind{ .name, .pattern, .lexis, .shape, .owner }) |k| {
        if (f.dir[@intFromEnum(k)].count != h.symbol_count) return Error.FolioBadCount;
    }
    for ([_]leaf.Kind{ .goto_span, .complete_span, .kernel_span }) |k| {
        if (f.dir[@intFromEnum(k)].count != h.state_count + 1) return Error.FolioBadCount;
    }
    if (f.dir[@intFromEnum(leaf.Kind.production)].count != h.production_count) return Error.FolioBadCount;
    if (f.dir[@intFromEnum(leaf.Kind.rhs)].count != f.dir[@intFromEnum(leaf.Kind.step)].count) {
        return Error.FolioBadCount;
    }
    if (@as(u64, h.state_count) * h.width != f.dir[@intFromEnum(leaf.Kind.action)].count) {
        return Error.FolioBadCount;
    }
    try arena(f, f.head.title);
}

/// Every id, span, and tag inside the sections.
pub fn contents(f: *const Folio) Error!void {
    const h = f.head;

    for (f.view(.name, leaf.Span)) |s| try arena(f, s);
    for (f.view(.field, leaf.Span)) |s| try arena(f, s);
    for (f.view(.pattern, leaf.PatternRecord)) |p| {
        switch (try tag(leaf.PatternKind, p.kind)) {
            .literal, .regex => try arena(f, .{ .off = p.off, .len = p.len }),
            .none, .external => if (p.off != 0 or p.len != 0) return Error.FolioBadTag,
        }
    }
    for (f.view(.lexis, leaf.LexisRecord)) |lx| {
        if (lx.flags & ~leaf.LexisRecord.known != 0) return Error.FolioBadTag;
    }
    for (f.view(.shape, u32)) |s| _ = try tag(leaf.ShapeKind, s);
    for (f.view(.alias, leaf.AliasRecord)) |a| {
        try arena(f, .{ .off = a.off, .len = a.len });
        if (a.named > 1) return Error.FolioBadTag;
    }
    inline for (.{ leaf.Kind.owner, .supertype, .extra, .rhs }) |k| {
        for (f.view(k, u32)) |s| {
            if (s >= h.symbol_count) return Error.FolioBadSymbol;
        }
    }

    const bodies = f.dir[@intFromEnum(leaf.Kind.rhs)].count;
    for (f.view(.production, leaf.ProductionRecord)) |p| {
        if (p.lhs >= h.symbol_count) return Error.FolioBadSymbol;
        if (@as(u64, p.rhs_off) + p.rhs_len > bodies) return Error.FolioBadProduction;
    }
    const alias_count = f.aliasCount();
    const field_count = f.fieldCount();
    for (f.view(.step, leaf.StepRecord)) |st| {
        if (st.alias != leaf.none and st.alias >= alias_count) return Error.FolioBadIndex;
        if (st.field != leaf.none and st.field >= field_count) return Error.FolioBadIndex;
    }

    // The table itself. A shift naming a state that is not there and a fold
    // naming a production that is not there are the two ways a legal-looking
    // cell walks a parser off the end of the automaton.
    for (f.view(.action, leaf.Action)) |a| switch (a.verb) {
        .shift => if (a.value >= h.state_count) return Error.FolioBadState,
        .reduce => if (a.value >= h.production_count) return Error.FolioBadProduction,
        .err, .accept => {},
    };

    try ascends(f, .goto_span, .goto_edge);
    try ascends(f, .complete_span, .complete);
    try ascends(f, .kernel_span, .kernel);

    for (f.view(.goto_edge, leaf.EdgeRecord)) |e| {
        if (e.symbol >= h.symbol_count) return Error.FolioBadSymbol;
        if (e.target >= h.state_count) return Error.FolioBadState;
    }
    for (f.view(.complete, u32)) |prod| {
        if (prod >= h.production_count) return Error.FolioBadProduction;
    }
    const prods = f.view(.production, leaf.ProductionRecord);
    for (f.view(.kernel, leaf.ItemRecord)) |item| {
        if (item.prod >= h.production_count) return Error.FolioBadProduction;
        if (item.dot > prods[item.prod].rhs_len) return Error.FolioBadProduction;
    }
}

/// A span table has to start at zero, never go backwards, and end at exactly
/// the length of what it indexes. Anything else and a state's slice is either
/// somebody else's records or nobody's.
fn ascends(f: *const Folio, comptime spans: leaf.Kind, comptime items: leaf.Kind) Error!void {
    const table = f.view(spans, u32);
    const total = f.dir[@intFromEnum(items)].count;
    if (table[0] != 0 or table[table.len - 1] != total) return Error.FolioBadSpan;
    for (table[1..], table[0 .. table.len - 1]) |now, before| {
        if (now < before) return Error.FolioBadSpan;
    }
}

/// A stored number as one of this version's tags. Both tag enums are dense and
/// start at zero, so being in range is the whole question — and a value out of
/// it is a meaning a later version gave the field, which is exactly what must
/// not be guessed at.
fn tag(comptime E: type, v: u32) Error!E {
    if (v >= std.enums.values(E).len) return Error.FolioBadTag;
    return @enumFromInt(v);
}

fn arena(f: *const Folio, s: leaf.Span) Error!void {
    const text = f.dir[@intFromEnum(leaf.Kind.text)].count;
    if (@as(u64, s.off) + s.len > text) return Error.FolioBadText;
}

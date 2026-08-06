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
//! out-of-range index, an out-of-arena slice, or an undefined tag is checked  -
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
    if (f.dir[@intFromEnum(leaf.Kind.complete_span)].count != h.state_count + 1) return Error.FolioBadCount;
    if (f.dir[@intFromEnum(leaf.Kind.production)].count != h.production_count) return Error.FolioBadCount;
    if (f.dir[@intFromEnum(leaf.Kind.rhs)].count != f.dir[@intFromEnum(leaf.Kind.stepref)].count) {
        return Error.FolioBadCount;
    }
    if (f.dir[@intFromEnum(leaf.Kind.row)].count != h.state_count) return Error.FolioBadCount;
    // A span table of zero entries has no leading zero and no total, so every
    // slice taken from it would be read out of somebody else's section.
    for ([_]leaf.Kind{ .row_span, .set_span }) |k| {
        if (f.dir[@intFromEnum(k)].count == 0) return Error.FolioBadCount;
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
        // The record is a word wide and the IR's rank is half of it, so a rank
        // past `i16` is a file `bind` would silently truncate. Doubted here,
        // where every other impossible number is doubted, rather than narrowed
        // hopefully at bind.
        if (p.rank < std.math.minInt(i16) or p.rank > std.math.maxInt(i16)) {
            return Error.FolioBadProduction;
        }
    }
    const alias_count = f.aliasCount();
    const field_count = f.fieldCount();
    const steps = f.view(.step, leaf.StepRecord);
    for (steps) |st| {
        if (st.alias != leaf.none and st.alias >= alias_count) return Error.FolioBadIndex;
        if (st.field != leaf.none and st.field >= field_count) return Error.FolioBadIndex;
    }
    const refs = f.ids(.stepref);
    for (0..refs.len()) |i| {
        if (refs.at(@intCast(i)) >= steps.len) return Error.FolioBadIndex;
    }

    try table(f);

    try ascends(f, .complete_span, .complete);
    for (f.view(.complete, u32)) |prod| {
        if (prod >= h.production_count) return Error.FolioBadProduction;
    }

    const parties = f.dir[@intFromEnum(leaf.Kind.party)].count;
    const rivals = f.dir[@intFromEnum(leaf.Kind.rival)].count;
    for (f.view(.conflict, leaf.ConflictRecord)) |k| {
        if (k.state >= h.state_count) return Error.FolioBadState;
        if (k.terminal >= h.width) return Error.FolioBadSymbol;
        _ = try tag(leaf.ConflictKind, k.kind);
        _ = try tag(leaf.ConflictClass, k.class);
        // A dropped reading is a cell a parse will step into, so it is held to
        // the same range checks as one the table chose.
        for ([_]u32{ k.chosen, k.other }) |raw| try reachable(f, @bitCast(raw));
        if (@as(u64, k.party_off) + k.party_len > parties) return Error.FolioBadIndex;
        if (@as(u64, k.rival_off) + k.rival_len > rivals) return Error.FolioBadIndex;
    }
    for (f.view(.party, u32)) |s| {
        if (s >= h.symbol_count) return Error.FolioBadSymbol;
    }
    // A third reading is stepped into exactly like the second, so it is held to
    // the same reachability check and not merely to a bound.
    for (f.view(.rival, u32)) |raw| try reachable(f, @bitCast(raw));
    for (f.view(.frayed, leaf.FrayedRecord)) |x| {
        if (x.state >= h.state_count) return Error.FolioBadState;
        if (x.terminal >= h.width) return Error.FolioBadSymbol;
        _ = try tag(leaf.Harm, x.harm);
    }
}

/// Every layer of the interned table, top down: no state reaches a row that is
/// not there, no row a group, no group a set, no set a column.
///
/// What is deliberately not checked is whether two groups of one row claim the
/// same column. It is a table nobody would write and it is not unsafe - the
/// expansion writes one cell twice and the second wins - so it falls on the
/// "merely unusual" side of the line this file draws, and the seal already
/// catches every accidental way of getting there.
fn table(f: *const Folio) Error!void {
    const groups = f.dir[@intFromEnum(leaf.Kind.group)].count;
    const sets = f.dir[@intFromEnum(leaf.Kind.set_span)].count - 1;
    const columns = f.columnCount();

    const rows = f.rowCount();
    for (f.view(.row, u32)) |r| {
        if (r >= rows) return Error.FolioBadIndex;
    }
    try climbs(f, .row_span, f.ids(.groupref).len());
    try climbs(f, .set_span, f.ids(.setsym).len());

    const refs = f.ids(.groupref);
    for (0..refs.len()) |i| {
        if (refs.at(@intCast(i)) >= groups) return Error.FolioBadIndex;
    }
    for (f.view(.group, leaf.GroupRecord)) |rec| {
        try reachable(f, @bitCast(rec.cell));
        if (rec.set >= sets) return Error.FolioBadIndex;
    }
    const cols = f.ids(.setsym);
    for (0..cols.len()) |i| {
        if (cols.at(@intCast(i)) >= columns) return Error.FolioBadSymbol;
    }
    for (f.odds()) |rec| {
        if (rec.state >= f.head.state_count) return Error.FolioBadState;
        // Only a terminal can be strayed: a nonterminal's transition is a
        // column in the row and has nowhere else to be.
        if (rec.symbol >= f.head.terminal_count) return Error.FolioBadSymbol;
        if (rec.target != leaf.none and rec.target >= f.head.state_count) return Error.FolioBadState;
    }
}

/// A cell that names something that is there. A shift naming a state that is
/// not and a fold naming a production that is not are the two ways a
/// legal-looking cell walks a parser off the end of the automaton.
fn reachable(f: *const Folio, a: leaf.Action) Error!void {
    switch (a.verb) {
        .shift => if (a.value >= f.head.state_count) return Error.FolioBadState,
        .reduce => if (a.value >= f.head.production_count) return Error.FolioBadProduction,
        .err, .accept => {},
    }
}

/// A span table has to start at zero, never go backwards, and end at exactly
/// the length of what it indexes. Anything else and a state's slice is either
/// somebody else's records or nobody's.
fn ascends(f: *const Folio, comptime spans: leaf.Kind, comptime items: leaf.Kind) Error!void {
    try climbs(f, spans, f.dir[@intFromEnum(items)].count);
}

fn climbs(f: *const Folio, comptime spans: leaf.Kind, total: u32) Error!void {
    const at = f.view(spans, u32);
    if (at[0] != 0 or at[at.len - 1] != total) return Error.FolioBadSpan;
    for (at[1..], at[0 .. at.len - 1]) |now, before| {
        if (now < before) return Error.FolioBadSpan;
    }
}

/// A stored number as one of this version's tags. Both tag enums are dense and
/// start at zero, so being in range is the whole question - and a value out of
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

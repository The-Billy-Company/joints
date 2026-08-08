//! Locking the table up: a dense parse table in, one copy of each distinct
//! thing in it out.
//!
//! A pressed table is `states * width` cells and about three percent of them
//! say anything, so writing it down as it stands spends most of a folio on the
//! word "no". But the interesting part is not the emptiness - that is easy to
//! skip - it is that the *non*-empty part is enormously repetitive. Real
//! grammars have thousands of states and a few hundred distinct rows; a row has
//! a handful of distinct values and each value covers a run of columns; and the
//! column sets themselves recur, because "any of the binary operators" is a set
//! the grammar has an opinion about in dozens of places.
//!
//! So three interning layers, each over the layer below:
//!
//!   state -> row -> group -> (cell, column set)
//!
//! and nothing is stored twice at any level. That is where the size goes: on
//! the eleven-grammar corpus this is the table at about five percent of its
//! dense spelling, with no compressor anywhere near it and every layer still a
//! bare array that a reader can index.
//!
//! Terminals and nonterminals share one column space, which is the other half
//! of the trick. A goto is `shift` into the nonterminal half, so the same
//! machinery interns both, and a state that shifts to 41 on a terminal and
//! gotos to 41 on a nonterminal writes that value once. It also means the
//! separate goto table stops existing: `odd` below is all that is left of it.

const std = @import("std");
const leaf = @import("leaf.zig");
const press = @import("../press/press.zig");

pub const Error = std.mem.Allocator.Error;

/// The locked table, in the six arrays the folio writes and one that says
/// where the automaton disagrees with it.
///
/// Owns its arrays; `deinit` when the folio is written. Every slice is already
/// in the order and the encoding the section wants, so `impose` copies rather
/// than decides.
pub const Forme = struct {
    arena: std.heap.ArenaAllocator,
    /// Per state, its row.
    row: []const u32,
    /// Per row, where its groups start in `groupref`. `rows + 1` long.
    row_span: []const u32,
    groupref: []const u32,
    group: []const leaf.GroupRecord,
    /// Per set, where its columns start in `setsym`. `sets + 1` long.
    set_span: []const u32,
    setsym: []const u32,
    odd: []const leaf.OddRecord,

    pub fn deinit(f: *Forme) void {
        f.arena.deinit();
        f.* = undefined;
    }

    pub fn rows(f: *const Forme) u32 {
        return @intCast(f.row_span.len - 1);
    }

    pub fn sets(f: *const Forme) u32 {
        return @intCast(f.set_span.len - 1);
    }
};

/// Lock the pressed table and the automaton's transitions into one forme.
///
/// Both are taken because they are two halves of one table and only look like
/// two structures: `press` keeps the transitions beside the states and the
/// verdicts in a grid, and a folio has no reason to inherit that split.
pub fn lock(
    gpa: std.mem.Allocator,
    gr: *const press.Grammar,
    result: *const press.Result,
) Error!Forme {
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const a = arena.allocator();

    // Keys outlive their insertion and die with the build, so they get their
    // own arena rather than a place in the result's.
    var keys = std.heap.ArenaAllocator.init(gpa);
    defer keys.deinit();

    var b: Locker = .{
        .gpa = gpa,
        .out = a,
        .keys = keys.allocator(),
        .width = result.tables.width,
        .terminals = gr.terminal_count,
    };
    defer b.deinit();

    const states = result.collection.states;
    const row = try a.alloc(u32, states.len);
    try b.row_span.append(a, 0);
    try b.set_span.append(a, 0);

    for (states, 0..) |st, i| {
        const q: u32 = @intCast(i);
        b.cells.clearRetainingCapacity();
        try b.verdicts(q, result.tables);
        try b.walk(st);
        row[q] = try b.intern();
        try b.stray(q, st, result.tables);
    }
    return .{
        .arena = arena,
        .row = row,
        .row_span = b.row_span.items,
        .groupref = b.groupref.items,
        .group = b.group.items,
        .set_span = b.set_span.items,
        .setsym = b.setsym.items,
        .odd = b.odd.items,
    };
}

/// One thing a state says, as a column and the word in it. `extern` so a run of
/// them is a run of bytes a hash map can key on directly.
const Said = extern struct {
    col: u32,
    cell: u32,
};

comptime {
    // The sentence above, as a gate. `intern` keys a row on `sliceAsBytes` of a
    // run of these, so a field that left the type with slack would hash and
    // compare bytes the allocation supplied - and two states saying the same
    // thing would intern as two rows, which is a bigger table for no reason and
    // a table that is a function of the allocator. Same law the folio's
    // sections are held to, so there is one of it.
    leaf.seamless(Said);
}

const Locker = struct {
    gpa: std.mem.Allocator,
    /// Where the result's arrays go.
    out: std.mem.Allocator,
    /// Where an interned key's bytes go; freed when the build is.
    keys: std.mem.Allocator,
    width: u32,
    terminals: u32,

    /// The state under construction, in ascending column order.
    cells: std.ArrayList(Said) = .empty,
    /// The groups of the row under construction, as ids, ascending.
    refs: std.ArrayList(u32) = .empty,
    /// Which of `cells` a group has already claimed.
    taken: std.ArrayList(bool) = .empty,

    seen_row: std.StringHashMapUnmanaged(u32) = .empty,
    seen_group: std.AutoHashMapUnmanaged(leaf.GroupRecord, u32) = .empty,
    seen_set: std.StringHashMapUnmanaged(u32) = .empty,

    row_span: std.ArrayList(u32) = .empty,
    groupref: std.ArrayList(u32) = .empty,
    group: std.ArrayList(leaf.GroupRecord) = .empty,
    set_span: std.ArrayList(u32) = .empty,
    setsym: std.ArrayList(u32) = .empty,
    odd: std.ArrayList(leaf.OddRecord) = .empty,

    fn deinit(b: *Locker) void {
        b.cells.deinit(b.gpa);
        b.refs.deinit(b.gpa);
        b.taken.deinit(b.gpa);
        b.seen_row.deinit(b.gpa);
        b.seen_group.deinit(b.gpa);
        b.seen_set.deinit(b.gpa);
    }

    /// The terminal half of a state's row: every cell the table filled in.
    fn verdicts(b: *Locker, q: u32, t: press.Tables) Error!void {
        const base = q * b.width;
        for (0..b.width) |i| {
            const a = t.action[base + i];
            if (a.kind == .err) continue;
            try b.cells.append(b.gpa, .{ .col = @intCast(i), .cell = cell(a) });
        }
    }

    /// The nonterminal half: a goto is a read of a symbol that has no column in
    /// the grid, so it gets one out past the end of it.
    ///
    /// Edges arrive sorted by symbol and terminals are numbered below
    /// nonterminals, so the nonterminal ones are a sorted tail and land in
    /// ascending column order behind the terminals already appended.
    fn walk(b: *Locker, st: press.State) Error!void {
        for (st.edges) |e| {
            if (e.symbol < b.terminals) continue;
            try b.cells.append(b.gpa, .{
                .col = b.width + (e.symbol - b.terminals),
                .cell = @bitCast(leaf.Action{ .verb = .shift, .value = @intCast(e.target) }),
            });
        }
    }

    /// The assembled row, interned; the id a state should store.
    fn intern(b: *Locker) Error!u32 {
        const key = std.mem.sliceAsBytes(b.cells.items);
        if (b.seen_row.get(key)) |id| return id;

        b.refs.clearRetainingCapacity();
        b.taken.clearRetainingCapacity();
        try b.taken.appendNTimes(b.gpa, false, b.cells.items.len);
        for (b.cells.items, 0..) |said, i| {
            if (b.taken.items[i]) continue;
            // One group is one value and every column holding it. Those columns
            // are not a run - "reduce 41" is scattered across the row - so this
            // sweeps the tail rather than counting a length. Ascending, because
            // `cells` is.
            const first = b.setsym.items.len;
            for (b.cells.items[i..], b.taken.items[i..]) |other, *claimed| {
                if (other.cell != said.cell) continue;
                claimed.* = true;
                try b.setsym.append(b.out, other.col);
            }
            const set = try b.share(first);
            try b.refs.append(b.gpa, try b.groupOf(.{ .cell = said.cell, .set = set }));
        }

        // Ascending, so two rows with the same groups discovered in a different
        // order are still one row and one comparison finds it.
        std.mem.sort(u32, b.refs.items, {}, std.sort.asc(u32));
        const id: u32 = @intCast(b.row_span.items.len - 1);
        try b.groupref.appendSlice(b.out, b.refs.items);
        try b.row_span.append(b.out, @intCast(b.groupref.items.len));
        try b.seen_row.put(b.gpa, try b.keys.dupe(u8, key), id);
        return id;
    }

    /// The set whose columns were just appended at `first`, interned. A repeat
    /// gives its columns back rather than keeping a second copy.
    fn share(b: *Locker, first: usize) Error!u32 {
        const key = std.mem.sliceAsBytes(b.setsym.items[first..]);
        if (b.seen_set.get(key)) |id| {
            b.setsym.shrinkRetainingCapacity(first);
            return id;
        }
        const id: u32 = @intCast(b.set_span.items.len - 1);
        try b.set_span.append(b.out, @intCast(b.setsym.items.len));
        try b.seen_set.put(b.gpa, try b.keys.dupe(u8, key), id);
        return id;
    }

    fn groupOf(b: *Locker, rec: leaf.GroupRecord) Error!u32 {
        const found = try b.seen_group.getOrPut(b.gpa, rec);
        if (!found.found_existing) {
            found.value_ptr.* = @intCast(b.group.items.len);
            try b.group.append(b.out, rec);
        }
        return found.value_ptr.*;
    }

    /// Every terminal transition this state has that its row does not already
    /// imply, in either direction.
    ///
    /// The row says a terminal reads into a state; that *is* the edge, almost
    /// always, and writing both would be writing the automaton twice. Almost:
    /// precedence deletes reads from states that keep the edge, and unfolding
    /// can leave the two pointing different places. Both sides are recorded
    /// here rather than assumed away, because an edge the table cannot see is
    /// exactly what a reader asking what the automaton *could* have done wants,
    /// and getting it wrong would be silent.
    fn stray(b: *Locker, q: u32, st: press.State, t: press.Tables) Error!void {
        const base = q * b.width;
        var e: usize = 0;
        var col: u32 = 0;
        while (true) {
            while (col < b.terminals and t.action[base + col].kind != .shift) col += 1;
            const read: ?u32 = if (col < b.terminals) col else null;
            const edge: ?u32 = if (e < st.edges.len and st.edges[e].symbol < b.terminals)
                st.edges[e].symbol
            else
                null;
            const symbol = @min(read orelse std.math.maxInt(u32), edge orelse std.math.maxInt(u32));
            if (symbol == std.math.maxInt(u32)) break;

            if (edge == symbol and read == symbol) {
                // The common case by far, and the one that costs nothing: the
                // read and the edge agree, so the row already said it.
                if (st.edges[e].target != t.action[base + col].value) {
                    try b.note(q, symbol, st.edges[e].target);
                }
                e += 1;
                col += 1;
            } else if (edge == symbol) {
                try b.note(q, symbol, st.edges[e].target);
                e += 1;
            } else {
                try b.note(q, symbol, leaf.none);
                col += 1;
            }
        }
    }

    fn note(b: *Locker, q: u32, symbol: u32, target: u32) Error!void {
        try b.odd.append(b.out, .{ .state = q, .symbol = symbol, .target = target });
    }
};

// Five things the press decides are stored as an ordinal, which makes the
// ordinal the file format. Each has a `leaf` twin declared separately on
// purpose - one type is a promise about a file and the other is a verdict - and
// what keeps the two from drifting apart is `concurs`, below: same names, same
// ordinals, checked at comptime. Every conversion in this file goes through it,
// so there is no way to spell one that is not proved.
//
// `Shape` was the fifth and arrived last, because its switch was a named
// function in `impose` rather than an inline prong and so read as a conversion
// somebody had chosen rather than one restating this. What stood in for the
// proof was a round-trip test comparing `@tagName` to `@tagName` with
// `expectEqual` - which on a slice compares the address, so it was really
// asking whether the backend had merged two identical literals. It had, on
// macOS.
comptime {
    concurs(press.Action.Kind, leaf.Action.Verb);
    concurs(press.Conflict.Class, leaf.ConflictClass);
    concurs(press.Conflict.Kind, leaf.ConflictKind);
    concurs(press.Frayed.Harm, leaf.Harm);
    concurs(press.Shape, leaf.ShapeKind);
}

/// Two enums with the same names on the same ordinals.
fn concurs(comptime Press: type, comptime Leaf: type) void {
    const here = std.meta.fields(Press);
    const disk = std.meta.fields(Leaf);
    if (here.len != disk.len) @compileError(@typeName(Press) ++ " and " ++
        @typeName(Leaf) ++ " differ in length; a class the press can produce" ++
        " and the format cannot spell is a class that round-trips as another one." ++
        " Append the missing member - never insert one.");
    for (here, disk) |a, b| {
        if (!std.mem.eql(u8, a.name, b.name) or a.value != b.value) {
            @compileError(@typeName(Press) ++ "." ++ a.name ++ " sits where " ++
                @typeName(Leaf) ++ "." ++ b.name ++ " does. The ordinal is what" ++
                " is on disk, so reordering renames every folio already written.");
        }
    }
}

/// The same case, spelled in the other of two enums proved to concur. Both
/// directions are this one function, because the proof is symmetric and so is
/// the conversion: once `concurs` holds, the ordinal *is* the shared name, and a
/// prong-by-prong `switch` restating that is eight copies of a fact one comptime
/// block already establishes.
pub fn same(comptime To: type, from: anytype) To {
    comptime concurs(@TypeOf(from), To);
    return @enumFromInt(@intFromEnum(from));
}

/// The same, from the raw ordinal a record holds. A folio names its enum columns
/// as `u32`, so the type they mean has to be supplied by the reader; naming it
/// here rather than at each call site is what keeps `concurs` in the path.
pub fn spelt(comptime To: type, comptime Disk: type, ordinal: u32) To {
    return same(To, @as(Disk, @enumFromInt(ordinal)));
}

/// One cell, in the folio's encoding, and the one place the two action
/// spellings meet.
pub fn cell(a: press.Action) u32 {
    return @bitCast(leaf.Action{ .verb = same(leaf.Action.Verb, a.kind), .value = a.value });
}

/// A cell, read back. This used to be a bare `@bitCast` at four call sites in
/// `bind`, sound because a `mirrors` helper there proved the same thing
/// `concurs` does - by hand, over the verbs only, and invoked from *one* of the
/// four functions that depended on it. Which held, but held because all four
/// were compiled together in one file: the proof sat beside the conversion
/// rather than inside it, so nothing stopped a fifth reader elsewhere from
/// bitcasting a cell with no proof at all. Here it cannot be reached without
/// one.
pub fn action(c: u32) press.Action {
    const disk: leaf.Action = @bitCast(c);
    return .{ .kind = same(press.Action.Kind, disk.verb), .value = disk.value };
}

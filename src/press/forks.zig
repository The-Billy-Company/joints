//! Where a parse may legitimately split, read off a finished verdict.
//!
//! Apart from `settle` because it is not part of settling. Every other file in
//! this cluster answers "what should this cell do"; this one answers "what did
//! the cell that already answered leave on the table", and it answers it for a
//! *parse loop* rather than for a report. The two have opposite cost profiles —
//! settling happens once per grammar and may allocate freely, where this is
//! asked on every token of every file and must cost a masked load — so keeping
//! them in one file invites the second to be written like the first.

const std = @import("std");
const settle = @import("settle.zig");

const Action = settle.Action;
const Conflict = settle.Conflict;

/// Where a parse may legitimately split, and into what.
///
/// A contested cell still answers once, because a table has to. But the reading
/// it dropped is not a mistake: it is the other half of an ambiguity the author
/// declared, and it is the whole difference between C's `long total;` being a
/// declaration and being nothing the table can continue from. `Conflict` already
/// records the loser; this is that record turned into something a parse loop can
/// ask on every token without noticing.
///
/// **`declared` and `unwritten` cells are forks; the other two are not.** A
/// `repetition` cell is a list deciding whether it is over, and reading on is
/// what a repeat *means* - the language never saw a choice, so forking there
/// would double the parse on every element of every list to reach a reading
/// nobody wanted. A `residual` cell is a defect: nobody sanctioned that
/// ambiguity, and exploring it would be guessing on the author's behalf a
/// second time, in the other direction.
///
/// An `unwritten` cell forks for the reason a `residual` one does not. The
/// author *did* rank the reading; what nobody wrote is the zero on the other
/// side of the comparison. So an absent precedence gets to order the two - the
/// table still takes the fold, and every grammar's row is the row it was - and
/// does not get to erase the one it ordered second. Go's `&T{}` is the case:
/// `composite_literal` is ranked -1, the fold facing it across `{` is ranked by
/// nobody, and deleting the read on that comparison put five states' worth of
/// `x := &T{}`, `return &T{}`, `var v = &T{}`, `g(&T{})` and `*(&T{})` out of
/// the language.
///
/// Built by the consumer rather than carried in the `Verdict`, because it is an
/// index over a table and not a fact the table was missing. A press that only
/// means to report on a grammar should not pay for it.
pub const Forks = struct {
    /// One bit per cell, so an uncontested cell costs a masked load and never a
    /// search. Contested cells number in the hundreds against a table of
    /// hundreds of thousands, which is exactly the ratio that makes a bitset
    /// over a sorted list beat a second dense table by thirty-two to one on
    /// space and lose nothing on time.
    marked: []const u64,
    /// Cell, and one reading the table dropped there. Sorted by cell, and a
    /// cell that dropped several readings holds several entries — contiguous,
    /// which is what lets `at` hand back all of them as a slice.
    splits: []const Split,
    width: u32,

    pub const Split = struct { cell: u32, other: Action };

    pub fn of(
        gpa: std.mem.Allocator,
        conflicts: []const Conflict,
        states: usize,
        width: u32,
    ) !Forks {
        var splits: std.ArrayList(Split) = .empty;
        errdefer splits.deinit(gpa);
        for (conflicts) |k| {
            if ((k.class != .declared and k.class != .unwritten) or k.other.none()) continue;
            const cell = k.state * width + k.terminal;
            try splits.append(gpa, .{ .cell = cell, .other = k.other });
            // `other` first, always: it is the reading a parse prefers when it
            // explores the cell, and the order these arrive in is the order the
            // strands are born in.
            for (k.rest) |also| try splits.append(gpa, .{ .cell = cell, .other = also });
        }
        // Stable, so the rivals of one cell stay in the order they were offered
        // in. An unstable sort is free to put `rest` ahead of `other`, and which
        // reading a parse tries first is a decision the press already made.
        std.mem.sort(Split, splits.items, {}, before);

        const marked = try gpa.alloc(u64, (states * width + 63) / 64);
        @memset(marked, 0);
        for (splits.items) |s| marked[s.cell >> 6] |= @as(u64, 1) << @truncate(s.cell);
        return .{ .marked = marked, .splits = try splits.toOwnedSlice(gpa), .width = width };
    }

    fn before(_: void, a: Split, b: Split) bool {
        return a.cell < b.cell;
    }

    fn seek(key: u32, s: Split) std.math.Order {
        return std.math.order(key, s.cell);
    }

    pub fn deinit(f: *Forks, gpa: std.mem.Allocator) void {
        gpa.free(f.marked);
        gpa.free(f.splits);
        f.* = undefined;
    }

    /// The readings this cell dropped, when the author declared the cell a
    /// choice. Empty for every other cell, which is nearly all of them, and the
    /// caller pays a masked load to learn so.
    ///
    /// A slice rather than one `Action` because an ambiguity need not be
    /// binary: three readings of a bare identifier complete at once in C++, and
    /// a cell that could name one loser made the third unreachable by any
    /// parse. Nearly every cell that offers anything offers exactly one, so the
    /// slice is length 1 in the common case and costs a bound, not a search.
    pub fn at(f: Forks, state: u32, terminal: u32) []const Split {
        const cell = state * f.width + terminal;
        if (f.marked[cell >> 6] & (@as(u64, 1) << @truncate(cell)) == 0) return &.{};
        const from = std.sort.lowerBound(Split, f.splits, cell, seek);
        var to = from + 1;
        while (to < f.splits.len and f.splits[to].cell == cell) to += 1;
        return f.splits[from..to];
    }

    /// How many readings a parse over this table may be offered. Zero is a
    /// grammar that never forks, which is why a fork must cost json nothing.
    /// Cells with more than one rival count once per rival, because the cost a
    /// caller is sizing against is strands and not addresses.
    pub fn count(f: Forks) usize {
        return f.splits.len;
    }
};

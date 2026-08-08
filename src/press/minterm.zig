//! The parse table's alphabet, cut down to the columns anything can tell apart.
//!
//! **Where this is not.** The obvious reading of "minterm alphabet for the
//! lexer" is the byte line, and that job is already done — by the floor, one
//! layer below where press could reach. `irregex`'s determinizer reduces a
//! finished table in *both* dimensions before it is ever frozen: rows by Moore's
//! refinement, then columns by "two byte classes are indistinguishable when no
//! state routes them differently" (`regex/linear/automata/reduce.zig`), in that
//! order, because merging states is what makes whole columns coincide. So the
//! `class[256]` map a voice arrives with is already the coarsest one its
//! language admits, and a second pass over it in `press/` would be the
//! reimplementation SECTIONS.md §5.3 forbids, computing a partition it is
//! guaranteed to find already computed. Measured, not assumed: the rung reports
//! the narrowing a press-side pass would find, and it is zero.
//!
//! **Where it is.** The parse table has an alphabet too, and nobody has
//! quotiented that one. Its scalars are terminal columns rather than bytes, and
//! the family of sets over that line is the grammar itself: every state, on
//! every distinct action it takes, names the set of terminals it takes that
//! action on. The coarsest partition no such set splits is the alphabet the
//! table actually distinguishes — two columns in one block are two terminals no
//! state anywhere routes differently, so the table could name the block once
//! instead of both columns. That is the same construction `minterm` was lifted
//! out of the regex tier to serve, asked of a different line.
//!
//! Error cells are not interned. A refusal is the absence of a set, so the
//! columns every state refuses fall into the empty label together and come out
//! as one block — which is the right answer and costs nothing to reach.
//!
//! **The ceiling, and what press does at it.** `Space` refuses rather than
//! truncates: past `family_max` distinct action-sets it returns
//! `error.Oversized`. Press does **not** propagate that. A grammar wide enough
//! to exhaust the signature word is a grammar whose columns were mostly
//! distinguishable anyway — the ceiling is reached by having many *different*
//! sets, which is the shape with the least to gain — so `of` falls back to the
//! identity alphabet, where every column is its own block. Pressing succeeds,
//! the table is exactly what it would have been, `narrowed()` reports false, and
//! the rung prints a ratio of 1.00 for that grammar. A size optimization that
//! could refuse to press a grammar would be a worse trade than the bytes are
//! worth.

const std = @import("std");
const minterm = @import("irregex").math.minterm;
const lalr = @import("lalr.zig");

/// The line is the terminal columns. `u16` tops it because a grammar with more
/// than 65,536 terminals does not exist and would fail the folio's own column
/// ceiling first; the family cap is where "pathological, decline it" begins,
/// and 4,096 distinct action-sets is past every pinned grammar.
pub const Space = minterm.Space(u32, std.math.maxInt(u16), 4096);
pub const family_max = Space.sets_max;

/// A partition of the table's columns, dense per column so a consumer indexes
/// rather than searches.
pub const Alphabet = struct {
    gpa: std.mem.Allocator,
    /// `block[c]` — which class column `c` belongs to. Always `columns` long.
    block: []const u32,
    /// How many classes the columns fall into.
    classes: u32,

    pub fn deinit(a: *Alphabet) void {
        a.gpa.free(a.block);
        a.* = undefined;
    }

    pub fn columns(a: Alphabet) u32 {
        return @intCast(a.block.len);
    }

    /// False when the columns were already all distinguishable, or when the
    /// family blew the ceiling and press fell back — see the header.
    pub fn narrowed(a: Alphabet) bool {
        return a.classes < a.block.len;
    }

    /// Columns per class. One when nothing merged; the number the rung prints.
    pub fn ratio(a: Alphabet) f64 {
        if (a.classes == 0) return 1;
        return @as(f64, @floatFromInt(a.block.len)) / @as(f64, @floatFromInt(a.classes));
    }
};

/// The coarsest column alphabet the table admits. Never fails on grammar shape:
/// an over-wide family falls back to the identity partition.
pub fn of(gpa: std.mem.Allocator, t: *const lalr.Tables) std.mem.Allocator.Error!Alphabet {
    const width = t.width;
    if (width == 0 or width > Space.ceiling) return identity(gpa, width);

    var b = Space.Builder.init(gpa);
    defer b.deinit();

    // One pass per state, grouping the row's live cells by what they hold. The
    // row is sparse, so this walks the columns and sorts a handful, not `width`.
    var live: std.ArrayList([2]u32) = .empty; // {cell, column}
    defer live.deinit(gpa);
    var runs: std.ArrayList(Space.Range) = .empty;
    defer runs.deinit(gpa);

    const states = t.action.len / width;
    for (0..states) |s| {
        live.clearRetainingCapacity();
        for (0..width) |c| {
            const cell = t.at(@intCast(s), @intCast(c));
            if (cell.kind == .err) continue;
            try live.append(gpa, .{ @as(u32, @bitCast(cell)), @intCast(c) });
        }
        std.mem.sortUnstable([2]u32, live.items, {}, byCell);

        var i: usize = 0;
        while (i < live.items.len) {
            const cell = live.items[i][0];
            runs.clearRetainingCapacity();
            while (i < live.items.len and live.items[i][0] == cell) : (i += 1) {
                const col = live.items[i][1];
                const last = if (runs.items.len == 0) null else &runs.items[runs.items.len - 1];
                if (last) |r| if (r[1] + 1 == col) {
                    r[1] = col;
                    continue;
                };
                try runs.append(gpa, .{ col, col });
            }
            _ = b.intern(runs.items) catch |e| switch (e) {
                error.Oversized => return identity(gpa, width),
                error.OutOfMemory => return error.OutOfMemory,
            };
        }
    }

    const p = b.finish() catch |e| switch (e) {
        error.Oversized => return identity(gpa, width),
        error.OutOfMemory => return error.OutOfMemory,
    };
    defer p.deinit(gpa);
    return spread(gpa, &p, width);
}

fn byCell(_: void, a: [2]u32, b: [2]u32) bool {
    return a[0] < b[0];
}

/// Lower the partition's atoms onto the columns, renumbering as they are met so
/// the class ids stay dense over the columns that exist — the sweep partitions
/// the whole line, including the stretch above `width` that no column occupies.
fn spread(
    gpa: std.mem.Allocator,
    p: *const Space.Partition,
    width: u32,
) std.mem.Allocator.Error!Alphabet {
    const block = try gpa.alloc(u32, width);
    errdefer gpa.free(block);

    const unmet = std.math.maxInt(u32);
    const seen = try gpa.alloc(u32, @as(usize, p.count) + 1);
    defer gpa.free(seen);
    @memset(seen, unmet);

    var next: u32 = 0;
    for (p.atoms, p.owner) |r, m| {
        if (r[0] >= width) continue;
        if (seen[m] == unmet) {
            seen[m] = next;
            next += 1;
        }
        const hi = @min(r[1], width - 1);
        @memset(block[r[0] .. hi + 1], seen[m]);
    }
    return .{ .gpa = gpa, .block = block, .classes = next };
}

fn identity(gpa: std.mem.Allocator, width: u32) std.mem.Allocator.Error!Alphabet {
    const block = try gpa.alloc(u32, width);
    for (block, 0..) |*b, i| b.* = @intCast(i);
    return .{ .gpa = gpa, .block = block, .classes = width };
}

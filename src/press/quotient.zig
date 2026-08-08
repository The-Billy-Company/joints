//! Which states no parse can tell apart, and the map that says so.
//!
//! LALR merges states that share an LR(0) kernel, and `press.zig` unfolds the
//! places where that merge was wrong. Both of those are questions about
//! *construction*. This is the question from the other end: given the table
//! that came out, which of its states are the same state as far as anything
//! reading the table is concerned?
//!
//! The answer is a bisimulation, and the only interesting decision in the file
//! is what counts as an observation. A parse reading this table can see four
//! things and no more: what verb a cell holds, which production a fold names,
//! where a read goes, and which productions are complete here. Two states
//! agreeing on all four — and, recursively, going to states that agree on all
//! four — are interchangeable: substituting one for the other changes no shift,
//! no reduce, and therefore no node in the tree. So the coarsest partition
//! stable under the transition function, seeded by everything observable that
//! the transition function does not itself carry, is exactly the relation
//! wanted, and `irregex.math.refine` computes it.
//!
//! **What the seeding has to carry, and why getting it wrong is silent.** The
//! transitions carry where a read goes. They do not carry the *verb*: an `err`
//! cell and a `reduce` cell both step nowhere, so a table-only refinement would
//! happily merge a state that folds on `;` with one that refuses it. They do
//! not carry *which* production a fold names, so it would merge two states that
//! reduce different rules on every column — same parse, different tree, and the
//! tree is the whole product. And they do not carry `complete`, which is a
//! per-state list the folio hands to consumers directly rather than through the
//! table. All three are in the colouring below, spelled exactly rather than
//! hashed, because a colour collision here is two states merged that a reader
//! can tell apart and nothing downstream would ever say so.
//!
//! **The dead state is the conservative direction, which is the one wanted.**
//! `refine` treats a missing transition as a step into an implicit sink that
//! agrees with nothing. An action table is sparse — 97% of cells say nothing —
//! so nearly every column of nearly every row is that sink. The effect is that
//! two states are kept apart the moment one has a read on a column the other
//! refuses, which is the right answer: the column patterns *are* the expected
//! sets a parse error is reported against. A treatment that let holes match
//! anything would merge states with different expected sets, which is a smaller
//! table and a worse diagnostic.
//!
//! **Two column families, not one.** The action row is one; the automaton's own
//! edges are the other. They mostly agree — a shift cell says where its terminal
//! goes — but not always, which is the entire reason the folio carries an `odd`
//! section: precedence can delete a read from a state that still has the edge,
//! and unfolding can leave a read whose target is not the edge's. Refining on
//! the cells alone would merge two states whose `odd` records differ, so the
//! edges get columns of their own and the automaton is preserved beside the
//! table.
//!
//! Nothing here rewrites anything. The quotient is *recorded* — that is what
//! `folio.leaf.Kind.quotient` is, "a fact about the table that the table cannot
//! state" — because collapsing the automaton renumbers every state id in the
//! artifact, and the ids are addressed by six other areas. Recording it first
//! makes the relation checkable against the table it describes, which is the
//! order a published size claim has to be built in.

const std = @import("std");
const refine = @import("irregex").math.refine;
const g = @import("copy/grammar.zig");
const lalr = @import("lalr.zig");
const lr0 = @import("cast/lr0.zig");

/// The partition, one block id per state.
///
/// **It lives in the table's arena and has no `deinit`.** The relation is a
/// statement about one `lalr.Tables` and is meaningless beside any other, so
/// tying its lifetime to that arena is the honest ownership — and it is the only
/// one that is safe here. A `Result` is routinely taken apart by hand
/// (`built.tables.deinit(); built.collection.deinit();` is the idiom in four
/// fixtures across three areas), so an allocation reachable only through
/// `Result.deinit` would leak in every one of them, in code no lane owning this
/// file can see.
pub const Quotient = struct {
    /// `block[s]` — which class state `s` fell into. Blocks are numbered by
    /// first appearance in state order, so the numbering is canonical and state
    /// zero is always block zero.
    block: []const u32,
    blocks: u32,
    /// Which engine `refine` actually ran, and how many Moore passes it spent.
    /// Provenance for the bench rung: an automaton deep enough to escalate is a
    /// different shape from one that settles in three passes.
    engine: refine.Engine,
    passes: u32,

    pub fn states(q: Quotient) u32 {
        return @intCast(q.block.len);
    }

    pub fn at(q: Quotient, state: u32) u32 {
        return q.block[state];
    }

    /// How many states the relation says are copies of another. The size claim,
    /// before it is a number of bytes.
    pub fn merged(q: Quotient) u32 {
        return q.states() - q.blocks;
    }
};

/// The action-bisimulation over one pressed automaton.
///
/// `gpa` is scratch and is given back; the answer is in `t`'s arena. Everything
/// this walks is `t`'s and `c`'s already, so a caller holding those two holds
/// everything the result borrows.
pub fn of(
    gpa: std.mem.Allocator,
    gr: *const g.Grammar,
    c: *const lr0.Collection,
    t: *lalr.Tables,
) std.mem.Allocator.Error!Quotient {
    const n: u32 = @intCast(c.states.len);
    const symbols: u32 = t.width + gr.symbolCount();

    const block = try t.arena.allocator().alloc(u32, n);
    if (n == 0) return .{ .block = block, .blocks = 0, .engine = .moore, .passes = 0 };

    const delta = try gpa.alloc(u32, @as(usize, n) * symbols);
    defer gpa.free(delta);
    @memset(delta, refine.nowhere);
    for (c.states, 0..) |st, q| {
        const base = q * symbols;
        for (0..t.width) |col| {
            const a = t.at(@intCast(q), @intCast(col));
            if (a.kind == .shift) delta[base + col] = a.value;
        }
        // The edges, beside the cells rather than instead of them: see the
        // header on why `odd` makes the two families different questions.
        for (st.edges) |e| delta[base + t.width + e.symbol] = e.target;
    }

    const colour = try gpa.alloc(u32, n);
    defer gpa.free(colour);
    try paint(gpa, c, t, colour);

    const got = try refine.refine(gpa, .{
        .states = n,
        .symbols = symbols,
        .delta = delta,
    }, colour, block, .auto);
    return .{
        .block = block,
        .blocks = got.blocks,
        .engine = got.engine,
        .passes = got.passes,
    };
}

/// Seed every state with a dense id for everything a parse can observe that the
/// transitions do not carry: the verb in each cell, the production each fold
/// names, and the completions the folio hands out per state.
///
/// Interned on the exact bytes rather than on a digest of them. A 64-bit hash
/// is the house idiom for a kernel identity and would be fine for a *report*;
/// it is not fine here, because the failure mode is two distinguishable states
/// declared identical, and the claim this file exists to make is that they are
/// not. Distinct signatures are the only thing kept, so the arena holds a few
/// hundred rows rather than one per state.
fn paint(
    gpa: std.mem.Allocator,
    c: *const lr0.Collection,
    t: *const lalr.Tables,
    colour: []u32,
) std.mem.Allocator.Error!void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var seen: std.StringHashMapUnmanaged(u32) = .empty;
    defer seen.deinit(gpa);

    var sig: std.ArrayList(u8) = .empty;
    defer sig.deinit(gpa);

    for (c.states, 0..) |st, q| {
        sig.clearRetainingCapacity();
        for (0..t.width) |col| {
            const a = t.at(@intCast(q), @intCast(col));
            try sig.append(gpa, @intFromEnum(a.kind));
            // A read's target is a transition and belongs in `delta`, where it
            // is compared by block rather than by id; a fold's production is
            // not a state and has nowhere else to be said.
            if (a.kind == .reduce) try sig.appendSlice(gpa, std.mem.asBytes(&@as(u32, a.value)));
        }
        try sig.appendSlice(gpa, std.mem.sliceAsBytes(st.complete));
        const slot = try seen.getOrPut(gpa, sig.items);
        if (!slot.found_existing) {
            slot.key_ptr.* = try arena.allocator().dupe(u8, sig.items);
            slot.value_ptr.* = seen.count() - 1;
        }
        colour[q] = slot.value_ptr.*;
    }
}

// ── the folio section ──
//
// `leaf.Kind.quotient` is byte-opaque, so this is the only place its interior
// is written down. The whole of it:
//
//     0 .. 4    tag, `QTNT`
//     4 .. 8    blocks
//     8 .. 12   states
//     12        width, the bytes one block id is written at: 1, 2, or 4
//     13 .. 16  zero
//     16 ..     `states` block ids, little-endian, `width` bytes each
//
// A class map is the one thing in the section, and it is `states` numbers whose
// range is known before the first is written, so it is stored at the width that
// range needs and nothing else is stored at all. Everything the reader needs to
// disbelieve it — that the state count is the automaton's, that no id names a
// block past the end, that the length is exactly what the header implies — is
// derivable from those three words, which is what makes `classes` total.

/// What a block map claims to be. Bumped for any layout change here, so a
/// section written before one is refused rather than read as its replacement.
const tag: u32 = 0x544e_5451; // "QTNT"

const head_len = 16;

/// The narrowest width that names every block. One byte covers every grammar in
/// the corpus, and the section is a fifth the size of the `row` table it
/// describes because of it.
fn widthFor(blocks: u32) u8 {
    return if (blocks <= 1 << 8) 1 else if (blocks <= 1 << 16) 2 else 4;
}

pub fn size(states: u32, blocks: u32) usize {
    return head_len + @as(usize, states) * widthFor(blocks);
}

/// The section's bytes. Free with `gpa.free`.
pub fn encode(gpa: std.mem.Allocator, q: Quotient) std.mem.Allocator.Error![]u8 {
    const w = widthFor(q.blocks);
    const out = try gpa.alloc(u8, size(q.states(), q.blocks));
    @memset(out, 0);
    std.mem.writeInt(u32, out[0..4], tag, .little);
    std.mem.writeInt(u32, out[4..8], q.blocks, .little);
    std.mem.writeInt(u32, out[8..12], q.states(), .little);
    out[12] = w;
    for (q.block, 0..) |b, i| put(out[head_len + i * w ..], w, b);
    return out;
}

fn put(at: []u8, w: u8, v: u32) void {
    switch (w) {
        1 => at[0] = @intCast(v),
        2 => std.mem.writeInt(u16, at[0..2], @intCast(v), .little),
        else => std.mem.writeInt(u32, at[0..4], v, .little),
    }
}

/// The class map, read where it lies. Null for a section this binary does not
/// fully recognize, which the folio turns into a refusal — the map is small and
/// entirely derivable, so there is no half-reading it.
pub const Classes = struct {
    raw: []const u8,
    width: u8,
    blocks: u32,

    pub fn states(x: Classes) u32 {
        return @intCast(x.raw.len / x.width);
    }

    pub fn at(x: Classes, state: u32) u32 {
        const off = @as(usize, state) * x.width;
        return switch (x.width) {
            1 => x.raw[off],
            2 => std.mem.readInt(u16, x.raw[off..][0..2], .little),
            else => std.mem.readInt(u32, x.raw[off..][0..4], .little),
        };
    }

    pub fn merged(x: Classes) u32 {
        return x.states() - x.blocks;
    }
};

/// Read a `quotient` section against the automaton it claims to describe.
///
/// Total: every way the bytes can fail to be a class map for `states` states is
/// `null`, including being empty. A folio may legitimately carry none — the
/// relation is a pure function of the table, so a binary that wants it and does
/// not find it can compute it — but a folio carrying one that does not fit is a
/// file written by something this binary cannot account for, and `collate`
/// refuses it there rather than answering around it.
pub fn classes(bytes: []const u8, states: u32) ?Classes {
    if (bytes.len < head_len) return null;
    if (std.mem.readInt(u32, bytes[0..4], .little) != tag) return null;
    const blocks = std.mem.readInt(u32, bytes[4..8], .little);
    const said = std.mem.readInt(u32, bytes[8..12], .little);
    const w = bytes[12];
    if (said != states or blocks == 0 or blocks > states) return null;
    if (w != widthFor(blocks)) return null;
    if (bytes.len != size(states, blocks)) return null;
    if (!std.mem.allEqual(u8, bytes[13..head_len], 0)) return null;

    const out: Classes = .{ .raw = bytes[head_len..], .width = w, .blocks = blocks };
    // Every id names a block, and every block is named. The second half is what
    // makes the map a partition rather than a labelling: `refine` numbers by
    // first appearance, so a gap is a map that did not come from one.
    var reached: u32 = 0;
    for (0..states) |s| {
        const b = out.at(@intCast(s));
        if (b > reached) return null;
        if (b == reached) reached += 1;
    }
    if (reached != blocks) return null;
    return out;
}

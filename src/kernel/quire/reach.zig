//! The neighbourhood: what a query matcher asks a tree, and what `children`
//! alone could not answer.
//!
//! These are `Quire` methods; they live here because they are one concern and
//! `quire.zig` already holds four others. `Quire` aliases each one, so a caller
//! writes `q.nextSibling(ref)` and never names this file.
//!
//! Two rules run through every accessor below and both of them are where a
//! plausible guess goes wrong.
//!
//! **The top of the tree is a run, not a node.** `root` is null unless the
//! parse left exactly one, because a parse that stopped early hands back the
//! forest of everything it completed and this package refuses to crown a fake
//! `program` over it (see `README.md`). So the roots are a sibling run like any
//! other: `nextSibling` of a root is the next root, `parent` of a root is
//! absence, and `depth` of every root is zero.
//!
//! **An extra is a child that does not count structurally.** It is in the tree,
//! it has a name, and a `(comment)` pattern matches it - so the plain and named
//! sibling walks both step onto one, exactly as tree-sitter's do: its relevance
//! test is visible-and-named, and a comment is both. The one place an extra is
//! skipped is the field map, and it is skipped there by `gather` rather than
//! here - a spliced extra is refused the step's field on the way in, so
//! `childByFieldName` can never answer with one.

const std = @import("std");

const quire = @import("quire.zig");
const Quire = quire.Quire;
const Ref = quire.Ref;
const none = quire.none;

/// Whoever holds this node, or absence for a root.
pub fn parent(q: *const Quire, ref: Ref) ?Ref {
    const p = q.nodes[ref].parent;
    return if (p == none) null else p;
}

/// The run this node sits in, left to right: its parent's children, or the
/// root list. The forest rule above, made askable rather than inferable -
/// `children(parent(ref).?)` has no answer for a root and this does.
pub fn among(q: *const Quire, ref: Ref) []const Ref {
    const p = q.nodes[ref].parent;
    return if (p == none) q.roots else q.children(p);
}

/// The next node in the run holding this one, extras included.
pub fn nextSibling(q: *const Quire, ref: Ref) ?Ref {
    const run = q.among(ref);
    const at = std.mem.indexOfScalar(Ref, run, ref) orelse return null;
    return if (at + 1 < run.len) run[at + 1] else null;
}

pub fn prevSibling(q: *const Quire, ref: Ref) ?Ref {
    const run = q.among(ref);
    const at = std.mem.indexOfScalar(Ref, run, ref) orelse return null;
    return if (at > 0) run[at - 1] else null;
}

/// The next node in the run that a query could match by name.
///
/// A `comment` is one of those, and being an extra does not exempt it. That is
/// tree-sitter's answer and not a convenience: the C API's named walk tests
/// visibility and namedness, both of which a comment has, so a pattern written
/// against `next_named_sibling` in any of the corpus's query files was written
/// knowing comments arrive.
pub fn nextNamedSibling(q: *const Quire, ref: Ref) ?Ref {
    const run = q.among(ref);
    const at = std.mem.indexOfScalar(Ref, run, ref) orelse return null;
    for (run[at + 1 ..]) |c| if (q.isNamed(c)) return c;
    return null;
}

pub fn prevNamedSibling(q: *const Quire, ref: Ref) ?Ref {
    const run = q.among(ref);
    var at = std.mem.indexOfScalar(Ref, run, ref) orelse return null;
    while (at > 0) {
        at -= 1;
        if (q.isNamed(run[at])) return run[at];
    }
    return null;
}

/// The child this node files under `name`, or absence.
///
/// The first such child, because a production can file two steps under one
/// name and tree-sitter's own lookup answers with the first. An extra can
/// never be the answer: see the header.
pub fn childByFieldName(q: *const Quire, ref: Ref, want: []const u8) ?Ref {
    for (q.children(ref)) |c| {
        const f = q.nodes[c].field;
        if (f != none and std.mem.eql(u8, q.gr.field_names[f], want)) return c;
    }
    return null;
}

/// Where a sibling run stops being worth scanning and starts being worth
/// bisecting. See `sunk`.
const bisect_over = 48;

/// The deepest node whose span covers `[from, to)`, or absence when no root
/// does.
///
/// This is what an editor asks on every frame: highlight the viewport, not the
/// file. Null rather than a whole-file node is the forest rule again - a range
/// inside a stretch a mend walked past is covered by nothing, and saying so is
/// the answer, where tree-sitter's single root would claim it.
///
/// A bisection per level once a run is wide enough to pay for one, which the
/// sibling runs earn by being sorted and disjoint. That is the one invariant
/// this accessor needs and does not check: `survey`'s `order` treats it as
/// checkable rather than given, so on a tree `survey` would call disordered
/// this may answer absence where a scan would have found a node. Every other
/// accessor here is total, and the trade is worth naming - a twenty-thousand
/// wide parent is fifteen compares rather than ten thousand, which is the
/// difference between highlighting a screen and stalling on one.
///
/// An empty range on a boundary is covered by the node ending there *and* the
/// one starting there, and this answers with the first in source order. It is
/// the only case where several siblings cover one range at all: for
/// `from < to` disjointness makes the answer unique.
pub fn descendantForByteRange(q: *const Quire, from: u32, to: u32) ?Ref {
    var found: ?Ref = null;
    var run = q.roots;
    while (sunk(q, run, from, to)) |ref| {
        found = ref;
        run = q.children(ref);
    }
    return found;
}

/// The first node of one sibling run covering `[from, to)`.
///
/// A scan below `bisect_over` and a bisection above it, and the threshold is
/// measured rather than chosen: a real file's widest parent is a few dozen
/// children, where an unpredictable branch per halving costs more than walking
/// the whole run, and `bench/rungs/cursor` had the descent 1.4x slower than the
/// naive walk on every corpus file until this line existed.
fn sunk(q: *const Quire, run: []const Ref, from: u32, to: u32) ?Ref {
    if (run.len <= bisect_over) {
        for (run) |c| if (covers(q, c, from, to)) return c;
        return null;
    }
    // Sorted by start, so the last run entry starting at or before `from` is
    // the only one that can cover a non-empty range; the walk back is the
    // boundary case in the header, and it steps at most as far as there are
    // nodes ending exactly where `from` is.
    var lo: usize = 0;
    var hi: usize = run.len;
    while (hi - lo > 1) {
        const mid = lo + (hi - lo) / 2;
        if (q.nodes[run[mid]].start <= from) lo = mid else hi = mid;
    }
    if (!covers(q, run[lo], from, to)) return null;
    while (lo > 0 and covers(q, run[lo - 1], from, to)) lo -= 1;
    return run[lo];
}

fn covers(q: *const Quire, ref: Ref, from: u32, to: u32) bool {
    const n = q.nodes[ref];
    return n.start <= from and to <= n.end();
}

/// Parent hops to a root, so every root is zero.
///
/// A climb, and there is no other answer a pointer tree can give - which is the
/// half of the vellum trade worth knowing before choosing a representation:
/// `vellum.Sheet.depth` reads this off the excess walk and is nine times faster
/// on a large file, where its `parent` is twenty-nine times slower.
/// `bench/rungs/cursor` prints both.
pub fn depth(q: *const Quire, ref: Ref) u32 {
    var d: u32 = 0;
    var at = q.nodes[ref].parent;
    while (at != none) : (at = q.nodes[at].parent) d += 1;
    return d;
}

/// Nodes under this one, counting it.
///
/// Takes an allocator because it is a walk and the depth of a real file is not
/// bounded - a thousand-deep nest of `[` in one json document is a fixture
/// here, not a pathology - so the frontier cannot be a fixed array for the same
/// reason `settle`'s and `survey`'s cannot. It starts on the call stack and
/// spills, which is what keeps the ordinary answer - most nodes are leaves and
/// most subtrees are tiny - from paying for the pathological one; the rung had
/// this 1.8x slower than the same walk with a caller-held buffer while every
/// call went to the heap.
///
/// That the answer is a walk at all is the whole of what
/// `vellum.Sheet.subtreeSize` buys back: one `findClose` and a subtraction, no
/// allocation, and no dependence on how large the answer is.
pub fn subtreeSize(q: *const Quire, gpa: std.mem.Allocator, ref: Ref) !u32 {
    var fallback = std.heap.stackFallback(64 * @sizeOf(Ref), gpa);
    const arena = fallback.get();
    var stack: std.ArrayList(Ref) = .empty;
    defer stack.deinit(arena);
    try stack.append(arena, ref);
    var n: u32 = 0;
    while (stack.pop()) |at| {
        n += 1;
        for (q.children(at)) |c| try stack.append(arena, c);
    }
    return n;
}

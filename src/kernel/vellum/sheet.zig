//! The sheet: a quire settled into parentheses.
//!
//! A tree written depth-first as `(` and `)` is 2n bits, and every question
//! about the tree is then a question about that word's excess walk. Measured,
//! the shape of a settled tree costs under three bits a node here against the
//! sixteen bytes the quire spends on `kids_at`, `kids_len`, `parent`, and the
//! entry in the flat `kids` array - and `subtreeSize` and `depth` go from a
//! walk to arithmetic on the way past. The mechanism is Sadakane & Navarro's
//! range min-max tree, which lives in `irregex.math.succinct.parens`; nothing
//! of it is re-rolled here.
//!
//! Under three and not two: `2n + o(n)` is asymptotic in the *block size*, and
//! the min-max tree over 512-bit blocks is a constant fraction of the word
//! rather than a vanishing one. `bench/rungs/vellum/` measures it at 2.82 bits
//! a node over 188k nodes and the README quotes that rather than the theorem.
//!
//! **A node is the bit position of its own `(`.** That is the handle, not the
//! preorder index, and the choice is the difference between a fast sheet and a
//! slow one: `preorder(spot)` is `rank1`, which is O(1), where recovering the
//! spot from a preorder index is `select1`, which is a binary search. Every
//! payload lookup goes through the cheap direction.
//!
//! **What the shape cannot say still costs what it costs.** A node's kind,
//! span, and field are facts about the grammar and the file, not about the
//! tree, so they sit in `Ink` beside the word and the sheet is *not* two bits
//! a node end to end. `README.md` reports both halves; a claim that quoted only
//! the shape would be measuring the part that was already free.
//!
//! Static, which is the honest half of the trade. Every query reads immutable
//! storage and an edit rebuilds, so this is the form of a file at rest -
//! mmap-able, shareable, the thing a query engine wants. `word.zig` is the half
//! that survives a keystroke.

const std = @import("std");
const parens = @import("irregex").math.succinct.parens;
const press = @import("../../press/press.zig");
const quire = @import("../quire/quire.zig");

/// A node's handle: the bit position of its own `(`.
pub const Spot = u32;

/// Everything about a node that is not its position in the tree, in preorder.
///
/// Four words rather than the quire's seven, because three of the quire's are
/// the shape: `parent` is `enclose`, and `kids_at`/`kids_len` are `firstChild`
/// and `nextSibling`. Nothing was compressed to get there - those three fields
/// simply stopped being stored.
pub const Ink = struct {
    kind: quire.Kind,
    start: u32,
    len: u32,
    /// A `Grammar.field_names` index, or `quire.none`.
    field: u32,
};

pub const Error = error{
    /// The arena handed in is not a tree: a ref past the end, a child run past
    /// the end of `kids`, or more nodes emitted than the arena holds - which is
    /// what a cycle looks like from inside the walk, and what stops it running
    /// forever. `Quire.survey` is the full diagnosis; this is the refusal.
    NotATree,
    /// More nodes than a parenthesis word can address. The static structure
    /// takes an `i32` bit count, so the ceiling is about a billion nodes; a
    /// quire that large is a different problem than this one.
    Oversized,
};

/// A settled tree: the word, its range min-max index, and the payload.
pub const Sheet = struct {
    gpa: std.mem.Allocator,
    /// Borrowed, exactly as the quire borrows it. Names live in the grammar and
    /// nowhere else, so a settled tree is still keyed on the one spelling of
    /// `binary_expression` the press interned.
    gr: *const press.Grammar,
    shape: parens.Parens,
    ink: []const Ink,

    pub fn deinit(s: *Sheet) void {
        s.shape.deinit(s.gpa);
        s.gpa.free(s.ink);
        s.* = undefined;
    }

    pub fn count(s: *const Sheet) u32 {
        return @intCast(s.ink.len);
    }

    /// The whole sheet, and the shape alone. Two numbers because the trade is
    /// two-sided: the shape is what the succinct encoding replaced, and the ink
    /// is what it left exactly where it was.
    pub fn sizeBytes(s: *const Sheet) usize {
        return s.shape.sizeBytes() + s.ink.len * @sizeOf(Ink);
    }

    pub fn shapeBytes(s: *const Sheet) usize {
        return s.shape.sizeBytes();
    }

    // ── the tree ────────────────────────────────────────────────────────────

    /// The first root. The rest are its siblings, so a forest needs no second
    /// entry point.
    pub fn root(s: *const Sheet) ?Spot {
        return if (s.shape.bitLen() == 0) null else 0;
    }

    pub fn parent(s: *const Sheet, spot: Spot) ?Spot {
        return cast(s.shape.enclose(spot));
    }

    pub fn firstChild(s: *const Sheet, spot: Spot) ?Spot {
        return cast(s.shape.firstChild(spot));
    }

    pub fn lastChild(s: *const Sheet, spot: Spot) ?Spot {
        return cast(s.shape.lastChild(spot));
    }

    pub fn nextSibling(s: *const Sheet, spot: Spot) ?Spot {
        return cast(s.shape.nextSibling(spot));
    }

    pub fn prevSibling(s: *const Sheet, spot: Spot) ?Spot {
        return cast(s.shape.prevSibling(spot));
    }

    /// Nodes under `spot`, counting it. One `findClose` and a subtraction,
    /// where the quire has to walk the subtree.
    pub fn subtreeSize(s: *const Sheet, spot: Spot) u32 {
        return @intCast(s.shape.subtreeSize(spot));
    }

    /// Parent hops to a root, so a root is zero. The structure counts excess,
    /// where a root sits at one; the offset is here rather than at every call
    /// site because the question anybody asks is how far down this is.
    pub fn depth(s: *const Sheet, spot: Spot) u32 {
        return @intCast(s.shape.depth(spot) - 1);
    }

    pub fn preorder(s: *const Sheet, spot: Spot) u32 {
        return @intCast(s.shape.preorder(spot));
    }

    /// The inverse, and the slow direction: a binary search over the rank
    /// samples. Here because settling hands out preorder indices and something
    /// has to turn one back into a handle, not because a walk should use it.
    pub fn spotOf(s: *const Sheet, order: u32) ?Spot {
        return cast(s.shape.nodeAt(order));
    }

    pub fn isAncestor(s: *const Sheet, a: Spot, b: Spot) bool {
        return s.shape.isAncestor(a, b);
    }

    /// Deepest node holding both, or null when they sit in different trees of
    /// the forest. Neither the quire nor tree-sitter answers this without a
    /// walk; here it is one range-min query.
    pub fn lca(s: *const Sheet, a: Spot, b: Spot) ?Spot {
        return cast(s.shape.lca(a, b));
    }

    /// The children of `spot`, left to right.
    pub fn kids(s: *const Sheet, spot: Spot) Kids {
        return .{ .s = s, .cursor = s.firstChild(spot) };
    }

    pub const Kids = struct {
        s: *const Sheet,
        cursor: ?Spot,

        pub fn next(k: *Kids) ?Spot {
            const spot = k.cursor orelse return null;
            k.cursor = k.s.nextSibling(spot);
            return spot;
        }
    };

    // ── what the shape cannot say ───────────────────────────────────────────

    pub fn at(s: *const Sheet, spot: Spot) Ink {
        return s.ink[s.preorder(spot)];
    }

    /// What this node is called - the grammar's own spelling, from whichever of
    /// the two places it came from.
    ///
    /// The second spelling of `Quire.name` in this package, and it should be
    /// the last: the mapping is a fact about a `Kind` and a grammar, not about
    /// whichever tree is holding it. See the follow-up in `README.md` for the
    /// three free functions in `quire` that would collapse both.
    pub fn name(s: *const Sheet, spot: Spot) []const u8 {
        const k = s.at(spot).kind;
        return if (k.renamed) s.gr.aliases[k.index].name else s.gr.nameOf(k.index);
    }

    pub fn isNamed(s: *const Sheet, spot: Spot) bool {
        const k = s.at(spot).kind;
        return if (k.renamed) s.gr.aliases[k.index].named else s.gr.shapeOf(k.index) == .named;
    }

    pub fn isExtra(s: *const Sheet, spot: Spot) bool {
        return s.at(spot).kind.extra;
    }

    pub fn field(s: *const Sheet, spot: Spot) ?[]const u8 {
        const f = s.at(spot).field;
        return if (f == quire.none) null else s.gr.field_names[f];
    }

    pub fn start(s: *const Sheet, spot: Spot) u32 {
        return s.at(spot).start;
    }

    pub fn end(s: *const Sheet, spot: Spot) u32 {
        const i = s.at(spot);
        return i.start + i.len;
    }

    fn cast(spot: ?usize) ?Spot {
        return if (spot) |v| @intCast(v) else null;
    }
};

/// Where the walk stands: a node and how many of its children have been
/// written. An explicit stack rather than recursion, because a maximally-deep
/// left spine is a real shape - a thousand-deep nest of `[` in one json file
/// is a fixture, not a pathology - and a settle that overflows on it is a
/// settle that cannot be trusted on the corpus.
const Frame = struct { ref: quire.Ref, kid: u32 };

/// Settle a live quire into a sheet: one depth-first pass, `(` down and `)` up.
///
/// The forest settles as a forest. A parse that stopped early hands back
/// several roots and the word simply returns to excess zero between them, which
/// is what the parenthesis encoding already means by an ordinal *forest*; there
/// is no synthetic crown here for the same reason there is none in the quire.
pub fn settle(gpa: std.mem.Allocator, q: *const quire.Quire) !Sheet {
    if (q.nodes.len > std.math.maxInt(i32) / 2) return Error.Oversized;

    var word = try parens.Parens.Builder.init(gpa, @max(2, 2 * q.nodes.len));
    errdefer word.deinit(gpa);
    var ink: std.ArrayList(Ink) = .empty;
    errdefer ink.deinit(gpa);
    try ink.ensureTotalCapacity(gpa, q.nodes.len);
    var stack: std.ArrayList(Frame) = .empty;
    defer stack.deinit(gpa);

    var next_root: usize = 0;
    while (true) {
        if (stack.items.len == 0) {
            if (next_root == q.roots.len) break;
            const r = q.roots[next_root];
            next_root += 1;
            try enter(gpa, q, r, &word, &ink, &stack);
            continue;
        }
        const top = stack.items.len - 1;
        const held = stack.items[top];
        const n = q.nodes[held.ref];
        if (held.kid == n.kids_len) {
            try word.close();
            _ = stack.pop();
            continue;
        }
        // Read the child out and bump the counter BEFORE descending: `enter`
        // appends to the same list, so a pointer into it does not survive.
        stack.items[top].kid += 1;
        try enter(gpa, q, q.kids[n.kids_at + held.kid], &word, &ink, &stack);
    }

    var shape = try word.seal(gpa);
    errdefer shape.deinit(gpa);
    return .{ .gpa = gpa, .gr = q.gr, .shape = shape, .ink = try ink.toOwnedSlice(gpa) };
}

fn enter(
    gpa: std.mem.Allocator,
    q: *const quire.Quire,
    ref: quire.Ref,
    word: *parens.Parens.Builder,
    ink: *std.ArrayList(Ink),
    stack: *std.ArrayList(Frame),
) !void {
    if (ref >= q.nodes.len) return Error.NotATree;
    const n = q.nodes[ref];
    if (n.kids_at + n.kids_len > q.kids.len) return Error.NotATree;
    // The termination guard. A well-formed arena reaches each node once, so
    // writing an (n+1)th open means the walk is going round.
    if (ink.items.len == q.nodes.len) return Error.NotATree;
    word.open();
    ink.appendAssumeCapacity(.{
        .kind = n.kind,
        .start = n.start,
        .len = n.len,
        .field = n.field,
    });
    try stack.append(gpa, .{ .ref = ref, .kid = 0 });
}

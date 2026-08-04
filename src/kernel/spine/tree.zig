//! The spine as a file sees it: leaves in byte order, and an edit stated the
//! way an editor states one.
//!
//! Because the product is associative, re-bracketing is free, so replacing one
//! leaf invalidates only the branches directly above it. Every other product in
//! the file is still true, whatever the edit was and wherever it landed. That
//! is the whole of property 1 in `research/joinery/CLAIM.md`, and it is the
//! thing tree-sitter structurally cannot do: an LR state has to be recomputed
//! when its predecessor moves, where a function need not.
//!
//! What is here is the addressing - which leaf a byte is in, which leaves a cut
//! disturbed, what has to be re-derived - plus the four entry points that use
//! it. The nodes, their annotations, and the rotations live next door in
//! `arbor.zig`, which knows nothing about bytes.

const std = @import("std");
const arbor = @import("arbor.zig");

pub const Id = arbor.Id;

/// The spine over one monoid. `M` declares:
///
///   - `Element: type` - what a segment does.
///   - `Ctx: type` - everything an element is read against; `void` when there
///     is nothing. The joint's is an `Arena` of interning pools plus the goto
///     graph, which is why this is a parameter and not an assumption.
///   - `identity: Element` - doing nothing.
///   - `compose(Ctx, Element, Element) !?Element` - `a` and then `b`, or null
///     when the pairing is refused.
///   - `eql(Element, Element) bool` - optional; structural equality otherwise.
pub fn Tree(comptime M: type) type {
    comptime {
        for ([_][]const u8{ "Element", "Ctx", "identity", "compose" }) |need| {
            if (!@hasDecl(M, need)) @compileError(
                @typeName(M) ++ " is not a monoid here: it needs a `" ++ need ++ "`",
            );
        }
    }
    return struct {
        const Self = @This();
        const Wood = arbor.Arbor(M);

        pub const Element = M.Element;
        pub const Ctx = M.Ctx;
        pub const Leaf = Wood.Leaf;
        pub const same = Wood.same;

        /// An edit as the editor states it: the byte range that went away, and
        /// how many bytes replaced it.
        pub const Cut = struct { from: u32, to: u32, insert: u32 };

        /// What a cut disturbed. `first .. last` are the leaves that have to be
        /// re-derived, and `from .. to` is the byte range they cover *after*
        /// the edit - which is what a minter has to produce, not the cut
        /// itself, because a keystroke inside a segment invalidates the whole
        /// segment.
        pub const Span = struct { first: u32, last: u32, from: u32, to: u32 };

        wood: Wood,
        root: Id,

        pub fn init(gpa: std.mem.Allocator) Self {
            return .{ .wood = Wood.init(gpa), .root = .none };
        }

        pub fn deinit(s: *Self) void {
            s.wood.deinit();
            s.* = undefined;
        }

        /// The product of the whole file, or null when some pairing in it was
        /// refused. An empty spine is the identity, which is the only answer
        /// that keeps `build(&.{})` composable with anything.
        pub fn product(s: *const Self) ?Element {
            return if (s.root == .none) M.identity else s.wood.get(s.root).value;
        }

        pub fn len(s: *const Self) u32 {
            return s.wood.leavesOf(s.root);
        }

        pub fn bytes(s: *const Self) u32 {
            return s.wood.bytesOf(s.root);
        }

        /// How tall the tree is. The number `splice` costs, so a measurement
        /// that wants the claim as a number reads it from here.
        pub fn height(s: *const Self) u32 {
            return s.wood.heightOf(s.root);
        }

        pub fn at(s: *const Self, i: u32) Leaf {
            std.debug.assert(i < s.len());
            var id = s.root;
            var k = i;
            while (true) {
                const n = s.wood.get(id);
                if (n.left == .none) return .{ .bytes = n.bytes, .element = n.value.? };
                const wide = s.wood.leavesOf(n.left);
                if (k < wide) {
                    id = n.left;
                } else {
                    k -= wide;
                    id = n.right;
                }
            }
        }

        /// Where leaf `i` begins. `i == len()` answers the end of the file, so
        /// a caller walking segment boundaries does not need a special last
        /// step.
        pub fn offset(s: *const Self, i: u32) u32 {
            std.debug.assert(i <= s.len());
            var id = s.root;
            var k = i;
            var b: u32 = 0;
            while (id != .none) {
                const n = s.wood.get(id);
                if (n.left == .none) {
                    if (k == 1) b += n.bytes;
                    break;
                }
                const wide = s.wood.leavesOf(n.left);
                if (k < wide) {
                    id = n.left;
                } else {
                    k -= wide;
                    b += s.wood.bytesOf(n.left);
                    id = n.right;
                }
            }
            return b;
        }

        /// The product of the leaves `from .. to`, read without disturbing
        /// anything.
        ///
        /// The whole-file product is one field read; any other range is this,
        /// and it is the reason a re-mint policy can afford to ask an algebraic
        /// question per candidate split. Folding a suffix costs one composition
        /// per leaf, which is the linear cost the spine exists to avoid; the
        /// descent pays `log n` and stops at every node the range already
        /// covers whole. Null when some pairing inside the range was refused,
        /// exactly as `product` is.
        pub fn between(s: *const Self, x: Ctx, from: u32, to: u32) !?Element {
            std.debug.assert(from <= to and to <= s.len());
            if (from == to) return M.identity;
            return s.gather(x, s.root, 0, s.wood.leavesOf(s.root), from, to);
        }

        fn gather(s: *const Self, x: Ctx, id: Id, lo: u32, hi: u32, from: u32, to: u32) !?Element {
            if (id == .none or to <= lo or hi <= from) return M.identity;
            const n = s.wood.get(id);
            if (from <= lo and hi <= to) return n.value;
            const wide = s.wood.leavesOf(n.left);
            const a = try s.gather(x, n.left, lo, lo + wide, from, to) orelse return null;
            const b = try s.gather(x, n.right, lo + wide, hi, from, to) orelse return null;
            return try M.compose(x, a, b);
        }

        /// Which leaves a cut disturbed, and the bytes the replacements must
        /// cover.
        ///
        /// A leaf is disturbed when its span and the cut genuinely overlap, so
        /// a pure insertion sitting exactly on a segment boundary disturbs
        /// nothing and just puts new leaves between two untouched ones. Typing
        /// inside a segment disturbs that one segment. Both fall out of the
        /// same predicate rather than being special cases, which matters
        /// because the boundary case is the one an editor hits every time you
        /// press Enter.
        pub fn touched(s: *const Self, cut: Cut) Span {
            std.debug.assert(cut.from <= cut.to and cut.to <= s.bytes());
            const opened = s.upto(cut.from, .ended);
            const closed = s.upto(cut.to, .begun);
            const first = opened[0];
            const last = @max(closed[0], first);
            const stop = s.offset(last);
            return .{
                .first = first,
                .last = last,
                .from = opened[1],
                .to = (stop - cut.to) + cut.from + cut.insert,
            };
        }

        /// Replace everything. The only bulk entry point, and it costs one
        /// composition per node rather than per pair of leaves.
        pub fn build(s: *Self, x: Ctx, ls: []const Leaf) !?Element {
            s.wood.drop(s.root);
            s.root = try s.wood.bulk(x, ls);
            return s.product();
        }

        /// Swap one leaf and re-multiply the branches above it. The claim, and
        /// the cheapest thing here: exactly `height` compositions, no
        /// rebalancing, no allocation, because the leaf count did not move.
        pub fn splice(s: *Self, x: Ctx, i: u32, l: Leaf) !?Element {
            std.debug.assert(i < s.len() and l.bytes > 0);
            try s.wood.sink(x, s.root, i, l);
            return s.product();
        }

        /// Replace the leaves `from .. to` with `fresh`, which may be a
        /// different number of them or none.
        pub fn replace(s: *Self, x: Ctx, from: u32, to: u32, fresh: []const Leaf) !?Element {
            std.debug.assert(from <= to and to <= s.len());
            // One leaf for one leaf is the keystroke, which is most of what an
            // editor ever asks for, and it is the same answer by a much shorter
            // route: no split, no join, no node churn. `verify` proves the two
            // paths agree.
            if (to - from == 1 and fresh.len == 1) return s.splice(x, from, fresh[0]);

            const a, const rest = try s.wood.split(x, s.root, from);
            const mid, const b = try s.wood.split(x, rest, to - from);
            s.wood.drop(mid);
            const grown = try s.wood.bulk(x, fresh);
            s.root = try s.wood.join(x, try s.wood.join(x, a, grown), b);
            return s.product();
        }

        /// An edit in the editor's own terms. `minter` is anything with
        /// `mint(from: u32, to: u32) ![]const Leaf` returning the segments that
        /// now cover `from .. to`; the slice is copied before anything else
        /// touches the tree, so returning a borrowed scratch buffer is fine -
        /// which is deliberate, because that is exactly the shape `Cursor.run`
        /// already hands back.
        ///
        /// The tree does not segment. It cannot: where a segment ends is a fact
        /// about tokens, and the only thing that knows is whatever is driving
        /// the cursor. So the tree says which byte range went stale and the
        /// caller says what is in it.
        pub fn edit(s: *Self, x: Ctx, cut: Cut, minter: anytype) !?Element {
            const span = s.touched(cut);
            const fresh = try minter.mint(span.from, span.to);
            var covered: u32 = 0;
            for (fresh) |l| covered += l.bytes;
            if (covered != span.to - span.from) return error.MintDoesNotCover;
            return s.replace(x, span.first, span.last, fresh);
        }

        /// Re-derive every product bottom-up and check the tree against itself.
        /// `O(n)` compositions, so it is a test and debug instrument rather
        /// than something a parse runs - but it is the only thing that can
        /// prove a rebalance carried its annotations, since a rotation that
        /// drops one leaves a tree that still looks perfectly well-formed.
        pub fn verify(s: *const Self, x: Ctx) !void {
            _ = try s.audit(x, s.root);
        }

        const Facts = struct { height: u32, leaves: u32, bytes: u32, value: ?Element };

        fn audit(s: *const Self, x: Ctx, id: Id) !Facts {
            if (id == .none) return .{ .height = 0, .leaves = 0, .bytes = 0, .value = M.identity };
            const n = s.wood.get(id);
            if (n.height == 0) return error.FreedNodeInTree;
            if (n.left == .none) {
                if (n.right != .none) return error.HalfBranch;
                if (n.value == null) return error.RefusedLeaf;
                if (n.bytes == 0) return error.EmptyLeaf;
                if (n.height != 1 or n.leaves != 1) return error.BadLeaf;
                return .{ .height = 1, .leaves = 1, .bytes = n.bytes, .value = n.value };
            }
            if (n.right == .none) return error.HalfBranch;
            const l = try s.audit(x, n.left);
            const r = try s.audit(x, n.right);
            const gap = @as(i64, l.height) - @as(i64, r.height);
            if (gap < -1 or gap > 1) return error.Unbalanced;
            if (n.height != 1 + @max(l.height, r.height)) return error.BadHeight;
            if (n.leaves != l.leaves + r.leaves) return error.BadCount;
            if (n.bytes != l.bytes + r.bytes) return error.BadBytes;
            const want = try Wood.mul(x, l.value, r.value);
            if (!same(n.value, want)) return error.LostAnnotation;
            return .{ .height = n.height, .leaves = n.leaves, .bytes = n.bytes, .value = n.value };
        }

        /// How many leaves lie before byte `p`, and where they stop.
        ///
        /// The two poles are the two ends of a disturbed range: the first
        /// disturbed leaf is the first one that has not `ended`, and the last
        /// is the last one that had `begun`. Same descent either way, because a
        /// branch whose whole span sits at or before `p` contributes all of its
        /// leaves under both readings.
        fn upto(s: *const Self, p: u32, comptime pole: enum { ended, begun }) struct { u32, u32 } {
            var id = s.root;
            var i: u32 = 0;
            var b: u32 = 0;
            while (id != .none) {
                const n = s.wood.get(id);
                if (n.left == .none) {
                    if (switch (pole) {
                        .ended => b + n.bytes <= p,
                        .begun => b < p,
                    }) {
                        i += 1;
                        b += n.bytes;
                    }
                    break;
                }
                const wide = s.wood.bytesOf(n.left);
                if (b + wide <= p) {
                    i += s.wood.leavesOf(n.left);
                    b += wide;
                    id = n.right;
                } else id = n.left;
            }
            return .{ i, b };
        }
    };
}

//! The wood the spine is cut from: nodes in an arena, their annotations, and
//! the rotations that keep the thing shallow.
//!
//! Split out of `tree.zig` because the two halves answer different questions.
//! This one knows nothing about bytes, cuts, or where a segment ends; it knows
//! that a branch holds the product of its children and that a tree twelve deep
//! over four thousand leaves is a bug. `tree.zig` knows the file. Everything
//! here is `pub` because Zig's privacy is per file and this is one type in two
//! files, not two types - nothing below is re-exported from `spine.zig`.
//!
//! ## Why an arena of indices rather than a tree of pointers
//!
//! The nodes live in one `ArrayList` and children are `u32` indices into it. A
//! tree of pointers into a list that reallocates is a use-after-free waiting
//! for the first big file, and the discipline it forces is worth stating: **a
//! node pointer does not survive a call that can allocate.** Every routine
//! below reads the child ids it needs, recurses, and only then takes a pointer
//! to write. That is not stylistic - `join` recursing while holding
//! `&nodes[id]` corrupts the tree the first time the arena grows mid-splice.
//!
//! ## A refusal absorbs
//!
//! `joint/effect.zig` composes partially on purpose - a refusal is the algebra
//! saying no parse ever put those two runs next to each other, which is the
//! pruning that keeps a joint small. So an annotation is `?Element` and a
//! branch over a refusal holds nothing either.
//!
//! That lift is sound for exactly the reason `effect.zig`'s associativity test
//! is written the way it is. It asserts that `(a·b)·c` and `a·(b·c)` are *both*
//! refused or *both* equal, never one of each - which is precisely the law you
//! need to adjoin a zero to a partial operation and get a total associative
//! one. So a subtree holding no product is a fact about the file rather than a
//! hole in the tree.

const std = @import("std");

/// A node's address in the arena. `none` rather than `?Id` so a child costs
/// four bytes instead of eight.
pub const Id = enum(u32) { none = std.math.maxInt(u32), _ };

pub fn Arbor(comptime M: type) type {
    return struct {
        const Self = @This();

        pub const Element = M.Element;
        pub const Ctx = M.Ctx;

        /// One segment: the bytes it covers and what it does to the stack. Zero
        /// bytes is not allowed - a leaf that covers nothing has no place in
        /// the byte order, so `touched` could not say which side of it a cut
        /// fell on.
        pub const Leaf = struct { bytes: u32, element: Element };

        pub const Node = struct {
            left: Id,
            right: Id,
            /// Zero marks a node on the free list, which is what lets the list
            /// thread through `right` without an allocation of its own: a live
            /// node's height is at least one.
            height: u32,
            leaves: u32,
            bytes: u32,
            value: ?Element,
        };

        gpa: std.mem.Allocator,
        nodes: std.ArrayList(Node),
        head: Id,

        pub fn init(gpa: std.mem.Allocator) Self {
            return .{ .gpa = gpa, .nodes = .empty, .head = .none };
        }

        pub fn deinit(s: *Self) void {
            s.nodes.deinit(s.gpa);
        }

        /// Both defined and equal, or both refused - the comparison every claim
        /// about this structure is stated in.
        pub fn same(a: ?Element, b: ?Element) bool {
            if (a == null or b == null) return a == null and b == null;
            return if (@hasDecl(M, "eql")) M.eql(a.?, b.?) else std.meta.eql(a.?, b.?);
        }

        /// `a` and then `b`, with a refusal absorbing. The one place
        /// `M.compose` is called, so the compositions an edit costs are the
        /// calls to this.
        pub fn mul(x: Ctx, a: ?Element, b: ?Element) !?Element {
            const l = a orelse return null;
            const r = b orelse return null;
            return try M.compose(x, l, r);
        }

        pub fn get(s: *const Self, id: Id) Node {
            return s.nodes.items[@intFromEnum(id)];
        }

        pub fn ref(s: *Self, id: Id) *Node {
            return &s.nodes.items[@intFromEnum(id)];
        }

        pub fn heightOf(s: *const Self, id: Id) u32 {
            return if (id == .none) 0 else s.get(id).height;
        }

        pub fn leavesOf(s: *const Self, id: Id) u32 {
            return if (id == .none) 0 else s.get(id).leaves;
        }

        pub fn bytesOf(s: *const Self, id: Id) u32 {
            return if (id == .none) 0 else s.get(id).bytes;
        }

        pub fn valueOf(s: *const Self, id: Id) ?Element {
            return if (id == .none) M.identity else s.get(id).value;
        }

        pub fn alloc(s: *Self) !Id {
            if (s.head != .none) {
                const id = s.head;
                s.head = s.get(id).right;
                return id;
            }
            try s.nodes.append(s.gpa, undefined);
            return @enumFromInt(s.nodes.items.len - 1);
        }

        pub fn release(s: *Self, id: Id) void {
            const n = s.ref(id);
            n.height = 0;
            n.right = s.head;
            s.head = id;
        }

        pub fn drop(s: *Self, id: Id) void {
            if (id == .none) return;
            const n = s.get(id);
            s.drop(n.left);
            s.drop(n.right);
            s.release(id);
        }

        pub fn sprout(s: *Self, l: Leaf) !Id {
            const id = try s.alloc();
            s.ref(id).* = .{
                .left = .none,
                .right = .none,
                .height = 1,
                .leaves = 1,
                .bytes = l.bytes,
                .value = l.element,
            };
            return id;
        }

        pub fn branch(s: *Self, x: Ctx, l: Id, r: Id) !Id {
            const id = try s.alloc();
            const n = s.ref(id);
            n.left = l;
            n.right = r;
            try s.pull(x, id);
            return id;
        }

        /// Recompute one branch from its children. Every composition this tree
        /// ever performs is one of these.
        pub fn pull(s: *Self, x: Ctx, id: Id) !void {
            const n = s.get(id);
            const value = try mul(x, s.valueOf(n.left), s.valueOf(n.right));
            const w = s.ref(id);
            w.height = 1 + @max(s.heightOf(n.left), s.heightOf(n.right));
            w.leaves = s.leavesOf(n.left) + s.leavesOf(n.right);
            w.bytes = s.bytesOf(n.left) + s.bytesOf(n.right);
            w.value = value;
        }

        /// A whole run of leaves at once, halving. One composition per node
        /// rather than one per leaf pair, and perfectly balanced on the way out.
        pub fn bulk(s: *Self, x: Ctx, ls: []const Leaf) !Id {
            if (ls.len == 0) return .none;
            if (ls.len == 1) return try s.sprout(ls[0]);
            const half = ls.len / 2;
            const l = try s.bulk(x, ls[0..half]);
            const r = try s.bulk(x, ls[half..]);
            return try s.branch(x, l, r);
        }

        /// Swap leaf `i` and re-multiply the branches over it. No rebalancing
        /// and no allocation, because the leaf count did not move.
        pub fn sink(s: *Self, x: Ctx, id: Id, i: u32, l: Leaf) !void {
            const n = s.get(id);
            if (n.left == .none) {
                const w = s.ref(id);
                w.bytes = l.bytes;
                w.value = l.element;
                return;
            }
            const wide = s.leavesOf(n.left);
            if (i < wide) try s.sink(x, n.left, i, l) else try s.sink(x, n.right, i - wide, l);
            try s.pull(x, id);
        }

        /// Rebalance one node whose children may now differ in height by two,
        /// and re-multiply it. Both rotations re-multiply what they moved, so a
        /// rotation cannot leave a stale product behind it.
        pub fn settle(s: *Self, x: Ctx, id: Id) !Id {
            try s.pull(x, id);
            const n = s.get(id);
            const gap = @as(i64, s.heightOf(n.left)) - @as(i64, s.heightOf(n.right));
            if (gap > 1) {
                const kid = s.get(n.left);
                if (s.heightOf(kid.left) < s.heightOf(kid.right)) {
                    s.ref(id).left = try s.spin(x, n.left, .left);
                }
                return try s.spin(x, id, .right);
            }
            if (gap < -1) {
                const kid = s.get(n.right);
                if (s.heightOf(kid.right) < s.heightOf(kid.left)) {
                    s.ref(id).right = try s.spin(x, n.right, .right);
                }
                return try s.spin(x, id, .left);
            }
            return id;
        }

        pub fn spin(s: *Self, x: Ctx, id: Id, comptime way: enum { left, right }) !Id {
            const n = s.get(id);
            const pivot = if (way == .left) n.right else n.left;
            const moved = if (way == .left) s.get(pivot).left else s.get(pivot).right;
            const w = s.ref(id);
            if (way == .left) w.right = moved else w.left = moved;
            const p = s.ref(pivot);
            if (way == .left) p.left = id else p.right = id;
            try s.pull(x, id);
            try s.pull(x, pivot);
            return pivot;
        }

        /// Two trees of any heights into one. The engine under `replace`: an
        /// unbalanced concatenation costs `O(|h(l) - h(r)|)` compositions,
        /// which is what keeps the whole edit logarithmic even when the
        /// replacement is a different size from what it replaced.
        pub fn join(s: *Self, x: Ctx, l: Id, r: Id) !Id {
            if (l == .none) return r;
            if (r == .none) return l;
            const hl = s.heightOf(l);
            const hr = s.heightOf(r);
            if (hl > hr + 1) {
                const grown = try s.join(x, s.get(l).right, r);
                s.ref(l).right = grown;
                return try s.settle(x, l);
            }
            if (hr > hl + 1) {
                const grown = try s.join(x, l, s.get(r).left);
                s.ref(r).left = grown;
                return try s.settle(x, r);
            }
            return try s.branch(x, l, r);
        }

        pub const Halves = struct { Id, Id };

        pub fn split(s: *Self, x: Ctx, id: Id, mark: u32) !Halves {
            if (id == .none) return .{ .none, .none };
            if (mark == 0) return .{ .none, id };
            if (mark == s.leavesOf(id)) return .{ id, .none };
            // A leaf's only cuts are its two ends, both answered above.
            const n = s.get(id);
            std.debug.assert(n.left != .none);
            // The branch node is spent: whichever side of the cut its children
            // land on, they are re-joined to something else. Its children were
            // read out first, so handing the slot back here is safe even though
            // the joins below may immediately allocate it again.
            s.release(id);
            const wide = s.leavesOf(n.left);
            if (mark <= wide) {
                const a, const b = try s.split(x, n.left, mark);
                return .{ a, try s.join(x, b, n.right) };
            }
            const a, const b = try s.split(x, n.right, mark - wide);
            return .{ try s.join(x, n.left, a), b };
        }
    };
}

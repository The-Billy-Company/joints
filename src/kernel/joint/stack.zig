//! A persistent, hash-consed stack of grammar symbols.
//!
//! An LR stack is a path in the goto automaton, so it can be written as the
//! string of symbols along that path and the states recovered by replaying
//! `goto`. Writing it that way is what lets a *segment* of a parse be described
//! without reference to what precedes it, which is the whole of M2.
//!
//! Two properties make it worth a data structure rather than a slice.
//!
//! It is **persistent**, because composing two stack effects truncates the left
//! one and appends the right one, and the surviving prefix is almost always the
//! bulk of it. A cons list shares that prefix for free: composition costs the
//! symbols it actually moves, not the depth of the stack it moves them on.
//!
//! It is **hash-consed**, so a stack is one `u32` and two stacks are equal in
//! one comparison. Every question M2 asks is an equality question — is this
//! joint the same as that one, how many distinct effects does this segment
//! have, did this edit change anything — and the answer has to be cheap or the
//! measurement costs more than the parse.
//!
//! Both properties are wanted for a second kind of sequence, so `Column` is
//! generic and `Pool` is its symbol instantiation. The other is the guard a
//! stack effect carries — one roster per popped depth, truncated and joined by
//! exactly the same two operations, in `ledger.zig`. Two clients, one structure,
//! and the element type keeps them from being confused for each other.

const std = @import("std");

pub const Symbol = u32;

/// A hash-consed persistent sequence of `T`, read bottom-to-top: `push` adds at
/// the top, `drop` removes from the top, and every tail is shared.
pub fn Column(comptime T: type) type {
    return struct {
        gpa: std.mem.Allocator,
        nodes: std.ArrayList(Node),
        interned: std.AutoHashMapUnmanaged(Key, Id),
        /// Reused by `concat`, which has to reverse a column to re-push it.
        scratch: std.ArrayList(T),

        const Self = @This();

        /// `empty` is the bottom; every other value indexes a shared node.
        pub const Id = enum(u32) { empty = 0, _ };

        const Node = struct {
            item: T,
            tail: Id,
            /// Cached so `depth` is a load rather than a walk — composition asks
            /// for it on every single step.
            depth: u32,
        };

        const Key = struct { item: T, tail: Id };

        pub fn init(gpa: std.mem.Allocator) Self {
            return .{ .gpa = gpa, .nodes = .empty, .interned = .empty, .scratch = .empty };
        }

        pub fn deinit(p: *Self) void {
            p.nodes.deinit(p.gpa);
            p.interned.deinit(p.gpa);
            p.scratch.deinit(p.gpa);
            p.* = undefined;
        }

        pub fn depth(p: *const Self, id: Id) u32 {
            return if (id == .empty) 0 else p.node(id).depth;
        }

        pub fn top(p: *const Self, id: Id) ?T {
            return if (id == .empty) null else p.node(id).item;
        }

        pub fn tail(p: *const Self, id: Id) Id {
            return if (id == .empty) .empty else p.node(id).tail;
        }

        /// The item furthest from the top, which for a guard is the deepest claim
        /// it makes. A walk, unlike `top` — the structure shares its tails, so
        /// the bottom is the one end it cannot cache.
        pub fn bottom(p: *const Self, id: Id) ?T {
            if (id == .empty) return null;
            var cur = id;
            while (p.tail(cur) != .empty) cur = p.tail(cur);
            return p.node(cur).item;
        }

        pub fn push(p: *Self, id: Id, item: T) !Id {
            const slot = try p.interned.getOrPut(p.gpa, .{ .item = item, .tail = id });
            if (slot.found_existing) return slot.value_ptr.*;
            try p.nodes.append(p.gpa, .{ .item = item, .tail = id, .depth = p.depth(id) + 1 });
            slot.value_ptr.* = @enumFromInt(p.nodes.items.len); // node 0 is `empty`
            return slot.value_ptr.*;
        }

        /// Remove the top `n`. Null when the column is shallower than that — the
        /// caller is popping into whatever preceded it, which is information
        /// this type deliberately does not have.
        pub fn drop(p: *const Self, id: Id, n: u32) ?Id {
            if (p.depth(id) < n) return null;
            var cur = id;
            for (0..n) |_| cur = p.tail(cur);
            return cur;
        }

        /// `other` stacked on top of `base`, bottom-to-top order preserved. Empty
        /// `base` returns `other` untouched, which is the common case and the
        /// reason the whole structure shares rather than copies.
        pub fn concat(p: *Self, base: Id, other: Id) !Id {
            if (other == .empty) return base;
            if (base == .empty) return other;
            p.scratch.clearRetainingCapacity();
            var it = p.iterate(other);
            while (it.next()) |s| try p.scratch.append(p.gpa, s);
            var cur = base;
            while (p.scratch.pop()) |s| cur = try p.push(cur, s);
            return cur;
        }

        /// The column with its bottom item replaced. Rebuilds the spine above it,
        /// which is what a persistent structure costs to edit at the far end —
        /// paid only when a neighbour narrows a guard's deepest claim.
        pub fn reseat(p: *Self, id: Id, item: T) !Id {
            const n = p.depth(id);
            if (n == 0) return p.push(.empty, item);
            p.scratch.clearRetainingCapacity();
            var it = p.iterate(id);
            for (0..n - 1) |_| try p.scratch.append(p.gpa, it.next().?);
            var cur = try p.push(.empty, item);
            while (p.scratch.pop()) |s| cur = try p.push(cur, s);
            return cur;
        }

        /// Bottom-to-top, borrowed from the pool and valid only until the next
        /// call on it. For walking a column forward through the automaton, where
        /// the caller wants the order a path reads in and has no business owning
        /// a buffer sized by someone else's depth.
        pub fn flatten(p: *Self, id: Id) ![]const T {
            p.scratch.clearRetainingCapacity();
            try p.scratch.resize(p.gpa, p.depth(id));
            return p.read(id, p.scratch.items);
        }

        /// Top-down. The order a parser pops in, not the order a stack reads in.
        pub fn iterate(p: *const Self, id: Id) Iterator {
            return .{ .pool = p, .cur = id };
        }

        pub const Iterator = struct {
            pool: *const Self,
            cur: Id,

            pub fn next(it: *Iterator) ?T {
                const s = it.pool.top(it.cur) orelse return null;
                it.cur = it.pool.tail(it.cur);
                return s;
            }
        };

        /// Bottom-to-top into `buf`, which must hold `depth(id)`. For printing
        /// and for tests; the parser never needs a stack flattened.
        pub fn read(p: *const Self, id: Id, buf: []T) []T {
            const n = p.depth(id);
            std.debug.assert(buf.len >= n);
            var it = p.iterate(id);
            var i = n;
            while (it.next()) |s| {
                i -= 1;
                buf[i] = s;
            }
            return buf[0..n];
        }

        /// Build one from a bottom-to-top slice.
        pub fn of(p: *Self, items: []const T) !Id {
            var cur: Id = .empty;
            for (items) |s| cur = try p.push(cur, s);
            return cur;
        }

        fn node(p: *const Self, id: Id) Node {
            return p.nodes.items[@intFromEnum(id) - 1];
        }
    };
}

/// The column M2 was written for: grammar symbols. `Pool.Id` is a stack, and
/// there is deliberately no file-level alias for it — inside a generic body,
/// `Id` would then name two things and Zig is right to refuse.
pub const Pool = Column(Symbol);

const testing = std.testing;

test "the same sequence interns to the same stack" {
    var p = Pool.init(testing.allocator);
    defer p.deinit();

    const a = try p.of(&.{ 1, 2, 3 });
    const b = try p.of(&.{ 1, 2, 3 });
    try testing.expectEqual(a, b);
    try testing.expectEqual(@as(u32, 3), p.depth(a));

    // And a shared prefix really is shared: five symbols across two stacks
    // that agree on three cost four nodes, not six.
    _ = try p.of(&.{ 1, 2, 9 });
    try testing.expectEqual(@as(usize, 4), p.nodes.items.len);
}

test "dropping past the bottom is unknown, not empty" {
    var p = Pool.init(testing.allocator);
    defer p.deinit();

    const s = try p.of(&.{ 7, 8 });
    try testing.expectEqual(try p.of(&.{7}), p.drop(s, 1).?);
    try testing.expectEqual(Pool.Id.empty, p.drop(s, 2).?);
    try testing.expectEqual(@as(?Pool.Id, null), p.drop(s, 3));
}

test "concat preserves order and shares when it can" {
    var p = Pool.init(testing.allocator);
    defer p.deinit();

    const base = try p.of(&.{ 1, 2 });
    const other = try p.of(&.{ 3, 4 });
    try testing.expectEqual(try p.of(&.{ 1, 2, 3, 4 }), try p.concat(base, other));

    // Nothing on nothing, and nothing under something, both cost zero nodes.
    const before = p.nodes.items.len;
    try testing.expectEqual(base, try p.concat(base, .empty));
    try testing.expectEqual(other, try p.concat(.empty, other));
    try testing.expectEqual(before, p.nodes.items.len);
}

test "read gives back what of was given" {
    var p = Pool.init(testing.allocator);
    defer p.deinit();

    var buf: [4]Symbol = undefined;
    const s = try p.of(&.{ 5, 6, 7, 8 });
    try testing.expectEqualSlices(Symbol, &.{ 5, 6, 7, 8 }, p.read(s, &buf));
}

test "the far end can be read and rewritten" {
    var p = Pool.init(testing.allocator);
    defer p.deinit();

    // The two operations a guard needs and a stack never did: its deepest claim
    // is the one a neighbour narrows, and it sits at the end the tails share.
    const s = try p.of(&.{ 1, 2, 3 });
    try testing.expectEqual(@as(?Symbol, 1), p.bottom(s));
    try testing.expectEqual(try p.of(&.{ 9, 2, 3 }), try p.reseat(s, 9));
    try testing.expectEqual(try p.of(&.{7}), try p.reseat(try p.of(&.{4}), 7));

    // Nothing has no far end, and reseating it is how a one-item column starts.
    try testing.expectEqual(@as(?Symbol, null), p.bottom(.empty));
    try testing.expectEqual(try p.of(&.{5}), try p.reseat(.empty, 5));
}

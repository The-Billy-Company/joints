//! A hash-consed set of automaton states — the guard on a stack effect.
//!
//! A segment that pops through its own base cannot know which state it
//! uncovered. The measurement says what it *can* know is usually far better
//! than "one of thirty-seven": popping a `{` uncovers exactly the four places a
//! `{` may be written, and all four then do the identical thing to the stack.
//! Carrying those four as one guarded answer is the difference between a joint
//! of rank one and a joint that doubles on every closing brace.
//!
//! So the floor of an effect is a **roster**: the set of states it would be
//! correct under. Composition intersects — a left neighbour that lands in one
//! of them keeps that scenario and discards the rest — so a chain of segments
//! narrows the guard rather than branching, and a roster that narrows to one
//! member is a run that has learned exactly where it stands.
//!
//! Interned for the same reason a stack is: every question is an equality
//! question, and a set that costs a pointer comparison is a set a measurement
//! can afford to ask about a million times.
//!
//! The same pool interns the **symbol** sets a [`ledger`](ledger.zig) claim
//! carries, for exactly the reason it interns state sets: two runs that popped
//! `{` and `[` respectively are one element the moment nothing can tell them
//! apart. Both are dense small integers over the same table, the operations
//! wanted are the same three, and a second copy of this machinery would earn
//! nothing but a type name.

const std = @import("std");

/// A member: a state id, or — in a ledger claim's symbol half — a grammar symbol.
///
/// `Pool.Hash` below hashes a roster as `sliceAsBytes` of these and compares
/// two rosters with `std.mem.eql`, which consults
/// `std.meta.hasUniqueRepresentation` before it will `memcmp`. So a member type
/// with bytes no field owns would leave the two halves reading different
/// things, and a pool whose whole purpose is "equal sets are one id" would mint
/// two ids for one set — silently, and as a function of the allocator. The
/// assertion is trivial for an integer and is here for the edit that stops it
/// being one.
pub const State = u32;

comptime {
    if (!std.meta.hasUniqueRepresentation(State)) @compileError(
        "roster.State is hashed by its bytes and compared by its fields, so" ++
            " every byte of it has to belong to a field.",
    );
}

/// A set of states. `nowhere` is the empty set — a scenario nothing supports,
/// which is what a refused composition produces.
pub const Id = enum(u32) { nowhere = 0, _ };

pub const Pool = struct {
    gpa: std.mem.Allocator,
    /// `sets[i]` is the roster with id `i`, sorted ascending. Sorted is the
    /// whole trick: it makes the byte image canonical, so interning is a hash
    /// of the bytes and intersection is a merge.
    sets: std.ArrayList([]const State),
    interned: std.HashMapUnmanaged([]const State, Id, Hash, std.hash_map.default_max_load_percentage),
    arena: std.heap.ArenaAllocator,
    scratch: std.ArrayList(State),

    const Hash = struct {
        pub fn hash(_: Hash, k: []const State) u64 {
            return std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(k));
        }
        pub fn eql(_: Hash, a: []const State, b: []const State) bool {
            return std.mem.eql(State, a, b);
        }
    };

    pub fn init(gpa: std.mem.Allocator) Pool {
        return .{
            .gpa = gpa,
            .sets = .empty,
            .interned = .empty,
            .arena = std.heap.ArenaAllocator.init(gpa),
            .scratch = .empty,
        };
    }

    pub fn deinit(p: *Pool) void {
        p.sets.deinit(p.gpa);
        p.interned.deinit(p.gpa);
        p.arena.deinit();
        p.scratch.deinit(p.gpa);
        p.* = undefined;
    }

    /// The roster of `states`, in any order and with any duplicates. Sorting is
    /// the caller's convenience, not its obligation.
    pub fn of(p: *Pool, states: []const State) !Id {
        p.scratch.clearRetainingCapacity();
        try p.scratch.appendSlice(p.gpa, states);
        std.mem.sort(State, p.scratch.items, {}, std.sort.asc(State));
        var n: usize = 0;
        for (p.scratch.items) |s| {
            if (n != 0 and p.scratch.items[n - 1] == s) continue;
            p.scratch.items[n] = s;
            n += 1;
        }
        return p.intern(p.scratch.items[0..n]);
    }

    /// A single state, the common case, without touching the scratch buffer.
    pub fn one(p: *Pool, state: State) !Id {
        return p.intern(&.{state});
    }

    pub fn members(p: *const Pool, id: Id) []const State {
        return if (id == .nowhere) &.{} else p.sets.items[@intFromEnum(id) - 1];
    }

    pub fn size(p: *const Pool, id: Id) u32 {
        return @intCast(p.members(id).len);
    }

    pub fn has(p: *const Pool, id: Id, state: State) bool {
        return std.sort.binarySearch(State, p.members(id), state, order) != null;
    }

    /// The members of `id` that `keep` accepts, as a roster. The one operation
    /// composition needs: a guard narrowed by what the neighbour turned out to
    /// be. `nowhere` means the two runs were never adjacent.
    pub fn refine(
        p: *Pool,
        id: Id,
        ctx: anytype,
        comptime keep: fn (@TypeOf(ctx), State) bool,
    ) !Id {
        const all = p.members(id);
        var n: usize = 0;
        for (all) |s| n += @intFromBool(keep(ctx, s));
        if (n == all.len) return id;
        if (n == 0) return .nowhere;
        p.scratch.clearRetainingCapacity();
        for (all) |s| if (keep(ctx, s)) try p.scratch.append(p.gpa, s);
        return p.intern(p.scratch.items);
    }

    /// The states both rosters allow — what it means for two runs to be talking
    /// about the same place on the stack. A merge rather than a search per
    /// member, which is what sorting the sets was for. `nowhere` means the two
    /// runs were never adjacent.
    pub fn meet(p: *Pool, a: Id, b: Id) !Id {
        if (a == b) return a;
        const xs = p.members(a);
        const ys = p.members(b);
        p.scratch.clearRetainingCapacity();
        var i: usize = 0;
        var j: usize = 0;
        while (i < xs.len and j < ys.len) {
            if (xs[i] < ys[j]) i += 1 else if (ys[j] < xs[i]) j += 1 else {
                try p.scratch.append(p.gpa, xs[i]);
                i += 1;
                j += 1;
            }
        }
        return p.intern(p.scratch.items);
    }

    /// The states either roster allows — the guard of a scenario that is one of
    /// two scenarios and no longer remembers which. Fusing limbs is where this
    /// is wanted: two runs that agree on everything a neighbour can observe
    /// should cost one answer, not two, and the price of saying so is a guard
    /// wide enough to cover both.
    pub fn join(p: *Pool, a: Id, b: Id) !Id {
        if (a == b) return a;
        if (a == .nowhere) return b;
        if (b == .nowhere) return a;
        const xs = p.members(a);
        const ys = p.members(b);
        p.scratch.clearRetainingCapacity();
        var i: usize = 0;
        var j: usize = 0;
        while (i < xs.len and j < ys.len) {
            if (xs[i] < ys[j]) {
                try p.scratch.append(p.gpa, xs[i]);
                i += 1;
            } else if (ys[j] < xs[i]) {
                try p.scratch.append(p.gpa, ys[j]);
                j += 1;
            } else {
                try p.scratch.append(p.gpa, xs[i]);
                i += 1;
                j += 1;
            }
        }
        try p.scratch.appendSlice(p.gpa, xs[i..]);
        try p.scratch.appendSlice(p.gpa, ys[j..]);
        return p.intern(p.scratch.items);
    }

    /// Sorted and deduplicated already, or the interning is not canonical.
    fn intern(p: *Pool, sorted: []const State) !Id {
        if (sorted.len == 0) return .nowhere;
        const slot = try p.interned.getOrPut(p.gpa, sorted);
        if (slot.found_existing) return slot.value_ptr.*;
        const owned = try p.arena.allocator().dupe(State, sorted);
        slot.key_ptr.* = owned;
        try p.sets.append(p.gpa, owned);
        slot.value_ptr.* = @enumFromInt(p.sets.items.len); // set 0 is `nowhere`
        return slot.value_ptr.*;
    }

    fn order(a: State, b: State) std.math.Order {
        return std.math.order(a, b);
    }
};

const testing = std.testing;

test "the same set interns to the same roster, however it was spelled" {
    var p = Pool.init(testing.allocator);
    defer p.deinit();

    const a = try p.of(&.{ 7, 2, 7, 5 });
    const b = try p.of(&.{ 2, 5, 7 });
    try testing.expectEqual(a, b);
    try testing.expectEqualSlices(State, &.{ 2, 5, 7 }, p.members(a));
    try testing.expectEqual(@as(u32, 3), p.size(a));

    // The empty set is a value, not an absence: a composition that refuted
    // every scenario has to be able to say so in the same currency.
    try testing.expectEqual(Id.nowhere, try p.of(&.{}));
    try testing.expectEqual(@as(usize, 0), p.members(.nowhere).len);
}

test "membership and refinement, which is all composition ever asks" {
    var p = Pool.init(testing.allocator);
    defer p.deinit();

    const wide = try p.of(&.{ 2, 8, 25, 33 });
    try testing.expect(p.has(wide, 25));
    try testing.expect(!p.has(wide, 26));

    const even = try p.refine(wide, {}, struct {
        fn f(_: void, s: State) bool {
            return s % 2 == 0;
        }
    }.f);
    try testing.expectEqualSlices(State, &.{ 2, 8 }, p.members(even));

    // Refining away nothing gives the identical roster rather than a copy, and
    // refining away everything gives `nowhere` rather than an empty allocation.
    try testing.expectEqual(wide, try p.refine(wide, {}, struct {
        fn f(_: void, _: State) bool {
            return true;
        }
    }.f));
    try testing.expectEqual(Id.nowhere, try p.refine(wide, {}, struct {
        fn f(_: void, _: State) bool {
            return false;
        }
    }.f));
}

test "meeting two rosters keeps what both allow" {
    var p = Pool.init(testing.allocator);
    defer p.deinit();

    const left = try p.of(&.{ 1, 4, 9, 16 });
    const right = try p.of(&.{ 2, 4, 16, 25 });
    try testing.expectEqualSlices(State, &.{ 4, 16 }, p.members(try p.meet(left, right)));

    // Commutative and idempotent, since composition reassociates freely and a
    // meet that depended on the order would be a monoid law waiting to break.
    try testing.expectEqual(try p.meet(left, right), try p.meet(right, left));
    try testing.expectEqual(left, try p.meet(left, left));

    // Sets that share nothing meet at `nowhere`, and `nowhere` absorbs.
    try testing.expectEqual(Id.nowhere, try p.meet(left, try p.of(&.{ 3, 5 })));
    try testing.expectEqual(Id.nowhere, try p.meet(left, .nowhere));
}

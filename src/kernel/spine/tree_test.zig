//! The boring parts of the spine, which is where a balanced tree actually goes
//! wrong: nothing in it, one thing in it, the thing at either end, and a
//! rotation that carried the wrong product.
//!
//! The edit stream in `stream_test.zig` is the test that matters; these are the
//! cases a random stream reaches rarely and diagnoses badly when it does.

const std = @import("std");
const t = std.testing;
const spine = @import("spine.zig");
const toy = @import("toy.zig");

const Tally = toy.Tally;
const Sieve = toy.Sieve;
const Spine = spine.Tree(Tally);
const Leaf = Spine.Leaf;

/// A spine plus the meter its monoid composes against.
const Fix = struct {
    m: toy.Meter = .{},
    s: Spine,

    fn init() Fix {
        return .{ .s = Spine.init(t.allocator) };
    }

    fn deinit(f: *Fix) void {
        f.s.deinit();
    }

    /// Everything true of the tree at once: it agrees with itself, and its
    /// product agrees with the from-scratch one over its own leaves.
    fn check(f: *Fix) !void {
        try f.s.verify(&f.m);
        var ls: std.ArrayList(Leaf) = .empty;
        defer ls.deinit(t.allocator);
        for (0..f.s.len()) |i| try ls.append(t.allocator, f.s.at(@intCast(i)));
        try t.expect(Spine.same(f.s.product(), try toy.fold(Tally, &f.m, ls.items)));
    }
};

/// A leaf whose element is decided by `n`, so a test can name the same leaf
/// twice and mean it.
fn leaf(n: u64, bytes: u32) Leaf {
    return .{ .bytes = bytes, .element = .{ .hash = n *% 0x2545F4914F6CDD1D | 1, .span = 1 } };
}

test "spine: an empty one is the identity and stays legal" {
    var f = Fix.init();
    defer f.deinit();

    try t.expectEqual(@as(u32, 0), f.s.len());
    try t.expectEqual(@as(u32, 0), f.s.bytes());
    try t.expectEqual(@as(u32, 0), f.s.height());
    try t.expect(Spine.same(Tally.identity, f.s.product()));
    try f.check();

    // The identity really is the identity of what comes after it: a file built
    // from nothing and then filled has the same product as one built full.
    _ = try f.s.build(&f.m, &.{ leaf(1, 3), leaf(2, 4) });
    const filled = f.s.product();
    var other = Fix.init();
    defer other.deinit();
    _ = try other.s.build(&other.m, &.{});
    _ = try other.s.replace(&other.m, 0, 0, &.{ leaf(1, 3), leaf(2, 4) });
    try t.expect(Spine.same(filled, other.s.product()));
}

test "spine: one leaf is its own product, and survives being replaced" {
    var f = Fix.init();
    defer f.deinit();
    _ = try f.s.build(&f.m, &.{leaf(7, 5)});

    try t.expectEqual(@as(u32, 1), f.s.len());
    try t.expectEqual(@as(u32, 5), f.s.bytes());
    try t.expect(Spine.same(leaf(7, 5).element, f.s.product()));
    try f.check();

    _ = try f.s.splice(&f.m, 0, leaf(8, 2));
    try t.expect(Spine.same(leaf(8, 2).element, f.s.product()));
    try t.expectEqual(@as(u32, 2), f.s.bytes());
    try f.check();

    // And all the way back to nothing, which is the case a `split` that assumes
    // it always has something to cut gets wrong.
    _ = try f.s.replace(&f.m, 0, 1, &.{});
    try t.expectEqual(@as(u32, 0), f.s.len());
    try t.expect(Spine.same(Tally.identity, f.s.product()));
    try f.check();
}

test "spine: either end splices without disturbing the other" {
    var f = Fix.init();
    defer f.deinit();
    var start: [16]Leaf = undefined;
    for (&start, 0..) |*l, i| l.* = leaf(i, 1 + @as(u32, @intCast(i % 4)));
    _ = try f.s.build(&f.m, &start);
    const whole = f.s.product();

    for ([_]u32{ 0, 15 }) |end| {
        _ = try f.s.splice(&f.m, end, leaf(100 + end, 9));
        try f.check();
        try t.expect(!Spine.same(whole, f.s.product()));
        _ = try f.s.splice(&f.m, end, start[end]);
        try f.check();
        // Back to exactly where it was, which is the statement that a splice
        // touches the products above it and nothing else.
        try t.expect(Spine.same(whole, f.s.product()));
    }
}

test "spine: a cut names the leaves it really disturbed" {
    var f = Fix.init();
    defer f.deinit();
    _ = try f.s.build(&f.m, &.{ leaf(1, 3), leaf(2, 4), leaf(3, 5) });

    // A pure insertion sitting on a segment boundary disturbs nothing; the same
    // insertion one byte later disturbs the segment it landed inside. That
    // difference is what an editor hits on every press of Enter, and it is the
    // reason the predicate is an overlap rather than a containment.
    const onto = f.s.touched(.{ .from = 3, .to = 3, .insert = 1 });
    try t.expectEqual(@as(u32, 1), onto.first);
    try t.expectEqual(@as(u32, 1), onto.last);
    try t.expectEqual(@as(u32, 3), onto.from);
    try t.expectEqual(@as(u32, 4), onto.to);

    const into = f.s.touched(.{ .from = 4, .to = 4, .insert = 1 });
    try t.expectEqual(@as(u32, 1), into.first);
    try t.expectEqual(@as(u32, 2), into.last);
    try t.expectEqual(@as(u32, 3), into.from);
    try t.expectEqual(@as(u32, 8), into.to);

    // A deletion crossing all three, and an append past the last byte.
    const across = f.s.touched(.{ .from = 1, .to = 9, .insert = 0 });
    try t.expectEqual(@as(u32, 0), across.first);
    try t.expectEqual(@as(u32, 3), across.last);
    try t.expectEqual(@as(u32, 0), across.from);
    try t.expectEqual(@as(u32, 4), across.to);

    const past = f.s.touched(.{ .from = 12, .to = 12, .insert = 3 });
    try t.expectEqual(@as(u32, 3), past.first);
    try t.expectEqual(@as(u32, 3), past.last);
    try t.expectEqual(@as(u32, 12), past.from);
    try t.expectEqual(@as(u32, 15), past.to);
}

test "spine: an empty tree still answers what a cut disturbed" {
    var f = Fix.init();
    defer f.deinit();
    const span = f.s.touched(.{ .from = 0, .to = 0, .insert = 6 });
    try t.expectEqual(@as(u32, 0), span.first);
    try t.expectEqual(@as(u32, 0), span.last);
    try t.expectEqual(@as(u32, 0), span.from);
    try t.expectEqual(@as(u32, 6), span.to);
}

/// Hands back one leaf covering whatever it was asked for, or none when the
/// span is empty. Enough to drive `edit` where the point is the byte
/// arithmetic rather than the segmentation.
const Whole = struct {
    one: [1]Spine.Leaf = undefined,
    pub fn mint(w: *Whole, from: u32, to: u32) ![]const Spine.Leaf {
        if (to == from) return &.{};
        w.one[0] = leaf(@as(u64, from) << 20 | to, to - from);
        return w.one[0..1];
    }
};

test "spine: an edit re-derives the segments it landed in and no others" {
    var f = Fix.init();
    defer f.deinit();
    _ = try f.s.build(&f.m, &.{ leaf(1, 4), leaf(2, 4), leaf(3, 4) });
    const before = f.s.at(0);
    var w: Whole = .{};

    // Type one byte inside the middle segment: that segment is re-derived, the
    // two around it are not, and the file is one byte longer.
    _ = try f.s.edit(&f.m, .{ .from = 6, .to = 6, .insert = 1 }, &w);
    try t.expectEqual(@as(u32, 3), f.s.len());
    try t.expectEqual(@as(u32, 13), f.s.bytes());
    try t.expectEqual(@as(u32, 5), f.s.at(1).bytes);
    try t.expect(Tally.eql(before.element, f.s.at(0).element));
    try f.check();

    // Delete across the join between the first two, which takes both.
    _ = try f.s.edit(&f.m, .{ .from = 2, .to = 7, .insert = 0 }, &w);
    try t.expectEqual(@as(u32, 2), f.s.len());
    try t.expectEqual(@as(u32, 8), f.s.bytes());
    try f.check();

    // And an insertion at the very end, which disturbs nothing and appends.
    _ = try f.s.edit(&f.m, .{ .from = 8, .to = 8, .insert = 3 }, &w);
    try t.expectEqual(@as(u32, 3), f.s.len());
    try t.expectEqual(@as(u32, 11), f.s.bytes());
    try f.check();
}

test "spine: a minter that does not cover the span is refused" {
    var f = Fix.init();
    defer f.deinit();
    _ = try f.s.build(&f.m, &.{leaf(1, 4)});
    const Short = struct {
        one: [1]Spine.Leaf = undefined,
        pub fn mint(sh: *@This(), from: u32, _: u32) ![]const Spine.Leaf {
            sh.one[0] = leaf(from, 1);
            return sh.one[0..1];
        }
    };
    var sh: Short = .{};
    try t.expectError(
        error.MintDoesNotCover,
        f.s.edit(&f.m, .{ .from = 1, .to = 2, .insert = 9 }, &sh),
    );
}

test "spine: growing a leaf at a time never loses an annotation" {
    var f = Fix.init();
    defer f.deinit();

    // Inserting at the front every time is the worst case for an AVL join: the
    // tree is out of balance on the same side at every step, so this is the
    // path that rotates most, and a rotation that forgets to re-multiply what it
    // moved is invisible in the shape and fatal in the answer.
    for (0..200) |i| {
        _ = try f.s.replace(&f.m, 0, 0, &.{leaf(i, 1 + @as(u32, @intCast(i % 7)))});
        try f.check();
    }
    try t.expectEqual(@as(u32, 200), f.s.len());
    // Balanced, not merely correct: 200 leaves in a list would be 200 tall.
    try t.expect(f.s.height() <= 12);

    // The same leaves built in one pass have the same product under a different
    // bracketing, which is associativity stated as a test rather than assumed.
    var ls: std.ArrayList(Leaf) = .empty;
    defer ls.deinit(t.allocator);
    for (0..f.s.len()) |i| try ls.append(t.allocator, f.s.at(@intCast(i)));
    var fresh = Fix.init();
    defer fresh.deinit();
    _ = try fresh.s.build(&fresh.m, ls.items);
    try t.expect(Spine.same(f.s.product(), fresh.s.product()));

    // And back down to nothing from the middle out, which is the other side of
    // the same rebalancing.
    while (f.s.len() > 0) {
        _ = try f.s.replace(&f.m, f.s.len() / 2, f.s.len() / 2 + 1, &.{});
        try f.check();
    }
    try t.expect(Spine.same(Tally.identity, f.s.product()));
}

test "spine: a refusal absorbs, and splicing it away brings the product back" {
    const Sp = spine.Tree(Sieve);
    var m: toy.Meter = .{};
    var s = Sp.init(t.allocator);
    defer s.deinit();

    // `funnel` sends everything to point 4; `blocked` is defined nowhere on 4.
    // No parse put those two next to each other, so their product is a refusal
    // rather than an element - and the file has no product at all while it is
    // in there, which is the honest answer and not a hole in the tree.
    const funnel: Sieve.Element = .{ .to = @splat(4) };
    const blocked: Sieve.Element = .{ .to = .{ 0, 1, 2, 3, Sieve.nowhere, 5, 6, 7 } };
    const open: Sieve.Element = .{ .to = .{ 7, 6, 5, 4, 3, 2, 1, 0 } };

    _ = try s.build(&m, &.{
        .{ .bytes = 1, .element = Sieve.identity },
        .{ .bytes = 1, .element = funnel },
        .{ .bytes = 1, .element = blocked },
        .{ .bytes = 1, .element = open },
    });
    try t.expectEqual(@as(?Sieve.Element, null), s.product());
    try s.verify(&m);

    _ = try s.splice(&m, 2, .{ .bytes = 1, .element = open });
    try t.expect(s.product() != null);
    try s.verify(&m);
    try t.expect(Sp.same(s.product(), try toy.fold(Sieve, &m, &[_]Sp.Leaf{
        .{ .bytes = 1, .element = Sieve.identity },
        .{ .bytes = 1, .element = funnel },
        .{ .bytes = 1, .element = open },
        .{ .bytes = 1, .element = open },
    })));

    // Putting it back refuses again, so the absorbing zero is not sticky: a
    // branch holds no product because its children do not compose today, never
    // because they once did not.
    _ = try s.splice(&m, 2, .{ .bytes = 1, .element = blocked });
    try t.expectEqual(@as(?Sieve.Element, null), s.product());
    try s.verify(&m);
}

//! A flat matrix of equal-width bit sets.
//!
//! LALR construction carries one terminal set per nonterminal transition and
//! spends nearly all of its time taking unions along a relation. Individually
//! allocated sets would put a pointer chase in front of every one of those
//! unions and scatter them across the heap; here every set is a stride into one
//! contiguous buffer, so a union is a straight-line word loop over memory the
//! prefetcher already has.
//!
//! Rows are fixed at construction because the number of transitions and the
//! number of terminals are both known before the first union happens.

const std = @import("std");

pub const Matrix = struct {
    words: []u64,
    /// Words per row. Rows are padded to this stride so row starts are
    /// computable rather than stored.
    stride: usize,
    bits: usize,

    pub fn init(gpa: std.mem.Allocator, rows: usize, bits: usize) !Matrix {
        const stride = (bits + 63) / 64;
        const words = try gpa.alloc(u64, rows * stride);
        @memset(words, 0);
        return .{ .words = words, .stride = stride, .bits = bits };
    }

    pub fn deinit(m: *Matrix, gpa: std.mem.Allocator) void {
        gpa.free(m.words);
        m.* = undefined;
    }

    pub fn row(m: Matrix, i: usize) []u64 {
        return m.words[i * m.stride ..][0..m.stride];
    }

    pub fn set(m: Matrix, i: usize, bit: usize) void {
        m.row(i)[bit >> 6] |= @as(u64, 1) << @truncate(bit);
    }

    pub fn isSet(m: Matrix, i: usize, bit: usize) bool {
        return m.row(i)[bit >> 6] & (@as(u64, 1) << @truncate(bit)) != 0;
    }

    /// `dst |= src`, reporting whether anything changed. The answer is what
    /// drives every fixpoint here, so computing it during the union is strictly
    /// cheaper than comparing before and after.
    pub fn unionInto(m: Matrix, dst: usize, src: usize) bool {
        var changed = false;
        const d = m.row(dst);
        const s = m.row(src);
        for (d, s) |*a, b| {
            const merged = a.* | b;
            changed = changed or merged != a.*;
            a.* = merged;
        }
        return changed;
    }

    /// `dst |= src`, where the two rows live in different matrices of equal
    /// width. Used to pour a `Follow` set into a lookahead set.
    pub fn unionFrom(m: Matrix, dst: usize, other: Matrix, src: usize) void {
        for (m.row(dst), other.row(src)) |*a, b| a.* |= b;
    }

    pub fn copyRow(m: Matrix, dst: usize, src: usize) void {
        if (dst == src) return;
        @memcpy(m.row(dst), m.row(src));
    }

    pub fn count(m: Matrix, i: usize) usize {
        var n: usize = 0;
        for (m.row(i)) |word| n += @popCount(word);
        return n;
    }

    pub fn intersects(m: Matrix, a: usize, b: usize) bool {
        for (m.row(a), m.row(b)) |x, y| if (x & y != 0) return true;
        return false;
    }

    /// Iterate the set bits of one row in ascending order.
    pub fn iterate(m: Matrix, i: usize) Iterator {
        return .{ .words = m.row(i), .word = 0, .index = 0 };
    }

    pub const Iterator = struct {
        words: []const u64,
        word: u64,
        index: usize,

        pub fn next(it: *Iterator) ?usize {
            while (it.word == 0) {
                if (it.index >= it.words.len) return null;
                it.word = it.words[it.index];
                it.index += 1;
            }
            const bit = @ctz(it.word);
            it.word &= it.word - 1;
            return (it.index - 1) * 64 + bit;
        }
    };
};

const testing = std.testing;

test "a union reports change only when it adds something" {
    var m = try Matrix.init(testing.allocator, 3, 130);
    defer m.deinit(testing.allocator);

    m.set(0, 1);
    m.set(0, 129);
    m.set(1, 1);

    try testing.expect(m.unionInto(1, 0)); // 129 is new
    try testing.expect(!m.unionInto(1, 0)); // nothing left to add
    try testing.expectEqual(@as(usize, 2), m.count(1));
    try testing.expect(m.isSet(1, 129));
    try testing.expect(!m.intersects(0, 2));
}

test "iteration walks set bits in order across word boundaries" {
    var m = try Matrix.init(testing.allocator, 1, 200);
    defer m.deinit(testing.allocator);
    for ([_]usize{ 0, 63, 64, 127, 199 }) |b| m.set(0, b);

    var seen: [5]usize = undefined;
    var n: usize = 0;
    var it = m.iterate(0);
    while (it.next()) |b| : (n += 1) seen[n] = b;

    try testing.expectEqual(@as(usize, 5), n);
    try testing.expectEqualSlices(usize, &.{ 0, 63, 64, 127, 199 }, &seen);
}

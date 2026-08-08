//! One pass over the raw material, in blocks, before anything is a token.
//!
//! Everything above this file asks the same three questions of a stretch of
//! bytes - where is the next one of these, how far does this run of those go,
//! where does this two-byte pair land - and every one of them was written as a
//! `while (i < bytes.len) : (i += 1)` somewhere in `kernel/lex/`. A byte at a
//! time is the wrong instrument for a question a compare against sixty-four
//! lanes answers in one go, and the lexer asks it once per line.
//!
//! ## Why sixty-four and not the machine's own width
//!
//! `std.simd.suggestVectorLength(u8)` says 16 on this laptop's NEON and 32 on
//! an AVX2 box. The block here is 64 regardless, because **the mask is the
//! product**: a `u64` is one word to shift, to `@ctz`, to carry into the next
//! block and to hand to a caller, where four `u16`s are four of everything and
//! a seam between each pair. Zig legalizes the wide compare into the four
//! register-sized ones the core actually has, and an out-of-order core issues
//! them across its vector pipes - the same trade irregex's streaming scanners
//! took at 64 bytes, for the same measured reason.
//!
//! ## Portability, stated plainly
//!
//! There is no intrinsic anywhere in this file and no `@import("std").Target`
//! branch. `@Vector(64, u8)` compiles on every backend Zig has; on a target
//! with no vector unit at all it lowers to scalar code that is still correct,
//! just no faster than the loop it replaced. That is the whole fallback story:
//! one implementation, legalized per target, byte-identical answers. joints
//! builds on macOS/aarch64 and Linux/x86-64 in CI and neither gets its own
//! path here.

const std = @import("std");

/// Bytes per block, and therefore the width of every mask below.
pub const block = 64;

/// One block's worth of answers. Bit `k` is byte `base + k`.
pub const Mask = u64;

const V = @Vector(block, u8);

/// A block of the material, loaded once and asked several questions.
///
/// The load is the expensive part and the compares are nearly free, so the
/// shape that matters is one `of` followed by however many `where`s the caller
/// needs. Asking for newlines and spaces separately would pay the load twice.
pub const Sheet = struct {
    v: V,
    /// How many of the 64 lanes are real. A short block is padded with NUL,
    /// which is safe because no class this file answers about contains NUL -
    /// but a caller counting a run still has to stop at `live`.
    live: u32,

    pub fn of(bytes: []const u8, base: usize) Sheet {
        const left = bytes.len - base;
        if (left >= block) return .{ .v = bytes[base..][0..block].*, .live = block };
        var pad: [block]u8 = @splat(0);
        @memcpy(pad[0..left], bytes[base..]);
        return .{ .v = pad, .live = @intCast(left) };
    }

    /// Where this byte sits in the block.
    pub inline fn where(s: Sheet, c: u8) Mask {
        return @bitCast(s.v == @as(V, @splat(c)));
    }

    /// Where any of these bytes sit. Comptime so the OR tree unrolls into the
    /// compares themselves rather than a loop over a runtime slice.
    pub inline fn whereAny(s: Sheet, comptime cs: []const u8) Mask {
        var m: Mask = 0;
        inline for (cs) |c| m |= s.where(c);
        return m;
    }

    /// The lanes that are really there, so a padded tail cannot answer.
    pub inline fn real(s: Sheet) Mask {
        return if (s.live == block) ~@as(Mask, 0) else (@as(Mask, 1) << @intCast(s.live)) - 1;
    }
};

/// Bytes tried one at a time before a block is loaded at all.
///
/// A movemask is free on x86 and is not free on NEON, where extracting a
/// 64-lane comparison into a `u64` is a shift-and-narrow sequence. The runs
/// this file is asked about are mostly *short* - a four-space indent, a
/// `*/` two bytes along - and for those the extraction costs more than the
/// bytes it was meant to skip. So the block is entered only once a run has
/// already proven it is long, and the measured price of getting this wrong is
/// on the record: without the peel the vectorized arm was behind the byte loop
/// on every corpus file in `bench/rungs/grain`.
const peel = 16;

inline fn holds(comptime cs: []const u8, c: u8) bool {
    inline for (cs) |k| if (c == k) return true;
    return false;
}

/// The next byte in `cs` at or after `from`, or `bytes.len` when there is
/// none. The end-of-input answer is a position rather than a null because
/// every caller here treats "ran off the end" as "stopped at the end".
pub fn find(bytes: []const u8, from: u32, comptime cs: []const u8) u32 {
    var i: usize = from;
    const near = @min(bytes.len, i + peel);
    while (i < near) : (i += 1) if (holds(cs, bytes[i])) return @intCast(i);
    while (i < bytes.len) : (i += block) {
        const sheet = Sheet.of(bytes, i);
        const hit = sheet.whereAny(cs) & sheet.real();
        if (hit != 0) return @intCast(i + @ctz(hit));
    }
    return @intCast(bytes.len);
}

/// The first byte at or after `from` that is **not** in `cs` - the run
/// skipper. Ends at `bytes.len`, which is what a run reaching the end of the
/// file means.
pub fn past(bytes: []const u8, from: u32, comptime cs: []const u8) u32 {
    var i: usize = from;
    const near = @min(bytes.len, i + peel);
    while (i < near) : (i += 1) if (!holds(cs, bytes[i])) return @intCast(i);
    while (i < bytes.len) : (i += block) {
        const sheet = Sheet.of(bytes, i);
        const out = ~sheet.whereAny(cs) & sheet.real();
        if (out != 0) return @intCast(i + @ctz(out));
    }
    return @intCast(bytes.len);
}

/// The next `pair` at or after `from`, or `bytes.len`.
///
/// Both bytes are gated in one block: the second byte's mask is shifted down
/// by one so a lane holding `pair[0]` lines up with its own successor, and the
/// bit that falls off the top is recovered from the next block's first byte.
/// That carry is the only reason this is not just two `find`s - a pair
/// straddling a block boundary is the case a naive version silently misses.
pub fn seek(bytes: []const u8, from: u32, comptime pair: [2]u8) u32 {
    if (bytes.len < 2) return @intCast(bytes.len);
    var i: usize = from;
    while (i + 1 < bytes.len) : (i += block) {
        const sheet = Sheet.of(bytes, i);
        const lead = sheet.where(pair[0]) & sheet.real();
        if (lead == 0) continue;
        var next = sheet.where(pair[1]) >> 1;
        if (i + block < bytes.len and bytes[i + block] == pair[1]) {
            next |= @as(Mask, 1) << (block - 1);
        }
        // A lane whose successor is padding contributes nothing: the pad is NUL
        // and no pair this file is asked about contains one, so the last real
        // byte cannot open a pair that is not there.
        const hit = lead & next;
        if (hit != 0) return @intCast(i + @ctz(hit));
    }
    return @intCast(bytes.len);
}

test "sweep: find and past agree with the byte loop on every offset" {
    const src = "  \tabc\n\n  # x\n\tdef\r\nghi";
    for (0..src.len + 1) |at| {
        const from: u32 = @intCast(at);
        var want: u32 = from;
        while (want < src.len and src[want] != '\n') want += 1;
        try std.testing.expectEqual(want, find(src, from, "\n"));

        var run: u32 = from;
        while (run < src.len and (src[run] == ' ' or src[run] == '\t')) run += 1;
        try std.testing.expectEqual(run, past(src, from, " \t"));
    }
}

test "sweep: a pair straddling the block boundary is still found" {
    // The carry the shift alone loses. `*` lands on the last lane of block 0
    // and `/` on the first lane of block 1, which is the one arrangement a
    // within-block `lead & (next >> 1)` cannot see.
    var src: [block + 8]u8 = @splat('x');
    src[block - 1] = '*';
    src[block] = '/';
    try std.testing.expectEqual(@as(u32, block - 1), seek(&src, 0, .{ '*', '/' }));
}

test "sweep: seek matches the byte loop over a comment-shaped corpus" {
    const src = "/* a */ b /*c*/ /**/ * / */ end";
    for (0..src.len + 1) |at| {
        const from: u32 = @intCast(at);
        var want: u32 = from;
        while (want + 1 < src.len and !(src[want] == '*' and src[want + 1] == '/')) want += 1;
        if (want + 1 >= src.len) want = @intCast(src.len);
        try std.testing.expectEqual(want, seek(src, from, .{ '*', '/' }));
    }
}

test "sweep: find and past cross block boundaries without a seam" {
    const gpa = std.testing.allocator;
    var src: std.ArrayList(u8) = .empty;
    defer src.deinit(gpa);
    for (0..300) |i| try src.appendSlice(gpa, if (i % 7 == 0) "\n" else "ab");

    // Every newline in the file, walked by re-entering `find` past each hit,
    // has to name the same offsets the byte loop does - the seam between two
    // blocks is where a mask-based scanner drops one.
    var got: std.ArrayList(u32) = .empty;
    defer got.deinit(gpa);
    var i: u32 = 0;
    while (true) {
        const hit = find(src.items, i, "\n");
        if (hit >= src.items.len) break;
        try got.append(gpa, hit);
        i = hit + 1;
    }
    var expect: std.ArrayList(u32) = .empty;
    defer expect.deinit(gpa);
    for (src.items, 0..) |c, k| if (c == '\n') try expect.append(gpa, @intCast(k));
    try std.testing.expectEqualSlices(u32, expect.items, got.items);
}

//! The laws under the second monoid, proved rather than asserted.
//!
//! `spine.Excess` is the whole of M3 - every navigation op in the sheet is a
//! search for a target excess over it - so "this is a monoid" is not a remark,
//! it is the precondition for the tree above it meaning anything. A comment
//! saying so proves nothing, and the way this measure is wrong is not
//! spectacular: leave the empty prefix out of `min`/`max` and the identity
//! still holds on the left, associativity still holds, every hand-written case
//! still passes, and `w · identity` quietly differs from `w`. So the triples
//! here are drawn out of real random words and the laws are checked over them.
//!
//! The homomorphism is the one that matters most. `measure` is a direct running
//! scan and `compose` is arithmetic on two triples; they are different
//! computations, so `measure(uv) == measure(u) · measure(v)` over random words
//! is evidence rather than a tautology. Everything the sheet does rests on it.

const std = @import("std");
const t = std.testing;
const spine = @import("../spine/spine.zig");
const word = @import("word.zig");
const parens = @import("irregex").math.succinct.parens;

const Excess = spine.Excess;

/// Compose, and refuse to let a total monoid say no. `Tree` allows a partial
/// product and this one has no refusal to make, so an `orelse` here is a claim
/// and not a formality.
fn mul(a: Excess, b: Excess) !Excess {
    return (try Excess.compose({}, a, b)) orelse error.TotalMonoidRefused;
}

/// An arbitrary ±1 walk. Deliberately not balanced: the algebra is over the
/// free monoid on two letters and restricting the draws to forests would only
/// test the corner the sheet happens to live in.
fn run(rng: std.Random, buf: []u8) []u8 {
    for (buf) |*c| c.* = if (rng.boolean()) '(' else ')';
    return buf;
}

/// A balanced word of `n` nodes, shaped like something a parse would leave: a
/// random forest rather than a comb or a spine.
fn forest(gpa: std.mem.Allocator, rng: std.Random, n: u32) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var open: u32 = 0;
    var left = n;
    while (left > 0 or open > 0) {
        // Open while there are nodes left and either nothing is open or the
        // coin says down; otherwise close.
        if (left > 0 and (open == 0 or rng.uintLessThan(u8, 3) != 0)) {
            try out.append(gpa, '(');
            open += 1;
            left -= 1;
        } else {
            try out.append(gpa, ')');
            open -= 1;
        }
    }
    return out.toOwnedSlice(gpa);
}

test "vellum: the empty word is the identity on both sides" {
    var prng = std.Random.DefaultPrng.init(0x5EED_0001);
    const rng = prng.random();
    var buf: [64]u8 = undefined;
    for (0..2000) |_| {
        const w = word.measure(run(rng, buf[0..rng.uintLessThan(usize, 64)]));
        try t.expect(Excess.eql(try mul(Excess.identity, w), w));
        try t.expect(Excess.eql(try mul(w, Excess.identity), w));
    }
}

test "vellum: the measure is associative" {
    var prng = std.Random.DefaultPrng.init(0x5EED_0002);
    const rng = prng.random();
    var a: [24]u8 = undefined;
    var b: [24]u8 = undefined;
    var c: [24]u8 = undefined;
    for (0..4000) |_| {
        const u = word.measure(run(rng, a[0..rng.uintLessThan(usize, 24)]));
        const v = word.measure(run(rng, b[0..rng.uintLessThan(usize, 24)]));
        const z = word.measure(run(rng, c[0..rng.uintLessThan(usize, 24)]));
        try t.expect(Excess.eql(try mul(try mul(u, v), z), try mul(u, try mul(v, z))));
    }
}

test "vellum: the measure is a homomorphism from the free monoid" {
    // The law the whole structure rests on: measuring a concatenation and
    // composing two measures are the same answer, computed two different ways.
    var prng = std.Random.DefaultPrng.init(0x5EED_0003);
    const rng = prng.random();
    var buf: [128]u8 = undefined;
    for (0..4000) |_| {
        const n = rng.uintLessThan(usize, 128);
        const whole = run(rng, buf[0..n]);
        const cut = rng.uintAtMost(usize, n);
        try t.expect(Excess.eql(
            word.measure(whole),
            try mul(word.measure(whole[0..cut]), word.measure(whole[cut..])),
        ));
    }
}

test "vellum: every element is a product of the two generators" {
    // `step` is the only element that is not derived, so if folding it through
    // `compose` did not land where the direct scan lands, one of the two is
    // lying and every claim above is over the wrong object.
    var prng = std.Random.DefaultPrng.init(0x5EED_0004);
    const rng = prng.random();
    var buf: [96]u8 = undefined;
    for (0..2000) |_| {
        const w = run(rng, buf[0..rng.uintLessThan(usize, 96)]);
        var acc: Excess = .identity;
        for (w) |ch| acc = try mul(acc, Excess.step(ch == '('));
        try t.expect(Excess.eql(acc, word.measure(w)));
    }
}

test "vellum: balanced agrees with the static structure's own refusal" {
    // Two independent judges of the same question - a triple of integers here,
    // a builder that counts open depth over there. `Parens` is where the sheet
    // sends a word, so a disagreement means the sheet can be handed a word this
    // measure calls a forest and that one refuses.
    var prng = std.Random.DefaultPrng.init(0x5EED_0005);
    const rng = prng.random();
    var buf: [40]u8 = undefined;
    var forests: u32 = 0;
    for (0..4000) |_| {
        const w = run(rng, buf[0 .. 2 * rng.uintLessThan(usize, 20)]);
        const ours = word.measure(w).balanced();
        if (parens.Parens.fromShape(t.allocator, w)) |built| {
            var p = built;
            p.deinit(t.allocator);
            forests += 1;
            try t.expect(ours);
        } else |e| {
            try t.expectEqual(parens.Parens.Error.NonCanonical, e);
            try t.expect(!ours);
        }
    }
    // A run of coin flips that never once landed on a forest would pass the
    // loop above by vacuity on one arm.
    try t.expect(forests > 100);
}

test "vellum: a word maintains its measure across an amend" {
    const gpa = t.allocator;
    var prng = std.Random.DefaultPrng.init(0x5EED_0006);
    const rng = prng.random();

    const seed = try forest(gpa, rng, 2000);
    defer gpa.free(seed);
    var w = try word.Word.fromShape(gpa, seed);
    defer w.deinit();
    try w.verify();

    var mirror: std.ArrayList(u8) = .empty;
    defer mirror.deinit(gpa);
    try mirror.appendSlice(gpa, seed);

    for (0..300) |_| {
        const n: u32 = @intCast(mirror.items.len);
        const from = rng.uintAtMost(u32, n);
        const to = from + rng.uintAtMost(u32, @min(64, n - from));
        var patch: [48]u8 = undefined;
        const fresh = run(rng, patch[0..rng.uintLessThan(usize, 48)]);

        try mirror.replaceRange(gpa, from, to - from, fresh);
        try w.amend(from, to, fresh);

        // The tree against the file, after every edit, exactly as the spine's
        // own stream test does it: an incremental structure that is right at
        // the end and wrong in the middle is wrong.
        try t.expectEqualStrings(mirror.items, w.shape());
        try w.verify();
        try t.expect(Excess.eql(w.product(), word.measure(mirror.items)));
    }
}

test "vellum: excess off the spine equals a scan of the word" {
    const gpa = t.allocator;
    var prng = std.Random.DefaultPrng.init(0x5EED_0007);
    const rng = prng.random();
    const seed = try forest(gpa, rng, 1500);
    defer gpa.free(seed);
    var w = try word.Word.fromShape(gpa, seed);
    defer w.deinit();

    // Every position, not a sample: the descent crosses a leaf boundary at
    // exactly one k in `block`, and sampling is how you miss it.
    for (0..w.count() + 1) |k| {
        try t.expectEqual(word.measure(seed[0..k]).total, try w.excess(@intCast(k)));
    }
}

test "vellum: the adverse shapes a random forest never draws" {
    const gpa = t.allocator;
    // One node; a spine as deep as the corpus ever gets; a parent as wide as a
    // json array of scalars. Each is a real file and each breaks a different
    // assumption - the deep one overflows a recursive walk, the wide one is
    // where `nextSibling` is the only cheap way through.
    var deep: [2048]u8 = undefined;
    for (0..1024) |i| deep[i] = '(';
    for (1024..2048) |i| deep[i] = ')';
    var wide: [2050]u8 = undefined;
    wide[0] = '(';
    for (0..1024) |i| {
        wide[1 + 2 * i] = '(';
        wide[2 + 2 * i] = ')';
    }
    wide[2049] = ')';

    for ([_][]const u8{ "", "()", "()()", &deep, &wide }) |shape| {
        var w = try word.Word.fromShape(gpa, shape);
        defer w.deinit();
        try w.verify();
        try t.expect(w.balanced());
        var sealed = try w.seal(gpa);
        defer sealed.deinit(gpa);
        try t.expectEqual(shape.len / 2, sealed.nodeCount());
    }
}

test "vellum: a word that is not a forest is refused at the seal, not at the edit" {
    // Deliberate: an editor passes through unbalanced states on the way between
    // two balanced ones, so an amend that refused them would make the dynamic
    // form useless for the one job it has. The refusal belongs where the static
    // structure is built.
    const gpa = t.allocator;
    var w = try word.Word.fromShape(gpa, "(()())");
    defer w.deinit();
    try w.amend(1, 3, "(");
    try t.expect(!w.balanced());
    try t.expectError(parens.Parens.Error.NonCanonical, w.seal(gpa));
    try t.expectError(parens.Parens.Error.NonCanonical, w.amend(0, 0, "x"));
}

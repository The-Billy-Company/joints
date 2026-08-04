//! The test that matters: a random edit stream, checked after every edit
//! against a product computed from scratch.
//!
//! A wrong composition is silent. Nothing crashes, nothing is out of bounds, the
//! tree stays perfectly balanced, and the answer is just quietly not the parse
//! of the file - which for this package means a wrong syntax tree that looks
//! right until somebody diffs it. So this is the only test here worth much, and
//! it asserts three things after every single edit rather than one:
//!
//! 1. the leaves are exactly the leaves an independent shadow says they are;
//! 2. the maintained product equals the left-to-right fold of those leaves,
//!    which is the from-scratch answer;
//! 3. it also equals the product of a *freshly built* tree over the same
//!    leaves, whose bracketing is different - and that is the one a linear fold
//!    cannot check, because a fold assumes the associativity the tree is
//!    exploiting.
//!
//! Every edit is drawn from a fixed seed and recorded, so a failure prints a
//! reproducer; and because a recorded step is a magnitude rather than a byte
//! offset, dropping one from the middle still replays, which is what makes the
//! greedy shrink below able to hand back a minimal case instead of four thousand
//! edits with the bad one somewhere inside.

const std = @import("std");
const t = std.testing;
const spine = @import("spine.zig");
const toy = @import("toy.zig");

/// One edit, recorded as magnitudes rather than as byte offsets. That is the
/// whole reason a script can be shrunk: an offset recorded against a file that
/// no longer exists is meaningless once an earlier edit is removed, where a
/// magnitude folds onto whatever file it lands on.
const Step = struct { from: u32, span: u32, insert: u32, seed: u64 };

fn Run(comptime M: type) type {
    return struct {
        const Self = @This();
        const Sp = spine.Tree(M);
        const Leaf = Sp.Leaf;

        gpa: std.mem.Allocator,
        m: toy.Meter = .{},
        s: Sp,
        /// What the leaves ought to be, maintained by the obvious means.
        shadow: std.ArrayList(Leaf),
        /// Where a fresh tree is rebuilt for check 3. Kept rather than made per
        /// edit so its node arena is reused; a check that allocated a thousand
        /// nodes per edit would dominate the run it is checking.
        other: Sp,
        /// The minter's scratch, and deliberately a borrowed slice: that is the
        /// shape `Cursor.run` hands back, so `edit` is exercised against the
        /// lifetime a real caller has rather than a friendlier one.
        out: std.ArrayList(Leaf),
        seed: u64 = 0,
        live: u32 = 0,
        dead: u32 = 0,
        peak: u32 = 0,

        fn init(gpa: std.mem.Allocator, bytes0: u32, seed0: u64) !Self {
            var r: Self = .{
                .gpa = gpa,
                .s = Sp.init(gpa),
                .shadow = .empty,
                .other = Sp.init(gpa),
                .out = .empty,
                .seed = seed0,
            };
            const ls = try r.mint(0, bytes0);
            _ = try r.s.build(&r.m, ls);
            try r.shadow.appendSlice(gpa, ls);
            return r;
        }

        fn deinit(r: *Self) void {
            r.out.deinit(r.gpa);
            r.shadow.deinit(r.gpa);
            r.other.deinit();
            r.s.deinit();
        }

        /// Segments covering `from .. to`, drawn from this step's own seed so
        /// replaying the same script mints the same thing even when the byte
        /// range moved.
        pub fn mint(r: *Self, from: u32, to: u32) ![]const Leaf {
            var prng = std.Random.DefaultPrng.init(r.seed ^ (@as(u64, from) << 32) ^ to);
            const rng = prng.random();
            r.out.clearRetainingCapacity();
            var left = to - from;
            while (left > 0) {
                const take = 1 + rng.uintLessThan(u32, @min(left, 12));
                left -= take;
                try r.out.append(r.gpa, .{ .bytes = take, .element = M.draw(rng) });
            }
            return r.out.items;
        }

        fn apply(r: *Self, st: Step) !void {
            r.seed = st.seed;
            const n = r.s.bytes();
            const from = st.from % (n + 1);
            const cut: Sp.Cut = .{
                .from = from,
                .to = from + st.span % (n - from + 1),
                .insert = st.insert,
            };
            const span = r.s.touched(cut);
            _ = try r.s.edit(&r.m, cut, r);
            // `edit` copied the minted leaves in, so the scratch still holds
            // them and the shadow gets exactly what the tree got.
            try r.shadow.replaceRange(r.gpa, span.first, span.last - span.first, r.out.items);
        }

        fn check(r: *Self) !void {
            try t.expectEqual(@as(u32, @intCast(r.shadow.items.len)), r.s.len());
            var wide: u32 = 0;
            for (r.shadow.items, 0..) |l, i| {
                const got = r.s.at(@intCast(i));
                try t.expectEqual(l.bytes, got.bytes);
                try t.expect(Sp.same(l.element, got.element));
                wide += l.bytes;
            }
            try t.expectEqual(wide, r.s.bytes());
            try r.s.verify(&r.m);

            const scratch = try toy.fold(M, &r.m, r.shadow.items);
            try t.expect(Sp.same(r.s.product(), scratch));
            _ = try r.other.build(&r.m, r.shadow.items);
            try t.expect(Sp.same(r.s.product(), r.other.product()));

            if (r.s.product() == null) r.dead += 1 else r.live += 1;
            r.peak = @max(r.peak, r.s.len());
        }
    };
}

/// Replay a script and answer whether it still breaks. Only `OutOfMemory` is
/// re-raised, because a shrink that treated an allocator failure as the bug it
/// was hunting would hand back a reproducer for the wrong thing.
fn breaks(
    comptime M: type,
    gpa: std.mem.Allocator,
    bytes0: u32,
    seed0: u64,
    script: []const Step,
) anyerror!bool {
    var r = Run(M).init(gpa, bytes0, seed0) catch |e| {
        if (e == error.OutOfMemory) return e;
        return true;
    };
    defer r.deinit();
    for (script) |st| {
        r.apply(st) catch |e| {
            if (e == error.OutOfMemory) return e;
            return true;
        };
        r.check() catch |e| {
            if (e == error.OutOfMemory) return e;
            return true;
        };
    }
    return false;
}

/// Drop edits one at a time for as long as the failure survives, and keep
/// sweeping until a whole pass changes nothing. One pass would be cheaper but
/// would not be minimal in any sense worth stating: removing a late edit can be
/// what makes an early one droppable, so the fixpoint is what earns the claim
/// that no single remaining edit is spare.
fn shrink(
    comptime M: type,
    gpa: std.mem.Allocator,
    bytes0: u32,
    seed0: u64,
    script: *std.ArrayList(Step),
) anyerror!void {
    var moved = true;
    while (moved) {
        moved = false;
        var i: usize = 0;
        while (i < script.items.len) {
            const held = script.orderedRemove(i);
            if (try breaks(M, gpa, bytes0, seed0, script.items)) {
                moved = true;
                continue;
            }
            try script.insert(gpa, i, held);
            i += 1;
        }
    }
}

fn drive(comptime M: type, name: []const u8, seed: u64, bytes0: u32, edits: u32) anyerror!Run(M) {
    const gpa = t.allocator;
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var script: std.ArrayList(Step) = .empty;
    defer script.deinit(gpa);

    var r = try Run(M).init(gpa, bytes0, seed);
    errdefer r.deinit();

    for (0..edits) |_| {
        const st: Step = .{
            .from = rng.int(u32),
            .span = rng.int(u32),
            .insert = rng.uintLessThan(u32, 24),
            .seed = rng.int(u64),
        };
        try script.append(gpa, st);
        r.apply(st) catch |e| return confess(M, name, seed, bytes0, &script, e);
        r.check() catch |e| return confess(M, name, seed, bytes0, &script, e);
    }
    std.debug.print(
        "  {s:<6} seed 0x{X:0>16}  {d:>5} edits  {d:>5} leaves at its widest  {d} held / {d} refused\n",
        .{ name, seed, edits, r.peak, r.live, r.dead },
    );
    return r;
}

fn confess(
    comptime M: type,
    name: []const u8,
    seed: u64,
    bytes0: u32,
    script: *std.ArrayList(Step),
    e: anyerror,
) anyerror {
    std.debug.print(
        "\nspine: {s} edit stream broke at edit {d} with {s}\n  seed 0x{X:0>16}, {d} initial bytes\n",
        .{ name, script.items.len - 1, @errorName(e), seed, bytes0 },
    );
    shrink(M, t.allocator, bytes0, seed, script) catch {};
    std.debug.print("  minimal reproducer, {d} edit(s):\n", .{script.items.len});
    for (script.items, 0..) |st, i| std.debug.print(
        "    [{d}] from={d} span={d} insert={d} seed=0x{X:0>16}\n",
        .{ i, st.from, st.span, st.insert, st.seed },
    );
    return e;
}

test "spine: the maintained product equals the from-scratch product, every edit" {
    std.debug.print("\nspine: random edit streams\n", .{});

    // Three file sizes on the total monoid, because the failures differ by
    // scale: a tiny file empties out and refills constantly, where a big one
    // never leaves the deep-tree case.
    for ([_][2]u32{ .{ 64, 2000 }, .{ 4096, 2000 }, .{ 32768, 600 } }) |case| {
        var r = try drive(toy.Tally, "tally", 0x5EED_0F_5E9E17, case[0], case[1]);
        defer r.deinit();
        // Tally cannot refuse, so a run where anything went null would mean the
        // absorbing zero leaked out of the tree rather than out of the monoid.
        try t.expectEqual(@as(u32, 0), r.dead);
        try t.expectEqual(case[1], r.live);
        try t.expect(r.peak > 4);
    }

    // And the partial one, on short files, where both answers really happen.
    // Long files under a refusing monoid go null and stay null, which is honest
    // about the algebra and useless as a test.
    var r = try drive(toy.Sieve, "sieve", 0x51E7E_0F_5E9E17, 96, 2500);
    defer r.deinit();
    try t.expect(r.live > 0);
    try t.expect(r.dead > 0);
}

/// `Tally` with a rare lie in it: about one composition in a thousand forgets
/// the right operand. This is what a real bug here looks like - not a monoid
/// that is wrong everywhere, which the first edit would catch, but one that is
/// wrong on a pairing the tree happens to form and a left-to-right fold does
/// not. It exists so the shrinker is proved against the failure it was built
/// for instead of being trusted.
const Bent = struct {
    pub const Ctx = *toy.Meter;
    pub const Element = toy.Tally.Element;
    pub const identity: Element = toy.Tally.identity;
    pub const eql = toy.Tally.eql;
    pub const draw = toy.Tally.draw;

    pub fn compose(m: Ctx, a: Element, b: Element) !?Element {
        const out = (try toy.Tally.compose(m, a, b)).?;
        // Not `== 0`: the identity's hash is zero, and a lie that fired on
        // every fold's first step would be a monoid that is simply wrong.
        return if (a.hash % 1021 == 1) .{ .hash = a.hash, .span = out.span } else out;
    }
};

test "spine: a failing stream shrinks to a reproducer with nothing spare in it" {
    const gpa = t.allocator;
    const seed: u64 = 0xBAD_5EED_BAD_5EED;
    const bytes0: u32 = 64;
    const raw = 256;

    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var script: std.ArrayList(Step) = .empty;
    defer script.deinit(gpa);
    for (0..raw) |_| try script.append(gpa, .{
        .from = rng.int(u32),
        .span = rng.int(u32),
        .insert = rng.uintLessThan(u32, 24),
        .seed = rng.int(u64),
    });

    try t.expect(try breaks(Bent, gpa, bytes0, seed, script.items));
    try shrink(Bent, gpa, bytes0, seed, &script);
    try t.expect(try breaks(Bent, gpa, bytes0, seed, script.items));
    try t.expect(script.items.len < raw);

    // The claim a shrinker is worth having: every edit still in the script is
    // load-bearing, so what gets printed is a case somebody can read.
    for (0..script.items.len) |i| {
        const held = script.orderedRemove(i);
        try t.expect(!try breaks(Bent, gpa, bytes0, seed, script.items));
        try script.insert(gpa, i, held);
    }
    std.debug.print(
        "\nspine: a deliberately wrong compose broke a {d}-edit stream; shrank to {d}\n",
        .{ raw, script.items.len },
    );

    // And the same script under the honest monoid is not a failure at all,
    // which is what says the shrinker found the compose rather than the tree.
    try t.expect(!try breaks(toy.Tally, gpa, bytes0, seed, script.items));
}

/// Cuts a span into `pieces` roughly even segments, so a measurement can choose
/// whether an edit keeps the leaf count (the keystroke, which `replace` answers
/// without splitting) or has to re-segment (which it cannot).
fn Cutter(comptime Sp: type) type {
    return struct {
        pieces: u32,
        buf: [8]Sp.Leaf = undefined,

        pub fn mint(c: *@This(), from: u32, to: u32) ![]const Sp.Leaf {
            if (to == from) return &.{};
            const wide = to - from;
            const each = @max(1, wide / c.pieces);
            var left = wide;
            var n: u32 = 0;
            // `left > each` rather than `left > 0`: a last piece of zero bytes
            // is not a leaf, and a span narrower than `pieces` has to come back
            // as fewer of them.
            while (left > each and n + 1 < c.pieces) : (n += 1) {
                c.buf[n] = .{ .bytes = each, .element = .{ .hash = 0x9E37 *% (n +% wide) | 1, .span = 1 } };
                left -= each;
            }
            c.buf[n] = .{ .bytes = left, .element = .{ .hash = 0xC0FFEE *% wide | 1, .span = 1 } };
            return c.buf[0 .. n + 1];
        }
    };
}

test "spine: compositions per edit against leaf count" {
    const gpa = t.allocator;
    const Sp = spine.Tree(toy.Tally);
    const seed: u64 = 0x0B5E_C0DE_0B5E_C0DE;
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var m: toy.Meter = .{};

    const rounds = 4000;
    const wide = 4; // bytes per leaf, so a byte offset lands where intended

    std.debug.print(
        "\nspine: compositions per edit (seed 0x{X:0>16}, {d} edits per cell)\n" ++
            "  leaves  height  log2 n   splice  keystroke  resegment   splice/log2 n\n",
        .{ seed, rounds },
    );

    var n: u32 = 16;
    while (n <= 65536) : (n *= 4) {
        var s = Sp.init(gpa);
        defer s.deinit();
        const ls = try gpa.alloc(Sp.Leaf, n);
        defer gpa.free(ls);
        for (ls) |*l| l.* = .{ .bytes = wide, .element = toy.Tally.draw(rng) };
        _ = try s.build(&m, ls);
        const tall = s.height();

        m.reset();
        for (0..rounds) |_| {
            _ = try s.splice(&m, rng.uintLessThan(u32, n), .{ .bytes = wide, .element = toy.Tally.draw(rng) });
        }
        const spliced = m.composes;

        // One byte for one byte, strictly inside a leaf: one segment goes
        // stale, one replaces it, and the file's shape does not move. This is
        // the keystroke, and it is most of what an editor ever asks for.
        var one: Cutter(Sp) = .{ .pieces = 1 };
        m.reset();
        for (0..rounds) |_| {
            const p = rng.uintLessThan(u32, n) * wide + 1;
            _ = try s.edit(&m, .{ .from = p, .to = p + 1, .insert = 1 }, &one);
        }
        const keyed = m.composes;

        // The same edit straddling a segment boundary, so two segments go stale
        // and two replace them - past the one-for-one path and into a real
        // split and join.
        var two: Cutter(Sp) = .{ .pieces = 2 };
        m.reset();
        for (0..rounds) |_| {
            const p = rng.uintLessThan(u32, n - 1) * wide + wide - 1;
            _ = try s.edit(&m, .{ .from = p, .to = p + 2, .insert = 2 }, &two);
        }
        const cut = m.composes;

        const log2: f64 = @log2(@as(f64, @floatFromInt(n)));
        std.debug.print("  {d:>6}  {d:>6}  {d:>6.1}  {d:>7.1}  {d:>9.1}  {d:>9.1}  {d:>14.2}\n", .{
            n,
            tall,
            log2,
            @as(f64, @floatFromInt(spliced)) / rounds,
            @as(f64, @floatFromInt(keyed)) / rounds,
            @as(f64, @floatFromInt(cut)) / rounds,
            @as(f64, @floatFromInt(spliced)) / rounds / log2,
        });

        // A splice costs exactly the branches above the leaf, so the claim is
        // not a shape here - it is bounded by the tree's height, and an AVL
        // tree's height is bounded by 1.44 log2 n.
        try t.expect(spliced <= @as(u64, tall) * rounds);
        try t.expect(cut <= 12 * @as(u64, tall) * rounds);
    }
}

//! The two claims grain makes, held to real bytes.
//!
//! Claim one: a measurement taken with a ruling equals the measurement taken
//! without one, at **every** offset. Not on average and not on the shapes I
//! thought of - the shortcut is only worth having if it is invisible, and the
//! way to know is to ask every offset of every corpus file under both comment
//! spellings and demand the whole `Lead` back byte for byte.
//!
//! Claim two: a spliced ruling equals a rebuilt one. Same standard, and it is
//! the claim that decides whether this survives an editing session or gets
//! thrown away and rebuilt on every keystroke.
//!
//! Both are checked against generated text as well as the corpus, because the
//! corpus is well-behaved: it has no form feeds, almost no carriage returns,
//! and its continuations are all well formed. The generator is where the
//! awkward shapes come from, and it is seeded so a failure is reproducible.

const std = @import("std");
const grain = @import("grain.zig");

const Note = grain.Note;
const Ruling = grain.Ruling;

/// A file off the shelf, or `error.FileNotFound` when the tree is not
/// underfoot. Fixtures, not build inputs, so a run that cannot see them skips.
fn shelf(gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    var threaded = std.Io.Threaded.init(gpa, .{});
    defer threaded.deinit();
    return std.Io.Dir.cwd().readFileAlloc(threaded.io(), path, gpa, .limited(64 << 20));
}

const corpus = [_][]const u8{
    "research/joinery/corpus/ledger.py",
    "research/joinery/corpus/ledger.c",
    "research/joinery/corpus/ledger.rs",
    "research/joinery/corpus/ledger.go",
    "research/joinery/corpus/Ledger.java",
    "research/joinery/corpus/ledger.rb",
    "research/joinery/corpus/ledger.sh",
    "research/joinery/corpus/ledger.ts",
};

/// Text made of the shapes the ruling declines to state, so the fall-through
/// arm is exercised rather than assumed. The weights are deliberate: two
/// thirds ordinary lines, one third the awkward ones, which is far denser than
/// any real file and is the point.
fn woven(gpa: std.mem.Allocator, seed: u64, lines: usize) ![]u8 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rnd = prng.random();
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    const shapes = [_][]const u8{
        "x = 1",         "    y = 2",      "\t\tz = 3",     "",
        "   ",           "# note",         "    # note",    "/* open",
        "   */ tail",    "// line",        "a \\",          "b \\ bad",
        "  \r  carried", "\x0c  fed",      "/* /* n */ */", "s = \"# no\"",
        "  /* c */ d",   "\t # mixed",     "def f():",      "    return",
    };
    for (0..lines) |_| {
        try out.appendSlice(gpa, shapes[rnd.uintLessThan(usize, shapes.len)]);
        if (rnd.uintLessThan(u8, 8) == 0) try out.append(gpa, '\r');
        try out.append(gpa, '\n');
    }
    // A file that does not end in a newline is its own case: the last line's
    // leading run reaches the end of input, which is one of the four shapes.
    if (seed & 1 == 0) _ = out.pop();
    return out.toOwnedSlice(gpa);
}

/// Every offset, both arms, whole `Lead` compared.
fn agrees(gpa: std.mem.Allocator, text: []const u8, note: Note) !void {
    var r = try Ruling.of(gpa, text);
    defer r.deinit(gpa);
    for (0..text.len + 1) |o| {
        const at: u32 = @intCast(o);
        const cold = grain.lead(text, at, note, null);
        const warm = grain.lead(text, at, note, &r);
        std.testing.expectEqual(cold, warm) catch |e| {
            std.debug.print("grain: lead disagreed at {d} of {d} under {s}\n", .{ at, text.len, @tagName(note) });
            return e;
        };
    }
}

test "grain: a ruled measurement equals the byte walk on the corpus" {
    const gpa = std.testing.allocator;
    var read: usize = 0;
    for (corpus) |path| {
        const text = shelf(gpa, path) catch |e| {
            if (e == error.FileNotFound) continue;
            return e;
        };
        defer gpa.free(text);
        read += 1;
        for ([_]Note{ .hash, .slashes }) |note| try agrees(gpa, text, note);
    }
    // A corpus test that read nothing passes by doing nothing. The tree is not
    // always underfoot, so this is a skip rather than a failure - but it says
    // so instead of reporting green.
    if (read == 0) return error.SkipZigTest;
}

test "grain: a ruled measurement equals the byte walk on awkward generated text" {
    const gpa = std.testing.allocator;
    for (0..8) |s| {
        const text = try woven(gpa, 0x6_A1_11 ^ @as(u64, s), 40);
        defer gpa.free(text);
        for ([_]Note{ .hash, .slashes }) |note| try agrees(gpa, text, note);
    }
}

test "grain: a spliced ruling equals a rebuilt one over a stream of edits" {
    const gpa = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(0x5911CE_0001);
    const rnd = prng.random();
    const inserts = [_][]const u8{ "", "x", "\n", "\n\n", "    ", "\t# c\n", "/* q */", "\r\n  z" };

    for (0..2) |round| {
        const seed = try woven(gpa, 0xF1B4E + @as(u64, round), 30);
        defer gpa.free(seed);

        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(gpa);
        try text.appendSlice(gpa, seed);

        var live = try Ruling.of(gpa, text.items);
        defer live.deinit(gpa);

        for (0..300) |_| {
            const n: u32 = @intCast(text.items.len);
            const from = if (n == 0) 0 else rnd.uintLessThan(u32, n + 1);
            const to = from + if (n == from) 0 else rnd.uintLessThan(u32, @min(n - from, 12) + 1);
            const insert = inserts[rnd.uintLessThan(usize, inserts.len)];
            const cut: grain.Cut = .{ .from = from, .to = to, .insert = @intCast(insert.len) };

            try text.replaceRange(gpa, from, to - from, insert);
            try live.splice(gpa, text.items, cut);

            var cold = try Ruling.of(gpa, text.items);
            defer cold.deinit(gpa);
            try std.testing.expectEqualSlices(grain.Line, cold.lines.items, live.lines.items);
        }
    }
}

test "grain: a ruling refuses to answer about bytes it does not describe" {
    // The hazard that made `covers` an identity check rather than a length
    // one: a scanner reads many files and a ruling left over from the last is
    // exactly the shape that answers confidently and wrongly. Refusing by
    // construction is what lets `weave` install one and leave it installed.
    const gpa = std.testing.allocator;
    const one = "  a\n    b\n";
    const two = "        c\n  d\n";
    var r = try Ruling.of(gpa, one);
    defer r.deinit(gpa);
    try std.testing.expect(r.covers(one));
    try std.testing.expect(!r.covers(two));
    try std.testing.expectEqual(grain.lead(two, 0, .hash, null), grain.lead(two, 0, .hash, &r));
}

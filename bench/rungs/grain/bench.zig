//! Grain — is one pass over the raw material cheaper than the walk it replaces?
//!
//! Three arms, and the third is the only one that needs an index:
//!
//!   1. **`walk`** — the control. A verbatim transcription of the byte-at-a-time
//!      measurement `kernel/lex/hand/offside.zig` carried before this landed,
//!      kept here because deleting the original is the point and a rung with no
//!      baseline measures nothing. It is not reachable from the library and it
//!      is not a second implementation to keep in step - if it drifts from the
//!      other two, `agree` below fails the run before a single trial is timed.
//!   2. **`sweep`** — the same measurement with its inner scans vectorized and
//!      no index at all. This is what every caller gets for free today.
//!   3. **`ruled`** — the same measurement again, reading a `grain.Ruling`.
//!
//! Four sections, and two of them can embarrass the design:
//!
//!   * **`lead`** — nanoseconds a measurement, all three arms over one shuffled
//!     tour of the same offsets. The row that matters is `ruled` against
//!     `sweep`, because that is the one the index has to pay for.
//!   * **`build`** — what the index costs to raise, in nanoseconds a byte, and
//!     the break-even: how many measurements a file has to be asked for before
//!     the pre-pass has paid for itself. A file read once and closed never gets
//!     there, and the number says how far off it is.
//!   * **`edit`** — microseconds a keystroke, splicing the ruling against
//!     rebuilding it. This is the section that decides whether the index is an
//!     editor's or only a batch reader's.
//!   * **`shapes`** — generated text chosen to make each arm lose. A board that
//!     printed only the corpus would be advertising: real source is 3-5%
//!     newlines with four-byte indents, which is close to the worst case for a
//!     64-byte block and close to the best case for skipping a run of them.
//!
//! Min-of-N across interleaved rounds, the arms alternating within a round
//! rather than running in blocks, so a coworker agent's build landing halfway
//! through hits all three. Every arm's answers are summed and the sum is
//! carried out of the loop, because a measurement whose result is discarded is
//! a measurement the optimizer deletes.
//!
//! The floors at the bottom are assertions rather than prints, and they are why
//! this is a rung and not a script: an index that stopped being cheaper to
//! splice than to rebuild, or a vectorized walk that got slower than the byte
//! loop it replaced, exits nonzero here. The `ruled`-against-`sweep` ratio is
//! deliberately *not* floored - see the note above that table.

const std = @import("std");
const joints = @import("joints");

const grain = joints.kernel.grain;
const Note = grain.Note;
const Lead = grain.Lead;
const Ruling = grain.Ruling;
/// The house stopwatch, on the awake clock — the same instrument the vellum
/// rung reads, so two boards printing nanoseconds are printing the same unit.
const Span = joints.assay.Span;

/// Min-of-N. Interference only ever slows a trial.
const trials = 7;
/// Measurements per timed arm. Enough that the timer's resolution is noise.
const probes = 100_000;

const tab_stop = grain.tab_stop;

// ── the control: the byte walk, as it stood before grain ────────────────────

/// Whether a comment opens at `bytes[i]`, and how wide its opener is.
fn opens(n: Note, bytes: []const u8, i: u32) ?struct { u32, bool } {
    return switch (n) {
        .hash => if (bytes[i] == '#') .{ 1, false } else null,
        .slashes => blk: {
            if (bytes[i] != '/' or i + 1 >= bytes.len) break :blk null;
            break :blk switch (bytes[i + 1]) {
                '/' => .{ 2, false },
                '*' => .{ 2, true },
                else => null,
            };
        },
    };
}

fn walked(bytes: []const u8, at: u32, note: Note) Lead {
    var i = at;
    var column: u16 = 0;
    var fresh = false;
    var comment: ?u16 = null;
    while (i < bytes.len) switch (bytes[i]) {
        '\n' => {
            fresh = true;
            column = 0;
            i += 1;
        },
        ' ' => {
            column +|= 1;
            i += 1;
        },
        '\r', 0x0c => {
            column = 0;
            i += 1;
        },
        '\t' => {
            column = (column / tab_stop +| 1) *| tab_stop;
            i += 1;
        },
        '#', '/' => {
            const open = opens(note, bytes, i) orelse
                return .{ .at = i, .column = column, .fresh = fresh, .comment = comment, .broken = false };
            if (!fresh) return .{ .at = i, .column = column, .fresh = false, .comment = null, .broken = false };
            if (comment == null) comment = column;
            const width, const bounded = open;
            if (bounded) {
                column +|= @intCast(width);
                i = bored(bytes, i + width, &column);
            } else {
                while (i < bytes.len and bytes[i] != '\n') i += 1;
                if (i < bytes.len) i += 1;
                column = 0;
            }
        },
        '\\' => {
            var j = i + 1;
            if (j < bytes.len and bytes[j] == '\r') j += 1;
            if (j >= bytes.len) return .{ .at = j, .column = column, .fresh = fresh, .comment = comment, .broken = false };
            if (bytes[j] != '\n') return .{ .at = i, .column = column, .fresh = fresh, .comment = comment, .broken = true };
            i = j + 1;
            column = 0;
        },
        else => return .{ .at = i, .column = column, .fresh = fresh, .comment = comment, .broken = false },
    };
    return .{ .at = i, .column = 0, .fresh = true, .comment = comment, .broken = false };
}

/// The control's bounded-comment traversal, byte at a time.
fn bored(bytes: []const u8, from: u32, column: *u16) u32 {
    var i = from;
    var depth: u32 = 1;
    while (i < bytes.len) {
        if (bytes[i] == '\n') {
            column.* = 0;
            i += 1;
            continue;
        }
        if (i + 1 < bytes.len and bytes[i] == '/' and bytes[i + 1] == '*') {
            depth += 1;
            column.* +|= 2;
            i += 2;
            continue;
        }
        if (i + 1 < bytes.len and bytes[i] == '*' and bytes[i + 1] == '/') {
            depth -= 1;
            column.* +|= 2;
            i += 2;
            if (depth == 0) return i;
            continue;
        }
        column.* = if (bytes[i] == '\t') (column.* / tab_stop +| 1) *| tab_stop else column.* +| 1;
        i += 1;
    }
    return i;
}

// ── the board ───────────────────────────────────────────────────────────────

const Board = struct {
    gpa: std.mem.Allocator,
    tag: []const u8,
    note: Note,
    src: []const u8,
    owned: bool,
    ruling: Ruling,
    /// The offsets all three arms measure. Two orders, because the order is
    /// the finding: `tour` is every line start in the order the file has them,
    /// which is the order a scanner asks in, and `jumbled` is the same set
    /// shuffled, which is the order an editor jumping around asks in. The
    /// byte arms cannot tell the difference and the ruling's memo can, so a
    /// board printing only one of them would be choosing the answer.
    tour: []u32,
    jumbled: []u32,

    fn of(gpa: std.mem.Allocator, tag: []const u8, src: []const u8, owned: bool, note: Note) !*Board {
        const b = try gpa.create(Board);
        errdefer gpa.destroy(b);
        b.* = .{
            .gpa = gpa,
            .tag = tag,
            .note = note,
            .src = src,
            .owned = owned,
            .ruling = try Ruling.of(gpa, src),
            .tour = try gpa.alloc(u32, probes),
            .jumbled = try gpa.alloc(u32, probes),
        };
        errdefer gpa.free(b.tour);
        errdefer gpa.free(b.jumbled);

        // Line starts, which is where the layout hand is actually asked - it
        // runs on a fresh line and nowhere else. Drawing uniformly over bytes
        // would spend most of the tour mid-token measuring nothing.
        const lines = b.ruling.lines.items;
        for (b.tour, 0..) |*v, n| v.* = lines[n % lines.len].start;
        var prng = std.Random.DefaultPrng.init(0x64_A1_11_0001);
        const rng = prng.random();
        for (b.jumbled) |*v| v.* = lines[rng.uintLessThan(usize, lines.len)].start;
        return b;
    }

    fn deinit(b: *Board) void {
        const gpa = b.gpa;
        gpa.free(b.jumbled);
        gpa.free(b.tour);
        b.ruling.deinit(gpa);
        if (b.owned) gpa.free(b.src);
        gpa.destroy(b);
    }

    /// No arm is timed until all three agree at every offset of the file, not
    /// merely at the offsets the tour happens to draw. A fast wrong answer is
    /// not a result, and a control that has drifted is worse than no control.
    fn agree(b: *Board) !void {
        for (0..b.src.len + 1) |o| {
            const at: u32 = @intCast(o);
            const control = walked(b.src, at, b.note);
            if (!std.meta.eql(control, grain.lead(b.src, at, b.note, null))) return error.SweepDisagrees;
            if (!std.meta.eql(control, grain.lead(b.src, at, b.note, &b.ruling))) return error.RulingDisagrees;
        }
    }
};

const Arm = enum { walk, sweep, ruled };

fn once(b: *Board, arm: Arm, at: u32) Lead {
    return switch (arm) {
        .walk => walked(b.src, at, b.note),
        .sweep => grain.lead(b.src, at, b.note, null),
        .ruled => grain.lead(b.src, at, b.note, &b.ruling),
    };
}

const Row = struct { walk: f64, sweep: f64, ruled: f64 };

fn race(b: *Board, io: std.Io, order: enum { tour, jumbled }) !Row {
    const asks = switch (order) {
        .tour => b.tour,
        .jumbled => b.jumbled,
    };
    var best = [_]i128{std.math.maxInt(i128)} ** 3;
    var sum: u64 = 0;
    for (0..trials) |_| {
        inline for (.{ Arm.walk, Arm.sweep, Arm.ruled }, 0..) |arm, k| {
            const sp = Span.open(io);
            var acc: u64 = 0;
            for (asks) |at| acc +%= once(b, arm, at).at;
            best[k] = @min(best[k], sp.read(io).ns());
            sum +%= acc;
        }
    }
    std.mem.doNotOptimizeAway(sum);
    const each: f64 = @floatFromInt(asks.len);
    return .{
        .walk = @as(f64, @floatFromInt(best[0])) / each,
        .sweep = @as(f64, @floatFromInt(best[1])) / each,
        .ruled = @as(f64, @floatFromInt(best[2])) / each,
    };
}

/// What the index costs to raise, per byte of the file it describes.
fn raise(b: *Board, io: std.Io) !f64 {
    var best: i128 = std.math.maxInt(i128);
    for (0..trials) |_| {
        const sp = Span.open(io);
        var r = try Ruling.of(b.gpa, b.src);
        best = @min(best, sp.read(io).ns());
        r.deinit(b.gpa);
    }
    return @as(f64, @floatFromInt(best)) / @as(f64, @floatFromInt(@max(1, b.src.len)));
}

/// One keystroke: splicing the ruling against rebuilding it. The edit is a
/// single character in the middle of the file, which is the shape an editing
/// session is made of and the shape a rebuild is worst at.
fn keystroke(b: *Board, io: std.Io, out: *std.Io.Writer) !void {
    const gpa = b.gpa;
    if (b.src.len < 4) return;
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(gpa);
    try text.appendSlice(gpa, b.src);
    const cut: u32 = @intCast(text.items.len / 2);

    var rebuild: i128 = std.math.maxInt(i128);
    for (0..trials) |_| {
        const sp = Span.open(io);
        var r = try Ruling.of(gpa, text.items);
        rebuild = @min(rebuild, sp.read(io).ns());
        r.deinit(gpa);
    }

    var live = try Ruling.of(gpa, text.items);
    defer live.deinit(gpa);
    var splice: i128 = std.math.maxInt(i128);
    for (0..trials) |_| {
        try text.replaceRange(gpa, cut, 0, "x");
        const sp = Span.open(io);
        try live.splice(gpa, text.items, .{ .from = cut, .to = cut, .insert = 1 });
        splice = @min(splice, sp.read(io).ns());
        try text.replaceRange(gpa, cut, 1, "");
        try live.splice(gpa, text.items, .{ .from = cut, .to = cut + 1, .insert = 0 });
    }

    const us = 1000.0;
    try out.print("  {s:<10} {d:>8} {d:>14.3} {d:>14.3} {d:>11.1}x\n", .{
        b.tag,
        b.ruling.lines.items.len,
        @as(f64, @floatFromInt(rebuild)) / us,
        @as(f64, @floatFromInt(splice)) / us,
        @as(f64, @floatFromInt(rebuild)) / @as(f64, @floatFromInt(@max(1, splice))),
    });
    if (splice >= rebuild) return error.SpliceStoppedBeingCheaperThanRebuild;
}

// ── generated shapes, chosen to make an arm lose ────────────────────────────

const Shape = struct {
    tag: []const u8,
    note: Note,
    /// One line, repeated. The whole point of each row is what this looks like.
    line: []const u8,
    lines: usize,
};

const shapes = [_]Shape{
    // The worst case for the vectorized arm and the flattest for the index: a
    // four-byte indent then code. There is nothing to skip, the run ends in the
    // first four lanes of a 64-byte load, and the ruling's binary search is
    // pure overhead on top.
    .{ .tag = "tight", .note = .hash, .line = "    x = 1\n", .lines = 4000 },
    // A wide indent, which is where a block compare starts earning its load.
    .{ .tag = "deep", .note = .hash, .line = "                                        x = 1\n", .lines = 4000 },
    // The case the index exists for: a run of comment lines the measurement
    // has to see past. The byte walk reads every one of those bytes.
    .{ .tag = "prose", .note = .hash, .line = "# a sentence of ordinary prose in a comment\n", .lines = 4000 },
    // And the same run, blank. Cheapest possible per line for every arm, so
    // the ratio here is the index's ceiling rather than its typical.
    .{ .tag = "blank", .note = .hash, .line = "\n", .lines = 4000 },
    // A bounded comment per line, which is the arm `through` owns.
    .{ .tag = "bounded", .note = .slashes, .line = "  /* a bounded comment */ x\n", .lines = 4000 },
};

fn woven(gpa: std.mem.Allocator, s: Shape) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    for (0..s.lines) |_| try out.appendSlice(gpa, s.line);
    return out.toOwnedSlice(gpa);
}

// ── the corpus ──────────────────────────────────────────────────────────────

const Pair = struct { tag: []const u8, path: []const u8, note: Note };

const corpus = [_]Pair{
    .{ .tag = "python", .path = "research/joinery/corpus/ledger.py", .note = .hash },
    .{ .tag = "ruby", .path = "research/joinery/corpus/ledger.rb", .note = .hash },
    .{ .tag = "shell", .path = "research/joinery/corpus/ledger.sh", .note = .hash },
    .{ .tag = "c", .path = "research/joinery/corpus/ledger.c", .note = .slashes },
    .{ .tag = "rust", .path = "research/joinery/corpus/ledger.rs", .note = .slashes },
    .{ .tag = "go", .path = "research/joinery/corpus/ledger.go", .note = .slashes },
    .{ .tag = "java", .path = "research/joinery/corpus/Ledger.java", .note = .slashes },
    .{ .tag = "ts", .path = "research/joinery/corpus/ledger.ts", .note = .slashes },
    // Two real files big enough for the crossover to be visible. The joinery
    // fixtures are the shapes the lexer is *tested* against and they are a
    // kilobyte apiece, which is below the size at which any index can repay
    // its own lookup - a board carrying only those would report a loss that is
    // really a fact about the fixture. These two are the package's own largest
    // source files, under both comment spellings.
    .{ .tag = "outside", .path = "src/kernel/lex/outside.zig", .note = .slashes },
    .{ .tag = "standing", .path = "tool/standing.py", .note = .hash },
};

fn shelf(gpa: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 << 20));
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var buf: [1 << 16]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &buf);
    const out = &stdout.interface;
    defer out.flush() catch {};

    var boards: std.ArrayList(*Board) = .empty;
    defer {
        for (boards.items) |b| b.deinit();
        boards.deinit(gpa);
    }

    try out.print("\ngrain — one pass over the material against the walk it replaces\n\n", .{});

    for (corpus) |p| {
        const src = shelf(gpa, io, p.path) catch |e| {
            try out.print("  {s:<10} skipped ({s})\n", .{ p.tag, @errorName(e) });
            continue;
        };
        const b = try Board.of(gpa, p.tag, src, true, p.note);
        try boards.append(gpa, b);
    }
    for (shapes) |s| {
        const src = try woven(gpa, s);
        const b = try Board.of(gpa, s.tag, src, true, s.note);
        try boards.append(gpa, b);
    }
    if (boards.items.len == 0) return error.NothingToMeasure;

    for (boards.items) |b| try b.agree();

    var worst_sweep: f64 = 0;
    inline for (.{ .tour, .jumbled }, .{
        "lead in order  nanoseconds a measurement, line after line, as a scanner asks",
        "lead jumbled   the same asks in a shuffled order, as an editor asks",
    }) |order, caption| {
        try out.print("{s}\n", .{caption});
        try out.print("  {s:<10} {s:>8} {s:>10} {s:>10} {s:>10} {s:>10} {s:>10}\n", .{
            "file", "lines", "walk ns", "sweep ns", "ruled ns", "vs walk", "vs sweep",
        });
        for (boards.items) |b| {
            const r = try race(b, io, order);
            worst_sweep = @max(worst_sweep, r.sweep / r.walk);
            try out.print("  {s:<10} {d:>8} {d:>10.1} {d:>10.1} {d:>10.1} {d:>9.2}x {d:>9.2}x\n", .{
                b.tag,
                b.ruling.lines.items.len,
                r.walk,
                r.sweep,
                r.ruled,
                r.walk / r.sweep,
                r.sweep / r.ruled,
            });
        }
        try out.print("\n", .{});
    }

    try out.print("build  what the index costs to raise, and how many in-order asks repay it\n", .{});
    try out.print("  {s:<10} {s:>10} {s:>12} {s:>16}\n", .{ "file", "bytes", "ns a byte", "break-even asks" });
    for (boards.items) |b| {
        const per = try raise(b, io);
        const cost = per * @as(f64, @floatFromInt(b.src.len));
        const r = try race(b, io, .tour);
        const saved = r.sweep - r.ruled;
        // A shape where the index saves nothing per ask never repays its
        // pre-pass, and saying "never" is more use than a large number.
        var repay: [32]u8 = undefined;
        const asks = if (saved <= 0) "never" else try std.fmt.bufPrint(&repay, "{d:.0}", .{cost / saved});
        try out.print("  {s:<10} {d:>10} {d:>12.3} {s:>16}\n", .{ b.tag, b.src.len, per, asks });
    }

    try out.print("\nedit   microseconds a keystroke, rebuild the ruling against splice it\n", .{});
    try out.print("  {s:<10} {s:>8} {s:>14} {s:>14} {s:>12}\n", .{ "file", "lines", "rebuild us", "splice us", "ratio" });
    for (boards.items) |b| try keystroke(b, io, out);

    // The one floor on a timing here, and it is deliberately the loose one: a
    // vectorized walk that is slower than the byte loop on *every* shape means
    // the block size or the load is wrong, where losing on one narrow shape is
    // a fact about that shape. The `ruled` arm gets no floor at all, because
    // whether an index repays itself depends on how many times the file is
    // asked, and a wall-clock gate that cries wolf teaches you to stop reading
    // the board.
    if (worst_sweep > 4.0) return error.VectorizedWalkLostEverywhere;
    try out.print("\n", .{});
}

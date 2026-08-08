//! Cursor — what the neighbourhood accessors cost, against the walks they were.
//!
//! Every accessor `Quire` grew this wave existed already as a private helper in
//! `vellum/sheet_test.zig`, written the slow obviously-correct way to check the
//! settled tree's clever way. So the honest question is not "is it fast", it is
//! **what did making it public change** - and for most rows the answer is
//! nothing, because the public accessor IS that walk, moved. Those rows read
//! `1.0x` and they are the point: a matcher can now call a proven walk instead
//! of writing a fifth one.
//!
//! Four sections, and three of them can embarrass the change:
//!
//!   1. **`reach`** — nanoseconds an op, the oracle walk against the accessor,
//!      one row each. Two rows are not the same algorithm and are where a real
//!      claim lives: `descendant_for_byte_range` bisects a sibling run the
//!      oracle scans, and the gap only opens on a wide parent - which is why
//!      the slate carries one no corpus file contains.
//!   2. **`vellum`** — the same op asked of the live tree and of the settled
//!      one, because a matcher has to choose a representation. Two rows here
//!      have a published shape to reproduce rather than discover: the sheet's
//!      `parent` is ~29x slower than a stored back-pointer and its `depth` is
//!      ~9x faster than a climb. A table where both favoured one side would
//!      mean the harness was wrong.
//!   3. **`lift`** — the two accessors that changed on the PARSE path, spelled
//!      the old inline way against the new free-function way. Nothing else this
//!      wave touched is reachable from `warp`, so this row is the whole of the
//!      "did the lift cost anything" question, asked directly instead of
//!      inferred from a noisier end-to-end number.
//!   4. **`flat`** — a cold parse and a keystroke, per byte and per edit. Not
//!      compared to anything: it is the baseline this rung exists to hold from
//!      now on, so the next change to this path has a number to regress against.
//!
//! House rules from `bench/README.md` apply: both arms over the same shuffled
//! tour drawn once, interleaved within a round so a thermal drift lands on both,
//! min-of-N because interference only ever slows a trial, every answer consumed,
//! and every op cross-checked against its oracle on every node before a single
//! trial is timed. A fast wrong answer is not a result - and unlike the timings,
//! that check is an assertion: a disagreement exits nonzero.

const std = @import("std");
const joints = @import("joints");

const press = joints.press;
const lex = joints.kernel.lex.scanner;
const quire = joints.kernel.quire;
const vellum = joints.kernel.vellum;
const weave = joints.kernel.weave;
const Span = joints.assay.Span;

/// Min-of-N. Interference only ever slows a trial.
const trials = 7;
/// Nodes visited per timed op. Enough that the timer's resolution is noise.
const visits = 50_000;

const Pair = struct { tag: []const u8, grammar: []const u8, file: []const u8 };

const slate = [_]Pair{
    .{ .tag = "json", .grammar = "test/grammar/json.json", .file = "research/joinery/corpus/ledger.json" },
    .{ .tag = "big-json", .grammar = "test/grammar/json.json", .file = "upstream/grammars/verilog.json" },
    .{ .tag = "huge-json", .grammar = "test/grammar/json.json", .file = "upstream/grammars/scala.json" },
};

/// The shape the corpus does not have. A sibling step and a byte-range descent
/// are both linear in a parent's width, and every real file's widest parent is
/// a few dozen children - so a table built only on the corpus would report that
/// the bisection bought nothing, which is true of the corpus and false of the
/// structure. json's array is the cheapest way to write one parent this wide.
const wide_kids = 20_000;

fn wideSource(gpa: std.mem.Allocator) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.append(gpa, '[');
    for (0..wide_kids) |i| {
        if (i != 0) try out.append(gpa, ',');
        try out.append(gpa, '1');
    }
    try out.append(gpa, ']');
    return out.toOwnedSlice(gpa);
}

/// One file, pressed and parsed, both representations, and the visit order both
/// arms read.
const Board = struct {
    gpa: std.mem.Allocator,
    tag: []const u8,
    gr: press.Grammar,
    built: press.Result,
    scanner: lex.Scanner,
    gather: quire.Gather,
    src: []u8,
    q: quire.Quire,
    sheet: vellum.Sheet,
    /// Preorder index to the quire's ref, and to the sheet's spot.
    refs: []quire.Ref,
    spots: []vellum.Spot,
    /// The order both arms walk, shuffled once.
    tour: []u32,
    /// One field name the grammar declares, so the field row asks a real
    /// question rather than a miss on every node.
    field: []const u8,

    fn of(gpa: std.mem.Allocator, tag: []const u8, grammar_path: []const u8, src: []u8) !*Board {
        const b = try gpa.create(Board);
        errdefer gpa.destroy(b);
        b.gpa = gpa;
        b.tag = tag;
        b.src = src;
        const grammar = try shelf(gpa, grammar_path);
        defer gpa.free(grammar);
        b.gr = try press.treeSitter(gpa, grammar);
        errdefer b.gr.deinit();
        b.built = try press.tables(gpa, &b.gr);
        errdefer b.built.deinit();
        b.scanner = (try lex.Scanner.compile(gpa, &b.gr)) orelse return error.NothingLexable;
        errdefer b.scanner.deinit();
        b.gather = try quire.Gather.init(gpa, &b.gr, &b.built.collection, &b.built.tables, &b.scanner);
        errdefer b.gather.deinit();
        b.q = try b.gather.run(b.src);
        errdefer b.q.deinit();
        b.sheet = try vellum.settle(gpa, &b.q);
        errdefer b.sheet.deinit();
        b.field = if (b.gr.field_names.len == 0) "" else b.gr.field_names[0];

        // Preorder, this rung's own way, so the two arms are indexed by one
        // walk rather than by each other.
        const n = b.sheet.count();
        b.refs = try gpa.alloc(quire.Ref, n);
        errdefer gpa.free(b.refs);
        b.spots = try gpa.alloc(vellum.Spot, n);
        errdefer gpa.free(b.spots);
        var stack: std.ArrayList(struct { ref: quire.Ref, kid: u32 }) = .empty;
        defer stack.deinit(gpa);
        var seen: u32 = 0;
        var bit: u32 = 0;
        var next_root: usize = 0;
        while (true) {
            if (stack.items.len == 0) {
                if (next_root == b.q.roots.len) break;
                const r = b.q.roots[next_root];
                next_root += 1;
                b.refs[seen] = r;
                b.spots[seen] = bit;
                seen += 1;
                bit += 1;
                try stack.append(gpa, .{ .ref = r, .kid = 0 });
                continue;
            }
            const top = stack.items.len - 1;
            const held = stack.items[top];
            const kids = b.q.children(held.ref);
            if (held.kid == kids.len) {
                bit += 1;
                _ = stack.pop();
                continue;
            }
            stack.items[top].kid += 1;
            b.refs[seen] = kids[held.kid];
            b.spots[seen] = bit;
            seen += 1;
            bit += 1;
            try stack.append(gpa, .{ .ref = kids[held.kid], .kid = 0 });
        }
        if (seen != n) return error.WalkDisagrees;

        b.tour = try gpa.alloc(u32, visits);
        errdefer gpa.free(b.tour);
        var prng = std.Random.DefaultPrng.init(0xC0_5A_0007);
        const rng = prng.random();
        for (b.tour) |*v| v.* = rng.uintLessThan(u32, @max(1, n));
        return b;
    }

    fn deinit(b: *Board) void {
        const gpa = b.gpa;
        gpa.free(b.tour);
        gpa.free(b.spots);
        gpa.free(b.refs);
        b.sheet.deinit();
        b.q.deinit();
        b.gather.deinit();
        b.scanner.deinit();
        b.built.deinit();
        b.gr.deinit();
        gpa.free(b.src);
        gpa.destroy(b);
    }
};

// ── the oracle arm: the private walks from `vellum/sheet_test.zig`, verbatim ──
//
// Copied rather than imported, because a rung cannot reach a test file and must
// not become one. If either spelling drifts the cross-check below stops passing,
// which is the property that makes the copy safe to keep.

fn depthOf(q: *const quire.Quire, ref: quire.Ref) u32 {
    var d: u32 = 0;
    var at = q.nodes[ref].parent;
    while (at != quire.none) : (at = q.nodes[at].parent) d += 1;
    return d;
}

fn sizeOf(gpa: std.mem.Allocator, q: *const quire.Quire, ref: quire.Ref, stack: *std.ArrayList(quire.Ref)) !u32 {
    stack.clearRetainingCapacity();
    try stack.append(gpa, ref);
    var n: u32 = 0;
    while (stack.pop()) |at| {
        n += 1;
        for (q.children(at)) |c| try stack.append(gpa, c);
    }
    return n;
}

fn afterOf(q: *const quire.Quire, ref: quire.Ref) ?quire.Ref {
    const p = q.nodes[ref].parent;
    const among = if (p == quire.none) q.roots else q.children(p);
    for (among, 0..) |c, i| if (c == ref) return if (i + 1 < among.len) among[i + 1] else null;
    return null;
}

fn beforeOf(q: *const quire.Quire, ref: quire.Ref) ?quire.Ref {
    const p = q.nodes[ref].parent;
    const among = if (p == quire.none) q.roots else q.children(p);
    for (among, 0..) |c, i| if (c == ref) return if (i > 0) among[i - 1] else null;
    return null;
}

fn namedAfterOf(q: *const quire.Quire, ref: quire.Ref) ?quire.Ref {
    var at = ref;
    while (afterOf(q, at)) |n| : (at = n) if (q.isNamed(n)) return n;
    return null;
}

fn namedBeforeOf(q: *const quire.Quire, ref: quire.Ref) ?quire.Ref {
    var at = ref;
    while (beforeOf(q, at)) |p| : (at = p) if (q.isNamed(p)) return p;
    return null;
}

fn fieldOf(q: *const quire.Quire, ref: quire.Ref, want: []const u8) ?quire.Ref {
    if (want.len == 0) return null;
    for (q.children(ref)) |c| if (q.field(c)) |f| {
        if (std.mem.eql(u8, f, want)) return c;
    };
    return null;
}

/// The descent a scan gives, which is the shape a matcher would write by hand:
/// walk the run looking for the first node covering the range, then recur.
fn coverOf(q: *const quire.Quire, from: u32, to: u32) ?quire.Ref {
    var found: ?quire.Ref = null;
    var run = q.roots;
    outer: while (true) {
        for (run) |c| {
            const n = q.nodes[c];
            if (n.start <= from and to <= n.end()) {
                found = c;
                run = q.children(c);
                continue :outer;
            }
        }
        return found;
    }
}

// ── the table ───────────────────────────────────────────────────────────────

const Op = enum {
    parent,
    next_sibling,
    prev_sibling,
    next_named_sibling,
    prev_named_sibling,
    child_by_field_name,
    depth,
    subtree_size,
    descendant_for_byte_range,
};

/// A `u64` so a row's answers can be summed and consumed. Absence is zero,
/// which collides with ref zero and is fine: this is a checksum, not an answer.
fn oracle(b: *Board, comptime op: Op, i: u32, stack: *std.ArrayList(quire.Ref)) !u64 {
    const q = &b.q;
    const ref = b.refs[i];
    return switch (op) {
        .parent => if (q.nodes[ref].parent == quire.none) 0 else q.nodes[ref].parent,
        .next_sibling => afterOf(q, ref) orelse 0,
        .prev_sibling => beforeOf(q, ref) orelse 0,
        .next_named_sibling => namedAfterOf(q, ref) orelse 0,
        .prev_named_sibling => namedBeforeOf(q, ref) orelse 0,
        .child_by_field_name => fieldOf(q, ref, b.field) orelse 0,
        .depth => depthOf(q, ref),
        .subtree_size => try sizeOf(b.gpa, q, ref, stack),
        .descendant_for_byte_range => coverOf(q, q.nodes[ref].start, q.nodes[ref].end()) orelse 0,
    };
}

fn reached(b: *Board, comptime op: Op, i: u32) !u64 {
    const q = &b.q;
    const ref = b.refs[i];
    return switch (op) {
        .parent => q.parent(ref) orelse 0,
        .next_sibling => q.nextSibling(ref) orelse 0,
        .prev_sibling => q.prevSibling(ref) orelse 0,
        .next_named_sibling => q.nextNamedSibling(ref) orelse 0,
        .prev_named_sibling => q.prevNamedSibling(ref) orelse 0,
        .child_by_field_name => if (b.field.len == 0) 0 else q.childByFieldName(ref, b.field) orelse 0,
        .depth => q.depth(ref),
        .subtree_size => try q.subtreeSize(b.gpa, ref),
        .descendant_for_byte_range => q.descendantForByteRange(q.nodes[ref].start, q.nodes[ref].end()) orelse 0,
    };
}

const Row = struct { was_ns: f64, now_ns: f64, sum: u64 };

/// Both arms over the same tour, interleaved, min of `trials`. Checked on every
/// node of the tree first - not on the tour, which samples.
fn race(b: *Board, io: std.Io, comptime op: Op) !Row {
    var stack: std.ArrayList(quire.Ref) = .empty;
    defer stack.deinit(b.gpa);

    for (b.refs, 0..) |_, i| {
        const want = try oracle(b, op, @intCast(i), &stack);
        if (want != try reached(b, op, @intCast(i))) return error.AccessorDisagreesWithOracle;
    }

    var was: i128 = std.math.maxInt(i128);
    var now: i128 = std.math.maxInt(i128);
    var sum: u64 = 0;
    for (0..trials) |round| {
        var sp = Span.open(io);
        var acc: u64 = 0;
        for (b.tour) |i| acc +%= try oracle(b, op, i, &stack);
        was = @min(was, sp.lap(io).ns());

        sp = Span.open(io);
        var bcc: u64 = 0;
        for (b.tour) |i| bcc +%= try reached(b, op, i);
        now = @min(now, sp.read(io).ns());
        if (round == 0) sum = acc +% bcc;
    }
    const each: f64 = @floatFromInt(b.tour.len);
    return .{
        .was_ns = @as(f64, @floatFromInt(was)) / each,
        .now_ns = @as(f64, @floatFromInt(now)) / each,
        .sum = sum,
    };
}

// ── the representation trade ────────────────────────────────────────────────

const Both = enum { parent, next_sibling, depth, subtree_size };

fn live(b: *Board, comptime op: Both, i: u32) !u64 {
    const ref = b.refs[i];
    return switch (op) {
        .parent => b.q.parent(ref) orelse 0,
        .next_sibling => b.q.nextSibling(ref) orelse 0,
        .depth => b.q.depth(ref),
        .subtree_size => try b.q.subtreeSize(b.gpa, ref),
    };
}

fn settled(b: *Board, comptime op: Both, i: u32) u64 {
    const spot = b.spots[i];
    return switch (op) {
        .parent => b.sheet.parent(spot) orelse 0,
        .next_sibling => b.sheet.nextSibling(spot) orelse 0,
        .depth => b.sheet.depth(spot),
        .subtree_size => b.sheet.subtreeSize(spot),
    };
}

fn trade(b: *Board, io: std.Io, comptime op: Both) !Row {
    var q_ns: i128 = std.math.maxInt(i128);
    var s_ns: i128 = std.math.maxInt(i128);
    var sum: u64 = 0;
    for (0..trials) |round| {
        var sp = Span.open(io);
        var acc: u64 = 0;
        for (b.tour) |i| acc +%= try live(b, op, i);
        q_ns = @min(q_ns, sp.lap(io).ns());

        sp = Span.open(io);
        var bcc: u64 = 0;
        for (b.tour) |i| bcc +%= settled(b, op, i);
        s_ns = @min(s_ns, sp.read(io).ns());
        if (round == 0) sum = acc +% bcc;
    }
    const each: f64 = @floatFromInt(b.tour.len);
    return .{
        .was_ns = @as(f64, @floatFromInt(q_ns)) / each,
        .now_ns = @as(f64, @floatFromInt(s_ns)) / each,
        .sum = sum,
    };
}

// ── the lift, on the parse path ─────────────────────────────────────────────

/// `Quire.name` as it was spelled before the three free functions landed. The
/// only reason a copy of two dead lines is defensible: this row is the whole
/// evidence that lifting them cost nothing, and it cannot be measured without
/// both spellings in one binary.
fn nameWas(q: *const quire.Quire, ref: quire.Ref) []const u8 {
    const k = q.nodes[ref].kind;
    return if (k.renamed) q.gr.aliases[k.index].name else q.gr.nameOf(k.index);
}

fn namedWas(q: *const quire.Quire, ref: quire.Ref) bool {
    const k = q.nodes[ref].kind;
    return if (k.renamed) q.gr.aliases[k.index].named else q.gr.shapeOf(k.index) == .named;
}

fn lift(b: *Board, io: std.Io) !Row {
    var was: i128 = std.math.maxInt(i128);
    var now: i128 = std.math.maxInt(i128);
    var sum: u64 = 0;
    for (0..trials) |round| {
        var sp = Span.open(io);
        var acc: u64 = 0;
        for (b.tour) |i| {
            acc +%= nameWas(&b.q, b.refs[i]).len;
            acc +%= @intFromBool(namedWas(&b.q, b.refs[i]));
        }
        was = @min(was, sp.lap(io).ns());

        sp = Span.open(io);
        var bcc: u64 = 0;
        for (b.tour) |i| {
            bcc +%= b.q.name(b.refs[i]).len;
            bcc +%= @intFromBool(b.q.isNamed(b.refs[i]));
        }
        now = @min(now, sp.read(io).ns());
        if (round == 0) sum = acc +% bcc;
        if (acc != bcc) return error.LiftChangedTheAnswer;
    }
    const each: f64 = @floatFromInt(b.tour.len);
    return .{
        .was_ns = @as(f64, @floatFromInt(was)) / each,
        .now_ns = @as(f64, @floatFromInt(now)) / each,
        .sum = sum,
    };
}

// ── the flat cost ──────────────────────────────────────────────────────────

/// A cold parse and a keystroke over the same file, so the path everything here
/// sits on has a tracked number of its own.
fn flat(b: *Board, io: std.Io, out: *std.Io.Writer) !void {
    const gpa = b.gpa;
    var loom: weave.Loom = .init(gpa, &b.gr, &b.built.collection, &b.built.tables, &b.scanner);
    defer loom.deinit();
    var w = try weave.Weave.init(gpa, &loom);
    defer w.deinit();

    var cold: i128 = std.math.maxInt(i128);
    for (0..trials) |_| {
        var sp = Span.open(io);
        try w.warp(b.src);
        cold = @min(cold, sp.read(io).ns());
    }

    // A space typed at evenly spaced points and taken back out, so every edit
    // lands on the file the last one started from.
    const beats: u32 = 32;
    var keys: i128 = std.math.maxInt(i128);
    for (0..trials) |_| {
        var sp = Span.open(io);
        for (0..beats) |k| {
            const at: u32 = @intCast(b.src.len * (k + 1) / (beats + 1));
            try w.amend(.{ .from = at, .to = at, .insert = 1 }, " ");
            try w.amend(.{ .from = at, .to = at + 1, .insert = 0 }, "");
        }
        keys = @min(keys, sp.read(io).ns());
    }

    const bytes: f64 = @floatFromInt(@max(1, b.src.len));
    try out.print("  {s:<10} {d:>9} {d:>12.1} {d:>12.3} {d:>12.2}\n", .{
        b.tag,
        b.src.len,
        @as(f64, @floatFromInt(cold)) / 1000.0,
        @as(f64, @floatFromInt(cold)) / bytes,
        @as(f64, @floatFromInt(keys)) / 1000.0 / @as(f64, @floatFromInt(2 * beats)),
    });
}

fn shelf(gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    var threaded = std.Io.Threaded.init(gpa, .{});
    defer threaded.deinit();
    return std.Io.Dir.cwd().readFileAlloc(threaded.io(), path, gpa, .limited(64 << 20));
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var buf: [1 << 16]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &buf);
    const out = &stdout.interface;
    defer out.flush() catch {};

    var boards: std.ArrayList(*Board) = .empty;
    defer {
        for (boards.items) |b| b.deinit();
        boards.deinit(gpa);
    }

    try out.print("\ncursor — the neighbourhood accessors against the walks they were\n\n", .{});
    for (slate) |p| {
        const src = shelf(gpa, p.file) catch |e| {
            try out.print("  {s:<10} skipped ({s})\n", .{ p.tag, @errorName(e) });
            continue;
        };
        const b = Board.of(gpa, p.tag, p.grammar, src) catch |e| {
            try out.print("  {s:<10} skipped ({s})\n", .{ p.tag, @errorName(e) });
            continue;
        };
        try boards.append(gpa, b);
    }
    {
        const src = try wideSource(gpa);
        const b = Board.of(gpa, "wide", "test/grammar/json.json", src) catch |e| {
            try out.print("  {s:<10} skipped ({s})\n", .{ "wide", @errorName(e) });
            return e;
        };
        try boards.append(gpa, b);
    }
    if (boards.items.len == 0) return error.NothingToMeasure;

    try out.print("reach  nanoseconds an op, the oracle walk against the accessor\n", .{});
    for (boards.items) |b| {
        try out.print("  {s:<10} {s:>27} {s:>11} {s:>12} {s:>9}\n", .{
            b.tag, "op", "oracle ns", "accessor ns", "ratio",
        });
        inline for (comptime std.enums.values(Op)) |op| {
            const r = try race(b, init.io, op);
            try out.print("  {s:<10} {s:>27} {d:>11.2} {d:>12.2} {d:>8.2}x\n", .{
                "", @tagName(op), r.was_ns, r.now_ns, r.was_ns / @max(0.0001, r.now_ns),
            });
            std.mem.doNotOptimizeAway(r.sum);
        }
    }

    try out.print("\nvellum  nanoseconds an op, live tree against settled sheet\n", .{});
    for (boards.items) |b| {
        try out.print("  {s:<10} {s:>27} {s:>11} {s:>12} {s:>9}\n", .{
            b.tag, "op", "live ns", "settled ns", "ratio",
        });
        inline for (comptime std.enums.values(Both)) |op| {
            const r = try trade(b, init.io, op);
            try out.print("  {s:<10} {s:>27} {d:>11.2} {d:>12.2} {d:>8.2}x\n", .{
                "", @tagName(op), r.was_ns, r.now_ns, r.was_ns / @max(0.0001, r.now_ns),
            });
            std.mem.doNotOptimizeAway(r.sum);
        }
    }

    try out.print("\nlift  nanoseconds a name+isNamed pair, inline against the free functions\n", .{});
    try out.print("  {s:<10} {s:>11} {s:>12} {s:>9}\n", .{ "file", "inline ns", "lifted ns", "ratio" });
    for (boards.items) |b| {
        const r = try lift(b, init.io);
        try out.print("  {s:<10} {d:>11.2} {d:>12.2} {d:>8.2}x\n", .{
            b.tag, r.was_ns, r.now_ns, r.was_ns / @max(0.0001, r.now_ns),
        });
        std.mem.doNotOptimizeAway(r.sum);
    }

    try out.print("\nflat  the path everything above sits on\n", .{});
    try out.print("  {s:<10} {s:>9} {s:>12} {s:>12} {s:>12}\n", .{
        "file", "bytes", "parse us", "parse ns/B", "keystroke us",
    });
    for (boards.items) |b| try flat(b, init.io, out);
    try out.print("\n", .{});
}

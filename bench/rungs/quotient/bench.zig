//! Quotient — three Myhill–Nerode questions asked of one pressed grammar, and
//! the honest answer to each.
//!
//! `tool/rung4.py` owns the number the size claim is made in — bits per
//! production against the tree-sitter `.so` — because that measurement needs a
//! tree-sitter toolchain and a `.dylib` per grammar. This is the half that does
//! not: what the three quotients *find*, priced against the arm each of them is
//! supposed to beat. Every section here can embarrass its own design, and two
//! of them do:
//!
//!   1. **`states`** — the action-bisimulation. How many of a pressed
//!      automaton's states are copies of another, and what `refine` spent
//!      finding out. The honest result is that this is nearly always **zero**,
//!      and the reason is upstream: `forme.lock` already interns identical
//!      rows, and `press.zig`'s unfolding loop exists precisely to *split*
//!      states LALR merged wrongly. The table arriving here has had its
//!      duplicates removed twice by construction, so a third pass finding a
//!      handful is the correct answer rather than a disappointing one. It is
//!      printed anyway, every run, because "the relation is empty" is a claim
//!      that has to keep being true as the press changes.
//!   2. **`columns`** — the minterm alphabet over the table's terminal columns.
//!      Two columns in one class are two terminals no state anywhere routes
//!      differently. This one wins, and by how much is a fact about the
//!      grammar's lookahead structure rather than about the format.
//!   3. **`names`** — the DAFSA over the grammar's string payloads, against a
//!      plain sorted array with an offset pair per key, which is what the folio
//!      writes today. The irregex `partition` rung found a DAFSA *losing* at
//!      0.12x on keys with long unshared stems; grammar symbol names are a
//!      mixed corpus, so the ratio is printed per grammar and per payload and
//!      believed rather than assumed.
//!
//! There are no timing floors here. Every number is a byte count or a state
//! count and therefore deterministic, so the assertions at the bottom are the
//! ones that can be made without crying wolf on a shared laptop: the relation
//! must be a partition, the alphabet must be no coarser than it can prove, and
//! the DAFSA must rank every key it was given.

const std = @import("std");
const joints = @import("joints");

const press = joints.press;

const Pinned = struct { tag: []const u8, grammar: []const u8 };

/// The pinned grammars, by the path `tool/grammars.py fetch` puts them at. A
/// grammar that is not underfoot is a skipped row, never a failure: this rung
/// has to run in a clone that never fetched.
const slate = [_]Pinned{
    .{ .tag = "json", .grammar = "upstream/grammars/json.json" },
    .{ .tag = "c", .grammar = "upstream/grammars/c.json" },
    .{ .tag = "go", .grammar = "upstream/grammars/go.json" },
    .{ .tag = "java", .grammar = "upstream/grammars/java.json" },
    .{ .tag = "javascript", .grammar = "upstream/grammars/javascript.json" },
    .{ .tag = "python", .grammar = "upstream/grammars/python.json" },
    .{ .tag = "ruby", .grammar = "upstream/grammars/ruby.json" },
    .{ .tag = "rust", .grammar = "upstream/grammars/rust.json" },
    .{ .tag = "bash", .grammar = "upstream/grammars/bash.json" },
    .{ .tag = "cpp", .grammar = "upstream/grammars/cpp.json" },
    .{ .tag = "typescript", .grammar = "upstream/grammars/typescript.json" },
};

const Board = struct {
    gpa: std.mem.Allocator,
    grammar: press.Grammar,
    result: press.Result,

    fn of(gpa: std.mem.Allocator, path: []const u8) !Board {
        const text = try read(gpa, path);
        defer gpa.free(text);
        var gr = try press.treeSitter(gpa, text);
        errdefer gr.deinit();
        return .{ .gpa = gpa, .grammar = gr, .result = try press.tables(gpa, &gr) };
    }

    fn deinit(b: *Board) void {
        b.result.deinit();
        b.grammar.deinit();
    }
};

fn read(gpa: std.mem.Allocator, path: []const u8) ![]u8 {
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

    try out.print("\nquotient — three Myhill–Nerode questions, and what each one finds\n\n", .{});
    try out.print(
        "  {s:<12} {s:>7} {s:>7} {s:>7} {s:>9} {s:>6} {s:>6} {s:>6} {s:>7} {s:>7} {s:>7}\n",
        .{
            "grammar",  "states", "blocks", "merged", "engine",
            "cols",     "class",  "x",      "names",  "pats",
            "spelling",
        },
    );

    var ran: u32 = 0;
    for (slate) |p| {
        var b = Board.of(gpa, p.grammar) catch |e| {
            try out.print("  {s:<12} skipped ({s})\n", .{ p.tag, @errorName(e) });
            continue;
        };
        defer b.deinit();
        ran += 1;

        const q = b.result.quotient orelse return error.PressPublishedNoQuotient;
        // The relation is a partition or the rung is measuring nothing.
        var reached: u32 = 0;
        for (0..q.states()) |s| {
            const blk = q.at(@intCast(s));
            if (blk > reached) return error.NotAPartition;
            if (blk == reached) reached += 1;
        }
        if (reached != q.blocks) return error.NotAPartition;

        var alpha = try press.alphabet.of(gpa, &b.result.tables);
        defer alpha.deinit();
        if (alpha.classes > alpha.columns()) return error.AlphabetGrew;

        var names = try press.dafsa.names(gpa, &b.grammar);
        defer names.deinit();
        var pats = try press.dafsa.patterns(gpa, &b.grammar);
        defer pats.deinit();
        for (names.keys, 0..) |k, i| {
            const rank = names.ordinalOf(k) orelse return error.RankMissedItsOwnKey;
            if (rank != @as(u32, @intCast(i))) return error.RankIsNotTheOrder;
        }

        const nw = names.weight();
        try out.print(
            "  {s:<12} {d:>7} {d:>7} {d:>7} {s:>9} {d:>6} {d:>6} {d:>5.2}x {d:>6.2}x {d:>6.2}x {d:>6.1}\n",
            .{
                p.tag,             q.states(),        q.blocks,         q.merged(),
                @tagName(q.engine), alpha.columns(),  alpha.classes,    alpha.ratio(),
                nw.ratio(),        pats.weight().ratio(),
                @as(f64, @floatFromInt(nw.text)) / @as(f64, @floatFromInt(@max(1, nw.keys))),
            },
        );
    }

    if (ran == 0) {
        try out.print("\nno grammar underfoot; run `python3 tool/grammars.py fetch`\n", .{});
        return;
    }
    try out.print(
        \\
        \\states  blocks/merged: how much of the automaton the action-bisimulation
        \\        collapsed. Near zero is the expected answer and the reason is in
        \\        the header - row interning and unfolding got there first.
        \\cols    class/x: the column alphabet after the minterm sweep, and how
        \\        many terminal columns one class covers.
        \\names   pats: DAFSA bytes over sorted-array bytes, per payload. Over
        \\        1.00x the automaton LOSES and the folio is right to keep the
        \\        array; `spelling` is the mean key length that decides it.
        \\
    , .{});
}

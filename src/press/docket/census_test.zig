//! The census as a program: thirty grammars in, one owner per wall out.
//!
//! Every grammar that does not parse whole stops somewhere, and every round of
//! work on the press begins by deciding which of four subsystems each stop
//! belongs to. That decision used to be a markdown table, so it was a snapshot of
//! one afternoon's reasoning: it went stale the first time the press changed - the
//! table said html was the scanner's and elixir stopped at byte 25, and by the
//! next round html parsed whole and elixir reached 79 - and re-deriving it cost
//! the reader the whole argument about lookahead unions before they could route a
//! single wall.
//!
//! So it is this instead. Give it grammars and files; it presses each one, walks
//! the oracle over the bytes, and asks `inquest` who owns wherever the walk
//! stopped, with the argument attached to every row.
//!
//!     .local/orchestrate/census.txt, one line per grammar -
//!     upstream/grammars/c.json | research/joinery/corpus/ledger.c
//!
//! Then, from the package root:
//!
//!     zig build census
//!
//! Nothing is transcribed and no column is assigned by hand, which is the whole
//! point: after a press change the same command answers again, and the answer is
//! about the automaton that exists rather than the one someone remembers. The
//! request file is gitignored scratch and absent it the test returns immediately,
//! so being in the suite costs a no-op.
//!
//! **The first wall, not the last one.** Two loops run over the same tables. The
//! oracle (`kernel/walk`) stops dead at the first token the table refuses and
//! hands back the chain of reductions that token drove; the product loop
//! (`kernel/quire`) mends and reads on, so its verdict names wherever a forest ran
//! out several hundred recoveries later. The census attributes the *oracle's*
//! wall, for two reasons. It is the wall the grammar actually has - haskell's stop
//! only exists because 4,940 mends happened first - and it is the only one with
//! evidence, since attribution turns on which fold went wrong and the cell that
//! kills a parse is almost never the cell the parse dies in. Without the chain a
//! row can only be told "not this cell", which is true and nearly useless: it is
//! the whole difference between the seven `press?` rows and seven answers.
//!
//! The product loop still reports, as the second half of each row: whether it read
//! past that wall, how many mends that cost, and where it ended up. A row saying
//! `press ... [quire read to whole]` is a grammar whose table has a defect the
//! recovery is currently hiding, which is worth knowing in both directions.
//!
//! One tree invariant rides along, because the trees are already here and thirty
//! of them is the difference between one node and a class of bug: a child whose
//! span reaches outside its own parent's. `Node` promises a node runs from its
//! first token to its last, so a kid past the end is a violation and not a matter
//! of taste. Exactly one exists in this corpus, and it is toml's.
//!
//! Importing `kernel/` from a press file is what a cross-layer instrument costs;
//! `carry_test.zig` reaches into `folio/` for the same reason. Neither is press's
//! product code, and the claim each proves spans the seam it reaches over.

const std = @import("std");
const g = @import("../copy/grammar.zig");
const import = @import("../copy/import.zig");
const inquest = @import("../inquest.zig");
const lr0 = @import("../cast/lr0.zig");
const press = @import("../press.zig");
const lex = @import("../../kernel/lex/scanner.zig");
const quire = @import("../../kernel/quire/quire.zig");

/// The census board, on stdout. `zig build census` is run by a person who wants
/// to read or pipe this, and `std.debug.print` would have put it on stderr -
/// which the build runner renders through its failure printer, captioning a
/// green run `failed command:`. brigade's `note` is the stdout channel for
/// exactly this. Nothing here is a failure diagnostic: a grammar that cannot be
/// asked prints its reason and the walk continues.
const note = @import("root").note;
const walk = @import("../../kernel/walk/drive.zig");

const asked = ".local/orchestrate/census.txt";

test "census: who owns each wall" {
    const gpa = std.testing.allocator;
    var threaded = std.Io.Threaded.init(gpa, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const request = std.Io.Dir.cwd().readFileAlloc(io, asked, gpa, .limited(1 << 16)) catch return;
    defer gpa.free(request);

    var out: [4096]u8 = undefined;
    var tally: std.EnumArray(inquest.Owner, u32) = .initFill(0);
    var unproven: u32 = 0;
    var rows: u32 = 0;
    var whole: u32 = 0;
    var parted: u32 = 0;

    var lines = std.mem.tokenizeScalar(u8, request, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        var field = std.mem.splitScalar(u8, line, '|');
        const grammar_path = trim(field.next() orelse continue);
        const source_path = trim(field.next() orelse continue);
        if (grammar_path.len == 0 or source_path.len == 0) continue;

        rows += 1;
        var w: std.Io.Writer = .fixed(&out);
        const row = ask(gpa, io, grammar_path, source_path, &w) catch |e| {
            note("{s:<20} - {s}\n", .{ leaf(grammar_path), @errorName(e) });
            continue;
        };
        note("{s}\n", .{w.buffered()});
        tally.getPtr(row.found.owner).* += 1;
        if (!row.found.proven) unproven += 1;
        if (row.whole) whole += 1;
        if (!row.agreed) parted += 1;
    }

    var w: std.Io.Writer = .fixed(&out);
    w.print("\n{d} grammars", .{rows}) catch {};
    var it = tally.iterator();
    while (it.next()) |e| {
        if (e.value.* > 0) w.print(" · {d} {s}", .{ e.value.*, @tagName(e.key) }) catch {};
    }
    w.print(" ({d} unproven)\n", .{unproven}) catch {};
    // The product loop's own answer, which is the number a user of the parser sees
    // and a different question from who owns the first wall.
    w.print("quire read {d} of them whole; the two loops part on {d}\n", .{ whole, parted }) catch {};
    note("{s}", .{w.buffered()});
}

/// One grammar's answer: who owns its first wall, whether the product loop got a
/// whole tree anyway, and whether the two loops stopped in the same place.
const Row = struct { found: inquest.Finding, whole: bool = false, agreed: bool = true };

/// One grammar, one file, one row. Everything is torn down before returning, so
/// thirty of these hold one grammar's tables at a time rather than thirty.
fn ask(
    gpa: std.mem.Allocator,
    io: std.Io,
    grammar_path: []const u8,
    source_path: []const u8,
    w: *std.Io.Writer,
) !Row {
    const json = try std.Io.Dir.cwd().readFileAlloc(io, grammar_path, gpa, .limited(64 << 20));
    defer gpa.free(json);
    var gr = try import.treeSitter(gpa, json);
    defer gr.deinit();

    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, source_path, gpa, .limited(64 << 20));
    defer gpa.free(bytes);

    var built = try press.tables(gpa, &gr);
    defer built.deinit();

    var scanner = (try lex.Scanner.compile(gpa, &gr)) orelse {
        // Nothing in the grammar lexes at all, which is the scanner's answer
        // before any table is consulted - yaml, whose every terminal is external.
        const found: inquest.Finding = .{ .owner = .lexer, .because = .nothing_lexes };
        try w.print("{s:<20} ", .{gr.name});
        try inquest.write(found, &gr, .{ .stray = .{ .at = 0, .lexable = .nothing } }, w);
        return .{ .found = found };
    };
    defer scanner.deinit();

    var drive = try walk.Drive.init(gpa, &gr, &built.collection, &built.tables, &scanner);
    defer drive.deinit();
    var trace = try drive.run(bytes);
    defer trace.deinit(gpa);

    // The chain is borrowed from the `Drive` and dies with it, and `inquest` names
    // its own `Fold` because press cannot import the run time. Two fields, copied
    // rather than reinterpreted: a layout-compatible cast would be shorter and
    // would break silently the day either side grows a third.
    const chain = try folds(gpa, trace.ending);
    defer if (chain) |c| gpa.free(c);

    const wall = seen(trace.ending, chain, &scanner, bytes);
    const found = built.whose(&gr, wall, scanner.blind);
    try w.print("{s:<20} ", .{gr.name});
    try inquest.write(found, &gr, wall, w);
    try anchor(&gr, &built.collection, found, wall, w);

    // What the product loop made of the same bytes. Only ever an annotation: a
    // mend is a decision about how to carry on past a wall, not a claim that the
    // wall was somebody else's.
    var gather = try quire.Gather.init(gpa, &gr, &built.collection, &built.tables, &scanner);
    defer gather.deinit();
    var tree = try gather.run(bytes);
    defer tree.deinit();
    const agreed = try since(tree, wall, &gr, w);
    try forked(&gather, w);
    try loose(gpa, tree, w);
    return .{
        .found = found,
        .whole = std.meta.activeTag(tree.stop) == .accepted,
        .agreed = agreed,
    };
}

/// The kernel of the state a row names, spelled in the grammar's own names.
///
/// A state id is an index into a collection that renumbers whenever the symbol
/// space or the production list moves, and dropping one dead markdown terminal
/// moved cpp's refusal from 1646 to 935 without touching cpp. `(production, dot)`
/// pairs are no better: production indices shift for the same reason. What
/// survives is the kernel *rendered*: `array -> [ ] .` beside
/// `array_pattern -> [ ] .` names javascript 269 across any press, because it is
/// spelled in names the grammar owns rather than in numbers this pressing chose.
///
/// So the id stays for whoever is reading this press, and the kernel goes beside
/// it for whoever quotes the row into another one. Two items is the whole budget;
/// a wide kernel is summarised rather than dumped, since the point is a citation
/// and not a state listing - `joints state <n>` is where the rest lives.
fn anchor(
    gr: *const g.Grammar,
    c: *const lr0.Collection,
    found: inquest.Finding,
    wall: inquest.Wall,
    w: *std.Io.Writer,
) !void {
    // The cell the finding blames if it named one, else the state that refused;
    // an address nobody can act on does not need anchoring.
    const at = if (found.cell) |cell| cell.state else switch (wall) {
        .refused => |r| r.state,
        else => return,
    };
    if (at >= c.states.len) return;
    const items = c.states[at].kernel;
    if (items.len == 0) return;

    try w.print(" [{d} is", .{at});
    for (items[0..@min(items.len, 2)]) |item| {
        const p = gr.productions[item.prod];
        try w.print(" {s} ->", .{gr.nameOf(p.lhs)});
        for (p.rhs, 0..) |sym, i| {
            if (i == item.dot) try w.writeAll(" .");
            try w.print(" {s}", .{gr.nameOf(sym)});
        }
        if (item.dot >= p.rhs.len) try w.writeAll(" .");
        try w.writeAll(";");
    }
    if (items.len > 2) try w.print(" +{d} more", .{items.len - 2});
    try w.writeAll("]");
}

/// Children outside their own parent's span. `Node`'s contract is that a node
/// runs from its first token to its last, so the extras between them are inside
/// it - which makes a kid reaching past its parent's end an invariant violation
/// and not a matter of taste. Rides along here because the census already holds a
/// tree per grammar, and because one number over thirty grammars is the difference
/// between toml's 731st node and a class of bug.
///
/// It used to walk the arena itself, and that second walk was the only reason
/// anyone knew toml violates the invariant - `Quire.verify` demanded the same
/// thing and was reached by nothing but the amend fuzz. Two spellings of one
/// rule, agreeing, which is the shape that drifts. Now both read
/// `Quire.survey`, so a census and a parse can only ever say the same thing.
fn loose(gpa: std.mem.Allocator, tree: quire.Quire, w: *std.Io.Writer) !void {
    const found = try tree.survey(gpa);
    if (found.sound()) return;
    try w.print(" [{d} loose, {d} disorder, {d} torn", .{
        found.loose, found.disorder, found.torn,
    });
    if (found.first) |f| {
        if (f.ref >= tree.nodes.len) {
            try w.print(": {s} - ref {d} past {d} nodes]", .{ f.why, f.ref, tree.nodes.len });
            return;
        }
        const k = tree.nodes[f.ref];
        try w.print(": {s} - {s} [{d}, {d})", .{ f.why, tree.name(f.ref), k.start, k.end() });
        if (f.under != quire.none and f.under < tree.nodes.len) {
            const p = tree.nodes[f.under];
            try w.print(" in {s} [{d}, {d})", .{ tree.name(f.under), p.start, p.end() });
        }
    }
    try w.writeAll("]");
}

/// The oracle's stop in the inquest's terms. The one fact the ending does not
/// carry is argument 1 - whether anything lexes at a stray offset at all - and
/// answering it is one scanner call with the action row's restriction lifted.
fn seen(
    ending: walk.Ending,
    chain: ?[]const inquest.Fold,
    scanner: *lex.Scanner,
    bytes: []const u8,
) inquest.Wall {
    return switch (ending) {
        .accepted => .whole,
        .truncated => .unclosed,
        .stray => |at| .{ .stray = .{
            .at = at,
            .lexable = switch (scanner.next(bytes, at, null)) {
                .token => |tok| .{ .terminal = tok.symbol },
                else => .nothing,
            },
        } },
        .unexpected => |u| .{ .refused = .{
            .terminal = u.tok.symbol,
            .state = u.state,
            .folded = chain,
        } },
    };
}

fn folds(gpa: std.mem.Allocator, ending: walk.Ending) !?[]const inquest.Fold {
    const from = switch (ending) {
        .unexpected => |u| u.folded,
        else => return null,
    };
    const out = try gpa.alloc(inquest.Fold, from.len);
    for (from, out) |f, *o| o.* = .{ .state = f.state, .prod = f.prod };
    return out;
}

/// How far the product loop got past the wall the oracle stopped at. Silent when
/// the two agree and nothing was mended, which is every whole grammar.
///
/// `Quire.stop` is documented as where the trouble began rather than where the
/// forest ends, so agreement is the expectation and a disagreement is a finding
/// about the two loops - which is `kernel/quire/gather_test.zig`'s claim, stated
/// here per grammar instead of as one pass or fail.
fn since(tree: quire.Quire, wall: inquest.Wall, gr: *const g.Grammar, w: *std.Io.Writer) !bool {
    const here = std.meta.activeTag(wall);
    const same = switch (tree.stop) {
        .accepted => here == .whole,
        .truncated => here == .unclosed,
        .stray => |at| here == .stray and wall.stray.at == at,
        .unexpected => |u| here == .refused and wall.refused.terminal == u.symbol and
            wall.refused.state == u.state,
    };
    if (same) {
        if (tree.mends > 0) try w.print(" [quire mended {d}x past it]", .{tree.mends});
        return true;
    }
    try w.writeAll(" [quire ");
    if (tree.mends > 0) try w.print("mended {d}x and ", .{tree.mends});
    switch (tree.stop) {
        .accepted => try w.writeAll("read to whole]"),
        .truncated => try w.writeAll("ran out of input]"),
        .stray => |at| try w.print("stopped at byte {d} instead]", .{at}),
        .unexpected => |u| try w.print(
            "stopped on {s} in state {d} instead]",
            .{ gr.nameOf(u.symbol), u.state },
        ),
    }
    return false;
}

/// What the fork budget did on this file. Silent for a grammar whose tables
/// cannot fork, which is most of them.
///
/// The three numbers answer different questions and only together. `forks` is
/// how often an author's declared choice was actually taken up; `merged` is how
/// many of the readings that produced turned out to be one derivation written
/// twice, which is the population `crowd` used to be spent on; and `denied` is
/// how often a declared choice found no room at all. A row with `denied` at zero
/// is a row where the cap is not a limit on anything, whatever its value - which
/// is the only honest way to ask whether raising it would buy a byte.
fn forked(gather: *const quire.Gather, w: *std.Io.Writer) !void {
    if (gather.rifts == 0 and gather.denied == 0) return;
    try w.print(" [forks {d} merged {d} denied {d}]", .{
        gather.rifts,
        gather.merges,
        gather.denied,
    });
}

fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r");
}

fn leaf(path: []const u8) []const u8 {
    const cut = std.mem.lastIndexOfScalar(u8, path, '/') orelse return path;
    return path[cut + 1 ..];
}

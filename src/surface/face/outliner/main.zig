//! The outliner CLI.
//!
//! Seven verbs, in two groups. Four look at the machinery: `grammar` imports a
//! tree-sitter `grammar.json` and reports what the press made of it, `state`
//! prints one LR state, `lex` runs the terminal scanner over a real file, and
//! `joints` is rung 1 of `research/joinery/TESTING.md` — the measurement that
//! decided whether the whole package was a good idea. Two are the product:
//! `parse` returns a tree, `amend` returns the tree again after an edit without
//! re-reading the file, and `mint` turns a grammar into a folio. All three are
//! real now; the machinery verbs are why they could be written at all.
//!
//! Exit codes follow the family: 0 ran, 1 a clean negative answer, 2 an error.
//! `joints` uses that 1 for something specific: the kill condition tripped.

const std = @import("std");
const outliner = @import("outliner");
const assay = outliner.assay;
const import = outliner.press.import;
const scanner = outliner.kernel.lex.scanner;
const joints = @import("joints.zig");
const state = @import("state.zig");
const parse = @import("parse.zig");
const mint = @import("mint.zig");
const amend = @import("amend.zig");
const intake = @import("intake.zig");

/// Who this binary is, and what it can be asked to trace. Both are declared on
/// the package and re-exported here because the engine reads them off the ROOT
/// module of whatever compilation it lands in, and there are two: this face is
/// the executable's root, `src/root.zig` is the library's and the test build's.
/// Restating them would be two copies of one identity, free to disagree.
pub const irgx_brand = outliner.irgx_brand;
pub const irgx_lenses = outliner.irgx_lenses;

const usage =
    \\outliner - parsing as algebra
    \\
    \\usage:
    \\  outliner grammar <grammar.json>          import a tree-sitter grammar, report its shape
    \\  outliner lex <grammar.json> <file>       tokenize a file, print the stream
    \\  outliner joints <grammar.json> <file>... measure segment effects (rung 1)
    \\  outliner state <grammar.json> <n>        print one LR state: its items and its row
    \\  outliner state <grammar.json> --census <terminal>...  count those terminals over every state
    \\  outliner state <grammar.json> --holding <item>  name the states holding a reading
    \\  outliner state <grammar.json> --chain <n>  how a parse reaches n, and where a fold there goes
    \\  outliner parse <grammar.json|folio> <file>...  parse a file, print the tree
    \\  outliner amend <grammar.json|folio> <file> FROM..TO=TEXT...  re-parse across edits
    \\  outliner mint <grammar.json|folio>... [-o P]  press grammars into a folio
    \\                (several press into one codex), or read one back
    \\  outliner --version
    \\
    \\a <file> of - is stdin
    \\
    \\parse flags:
    \\  --all       keep the anonymous nodes in the tree
    \\  --ranges    one node per line with the bytes it covers
    \\  --scars     the repair sites instead of the tree
    \\  --json      the whole answer as one JSON object per file
    \\  --quiet     the verdict only, no stdout
    \\  --mend=P    what to do at a refusal: fell (default), none, keep, relent
    \\  --no-supply delete-only repair, the control arm
    \\  --language=NAME  which grammar, when the folio holds several
    \\
    \\amend flags:
    \\  --cold      re-read the whole file per edit, for the comparison
    \\  --policy=P  how far the re-mint window widens: prove, snap, whole
    \\  --language=NAME  which grammar, when the folio holds several
    \\
    \\joints flags:
    \\  --exact     fuse two limbs only on identical claims, never by depth
    \\  --dump      print the first many-valued joint in full
    \\  --confess   print the standing limbs wherever a run hits a ceiling
    \\  --entries N survey a segment from N entry states, 0 for every one
    \\  --limbs N   carry at most N parses at once
    \\  --fan N     admit at most N floors when a fold outruns the segment
    \\  --churn N   sprout at most N limbs while reading one token
    \\
    \\environment:
    \\  OUTLINER_TRACE=press,lex,joint,weave,folio,quire  light one or more phase traces
    \\                 (or `all`, which adds the search engine's own beneath them)
    \\
;

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    // Before dispatch, because a verb that traces its own setup would otherwise
    // run with the lens mask still zero. This is also the only read of
    // `OUTLINER_TRACE`: a phase asks `assay.trace(.press, …)` and never the
    // environment, so lighting one is a decision made in one place.
    assay.install(.{});

    var out_buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &out_buf);
    const w = &stdout.interface;
    defer w.flush() catch {};

    if (args.len < 2) {
        try w.writeAll(usage);
        return 2;
    }
    const verb = args[1];

    if (std.mem.eql(u8, verb, "--version") or std.mem.eql(u8, verb, "-V")) {
        try w.print("outliner {s}\n", .{@import("build_options").version});
        return 0;
    }
    if (std.mem.eql(u8, verb, "grammar")) {
        if (args.len < 3) {
            try w.writeAll("outliner: grammar needs a path to a grammar.json\n");
            return 2;
        }
        var show: Show = .{};
        var path: ?[]const u8 = null;
        for (args[2..]) |a| {
            if (std.mem.eql(u8, a, "--rules")) show.rules = true //
            else if (std.mem.eql(u8, a, "--trace")) outliner.press.setTrace(true) //
            else if (std.mem.startsWith(u8, a, "--growth=")) outliner.press.setGrowth(
                std.fmt.parseInt(u32, a["--growth=".len..], 10) catch 8,
            ) //
            else if (std.mem.eql(u8, a, "--conflicts")) show.conflicts = true //
            else path = a;
        }
        if (path == null) {
            try w.writeAll("outliner: grammar needs a path to a grammar.json\n");
            return 2;
        }
        return describe(gpa, init.io, w, path.?, show);
    }
    if (std.mem.eql(u8, verb, "state")) {
        if (args.len < 4) {
            try w.writeAll("outliner: state needs a grammar.json and a state number" ++
                " (or --census and a terminal)\n");
            return 2;
        }
        if (std.mem.eql(u8, args[3], "--census")) {
            if (args.len < 5) {
                try w.writeAll("outliner: --census needs at least one terminal name\n");
                return 2;
            }
            return state.run(gpa, init.io, w, args[2], .{ .census = args[4..] });
        }
        if (std.mem.eql(u8, args[3], "--holding")) {
            if (args.len < 5) {
                try w.writeAll("outliner: --holding needs an item to look for," ++
                    " like 'variable_lvalue -> _identifier .' or '-> _identifier .'\n");
                return 2;
            }
            return state.run(gpa, init.io, w, args[2], .{ .holding = args[4] });
        }
        if (std.mem.eql(u8, args[3], "--chain")) {
            if (args.len < 5) {
                try w.writeAll("outliner: --chain needs a state number\n");
                return 2;
            }
            const from = std.fmt.parseInt(u32, args[4], 10) catch {
                try w.print("outliner: {s} is not a state number\n", .{args[4]});
                return 2;
            };
            return state.run(gpa, init.io, w, args[2], .{ .chain = from });
        }
        const at = std.fmt.parseInt(u32, args[3], 10) catch {
            try w.print("outliner: {s} is not a state number\n", .{args[3]});
            return 2;
        };
        return state.run(gpa, init.io, w, args[2], .{ .at = at });
    }
    if (std.mem.eql(u8, verb, "lex")) {
        if (args.len < 4) {
            try w.writeAll("outliner: lex needs a grammar.json and a source file\n");
            return 2;
        }
        return lex(gpa, init.io, w, args[2], args[3]);
    }
    if (std.mem.eql(u8, verb, "joints")) {
        if (args.len < 4) {
            try w.writeAll("outliner: joints needs a grammar.json and at least one source file\n");
            return 2;
        }
        return joints.run(gpa, init.io, w, args[2], args[3..]);
    }
    if (std.mem.eql(u8, verb, "parse")) {
        if (args.len < 4) {
            try w.writeAll("outliner: parse needs a grammar.json and at least one source file\n");
            return 2;
        }
        return parse.run(gpa, init.io, w, args[2], args[3..]);
    }
    if (std.mem.eql(u8, verb, "amend")) {
        if (args.len < 4) {
            try w.writeAll("outliner: amend needs a grammar.json, a source file and an edit\n");
            return 2;
        }
        return amend.run(gpa, init.io, w, args[2], args[3..]);
    }
    if (std.mem.eql(u8, verb, "mint")) {
        if (args.len < 3) {
            try w.writeAll("outliner: mint needs a grammar.json or a folio\n");
            return 2;
        }
        return mint.run(gpa, init.io, w, args[2..]);
    }

    try w.writeAll(usage);
    return 2;
}

/// Tokenize `path` with the grammar at `grammar_path`, unconditionally.
///
/// Unconditionally is the point, and the output says so: without the parse
/// state's valid-terminal set, a context-dependent terminal (JSON's
/// `string_content`, a shell heredoc body) is longest almost everywhere and
/// eats the structure around it. The summary reports how much of the file went
/// into how few tokens, which is the cheapest way to see that happen.
fn lex(
    gpa: std.mem.Allocator,
    io: std.Io,
    w: *std.Io.Writer,
    grammar_path: []const u8,
    path: []const u8,
) !u8 {
    const source = intake.slurp(gpa, io, w, grammar_path) orelse return 2;
    defer gpa.free(source);
    var gr = import.treeSitter(gpa, source) catch |e| {
        try w.print("outliner: cannot import {s}: {s}\n", .{ grammar_path, @errorName(e) });
        return 2;
    };
    defer gr.deinit();

    const text = intake.slurp(gpa, io, w, path) orelse return 2;
    defer gpa.free(text);

    var sc = (scanner.Scanner.compile(gpa, &gr) catch |e| {
        try w.print("outliner: cannot compile {s}'s scanner: {s}\n", .{ gr.name, @errorName(e) });
        return 2;
    }) orelse {
        try w.print("outliner: {s} has no lexable terminal at all\n", .{gr.name});
        return 1;
    };
    defer sc.deinit();

    const lexing = assay.Span.open(io);
    // `null` and not a parse's `Expected`: this verb is the scanner asked what
    // it *can* match, not what the parse lets it. The two differ by more than a
    // little - with no state naming its terminals, every contextual one is live
    // everywhere, so an `immediate` body pattern (a string's interior, a JSX
    // fragment, a shebang tail) is admitted at offsets no parse would offer it
    // and, being a negated class, usually wins longest-match and swallows the
    // line. Reading this run as the parse's token stream reads a whole file as
    // one `string_fragment`; the tree from `parse` on the same bytes is fully
    // built. The footer below says so, because nothing else here does.
    var run = try scanner.tokenize(&sc, gpa, text, null);
    defer run.deinit(gpa);
    const us = lexing.read(io).us();

    for (run.tokens) |tok| {
        try w.print("{d:>7} {d:>4}  {s: <24}", .{ tok.start, tok.len, gr.nameOf(tok.symbol) });
        try writeClipped(w, text[tok.start..tok.end()]);
        try w.writeAll("\n");
    }

    var covered: usize = 0;
    for (run.tokens) |tok| covered += tok.len;
    try w.print("\n{s}: {d} tokens over {d} bytes ({d} covered) in {d} us\n", .{
        gr.name, run.tokens.len, text.len, covered, us,
    });
    try w.writeAll("  admitted context-free: no parse state gates these, so a" ++
        " contextual\n  terminal fires where the parse would refuse it — use" ++
        " `parse` for the real stream\n");
    if (sc.blind.len > 0) {
        try w.print("  blind to {d} terminal(s):", .{sc.blind.len});
        for (sc.blind, 0..) |s, i| {
            if (i == 8) {
                try w.print(" +{d} more", .{sc.blind.len - i});
                break;
            }
            try w.print(" {s}", .{gr.nameOf(s)});
        }
        try w.writeAll("\n");
    }
    if (sc.declined.len > 0) {
        // Ours rather than someone else's C, which is why it reads differently
        // from `blind`: a declined pattern is the engine refusing a spelling we
        // could support, and it is invisible in the token stream above - the
        // terminal simply never wins, so the row it should have owned is either
        // a wider neighbour's or a stray.
        try w.print("  {d} pattern(s) the engine would not build:", .{sc.declined.len});
        for (sc.declined, 0..) |s, i| {
            if (i == 8) {
                try w.print(" +{d} more", .{sc.declined.len - i});
                break;
            }
            try w.print(" {s}", .{gr.nameOf(s)});
        }
        try w.writeAll("\n");
    }
    if (run.stray) |off| {
        try w.print("  stray byte at {d}: no terminal begins here\n", .{off});
        return 1;
    }
    return 0;
}

/// One line's worth of a token's text, with the whitespace made visible — a
/// token that is a newline should not silently end the row describing it.
fn writeClipped(w: *std.Io.Writer, text: []const u8) !void {
    const clip = @min(text.len, 48);
    for (text[0..clip]) |c| switch (c) {
        '\n' => try w.writeAll("\\n"),
        '\t' => try w.writeAll("\\t"),
        '\r' => try w.writeAll("\\r"),
        else => try w.writeByte(c),
    };
    if (text.len > clip) try w.print("… +{d}", .{text.len - clip});
}

const Show = struct { rules: bool = false, conflicts: bool = false };

const Symbol = outliner.press.grammar.Symbol;

/// Contested cells grouped by *whose* ambiguity they are, commonest first.
///
/// The grouping is the whole point. Hundreds of individual cells say only that
/// a grammar is not LALR; the same cells collapsed onto the rule groups that
/// caused them usually say which handful of rules did, and whether each group
/// is one symbol away from something the author already declared. A count per
/// group is what turns "258 residual conflicts" into a list short enough to fix.
fn parties(
    gpa: std.mem.Allocator,
    w: *std.Io.Writer,
    gr: *const outliner.press.grammar.Grammar,
    conflicts: []const outliner.press.lalr.Conflict,
) !void {
    const Group = struct {
        party: []const Symbol,
        class: outliner.press.lalr.Conflict.Class,
        cells: u32 = 0,
        reduce_reduce: u32 = 0,
        /// One cell of the group, so the report can show the actual two rules
        /// rather than only how many times they disagreed.
        witness: outliner.press.lalr.Conflict,
    };
    var groups: std.ArrayList(Group) = .empty;
    defer groups.deinit(gpa);

    for (conflicts) |k| {
        const at = for (groups.items) |*grp| {
            if (grp.class == k.class and std.mem.eql(Symbol, grp.party, k.party)) break grp;
        } else blk: {
            try groups.append(gpa, .{ .party = k.party, .class = k.class, .witness = k });
            break :blk &groups.items[groups.items.len - 1];
        };
        at.cells += 1;
        if (k.kind == .reduce_reduce) at.reduce_reduce += 1;
    }
    std.mem.sort(Group, groups.items, {}, struct {
        fn less(_: void, a: Group, b: Group) bool {
            return a.cells > b.cells;
        }
    }.less);

    for (groups.items) |grp| {
        try w.print("    {s: <11} {d: >4} cells ({d} r/r)  ", .{
            @tagName(grp.class), grp.cells, grp.reduce_reduce,
        });
        for (grp.party, 0..) |s, i| {
            if (i > 0) try w.writeAll(" + ");
            try w.writeAll(gr.nameOf(s));
        }
        try w.writeByte('\n');
        // Only the residue gets spelled out. A declared group is the author
        // saying "yes, here", and the repetition class is a normalization
        // artifact — neither is something to go read productions about.
        if (grp.class != .residual) continue;
        const k = grp.witness;
        const on = if (k.terminal >= gr.terminal_count) "$end" else gr.nameOf(k.terminal);
        try w.print("                 state {d} on {s}:  ", .{ k.state, on });
        try state.verdict(w, gr, k.chosen);
        try w.writeAll("\n                 versus            ");
        try state.verdict(w, gr, k.other);
        try w.writeByte('\n');
    }
}

fn describe(
    gpa: std.mem.Allocator,
    io: std.Io,
    w: *std.Io.Writer,
    path: []const u8,
    show: Show,
) !u8 {
    const source = intake.slurp(gpa, io, w, path) orelse return 2;
    defer gpa.free(source);

    // Two spans rather than one span lapped twice: the reporting between the
    // phases is not either phase, and lapping would fold it into the second.
    const importing = assay.Span.open(io);
    var gr = import.treeSitter(gpa, source) catch |e| {
        try w.print("outliner: cannot import {s}: {s}\n", .{ path, @errorName(e) });
        return 2;
    };
    defer gr.deinit();
    const elapsed_us = importing.read(io).us();

    var rhs_total: usize = 0;
    var epsilons: usize = 0;
    var longest: usize = 0;
    for (gr.productions) |p| {
        rhs_total += p.rhs.len;
        if (p.rhs.len == 0) epsilons += 1;
        longest = @max(longest, p.rhs.len);
    }
    const literals = blk: {
        var n: usize = 0;
        for (gr.patterns) |p| if (p) |pat| {
            if (pat == .literal) n += 1;
        };
        break :blk n;
    };

    try w.print("{s}\n", .{gr.name});
    try w.print("  symbols        {d}  ({d} terminal, {d} nonterminal)\n", .{
        gr.symbolCount(), gr.terminal_count, gr.nonterminalCount(),
    });
    try w.print("  terminals      {d} literal, {d} regex, {d} external\n", .{
        literals, gr.terminal_count - literals - gr.externals.len, gr.externals.len,
    });
    try w.print("  productions    {d}  ({d} epsilon, longest rhs {d}, {d} symbols total)\n", .{
        gr.productions.len, epsilons, longest, rhs_total,
    });
    // A nonterminal a right-hand side still names but which derives no terminal
    // string makes every production mentioning it unreachable, and in an
    // imported grammar that is the importer's fault, not the language's. A rule
    // with no productions that nothing mentions is the *fold* having worked, so
    // it is deliberately not on this list.
    const barren = try gr.barren(gpa);
    defer gpa.free(barren);

    try w.print("  extras         {d}\n", .{gr.extras.len});
    try w.print("  conflicts      {d} declared\n", .{gr.declared_conflicts.len});
    try w.print("  imported in    {d} us\n", .{elapsed_us});

    const pressing = assay.Span.open(io);
    var built = outliner.press.tables(gpa, &gr) catch |e| {
        try w.print("outliner: cannot press {s}: {s}\n", .{ gr.name, @errorName(e) });
        return 2;
    };
    defer built.deinit();
    const c = &built.collection;
    const built_us = pressing.read(io).us();
    var kernel_items: usize = 0;
    var edge_count: usize = 0;
    var widest: usize = 0;
    for (c.states) |st| {
        kernel_items += st.kernel.len;
        edge_count += st.edges.len;
        widest = @max(widest, st.kernel.len);
    }
    try w.print("  lr(0) states   {d}  ({d} kernel items, widest {d}, {d} edges)\n", .{
        c.states.len, kernel_items, widest, edge_count,
    });
    if (built.unfolded > 0) {
        try w.print("  unfolded       {d} round(s) to separate merged lookaheads\n", .{
            built.unfolded,
        });
    }

    const t = &built.tables;
    var shifts: usize = 0;
    var reduces: usize = 0;
    for (t.action) |act| switch (act.kind) {
        .shift => shifts += 1,
        .reduce, .accept => reduces += 1,
        .err => {},
    };
    var sr: usize = 0;
    for (t.conflicts) |k| {
        if (k.kind == .shift_reduce) sr += 1;
    }
    const cells = t.action.len;
    try w.print("  lalr table     {d} cells, {d} shift, {d} reduce ({d}% dense)\n", .{
        cells, shifts, reduces, (shifts + reduces) * 100 / cells,
    });
    const tally = t.tally();
    try w.print("  contested      {d} cells ({d} shift/reduce, {d} reduce/reduce)\n", .{
        t.conflicts.len, sr, t.conflicts.len - sr,
    });
    try w.print("                 {d} repetition, {d} declared, {d} RESIDUAL ({d} s/r, {d} r/r)\n", .{
        tally.repetition,            tally.declared,               tally.residual.total(),
        tally.residual.shift_reduce, tally.residual.reduce_reduce,
    });
    // `floor()` is the same population this line used to count with a loop of
    // its own — every frayed cell whose harm is `read_dropped` — so the count
    // comes off the partition rather than beside it.
    const stand = t.floor();
    try w.print("  frayed         {d} cells contested only by state merging ({d} REFUSE a token)\n", .{
        t.frayed.len, stand.total(),
    });
    // The count is the least interesting fact about a refusal, and printing it
    // alone reads as N defects on a table that has far fewer. `agreed` is a cell
    // canonical LR(1) builds too, so the press has nothing to answer for there;
    // `alone` and `stuck` are inventions no partition of this state's arrivals
    // can undo; only `open` is a cell another unfolding round could reach. See
    // `lalr.Floor`.
    if (stand.total() > 0) {
        try w.print("                 {d} agreed, {d} alone, {d} stuck, {d} open" ++
            " — {d} SEALED under any split\n", .{
            stand.agreed, stand.alone, stand.stuck, stand.open, stand.sealed(),
        });
    }
    try w.print("  built in       {d} us\n", .{built_us});
    if (show.conflicts and t.conflicts.len > 0) try parties(gpa, w, &gr, t.conflicts);
    if (barren.len > 0) {
        try w.print("  BARREN         {d} referenced nonterminals derive nothing\n", .{barren.len});
        for (barren) |s| try w.print("                 {s}\n", .{gr.nameOf(s)});
    }
    if (gr.externals.len > 0) {
        try w.writeAll("  note: external scanner tokens cannot be lexed here:");
        for (gr.externals, 0..) |s, i| {
            if (i == 8) {
                try w.print(" +{d} more", .{gr.externals.len - i});
                break;
            }
            try w.print(" {s}", .{gr.nameOf(s)});
        }
        try w.writeAll("\n");
    }
    if (show.rules) {
        try w.writeAll("\n");
        for (0..gr.productions.len) |i| {
            try w.print("{d:>5}  ", .{i});
            try state.rule(w, &gr, @intCast(i));
            try w.writeAll("\n");
        }
    }
    return 0;
}

test {
    std.testing.refAllDecls(@This());
    _ = outliner;
    // Named rather than left to `refAllDecls`, which reaches public decls: the
    // face's siblings are private consts here, so `parse.zig`'s tests were only
    // ever collected if something else happened to analyse the file. The one
    // asserting the verdict still says `surveyed` is the wiring gate under
    // `tool/sound.py`, and a gate collected by accident is not collected.
    _ = @import("parse.zig");
}

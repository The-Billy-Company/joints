//! The outliner CLI.
//!
//! Six verbs, in two groups. Four look at the machinery: `grammar` imports a
//! tree-sitter `grammar.json` and reports what the press made of it, `state`
//! prints one LR state, `lex` runs the terminal scanner over a real file, and
//! `joints` is rung 1 of `research/joinery/TESTING.md` — the measurement that
//! decided whether the whole package was a good idea. Two are the product:
//! `parse` returns a tree and `mint` turns a grammar into a folio. Both are
//! real now; the machinery verbs are why they could be written at all.
//!
//! Exit codes follow the family: 0 ran, 1 a clean negative answer, 2 an error.
//! `joints` uses that 1 for something specific: the kill condition tripped.

const std = @import("std");
const outliner = @import("outliner");
const import = outliner.press.import;
const scanner = outliner.kernel.lex.scanner;
const joints = @import("joints.zig");
const parse = @import("parse.zig");
const mint = @import("mint.zig");

const usage =
    \\outliner - parsing as algebra
    \\
    \\usage:
    \\  outliner grammar <grammar.json>          import a tree-sitter grammar, report its shape
    \\  outliner lex <grammar.json> <file>       tokenize a file, print the stream
    \\  outliner joints <grammar.json> <file>... measure segment effects (rung 1)
    \\  outliner state <grammar.json> <n>        print one LR state: its items and its row
    \\  outliner parse <grammar.json> <file>...  parse a file, print the tree
    \\  outliner mint <grammar.json|folio> [-o P]  press a grammar into a folio, or read one back
    \\  outliner --version
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
;

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

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
            try w.writeAll("outliner: state needs a grammar.json and a state number\n");
            return 2;
        }
        const at = std.fmt.parseInt(u32, args[3], 10) catch {
            try w.print("outliner: {s} is not a state number\n", .{args[3]});
            return 2;
        };
        return inspect(gpa, init.io, w, args[2], at);
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

fn slurp(gpa: std.mem.Allocator, io: std.Io, w: *std.Io.Writer, path: []const u8) !?[]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 << 20)) catch |e| {
        try w.print("outliner: cannot read {s}: {s}\n", .{ path, @errorName(e) });
        return null;
    };
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
    const source = (try slurp(gpa, io, w, grammar_path)) orelse return 2;
    defer gpa.free(source);
    var gr = import.treeSitter(gpa, source) catch |e| {
        try w.print("outliner: cannot import {s}: {s}\n", .{ grammar_path, @errorName(e) });
        return 2;
    };
    defer gr.deinit();

    const text = (try slurp(gpa, io, w, path)) orelse return 2;
    defer gpa.free(text);

    var sc = (try scanner.Scanner.compile(gpa, &gr)) orelse {
        try w.print("outliner: {s} has no lexable terminal at all\n", .{gr.name});
        return 1;
    };
    defer sc.deinit();

    const started = std.Io.Clock.awake.now(io);
    var run = try scanner.tokenize(&sc, gpa, text, null);
    defer run.deinit(gpa);
    const us: i64 = @intCast(@divTrunc(
        started.durationTo(std.Io.Clock.awake.now(io)).nanoseconds,
        std.time.ns_per_us,
    ));

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

/// One state, whole: what it has read, and what it will do with every terminal.
///
/// The question a wrong table raises is never "how many conflicts" — it is
/// "why did *this* cell say that", and answering it needs the state's items
/// beside its row. A reduce on a terminal that cannot follow the folded rule is
/// a lookahead bug; the same reduce beside a shift the ladder passed over is a
/// resolution bug; and the two are indistinguishable from a count.
fn inspect(
    gpa: std.mem.Allocator,
    io: std.Io,
    w: *std.Io.Writer,
    grammar_path: []const u8,
    at: u32,
) !u8 {
    const source = (try slurp(gpa, io, w, grammar_path)) orelse return 2;
    defer gpa.free(source);
    var gr = import.treeSitter(gpa, source) catch |e| {
        try w.print("outliner: cannot import {s}: {s}\n", .{ grammar_path, @errorName(e) });
        return 2;
    };
    defer gr.deinit();

    var built = try outliner.press.tables(gpa, &gr);
    defer built.deinit();
    if (at >= built.collection.states.len) {
        try w.print("outliner: {s} has {d} states\n", .{ gr.name, built.collection.states.len });
        return 2;
    }

    try w.print("state {d} of {s}\n\n  items:\n", .{ at, gr.name });
    for (built.collection.states[at].kernel) |item| {
        const p = gr.productions[item.prod];
        try w.print("    {s} ->", .{gr.nameOf(p.lhs)});
        for (p.rhs, 0..) |sym, k| {
            if (k == item.dot) try w.writeAll(" .");
            try w.print(" {s}", .{gr.nameOf(sym)});
        }
        if (item.dot == p.rhs.len) try w.writeAll(" .");
        try w.writeAll("\n");
    }

    try w.writeAll("\n  row:\n");
    var rows: u32 = 0;
    for (0..gr.terminal_count) |sym| {
        const act = built.tables.at(at, @intCast(sym));
        if (act.kind == .err) continue;
        rows += 1;
        try w.print("    {s: <28} ", .{gr.nameOf(@intCast(sym))});
        try verdict(w, &gr, act);
        for (built.tables.conflicts) |k| {
            if (k.state != at or k.terminal != sym) continue;
            try w.print("   [{s} {s}, over ", .{ @tagName(k.class), @tagName(k.kind) });
            try verdict(w, &gr, k.other);
            try w.writeAll("]");
            break;
        }
        try w.writeAll("\n");
    }
    try w.print("\n  {d} terminal(s) accepted of {d}\n", .{ rows, gr.terminal_count });
    return 0;
}

const Show = struct { rules: bool = false, conflicts: bool = false };

const Grammar = outliner.press.grammar.Grammar;
const Symbol = outliner.press.grammar.Symbol;

/// One production, with the precedence and side each step carries — because in
/// a conflict report those two are usually the whole answer to "why didn't this
/// resolve". Printed against the final step, which is the one a completed
/// reading is judged on.
fn rule(w: *std.Io.Writer, gr: *const Grammar, prod: u32) !void {
    const p = gr.productions[prod];
    try w.print("{s} ->", .{gr.nameOf(p.lhs)});
    if (p.rhs.len == 0) try w.writeAll(" ε");
    for (p.rhs) |s| try w.print(" {s}", .{gr.nameOf(s)});
    const last = p.consumed(p.rhs.len);
    if (last.prec != .none or last.assoc != .none) {
        try w.writeAll("   [prec ");
        switch (last.prec) {
            .none => try w.writeAll("-"),
            .level => |v| try w.print("{d}", .{v}),
            .name => |n| try w.print("'{s}'", .{gr.prec_names[n]}),
        }
        try w.print(" {s}]", .{@tagName(last.assoc)});
    }
}

/// What a cell decided, in the vocabulary of the grammar rather than of the
/// table: a shift names the token read, a reduce names the rule folded.
fn verdict(w: *std.Io.Writer, gr: *const Grammar, a: outliner.press.lalr.Action) !void {
    switch (a.kind) {
        .shift => try w.writeAll("read on"),
        .accept => try w.writeAll("accept"),
        .err => try w.writeAll("nothing"),
        .reduce => {
            try w.writeAll("fold  ");
            try rule(w, gr, a.value);
        },
    }
}

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
        try verdict(w, gr, k.chosen);
        try w.writeAll("\n                 versus            ");
        try verdict(w, gr, k.other);
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
    const source = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 << 20)) catch |e| {
        try w.print("outliner: cannot read {s}: {s}\n", .{ path, @errorName(e) });
        return 2;
    };
    defer gpa.free(source);

    const started = std.Io.Clock.awake.now(io);
    var gr = import.treeSitter(gpa, source) catch |e| {
        try w.print("outliner: cannot import {s}: {s}\n", .{ path, @errorName(e) });
        return 2;
    };
    defer gr.deinit();
    const elapsed_us: i64 = @intCast(@divTrunc(
        started.durationTo(std.Io.Clock.awake.now(io)).nanoseconds,
        std.time.ns_per_us,
    ));

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

    const lr_started = std.Io.Clock.awake.now(io);
    var built = try outliner.press.tables(gpa, &gr);
    defer built.deinit();
    const c = &built.collection;
    const built_us: i64 = @intCast(@divTrunc(
        lr_started.durationTo(std.Io.Clock.awake.now(io)).nanoseconds,
        std.time.ns_per_us,
    ));
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
    var refused: usize = 0;
    for (t.frayed) |f| {
        if (f.harm == .read_dropped) refused += 1;
    }
    try w.print("  frayed         {d} cells contested only by state merging ({d} REFUSE a token)\n", .{
        t.frayed.len, refused,
    });
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
            try rule(w, &gr, @intCast(i));
            try w.writeAll("\n");
        }
    }
    return 0;
}

test {
    std.testing.refAllDecls(@This());
    _ = outliner;
}

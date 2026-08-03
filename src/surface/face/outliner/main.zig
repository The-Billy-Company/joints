//! The outliner CLI.
//!
//! One verb today — `grammar`, which imports a tree-sitter `grammar.json` and
//! reports what the press made of it. That is not a placeholder: rung 1 of
//! `research/joinery/TESTING.md` needs an LR automaton over a real grammar
//! before it can measure anything, and a front end nobody can look at is a
//! front end nobody can check.
//!
//! Exit codes follow the family: 0 ran, 1 a clean negative answer, 2 an error.

const std = @import("std");
const outliner = @import("outliner");
const import = outliner.press.import;

const usage =
    \\outliner - parsing as algebra
    \\
    \\usage:
    \\  outliner grammar <grammar.json>   import a tree-sitter grammar, report its shape
    \\  outliner --version
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
        var rules: bool = false;
        var path: ?[]const u8 = null;
        for (args[2..]) |a| {
            if (std.mem.eql(u8, a, "--rules")) rules = true else path = a;
        }
        if (path == null) {
            try w.writeAll("outliner: grammar needs a path to a grammar.json\n");
            return 2;
        }
        return describe(gpa, init.io, w, path.?, rules);
    }

    try w.writeAll(usage);
    return 2;
}

fn describe(
    gpa: std.mem.Allocator,
    io: std.Io,
    w: *std.Io.Writer,
    path: []const u8,
    rules: bool,
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
    // A nonterminal with no production derives nothing, so any string using it
    // is unparseable. In an imported grammar that is never the grammar's fault
    // — it means a rule body was dropped on the way in.
    var barren: usize = 0;
    for (gr.terminal_count..gr.symbolCount()) |s| {
        if (gr.productionsOf(@intCast(s)).len == 0) barren += 1;
    }

    try w.print("  extras         {d}\n", .{gr.extras.len});
    try w.print("  conflicts      {d} declared\n", .{gr.declared_conflicts.len});
    try w.print("  imported in    {d} us\n", .{elapsed_us});

    const lr_started = std.Io.Clock.awake.now(io);
    var c = try outliner.press.lr0.build(gpa, &gr);
    defer c.deinit();
    const lr_us: i64 = @intCast(@divTrunc(
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
    try w.print("  built in       {d} us\n", .{lr_us});

    const la_started = std.Io.Clock.awake.now(io);
    var t = try outliner.press.lalr.build(gpa, &gr, &c);
    defer t.deinit();
    const la_us: i64 = @intCast(@divTrunc(
        la_started.durationTo(std.Io.Clock.awake.now(io)).nanoseconds,
        std.time.ns_per_us,
    ));
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
    try w.print("  conflicts      {d} unresolved ({d} shift/reduce, {d} reduce/reduce)\n", .{
        t.conflicts.len, sr, t.conflicts.len - sr,
    });
    try w.print("  built in       {d} us\n", .{la_us});
    if (barren > 0) {
        try w.print("  BARREN         {d} nonterminals derive nothing\n", .{barren});
        for (gr.terminal_count..gr.symbolCount()) |s| {
            if (gr.productionsOf(@intCast(s)).len == 0) {
                try w.print("                 {s}\n", .{gr.nameOf(@intCast(s))});
            }
        }
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
    if (rules) {
        try w.writeAll("\n");
        for (gr.productions, 0..) |p, i| {
            try w.print("{d:>5}  {s} ->", .{ i, gr.nameOf(p.lhs) });
            if (p.rhs.len == 0) try w.writeAll(" ε");
            for (p.rhs) |s| try w.print(" {s}", .{gr.nameOf(s)});
            if (p.prec != 0 or p.assoc != .none) {
                try w.print("   [prec {d} {s}]", .{ p.prec, @tagName(p.assoc) });
            }
            try w.writeAll("\n");
        }
    }
    return 0;
}

test {
    std.testing.refAllDecls(@This());
    _ = outliner;
}

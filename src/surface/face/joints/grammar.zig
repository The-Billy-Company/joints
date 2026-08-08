//! `joints grammar` - import a tree-sitter grammar and report its shape.
//!
//! The verb that answers "what did tree-sitter actually declare?" before any
//! question about parsing it. Its `--conflicts` view is the one that matters:
//! contested cells grouped by whose ambiguity they are, because hundreds of
//! individual cells say only that a grammar is not LALR.

const std = @import("std");
const joints = @import("joints");
const intake = @import("intake.zig");
const state = @import("state.zig");

const press = joints.press;
const assay = joints.assay;

/// The flags, and the path they qualify. Anything that is not a flag is the
/// path, last one winning - the same rule every verb here follows.
pub fn run(
    gpa: std.mem.Allocator,
    io: std.Io,
    w: *std.Io.Writer,
    args: []const []const u8,
) !u8 {
    var show: Show = .{};
    var path: ?[]const u8 = null;
    for (args) |a| {
        if (std.mem.eql(u8, a, "--rules")) show.rules = true //
        else if (std.mem.eql(u8, a, "--trace")) press.setTrace(true) //
        else if (std.mem.startsWith(u8, a, "--growth=")) press.setGrowth(
            std.fmt.parseInt(u32, a["--growth=".len..], 10) catch 8,
        ) //
        else if (std.mem.eql(u8, a, "--conflicts")) show.conflicts = true //
        else path = a;
    }
    // Reachable with a non-empty `args`: every one of them can be a flag.
    const p = path orelse {
        try w.writeAll("joints: grammar needs a path to a grammar.json\n");
        return 2;
    };
    return describe(gpa, io, w, p, show);
}

const Show = struct { rules: bool = false, conflicts: bool = false };

const Symbol = press.Symbol;

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
    gr: *const press.Grammar,
    conflicts: []const press.Conflict,
) !void {
    const Group = struct {
        party: []const Symbol,
        class: press.Conflict.Class,
        cells: u32 = 0,
        reduce_reduce: u32 = 0,
        /// One cell of the group, so the report can show the actual two rules
        /// rather than only how many times they disagreed.
        witness: press.Conflict,
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
    var gr = intake.grammar(gpa, w, path, source) orelse return 2;
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
    var built = intake.tables(gpa, w, &gr) orelse return 2;
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

//! Ask the table what it decided at one symbol, across the whole automaton.
//!
//! A wall verdict names the state the parse died in, and `joints state` will
//! print that state - but the state a parse dies in is rarely the state that
//! killed it. The damage is a cell *upstream*: some state held both a read and a
//! fold on the same token, the fold won, and the reading that could have gone on
//! was popped off the stack several folds before anything looked wrong. Naming
//! that cell needs a search over states rather than a lookup of one, because
//! there is no locality between a state's number and the parse's path through it.
//!
//! So this finds every state whose kernel stands the dot beside a named symbol
//! and prints what the row says about one named terminal there - with the
//! conflict class if the cell was contested, and with the seam if a merge
//! invented it. Those three facts are the whole attribution: a contested
//! read-or-fold is the press's resolution to answer for, a cell a seam
//! over-permits is the press's merge to answer for, and an uncontested cell the
//! grammar means is nobody's.
//!
//! Asked by a file rather than a flag, because a test takes no arguments and a
//! full press is seconds - too slow to run on every build and too specific to
//! want to. Write `.local/orchestrate/wall.txt`, three or four lines:
//!
//!     upstream/grammars/zig.json
//!     after primary_type_expression      (or `before <symbol>`)
//!     on {
//!     growth 16                          (optional: press again with this ration)
//!
//! Name no symbol and the search is the whole table: every state that reads the
//! token, every state that refused it to a fold, and whether a seam invented the
//! permission. That is the census question - a wall is only the press's if some
//! state held a read the resolution took away - and it wants no dot to aim at,
//! because the state that killed the parse is not the state the verdict names.
//!
//! Absent, it returns immediately.

const std = @import("std");
const g = @import("grammar.zig");
const import = @import("import.zig");
const press = @import("press.zig");

const asked = ".local/orchestrate/wall.txt";

test "what the table decided at a symbol" {
    const gpa = std.testing.allocator;
    var threaded = std.Io.Threaded.init(gpa, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const request = std.Io.Dir.cwd().readFileAlloc(io, asked, gpa, .limited(1 << 16)) catch return;
    defer gpa.free(request);

    var path: []const u8 = "";
    var after: ?[]const u8 = null;
    var before: ?[]const u8 = null;
    var on: ?[]const u8 = null;
    var ration: ?u32 = null;
    var loud = false;
    var lines = std.mem.tokenizeScalar(u8, request, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        if (rest(line, "after ")) |s| {
            after = s;
        } else if (rest(line, "before ")) |s| {
            before = s;
        } else if (rest(line, "on ")) |s| {
            on = s;
        } else if (eq(line, "trace")) {
            loud = true;
        } else if (rest(line, "growth ")) |s| {
            ration = std.fmt.parseInt(u32, s, 10) catch null;
        } else if (path.len == 0) {
            path = line;
        }
    }
    if (path.len == 0) return;

    const source = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 << 20));
    defer gpa.free(source);
    var gr = try import.treeSitter(gpa, source);
    defer gr.deinit();

    const token: ?u32 = if (on) |name| find(&gr, name) else null;
    if (on != null and token == null) {
        std.debug.print("{s}: no terminal named {s}\n", .{ gr.name, on.? });
        return;
    }

    const ask: Ask = .{ .after = after, .before = before, .on = on, .token = token };
    {
        if (loud) press.setTrace(true);
        defer press.setTrace(false);
        var built = try press.tables(gpa, &gr);
        defer built.deinit();
        if (ask.after == null and ask.before == null) {
            wherever(&built, ask);
        } else {
            try survey(&gr, &built, ask, true);
        }
    }
    // The same question of a bigger ration. A cell a seam calls cuttable is a
    // cell some arrival partition removes, and the plan is cut back to fit under
    // a state ceiling - so "cuttable and still folding" has two readings, and
    // only pressing again separates them: the ration was too small, or the round
    // that cell belonged to was dropped for gaining nothing.
    if (ration) |n| {
        press.setGrowth(n);
        defer press.setGrowth(4);
        var wider = try press.tables(gpa, &gr);
        defer wider.deinit();
        std.debug.print("at growth {d}:\n", .{n});
        if (ask.after == null and ask.before == null) {
            wherever(&wider, ask);
        } else {
            try survey(&gr, &wider, ask, false);
        }
    }
}

/// One terminal, every state. A wall is the press's only if some state held a
/// read on the token and the resolution took it away, so the counts that matter
/// are `read_dropped` frayed cells and how many of those a seam calls cuttable;
/// the number of states that read the token on is the ceiling on where the loop
/// could have been standing instead.
fn wherever(built: *const press.Result, ask: Ask) void {
    const t = ask.token orelse return;
    var reads: u32 = 0;
    var folds: u32 = 0;
    for (0..built.collection.states.len) |at| {
        switch (built.tables.at(@intCast(at), t).kind) {
            .shift => reads += 1,
            .reduce => folds += 1,
            else => {},
        }
    }
    var dropped: u32 = 0;
    var wrongly_folded: u32 = 0;
    var cuttable: u32 = 0;
    for (built.tables.frayed) |f| {
        if (f.terminal != t) continue;
        switch (f.harm) {
            .read_dropped => dropped += 1,
            .fold_dropped => wrongly_folded += 1,
        }
        if (built.tables.seamAt(f.state)) |seam| {
            if (std.mem.indexOfScalar(u32, seam.over, t) != null and seam.arrivals > 1 and
                std.mem.indexOfScalar(u32, seam.stubborn, t) == null) cuttable += 1;
        }
        if (dropped + wrongly_folded <= 6) std.debug.print(
            "state {d}: {s} {s}\n",
            .{ f.state, ask.on.?, @tagName(f.harm) },
        );
    }
    std.debug.print(
        "{s} over {d} states: {d} read on, {d} fold; frayed {d} " ++
            "({d} read_dropped, {d} cuttable)\n",
        .{ ask.on.?, built.collection.states.len, reads, folds, dropped + wrongly_folded, dropped, cuttable },
    );
}

const Ask = struct {
    after: ?[]const u8,
    before: ?[]const u8,
    on: ?[]const u8,
    token: ?u32,
};

/// Every item standing the dot beside the asked symbol, and what its state's row
/// says about the asked token. Rows are worth reading once; a second press only
/// needs the counts, because splitting renumbers states and the comparable thing
/// between two presses is how many of these cells read on rather than fold.
fn survey(gr: *const g.Grammar, built: *const press.Result, ask: Ask, rows: bool) !void {
    var hits: u32 = 0;
    var reads: u32 = 0;
    var folds: u32 = 0;
    var invented: u32 = 0;
    var cuttable: u32 = 0;
    for (built.collection.states, 0..) |st, at| {
        for (st.kernel) |item| {
            const p = gr.productions[item.prod];
            const beside = if (ask.after) |name|
                item.dot > 0 and eq(gr.nameOf(p.rhs[item.dot - 1]), name)
            else if (ask.before) |name|
                item.dot < p.rhs.len and eq(gr.nameOf(p.rhs[item.dot]), name)
            else
                false;
            if (!beside) continue;

            hits += 1;
            if (rows) {
                std.debug.print("state {d}: {s} ->", .{ at, gr.nameOf(p.lhs) });
                for (p.rhs, 0..) |sym, k| {
                    if (k == item.dot) std.debug.print(" .", .{});
                    std.debug.print(" {s}", .{gr.nameOf(sym)});
                }
                if (item.dot == p.rhs.len) std.debug.print(" .", .{});
            }
            if (ask.token) |t| {
                switch (built.tables.at(@intCast(at), t).kind) {
                    .shift => reads += 1,
                    .reduce => folds += 1,
                    else => {},
                }
                if (built.tables.seamAt(@intCast(at))) |seam| {
                    if (std.mem.indexOfScalar(u32, seam.over, t) != null) {
                        invented += 1;
                        if (seam.arrivals > 1 and
                            std.mem.indexOfScalar(u32, seam.stubborn, t) == null) cuttable += 1;
                    }
                }
                if (rows) decided(gr, built, @intCast(at), t, ask.on.?);
            }
            if (rows) std.debug.print("\n", .{});
        }
    }
    const floor = built.tables.floor();
    std.debug.print(
        "{d} item(s) over {d} states, unfolded {d}: {d} read on, {d} fold " ++
            "({d} invented, {d} cuttable); floor open {d} of {d}\n",
        .{
            hits,          built.collection.states.len, built.unfolded, reads, folds,
            invented,      cuttable,                    floor.open,     floor.total(),
        },
    );
}

/// What one cell says, and whose answer it is.
fn decided(
    gr: *const g.Grammar,
    built: *const press.Result,
    at: u32,
    token: u32,
    name: []const u8,
) void {
    const act = built.tables.at(at, token);
    std.debug.print("   | {s} {s}", .{ name, @tagName(act.kind) });
    switch (act.kind) {
        .shift => std.debug.print(" to {d}", .{act.value}),
        .reduce => {
            const folded = gr.productions[act.value];
            std.debug.print(" {s} ->", .{gr.nameOf(folded.lhs)});
            for (folded.rhs) |sym| std.debug.print(" {s}", .{gr.nameOf(sym)});
        },
        else => {},
    }
    for (built.tables.conflicts) |k| {
        if (k.state != at or k.terminal != token) continue;
        std.debug.print("  [{s} {s} over {s}]", .{
            @tagName(k.class), @tagName(k.kind), @tagName(k.other.kind),
        });
        break;
    }
    for (built.tables.frayed) |f| {
        if (f.state != at or f.terminal != token) continue;
        std.debug.print("  [frayed, {s}]", .{@tagName(f.harm)});
        break;
    }
    if (built.tables.seamAt(at)) |seam| {
        if (std.mem.indexOfScalar(u32, seam.over, token) != null) {
            const stuck = std.mem.indexOfScalar(u32, seam.stubborn, token) != null;
            std.debug.print("  [invented by a merge of {d} arrivals, {s}]", .{
                seam.arrivals,
                if (seam.arrivals <= 1) "alone" else if (stuck) "stuck" else "cuttable",
            });
        }
    }
}

fn rest(line: []const u8, head: []const u8) ?[]const u8 {
    return if (std.mem.startsWith(u8, line, head)) line[head.len..] else null;
}

fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn find(gr: anytype, name: []const u8) ?u32 {
    for (gr.names[0..gr.terminal_count], 0..) |it, sym| if (eq(it, name)) return @intCast(sym);
    return null;
}

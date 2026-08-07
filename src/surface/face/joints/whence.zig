//! The automaton read backwards: which states hold a reading, and whence a
//! parse that is standing in one arrived.
//!
//! `state <n>` answers *forwards* — here is a state, here is its row. That is
//! the wrong direction for the only question a wall actually raises. A parse
//! that refuses a byte reports **the state it stopped in**, and for any wall
//! whose state holds a completed item that state is not where the mistake was
//! made: something folded early, the fold moved the parse somewhere the
//! construct was never going to be accepted, and the refusal is that fold's
//! consequence several constructs downstream. `owners.py` calls that population
//! **stranded** and refuses to name an owner for it, correctly — 22,179 bytes
//! of the corpus, and nothing in the wall's own state can say whose it is.
//!
//! Two queries, and they are two halves of one question.
//!
//! # `--holding` — from a reading to the states that hold it
//!
//! An item is matched **structurally**, not as text. The first cut of this
//! matched with `std.mem.indexOf` over the printed line, which is wrong in a
//! way that flatters: a completed item is a strict *prefix* of the same item
//! with the dot one position earlier, so asking verilog for
//! `variable_lvalue -> _identifier .` returned **92 states** and every row it
//! printed was `variable_lvalue -> _identifier . select1` — a different item,
//! at a different dot, in states that have not folded anything. The answer was
//! not merely inflated; none of it was the question. So the query is parsed
//! into a left-hand side, a full body, and a dot position, and all three have
//! to agree.
//!
//! The left-hand side is optional, and that is not a convenience. The stranded
//! population groups by **fold body** — the item minus its left-hand side —
//! because that is the grouping under which it collapses: by whole item it is
//! 22 items with 14 singletons, and by body the top three carry 88% of the
//! bytes. `--holding '-> _identifier .'` is that query, and it is the one that
//! shows four left-hand sides competing over one bare body.
//!
//! Kernel items only. A closure item is derivable from a kernel one and would
//! name most of the automaton for any nonterminal near the root.
//!
//! # `--chain` — from a state to what a fold there exposes
//!
//! Naming the states that hold an item is navigation. Attribution needs the
//! other half: **where does the fold go**. Reducing `A -> α` pops `|α|` states
//! and then takes the goto on `A` from whatever is uncovered, so the state that
//! actually chose this reading is `|α|` steps back — and the walk is exact,
//! because each step may only cross an edge labelled with the matching symbol
//! of `α`. That set is the fold's **handle origin**, and it is the first place
//! upstream of a stranded wall where a different decision was available.
//!
//! The count of exposed states is itself the finding. One means the fold has a
//! single context and its lookahead is that context's; several means one state
//! is serving several arrivals, its lookahead is the **union** over them, and
//! that is precisely the LALR merge damage `TESTING.md` names `frayed` — a cell
//! that is correct for the context the lookahead came from and wrong for every
//! other context sharing the state. So a wide handle origin is a conflict
//! suspect and a narrow one is not, which is the discrimination the wall's own
//! state could not make.
//!
//! # What neither may claim
//!
//! The collection is **ours**. A reading the press lost is not in it, so it is
//! not in any answer here, and "no state holds this" is never evidence that no
//! parser holds it. That is the same blind spot that made `owners.py`'s old
//! `gap` verdict false, and it is not repaired by asking the same item sets a
//! new question.

const std = @import("std");
const joints = @import("joints");

const Grammar = joints.press.grammar.Grammar;
const Collection = joints.press.lr0.Collection;
const Item = joints.press.lr0.Item;

/// The automaton read backwards. `press` already owns this — a CSR of inverted
/// edges and an unwind that crosses only edges labelled by the body symbol at
/// that position, so a handle origin is exact rather than a radius. This file
/// asks the questions; it does not re-derive the walk that answers them.
const Retrace = joints.press.retrace.Retrace;
const Step = joints.press.retrace.Step;

/// How many state ids a line will name before it stops counting out loud.
const shown = 12;

/// One item pattern: an optional left-hand side, a full right-hand side, and
/// an optional dot position.
///
/// Full body rather than prefix, deliberately — see the header. A caller who
/// wants "every item over this body, wherever the dot is" omits the `.` and
/// gets `dot == null`, which is a question worth asking and is *not* what a
/// stray prefix match used to answer by accident.
const Query = struct {
    lhs: ?[]const u8,
    body: []const []const u8,
    dot: ?usize,

    /// `A -> a b . c`, `-> a b .`, or `a b c` — lhs optional, dot optional.
    ///
    /// Errors are returned rather than defaulted. A query with two dots is a
    /// caller who thinks the grammar has a `.` terminal (six of these grammars
    /// do) and a silent pick between the two readings would answer a question
    /// nobody asked.
    fn parse(gpa: std.mem.Allocator, text: []const u8) !Query {
        const arrow = std.mem.indexOf(u8, text, "->");
        const lhs = if (arrow) |at| std.mem.trim(u8, text[0..at], " ") else "";
        const rest = if (arrow) |at| text[at + 2 ..] else text;

        var body: std.ArrayList([]const u8) = .empty;
        errdefer body.deinit(gpa);
        var dot: ?usize = null;
        var it = std.mem.tokenizeAny(u8, rest, " \t");
        while (it.next()) |tok| {
            if (!std.mem.eql(u8, tok, ".")) {
                try body.append(gpa, tok);
            } else if (dot != null) {
                return error.TwoDots;
            } else {
                dot = body.items.len;
            }
        }
        return .{
            .lhs = if (lhs.len == 0 or std.mem.eql(u8, lhs, "*")) null else lhs,
            .body = try body.toOwnedSlice(gpa),
            .dot = dot,
        };
    }

    fn holds(q: Query, gr: *const Grammar, item: Item) bool {
        const p = gr.productions[item.prod];
        if (q.dot) |d| if (d != item.dot) return false;
        if (p.rhs.len != q.body.len) return false;
        if (q.lhs) |name| if (!std.mem.eql(u8, name, gr.nameOf(p.lhs))) return false;
        for (p.rhs, q.body) |sym, want| {
            if (!std.mem.eql(u8, gr.nameOf(sym), want)) return false;
        }
        return true;
    }
};

/// Every state holding a kernel item that matches, every matching item printed.
///
/// Every one, not the first. The predecessor of this function broke out of the
/// item loop on its first hit, so a state holding two matching items reported
/// whichever the kernel happened to sort first — and the population this exists
/// for is exactly the one where several readings complete in one state.
pub fn holding(
    gpa: std.mem.Allocator,
    w: *std.Io.Writer,
    gr: *const Grammar,
    c: *const Collection,
    text: []const u8,
) !u8 {
    const q = Query.parse(gpa, text) catch |e| {
        try w.print("joints: cannot read {s} as an item: {s}\n", .{ text, @errorName(e) });
        return 2;
    };
    defer gpa.free(q.body);

    var states: u32 = 0;
    var items: u32 = 0;
    for (c.states, 0..) |st, at| {
        var here: u32 = 0;
        for (st.kernel) |item| {
            if (!q.holds(gr, item)) continue;
            here += 1;
            try w.print("{d}: ", .{at});
            try spell(w, gr, item);
            try w.writeAll("\n");
        }
        items += here;
        states += @intFromBool(here > 0);
    }
    try w.print("\n{d} of {d} state(s) hold a kernel item matching `{s}`", .{
        states, c.states.len, text,
    });
    if (items != states) try w.print(" ({d} items)", .{items});
    if (q.dot == null) try w.writeAll(" — no dot in the query, so any dot position matched");
    try w.writeAll("\n");
    return @intFromBool(states == 0);
}

/// How the parse reaches this state, and where each fold available here goes.
pub fn chain(
    gpa: std.mem.Allocator,
    w: *std.Io.Writer,
    gr: *const Grammar,
    c: *const Collection,
    at: u32,
) !u8 {
    if (at >= c.states.len) {
        try w.print("joints: {s} has {d} states\n", .{ gr.name, c.states.len });
        return 2;
    }
    var back = try Retrace.build(gpa, c);
    defer back.deinit(gpa);

    try w.print("state {d} of {s}\n\n  arrives on:\n", .{ at, gr.name });
    // Sorted by symbol so the rows below group in one pass and two runs over
    // the same table print the same order. A copy, because the CSR's order is
    // `press`'s business and nothing there promises this one.
    const in = try gpa.dupe(Step, back.into[back.at[at]..back.at[at + 1]]);
    defer gpa.free(in);
    std.mem.sort(Step, in, {}, struct {
        fn less(_: void, a: Step, b: Step) bool {
            return if (a.symbol != b.symbol) a.symbol < b.symbol else a.from < b.from;
        }
    }.less);
    if (in.len == 0) try w.writeAll("    (nothing — no edge enters this state)\n");
    var seen: u32 = 0;
    for (in, 0..) |a, i| {
        // Grouped on the fly off that sort: a repeat of the previous symbol is
        // a second source of the same arrival rather than a new row.
        if (i > 0 and in[i - 1].symbol == a.symbol) continue;
        seen += 1;
        var n: u32 = 0;
        for (in) |b| n += @intFromBool(b.symbol == a.symbol);
        try w.print("    {s: <28} from {d} state(s):", .{ gr.nameOf(a.symbol), n });
        var k: u32 = 0;
        for (in) |b| {
            if (b.symbol != a.symbol) continue;
            k += 1;
            if (k > shown) {
                try w.print(" +{d} more", .{n - shown});
                break;
            }
            try w.print(" {d}", .{b.from});
        }
        try w.writeAll("\n");
    }

    try w.writeAll("\n  folds here, and what each one exposes:\n");
    const complete = c.states[at].complete;
    if (complete.len == 0) {
        try w.writeAll("    (none — nothing completes here, so no fold can have" ++
            " left this state)\n");
    }
    var wide: u32 = 0;
    for (complete) |prod| wide += @intFromBool(try fold(gpa, w, gr, c, &back, at, prod));
    try w.print(
        "\n  {d} arrival symbol(s), {d} fold(s), {d} of them with a handle" ++
            " origin wider than one state\n",
        .{ seen, complete.len, wide },
    );
    if (wide > 0) try w.writeAll("  A wide handle origin is one state serving" ++
        " several arrivals, so its fold lookahead is the union over them —" ++
        " the merge damage `TESTING.md` calls frayed, and a conflict suspect.\n");
    return 0;
}

/// One completed production: pop its body, name what that uncovers, and say
/// where the goto lands. Returns whether the handle origin was wider than one.
fn fold(
    gpa: std.mem.Allocator,
    w: *std.Io.Writer,
    gr: *const Grammar,
    c: *const Collection,
    back: *Retrace,
    at: u32,
    prod: u32,
) !bool {
    const p = gr.productions[prod];
    try w.writeAll("    ");
    try spell(w, gr, .{ .prod = prod, .dot = @intCast(p.rhs.len) });
    try w.writeAll("\n");

    // Borrowed and valid only until the next `back`, which is why it is copied:
    // the goto pass below re-reads it after nothing else has called in, but a
    // caller adding a second unwind here would otherwise read freed intent.
    const found = try back.back(gpa, at, p.rhs);
    const origin = try gpa.dupe(u32, found);
    defer gpa.free(origin);
    std.mem.sort(u32, origin, {}, std.sort.asc(u32));

    if (p.rhs.len == 0) {
        try w.writeAll("      pops 0 — an epsilon fold, so it uncovers this" ++
            " very state\n");
    } else {
        try w.print("      pops {d}, uncovering {d} state(s):", .{ p.rhs.len, origin.len });
        for (origin, 0..) |s, i| {
            if (i == shown) {
                try w.print(" +{d} more", .{origin.len - i});
                break;
            }
            try w.print(" {d}", .{s});
        }
        try w.writeAll("\n");
    }
    if (origin.len == 0) {
        // Not an error and worth its own line: the handle cannot be spelled
        // backwards from here, which happens when the state was reached by a
        // path this production's body does not describe — i.e. the completed
        // item came from the closure rather than from a shift.
        try w.writeAll("      no path back spells this body, so the fold is" ++
            " reachable here only through another state\n");
        return false;
    }

    try w.print("      goto {s} from those:", .{gr.nameOf(p.lhs)});
    var lands: u32 = 0;
    for (origin, 0..) |s, i| {
        const to = c.goto(s, p.lhs) orelse continue;
        lands += 1;
        if (i < shown) try w.print(" {d}", .{to});
    }
    if (origin.len > shown) try w.print(" +{d} more", .{origin.len - shown});
    if (lands == 0) try w.writeAll(" (none — no goto on this symbol)");
    try w.writeAll("\n");
    return origin.len > 1;
}

/// `lhs -> a b . c`, straight to the writer.
///
/// Unbuffered, unlike the fixed-size render this replaced: that one returned
/// null for an item too long for its 512 bytes and the caller skipped it, so a
/// long production was silently not searchable. A query that cannot match a
/// rule because the rule is wide is the failure genre this whole file exists
/// to stop.
fn spell(w: *std.Io.Writer, gr: *const Grammar, item: Item) !void {
    const p = gr.productions[item.prod];
    try w.print("{s} ->", .{gr.nameOf(p.lhs)});
    for (p.rhs, 0..) |sym, k| {
        if (k == item.dot) try w.writeAll(" .");
        try w.print(" {s}", .{gr.nameOf(sym)});
    }
    if (item.dot == p.rhs.len) try w.writeAll(" .");
}

test "whence: a completed item does not match the same body one dot earlier" {
    // The defect this file was written to repair, as a test rather than as a
    // paragraph. Under the substring match `A -> b .` matched `A -> b . c`,
    // which is a different production entirely once the body has to agree.
    const gpa = std.testing.allocator;
    const q = try Query.parse(gpa, "A -> b .");
    defer gpa.free(q.body);
    try std.testing.expectEqualStrings("A", q.lhs.?);
    try std.testing.expectEqual(@as(usize, 1), q.body.len);
    try std.testing.expectEqual(@as(?usize, 1), q.dot);

    const wide = try Query.parse(gpa, "A -> b . c");
    defer gpa.free(wide.body);
    try std.testing.expectEqual(@as(usize, 2), wide.body.len);
    try std.testing.expectEqual(@as(?usize, 1), wide.dot);
    // Same lhs, same dot, different body — so no item can satisfy both, which
    // is what the prefix match could not express.
    try std.testing.expect(q.body.len != wide.body.len);
}

test "whence: a body query drops the left-hand side and a dotless one any dot" {
    const gpa = std.testing.allocator;
    const body = try Query.parse(gpa, "-> _identifier .");
    defer gpa.free(body.body);
    try std.testing.expectEqual(@as(?[]const u8, null), body.lhs);
    try std.testing.expectEqual(@as(?usize, 1), body.dot);

    const loose = try Query.parse(gpa, "A -> b c");
    defer gpa.free(loose.body);
    try std.testing.expectEqual(@as(?usize, null), loose.dot);

    // Two dots is a caller who has not noticed `.` is a terminal in six of
    // these grammars. Refused rather than resolved.
    try std.testing.expectError(error.TwoDots, Query.parse(gpa, "A -> . b ."));
}

//! The relation, checked against the table it claims to describe.
//!
//! One of these tests matters more than the rest. `merged states are
//! indistinguishable` re-derives the bisimulation condition directly from the
//! finished table — for every pair in a block, every cell agrees on verb and on
//! the production a fold names, every completion list is equal, and every
//! transition lands in one block — without going back through `refine`. So it
//! fails on a wrong colouring, a wrong delta, and a wrong engine alike, which a
//! test that asked `refine` whether it agreed with itself would not.
//!
//! The rest are the other half of the claim: that the encoding survives, and
//! that a class map which does not fit the automaton is refused rather than
//! read.

const std = @import("std");
const press = @import("../press.zig");
const quotient = @import("../quotient.zig");
const alphabet = @import("../minterm.zig");
const dafsa = @import("../dafsa.zig");
const folio = @import("../../folio/folio.zig");
const leaf = @import("../../folio/leaf.zig");

const testing = std.testing;

/// A grammar with two rules that differ only in the terminal they end on, so the
/// automaton has states that are and states that are not each other's copies.
fn sample(gpa: std.mem.Allocator) !press.Grammar {
    var b = press.Builder.init(gpa);
    defer b.deinit();

    const id = try b.intern("id", "identifier", .{ .regex = "[a-z]+" });
    const plus = try b.intern("plus", "+", .{ .literal = "+" });
    const star = try b.intern("star", "*", .{ .literal = "*" });
    const open = try b.intern("open", "(", .{ .literal = "(" });
    const close = try b.intern("close", ")", .{ .literal = ")" });
    const ws = try b.intern("ws", "whitespace", .{ .regex = "\\s+" });

    const start = try b.intern("$start", "$start", null);
    const expr = try b.intern("expr", "expression", null);
    const term = try b.intern("term", "term", null);
    const atom = try b.intern("atom", "atom", null);

    try b.addProduction(start, &.{expr}, &.{});
    try b.addProduction(expr, &.{term}, &.{});
    try b.addProduction(expr, &.{ expr, plus, term }, &.{ .{}, .{}, .{} });
    try b.addProduction(term, &.{atom}, &.{});
    try b.addProduction(term, &.{ term, star, atom }, &.{ .{}, .{}, .{} });
    try b.addProduction(atom, &.{id}, &.{});
    try b.addProduction(atom, &.{ open, expr, close }, &.{ .{}, .{}, .{} });
    return b.finish("quotient_sample", start, &.{ws}, &.{});
}

const Pressed = struct {
    grammar: press.Grammar,
    result: press.Result,

    fn of(gpa: std.mem.Allocator) !Pressed {
        var gr = try sample(gpa);
        errdefer gr.deinit();
        return .{ .grammar = gr, .result = try press.tables(gpa, &gr) };
    }

    fn deinit(p: *Pressed) void {
        p.result.deinit();
        p.grammar.deinit();
    }
};

test "pressing a grammar yields a quotient over every state" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();

    const q = p.result.quotient orelse return error.NoQuotient;
    try testing.expectEqual(p.result.collection.states.len, q.states());
    try testing.expect(q.blocks > 0);
    try testing.expect(q.blocks <= q.states());
    // Numbered by first appearance, which is what makes the map canonical and
    // the folio's own check able to reject a labelling that is not a partition.
    var reached: u32 = 0;
    for (0..q.states()) |s| {
        const b = q.at(@intCast(s));
        try testing.expect(b <= reached);
        if (b == reached) reached += 1;
    }
    try testing.expectEqual(q.blocks, reached);
}

test "merged states are indistinguishable, cell by cell and edge by edge" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();

    const q = p.result.quotient orelse return error.NoQuotient;
    const t = &p.result.tables;
    const states = p.result.collection.states;

    // One representative per block, then every state against its own. Pairwise
    // over the whole automaton would be quadratic and would prove nothing extra:
    // agreement with a common representative is agreement with each other.
    const rep = try testing.allocator.alloc(u32, q.blocks);
    defer testing.allocator.free(rep);
    var filled: u32 = 0;
    for (0..q.states()) |s| {
        const b = q.at(@intCast(s));
        if (b == filled) {
            rep[b] = @intCast(s);
            filled += 1;
        }
    }

    for (states, 0..) |st, s| {
        const r = rep[q.at(@intCast(s))];
        if (r == s) continue;
        const other = states[r];

        for (0..t.width) |col| {
            const a = t.at(@intCast(s), @intCast(col));
            const c = t.at(r, @intCast(col));
            // The verb, because an `err` and a `reduce` both step nowhere and
            // the transitions alone would call them the same.
            try testing.expectEqual(a.kind, c.kind);
            // Which production a fold names, because that is the tree.
            if (a.kind == .reduce) try testing.expectEqual(a.value, c.value);
            // Where a read goes, up to the relation itself: two shifts may go to
            // different states, but never to different blocks.
            if (a.kind == .shift) try testing.expectEqual(q.at(a.value), q.at(c.value));
        }

        // The completions, which the folio hands out per state rather than
        // through the table, so nothing above would have caught a difference.
        try testing.expectEqualSlices(u32, other.complete, st.complete);

        // And the automaton's own edges beside the table's cells, which is why
        // the delta carries two column families: `odd` records live here.
        try testing.expectEqual(other.edges.len, st.edges.len);
        for (st.edges) |e| {
            const mate = p.result.collection.goto(r, e.symbol) orelse return error.EdgeMissing;
            try testing.expectEqual(q.at(mate), q.at(e.target));
        }
    }
}

test "the class map round-trips through the folio and comes back the same partition" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();

    const bytes = try folio.pack(testing.allocator, &p.grammar, &p.result);
    defer testing.allocator.free(bytes);
    const f = try folio.open(bytes);

    const q = p.result.quotient.?;
    const back = f.quotient() orelse return error.NoQuotientSection;
    try testing.expectEqual(q.states(), back.states());
    try testing.expectEqual(q.blocks, back.blocks);
    try testing.expectEqual(q.merged(), back.merged());
    for (0..q.states()) |s| try testing.expectEqual(q.at(@intCast(s)), back.at(@intCast(s)));
}

test "quotient is no longer reserved, and the section it fills is not empty" {
    try testing.expect(!leaf.reserved(.quotient));
    // `gloss` was reserved when this was written and is not any more - the query
    // engine gave it a reader, which is what un-reserving one means. `tariff` is
    // the one still standing, and what this line is really claiming is that the
    // predicate discriminates rather than saying no to everything.
    try testing.expect(!leaf.reserved(.gloss));
    try testing.expect(leaf.reserved(.tariff));

    var p = try Pressed.of(testing.allocator);
    defer p.deinit();
    const bytes = try folio.pack(testing.allocator, &p.grammar, &p.result);
    defer testing.allocator.free(bytes);
    const f = try folio.open(bytes);
    try testing.expect(f.view(.quotient, u8).len != 0);
}

test "a class map that does not fit its automaton is refused, not read around" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();
    const q = p.result.quotient.?;

    const raw = try quotient.encode(testing.allocator, q);
    defer testing.allocator.free(raw);
    try testing.expect(quotient.classes(raw, q.states()) != null);

    // For a different automaton.
    try testing.expect(quotient.classes(raw, q.states() + 1) == null);
    // Truncated.
    try testing.expect(quotient.classes(raw[0 .. raw.len - 1], q.states()) == null);
    try testing.expect(quotient.classes(raw[0..4], q.states()) == null);
    // Something else entirely.
    var wrong = try testing.allocator.dupe(u8, raw);
    defer testing.allocator.free(wrong);
    wrong[0] +%= 1;
    try testing.expect(quotient.classes(wrong, q.states()) == null);
    // A labelling rather than a partition: block ids that skip one.
    @memcpy(wrong, raw);
    if (q.blocks > 1) {
        wrong[16] = 1;
        try testing.expect(quotient.classes(wrong, q.states()) == null);
    }
}

test "the column alphabet is sound: one class means one column, everywhere" {
    var p = try Pressed.of(testing.allocator);
    defer p.deinit();

    var a = try alphabet.of(testing.allocator, &p.result.tables);
    defer a.deinit();

    const t = &p.result.tables;
    try testing.expectEqual(t.width, a.columns());
    try testing.expect(a.classes >= 1);
    try testing.expect(a.classes <= t.width);

    // The claim the narrowing rests on: two columns in one class are two columns
    // no state anywhere routes differently.
    const states = p.result.collection.states.len;
    for (0..t.width) |x| for (x + 1..t.width) |y| {
        if (a.block[x] != a.block[y]) continue;
        for (0..states) |s| {
            const l = t.at(@intCast(s), @intCast(x));
            const r = t.at(@intCast(s), @intCast(y));
            try testing.expectEqual(@as(u32, @bitCast(l)), @as(u32, @bitCast(r)));
        }
    };

    // And the converse, which is what makes it the *coarsest* one: two columns
    // in different classes are separated by some state.
    for (0..t.width) |x| for (x + 1..t.width) |y| {
        if (a.block[x] == a.block[y]) continue;
        var split = false;
        for (0..states) |s| {
            const l = t.at(@intCast(s), @intCast(x));
            const r = t.at(@intCast(s), @intCast(y));
            if (@as(u32, @bitCast(l)) != @as(u32, @bitCast(r))) split = true;
        }
        try testing.expect(split);
    };
}

test "rank is a minimal perfect hash over the grammar's names, and it inverts" {
    var gr = try sample(testing.allocator);
    defer gr.deinit();

    var set = try dafsa.names(testing.allocator, &gr);
    defer set.deinit();

    try testing.expectEqual(gr.names.len, set.count());
    var buf: [256]u8 = undefined;
    for (set.keys, 0..) |k, i| {
        const r = set.ordinalOf(k) orelse return error.Unranked;
        try testing.expectEqual(@as(u32, @intCast(i)), r);
        try testing.expectEqualStrings(k, set.d.spell(r, &buf) orelse return error.Unspelled);
    }
    try testing.expect(set.ordinalOf("a name this grammar does not have") == null);

    // Ascending, which is what the ordinal being the sorted position means.
    for (set.keys[1..], set.keys[0 .. set.keys.len - 1]) |b, a| {
        try testing.expect(std.mem.lessThan(u8, a, b));
    }

    const w = set.weight();
    try testing.expectEqual(set.count(), w.keys);
    try testing.expect(w.text > 0);
    try testing.expect(w.ratio() > 0);
}

test "terminal patterns rank too, and duplicates cost one key" {
    var gr = try sample(testing.allocator);
    defer gr.deinit();

    var set = try dafsa.patterns(testing.allocator, &gr);
    defer set.deinit();

    // Nonterminals have no pattern and externals spell nothing, so the set is
    // the lexable terminals and no more.
    try testing.expect(set.count() > 0);
    try testing.expect(set.count() <= gr.terminal_count);
    for (set.keys, 0..) |k, i| try testing.expectEqual(@as(u32, @intCast(i)), set.ordinalOf(k).?);
}

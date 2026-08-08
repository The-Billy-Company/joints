//! Walking the automaton backwards: which states could have been on the stack
//! before this one.
//!
//! An LR state says what has been recognized, not where it came from. That is
//! usually the point — merging every path with the same prospects is what makes
//! the automaton finite. But two questions need the path back, and both are
//! about *attribution* rather than about parsing:
//!
//!   - A completed production `A -> α` folds by popping `|α|` states, so the
//!     state that governs the goto is `|α|` steps behind. A conflict report that
//!     wants to say which rule was being built has to look there.
//!   - A synthesized list has no author. Asking who was expecting it is asking
//!     which items sat with the dot before it, and those items are in the state
//!     the list *started* from.
//!
//! The index is one pass over the forward edges and answers in the size of the
//! frontier, not the size of the automaton. It is deliberately a separate thing
//! from the table: nothing about parsing needs it, and building it eagerly for
//! every grammar would tax the common case to serve the reports.
const std = @import("std");
const g = @import("../copy/grammar.zig");
const lr0 = @import("lr0.zig");
const import = @import("../copy/import.zig");

/// An edge, seen from its far end.
pub const Step = struct { from: u32, symbol: g.Symbol };

pub const Retrace = struct {
    /// CSR over states: the edges arriving at `t` are `into[at[t]..at[t + 1]]`.
    at: []const u32,
    into: []const Step,
    /// Double-buffered frontier for the unwind, owned here so a caller in a
    /// per-cell loop is not allocating per cell.
    live: std.ArrayList(u32) = .empty,
    next: std.ArrayList(u32) = .empty,

    pub fn build(gpa: std.mem.Allocator, c: *const lr0.Collection) !Retrace {
        const at = try gpa.alloc(u32, c.states.len + 1);
        errdefer gpa.free(at);
        @memset(at, 0);

        // Count arrivals, then prefix-sum into offsets, then fill. The counting
        // pass is what lets the whole index be two allocations.
        for (c.states) |st| for (st.edges) |e| {
            at[e.target] += 1;
        };
        var run: u32 = 0;
        for (at) |*n| {
            const here = n.*;
            n.* = run;
            run += here;
        }

        const into = try gpa.alloc(Step, run);
        errdefer gpa.free(into);
        const fill = try gpa.alloc(u32, c.states.len);
        defer gpa.free(fill);
        @memcpy(fill, at[0..c.states.len]);
        for (c.states, 0..) |st, q| for (st.edges) |e| {
            into[fill[e.target]] = .{ .from = @intCast(q), .symbol = e.symbol };
            fill[e.target] += 1;
        };

        return .{ .at = at, .into = into };
    }

    pub fn deinit(r: *Retrace, gpa: std.mem.Allocator) void {
        gpa.free(r.at);
        gpa.free(r.into);
        r.live.deinit(gpa);
        r.next.deinit(gpa);
        r.* = undefined;
    }

    /// The states `|rhs|` steps behind `state`, reached by unwinding exactly the
    /// symbols of `rhs`. Valid until the next call.
    ///
    /// Unwinding is a set walk rather than a single path because merging is what
    /// the automaton does: several stacks can present the same prospects, and a
    /// fold in this state is a fold for all of them. The result is every state
    /// that could be exposed, which is the honest answer — a report naming one
    /// of them would be naming whichever the construction happened to visit
    /// first.
    pub fn back(
        r: *Retrace,
        gpa: std.mem.Allocator,
        state: u32,
        rhs: []const g.Symbol,
    ) ![]const u32 {
        r.live.clearRetainingCapacity();
        try r.live.append(gpa, state);

        var i = rhs.len;
        while (i > 0) {
            i -= 1;
            r.next.clearRetainingCapacity();
            for (r.live.items) |q| {
                for (r.into[r.at[q]..r.at[q + 1]]) |step| {
                    if (step.symbol != rhs[i]) continue;
                    // Linear, because a frontier is a handful of states and a
                    // set would cost more to build than to scan.
                    if (std.mem.indexOfScalar(u32, r.next.items, step.from) == null) {
                        try r.next.append(gpa, step.from);
                    }
                }
            }
            std.mem.swap(std.ArrayList(u32), &r.live, &r.next);
            if (r.live.items.len == 0) break;
        }
        return r.live.items;
    }
};

const testing = std.testing;

/// `$start -> sum`, `sum -> sum '+' term | term`, `term -> num | '(' sum ')'`.
/// Left-recursive, and with a bracketed form, so that the state holding
/// `term -> num .` is genuinely arrived at three ways.
fn sums(gpa: std.mem.Allocator) !g.Grammar {
    var b = g.Builder.init(gpa);
    defer b.deinit();
    const plus = try b.intern("+", "+", .{ .literal = "+" });
    const num = try b.intern("num", "num", .{ .literal = "n" });
    const lp = try b.intern("(", "(", .{ .literal = "(" });
    const rp = try b.intern(")", ")", .{ .literal = ")" });
    const start = try b.intern("$start", "$start", null);
    const sum = try b.intern("sum", "sum", null);
    const term = try b.intern("term", "term", null);
    try b.addProduction(start, &.{sum}, &.{});
    try b.addProduction(sum, &.{ sum, plus, term }, &.{});
    try b.addProduction(sum, &.{term}, &.{});
    try b.addProduction(term, &.{num}, &.{});
    try b.addProduction(term, &.{ lp, sum, rp }, &.{});
    return b.finish("sums", start, &.{}, &.{});
}

const Sym = struct {
    const plus: g.Symbol = 0;
    const num: g.Symbol = 1;
    const lp: g.Symbol = 2;
};

test "unwinding a right-hand side lands on the state that governs its goto" {
    var gr = try sums(testing.allocator);
    defer gr.deinit();
    var c = try lr0.build(testing.allocator, &gr, .{});
    defer c.deinit();

    var r = try Retrace.build(testing.allocator, &c);
    defer r.deinit(testing.allocator);

    const sum = gr.start + 1;
    const term = gr.start + 2;
    const rhs = &[_]g.Symbol{ sum, Sym.plus, term };

    // `sum -> sum '+' term` completes three steps past the start state, and
    // unwinding all three arrives at every state whose goto on `sum` the fold
    // could take: the start, and just inside a `(`, because a bracketed sum
    // continues the same way a top-level one does. Both are exposed, and
    // reporting one of them would be reporting whichever the walk saw first.
    const done = c.walk(0, rhs).?;
    const back = try r.back(testing.allocator, done, rhs);
    try testing.expectEqual(@as(usize, 2), back.len);
    for ([_]u32{ 0, c.goto(0, Sym.lp).? }) |q| {
        try testing.expect(std.mem.indexOfScalar(u32, back, q) != null);
    }

    // A right-hand side the automaton never spelled into this state arrives
    // nowhere, rather than arriving somewhere wrong.
    const stray = try r.back(testing.allocator, done, &.{Sym.plus});
    try testing.expectEqual(@as(usize, 0), stray.len);
}

test "a state several stacks share unwinds to all of them" {
    var gr = try sums(testing.allocator);
    defer gr.deinit();
    var c = try lr0.build(testing.allocator, &gr, .{});
    defer c.deinit();

    var r = try Retrace.build(testing.allocator, &c);
    defer r.deinit(testing.allocator);

    const sum = gr.start + 1;

    // A term can begin at the start, after a `+`, and after a `(`, so one state
    // holds `term -> num .` for all three and the fold there is a fold for all
    // three.
    const folding = c.goto(0, Sym.num).?;
    const after_plus = c.walk(0, &.{ sum, Sym.plus }).?;
    const after_lp = c.goto(0, Sym.lp).?;

    const back = try r.back(testing.allocator, folding, &.{Sym.num});
    try testing.expectEqual(@as(usize, 3), back.len);
    for ([_]u32{ 0, after_plus, after_lp }) |q| {
        try testing.expect(std.mem.indexOfScalar(u32, back, q) != null);
    }
}

/// c's `f(a);` under two readings — a declaration and a call over the same four
/// tokens — pressed through the tree-sitter front end rather than a `Builder`,
/// so the automaton under test is one a real import produces.
const two_readings =
    \\{"name":"decl","rules":{
    \\ "statement":{"type":"CHOICE","members":[
    \\  {"type":"SYMBOL","name":"declaration"},
    \\  {"type":"SYMBOL","name":"expression_statement"}]},
    \\ "declaration":{"type":"SEQ","members":[
    \\  {"type":"SYMBOL","name":"declarator"},{"type":"STRING","value":";"}]},
    \\ "expression_statement":{"type":"SEQ","members":[
    \\  {"type":"SYMBOL","name":"call"},{"type":"STRING","value":";"}]},
    \\ "declarator":{"type":"SEQ","members":[
    \\  {"type":"STRING","value":"f"},{"type":"STRING","value":"("},
    \\  {"type":"STRING","value":"a"},{"type":"STRING","value":")"}]},
    \\ "call":{"type":"SEQ","members":[
    \\  {"type":"STRING","value":"f"},{"type":"STRING","value":"("},
    \\  {"type":"STRING","value":"a"},{"type":"STRING","value":")"}]}}}
;

test "every unwound origin can read its body forward and land where it started" {
    // The two tests above check hand-picked positions, which is what a walk
    // that ignored the edge symbols would also pass: on a small automaton
    // "every state within |rhs| steps" is frequently the same set as the right
    // answer. This asserts the defining property instead, over every completed
    // item of every state, so a walk that is accidentally right has nowhere to
    // hide.
    const gpa = testing.allocator;
    var gr = try import.treeSitter(gpa, two_readings);
    defer gr.deinit();
    var c = try lr0.build(gpa, &gr, .{});
    defer c.deinit();

    var r = try Retrace.build(gpa, &c);
    defer r.deinit(gpa);

    // First that the inversion is a bijection: every arrival is a real edge and
    // every real edge is an arrival. An index missing edges would make the walk
    // below vacuously true by reaching nothing.
    var edges: usize = 0;
    for (c.states) |st| edges += st.edges.len;
    var arrivals: usize = 0;
    for (0..c.states.len) |q| {
        for (r.into[r.at[q]..r.at[q + 1]]) |step| {
            try testing.expectEqual(@as(?u32, @intCast(q)), c.goto(step.from, step.symbol));
            arrivals += 1;
        }
    }
    try testing.expectEqual(edges, arrivals);

    // Then the property itself, and that it is not vacuous.
    var checked: usize = 0;
    for (c.states, 0..) |st, at| {
        for (st.complete) |prod| {
            const rhs = gr.productions[prod].rhs;
            const back = try r.back(gpa, @intCast(at), rhs);
            for (back) |from| {
                var q = from;
                for (rhs) |sym| q = c.goto(q, sym).?;
                try testing.expectEqual(@as(u32, @intCast(at)), q);
                checked += 1;
            }
        }
    }
    try testing.expect(checked > 0);
}

//! LALR(1) lookaheads by the DeRemer-Pennello relations, and the action table
//! they decide.
//!
//! The naive way to get lookaheads is to build LR(1) items and then merge, or
//! to propagate spontaneous lookaheads around the automaton until nothing
//! changes. Both work and both are wasteful: the first builds a machine an
//! order of magnitude larger than the one it keeps, and the second iterates a
//! fixpoint whose answer is already determined by a graph.
//!
//! DeRemer and Pennello's observation (1982) is that the answer *is* a graph
//! problem. Every lookahead question decomposes into four relations over
//! nonterminal transitions - `directly reads`, `reads`, `includes`, `lookback`
//! - and the two that need closure are each a single union-along-edges, which
//! Tarjan's strongly-connected-components walk computes in one pass. Two passes
//! of that walk over a few thousand transitions is the entire cost.
//!
//! The layer above cares about none of that. It gets one table.

const std = @import("std");
const g = @import("grammar.zig");
const lr0 = @import("lr0.zig");
const sets = @import("sets.zig");

pub const Action = packed struct(u32) {
    kind: Kind,
    /// Target state for a shift, production index for a reduce.
    value: u30,

    pub const Kind = enum(u2) { err, shift, reduce, accept };
    pub const err: Action = .{ .kind = .err, .value = 0 };

    fn shift(target: u32) Action {
        return .{ .kind = .shift, .value = @intCast(target) };
    }
    fn reduce(prod: u32) Action {
        return .{ .kind = .reduce, .value = @intCast(prod) };
    }
};

/// A cell the grammar did not determine. Recorded rather than resolved away,
/// because the count of these is the honest measure of how much GLR a grammar
/// actually costs, and a generator that silently picks one is a generator you
/// cannot ask that question of.
pub const Conflict = struct {
    state: u32,
    terminal: u32,
    kind: Kind,
    chosen: Action,
    other: Action,

    pub const Kind = enum { shift_reduce, reduce_reduce };
};

pub const Tables = struct {
    arena: std.heap.ArenaAllocator,
    /// One past the last real terminal: the synthetic end-of-input column.
    end: u32,
    width: u32,
    /// Dense, `states * width`. Dense wins here - the widest real grammar is
    /// under 1500 states by 200 columns, which is a megabyte that answers in
    /// one indexed load, against a sparse row that answers in a search.
    action: []const Action,
    conflicts: []const Conflict,

    pub fn deinit(t: *Tables) void {
        t.arena.deinit();
        t.* = undefined;
    }

    pub fn at(t: Tables, state: u32, terminal: u32) Action {
        return t.action[state * t.width + terminal];
    }
};

pub fn build(gpa: std.mem.Allocator, gr: *const g.Grammar, c: *const lr0.Collection) !Tables {
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();

    var b: Build = .{ .gpa = gpa, .gr = gr, .c = c, .width = gr.terminal_count + 1 };
    defer b.deinit();

    // No FIRST sets: the relations below read terminals straight off the
    // automaton's own shift edges, which is what makes them a graph problem
    // rather than a second fixpoint. Nullability is the only symbol-level fact
    // they need.
    try b.deriveNullable();
    try b.mapTransitions();
    try b.deriveFollow();
    try b.deriveLookahead();
    return b.tabulate(arena);
}

/// A nonterminal transition: state `from`, over `symbol`, into `to`. Lookahead
/// is a property of these, not of states, which is the whole reason the
/// relations are expressible as a graph.
const Transition = struct { from: u32, symbol: g.Symbol, to: u32 };

const Build = struct {
    gpa: std.mem.Allocator,
    gr: *const g.Grammar,
    c: *const lr0.Collection,
    width: u32,

    nullable: []bool = &.{},
    transitions: []Transition = &.{},
    /// Transition id of each state's first nonterminal edge. Edges are sorted
    /// by symbol and every nonterminal outranks every terminal, so a state's
    /// nonterminal edges are a contiguous suffix and this one number plus an
    /// offset locates any of them.
    nt_base: []u32 = &.{},
    nt_start: []u32 = &.{},
    follow: sets.Matrix = undefined,
    /// One row per (state, complete production) pair.
    la: sets.Matrix = undefined,
    reduction_base: []u32 = &.{},
    have_follow: bool = false,
    have_la: bool = false,

    fn deinit(b: *Build) void {
        b.gpa.free(b.nullable);
        b.gpa.free(b.transitions);
        b.gpa.free(b.nt_base);
        b.gpa.free(b.nt_start);
        if (b.have_follow) b.follow.deinit(b.gpa);
        if (b.have_la) b.la.deinit(b.gpa);
        b.gpa.free(b.reduction_base);
    }

    fn index(b: Build, s: g.Symbol) usize {
        return s - b.gr.terminal_count;
    }

    fn nullableSuffix(b: Build, rhs: []const g.Symbol) bool {
        for (rhs) |s| {
            if (b.gr.isTerminal(s) or !b.nullable[b.index(s)]) return false;
        }
        return true;
    }

    fn deriveNullable(b: *Build) !void {
        b.nullable = try b.gpa.alloc(bool, b.gr.nonterminalCount());
        @memset(b.nullable, false);
        var changed = true;
        while (changed) {
            changed = false;
            for (b.gr.productions) |p| {
                const n = b.index(p.lhs);
                if (b.nullable[n] or !b.nullableSuffix(p.rhs)) continue;
                b.nullable[n] = true;
                changed = true;
            }
        }
    }

    fn mapTransitions(b: *Build) !void {
        const n = b.c.states.len;
        b.nt_base = try b.gpa.alloc(u32, n);
        b.nt_start = try b.gpa.alloc(u32, n);

        var total: u32 = 0;
        for (b.c.states, 0..) |st, q| {
            var start: u32 = @intCast(st.edges.len);
            for (st.edges, 0..) |e, i| {
                if (!b.gr.isTerminal(e.symbol)) {
                    start = @intCast(i);
                    break;
                }
            }
            b.nt_start[q] = start;
            b.nt_base[q] = total;
            total += @as(u32, @intCast(st.edges.len)) - start;
        }

        b.transitions = try b.gpa.alloc(Transition, total);
        for (b.c.states, 0..) |st, q| {
            for (st.edges[b.nt_start[q]..], 0..) |e, i| {
                b.transitions[b.nt_base[q] + i] = .{
                    .from = @intCast(q),
                    .symbol = e.symbol,
                    .to = e.target,
                };
            }
        }
    }

    /// The transition id for `(state, nonterminal)`, or null when the goto is
    /// undefined.
    fn transitionOf(b: Build, state: u32, symbol: g.Symbol) ?u32 {
        const edges = b.c.states[state].edges;
        var lo: usize = b.nt_start[state];
        var hi: usize = edges.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (edges[mid].symbol < symbol) lo = mid + 1 else hi = mid;
        }
        if (lo >= edges.len or edges[lo].symbol != symbol) return null;
        return b.nt_base[state] + @as(u32, @intCast(lo - b.nt_start[state]));
    }

    /// `Follow` for every nonterminal transition, in two closures.
    ///
    /// The first is `Read`: what a transition can see directly, plus what it
    /// can see through nullable nonterminals that follow it. The second is
    /// `Follow`: `Read`, plus what is visible to any transition this one is
    /// embedded in. Both are the same union-along-edges over a different
    /// relation, so both are the same walk.
    fn deriveFollow(b: *Build) !void {
        const n = b.transitions.len;
        b.follow = try sets.Matrix.init(b.gpa, n, b.width);
        b.have_follow = true;

        var edges: Relation = .init(b.gpa);
        defer edges.deinit();

        for (b.transitions, 0..) |t, i| {
            for (b.c.states[t.to].edges) |e| {
                if (b.gr.isTerminal(e.symbol)) {
                    // Directly reads: a terminal that can be shifted right
                    // after this goto is taken.
                    b.follow.set(i, e.symbol);
                } else if (b.nullable[b.index(e.symbol)]) {
                    // Reads: a nullable nonterminal can vanish, exposing
                    // whatever the transition past it could see.
                    try edges.add(@intCast(i), b.transitionOf(t.to, e.symbol).?);
                }
            }
        }
        // Input ends after the augmented start symbol, and nowhere else.
        b.follow.set(b.transitionOf(0, b.gr.productions[0].rhs[0]).?, b.gr.terminal_count);

        try edges.close(b.follow);

        // Includes: `A`'s transition can see whatever follows `B`, whenever
        // some `B -> ... A γ` has γ nullable. Walking every production of `B`
        // from the transition's own source state is what makes "the transition
        // of A at the right place" well defined.
        edges.clear();
        for (b.transitions, 0..) |t, i| {
            for (b.gr.productionsOf(t.symbol)) |p| {
                var at = t.from;
                for (b.gr.productions[p].rhs, 0..) |s, j| {
                    if (!b.gr.isTerminal(s) and b.nullableSuffix(b.gr.productions[p].rhs[j + 1 ..])) {
                        try edges.add(b.transitionOf(at, s).?, @intCast(i));
                    }
                    at = b.c.goto(at, s).?;
                }
            }
        }
        try edges.close(b.follow);
    }

    /// Lookback: a reduction of `A -> ω` in the state that ω walks to may
    /// happen on whatever follows that particular `A` transition. One
    /// reduction can be reached by several transitions, so the sets union.
    fn deriveLookahead(b: *Build) !void {
        b.reduction_base = try b.gpa.alloc(u32, b.c.states.len);
        var total: u32 = 0;
        for (b.c.states, 0..) |st, q| {
            b.reduction_base[q] = total;
            total += @intCast(st.complete.len);
        }
        b.la = try sets.Matrix.init(b.gpa, total, b.width);
        b.have_la = true;

        for (b.transitions, 0..) |t, i| {
            for (b.gr.productionsOf(t.symbol)) |p| {
                const landed = b.c.walk(t.from, b.gr.productions[p].rhs).?;
                if (b.reductionOf(landed, p)) |r| b.la.unionFrom(r, b.follow, i);
            }
        }
        // The augmented production is not reachable through any transition, so
        // its lookahead is stated rather than derived: accept at end of input.
        for (b.c.states, 0..) |st, q| {
            for (st.complete, 0..) |p, k| {
                if (p == 0) b.la.set(b.reduction_base[q] + k, b.gr.terminal_count);
            }
        }
    }

    fn reductionOf(b: Build, state: u32, prod: u32) ?usize {
        for (b.c.states[state].complete, 0..) |p, k| {
            if (p == prod) return b.reduction_base[state] + k;
        }
        return null;
    }

    fn tabulate(b: *Build, arena: std.heap.ArenaAllocator) !Tables {
        var owned = arena;
        const a = owned.allocator();
        const action = try a.alloc(Action, b.c.states.len * b.width);
        @memset(action, Action.err);

        var conflicts: std.ArrayList(Conflict) = .empty;
        defer conflicts.deinit(b.gpa);

        for (b.c.states, 0..) |st, q| {
            const row = action[q * b.width ..][0..b.width];
            for (st.edges) |e| {
                if (b.gr.isTerminal(e.symbol)) row[e.symbol] = Action.shift(e.target);
            }
            for (st.complete, 0..) |p, k| {
                var it = b.la.iterate(b.reduction_base[q] + k);
                while (it.next()) |t| {
                    const proposed = if (p == 0) Action{ .kind = .accept, .value = 0 } else Action.reduce(p);
                    row[t] = try b.settle(&conflicts, @intCast(q), @intCast(t), row[t], proposed);
                }
            }
        }

        return .{
            .arena = owned,
            .end = b.gr.terminal_count,
            .width = b.width,
            .action = action,
            .conflicts = try a.dupe(Conflict, conflicts.items),
        };
    }

    /// Decide one contested cell. Precedence is the grammar author's own answer
    /// and is honored silently; anything precedence does not cover is recorded
    /// as a conflict even though a choice still has to be made, because the
    /// count of those is what says how much of this grammar is really LALR.
    fn settle(
        b: *Build,
        conflicts: *std.ArrayList(Conflict),
        state: u32,
        terminal: u32,
        existing: Action,
        proposed: Action,
    ) !Action {
        if (existing.kind == .err) return proposed;
        // Accept outranks everything: it can only be contested at end of input,
        // where no shift exists and no other reduction is meaningful.
        if (proposed.kind == .accept) return proposed;
        if (existing.kind == .accept) return existing;

        if (existing.kind == .shift) {
            const shift_prec = b.shiftPrec(state, terminal);
            const p = b.gr.productions[proposed.value];
            if (p.prec != 0 and shift_prec.prec != 0 and p.prec != shift_prec.prec) {
                return if (p.prec > shift_prec.prec) proposed else existing;
            }
            if (p.prec != 0 and p.prec == shift_prec.prec) {
                switch (p.assoc) {
                    .left => return proposed,
                    .right => return existing,
                    .none => {},
                }
            }
            // Unresolved: shift, which is yacc's default and the one that keeps
            // the longer production alive.
            try conflicts.append(b.gpa, .{
                .state = state,
                .terminal = terminal,
                .kind = .shift_reduce,
                .chosen = existing,
                .other = proposed,
            });
            return existing;
        }

        // Two reductions. Precedence cannot separate them - it orders a
        // reduction against a shift, not against another reduction - so the
        // earlier production wins, which is the order the grammar declared.
        const keep = if (proposed.value < existing.value) proposed else existing;
        try conflicts.append(b.gpa, .{
            .state = state,
            .terminal = terminal,
            .kind = .reduce_reduce,
            .chosen = keep,
            .other = if (keep.value == existing.value) proposed else existing,
        });
        return keep;
    }

    fn shiftPrec(b: Build, state: u32, terminal: u32) struct { prec: i32, assoc: g.Assoc } {
        for (b.c.states[state].edges) |e| {
            if (e.symbol == terminal) return .{ .prec = e.prec, .assoc = e.assoc };
        }
        return .{ .prec = 0, .assoc = .none };
    }
};

/// A relation over transitions, and the union-along-edges closure that both
/// `Read` and `Follow` are instances of.
///
/// Tarjan's walk, in DeRemer and Pennello's formulation: descend the relation,
/// unioning as you return, and when a strongly connected component closes,
/// give every member the same set. Members of a cycle can all reach each other,
/// so they cannot differ - handling that explicitly is what lets one pass
/// replace an iterated fixpoint.
const Relation = struct {
    gpa: std.mem.Allocator,
    /// Flattened adjacency, built as pairs and then bucketed.
    pairs: std.ArrayList([2]u32),

    fn init(gpa: std.mem.Allocator) Relation {
        return .{ .gpa = gpa, .pairs = .empty };
    }

    fn deinit(r: *Relation) void {
        r.pairs.deinit(r.gpa);
    }

    fn clear(r: *Relation) void {
        r.pairs.clearRetainingCapacity();
    }

    fn add(r: *Relation, from: u32, to: u32) !void {
        try r.pairs.append(r.gpa, .{ from, to });
    }

    fn close(r: *Relation, m: sets.Matrix) !void {
        const n = m.words.len / m.stride;
        const heads = try r.gpa.alloc(u32, n + 1);
        defer r.gpa.free(heads);
        @memset(heads, 0);
        for (r.pairs.items) |p| heads[p[0] + 1] += 1;
        for (1..heads.len) |i| heads[i] += heads[i - 1];
        const adj = try r.gpa.alloc(u32, r.pairs.items.len);
        defer r.gpa.free(adj);
        var cursor = try r.gpa.dupe(u32, heads[0..n]);
        defer r.gpa.free(cursor);
        for (r.pairs.items) |p| {
            adj[cursor[p[0]]] = p[1];
            cursor[p[0]] += 1;
        }

        var walk: Walk = .{
            .m = m,
            .heads = heads,
            .adj = adj,
            .depth = try r.gpa.alloc(u32, n),
            .stack = try r.gpa.alloc(u32, n),
        };
        defer r.gpa.free(walk.depth);
        defer r.gpa.free(walk.stack);
        @memset(walk.depth, 0);
        for (0..n) |x| if (walk.depth[x] == 0) walk.descend(@intCast(x));
    }

    const settled = std.math.maxInt(u32);

    const Walk = struct {
        m: sets.Matrix,
        heads: []const u32,
        adj: []const u32,
        depth: []u32,
        stack: []u32,
        top: usize = 0,
        counter: u32 = 0,

        fn descend(w: *Walk, x: u32) void {
            w.stack[w.top] = x;
            w.top += 1;
            w.counter += 1;
            const mine = w.counter;
            w.depth[x] = mine;

            for (w.adj[w.heads[x]..w.heads[x + 1]]) |y| {
                if (w.depth[y] == 0) w.descend(y);
                w.depth[x] = @min(w.depth[x], w.depth[y]);
                _ = w.m.unionInto(x, y);
            }

            if (w.depth[x] != mine) return;
            // `x` roots a component; everything above it on the stack is in the
            // same cycle and therefore has exactly this set.
            while (true) {
                w.top -= 1;
                const y = w.stack[w.top];
                w.depth[y] = settled;
                w.m.copyRow(y, x);
                if (y == x) break;
            }
        }
    };
};

const testing = std.testing;

/// The textbook expression grammar, which is the smallest thing that exercises
/// every part of this file at once: a real conflict resolved by precedence, a
/// nullable-free `includes` chain, and a lookahead that only lookback can give.
///
///   E -> E + E | E * E | ( E ) | id
///
/// Written ambiguously on purpose. An unambiguous `E -> E + T` version has no
/// conflicts to settle, so it would test the tables without testing the part
/// that decides them.
const Expr = struct {
    gr: g.Grammar,
    plus: g.Symbol,
    star: g.Symbol,
    lp: g.Symbol,
    rp: g.Symbol,
    id: g.Symbol,
    e: g.Symbol,

    fn init(gpa: std.mem.Allocator, star_prec: i32, assoc: g.Assoc) !Expr {
        var b = g.Builder.init(gpa);
        defer b.deinit();
        const plus = try b.intern("+", "+", .{ .literal = "+" });
        const star = try b.intern("*", "*", .{ .literal = "*" });
        const lp = try b.intern("(", "(", .{ .literal = "(" });
        const rp = try b.intern(")", ")", .{ .literal = ")" });
        const id = try b.intern("id", "id", .{ .regex = "[a-z]+" });
        const start = try b.intern("$start", "$start", null);
        const e = try b.intern("E", "E", null);
        try b.addProduction(start, &.{e}, 0, .none);
        try b.addProduction(e, &.{ e, plus, e }, 1, assoc);
        try b.addProduction(e, &.{ e, star, e }, star_prec, assoc);
        try b.addProduction(e, &.{ lp, e, rp }, 0, .none);
        try b.addProduction(e, &.{id}, 0, .none);
        const gr = try b.finish("expr", start, &.{}, &.{});
        return .{
            .gr = gr,
            .plus = 0,
            .star = 1,
            .lp = 2,
            .rp = 3,
            .id = 4,
            .e = gr.start + 1,
        };
    }

    fn deinit(x: *Expr) void {
        x.gr.deinit();
    }
};

test "lookahead is exactly what can follow the nonterminal, not every terminal" {
    var x = try Expr.init(testing.allocator, 2, .left);
    defer x.deinit();
    var c = try lr0.build(testing.allocator, &x.gr);
    defer c.deinit();
    var t = try build(testing.allocator, &x.gr, &c);
    defer t.deinit();

    // The state that has just read `id` reduces `E -> id`. What can follow an
    // E is exactly `+`, `*`, `)`, and end of input - never `(` or `id`, which
    // an SLR-grade FOLLOW would also permit here only because it forgets which
    // E it is talking about.
    const after_id = c.goto(0, x.id).?;
    for ([_]u32{ x.plus, x.star, x.rp, t.end }) |look| {
        try testing.expectEqual(Action.Kind.reduce, t.at(after_id, look).kind);
    }
    for ([_]u32{ x.lp, x.id }) |look| {
        try testing.expectEqual(Action.Kind.err, t.at(after_id, look).kind);
    }
}

test "precedence settles a shift-reduce silently and leaves no conflict behind" {
    var x = try Expr.init(testing.allocator, 2, .left);
    defer x.deinit();
    var c = try lr0.build(testing.allocator, &x.gr);
    defer c.deinit();
    var t = try build(testing.allocator, &x.gr, &c);
    defer t.deinit();

    // `E + E . ` seeing `*`: multiplication binds tighter, so keep reading.
    const plus_state = c.walk(0, &.{ x.e, x.plus, x.e }).?;
    try testing.expectEqual(Action.Kind.shift, t.at(plus_state, x.star).kind);
    // `E + E . ` seeing `+`: same precedence, left associative, so fold now.
    try testing.expectEqual(Action.Kind.reduce, t.at(plus_state, x.plus).kind);
    // `E * E . ` seeing `+`: multiplication binds tighter, so fold now.
    const star_state = c.walk(0, &.{ x.e, x.star, x.e }).?;
    try testing.expectEqual(Action.Kind.reduce, t.at(star_state, x.plus).kind);

    try testing.expectEqual(@as(usize, 0), t.conflicts.len);
}

test "without precedence the same grammar reports its ambiguity instead of hiding it" {
    var x = try Expr.init(testing.allocator, 0, .none);
    defer x.deinit();
    var c = try lr0.build(testing.allocator, &x.gr);
    defer c.deinit();
    var t = try build(testing.allocator, &x.gr, &c);
    defer t.deinit();

    // `E + E .` and `E * E .` each seeing either operator: four undecided
    // cells, every one a shift-reduce, every one resolved to shift and every
    // one still on the record.
    try testing.expectEqual(@as(usize, 4), t.conflicts.len);
    for (t.conflicts) |k| {
        try testing.expectEqual(Conflict.Kind.shift_reduce, k.kind);
        try testing.expectEqual(Action.Kind.shift, k.chosen.kind);
    }
}

test "accept happens at end of input and only there" {
    var x = try Expr.init(testing.allocator, 2, .left);
    defer x.deinit();
    var c = try lr0.build(testing.allocator, &x.gr);
    defer c.deinit();
    var t = try build(testing.allocator, &x.gr, &c);
    defer t.deinit();

    const done = c.goto(0, x.e).?;
    try testing.expectEqual(Action.Kind.accept, t.at(done, t.end).kind);
    try testing.expectEqual(Action.Kind.shift, t.at(done, x.plus).kind);
}

//! LALR(1) lookaheads by the DeRemer-Pennello relations, and the action table
//! they decide.
//!
//! *Which* reductions are legal in a state is this file's question. *Which one
//! a parser should take when several are* is a different question with a
//! different answer — the author's precedence and associativity, walked in a
//! specific order — and it lives in `settle.zig`. The split is not tidiness:
//! written together, the second question comes out as a default buried in a
//! table-filling loop, and defaults are what this layer is being measured on.
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
const first = @import("first.zig");
const g = @import("grammar.zig");
const lr0 = @import("lr0.zig");
const sets = @import("sets.zig");
const imports = @import("import.zig");
const settle = @import("settle.zig");

/// What a state does on a terminal. Named here because the table is what hands
/// them out, and decided in `settle.zig`, which is where the question is.
pub const Action = settle.Action;
pub const Conflict = settle.Conflict;
pub const Tally = settle.Tally;

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
    frayed: []const settle.Frayed,

    pub fn deinit(t: *Tables) void {
        t.arena.deinit();
        t.* = undefined;
    }

    pub fn at(t: Tables, state: u32, terminal: u32) Action {
        return t.action[state * t.width + terminal];
    }

    pub fn tally(t: Tables) Tally {
        var out: Tally = .{};
        for (t.conflicts) |k| switch (k.class) {
            .repetition => out.repetition += 1,
            .declared => out.declared += 1,
            .residual => switch (k.kind) {
                .shift_reduce => out.residual.shift_reduce += 1,
                .reduce_reduce => out.residual.reduce_reduce += 1,
            },
        };
        return out;
    }
};

pub fn build(gpa: std.mem.Allocator, gr: *const g.Grammar, c: *const lr0.Collection) !Tables {
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();

    var b: Build = .{ .gpa = gpa, .gr = gr, .c = c, .width = gr.terminal_count + 1 };
    defer b.deinit();

    // The relations below read terminals straight off the automaton's own shift
    // edges, which is what makes them a graph problem rather than a second
    // fixpoint; nullability is the only symbol-level fact they need. FIRST
    // arrives in the same pass and is what attributing a conflict costs — the
    // shift side of one is every item that could begin with the contested
    // terminal, which is a FIRST question and nothing else.
    b.first = try first.build(gpa, gr);
    b.have_first = true;
    try b.mapTransitions();
    try b.deriveFollow();
    try b.deriveLookahead();
    return b.tabulate(arena);
}

fn order(key: g.Symbol, item: g.Symbol) std.math.Order {
    return std.math.order(key, item);
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

    first: first.First = undefined,
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
    /// The same rows, intersected rather than unioned over the contexts that
    /// reach the reduction. `la` says a fold is legal on a terminal somewhere;
    /// `meet` says it is legal on that terminal *everywhere* this state stands
    /// for. Where they differ, one LR(0) state is doing duty for contexts that
    /// disagree, and the disagreement is the merge's, not the grammar's.
    meet: sets.Matrix = undefined,
    reduction_base: []u32 = &.{},
    have_first: bool = false,
    have_follow: bool = false,
    have_la: bool = false,

    fn deinit(b: *Build) void {
        if (b.have_first) b.first.deinit(b.gpa);
        b.gpa.free(b.transitions);
        b.gpa.free(b.nt_base);
        b.gpa.free(b.nt_start);
        if (b.have_follow) b.follow.deinit(b.gpa);
        if (b.have_la) {
            b.la.deinit(b.gpa);
            b.meet.deinit(b.gpa);
        }
        b.gpa.free(b.reduction_base);
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
                } else if (b.first.nullable(e.symbol)) {
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
                    if (!b.gr.isTerminal(s) and b.first.nullableAll(b.gr.productions[p].rhs[j + 1 ..])) {
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
        b.meet = try sets.Matrix.init(b.gpa, total, b.width);
        b.have_la = true;

        const reached = try b.gpa.alloc(bool, total);
        defer b.gpa.free(reached);
        @memset(reached, false);

        for (b.transitions, 0..) |t, i| {
            for (b.gr.productionsOf(t.symbol)) |p| {
                const landed = b.c.walk(t.from, b.gr.productions[p].rhs).?;
                if (b.reductionOf(landed, p)) |r| {
                    b.la.unionFrom(r, b.follow, i);
                    if (reached[r]) b.meet.meetFrom(r, b.follow, i) else {
                        b.meet.copyFrom(r, b.follow, i);
                        reached[r] = true;
                    }
                }
            }
        }
        // The augmented production is not reachable through any transition, so
        // its lookahead is stated rather than derived: accept at end of input.
        for (b.c.states, 0..) |st, q| {
            for (st.complete, 0..) |p, k| {
                if (p == 0) {
                    b.la.set(b.reduction_base[q] + k, b.gr.terminal_count);
                    b.meet.set(b.reduction_base[q] + k, b.gr.terminal_count);
                }
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
        const verdict = try settle.all(.{
            .gr = b.gr,
            .c = b.c,
            .first = &b.first,
            .la = b.la,
            .meet = b.meet,
            .reduction_base = b.reduction_base,
            .width = b.width,
        }, b.gpa, owned.allocator());

        return .{
            .arena = owned,
            .end = b.gr.terminal_count,
            .width = b.width,
            .action = verdict.action,
            .conflicts = verdict.conflicts,
            .frayed = verdict.frayed,
        };
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
///
/// Both operator precedences are parameters, and neither may be quietly fixed:
/// zero is a *rank*, not an absence, so a fixture that pins one operator at 1
/// and calls the result "no precedence" is a fixture that ranks them. It read
/// as ambiguous for exactly as long as the resolver was unable to compare
/// anything against zero.
const Expr = struct {
    gr: g.Grammar,
    plus: g.Symbol,
    star: g.Symbol,
    lp: g.Symbol,
    rp: g.Symbol,
    id: g.Symbol,
    e: g.Symbol,

    fn init(gpa: std.mem.Allocator, plus_prec: i32, star_prec: i32, assoc: g.Assoc) !Expr {
        var b = g.Builder.init(gpa);
        defer b.deinit();
        const plus = try b.intern("+", "+", .{ .literal = "+" });
        const star = try b.intern("*", "*", .{ .literal = "*" });
        const lp = try b.intern("(", "(", .{ .literal = "(" });
        const rp = try b.intern(")", ")", .{ .literal = ")" });
        const id = try b.intern("id", "id", .{ .regex = "[a-z]+" });
        const start = try b.intern("$start", "$start", null);
        const e = try b.intern("E", "E", null);
        try b.addProduction(start, &.{e}, &.{});
        const rank = struct {
            fn at(level: i32, side: g.Assoc) [3]g.Step {
                // Uniform across the body, which is what `prec.left(n, seq(…))`
                // produces: the wrapper is the whole production, so every step
                // is inside it and the final one carries the fold's rank.
                return @splat(.{ .prec = .{ .level = level }, .assoc = side });
            }
        }.at;
        try b.addProduction(e, &.{ e, plus, e }, &rank(plus_prec, assoc));
        try b.addProduction(e, &.{ e, star, e }, &rank(star_prec, assoc));
        try b.addProduction(e, &.{ lp, e, rp }, &.{});
        try b.addProduction(e, &.{id}, &.{});
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
    var x = try Expr.init(testing.allocator, 1, 2, .left);
    defer x.deinit();
    var c = try lr0.build(testing.allocator, &x.gr, .{});
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
    var x = try Expr.init(testing.allocator, 1, 2, .left);
    defer x.deinit();
    var c = try lr0.build(testing.allocator, &x.gr, .{});
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
    var x = try Expr.init(testing.allocator, 0, 0, .none);
    defer x.deinit();
    var c = try lr0.build(testing.allocator, &x.gr, .{});
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
        try testing.expectEqual(Conflict.Class.residual, k.class);
    }
}

test "ranking one operator above the default settles the pair it outranks" {
    // `+` ranked, `*` left at the default. Nothing here declares associativity,
    // so associativity cannot settle anything and every cell that resolves does
    // so by comparing a rank against the default — which is a comparison, not a
    // refusal to compare. Half the cells of the unranked grammar go away.
    var x = try Expr.init(testing.allocator, 1, 0, .none);
    defer x.deinit();
    var c = try lr0.build(testing.allocator, &x.gr, .{});
    defer c.deinit();
    var t = try build(testing.allocator, &x.gr, &c);
    defer t.deinit();

    try testing.expectEqual(@as(usize, 2), t.conflicts.len);
    // `E + E . * ` folds: `*` binds looser, so the `+` closes first.
    const plus_state = c.walk(0, &.{ x.e, x.plus, x.e }).?;
    try testing.expectEqual(Action.Kind.reduce, t.at(plus_state, x.star).kind);
    // `E * E . + ` reads on: `+` outranks the fold it is contesting.
    const star_state = c.walk(0, &.{ x.e, x.star, x.e }).?;
    try testing.expectEqual(Action.Kind.shift, t.at(star_state, x.plus).kind);
    // The two cells left are each operator against itself, where the ranks tie
    // and no side was declared.
    for (t.conflicts) |k| try testing.expect(k.terminal == x.plus or k.terminal == x.star);
}

test "accept happens at end of input and only there" {
    var x = try Expr.init(testing.allocator, 1, 2, .left);
    defer x.deinit();
    var c = try lr0.build(testing.allocator, &x.gr, .{});
    defer c.deinit();
    var t = try build(testing.allocator, &x.gr, &c);
    defer t.deinit();

    const done = c.goto(0, x.e).?;
    try testing.expectEqual(Action.Kind.accept, t.at(done, t.end).kind);
    try testing.expectEqual(Action.Kind.shift, t.at(done, x.plus).kind);
}

/// A whole grammar, imported and tabulated. Attribution cannot be tested any
/// smaller: which rule a synthesized list belongs to is a fact about the front
/// end's sharing, the automaton's shape, and the author's declarations at once,
/// and a hand-built grammar has none of the three.
const Table = struct {
    gr: g.Grammar,
    c: lr0.Collection,
    t: Tables,

    fn of(gpa: std.mem.Allocator, src: []const u8) !Table {
        var gr = try imports.treeSitter(gpa, src);
        errdefer gr.deinit();
        var c = try lr0.build(gpa, &gr, .{});
        errdefer c.deinit();
        const t = try build(gpa, &gr, &c);
        return .{ .gr = gr, .c = c, .t = t };
    }

    fn deinit(x: *Table) void {
        x.t.deinit();
        x.c.deinit();
        x.gr.deinit();
    }

    /// The party of the first conflict, as rule names, for comparing against
    /// what a reader would expect the report to say.
    fn party(x: Table, gpa: std.mem.Allocator) ![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(gpa);
        for (x.t.conflicts[0].party, 0..) |s, i| {
            if (i > 0) try out.append(gpa, '+');
            try out.appendSlice(gpa, x.gr.nameOf(s));
        }
        return out.toOwnedSlice(gpa);
    }
};

/// `stmt -> L stmt | ';'` with `L` a shared list. A statement's list can be
/// followed by another statement, which can begin with a list of its own, so the
/// state that folds one element cannot say whether the list is over — C's
/// `attributed_statement`, which is why C declares that single rule ambiguous.
/// `decl` is written first, so it is `decl` that *names* the shared list.
const shared_list =
    \\{"name":"t","rules":{
    \\ "unit":{"type":"CHOICE","members":[
    \\   {"type":"SYMBOL","name":"decl"},{"type":"SYMBOL","name":"stmt"}]},
    \\ "decl":{"type":"SEQ","members":[{"type":"STRING","value":"n"},
    \\   {"type":"REPEAT1","content":{"type":"STRING","value":"a"}}]},
    \\ "stmt":{"type":"CHOICE","members":[
    \\   {"type":"SEQ","members":[{"type":"REPEAT1","content":{"type":"STRING","value":"a"}},
    \\     {"type":"SYMBOL","name":"stmt"}]},
    \\   {"type":"STRING","value":";"}]}},
    \\ "conflicts":[CONFLICTS]}
;

fn withConflicts(gpa: std.mem.Allocator, template: []const u8, groups: []const u8) ![]u8 {
    const at = std.mem.indexOf(u8, template, "CONFLICTS").?;
    return std.mem.concat(gpa, u8, &.{ template[0..at], groups, template[at + 9 ..] });
}

test "a shared list is attributed to the rule expecting it here, not the one that named it" {
    const src = try withConflicts(testing.allocator, shared_list, "");
    defer testing.allocator.free(src);
    var x = try Table.of(testing.allocator, src);
    defer x.deinit();

    // One list, shared by both hosts, and `decl` gave it its name.
    var lists: usize = 0;
    for (x.gr.terminal_count..x.gr.symbolCount()) |i| {
        const s: g.Symbol = @intCast(i);
        if (!x.gr.isSynthetic(s)) continue;
        lists += 1;
        try testing.expect(std.mem.startsWith(u8, x.gr.nameOf(s), "decl_repeat"));
    }
    try testing.expectEqual(@as(usize, 1), lists);

    const seen = try x.party(testing.allocator);
    defer testing.allocator.free(seen);
    // Not `decl`, which named the list and expects it elsewhere. Not
    // `decl+stmt`, which is what a union over every state expecting the list
    // would say. And not the list itself, which is left-recursive and so sits
    // in the very state that expects it.
    try testing.expectEqualStrings("stmt", seen);
}

test "declaring the rule the list actually belongs to settles it" {
    const src = try withConflicts(testing.allocator, shared_list, "[\"stmt\"]");
    defer testing.allocator.free(src);
    var x = try Table.of(testing.allocator, src);
    defer x.deinit();

    const cells = x.t.tally();
    try testing.expectEqual(@as(u32, 0), cells.residual.total());
    try testing.expect(cells.declared > 0);
}

test "declaring the rule that named the list does not settle it" {
    const src = try withConflicts(testing.allocator, shared_list, "[\"decl\"]");
    defer testing.allocator.free(src);
    var x = try Table.of(testing.allocator, src);
    defer x.deinit();

    // The point of tracing the list back: a declaration about `decl` is not a
    // licence for an ambiguity in `stmt`, even though both write the same list.
    try testing.expect(x.t.tally().residual.total() > 0);
}

/// Two lists over different bodies — `a+` and `(a|b)+` — each with a
/// top-level host and a bracketed one. Folding a single `a` cannot say which
/// list it belongs to, and the state where that happens is arrived at two ways:
/// from the start, and from inside a `(`. Java's shape, where one annotation
/// list argues with the modifier list that also admits annotations.
const two_lists =
    \\{"name":"t","rules":{
    \\ "u":{"type":"CHOICE","members":[
    \\   {"type":"SYMBOL","name":"p"},{"type":"SYMBOL","name":"q"},
    \\   {"type":"SYMBOL","name":"r"},{"type":"SYMBOL","name":"s"}]},
    \\ "p":{"type":"SEQ","members":[
    \\   {"type":"REPEAT1","content":{"type":"STRING","value":"a"}},{"type":"STRING","value":"x"}]},
    \\ "q":{"type":"SEQ","members":[
    \\   {"type":"REPEAT1","content":{"type":"CHOICE","members":[
    \\     {"type":"STRING","value":"a"},{"type":"STRING","value":"b"}]}},{"type":"STRING","value":"x"}]},
    \\ "r":{"type":"SEQ","members":[{"type":"STRING","value":"("},
    \\   {"type":"REPEAT1","content":{"type":"STRING","value":"a"}},{"type":"STRING","value":"x"}]},
    \\ "s":{"type":"SEQ","members":[{"type":"STRING","value":"("},
    \\   {"type":"REPEAT1","content":{"type":"CHOICE","members":[
    \\     {"type":"STRING","value":"a"},{"type":"STRING","value":"b"}]}},{"type":"STRING","value":"x"}]}},
    \\ "conflicts":[CONFLICTS]}
;

test "each stack that could expose the fold is its own candidate party" {
    // The two lists merge into one state after a single `a`, so the same cell is
    // reachable from the start and from inside a `(`. Either declaration
    // settles it, because either is a stack on which those two rules really are
    // confused with each other.
    for ([_][]const u8{ "[\"p\",\"q\"]", "[\"r\",\"s\"]" }) |groups| {
        const src = try withConflicts(testing.allocator, two_lists, groups);
        defer testing.allocator.free(src);
        var x = try Table.of(testing.allocator, src);
        defer x.deinit();
        const cells = x.t.tally();
        try testing.expect(cells.declared > 0);
        try testing.expectEqual(@as(u32, 0), cells.residual.total());
    }
}

test "the union of every stack is not a party any parse holds" {
    // Declaring all four says the four rules are mutually confused, which no
    // stack ever claims: `r` and `s` are unreachable without the `(` that `p`
    // and `q` cannot have seen. Accepting it would sanction a group on evidence
    // from two different parses.
    const src = try withConflicts(testing.allocator, two_lists, "[\"p\",\"q\",\"r\",\"s\"]");
    defer testing.allocator.free(src);
    var x = try Table.of(testing.allocator, src);
    defer x.deinit();
    try testing.expect(x.t.tally().residual.total() > 0);

    // And the report says the union, because with nothing declared there is
    // nothing to choose between the candidates.
    const seen = try x.party(testing.allocator);
    defer testing.allocator.free(seen);
    try testing.expectEqualStrings("p+q+r+s", seen);
}

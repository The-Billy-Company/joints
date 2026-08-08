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
const first = @import("cast/first.zig");
const g = @import("copy/grammar.zig");
const lr0 = @import("cast/lr0.zig");
const sets = @import("cast/sets.zig");
const imports = @import("copy/import.zig");
const settle = @import("quarrel/settle.zig");

/// What a state does on a terminal. Named here because the table is what hands
/// them out, and decided in `settle.zig`, which is where the question is.
pub const Action = settle.Action;
pub const Conflict = settle.Conflict;
pub const Tally = settle.Tally;

/// What a state does on a terminal, in the one distinction every instrument
/// here has to make and three of them had stopped making.
///
/// **A shift consumes a byte and a fold does not.** So "the terminals of this
/// state" has two answers, and they are not close: swift's `_implicit_semi` is
/// a shift in 20 states and a lookahead in 1,712, an 85x spread. When the
/// question is lexical - what must a scanner compete with here - the shifts are
/// the whole answer, because a reduce puts no token in anyone's hand. When it
/// is a table question - what may follow this state at all - the union is, and
/// that union is what `drive.offer` hands an external scanner as its permission
/// set.
///
/// This lives here, beside the action it classifies, because a census of a
/// mechanism and the mechanism itself are two implementations of one fact and
/// this repo has been bitten by them disagreeing twice: `state --census`
/// reduced a cohort to co-admission by shift alone and printed a wall of zeros
/// under a header that read like a clearance, and `lex`'s blind count called
/// swift blind to a terminal the parser was emitting. **One function, one
/// answer** - so `state --census`, `inquest`'s stand-in and `survey`'s legal
/// set all split on this and none of them re-derives it.
///
/// Total over the accepted cells and disjoint, which is what lets a footer add
/// the two counts and call the sum the accepted set. `accept` is filed with the
/// shifts because it ends the parse by taking a token rather than by folding
/// one, and because a reader asking "what can a scanner be asked for here"
/// wants it on that side.
pub const Half = enum {
    shift,
    fold,

    pub fn of(verb: @FieldType(Action, "kind")) ?Half {
        return switch (verb) {
            .shift, .accept => .shift,
            .reduce => .fold,
            .err => null,
        };
    }

    /// What the half means for whoever is reading, in the terms the reading is
    /// about: a shift is a token this state was waiting for, a fold is one it
    /// merely tolerates on the way to somewhere else.
    pub fn word(h: Half) []const u8 {
        return switch (h) {
            .shift => "shift",
            .fold => "lookahead",
        };
    }
};

/// A state that admits a token no context of it can hold, and how to take itself
/// apart so it stops.
///
/// The lookahead of a reduction is the union over the contexts that reach it, so
/// a terminal in the union but not in the intersection is legal after some
/// arrivals and impossible after the others. Most of the time that costs
/// nothing: the parser is only ever *in* one of those contexts, and a fold it
/// would never be asked to make is a cell nobody reads. What makes it fatal here
/// is that the row is also the lexer's instructions. `gather` scans exactly the
/// terminals the state does not refuse, so an invented permission is an invented
/// *token*, and a token that should not have been in the running can win the
/// tie. Ruby dies at byte 5 of `@rows = 1` that way: the fold of
/// `_nonlocal_variable -> instance_variable` carries the `%w()` element
/// separator, which is in the running only inside a word list, and it takes the
/// one byte the space needed.
///
/// So the population is not every over-permitted cell — those are legion and
/// nearly all harmless — but the ones that are *only* answered by the invention:
/// no read on that terminal, and no fold whose permission survives the
/// intersection. Those are the cells where merging changed what the state
/// admits, which is the only way it can change what gets lexed.
///
/// `settle.Frayed` is the neighbouring population: cells where the invention was
/// *contested*, and a read got deleted or two folds disagreed. The two overlap
/// and neither contains the other. A contested cell had something to argue with,
/// so it is at least reported; these are answered without ever being examined,
/// which is why driving the splitter on contests alone found a tenth of them.
pub const Seam = struct {
    state: u32,
    /// Terminals this state admits only because a merge invented the permission.
    over: []const u32,
    /// The arrivals, grouped: one copy of the state per lane. Two arrivals
    /// share a lane exactly when every fold here draws the same lookahead
    /// through them, which makes the split *sufficient* — each copy's folds end
    /// up with a lookahead that has no union left in it — and *coarsest*, which
    /// is what keeps a state reached forty ways from becoming forty states.
    ///
    /// Empty when no arrival stands under the disagreement: the folds all
    /// consume nothing, or every arrival draws the same lookahead and the
    /// contexts had already converged before this state. Splitting here cannot
    /// help, and the caller has to look further back.
    lanes: []const Lane = &.{},
    /// Over-permitted terminals that no grouping of *these* arrivals can remove,
    /// because one arrival already draws the terminal through one path to a fold
    /// and not through another. A copy holding that arrival holds the same union
    /// and the same meet, so the invention survives every cut this state admits.
    /// The disagreement is older than the arrival, and reaching it means walking
    /// back - which was measured at 24,572 states on bash for nothing.
    stubborn: []const u32 = &.{},
    /// Distinct states standing under this one's folds. One means there is
    /// nothing to separate: the merge widened the lookahead through a single
    /// context, so no partition of arrivals exists at all.
    arrivals: u32 = 0,

    pub const Lane = struct { from: u32, lane: u32 };
};

/// Where the refusals that are left actually stand: what no table construction
/// can reach, against what this search left on the table.
///
/// A refusing cell is a token the state will not admit because precedence gave
/// the cell to a fold. Whether that is a defect at all depends on why the fold
/// is there, and there are only four answers - which makes the count of refusals
/// far less interesting than its partition.
pub const Floor = struct {
    /// The fold is legal on this token under *every* context reaching the state.
    /// Nothing was invented, so nothing was merged wrongly: the grammar itself
    /// wants both readings here, and LR(1) would build the same cell. Anything
    /// left to win is the parse loop's, not the table's.
    agreed: u32 = 0,
    /// Invented, but through a single arrival. There is no partition of one.
    alone: u32 = 0,
    /// Invented through several arrivals that cannot be told apart here; see
    /// `Seam.stubborn`.
    stuck: u32 = 0,
    /// The arrivals draw lookaheads that can be told apart here, so a partition
    /// of them exists and the search did not take it - because the round it
    /// would have belonged to gained nothing overall, or because the plan was
    /// cut back to fit under the state ceiling.
    ///
    /// Read that as *the arrivals differ*, not as *a partition removes the
    /// cell*: the partition this bucket sees is finer than the one `Plan.cut`
    /// can express, since arrivals sharing a predecessor kernel share a lane
    /// there however differently they read. Zig's `{` is the worked example, and
    /// it says the difference costs a round to find. Its cell is `open`; the
    /// round that separated its kernel was built, 1834 states against 1720, and
    /// the cell survived with the same kernel hash under a new id. Three
    /// ceilings - 4, 16, 64 - give byte-identical automata, so the plan was not
    /// truncated either. `open` is the only bucket another round *can* reach;
    /// it is not a promise that one will.
    open: u32 = 0,

    pub fn total(f: Floor) u32 {
        return f.agreed + f.alone + f.stuck + f.open;
    }

    /// What no arrival partition can reach, at any cost.
    pub fn sealed(f: Floor) u32 {
        return f.agreed + f.alone + f.stuck;
    }

    /// Which bucket one cell is in. The field names are the buckets, so a
    /// caller asking about a single refusal gets the same four answers the
    /// tally does rather than a parallel vocabulary.
    pub const Cause = enum { agreed, alone, stuck, open };

    pub fn of(f: Floor, c: Cause) u32 {
        return switch (c) {
            .agreed => f.agreed,
            .alone => f.alone,
            .stuck => f.stuck,
            .open => f.open,
        };
    }
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
    frayed: []const settle.Frayed,
    /// Every cell a merged lookahead over-permits, contested or not. Empty by
    /// default because a table read back out of a folio has none to report: the
    /// artifact carries the decided cells, not the search that decided them.
    seams: []const Seam = &.{},

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
            .unwritten => out.unwritten += 1,
            .sided => out.sided += 1,
            .residual => switch (k.kind) {
                .shift_reduce => out.residual.shift_reduce += 1,
                .reduce_reduce => out.residual.reduce_reduce += 1,
            },
        };
        return out;
    }

    /// Sort every refusing cell into why it is still there. Needs the seams, so
    /// it answers zero on a table read back out of a folio.
    ///
    /// Linear in the refusals times the width of a seam's over-set, which is a
    /// few hundred against a few hundred; the state lookup is a binary search
    /// because seams are built in state order.
    pub fn floor(t: Tables) Floor {
        var out: Floor = .{};
        for (t.frayed) |f| {
            if (f.harm != .read_dropped) continue;
            switch (t.cause(f)) {
                .agreed => out.agreed += 1,
                .alone => out.alone += 1,
                .stuck => out.stuck += 1,
                .open => out.open += 1,
            }
        }
        return out;
    }

    /// Why one refusing cell is still there. `floor` is this tallied over every
    /// refusal; asking about a single cell - which is what attributing one wall
    /// needs - is the same question and must not be a second implementation of
    /// it. Answers about a `fold_dropped` cell too, where the reading it names
    /// is a fold rather than a read; the four buckets are about the seam, not
    /// about which side lost.
    pub fn cause(t: Tables, f: settle.Frayed) Floor.Cause {
        const seam = t.seamAt(f.state) orelse return .agreed;
        if (std.mem.indexOfScalar(u32, seam.over, f.terminal) == null) return .agreed;
        if (seam.arrivals <= 1) return .alone;
        if (std.mem.indexOfScalar(u32, seam.stubborn, f.terminal) != null) return .stuck;
        return .open;
    }

    /// The frayed cell at one address, if the merge damaged it.
    pub fn frayedAt(t: Tables, state: u32, terminal: u32) ?settle.Frayed {
        for (t.frayed) |f| if (f.state == state and f.terminal == terminal) return f;
        return null;
    }

    /// The conflict recorded at one address, if the cell was contested at all.
    pub fn conflictAt(t: Tables, state: u32, terminal: u32) ?Conflict {
        for (t.conflicts) |k| if (k.state == state and k.terminal == terminal) return k;
        return null;
    }

    pub fn seamAt(t: Tables, state: u32) ?*const Seam {
        var lo: usize = 0;
        var hi: usize = t.seams.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (t.seams[mid].state < state) lo = mid + 1 else hi = mid;
        }
        if (lo >= t.seams.len or t.seams[lo].state != state) return null;
        return &t.seams[lo];
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
        return b.reduction_base[state] + (b.slotOf(state, prod) orelse return null);
    }

    /// Every state whose admitted set the merge widened, with the arrivals
    /// grouped so the state can be taken apart.
    ///
    /// A terminal is over-permitted here when it is in a fold's lookahead union
    /// but not its meet, and is not a read the settlement kept. The neighbouring
    /// hypothesis - that a fold can also be granted a terminal *every* context
    /// draws and then walk into a state with no answer for it - is false by
    /// construction and was measured to be: `Follow` of a transition is derived
    /// from what the goto target reads, so the target admits every bit drawn
    /// through it. Over 2.6M arrivals across the eleven grammars, folds dead at
    /// their own goto: zero. Whatever is left after this comes apart further
    /// along the chain than one goto, where the stack decides and no set does.
    ///
    /// Two passes, because the second only wants the states the first found. A
    /// state's permissions are folded into two scratch rows — what any fold may
    /// do, and what every context agrees it may do — so finding the seams is a
    /// word loop per state rather than a bit test per cell.
    fn seams(b: *Build, arena: std.mem.Allocator, action: []const Action) ![]const Seam {
        var out: std.ArrayList(Seam) = .empty;
        errdefer out.deinit(b.gpa);
        const invented = try b.gpa.alloc(u64, b.la.stride);
        defer b.gpa.free(invented);
        const earned = try b.gpa.alloc(u64, b.la.stride);
        defer b.gpa.free(earned);
        var over: std.ArrayList(u32) = .empty;
        defer over.deinit(b.gpa);
        // Which seam a state holds, so the second pass can reject a landing in
        // one indexed load. `none` for the overwhelming majority.
        const holds = try b.gpa.alloc(u32, b.c.states.len);
        defer b.gpa.free(holds);
        @memset(holds, none);

        var draws: std.ArrayList(Draw) = .empty;
        defer draws.deinit(b.gpa);
        try b.trace(&draws);

        for (b.c.states, 0..) |st, q| {
            @memset(invented, 0);
            @memset(earned, 0);
            // A read the settlement kept is a permission the automaton itself
            // grants, so that terminal is admitted whatever the folds do. A read
            // it *dropped* is the opposite: precedence deleted it because the
            // fold outranked it, so the cell is answered by the invention alone
            // and the state has to come apart on it. Reading the LR(0) edge
            // instead of the settled cell hid exactly the class this whole
            // mechanism was built for - c's `p->q = 1`, where `=` is both
            // shiftable and in the fold's union, and where crediting the edge
            // took c from 5 refusing cells to 71.
            for (st.edges) |e| {
                if (e.symbol >= b.gr.terminal_count) break;
                if (action[q * b.width + e.symbol].kind != .shift) continue;
                earned[e.symbol / 64] |= @as(u64, 1) << @intCast(e.symbol % 64);
            }
            for (st.complete, 0..) |prod, k| {
                // The augmented production accepts rather than folds, and its
                // lookahead is stated rather than drawn through any context.
                if (prod == 0) continue;
                const r = b.reduction_base[q] + k;
                for (invented, earned, b.la.row(r), b.meet.row(r)) |*i, *e, all, every| {
                    i.* |= all;
                    e.* |= every;
                }
            }
            over.clearRetainingCapacity();
            for (invented, earned, 0..) |all, every, i| {
                var bits = all & ~every;
                while (bits != 0) : (bits &= bits - 1) {
                    try over.append(b.gpa, @intCast(i * 64 + @ctz(bits)));
                }
            }
            if (over.items.len == 0) continue;
            holds[q] = @intCast(out.items.len);
            try out.append(b.gpa, .{ .state = @intCast(q), .over = try arena.dupe(u32, over.items) });
        }

        if (out.items.len > 0) try b.regroup(arena, out.items, holds, draws.items);
        const owned = try arena.dupe(Seam, out.items);
        out.deinit(b.gpa);
        return owned;
    }

    /// One way a fold is reached: the state holding it, which of that state's
    /// folds it is, the state standing immediately under it, and the transition
    /// whose `Follow` it draws.
    const Draw = struct {
        landed: u32,
        slot: u32,
        under: u32,
        transition: u32,

        fn before(_: void, x: Draw, y: Draw) bool {
            if (x.landed != y.landed) return x.landed < y.landed;
            if (x.under != y.under) return x.under < y.under;
            return x.slot < y.slot;
        }
    };

    const none = std.math.maxInt(u32);

    /// Walk every way every fold in the automaton is reached, once, so that both
    /// judging a fold and grouping a state's arrivals are passes over this list
    /// rather than more walks of the transitions.
    fn trace(b: *Build, draws: *std.ArrayList(Draw)) !void {
        for (b.transitions, 0..) |t, i| {
            for (b.gr.productionsOf(t.symbol)) |p| {
                const rhs = b.gr.productions[p].rhs;
                // A fold that consumed nothing happens in the state the
                // transition leaves from, so no arrival stands under it and no
                // grouping of arrivals can separate its contexts.
                if (rhs.len == 0) continue;
                const landed = b.c.walk(t.from, rhs).?;
                const slot = b.slotOf(landed, p) orelse continue;
                try draws.append(b.gpa, .{
                    .landed = landed,
                    .slot = slot,
                    .under = b.c.walk(t.from, rhs[0 .. rhs.len - 1]).?,
                    .transition = @intCast(i),
                });
            }
        }
        std.mem.sortUnstable(Draw, draws.items, {}, Draw.before);
    }

    /// Group every seam state's arrivals by the lookahead they contribute.
    fn regroup(
        b: *Build,
        arena: std.mem.Allocator,
        list: []Seam,
        holds: []const u32,
        all: []const Draw,
    ) !void {
        var groups: std.AutoHashMapUnmanaged(u64, u32) = .empty;
        defer groups.deinit(b.gpa);
        var lanes: std.ArrayList(Seam.Lane) = .empty;
        defer lanes.deinit(b.gpa);
        // The state's over-permitted terminals as a mask, so an arrival is
        // compared only where the disagreement is.
        const wanted = try b.gpa.alloc(u64, b.follow.stride);
        defer b.gpa.free(wanted);
        const drew = try b.gpa.alloc(u64, b.follow.stride);
        defer b.gpa.free(drew);
        // The same span intersected rather than unioned, and what that
        // difference accumulates to over the whole state: an arrival that
        // reaches one fold two ways and disagrees with itself carries its own
        // union into every copy, so no cut here removes it.
        const both = try b.gpa.alloc(u64, b.follow.stride);
        defer b.gpa.free(both);
        const stuck = try b.gpa.alloc(u64, b.follow.stride);
        defer b.gpa.free(stuck);
        var fixed: std.ArrayList(u32) = .empty;
        defer fixed.deinit(b.gpa);

        var run: usize = 0;
        while (run < all.len) {
            var end = run;
            while (end < all.len and all[end].landed == all[run].landed) end += 1;
            const at = holds[all[run].landed];
            if (at == none) {
                run = end;
                continue;
            }
            const seam = &list[at];
            @memset(wanted, 0);
            for (seam.over) |t| wanted[t / 64] |= @as(u64, 1) << @intCast(t % 64);

            groups.clearRetainingCapacity();
            lanes.clearRetainingCapacity();
            @memset(stuck, 0);
            // Draws arrive sorted by arrival and then by fold, so an arrival's
            // whole contribution is one contiguous span and its identity can be
            // hashed as it is read. Materialising the (arrival × fold) matrix
            // instead costs a state reached three thousand ways with twenty
            // folds a quarter of a million words of zeroing to write a few
            // hundred - which was most of rust's press.
            var from = run;
            while (from < end) {
                var mine = from;
                while (mine < end and all[mine].under == all[from].under) mine += 1;
                var seal: std.hash.Wyhash = .init(0);
                var one = from;
                while (one < mine) {
                    var same = one;
                    @memset(drew, 0);
                    @memcpy(both, wanted);
                    while (same < mine and all[same].slot == all[one].slot) : (same += 1) {
                        // Masked as it is gathered. Two arrivals that draw
                        // different lookaheads *outside* the over-permitted set
                        // are not what this state is wrong about, and separating
                        // them is automaton nobody asked for - the difference
                        // between two copies of a state reached forty ways and
                        // forty of them.
                        for (drew, both, b.follow.row(all[same].transition), wanted) |*w, *v, f, m| {
                            w.* |= f & m;
                            v.* &= f;
                        }
                    }
                    for (stuck, drew, both) |*s, w, v| s.* |= w & ~v;
                    // A fold nothing drew is absent rather than zero, so the
                    // slot travels with the row: two arrivals that reach
                    // different folds are different contexts even when both
                    // draw nothing over-permitted.
                    seal.update(std.mem.asBytes(&all[one].slot));
                    seal.update(std.mem.sliceAsBytes(drew));
                    one = same;
                }
                const slot = try groups.getOrPut(b.gpa, seal.final());
                if (!slot.found_existing) slot.value_ptr.* = groups.count() - 1;
                try lanes.append(b.gpa, .{ .from = all[from].under, .lane = slot.value_ptr.* });
                from = mine;
            }
            seam.arrivals = @intCast(lanes.items.len);
            fixed.clearRetainingCapacity();
            for (seam.over) |t| {
                if (stuck[t / 64] & @as(u64, 1) << @intCast(t % 64) != 0) try fixed.append(b.gpa, t);
            }
            seam.stubborn = try arena.dupe(u32, fixed.items);
            // One lane is the whole state, which is what it already is; a cut
            // whose every invention is stubborn is a copy that changes nothing.
            if (groups.count() > 1 and fixed.items.len < seam.over.len) {
                seam.lanes = try arena.dupe(Seam.Lane, lanes.items);
            }
            run = end;
        }
    }

    /// Which of a state's completions is this production, as an index into
    /// `complete` rather than into the lookahead matrix.
    fn slotOf(b: Build, state: u32, prod: u32) ?u32 {
        for (b.c.states[state].complete, 0..) |p, k| {
            if (p == prod) return @intCast(k);
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
        // Both before the arena is copied into the literal: it captures its
        // buffer list by value, so anything allocated as a later field would be
        // invisible to the copy that owns it.
        const shown = try b.seams(owned.allocator(), verdict.action);

        return .{
            .arena = owned,
            .end = b.gr.terminal_count,
            .width = b.width,
            .action = verdict.action,
            .conflicts = verdict.conflicts,
            .frayed = verdict.frayed,
            .seams = shown,
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

test "precedence settles a shift-reduce silently and associativity settles one aloud" {
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

    // Four contested cells, settled on two different rungs, and the table is
    // the same either way — every action above is what it always was. What
    // separates them is *what did the settling*. Two were ordered by a rank the
    // author wrote about this very pair, and a rank that speaks deletes the
    // reading it outranks: those stay silent, because there is nothing left to
    // fork on. The other two are each operator against itself, where the ranks
    // tie and only a side declared over the whole rule breaks it. A side orders
    // the pair; it never said the other reading was wrong. So those two are
    // recorded and their read is left standing.
    //
    // Asserted by address rather than by count. `conflicts.len == 2` is also
    // true when the recorder fires on the precedence pair and skips the
    // associativity pair — the exact over-reach this distinction exists to
    // prevent — so the count is checked last and the four addresses first.
    try testing.expect(t.conflictAt(plus_state, x.star) == null);
    try testing.expect(t.conflictAt(star_state, x.plus) == null);
    for ([_]struct { u32, u32 }{ .{ plus_state, x.plus }, .{ star_state, x.star } }) |cell| {
        const k = t.conflictAt(cell[0], cell[1]) orelse return error.TestExpectedEqual;
        try testing.expectEqual(Conflict.Kind.shift_reduce, k.kind);
    }
    try testing.expectEqual(@as(usize, 2), t.conflicts.len);
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

test "the halves partition the verbs, and a real table has rows where they differ" {
    // Two assertions, and the second is the one that keeps the first honest.
    //
    // **Total and disjoint.** Every action a cell can hold lands in exactly one
    // half, or a footer that adds the two counts and calls the sum "accepted"
    // is lying. Written as an exhaustive walk of the verb enum so that a fifth
    // verb added later reddens here rather than silently vanishing from one of
    // the two lists.
    var verbs: u32 = 0;
    inline for (@typeInfo(@FieldType(Action, "kind")).@"enum".fields) |f| {
        const half = Half.of(@enumFromInt(f.value));
        if (std.mem.eql(u8, f.name, "err")) {
            try testing.expectEqual(@as(?Half, null), half);
        } else {
            try testing.expect(half != null);
            verbs += 1;
        }
    }
    try testing.expectEqual(@as(u32, 3), verbs);

    // **And the split is not vacuous.** Everything downstream - `state
    // --census`, `inquest`'s stand-in, `survey`'s legal set - exists because
    // the two halves of a row are different sets. If a real table had no state
    // where both halves are occupied and unequal, "say which half you mean"
    // would be a distinction with nothing behind it and every one of those
    // reports could go back to printing one number. So a pressed grammar is
    // required to produce such a state, and this fails if one ever cannot.
    var x = try Expr.init(testing.allocator, 1, 2, .left);
    defer x.deinit();
    var c = try lr0.build(testing.allocator, &x.gr, .{});
    defer c.deinit();
    var t = try build(testing.allocator, &x.gr, &c);
    defer t.deinit();

    var found = false;
    for (0..c.states.len) |s| {
        var shifts: u32 = 0;
        var folds: u32 = 0;
        for (0..t.width) |sym| switch (Half.of(t.at(@intCast(s), @intCast(sym)).kind) orelse continue) {
            .shift => shifts += 1,
            .fold => folds += 1,
        };
        if (shifts > 0 and folds > 0 and shifts != folds) found = true;
    }
    try testing.expect(found);
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

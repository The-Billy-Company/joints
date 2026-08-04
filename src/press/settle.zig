//! Deciding a contested cell: what a state does when it could both read on and
//! fold up, or fold up two different ways.
//!
//! Lookaheads say which reductions are *legal* in a state. They do not say
//! which one a parser should take when several are, and that question is where
//! every real grammar lives: `a - b - c` is legal read either way, and only the
//! author's declared associativity says which one the language means.
//!
//! The mistake this module exists to avoid is treating that as a table-filling
//! detail. Written inline in the tabulator it comes out as "shift wins, yacc
//! says so", which is a *choice made silently on the author's behalf* — and the
//! count of those choices is precisely the number this whole layer is being
//! judged on. So the ladder is written out, in the order the declarations were
//! meant to be consulted:
//!
//!   1. **Reduction against reduction, by precedence.** A stronger reduction
//!      erases the weaker ones outright; equals accumulate and stay contested.
//!      This rung is easy to miss — precedence is usually explained as ordering
//!      a fold against a read — and skipping it leaves every prec-ranked
//!      alternative of one rule fighting its siblings forever.
//!   2. **Read against fold, by precedence.** Every *interpretation* standing
//!      in the state gets a vote, because a state generally holds several items
//!      whose continuation could begin with the contested token and they need
//!      not agree. The precedence of an interpretation is the precedence of the
//!      symbol it just consumed — not of the token it is about to read, which
//!      belongs to whatever rule the token starts and says nothing about the
//!      fold being contemplated here.
//!   3. **Associativity**, once precedence has tied.
//!   4. **Attribution**, for whatever is left: one synthesized rule arguing
//!      with itself, a group the author declared ambiguous, or a genuine
//!      residue. Only the third is a defect.
//!
//! Every rung is the one tree-sitter walks, including the exception on rung 2
//! that looks like a bug and is not (see `Ladder.step`). Matching it is the
//! point: three hundred grammars were debugged against *these* rules, and a
//! generator that resolves them 99% the same way is a generator that parses a
//! different language on 1% of files.

const std = @import("std");
const first = @import("first.zig");
const g = @import("grammar.zig");
const lr0 = @import("lr0.zig");
const retrace = @import("retrace.zig");
const sets = @import("sets.zig");

pub const Action = packed struct(u32) {
    kind: Kind,
    /// Target state for a shift, production index for a reduce.
    value: u30,

    pub const Kind = enum(u2) { err, shift, reduce, accept };
    pub const err: Action = .{ .kind = .err, .value = 0 };

    pub fn shift(target: u32) Action {
        return .{ .kind = .shift, .value = @intCast(target) };
    }

    pub fn reduce(prod: u32) Action {
        return .{ .kind = .reduce, .value = @intCast(prod) };
    }

    fn none(a: Action) bool {
        return a.kind == .err;
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
    class: Class,
    /// What the table will do. A contested cell still needs one answer.
    chosen: Action,
    /// One of the readings that lost, for the report. There may have been more.
    other: Action,
    /// The rules whose readings were party to the cell, deduplicated, sorted,
    /// and mapped through `Grammar.owner` — which is exactly the group tested
    /// against the author's declared ambiguities. Kept rather than recomputed
    /// because it is the *evidence* for `class`: a residual conflict whose party
    /// is one symbol away from a declared group is an attribution bug, and
    /// without this there is no way to see that from the outside.
    party: []const g.Symbol,

    pub const Kind = enum { shift_reduce, reduce_reduce };

    /// *Whose* ambiguity this is. Precedence and associativity have already had
    /// their say by the time a conflict is recorded, so what remains is a
    /// question of attribution — and the three answers deserve three different
    /// reactions.
    pub const Class = enum {
        /// Every reading belongs to one nonterminal the front end synthesized —
        /// a repeat helper deciding whether to go round again. The language has
        /// no ambiguity here; the normalization does, and reading on is what
        /// "continue the list" means.
        repetition,
        /// The rules involved are a group the author declared ambiguous. A real
        /// fork, sanctioned, and the thing a GLR parser is *for*.
        declared,
        /// Nobody claimed this one. The only class that is a defect.
        residual,
    };
};

/// A cell that is only a contest because one LR(0) state is standing in for
/// several LR(1) ones.
///
/// The fold competing here is legal on this terminal after *some* of the paths
/// that reach the state and not after others. Merging unioned those paths, so
/// the table has to answer once for contexts that want different answers — and
/// whichever way it answers, one of them is wrong. Precedence will still pick a
/// side, quietly and plausibly; recording the cell is what keeps that from
/// looking like an author's decision. `press` splits the state and asks again.
pub const Frayed = struct {
    state: u32,
    terminal: u32,
    harm: Harm,

    /// Which way the merged answer went. Both refuse tokens; they differ only in
    /// where the refusal surfaces.
    pub const Harm = enum {
        /// A read was removed in favour of a fold that is only legal after some
        /// of the paths here. After the others the token is now unparseable, in
        /// this very cell — the token C's `p->q = 1` dies on.
        read_dropped,
        /// The read stood, or two folds disagreed and one was picked. The cell
        /// still answers, so nothing is refused *here*; the wrong fold is taken
        /// and the token that no longer fits is refused a few states later. Go
        /// folds `p.Q` to a `qualified_type` rather than a selector and then has
        /// nowhere to put the `=`, three states along and with the evidence
        /// gone.
        fold_dropped,
    };
};

/// How many cells of each class the grammar left behind.
pub const Tally = struct {
    repetition: u32 = 0,
    declared: u32 = 0,
    /// Split by which decision was left open, because the two have different
    /// cures. Precedence orders a fold against a read; it also orders two folds
    /// against each other, but only when the author ranked them.
    residual: Split = .{},

    pub const Split = struct {
        shift_reduce: u32 = 0,
        reduce_reduce: u32 = 0,

        pub fn total(s: Split) u32 {
            return s.shift_reduce + s.reduce_reduce;
        }
    };

    pub fn total(t: Tally) u32 {
        return t.repetition + t.declared + t.residual.total();
    }
};

/// Where a parse may legitimately split, and into what.
///
/// A contested cell still answers once, because a table has to. But the reading
/// it dropped is not a mistake: it is the other half of an ambiguity the author
/// declared, and it is the whole difference between C's `long total;` being a
/// declaration and being nothing the table can continue from. `Conflict` already
/// records the loser; this is that record turned into something a parse loop can
/// ask on every token without noticing.
///
/// **Only `declared` cells are forks.** A `repetition` cell is a list deciding
/// whether it is over, and reading on is what a repeat *means* - the language
/// never saw a choice, so forking there would double the parse on every element
/// of every list to reach a reading nobody wanted. A `residual` cell is a
/// defect: nobody sanctioned that ambiguity, and exploring it would be guessing
/// on the author's behalf a second time, in the other direction.
///
/// Built by the consumer rather than carried in the `Verdict`, because it is an
/// index over a table and not a fact the table was missing. A press that only
/// means to report on a grammar should not pay for it.
pub const Forks = struct {
    /// One bit per cell, so an uncontested cell costs a masked load and never a
    /// search. Contested cells number in the hundreds against a table of
    /// hundreds of thousands, which is exactly the ratio that makes a bitset
    /// over a sorted list beat a second dense table by thirty-two to one on
    /// space and lose nothing on time.
    marked: []const u64,
    /// Cell, and the reading the table dropped there. Sorted by cell.
    splits: []const Split,
    width: u32,

    pub const Split = struct { cell: u32, other: Action };

    pub fn of(
        gpa: std.mem.Allocator,
        conflicts: []const Conflict,
        states: usize,
        width: u32,
    ) !Forks {
        var splits: std.ArrayList(Split) = .empty;
        errdefer splits.deinit(gpa);
        for (conflicts) |k| {
            if (k.class != .declared or k.other.none()) continue;
            try splits.append(gpa, .{ .cell = k.state * width + k.terminal, .other = k.other });
        }
        std.mem.sortUnstable(Split, splits.items, {}, before);

        const marked = try gpa.alloc(u64, (states * width + 63) / 64);
        @memset(marked, 0);
        for (splits.items) |s| marked[s.cell >> 6] |= @as(u64, 1) << @truncate(s.cell);
        return .{ .marked = marked, .splits = try splits.toOwnedSlice(gpa), .width = width };
    }

    fn before(_: void, a: Split, b: Split) bool {
        return a.cell < b.cell;
    }

    fn seek(key: u32, s: Split) std.math.Order {
        return std.math.order(key, s.cell);
    }

    pub fn deinit(f: *Forks, gpa: std.mem.Allocator) void {
        gpa.free(f.marked);
        gpa.free(f.splits);
        f.* = undefined;
    }

    /// The reading this cell dropped, when the author declared the cell a
    /// choice. Null for every other cell, which is nearly all of them.
    pub fn at(f: Forks, state: u32, terminal: u32) ?Action {
        const cell = state * f.width + terminal;
        if (f.marked[cell >> 6] & (@as(u64, 1) << @truncate(cell)) == 0) return null;
        return f.splits[std.sort.lowerBound(Split, f.splits, cell, seek)].other;
    }

    /// How many cells a parse over this table may split at. Zero is a grammar
    /// that never forks, which is why a fork must cost json nothing.
    pub fn count(f: Forks) usize {
        return f.splits.len;
    }
};

/// Everything needed to judge one grammar's cells, and nothing else: the
/// grammar, its automaton, which reductions are legal where, and what each
/// symbol can begin with.
pub const Case = struct {
    gr: *const g.Grammar,
    c: *const lr0.Collection,
    first: *const first.First,
    /// One row per `(state, complete production)` pair, addressed through
    /// `reduction_base`.
    la: sets.Matrix,
    /// `la` intersected over the contexts that reach each reduction; see
    /// `Frayed`.
    meet: sets.Matrix,
    reduction_base: []const u32,
    /// Terminal columns plus the synthetic end-of-input column.
    width: u32,
};

pub const Verdict = struct {
    action: []const Action,
    conflicts: []const Conflict,
    frayed: []const Frayed,
};

/// Decide every cell. `arena` owns the result; `gpa` owns only scratch.
pub fn all(x: Case, gpa: std.mem.Allocator, arena: std.mem.Allocator) !Verdict {
    const action = try arena.alloc(Action, x.c.states.len * x.width);
    @memset(action, Action.err);

    var b: Bench = .{
        .x = x,
        .gpa = gpa,
        .action = action,
        .folds = try gpa.alloc(Folds, x.width),
        .closure = try lr0.Closure.init(gpa, x.gr),
        .origin = try lr0.Closure.init(gpa, x.gr),
        .rev = try retrace.Retrace.build(gpa, x.c),
    };
    defer b.deinit();

    for (0..x.c.states.len) |q| try b.judge(@intCast(q));

    // Parties accumulate into one flat run while judging, because a per-conflict
    // allocation for a two-symbol set is most of an allocator call spent on
    // nothing. They are cut into slices here, over arena memory the caller owns.
    const roll = try arena.dupe(g.Symbol, b.roll.items);
    const conflicts = try arena.dupe(Conflict, b.conflicts.items);
    for (conflicts, b.cuts.items) |*k, cut| k.party = roll[cut.at..][0..cut.len];
    return .{
        .action = action,
        .conflicts = conflicts,
        .frayed = try arena.dupe(Frayed, b.frayed.items),
    };
}

/// The reductions standing in one column, after they have been compared against
/// each other. At most two are remembered: the one the table will take, and one
/// rival for the report — a third tied reduction changes nothing about the
/// verdict and would only lengthen the record.
const Folds = struct {
    chosen: Action = Action.err,
    rival: Action = Action.err,
    prec: g.Prec = .none,
    /// The nonterminals the surviving reductions build. Carried because an
    /// ordering may rank *rules* rather than precedence names, and then this is
    /// the only thing a comparison has to match against.
    ///
    /// Inline and bounded rather than allocated: this is scratch for one column
    /// of one state, cleared by a `memset` between states, and a heap call per
    /// cell would be most of what this pass costs. Past the bound the set stops
    /// growing, so an ordering that names a rule beyond it finds nothing and
    /// the comparison comes back equal — the same answer as an author who
    /// ranked nothing, which is the safe direction to fail: the cell stays
    /// contested and gets reported rather than being resolved on a guess.
    rules: [8]g.Symbol = undefined,
    count: u8 = 0,
    /// Associativity across every *surviving* reduction. Three flags rather
    /// than one value because they are not exclusive: two productions can tie
    /// on precedence and disagree on associativity, and that disagreement is
    /// itself the answer (nothing is resolved).
    left: bool = false,
    right: bool = false,
    loose: bool = false,

    fn empty(f: Folds) bool {
        return f.chosen.none();
    }

    /// The rules the surviving reductions speak for.
    fn speaks(f: *const Folds) []const g.Symbol {
        return f.rules[0..f.count];
    }

    /// Offer a reduction to the column, keeping the strongest.
    fn offer(f: *Folds, gr: *const g.Grammar, prod: u32, lhs: g.Symbol, step: g.Step) void {
        const act = Action.reduce(prod);
        if (f.empty()) {
            f.* = .{ .chosen = act, .prec = step.prec };
        } else switch (gr.compare(step.prec, &.{lhs}, f.prec, f.speaks())) {
            // Stronger: the weaker readings were never really candidates, so
            // they leave no trace — not even an associativity flag.
            .gt => f.* = .{ .chosen = act, .prec = step.prec },
            .lt => return,
            // A tie is the contested case, and both readings survive it: what
            // gets decided here is only which one the table takes *first*,
            // since a declared tie becomes the fork's primary and its rival,
            // and the parse prefers the primary.
            //
            // Which is the question `prec.dynamic` was written to answer. The
            // real generator keeps both folds in the cell and carries the ranks
            // beside them - `REDUCE(sym_wide, 2, -1, 0), REDUCE(sym_plain, 2,
            // 0, 0)` for a two-branch tie where one branch is ranked -1 - so a
            // dynamic rank resolves nothing and orders everything. Ranked
            // equally, the earlier production wins, which is the order the
            // author wrote them in.
            .eq => {
                f.prec = step.prec;
                if (keener(gr, act, f.chosen)) {
                    f.rival = f.chosen;
                    f.chosen = act;
                } else if (f.rival.none()) {
                    f.rival = act;
                }
            },
        }
        if (std.mem.indexOfScalar(g.Symbol, f.speaks(), lhs) == null and f.count < f.rules.len) {
            f.rules[f.count] = lhs;
            f.count += 1;
        }
        switch (step.assoc) {
            .left => f.left = true,
            .right => f.right = true,
            .none => f.loose = true,
        }
    }

    fn tied(f: Folds) bool {
        return !f.rival.none();
    }
};

/// Whether `a` is the reading to take ahead of `b`, for two folds a static
/// ordering left tied. The higher dynamic rank first, and among equals the
/// earlier production - so a grammar that never writes `prec.dynamic` gets the
/// order it always got, and one that does gets the order it asked for.
///
/// Per-production, where tree-sitter compares the *sum* over each candidate
/// subtree. The two agree whenever the difference is on the fold being compared,
/// which is the shape authors write: c ranks the branch that swallows an
/// identifier into a type at -1 and its rival at 0. Where a rank deeper in
/// either subtree would flip it, only the fork can know, since only the fork has
/// the subtrees.
fn keener(gr: *const g.Grammar, a: Action, b: Action) bool {
    const x = gr.productions[a.value].dynamic;
    const y = gr.productions[b.value].dynamic;
    return if (x != y) x > y else a.value < b.value;
}

/// What the readings standing in a state have to say about one contested cell.
const Survey = struct {
    /// How each in-progress reading's precedence compared with the surviving
    /// reductions'. Not exclusive: a state can hold one interpretation that
    /// outranks the fold and another that loses to it, which is exactly the
    /// case rung 2 has to be careful about.
    above: bool = false,
    below: bool = false,
    level: bool = false,
    /// Some reading is the surviving fold's own production, continuing. Not an
    /// ambiguity at all - see `Ladder.step`.
    continues: bool = false,
    /// The one rule every reading belongs to, when there is one.
    sole: ?g.Symbol = null,
    one_rule: bool = true,
};

const Bench = struct {
    x: Case,
    gpa: std.mem.Allocator,
    action: []Action,
    /// Per-terminal scratch for the state being judged.
    folds: []Folds,
    closure: lr0.Closure,
    /// A second closure, for the predecessor states an attribution reads. It
    /// cannot share `closure`: the items being judged are a slice into that one.
    origin: lr0.Closure,
    rev: retrace.Retrace,
    conflicts: std.ArrayList(Conflict) = .empty,
    frayed: std.ArrayList(Frayed) = .empty,
    /// Columns that need the second pass. Reused across states.
    contested: std.ArrayList(u32) = .empty,
    /// One cell's party, built in two parts because the second part has more
    /// than one candidate: `owners` are the rules named outright by a reading,
    /// `lists` are the synthesized readings that have to be traced back to
    /// whoever was expecting them, and `party` is the candidate under test.
    owners: std.ArrayList(g.Symbol) = .empty,
    lists: std.ArrayList(Pending) = .empty,
    party: std.ArrayList(g.Symbol) = .empty,
    exposed: std.ArrayList(u32) = .empty,
    /// Every recorded conflict's party, end to end, and where each one sits.
    roll: std.ArrayList(g.Symbol) = .empty,
    cuts: std.ArrayList(struct { at: u32, len: u32 }) = .empty,

    /// A synthesized reading waiting to be attributed: the rule the front end
    /// invented, and the part of it this state has consumed.
    const Pending = struct { lhs: g.Symbol, prefix: []const g.Symbol };

    fn deinit(b: *Bench) void {
        b.gpa.free(b.folds);
        b.closure.deinit(b.gpa);
        b.origin.deinit(b.gpa);
        b.rev.deinit(b.gpa);
        b.conflicts.deinit(b.gpa);
        b.frayed.deinit(b.gpa);
        b.contested.deinit(b.gpa);
        b.owners.deinit(b.gpa);
        b.lists.deinit(b.gpa);
        b.party.deinit(b.gpa);
        b.exposed.deinit(b.gpa);
        b.roll.deinit(b.gpa);
        b.cuts.deinit(b.gpa);
    }

    fn row(b: *Bench, state: u32) []Action {
        return b.action[state * b.x.width ..][0..b.x.width];
    }

    /// The lookahead row for a completed production in a state, or null when
    /// that production does not complete there.
    fn lookahead(b: Bench, state: u32, prod: u32) ?usize {
        for (b.x.c.states[state].complete, 0..) |p, k| {
            if (p == prod) return b.x.reduction_base[state] + k;
        }
        return null;
    }

    /// Fill one state's row. Reads and folds are gathered first and compared
    /// only where they actually meet, so the expensive part — re-deriving the
    /// state's readings — is paid once per state that has a contest, and not at
    /// all by the states that do not.
    fn judge(b: *Bench, state: u32) !void {
        @memset(b.folds, .{});
        const st = b.x.c.states[state];
        const r = b.row(state);

        for (st.edges) |e| {
            if (b.x.gr.isTerminal(e.symbol)) r[e.symbol] = Action.shift(e.target);
        }

        for (st.complete, 0..) |prod, k| {
            const p = b.x.gr.productions[prod];
            var it = b.x.la.iterate(b.x.reduction_base[state] + k);
            // Accept is not a reduction competing with others: it can only be
            // contested at end of input, where no read is pending and no other
            // fold is meaningful.
            if (prod == 0) {
                while (it.next()) |t| r[t] = .{ .kind = .accept, .value = 0 };
                continue;
            }
            while (it.next()) |t| b.folds[t].offer(b.x.gr, prod, p.lhs, p.consumed(p.rhs.len));
        }

        b.contested.clearRetainingCapacity();
        for (b.folds, 0..) |f, t| {
            if (f.empty() or r[t].kind == .accept) continue;
            if (r[t].kind == .shift or f.tied()) {
                try b.contested.append(b.gpa, @intCast(t));
            } else {
                r[t] = f.chosen;
            }
        }
        if (b.contested.items.len == 0) return;

        const items = try b.closure.of(b.gpa, b.x.gr, st.kernel);
        for (b.contested.items) |t| try b.decide(state, t, items);
    }

    /// Is the fold in this cell legal on this terminal after every path into the
    /// state, or only after some of them? See `Frayed`.
    fn frays(b: Bench, state: u32, t: u32) bool {
        for (b.x.c.states[state].complete, 0..) |prod, k| {
            if (prod == 0) continue;
            const r = b.x.reduction_base[state] + k;
            if (b.x.la.isSet(r, t) and !b.x.meet.isSet(r, t)) return true;
        }
        return false;
    }

    /// Walk the ladder for one cell, and record what is left.
    fn decide(b: *Bench, state: u32, t: u32, items: []const lr0.Item) !void {
        const frayed = b.frays(state, t);
        const r = b.row(state);
        const f = b.folds[t];
        const reading = r[t].kind == .shift;

        var keep_read = reading;
        var keep_fold = true;
        var survey = try b.poll(state, t, items, f, .all);

        // A rule's own tail only outranks its fold where the fold had no business
        // in this column: `frays` is true exactly when the lookahead admits the
        // terminal under the union over arrivals and not under the intersection,
        // so the permission is the merge's invention rather than the grammar's.
        survey.continues = survey.continues and frayed;

        if (reading) {
            // One synthesized rule arguing with itself is a list deciding
            // whether it is over. Reading on is what a repeat means, and the
            // language never saw a choice here — so this is settled before
            // precedence is consulted, exactly as upstream settles it, rather
            // than being left for precedence that was never written down.
            const repetition = survey.one_rule and
                survey.sole != null and b.x.gr.isSynthetic(survey.sole.?);
            if (repetition) {
                // Named anyway: the class is already settled, but the report
                // still has to say which list it was.
                _ = try b.attribute(state);
                try b.record(state, t, .shift_reduce, .repetition, r[t], f.chosen);
                if (frayed) try b.fray(state, t, .fold_dropped);
                return;
            }
            switch (Ladder.step(survey, f)) {
                .read => keep_fold = false,
                .fold => keep_read = false,
                .undecided => {},
            }
        }

        // With the read eliminated, the in-progress readings are no longer party
        // to anything: what is left is a disagreement among completed
        // productions, and only those should be named in the report.
        if (!keep_read and reading) survey = try b.poll(state, t, items, f, .folds_only);

        // A read and a fold both still standing, and nothing static between
        // them: the table names the read, which is the right default and the
        // wrong one where the author ranked every available reading below the
        // fold. Yielding changes which of two surviving actions is primary and
        // which one the fork speculates on - `standing` and the conflict's kind
        // are what they were, so no cell becomes any more or less contested.
        const yield = keep_read and keep_fold and
            b.leading(items, t) < b.x.gr.productions[f.chosen.value].dynamic;

        const standing: u32 = @as(u32, @intFromBool(keep_read)) +
            (if (keep_fold) @as(u32, if (f.tied()) 2 else 1) else 0);
        const read = r[t];
        r[t] = if (keep_read and !yield) read else f.chosen;
        if (frayed) try b.fray(state, t, if (reading and !keep_read) .read_dropped else .fold_dropped);
        if (standing <= 1) return;

        const kind: Conflict.Kind = if (keep_read) .shift_reduce else .reduce_reduce;
        const other = if (!keep_read) f.rival else if (yield) read else f.chosen;
        try b.record(state, t, kind, try b.attribute(state), r[t], other);
    }

    /// The best dynamic rank among the readings that would shift this terminal.
    /// The best rather than any, so a reading only yields to a fold when every
    /// one of them was ranked below it.
    fn leading(b: Bench, items: []const lr0.Item, t: u32) i16 {
        var best: i16 = std.math.minInt(i16);
        for (items) |it| {
            const p = b.x.gr.productions[it.prod];
            if (it.dot >= p.rhs.len or p.rhs[it.dot] != t) continue;
            best = @max(best, p.dynamic);
        }
        return if (best == std.math.minInt(i16)) 0 else best;
    }

    fn fray(b: *Bench, state: u32, t: u32, harm: Frayed.Harm) !void {
        try b.frayed.append(b.gpa, .{ .state = state, .terminal = t, .harm = harm });
    }

    fn record(
        b: *Bench,
        state: u32,
        terminal: u32,
        kind: Conflict.Kind,
        class: Conflict.Class,
        chosen: Action,
        other: Action,
    ) !void {
        try b.cuts.append(b.gpa, .{
            .at = @intCast(b.roll.items.len),
            .len = @intCast(b.party.items.len),
        });
        try b.roll.appendSlice(b.gpa, b.party.items);
        try b.conflicts.append(b.gpa, .{
            .state = state,
            .terminal = terminal,
            .kind = kind,
            .class = class,
            .chosen = chosen,
            .other = other,
            // Cut from the roll once it has stopped moving; see `all`.
            .party = &.{},
        });
    }

    const Party = enum { all, folds_only };

    /// Which of a state's readings are party to this cell, what precedence each
    /// in-progress one carries, and which rules they belong to.
    ///
    /// A completed production is party when its lookahead admits the terminal.
    /// An in-progress one is party when its continuation could *begin* with the
    /// terminal — a FIRST question, and the reason this layer needs FIRST at all
    /// — and when its dot has actually moved: a reading that has consumed
    /// nothing is not an alternative interpretation of anything, and carries no
    /// precedence to contribute.
    fn poll(b: *Bench, state: u32, t: u32, items: []const lr0.Item, f: Folds, who: Party) !Survey {
        var out: Survey = .{};
        b.owners.clearRetainingCapacity();
        b.lists.clearRetainingCapacity();

        for (items) |item| {
            // The augmented production is nobody's ambiguity: it is the frame
            // the parse happens inside.
            if (item.prod == 0) continue;
            const p = b.x.gr.productions[item.prod];
            const done = item.dot == p.rhs.len;
            if (done) {
                const la = b.lookahead(state, item.prod) orelse continue;
                if (!b.x.la.isSet(la, t)) continue;
            } else {
                if (who == .folds_only) continue;
                if (item.dot == 0 or !b.x.first.has(p.rhs[item.dot], t)) continue;
                // The reading's rank is the rank of the step it has just
                // consumed, and the rule it speaks for is its own left-hand
                // side — which is what an ordering naming rules matches on.
                switch (b.x.gr.compare(p.consumed(item.dot).prec, &.{p.lhs}, f.prec, f.speaks())) {
                    .gt => out.above = true,
                    .lt => out.below = true,
                    .eq => out.level = true,
                }
                if (b.resumes(item, f)) out.continues = true;
            }

            if (out.sole) |s| {
                if (s != p.lhs) out.one_rule = false;
            } else out.sole = p.lhs;

            if (b.x.gr.isSynthetic(p.lhs)) {
                try b.lists.append(b.gpa, .{ .lhs = p.lhs, .prefix = p.rhs[0..item.dot] });
            } else {
                try enrol(b.gpa, &b.owners, b.x.gr.owner[p.lhs]);
            }
        }
        return out;
    }

    /// Whether this reading is a surviving fold's own production, continuing past
    /// where the fold stops: same rule, same steps consumed, and more to come.
    ///
    /// That is an optional suffix written as two branches of one rule, not two
    /// readings of the same text, and the distinguishing mark is the dot. A
    /// left-associative operator puts the two dots in *different* places - `E ->
    /// E + E .` against `E -> E . + E` - because the fold has consumed an operand
    /// the read has not. Here both have consumed the same prefix and one simply
    /// has further to go, so there is no second instance of anything for a side
    /// to be chosen between.
    fn resumes(b: Bench, item: lr0.Item, f: Folds) bool {
        const p = b.x.gr.productions[item.prod];
        for ([2]Action{ f.chosen, f.rival }) |act| {
            if (act.kind != .reduce) continue;
            const fold = b.x.gr.productions[act.value];
            if (fold.lhs != p.lhs or fold.rhs.len != item.dot) continue;
            if (std.mem.eql(g.Symbol, fold.rhs, p.rhs[0..item.dot])) return true;
        }
        return false;
    }

    /// Add one rule to a party, keeping it sorted and deduplicated. Sorted
    /// because a party is compared against the author's declared groups as a
    /// set, and a set spelled in traversal order is not comparable.
    fn enrol(gpa: std.mem.Allocator, into: *std.ArrayList(g.Symbol), rule: g.Symbol) !void {
        const at = std.sort.lowerBound(g.Symbol, into.items, rule, order);
        if (at == into.items.len or into.items[at] != rule) try into.insert(gpa, at, rule);
    }

    /// Whose ambiguity the cell is, once the synthesized readings have been
    /// traced back to the rules that were expecting them.
    ///
    /// A list the front end invented has no author, so naming it after the rule
    /// that happened to mention it first names an artifact of traversal order.
    /// Worse, it is wrong in exactly the case that matters: a list body written
    /// identically in a dozen rules is *one* symbol, shared, and the rule it is
    /// building here is whichever rule was expecting it — a fact about this
    /// state, not about the grammar.
    ///
    /// Unwinding the consumed part of the production gives the states that were
    /// expecting it, and there is generally more than one, because that is what
    /// an LR state is for. Each is a separate candidate rather than one union:
    /// they are different stacks, and a declaration sanctions an ambiguity
    /// between rules that can actually be confused *on some stack*. Unioning
    /// them instead reports a group no parse ever holds — C would come back
    /// claiming `attributed_declarator` and `attributed_statement` are confused
    /// with each other, when the truth is that each is separately confused with
    /// its own list.
    ///
    /// A grammar's own declarations are the arbiter of which candidate to
    /// believe: the first one the author sanctioned is the reading they meant.
    /// With none sanctioned there is nothing to choose between, and the union is
    /// reported — the honest superset, and the shape a reader needs to see to
    /// write the declaration that would settle it.
    fn attribute(b: *Bench, state: u32) !Conflict.Class {
        b.party.clearRetainingCapacity();
        try b.party.appendSlice(b.gpa, b.owners.items);
        if (b.lists.items.len == 0) {
            return if (b.x.gr.declared(b.party.items)) .declared else .residual;
        }

        // Every production of a list unwinds to a state where that list was
        // expected — `L -> x` over one step and `L -> L x` over two both land
        // where the `L` began — so the candidates line up across readings and
        // can be indexed by that state.
        b.exposed.clearRetainingCapacity();
        for (b.lists.items) |l| {
            for (try b.rev.back(b.gpa, state, l.prefix)) |q| {
                if (std.mem.indexOfScalar(u32, b.exposed.items, q) == null) {
                    try b.exposed.append(b.gpa, q);
                }
            }
        }

        for (b.exposed.items) |q| {
            b.party.clearRetainingCapacity();
            try b.party.appendSlice(b.gpa, b.owners.items);
            for (b.lists.items) |l| try b.hosts(q, l.lhs);
            if (b.party.items.len > 0 and b.x.gr.declared(b.party.items)) return .declared;
        }

        b.party.clearRetainingCapacity();
        try b.party.appendSlice(b.gpa, b.owners.items);
        for (b.exposed.items) |q| {
            for (b.lists.items) |l| try b.hosts(q, l.lhs);
        }
        // Nobody the author wrote was visibly waiting: reachable only through
        // another synthesized rule, or from the frame itself. Name the list's
        // host so the report says something a reader can act on.
        if (b.party.items.len == 0) {
            for (b.lists.items) |l| try enrol(b.gpa, &b.party, b.x.gr.owner[l.lhs]);
        }
        return .residual;
    }

    /// The rules holding the dot before `list` in state `q`, added to the
    /// candidate party.
    ///
    /// Only rules the author wrote count. A list is left-recursive, so `L -> . L
    /// x` sits in the very state that expects it and would otherwise enrol the
    /// list's own naming host in every party it appears in — which is how C came
    /// back claiming `attributed_declarator` was confused with
    /// `attributed_statement`, when the whole conflict was one statement's
    /// attribute list deciding whether it was finished. A list expecting itself
    /// is not two rules being confused.
    fn hosts(b: *Bench, q: u32, list: g.Symbol) !void {
        for (try b.origin.of(b.gpa, b.x.gr, b.x.c.states[q].kernel)) |item| {
            if (item.prod == 0) continue;
            const p = b.x.gr.productions[item.prod];
            if (item.dot == p.rhs.len or p.rhs[item.dot] != list) continue;
            if (b.x.gr.isSynthetic(p.lhs)) continue;
            try enrol(b.gpa, &b.party, b.x.gr.owner[p.lhs]);
        }
    }
};

fn order(key: g.Symbol, item: g.Symbol) std.math.Order {
    return std.math.order(key, item);
}

/// Rungs 2 and 3: read against fold, by precedence and then by associativity.
const Ladder = struct {
    const Outcome = enum { read, fold, undecided };

    fn step(s: Survey, f: Folds) Outcome {
        // Unanimously stronger reads win; unanimously weaker ones lose. A state
        // holding interpretations on both sides of the fold has not been told
        // anything consistent, so precedence declines to answer.
        if (s.above and !s.below) return .read;
        if (s.below and !s.above) {
            // The exception that looks like a bug. One interpretation ties the
            // fold while another loses to it: the tying one is still standing,
            // and on its own a tie among right-associative folds means read on.
            // The losing interpretation must not be allowed to flip that tie
            // into a fold, because it coexists with the tying one rather than
            // replacing it.
            if (s.level and purely(f, .right)) return .read;
            return .fold;
        }
        // Precedence tied, or never spoke. Associativity is the author's answer
        // to exactly this, and only when the folds agree on it.
        //
        // Except that it was not asked this. A rule with an optional tail comes
        // out of the front end as two productions sharing a prefix, so the state
        // that has read the prefix holds the short one complete and the long one
        // with its dot before the tail - and the whole rule sits inside one
        // `prec.left`, so both carry the same rank and the tie is guaranteed.
        // Answering that tie with associativity denies the tail outright: elixir
        // loses every `do` block, because `defmodule Foo do` folds the call at
        // `do` in six states whose own items shift it.
        //
        // `decide` has already narrowed this to cells a merge over-permitted, and
        // the narrowing is what makes it safe. Unconditional, the same rule reads
        // on wherever a tail is optional and the terminal could also follow the
        // rule - the dangling-else shape - and it cost c 356 bytes, sql 368 and
        // verilog 1118 to gain elixir's 54.
        if (s.continues) return .read;
        if (purely(f, .left)) return .fold;
        if (purely(f, .right)) return .read;
        return .undecided;
    }

    /// Whether every surviving fold declared this associativity and no other.
    /// A single non-associative or contrary fold makes the group silent — which
    /// is the honest reading of `prec` without a side.
    fn purely(f: Folds, side: g.Assoc) bool {
        if (f.loose) return false;
        return switch (side) {
            .left => f.left and !f.right,
            .right => f.right and !f.left,
            .none => false,
        };
    }
};

const testing = std.testing;

/// A grammar that ranks nothing, for the tests whose subject is numbers. Every
/// comparison then falls to the numeric arm, which is what they are about.
///
/// Nine alike, because the tests below name productions by index and a tie now
/// reads the production it was offered to find its dynamic rank. An index has to
/// be a real one.
fn ungoverned(a: std.mem.Allocator) !g.Grammar {
    var b = g.Builder.init(a);
    defer b.deinit();
    const s = try b.intern("S", "S", null);
    for ([_][]const u8{ "a", "b", "c", "d", "e", "f", "g", "h", "i" }) |name| {
        const t = try b.intern(name, name, .{ .literal = name });
        try b.addProduction(s, &.{t}, &.{});
    }
    return b.finish("t", s, &.{}, &.{});
}

/// The same, with one production the author ranked below the rest.
fn ranking(a: std.mem.Allocator, at: usize, level: i16) !g.Grammar {
    var b = g.Builder.init(a);
    defer b.deinit();
    const s = try b.intern("S", "S", null);
    for ([_][]const u8{ "a", "b", "c", "d", "e", "f", "g", "h", "i" }, 0..) |name, i| {
        const t = try b.intern(name, name, .{ .literal = name });
        if (i == at) {
            try b.addProductionDynamic(s, &.{t}, &.{}, level);
        } else try b.addProduction(s, &.{t}, &.{});
    }
    return b.finish("t", s, &.{}, &.{});
}

fn ranked(level: i32, assoc: g.Assoc) g.Step {
    return .{ .prec = .{ .level = level }, .assoc = assoc };
}

test "a stronger fold erases a weaker one instead of tying with it" {
    var gr = try ungoverned(testing.allocator);
    defer gr.deinit();
    var f: Folds = .{};
    f.offer(&gr, 3, gr.start, ranked(1, .left));
    f.offer(&gr, 4, gr.start, ranked(5, .right));
    try testing.expect(!f.tied());
    try testing.expectEqual(@as(u30, 4), f.chosen.value);
    // The weaker reading leaves nothing behind, associativity included: it was
    // never a candidate, so its `left` must not colour the group.
    try testing.expect(!f.left);
    try testing.expect(f.right);

    // And offering the weak one afterwards changes nothing.
    f.offer(&gr, 3, gr.start, ranked(1, .left));
    try testing.expect(!f.tied());
    try testing.expect(!f.left);
}

test "a tie keeps the earlier production and remembers it was contested" {
    var gr = try ungoverned(testing.allocator);
    defer gr.deinit();
    var f: Folds = .{};
    f.offer(&gr, 7, gr.start, ranked(2, .none));
    f.offer(&gr, 5, gr.start, ranked(2, .none));
    try testing.expect(f.tied());
    try testing.expectEqual(@as(u30, 5), f.chosen.value);
    try testing.expectEqual(@as(u30, 7), f.rival.value);
}

test "a dynamic rank takes a tie ahead of the order they were written in" {
    // Production 5 is ranked below 7, so 7 becomes the reading the table takes
    // and 5 the rival - the reverse of the same tie ungoverned. Both survive
    // either way: `prec.dynamic` orders a fork, it does not resolve one.
    var gr = try ranking(testing.allocator, 5, -1);
    defer gr.deinit();
    var f: Folds = .{};
    f.offer(&gr, 7, gr.start, ranked(2, .none));
    f.offer(&gr, 5, gr.start, ranked(2, .none));
    try testing.expect(f.tied());
    try testing.expectEqual(@as(u30, 7), f.chosen.value);
    try testing.expectEqual(@as(u30, 5), f.rival.value);

    // And in the other offering order, since a rank is a property of the
    // production rather than of when it was reached.
    var later: Folds = .{};
    later.offer(&gr, 5, gr.start, ranked(2, .none));
    later.offer(&gr, 7, gr.start, ranked(2, .none));
    try testing.expectEqual(@as(u30, 7), later.chosen.value);
    try testing.expectEqual(@as(u30, 5), later.rival.value);
}

test "precedence decides before associativity, and unanimity is required" {
    const left: Folds = .{ .chosen = Action.reduce(1), .left = true };
    const right: Folds = .{ .chosen = Action.reduce(1), .right = true };

    try testing.expectEqual(Ladder.Outcome.read, Ladder.step(.{ .above = true }, left));
    try testing.expectEqual(Ladder.Outcome.fold, Ladder.step(.{ .below = true }, right));
    // Interpretations on both sides: precedence has been told two things and
    // says neither, so associativity gets the cell.
    try testing.expectEqual(
        Ladder.Outcome.fold,
        Ladder.step(.{ .above = true, .below = true }, left),
    );
    try testing.expectEqual(
        Ladder.Outcome.read,
        Ladder.step(.{ .above = true, .below = true }, right),
    );
}

test "a rule's own tail outranks associativity, and only inside its own tie" {
    const left: Folds = .{ .chosen = Action.reduce(1), .left = true };

    // The elixir shape: the fold and the read are one rule, `prec.left` wraps
    // the whole of it so the tie is guaranteed, and answering the tie by side
    // would deny the tail in every context at once.
    try testing.expectEqual(
        Ladder.Outcome.read,
        Ladder.step(.{ .level = true, .continues = true }, left),
    );
    // Precedence still speaks first. An author who ranked the tail below the
    // fold said so on purpose, and this rung never hears the cell.
    try testing.expectEqual(
        Ladder.Outcome.fold,
        Ladder.step(.{ .below = true, .continues = true }, left),
    );
}

test "a tying interpretation rescues right associativity from a losing one" {
    const right: Folds = .{ .chosen = Action.reduce(1), .right = true };
    const left: Folds = .{ .chosen = Action.reduce(1), .left = true };
    const mixed: Folds = .{ .chosen = Action.reduce(1), .right = true, .loose = true };

    // Below alone folds; below *with* a tie, against purely right-associative
    // folds, reads on instead.
    try testing.expectEqual(Ladder.Outcome.fold, Ladder.step(.{ .below = true }, right));
    try testing.expectEqual(
        Ladder.Outcome.read,
        Ladder.step(.{ .below = true, .level = true }, right),
    );
    // The rescue is specific to right associativity: left folds, and a group
    // that is not purely right folds too.
    try testing.expectEqual(
        Ladder.Outcome.fold,
        Ladder.step(.{ .below = true, .level = true }, left),
    );
    try testing.expectEqual(
        Ladder.Outcome.fold,
        Ladder.step(.{ .below = true, .level = true }, mixed),
    );
}

test "silence in either direction leaves the cell undecided" {
    const loose: Folds = .{ .chosen = Action.reduce(1), .loose = true };
    const both: Folds = .{ .chosen = Action.reduce(1), .left = true, .right = true };
    // No interpretation carried a precedence at all — every reading in the
    // state had its dot at the front — and the folds declared no side.
    try testing.expectEqual(Ladder.Outcome.undecided, Ladder.step(.{}, loose));
    try testing.expectEqual(Ladder.Outcome.undecided, Ladder.step(.{ .level = true }, both));
}

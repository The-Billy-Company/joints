//! The fixture the rungs are walked on: one state's row at a time, and the
//! scratch that makes doing it thirty thousand times affordable.
//!
//! Everything expensive about settling is here rather than in the rungs, because
//! the rungs are cheap and the *deciding when to consult them* is not. Reads and
//! folds are gathered first and compared only where they actually meet, so
//! re-deriving a state's readings — the one costly step — is paid once per state
//! that has a contest and not at all by the states that do not. On a real grammar
//! that is a few hundred states of tens of thousands.
//!
//! The scratch is the other half. Per-terminal `Folds` are a `memset` between
//! states rather than an allocation, and every recorded party accumulates into
//! one flat roll that is cut into slices at the end, because a per-conflict
//! allocation for a two-symbol set is most of an allocator call spent on nothing.

const std = @import("std");
const g = @import("../copy/grammar.zig");
const lr0 = @import("../cast/lr0.zig");
const attribution = @import("attribution.zig");
const column = @import("column.zig");
const ladder = @import("ladder.zig");
const settle = @import("settle.zig");

const Action = settle.Action;
const Case = settle.Case;
const Conflict = settle.Conflict;
const Folds = column.Folds;
const Frayed = settle.Frayed;
const Ladder = ladder.Ladder;
const Survey = ladder.Survey;

pub const Bench = struct {
    x: Case,
    gpa: std.mem.Allocator,
    action: []Action,
    /// Per-terminal scratch for the state being judged.
    folds: []Folds,
    closure: lr0.Closure,
    /// Rung 4, with its own reverse index and closure; see `attribution.zig`.
    who: attribution.Attribution,
    conflicts: std.ArrayList(Conflict) = .empty,
    frayed: std.ArrayList(Frayed) = .empty,
    /// Columns that need the second pass. Reused across states.
    contested: std.ArrayList(u32) = .empty,
    /// Scratch for `strands`: the fold chain being walked, and every state it
    /// has already stood on. Owned here so a per-cell walk allocates once.
    chain: std.ArrayList(u32) = .empty,
    walked: std.ArrayList(u32) = .empty,
    /// Every recorded conflict's party, end to end, and where each one sits.
    roll: std.ArrayList(g.Symbol) = .empty,
    cuts: std.ArrayList(struct { at: u32, len: u32 }) = .empty,
    /// The same, for the readings a cell dropped past the first — see
    /// `Conflict.rest`. A second run rather than a widening of `roll`, because
    /// the two hold different things and a cell has a party whether or not it
    /// dropped more than one reading.
    rest: std.ArrayList(Action) = .empty,
    spans: std.ArrayList(struct { at: u32, len: u32 }) = .empty,

    pub fn init(x: Case, gpa: std.mem.Allocator, action: []Action) !Bench {
        return .{
            .x = x,
            .gpa = gpa,
            .action = action,
            .folds = try gpa.alloc(Folds, x.width),
            .closure = try lr0.Closure.init(gpa, x.gr),
            .who = try attribution.Attribution.init(x, gpa),
        };
    }

    pub fn deinit(b: *Bench) void {
        b.gpa.free(b.folds);
        b.closure.deinit(b.gpa);
        b.who.deinit();
        b.conflicts.deinit(b.gpa);
        b.frayed.deinit(b.gpa);
        b.contested.deinit(b.gpa);
        b.chain.deinit(b.gpa);
        b.walked.deinit(b.gpa);
        b.roll.deinit(b.gpa);
        b.cuts.deinit(b.gpa);
        b.rest.deinit(b.gpa);
        b.spans.deinit(b.gpa);
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
    pub fn judge(b: *Bench, state: u32) !void {
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
        var survey = try b.poll(state, t, items, f, .all, frayed);

        // A rule's own tail only outranks its fold where the fold had no business
        // in this column: `frays` is true exactly when the lookahead admits the
        // terminal under the union over arrivals and not under the intersection,
        // so the permission is the merge's invention rather than the grammar's.
        //
        // And only where folding actually *loses* the tail. See `strands`.
        survey.continues = survey.continues and frayed and b.strands(state, t);

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
                _ = try b.who.of(state);
                try b.record(state, t, .shift_reduce, .repetition, r[t], f.chosen, &.{});
                if (frayed) try b.fray(state, t, .fold_dropped);
                return;
            }
            switch (Ladder.step(survey, f)) {
                .read => keep_fold = false,
                .fold => keep_read = false,
                .undecided => {},
            }
        }

        // The ladder folded, and the only thing that put the fold above the read
        // was an absent rank read as zero: every `below` in the survey came from
        // an authored level losing to nothing, and no reading outranked the
        // fold. That comparison may order the two and may not delete one, so the
        // cell is recorded below and the read is left standing for a fork.
        //
        // Read here rather than at the record, because the next line re-polls
        // and the second survey deliberately cannot see this: it asks only the
        // completed productions, and the whole question is what happened to an
        // in-progress reading. Recorded before the `standing <= 1` return, which
        // is what dropped these cells silently in the first place - a spared cell
        // has exactly one surviving action, so it never reached the recorder.
        //
        // And the same holds one rung down. `Ladder.sided` is the other arm
        // that deletes a reading on something nobody wrote about *this pair*:
        // precedence declined, and a side declared over the whole rule ordered
        // them. Ordering is all it may do - so that cell is recorded too, and
        // the read it lost is left for the parse to fork on.
        //
        // The two arms are kept apart rather than or-ed into one flag. They
        // spare for opposite reasons - one because nobody instructed the cell,
        // one in spite of an instruction that only ordered it - and a consumer
        // that cannot tell them apart cannot treat them differently. Read
        // before the re-poll below, which deliberately cannot see either.
        const nobody_ranked = survey.unwritten and !survey.grounded and !survey.above;
        const by_side = Ladder.sided(survey, f);
        const spared = !keep_read and reading and (nobody_ranked or by_side);

        // With the read eliminated, the in-progress readings are no longer party
        // to anything: what is left is a disagreement among completed
        // productions, and only those should be named in the report.
        if (!keep_read and reading) survey = try b.poll(state, t, items, f, .folds_only, frayed);

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

        // The survey knows something attribution cannot in one shape:
        // precedence spoke in neither direction, and at least one reading was
        // ordered below the fold *only* by an implied zero. Rung 4 reads which
        // rules were in the room, sees nobody's declaration over the pair and
        // answers `residual` - the one class a parse may not fork on. But a
        // defect is a cell nobody ranked, and somebody did rank this one; what
        // is missing is the other half of their comparison. `unwritten` is that
        // cell's name, and it keeps the reading the table passed over available
        // to the parse.
        const nobody = survey.unwritten and !survey.grounded and
            !survey.above and !survey.below;

        // Every reading that survived the ladder, so the recorder can name the
        // ones the cell had to pass over. A read that *lost* to precedence is
        // not in here: it was ordered out, not passed over, and offering it to
        // a parse would undo the author's ranking.
        const folds = f.standing();
        var alive: [folds.len + 1]Action = @splat(Action.err);
        @memcpy(alive[0..folds.len], &folds);
        if (keep_read or spared) alive[folds.len] = read;

        if (spared) {
            // `unwritten` only where nobody else has a claim. A spared cell whose
            // party is a group the author declared is already forkable and is
            // already attributed, and overwriting that would trade a real
            // provenance for a redundant one.
            const found = try b.who.of(state);
            // `nobody_ranked` first where both arms fired: a cell nobody
            // instructed is the weaker claim of the two, and naming it that
            // keeps every fork that had no authored side behaving as it did.
            const why: Conflict.Class = if (nobody_ranked) .unwritten else .sided;
            try b.record(
                state,
                t,
                .shift_reduce,
                if (found == .residual) why else found,
                r[t],
                read,
                &alive,
            );
            return;
        }
        if (standing <= 1) return;

        const kind: Conflict.Kind = if (keep_read) .shift_reduce else .reduce_reduce;
        const other = if (!keep_read) f.rival else if (yield) read else f.chosen;
        const found = try b.who.of(state);
        try b.record(
            state,
            t,
            kind,
            if (found == .residual and nobody) .unwritten else found,
            r[t],
            other,
            &alive,
        );
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

    /// `alive` is every reading that survived the ladder here, in any order and
    /// padded with `Action.err`. Whatever of it is neither `chosen` nor `other`
    /// becomes `Conflict.rest` — the readings a cell used to drop without
    /// leaving a trace that they had ever been on the table.
    fn record(
        b: *Bench,
        state: u32,
        terminal: u32,
        kind: Conflict.Kind,
        class: Conflict.Class,
        chosen: Action,
        other: Action,
        alive: []const Action,
    ) !void {
        const party = b.who.named();
        try b.cuts.append(b.gpa, .{
            .at = @intCast(b.roll.items.len),
            .len = @intCast(party.len),
        });
        try b.roll.appendSlice(b.gpa, party);

        const at: u32 = @intCast(b.rest.items.len);
        for (alive) |act| {
            if (act.none() or
                @as(u32, @bitCast(act)) == @as(u32, @bitCast(chosen)) or
                @as(u32, @bitCast(act)) == @as(u32, @bitCast(other))) continue;
            if (std.mem.indexOfScalar(u32, @ptrCast(b.rest.items[at..]), @bitCast(act)) != null) continue;
            try b.rest.append(b.gpa, act);
        }
        try b.spans.append(b.gpa, .{ .at = at, .len = @intCast(b.rest.items.len - at) });

        try b.conflicts.append(b.gpa, .{
            .state = state,
            .terminal = terminal,
            .kind = kind,
            .class = class,
            .chosen = chosen,
            .other = other,
            // Cut from the rolls once they have stopped moving; see `settle.all`.
            .party = &.{},
            .rest = &.{},
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
    ///
    /// `frayed` is the caller's answer to `frays`, and it reaches this far
    /// because whether the merge invented this column decides how much authority
    /// an *absent* rank carries; see the `.lt` arm.
    fn poll(
        b: *Bench,
        state: u32,
        t: u32,
        items: []const lr0.Item,
        f: Folds,
        who: Party,
        frayed: bool,
    ) !Survey {
        var out: Survey = .{};
        b.who.open();

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
                const rank = p.consumed(item.dot).prec;
                switch (b.x.gr.compare(rank, &.{p.lhs}, f.prec, f.speaks())) {
                    .gt => out.above = true,
                    // `compare` reads an absent level as zero, which is
                    // upstream's ordering and right wherever the grammar really
                    // admits this terminal. In a column the merge invented it is
                    // not: the fold is only standing here because the union of
                    // the arrivals put it here, so a rank nobody wrote must not
                    // outrank one the author did. Narrowing this arm to frayed
                    // cells is the same narrowing `decide` already applies to
                    // `continues`, for the same reason - and it is why the
                    // narrowing is safe, since an unranked fold at an implied
                    // zero still outranks a negative reading everywhere the
                    // grammar itself admits the token.
                    //
                    // Julia ranks `assignment` `prec.right(-2)` so that it binds
                    // loosest of anything. State 88 holds that rule's read of `=`
                    // beside an unranked `_expression -> _primary_expression`, so
                    // -2 lost to an implied 0, the ladder folded, `standing` came
                    // to 1 and the cell was never even recorded - no conflict, no
                    // fork, and every bare `x = 1` off the table in the language
                    // where that is the commonest statement there is.
                    //
                    // Measured 2026-08-05, one build apart with nothing else
                    // moved (rebuilt and re-measured either side to prove it):
                    // corpus rubble 30,374 -> 29,604, python 102 -> 0 and now
                    // whole, julia 6,423 -> 5,713 with its own table half clean.
                    // 23 of 30 grammars byte-identical; ruby pays 42 on a wall
                    // its external scanner owns. On the press's own numbers it is
                    // one-directional: frayed cells no partition can separate
                    // 235 -> 87, refused-token cells 2,191 -> 2,019, LR(0) states
                    // 109,527 -> 106,553. Julia's 21 `open` cells all close with
                    // its automaton unchanged at 1,175 states, which is the
                    // evidence that bucket was never waiting on another round.
                    .lt => if (!frayed or f.prec != .none or rank != .level) {
                        out.below = true;
                        if (f.prec == .none and rank == .level) out.unwritten = true else out.grounded = true;
                    } else {
                        // Declining the comparison is right and dropping the
                        // *reason* for declining is not. The fold must not
                        // delete this read - the merge invented its permission
                        // to be here - but the author did rank the read, and the
                        // only thing that could ever have ordered the two is a
                        // zero nobody wrote. That is precisely `unwritten`, so
                        // the mark is set without the `below` it normally
                        // travels with: no verdict is claimed, and the cell can
                        // still say why none was reached.
                        //
                        // Without it the survey comes back empty, the ladder is
                        // undecided, both actions stand - and `attribution`,
                        // seeing nobody's declaration over the pair, calls the
                        // cell `residual`, which `forks` refuses to offer. So
                        // the table reads on and nothing may ever explore the
                        // fold. Swift's whole residual census is one such cell:
                        // state 1401 on `{`, `call_expression` ranked -2 by
                        // `prec(-2)` against an unranked `_if_let_binding`, and
                        // it is every `if let x = y { … }` in the language.
                        out.unwritten = true;
                    },
                    .eq => out.level = true,
                }
                if (b.resumes(item, f)) out.continues = true;
            }

            if (out.sole) |s| {
                if (s != p.lhs) out.one_rule = false;
            } else out.sole = p.lhs;

            try b.who.note(p.lhs, p.rhs[0..item.dot]);
        }
        return out;
    }

    /// Whether folding this cell would leave the terminal with nowhere to go.
    ///
    /// `continues` reads on because an optional tail written as two productions
    /// stands the short one complete beside the long one's dot, and answering
    /// that tie by associativity denies the tail outright. That is the right
    /// answer wherever the fold *strands* the token — nothing above was waiting
    /// for it, so refusing the tail refuses the sentence, which is elixir's
    /// `defmodule Foo do`. It is the wrong answer wherever the token is exactly
    /// what an enclosing rule is holding a dot in front of: `defp f(x) do` folds
    /// the inner call and hands the `do` to the outer one, and the tail rung
    /// takes it for the inner call instead, which is the whole of elixir's
    /// `arguments`-where-the-oracle-says-`do_block`.
    ///
    /// So the walk: pop the handle, take the goto, and ask whether the state it
    /// lands in has an edge on `t` — chaining while the answer is another fold,
    /// because a unit rule pops straight into a second one. An *edge* is the
    /// question and not a row, because the row that would answer it belongs to a
    /// state this build has not judged yet; over-answering only says a reading
    /// exists somewhere above, which is exactly the claim being made.
    fn strands(b: *Bench, state: u32, t: u32) bool {
        b.chain.clearRetainingCapacity();
        b.walked.clearRetainingCapacity();
        // Out of memory answers the way the rung already behaved: strand it and
        // read on. A table that failed to allocate is not the place to change
        // what a language means.
        b.chain.append(b.gpa, state) catch return true;
        var head: usize = 0;
        while (head < b.chain.items.len) : (head += 1) {
            const s = b.chain.items[head];
            for (b.x.c.states[s].complete, 0..) |prod, k| {
                if (prod == 0) continue;
                if (!b.x.la.isSet(b.x.reduction_base[s] + k, t)) continue;
                const p = b.x.gr.productions[prod];
                const from = b.who.rev.back(b.gpa, s, p.rhs) catch return true;
                // `back` reuses one frontier, so the gotos are taken off it
                // before anything else is asked to unwind.
                const room = b.walked.items.len;
                for (from) |u| {
                    const q = b.x.c.goto(u, p.lhs) orelse continue;
                    if (std.mem.indexOfScalar(u32, b.walked.items, q) == null) {
                        b.walked.append(b.gpa, q) catch return true;
                    }
                }
                for (b.walked.items[room..]) |q| {
                    if (b.x.c.goto(q, t) != null) return false;
                    b.chain.append(b.gpa, q) catch return true;
                }
            }
        }
        return true;
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
};

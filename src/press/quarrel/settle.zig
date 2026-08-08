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
//!
//! **This file is the record and the entry point; the rungs are its siblings.**
//! One rung per file, which is the seam the list above already draws: `column`
//! is rung 1, `ladder` is rungs 2 and 3, `attribution` is rung 4, and `workbench` is
//! the fixture they are walked on. `forks` is the index a parse loop reads off a
//! finished verdict, which is not settling at all. What stays here is what the
//! rest of the press and the folio see — `Action`, `Conflict`, `Frayed`, `Tally`,
//! the `Case` that goes in, the `Verdict` that comes out — and `impose`'s
//! comptime ledger reaches `Conflict` and `Frayed` through this file by name, so
//! this is where they belong rather than one import further away.

const std = @import("std");
const first = @import("../cast/first.zig");
const g = @import("../copy/grammar.zig");
const lr0 = @import("../cast/lr0.zig");
const sets = @import("../cast/sets.zig");

// Every import here is named for the file it opens, including the two that used
// to read `rungs = @import("ladder.zig")` and `workbench = @import("bench.zig")`.
// A local alias that renames the module is a name a reader cannot grep back to a
// file, and a header sentence naming `ladder` while the code says `rungs` is drift
// with nothing to catch it.
const attribution = @import("attribution.zig");
const column = @import("column.zig");
const forks = @import("forks.zig");
const ladder = @import("ladder.zig");
const workbench = @import("workbench.zig");

pub const Attribution = attribution.Attribution;
pub const Bench = workbench.Bench;
pub const Folds = column.Folds;
pub const Forks = forks.Forks;
pub const Ladder = ladder.Ladder;
pub const Survey = ladder.Survey;

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

    pub fn none(a: Action) bool {
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
    /// The reading that lost, named first: the one a parse prefers when it
    /// explores the cell, and the one every report of this cell quotes.
    other: Action,
    /// The readings that lost *behind* `other`, and used to be dropped without
    /// a record that they existed.
    ///
    /// A cell answers once and a fork carries the answer it did not give — but
    /// an ambiguity is not always binary, and a cell that can name one loser
    /// caps what a parse may recover at two readings. C++ completes
    /// `_declarator`, `type_specifier` and `expression` on a bare identifier at
    /// once; both strands the runtime used to get were declarations, and the
    /// `expression` reading tree-sitter takes for `f(y);` was never on the
    /// table to be preferred or refuted. Nothing downstream of a cell can
    /// recover a reading the cell never carried.
    ///
    /// Empty for the great majority of cells, and empty for *every* cell of a
    /// grammar whose declared ambiguities are all two-way, which is why this
    /// changes no row that was not already three-deep.
    rest: []const Action,
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
        /// The author ranked the reading and nobody ranked the fold, so the
        /// only thing that ordered them was upstream reading an absent level as
        /// zero. Not a defect and not a declaration: the resolution is real and
        /// the table keeps it, but nobody wrote it, so the reading it passed
        /// over stays available to a fork rather than being erased. See
        /// `Survey.unwritten`.
        ///
        /// Last on purpose. `leaf.ConflictClass` is this enum written to disk
        /// by ordinal, so the two orders are the same order and a class may
        /// only ever be appended.
        unwritten,
        /// Precedence declined in both directions and a side the author
        /// declared over the *whole rule* ordered the pair. Like `unwritten` a
        /// real resolution the table keeps, and like `unwritten` not a
        /// statement that the reading it ordered second is wrong — so it forks
        /// too. See `Ladder.sided`.
        ///
        /// Split out of `unwritten` because the two are spared for opposite
        /// reasons and a consumer has to be able to tell them apart. Under
        /// `unwritten` nobody wrote the other half of the comparison, so the
        /// parse has no authored guidance and the spared reading is all it
        /// has. Under `sided` the author *did* speak about these rules; what
        /// they wrote orders the pair and stops there. Recording both as
        /// `unwritten` made a reading kept for want of any instruction
        /// indistinguishable from one kept in spite of an instruction, and
        /// verilog's `parameter` is what that cost: see the changelog fragment
        /// naming `[89368,89412)`.
        sided,
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
    /// Counted apart from `residual` because it is not a defect and apart from
    /// `declared` because nobody declared it: the number here is how often the
    /// press had to order two readings on an authority neither side wrote.
    unwritten: u32 = 0,
    /// The other spared class, counted apart for the same reason: how often an
    /// authored side was the only thing that ordered a pair. Not a defect
    /// either, but a cell where an instruction exists — which is what makes it
    /// answerable differently from `unwritten`.
    sided: u32 = 0,
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
        return t.repetition + t.declared + t.unwritten + t.residual.total();
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

    var b: Bench = try .init(x, gpa, action);
    defer b.deinit();

    for (0..x.c.states.len) |q| try b.judge(@intCast(q));

    // Parties accumulate into one flat run while judging, because a per-conflict
    // allocation for a two-symbol set is most of an allocator call spent on
    // nothing. They are cut into slices here, over arena memory the caller owns.
    const roll = try arena.dupe(g.Symbol, b.roll.items);
    const rest = try arena.dupe(Action, b.rest.items);
    const conflicts = try arena.dupe(Conflict, b.conflicts.items);
    for (conflicts, b.cuts.items, b.spans.items) |*k, cut, span| {
        k.party = roll[cut.at..][0..cut.len];
        k.rest = rest[span.at..][0..span.len];
    }
    return .{
        .action = action,
        .conflicts = conflicts,
        .frayed = try arena.dupe(Frayed, b.frayed.items),
    };
}

// All five siblings, not just the two that have inline tests today. This block
// is the only path from the test root into this directory, so a `test` added to
// `attribution`, `forks` or `workbench` would otherwise be collected by nothing
// and read exactly like a passing suite - the hazard `src/proof.zig` describes
// one level up. Naming a module with no tests costs nothing.
test {
    _ = attribution;
    _ = column;
    _ = forks;
    _ = ladder;
    _ = workbench;
}

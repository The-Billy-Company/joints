//! Rung 1: reduction against reduction, inside one column of one state.
//!
//! The first rung and the one most easily skipped, because precedence is usually
//! explained as ordering a fold against a *read*. Two folds meeting in the same
//! column are ordered by it too, and skipping that leaves every prec-ranked
//! alternative of one rule fighting its siblings forever.
//!
//! It is a column and not a cell on purpose. The comparison is not pairwise: a
//! reduction is offered to whatever has already survived here, and a stronger
//! one erases the weaker outright rather than tying with it, so what the rung
//! leaves behind is one winner, at most one rival worth reporting, and the
//! precedence and associativity of everything that survived. `Ladder` reads
//! exactly that summary and never the reductions themselves.

const std = @import("std");
const g = @import("../copy/grammar.zig");
const settle = @import("settle.zig");

const Action = settle.Action;

/// The reductions standing in one column, after they have been compared against
/// each other: the one the table will take, one rival named first in the report,
/// and every other survivor behind them.
///
/// The third one and beyond used to be dropped, on the reasoning that they
/// change nothing about the *verdict* — which is true, and is not what they are
/// for. A tied reduction is a reading the author sanctioned, and dropping it
/// means no parse can ever reach it: C++ completes `_declarator`,
/// `type_specifier` **and** `expression` on a bare identifier in state 2572, so
/// `f(y);` forked into two readings that were both declarations and the
/// expression tree-sitter builds was never a strand. `chosen` and `rival` keep
/// their exact former meanings, so the table and every report of it are what
/// they were; `spare` is what a fork may additionally explore.
pub const Folds = struct {
    chosen: Action = Action.err,
    rival: Action = Action.err,
    /// Survivors past `rival`, in the order they were offered.
    ///
    /// Inline and bounded for the same reason `rules` is — this is scratch for
    /// one column of one state, cleared by a `memset` between states. Past the
    /// bound a survivor is dropped, which is where this rung was for every
    /// reading past the second: a ceiling on how much of an ambiguity a parse
    /// can see, never on what the table does.
    ///
    /// `spares_max` is above the corpus rather than at it, and that gap is the
    /// whole point: a bound sitting exactly on the widest thing it has ever
    /// been shown is indistinguishable from one that has been truncating all
    /// along, because the number it reports is the number it can hold. The
    /// widest cell on the thirty-grammar corpus drops **6** readings (verilog,
    /// 89 cells), so a cell needs `chosen` plus six. `research/joinery/arity/
    /// arity.py` re-measures that and *fails* when the widest cell reaches the
    /// bound, so this stops being a silent ceiling the moment a grammar arrives
    /// that could test it.
    spare: [spares_max]Action = undefined,
    spares: u8 = 0,
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
    /// Whether any *surviving* reduction's side was written on the rule that
    /// folds here, rather than absorbed from a rule the press folded away.
    ///
    /// A fourth flag beside the three above and not a property of any one of
    /// them, because the question rung 3 asks is about the group: one fold that
    /// authored `left` is an author speaking, however many others merely
    /// inherited the same word on their way through an `inline` rule. Reset
    /// with the rest when a stronger reduction erases the column, for the same
    /// reason - a side that lost is not a side that was declared.
    authored: bool = false,

    pub fn empty(f: Folds) bool {
        return f.chosen.none();
    }

    /// The rules the surviving reductions speak for.
    pub fn speaks(f: *const Folds) []const g.Symbol {
        return f.rules[0..f.count];
    }

    /// Offer a reduction to the column, keeping the strongest.
    pub fn offer(f: *Folds, gr: *const g.Grammar, prod: u32, lhs: g.Symbol, step: g.Step) void {
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
                    f.hold(f.rival);
                    f.rival = f.chosen;
                    f.chosen = act;
                } else if (f.rival.none()) {
                    f.rival = act;
                } else f.hold(act);
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
        if (step.assoc != .none and !step.spliced) f.authored = true;
    }

    pub fn tied(f: Folds) bool {
        return !f.rival.none();
    }

    /// Remember one more survivor, if there is room and it is real.
    fn hold(f: *Folds, act: Action) void {
        if (act.none() or f.spares == f.spare.len) return;
        f.spare[f.spares] = act;
        f.spares += 1;
    }

    /// Every reduction still standing here, keenest first. Fixed width, so an
    /// empty slot reads as `Action.err` and a caller filters rather than
    /// counting.
    pub fn standing(f: *const Folds) [spares_max + 2]Action {
        var out: [spares_max + 2]Action = @splat(Action.err);
        out[0] = f.chosen;
        out[1] = f.rival;
        for (f.spare[0..f.spares], 2..) |act, i| out[i] = act;
        return out;
    }
};

/// How many tied reductions past `chosen` and `rival` one column keeps. Named
/// so the two places that must agree — the array and what `standing` returns —
/// cannot drift, and so shrinking it is an edit somebody made on purpose.
pub const spares_max = 8;

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

const testing = std.testing;

/// A grammar that ranks nothing, for the tests whose subject is numbers. Every
/// comparison then falls to the numeric arm, which is what they are about.
///
/// Nine alike, because the tests below name productions by index and a tie now
/// reads the production it was offered to find its dynamic rank. An index has to
/// be a real one.
pub fn ungoverned(a: std.mem.Allocator) !g.Grammar {
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
pub fn ranking(a: std.mem.Allocator, at: usize, level: i16) !g.Grammar {
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

pub fn ranked(level: i32, assoc: g.Assoc) g.Step {
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

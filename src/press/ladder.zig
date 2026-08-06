//! Rungs 2 and 3: read against fold, by precedence and then by associativity.
//!
//! The rung that decides most cells, and the only one whose input is a *poll*
//! rather than a comparison. Every interpretation standing in the state gets a
//! vote, because a state generally holds several items whose continuation could
//! begin with the contested token and they need not agree — so what arrives here
//! is `Survey`, a summary of what the state's readings said, and the answer is
//! one of three words.
//!
//! Apart from the bench that polls it because the two are different kinds of
//! thing. Polling reads the automaton, the lookahead matrix and FIRST, and can
//! allocate and fail; stepping the ladder is a pure function of two small values
//! with no allocator, no error set and no automaton, which is what lets its
//! exceptions be tested exhaustively by writing the survey down. Every exception
//! on this rung was found by a test that could name the survey it needed.

const std = @import("std");
const g = @import("grammar.zig");
const column = @import("column.zig");

const Folds = column.Folds;

/// What the readings standing in a state have to say about one contested cell.
pub const Survey = struct {
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
    /// A `below` that came from an *authored* comparison: either the fold
    /// carried a rank the author wrote, or the reading carried none. Upstream's
    /// ordering is speaking for somebody in both cases, so the ladder's verdict
    /// is the author's and the reading it drops is dropped for a reason.
    grounded: bool = false,
    /// A `below` that came from an explicit rank losing to an implied zero
    /// nobody wrote. The two travel together on purpose: a cell can hold one
    /// reading that lost on the author's own ordering and another that lost only
    /// to the implied zero, and only a cell where *every* loss was unwritten is
    /// one where nobody chose. Never set in a frayed cell, since the `.lt` arm
    /// drops those before they are counted.
    unwritten: bool = false,
    /// The one rule every reading belongs to, when there is one.
    sole: ?g.Symbol = null,
    one_rule: bool = true,
};

/// Rungs 2 and 3: read against fold, by precedence and then by associativity.
pub const Ladder = struct {
    pub const Outcome = enum { read, fold, undecided };

    pub fn step(s: Survey, f: Folds) Outcome {
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

    /// Whether `step` answered `.fold` on the associativity rung rather than on
    /// precedence — the readings said nothing consistent in either direction,
    /// none of them is the fold's own production continuing, and the folds
    /// declared left and only left.
    ///
    /// Asked by `bench.decide`, which has to tell two `.fold` verdicts apart
    /// that look identical from the outside. A fold that won on precedence won
    /// on a comparison the author wrote *about these two readings*; a fold that
    /// won here won on a side the author wrote about the rule as a whole, which
    /// orders the pair and was never a statement that the other reading is
    /// wrong. The first deletes a reading; the second should leave it standing
    /// for the parse to fork on.
    pub fn sided(s: Survey, f: Folds) bool {
        return s.above == s.below and !s.continues and purely(f, .left);
    }

    /// Whether every surviving fold declared this associativity and no other.
    /// A single non-associative or contrary fold makes the group silent — which
    /// is the honest reading of `prec` without a side.
    ///
    /// And nobody declared anything if every side in the group was **absorbed**
    /// rather than written. Folding an `inline` rule into its callers carries
    /// that rule's ranks along, so a caller that said nothing about
    /// associativity arrives at the table wearing the victim's side and is
    /// indistinguishable from one whose author chose it. Answering a tie on
    /// that side deletes a reading nobody ordered against anything, and does it
    /// silently: with the read gone `standing` comes to 1 and `decide` returns
    /// before the cell is ever recorded, so there is no conflict and no fork to
    /// find afterwards. Verilog's `clockvar` is `$.hierarchical_identifier` and
    /// nothing else; it inherits that rule's `prec.left(0)` and uses it to fold
    /// away the reading of `[` in every state after an identifier.
    ///
    /// Declining leaves the cell `.undecided`, which is the answer for a
    /// question the author never answered - both actions stand, the cell is
    /// recorded, and the parse forks. It is not the same repair as preferring
    /// the host's rank at the splice, which was measured and is worse.
    fn purely(f: Folds, side: g.Assoc) bool {
        if (f.loose or !f.authored) return false;
        return switch (side) {
            .left => f.left and !f.right,
            .right => f.right and !f.left,
            .none => false,
        };
    }
};

const testing = std.testing;
const Action = @import("settle.zig").Action;

test "precedence decides before associativity, and unanimity is required" {
    const left: Folds = .{ .chosen = Action.reduce(1), .left = true, .authored = true };
    const right: Folds = .{ .chosen = Action.reduce(1), .right = true, .authored = true };

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
    const left: Folds = .{ .chosen = Action.reduce(1), .left = true, .authored = true };

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
    const right: Folds = .{ .chosen = Action.reduce(1), .right = true, .authored = true };
    const left: Folds = .{ .chosen = Action.reduce(1), .left = true, .authored = true };
    const mixed: Folds = .{ .chosen = Action.reduce(1), .right = true, .loose = true, .authored = true };

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

test "a side nobody wrote here decides nothing, whichever side it is" {
    // Verilog's state 1184 written down. `clockvar -> _identifier .` is the
    // whole of `$.hierarchical_identifier`, so the `left` it folds on arrived
    // with that rule's body when the press substituted it away; no author ever
    // said a `clockvar` binds leftward against a select.
    const borrowed_left: Folds = .{ .chosen = Action.reduce(1), .left = true };
    const borrowed_right: Folds = .{ .chosen = Action.reduce(1), .right = true };
    const written_left: Folds = .{ .chosen = Action.reduce(1), .left = true, .authored = true };

    // The cell that deleted the `[`: a tie, and a side that came in through a
    // fold. Undecided is the honest answer, and it is the answer that keeps
    // both actions - so the cell is recorded and the parse forks, where before
    // `standing` came to 1 and nothing was written down at all.
    try testing.expectEqual(Ladder.Outcome.undecided, Ladder.step(.{ .level = true }, borrowed_left));
    try testing.expectEqual(Ladder.Outcome.undecided, Ladder.step(.{ .level = true }, borrowed_right));
    try testing.expectEqual(Ladder.Outcome.fold, Ladder.step(.{ .level = true }, written_left));

    // Both arms of the rung, and the rung-2 rescue that reads the same group:
    // a `below` saved from folding by a tie needs a right-associativity
    // somebody declared, not one a victim brought with it.
    try testing.expectEqual(
        Ladder.Outcome.fold,
        Ladder.step(.{ .below = true, .level = true }, borrowed_right),
    );

    // One authored side is enough for the whole group. An `inline` rule folded
    // into six callers is not six authors, and one caller that wrote `left`
    // itself is still an author speaking.
    const mixed: Folds = .{ .chosen = Action.reduce(1), .left = true, .authored = true };
    try testing.expectEqual(Ladder.Outcome.fold, Ladder.step(.{ .level = true }, mixed));

    // And precedence still speaks first: provenance is only consulted where the
    // rungs above it had nothing to say.
    try testing.expectEqual(Ladder.Outcome.read, Ladder.step(.{ .above = true }, borrowed_left));
    try testing.expectEqual(Ladder.Outcome.fold, Ladder.step(.{ .below = true }, borrowed_left));
}

test "silence in either direction leaves the cell undecided" {
    const loose: Folds = .{ .chosen = Action.reduce(1), .loose = true };
    const both: Folds = .{ .chosen = Action.reduce(1), .left = true, .right = true, .authored = true };
    // No interpretation carried a precedence at all — every reading in the
    // state had its dot at the front — and the folds declared no side.
    try testing.expectEqual(Ladder.Outcome.undecided, Ladder.step(.{}, loose));
    try testing.expectEqual(Ladder.Outcome.undecided, Ladder.step(.{ .level = true }, both));
}

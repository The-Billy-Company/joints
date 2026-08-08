//! M3, the spine: the monoid-annotated balanced tree every other monoid binds
//! to.
//!
//! A leaf holds one segment's effect; an internal node holds the product of its
//! children. That is the whole structure, and it is what turns the algebra into
//! a data structure: because the product is associative, re-bracketing is free,
//! so an edit re-multiplies the `O(log n)` nodes above the changed leaf and
//! nothing else. Tree-sitter cannot do this because a state must be recomputed
//! when its predecessor changes; a function need not.
//!
//! ## Generic over the monoid, and it cost nothing to be
//!
//! The tree is `Tree(M)` for any `M` carrying an element type, an identity, and
//! a partial `compose`. It is monomorphized per monoid, so `M.compose` is a
//! direct call the optimizer can inline; there is no vtable, no boxing, and no
//! branch that a version welded to `Effect` would not also have. Nothing was
//! traded away, so the question is only whether the generality is ever used, and
//! it already is - three times over:
//!
//! - **M1 wants the same tree.** A lexical element is a state-to-state map and
//!   composes exactly as associatively; folding it into the same structure is
//!   the whole economy argument of this package, which is that the four monoids
//!   are one implementation rather than four subsystems.
//! - **Recovery is a semiring parameter.** Weighted joint entries under the
//!   tropical semiring are a different `compose` over the same tree, which is
//!   only true if the tree does not know which one it is holding.
//! - **The element the product actually wants may not be one effect.** Rung 1's
//!   verdict is that rank does *not* converge to one; what stays bounded is the
//!   residue - the set of pairings the guards have not refuted. A spine over
//!   sets of effects is the same tree over a different `M`, and a concrete tree
//!   would have to be rewritten to find that out. It is the likeliest next
//!   instantiation, so hard-coding `Effect` today would be hard-coding the thing
//!   the measurement already says is not the final element.
//!
//! `Joint` below binds the real one, and exists partly to keep that honest: if
//! `effect.compose` ever drifts from the shape a monoid has, this file stops
//! compiling instead of the first parse stopping working.
//!
//! ## The second binding, which arrived
//!
//! This section used to say a second monoid would be a `pub const` beside
//! `Joint` and nothing else - no change to `tree.zig`, no parameter added
//! anywhere, no dispatch - and that the area needing one would arrive with a
//! real `compose` or not arrive. `Bp` below is that arrival, and the promise
//! held to the line: `tree.zig` and `arbor.zig` did not move for it, and the
//! whole binding is the same five declarations `Joint` is.
//!
//! What it cost to be right was one thing, and it was in the measure rather
//! than in the tree: `min` and `max` have to range over the *empty* prefix too,
//! or the identity holds on one side and not the other. See `Excess`.
//!
//! A third binding is still just a `pub const` here. Recovery weights already
//! have a folio section waiting for them - `folio.leaf.Kind.tariff`, see
//! `leaf.reserved` - so a weighted spine can be loaded rather than recomputed
//! per open, and neither half has to wait on the other to be designed.

const std = @import("std");
const tree = @import("tree.zig");
const joint = @import("../joint/joint.zig");

/// The structure. See `tree.zig` for what `M` has to declare.
pub const Tree = tree.Tree;
pub const Id = tree.Id;

/// M2 in the spine: a file's stack effect, maintained.
///
/// The binding is six lines because the joint already *is* a monoid with a
/// partial composition - `compose` returns null for a pairing no parse
/// produced, which the tree treats as an absorbing zero. Nothing is adapted and
/// nothing is wrapped.
pub const Joint = Tree(struct {
    pub const Element = joint.Effect;
    pub const Ctx = joint.Arena;
    pub const identity: Element = .identity;
    pub const compose = joint.compose;
    pub const eql = joint.Effect.eql;
});

/// M3's element: what one run of a parenthesis word does to the walk reading
/// it.
///
/// Serialize a tree depth-first over `(` and `)` and you have a ±1 walk, whose
/// excess after k parens is opens minus closes. Three numbers say everything a
/// later run needs to know about an earlier one - where it ended, how far down
/// it dipped, how far up it climbed - and that triple is Sadakane & Navarro's
/// range min-max measure. It is the whole of M3: `parent`, `firstChild`,
/// `subtreeSize`, `depth` and `lca` are each a search for a target excess over
/// this, not an operation of their own.
///
/// **`min` and `max` include the empty prefix**, which is why both bracket
/// zero, and it is the one decision here that is easy to get wrong. Measure
/// only the non-empty prefixes and `identity · w` still equals `w` while
/// `w · identity` does not - a law that survives every hand-written case and
/// dies on the first random one. `vellum/word_test.zig` draws its triples out
/// of real random words for that reason rather than asserting the law here.
///
/// Total, where the joint is partial: no two walks refuse to concatenate. The
/// tree already treats a monoid that never says no as its easy case, so nothing
/// is adapted for it.
pub const Excess = struct {
    /// Where the run ends, relative to where it started.
    total: i32 = 0,
    min: i32 = 0,
    max: i32 = 0,

    /// The empty word. Every field is zero, including the two that bracket the
    /// walk, because the empty prefix is a prefix.
    pub const identity: Excess = .{};

    /// `a` and then `b`, with `b`'s dips and climbs read from where `a` left
    /// off. That shift is the entire homomorphism.
    pub fn compose(_: void, a: Excess, b: Excess) !?Excess {
        return .{
            .total = a.total + b.total,
            .min = @min(a.min, a.total + b.min),
            .max = @max(a.max, a.total + b.max),
        };
    }

    pub fn eql(a: Excess, b: Excess) bool {
        return a.total == b.total and a.min == b.min and a.max == b.max;
    }

    /// One parenthesis, which is the generator every element is a product of.
    pub fn step(open: bool) Excess {
        return if (open) .{ .total = 1, .min = 0, .max = 1 } else .{ .total = -1, .min = -1, .max = 0 };
    }

    /// Whether a word measuring this denotes a forest: it returns to where it
    /// started and never goes below it. `min == 0` rather than `min >= 0`
    /// because the empty prefix already pins the maximum at zero.
    pub fn balanced(e: Excess) bool {
        return e.total == 0 and e.min == 0;
    }
};

/// M3 in the spine: a tree's parenthesis word, maintained under edits.
///
/// `Leaf.bytes` counts PARENTHESES here. The tree's addressing is a count of
/// whatever a leaf is made of and it never asked what that was, so a run of
/// parens is as good an extent as a run of source bytes - which is the claim
/// the generic was making all along, now with a second instance to check it
/// against. `kernel/vellum/word.zig` is what holds one, and its README says
/// what this buys over rebuilding the static sheet.
pub const Bp = Tree(struct {
    pub const Element = Excess;
    pub const Ctx = void;
    pub const identity: Element = Excess.identity;
    pub const compose = Excess.compose;
    pub const eql = Excess.eql;
});

test "the joint binds to the spine without an adapter" {
    // Compile-time only, deliberately: an element needs a grammar, an
    // automaton, and three interning pools to exist, so what is proved here is
    // that the seam fits. That it is *correct* is proved over toy monoids,
    // where a failure is about the tree rather than about the press.
    const Nothing = struct {
        pub fn mint(_: @This(), _: u32, _: u32) ![]const Joint.Leaf {
            return &.{};
        }
    };
    _ = &Joint.build;
    _ = &Joint.splice;
    _ = &Joint.replace;
    _ = &Joint.verify;
    _ = &struct {
        fn bind(s: *Joint, x: joint.Arena, cut: Joint.Cut) !?joint.Effect {
            return s.edit(x, cut, Nothing{});
        }
    }.bind;
}

test {
    _ = @import("toy.zig");
}

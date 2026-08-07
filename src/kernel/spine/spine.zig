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

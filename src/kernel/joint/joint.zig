//! M2, the joint: the door to the stack-effect monoid.
//!
//! Six files implement it and `README.md` says what each one is. This file says
//! which of it is anybody else's business, because until it existed the answer
//! was "all of it": six files, ninety-six public symbols, zero of them internal.
//! An area with no interior has no interface either - every consumer picked a
//! file out of the directory and reached for whatever was in it, so nothing here
//! could be moved or renamed without finding out afterwards who was holding it.
//!
//! What is published below is measured rather than chosen: a sweep for what files
//! outside this directory actually name, and nothing beyond it. Thirteen
//! declarations, against the ninety-six public symbols behind them. The rest were
//! never anyone's business; they just had no way of saying so.
//!
//! Two shapes, and the split is not arbitrary. A name that means one thing is
//! published flat - there is one `Effect` in this package and `joint.Effect` is
//! its name. A name that only means something qualified stays behind the module
//! that qualifies it: `Pool` is four different pools and `Id` is two different
//! handles, so `joint.roster.Pool` is not ceremony, it is the smallest spelling
//! that is still true.

const effect = @import("effect.zig");
const cursor = @import("cursor.zig");
const reverse = @import("reverse.zig");

/// One segment's worth of stack effect, and the arena the interned parts of it
/// live in. `cursor.zig` re-exports both under the same names; that was the
/// second door, and this is the first reason to have only one.
pub const Effect = effect.Effect;
pub const Arena = effect.Arena;

/// The monoid operation, partial: null is a pairing no parse produced, which is
/// the refutation the guards buy and not an error. `spine.Joint` binds it
/// directly, so a drift in its shape is a compile error there rather than a
/// wrong parse here.
pub const compose = effect.compose;

/// The two generators every element is built from. Everything a parse does to a
/// stack is one of these or a product of them.
pub const reduce = effect.reduce;
pub const shift = effect.shift;

/// Running a run of tokens into the elements it could be: scenarios over one
/// shared symbol stack, split only where the table says two of them genuinely
/// disagree.
pub const Cursor = cursor.Cursor;
pub const Fork = cursor.Fork;

/// The goto automaton read backwards, for the one question a segment's own
/// destination state cannot answer: what a pop below its base uncovered.
pub const Reverse = reverse.Reverse;

/// Where the measurement stops rather than guessing. Rung 1 found the failure
/// these bound (`README.md`, *The falsifier*), so they are surface for the
/// instrument that reports it, not knobs to tune until it passes.
pub const limb_ceiling = cursor.limb_ceiling;
pub const fan_ceiling = reverse.fan_ceiling;

/// The three interned columns, each behind its own name. Hash-consing is why
/// every question this layer asks is an integer comparison, and the pools are
/// where the interning lives - so a consumer that holds a parse holds these.
pub const stack = @import("stack.zig");
pub const roster = @import("roster.zig");
pub const ledger = @import("ledger.zig");

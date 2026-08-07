//! Incremental parsing built on composable stack effects.
//!
//! # This version is a name reservation, and exports nothing
//!
//! There is no API here yet - not a narrow one, not a provisional one. The
//! engine is written in Zig and reached through a C ABI (`libjnt`, with `jnt_`
//! symbols), and the Rust binding over it has not been written. Publishing an
//! empty `0.0.0` is the honest way to hold the name while that is true: a stub
//! that returned plausible values would be worse than nothing, because a
//! dependency that compiles is one somebody builds on.
//!
//! Depending on this crate today gets you this documentation. Nothing will
//! break when the binding lands, because there is no surface to break.
//!
//! # What the project is
//!
//! A parser generator and incremental parser that imports tree-sitter's own
//! `grammar.json`, so the grammars already written for the ecosystem are the
//! input rather than something to re-author. What it does differently is
//! algebraic: a parse step's effect on the stack is an element of a monoid, so
//! the effects of two adjacent regions compose into the effect of the whole
//! region. That single property is what buys the rest -
//!
//! - **position independence**: a region can be parsed without knowing what
//!   precedes it, because its effect is composed in afterward rather than
//!   inherited;
//! - **parallelism**: the file cuts into segments that parse independently and
//!   reduce pairwise;
//! - **incrementality**: an edit invalidates the segments it touches, and the
//!   surrounding composition is reused instead of re-derived;
//! - **one artifact**: N languages pack into a single mmap-able file, so a tool
//!   ships one binary and one file rather than a shared library per grammar.
//!
//! The claim that the composition really does reproduce a whole-file parse has
//! a falsifier that can be measured before a parser exists, and it was measured
//! first, across eleven real grammars. The repository carries that argument and
//! the numbers behind it, including the part where the kill condition as
//! originally written was not met.
//!
//! # Status, plainly
//!
//! Early. The generator, the scanner, the monoid, the balanced tree, the
//! concrete syntax tree with repair, the incremental reparse, the packed
//! artifact, the CLI, and the C ABI all exist and are tested. The SIMD first
//! pass, the query engine, the settled succinct encoding, and the size claim do
//! not. Source opens under <https://github.com/The-Billy-Company> alongside the
//! sibling packages.

// Deliberately empty. See the crate documentation above: there is no surface
// yet, and inventing one to make the file look inhabited is the mistake this
// version exists to avoid. No `#![forbid(unsafe_code)]` either, true as it is
// today - this crate's entire future is an `extern "C"` boundary, so a lint that
// has to be deleted in the next release is not worth the line. The unsafe
// discipline that will matter is already declared in `[lints]`.

//! vellum — the quire settled.
//!
//! A quire is the loose gathering of leaves before it is bound; vellum is what
//! it is bound onto. Same tree, different measure: where the quire spends
//! thirty-two bytes a node saying who holds whom, vellum writes the shape as
//! parentheses and reads parent, first child, next sibling, depth and subtree
//! size back out of the excess walk - under three bits a node, and `depth` and
//! `subtreeSize` stop being walks on the way past. What that costs is `parent`,
//! which is a load there and a range-min search here; the README prints the
//! whole trade rather than the half that wins.
//!
//! Two forms, and the difference between them is the honest part:
//!
//!   `Sheet`  the file at rest. Static, mmap-shaped, every query off immutable
//!            storage. An edit rebuilds it end to end.
//!   `Word`   the same parenthesis word on the spine over `Excess`, so an edit
//!            re-multiplies `O(log n)` branches instead. This is the second
//!            monoid `spine.zig` reserved a place for, and it is the same tree
//!            M2 hangs from.
//!
//! `README.md` has the measured size and speed tables, both directions, and
//! says which form is worth what.

const sheet = @import("sheet.zig");
const word = @import("word.zig");

pub const Sheet = sheet.Sheet;
pub const Spot = sheet.Spot;
pub const Ink = sheet.Ink;
pub const settle = sheet.settle;
pub const Error = sheet.Error;

pub const Word = word.Word;
pub const measure = word.measure;

test {
    _ = sheet;
    _ = word;
}

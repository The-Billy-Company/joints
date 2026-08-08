//! grain - what the bytes are shaped like, before any of them is a token.
//!
//! The lowest zone in the charter, and the only one that reads nothing of this
//! package at all. It is handed raw material and reports its structure: where
//! the lines are, how far in each one's content sits, and what is in the way.
//! Nothing here knows what a token is or what a grammar is, which is what lets
//! `lex` read it without anything pointing back.
//!
//! Two things are on offer and they are used at different moments:
//!
//!   * `lead` and `through` - the measurement itself, correct standing alone.
//!     `outside.layout` calls one per token; both are vectorized internally and
//!     neither needs setup.
//!   * `Ruling` - the per-line index that makes `lead` skip whole runs of blank
//!     and comment lines instead of walking them. Optional by construction:
//!     `lead` takes `?*Ruling` and answers identically either way, so a caller
//!     with no index loses speed and nothing else. `kernel/weave` builds one and
//!     splices it on every edit.
//!
//! See `README.md` for the invariant that makes the second of those spliceable,
//! and for what the lane brief asked for that is deliberately absent.

pub const sweep = @import("sweep.zig");

const ruling = @import("ruling.zig");
const measure = @import("measure.zig");

pub const Ruling = ruling.Ruling;
pub const Line = ruling.Line;
pub const Kind = ruling.Kind;
pub const Note = ruling.Note;
pub const Cut = ruling.Cut;
pub const tab_stop = ruling.tab_stop;

pub const Lead = measure.Lead;
pub const lead = measure.lead;
pub const through = measure.through;

test {
    _ = sweep;
    _ = ruling;
    _ = measure;
}

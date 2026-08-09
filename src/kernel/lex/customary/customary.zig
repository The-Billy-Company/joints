//! A scanner, as data.
//!
//! tree-sitter's answer to "this terminal needs memory" is a C function the
//! grammar links: `scanner.c`, opaque, per language, compiled into whatever binary
//! wants to parse that language. This directory is the other answer. A grammar's
//! scanner arrives here as a **customary** - one pressed program over a closed
//! algebra of typed memory organs, carried in the folio beside the parse table and
//! run by one interpreter that knows nothing about any language.
//!
//! The name is the old one for a book of a house's local practices, which is
//! exactly what a per-grammar scanner is, and it sits beside rubric, press, folio,
//! and quire.
//!
//! # Six files, and the split is the design
//!
//! | File | What it owns |
//! |---|---|
//! | `organs.zig` | the memory a customary may have, and nothing else: two stacks, a register bank, all fixed-capacity |
//! | `book.zig` | the bytes: the wire format, and the fail-closed reader that proves a section before anything runs it |
//! | `scribe.zig` | the one writer of those bytes, from a customary as somebody wrote it |
//! | `guard.zig` | whether a rule's tests hold at an offset - the reading half |
//! | `deed.zig` | what a rule's actions do when they do - the writing half |
//! | `engine.zig` | the control flow those four hang off: phases, one bounded pass, scoring without committing, the permission set |
//!
//! Nothing here reads anything above `kernel/lex`. Name resolution - which
//! terminal a book's `"_block_close"` *is* - is the one thing the interpreter
//! cannot do for itself, and it is handed in at `Engine.bind` as a resolver rather
//! than reached for as a grammar. That is what keeps the interpreter a function of
//! the book and not of the press.
//!
//! # Where it is asked
//!
//! One place: `outside.step`, before every hand, with the organs riding inside
//! `outside.Carry` so that beginning a file, comparing two lexical states, bounding
//! a zero-width answer, and snapshotting a fork are the four things they already
//! were. That is the whole integration, and it is why `Gather`'s saved state is
//! *exact* where tree-sitter's `serialize` is a capped, lossy 1024 bytes.

pub const book = @import("book.zig");
pub const deed = @import("deed.zig");
pub const guard = @import("guard.zig");
pub const scribe = @import("scribe.zig");

const engine = @import("engine.zig");
const organs = @import("organs.zig");

pub const Engine = engine.Engine;
pub const Ask = engine.Ask;
pub const Hit = engine.Hit;
pub const Error = engine.Error;
pub const reach_max = engine.reach_max;

pub const Organs = organs.Organs;
pub const Frame = organs.Frame;
pub const Mark = organs.Mark;
pub const Facts = organs.Facts;
pub const Symbol = organs.Symbol;
pub const facts = organs.facts;
pub const soak = organs.soak;

/// Compile a customary as written into the bytes a folio carries. The press-time
/// half of the story; `Engine.bind` is the load-time half.
pub const press = scribe.press;
pub const Note = scribe.Note;

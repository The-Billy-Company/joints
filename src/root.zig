//! outliner — parsing as algebra.
//!
//! Tree-sitter treats a grammar as a program to generate. outliner treats it as
//! a monoid presentation to evaluate, which is why a grammar here becomes a
//! file rather than a shared library. The consequences — position-independent
//! incremental reparse, parallel parse as a prefix scan, GLR paid only where an
//! element is genuinely multi-valued, and recovery as a semiring parameter —
//! are all one implementation rather than four subsystems.
//!
//! Package shape, mirroring the sibling packages' three layers:
//!
//!   press/    — build time: a grammar in, tables out. The front end, the LR
//!               construction, and eventually the quotient and the folio writer.
//!   kernel/   — run time: pure compute over bytes and tables, no I/O.
//!   surface/  — the CLI and the C ABI (`libotl`, `otl_*`).
//!
//! Nothing here is stable. The package exists to answer one question first —
//! whether stack effects converge (`research/joinery/TESTING.md`, rung 1) — and
//! the shape above is what that measurement needs, not a finished design.

const std = @import("std");

/// Build time: a grammar becomes tables.
pub const press = struct {
    /// The IR every front end lowers to and the LR construction reads.
    pub const grammar = @import("press/grammar.zig");
    /// The tree-sitter front end. The whole go-to-market: three hundred
    /// maintained grammars are imported, never rewritten.
    pub const import = @import("press/import.zig");
    /// Flattening a token rule tree down to the one regex the lexer compiles.
    pub const lexeme = @import("press/lexeme.zig");
};

test {
    std.testing.refAllDecls(@This());
    _ = @import("press/grammar.zig");
    _ = @import("press/import.zig");
    _ = @import("press/lexeme.zig");
}

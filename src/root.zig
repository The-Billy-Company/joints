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
//!   folio/    — the artifact between them: tables as bytes, both ways.
//!   surface/  — the CLI and the C ABI (`libotl`, `otl_*`).
//!
//! Nothing here is stable. The package exists to answer one question first —
//! whether stack effects converge (`research/joinery/TESTING.md`, rung 1) — and
//! the shape above is what that measurement needs, not a finished design.

const std = @import("std");

/// Build time: a grammar becomes tables.
pub const press = struct {
    /// A grammar in, an automaton and its table out. Build tables through this
    /// rather than pairing `lr0` with `lalr` by hand: it owns the unfolding
    /// that an LALR merge artifact needs, and nothing else does.
    pub const tables = @import("press/press.zig").tables;
    /// What `tables` hands back. Exported because a caller that can get one and
    /// cannot name one has to reach for `anytype`, which trades the type check
    /// away at exactly the seam — the CLI, the folio writer — where the tables
    /// stop being this package's private business.
    pub const Result = @import("press/press.zig").Result;
    pub const setTrace = @import("press/press.zig").setTrace;
    pub const setGrowth = @import("press/press.zig").setGrowth;
    /// The IR every front end lowers to and the LR construction reads.
    pub const grammar = @import("press/grammar.zig");
    /// The tree-sitter front end. The whole go-to-market: three hundred
    /// maintained grammars are imported, never rewritten.
    pub const import = @import("press/import.zig");
    /// Flattening a token rule tree down to the one regex the lexer compiles.
    pub const lexeme = @import("press/lexeme.zig");
    /// Substituting a nonterminal away into the productions that use it.
    pub const fold = @import("press/fold.zig");
    /// LALR(1) lookaheads and the action table they decide.
    pub const lalr = @import("press/lalr.zig");
    /// Which reading wins a cell two of them want: precedence, associativity,
    /// and the attribution of whatever neither settles.
    pub const settle = @import("press/settle.zig");
    /// The LR(0) canonical collection — the automaton's shape, no lookahead.
    pub const lr0 = @import("press/lr0.zig");
    /// The automaton read backwards, for the questions about a fold's origin
    /// that its destination state cannot answer.
    pub const retrace = @import("press/retrace.zig");
    /// Nullability and FIRST, over the whole symbol space.
    pub const first = @import("press/first.zig");
    /// Equal-width bit sets in one buffer, the currency of set fixpoints.
    pub const sets = @import("press/sets.zig");
};

/// Run time: pure compute over bytes and tables, no I/O.
pub const kernel = struct {
    /// M1 — the terminal scanner: a grammar's terminals as one anchored
    /// longest-match slate over irregex, plus the tie-break that is a fact
    /// about the language rather than about automata.
    pub const lex = struct {
        pub const scanner = @import("kernel/lex/scanner.zig");
    };
    /// M2 — the stack-effect monoid, the algebra a parse is folded in.
    pub const joint = struct {
        pub const effect = @import("kernel/joint/effect.zig");
        /// Hash-consed persistent columns, and the one over grammar symbols.
        pub const stack = @import("kernel/joint/stack.zig");
        /// Hash-consed sets of states — one claim an effect makes about what was
        /// standing under the part of the stack it popped away.
        pub const roster = @import("kernel/joint/roster.zig");
        /// All of those claims at once, one per popped depth. The guard.
        pub const ledger = @import("kernel/joint/ledger.zig");
        /// The goto automaton backwards: what a pop below a segment's own base
        /// could have exposed.
        pub const reverse = @import("kernel/joint/reverse.zig");
        /// Running a segment against the tables to get one monoid element.
        pub const cursor = @import("kernel/joint/cursor.zig");
    };
    /// The ordinary left-to-right parse — the oracle every claim about
    /// composing segments is checked against, and the only honest source of a
    /// token stream for a grammar with context-dependent terminals.
    pub const walk = struct {
        pub const drive = @import("kernel/walk/drive.zig");
    };
    /// M3 — the monoid-annotated balanced tree the joints hang from, which is
    /// what makes an edit cost `O(log n)` regardless of where it landed. One
    /// entry point per subpackage from here down: a subpackage re-exports its
    /// own parts, so growing one is not an edit to this file.
    pub const spine = @import("kernel/spine/spine.zig");
    /// The live editable tree a parse yields, and eventually vellum, its
    /// settled succinct encoding.
    pub const quire = @import("kernel/quire/quire.zig");
    /// A file held open: the spine and the quire maintained together across an
    /// edit, which is the only place the two halves of the claim meet.
    pub const weave = @import("kernel/weave/weave.zig");
};

/// The artifact: a pressed grammar as bytes, mmap-able, versioned, checked.
pub const folio = @import("folio/folio.zig");

test {
    std.testing.refAllDecls(@This());
    _ = @import("kernel/lex/scanner.zig");
    _ = @import("kernel/lex/scanner_test.zig");
    _ = @import("kernel/joint/effect.zig");
    _ = @import("kernel/joint/stack.zig");
    _ = @import("kernel/joint/roster.zig");
    _ = @import("kernel/joint/ledger.zig");
    _ = @import("kernel/joint/reverse.zig");
    _ = @import("kernel/joint/cursor.zig");
    _ = @import("kernel/walk/drive.zig");
    _ = @import("kernel/spine/spine.zig");
    _ = @import("kernel/quire/quire.zig");
    _ = @import("kernel/weave/weave.zig");
    _ = @import("folio/folio.zig");
    _ = @import("press/press.zig");
    _ = @import("press/grammar.zig");
    _ = @import("press/import.zig");
    _ = @import("press/lexeme.zig");
    _ = @import("press/fold.zig");
    _ = @import("press/lalr.zig");
    _ = @import("press/settle.zig");
    _ = @import("press/lr0.zig");
    _ = @import("press/retrace.zig");
    _ = @import("press/first.zig");
    _ = @import("press/sets.zig");
}

//! joints — parsing as algebra.
//!
//! Tree-sitter treats a grammar as a program to generate. joints treats it as
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
//!   surface/  — the CLI and the C ABI (`libjnt`, `jnt_*`).
//!
//! Nothing here is stable. The package exists to answer one question first —
//! whether stack effects converge (`research/joinery/TESTING.md`, rung 1) — and
//! the shape above is what that measurement needs, not a finished design.

const irregex = @import("irregex");

/// Who joints is when it speaks. The engine underneath is embeddable and four
/// programs already ride it, so a diagnostic used to open with the name of the
/// binary that happened to be first — `gist:` — and its knobs lived in `GIST_*`.
/// Declaring this here is how the whole package signs its own name instead, and
/// it is read at comptime, so a knob is still a string literal by the time
/// `getenv` sees it.
pub const irgx_brand: irregex.Brand = .{
    .name = "joints",
    .env_prefix = "JOINTS_",
    .artifact_dir = ".joints",
};

/// What joints has to say through `JOINTS_TRACE`, one lens per subsystem
/// above — so the vocabulary is the package's own shape rather than a list that
/// drifts from it. Dark by default; `JOINTS_TRACE=press,joint` lights two, and
/// `all` adds the engine's own lenses underneath for a question that turns out
/// to be irregex's.
///
/// This is the half of the identity a brand alone could not give us: the engine
/// names its phases (`warm`, `reconcile`, `walk`), and none of those are ours.
/// The two sets are welded into one enum on the way in, which is why a call site
/// writes `assay.trace(.press, …)` without knowing which half it named — and why
/// re-spelling an engine lens here is a compile error rather than a lens that
/// silently never lights.
pub const irgx_lenses = enum { press, lex, joint, weave, folio, quire };

/// Time, counters, and the one diagnostic channel, re-exported so the face
/// reaches instrumentation through the package it already imports. Every emit
/// routes through a thread-local sink, which is what will let `libjnt` hold its
/// never-writes-your-stderr contract by construction rather than by audit.
pub const assay = irregex.assay;

/// Build time: a grammar becomes tables. `press.zig` publishes the IR - the
/// twenty-five names that cross that directory's boundary - so this file names
/// one door where it used to re-export thirteen submodules and leave the other
/// hundred and fifty public symbols reachable by accident.
pub const press = @import("press/press.zig");

/// Run time: pure compute over bytes and tables, no I/O.
pub const kernel = struct {
    /// M0 — the material itself: one vectorized pass over raw bytes reporting
    /// where the lines and the indents are, before anything is a token. Read by
    /// `lex`, and it reads nothing of this package back.
    pub const grain = @import("kernel/grain/grain.zig");
    /// M1 — the terminal scanner: a grammar's terminals as one anchored
    /// longest-match slate over irregex, plus the tie-break that is a fact
    /// about the language rather than about automata.
    pub const lex = struct {
        pub const scanner = @import("kernel/lex/scanner.zig");
        /// The other half of a terminal scanner, for the grammars whose lexer is
        /// not a function of the bytes in front of it: a per-grammar program over
        /// typed memory organs, pressed into the folio and run by one engine. Its
        /// own door beside `scanner` rather than a name re-exported from it,
        /// because the press-time half (`press`, `book`) has no scanner in the
        /// room yet and the mint verb is its caller.
        pub const customary = @import("kernel/lex/customary/customary.zig");
    };
    /// M2 — the stack-effect monoid, the algebra a parse is folded in. Six
    /// files behind one door: `joint.zig` publishes the fourteen names that
    /// cross the boundary and keeps the other eighty-two to itself.
    pub const joint = @import("kernel/joint/joint.zig");
    /// The ordinary left-to-right parse — the oracle every claim about
    /// composing segments is checked against, and the only honest source of a
    /// token stream for a grammar with context-dependent terminals. One file, so
    /// the file is the door.
    pub const walk = @import("kernel/walk/drive.zig");
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
    /// The quire settled: the same tree as a balanced-parenthesis word, static
    /// for a file at rest and on the spine for one being typed into. M3's
    /// second measure, and the second monoid the spine holds.
    pub const vellum = @import("kernel/vellum/vellum.zig");
    /// The query front end: a `.scm` file compiled against a grammar and
    /// pressed into the folio, so a `highlights.scm` is parsed once at mint
    /// rather than once per process. Running one against a tree is not here.
    pub const gloss = @import("kernel/gloss/gloss.zig");
};

/// The artifact: a pressed grammar as bytes, mmap-able, versioned, checked.
pub const folio = @import("folio/folio.zig");

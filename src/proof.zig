//! The test build's root, and nothing else's root. e2
//!
//! `zig build test` collects only the tests reachable from its root module's
//! own files. While `src/root.zig` was that root, the only way to reach a
//! `*_test.zig` was for production code to import it, so each area's module
//! root imported its own tests — and those tests then read downstream, because
//! a parser generator is only worth testing against the thing it generates for:
//! `press/carry_test.zig` drives a real grammar through `folio`,
//! `census_test.zig` through `quire` and `walk`. That made
//! `folio -> press/press.zig -> press/carry_test.zig -> folio` a real cycle
//! across five directories, over an arrow that was never in the program.
//!
//! So the tests get their own root, and every arrow that used to close the loop
//! starts here instead. Nothing imports this file, so a test file is now a leaf,
//! and a leaf cannot be on a round trip. Production imports production; a test
//! reaches wherever the test needs to reach.
//!
//! Both lists below are named file by file rather than pulled in through
//! `root.zig`. The facade re-exports the whole module, so importing it from
//! inside the module closes a cycle over everything — `charter.zone`
//! forbids that import outright, and a test root is not the exception, because
//! it is the one file with no reason to need a facade: it wants the parts.
//!
//! The hazard this trades for: a file that exists and is not named below is not
//! compiled by the test build, and a suite that quietly shrank reads exactly
//! like a green run — the same hazard `build.zig` warns about where it explains
//! why the library gets its own compilation. `tool/roll.py` is the gate that
//! refuses it.
//!
//! Its sibling `idiom.zig` is the other test root, and exists for a reason worth
//! knowing before you add a package-wide proof here: reaching a module's decls by
//! name forces Zig to analyse them, which costs 3.4 s and cannot be filtered away,
//! so a reflection walk in *this* file would have put that on
//! `zig build test -Dtest-filter=<what you touched>` - the loop that is meant to
//! answer in a tenth of a second.

// The production modules, so the tests written inline beside the code they
// check are collected. Each area root pulls in its own parts, so a new file
// under `press/` is `press.zig`'s business and not this file's; what has to be
// listed here is one entry point per area.
test {
    _ = @import("kernel/lex/scanner.zig");
    _ = @import("kernel/joint/effect.zig");
    _ = @import("kernel/joint/stack.zig");
    _ = @import("kernel/joint/roster.zig");
    _ = @import("kernel/joint/ledger.zig");
    _ = @import("kernel/joint/reverse.zig");
    _ = @import("kernel/joint/cursor.zig");
    _ = @import("kernel/spine/spine.zig");
    _ = @import("kernel/quire/quire.zig");
    _ = @import("kernel/weave/weave.zig");
    _ = @import("folio/folio.zig");
    _ = @import("press/press.zig");
    _ = @import("press/copy/grammar.zig");
    _ = @import("press/copy/import.zig");
    _ = @import("press/copy/lexeme.zig");
    _ = @import("press/copy/fold.zig");
    _ = @import("press/lalr.zig");
    _ = @import("press/quarrel/settle.zig");
    _ = @import("press/cast/lr0.zig");
    _ = @import("press/cast/retrace.zig");
    _ = @import("press/cast/first.zig");
    _ = @import("press/cast/sets.zig");
}

// The `*_test.zig` files, which live beside what they test and are reached only
// from here. Grouped by area, in the order the facade presents them.
test {
    _ = @import("kernel/lex/lexicon_test.zig");
    _ = @import("kernel/lex/scanner_test.zig");
    _ = @import("kernel/walk/drive_test.zig");
    _ = @import("kernel/spine/tree_test.zig");
    _ = @import("kernel/spine/stream_test.zig");
    _ = @import("kernel/quire/gather_test.zig");
    _ = @import("kernel/quire/survey_test.zig");
    _ = @import("kernel/weave/amend_test.zig");
    _ = @import("folio/folio_test.zig");
    _ = @import("press/copy/import_test.zig");
    // What this one protects is a press invariant: the IR `press.zig` computes
    // has to arrive at a parse intact, and the folio is the only place it can
    // quietly not — which is why it reads downstream of its own directory.
    _ = @import("press/docket/carry_test.zig");
    // The census over a verdict list, which `zig build census` narrows to. Also
    // inert without its request file, so being in the suite costs a no-op.
    _ = @import("press/docket/census_test.zig");
    // An instrument rather than an assertion: it answers "which cell decided
    // this" over a real grammar, and returns immediately unless asked.
    _ = @import("press/wall_test.zig");
}

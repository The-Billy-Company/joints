# Rust integration tests

These tests link the real, separately built `libjnt` and open the JSON grammar
in `json.json`. The fixture copies the repository's pinned
`test/grammar/json.json`, so a packaged crate retains the same real grammar
without reaching outside its own package. Keep the two byte-identical when
updating the grammar pin.

The cases exercise traversal, byte positions, strict parse refusal and exact
repair spans, nested capture enumeration, predicates, parser identity, and
independent workers. Owned parsers return from a factory and retain earlier
trees and captures across a valid/refused/valid parse sequence. Crate
documentation adds compile-fail examples for borrowed and owned parser lifetimes
and thread confinement. Run `cargo test` after `zig build` from the
repository root, or point `JOINTS_LIB_DIR` at an existing native build.

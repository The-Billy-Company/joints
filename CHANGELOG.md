# Changelog

Release notes describe the supported public interfaces. Research measurements
remain attached to their original sources and binaries in the dossiers.

<!-- towncrier release notes start -->

## [0.1.0] - 2026-10-03

First experimental release of the Joints parsing engine and its Python and
Rust bindings. Grammar tables are data read by one native engine. This release
requires a separately supplied, target-matching `libjnt` with ABI 2.

### Added

- Import tree-sitter `grammar.json` into a folio, or combine grammars in a
  codex. Compile and inspect these artifacts through the Joints CLI.
- Parse source, traverse nodes, and run structural queries in process through
  the C ABI, Python, and Rust. Nodes retain original source bytes, byte spans,
  fields, parentage, and byte-based positions.
- Expose incremental editing through the CLI and C weave API. Python and Rust
  currently expose immutable trees.
- Require accepted, sound, single-root, unrepaired parses in the strict
  bindings. Diagnostic parsing retains partial forests and deletion/insertion
  evidence. Unsupported query constructs and foreign predicates can refuse
  explicitly instead of returning incomplete successful results.
- Keep native owners and dependent handles within their lifetimes and threads.
  Rust parsers can borrow or own a grammar bank; workers can retain an owned
  parser inside their thread.
- Provide separate native archives for Linux x86_64 and macOS arm64, containing
  the CLI, shared and static libraries, C header, JSON grammar fixture,
  licenses, and a source/file integrity manifest. The native archives are tested
  on Ubuntu 24.04 (glibc 2.39) and macOS 14. Python wheel/sdist and Rust crate
  packages contain their interfaces, with no native library bundled.

### Reliability and validation

- Repair lexer, layout, format-string, wrapper, reduction-fork, and query-alias
  cases exposed by native consumers. Nested queries retain every matching
  assignment and preserve capture ordering.
- Pin grammar inputs and their bytes, validate structural soundness, and retain
  source identity for comparisons. Historical measurements continue to name
  the particular source and oracle they describe.
- Exercise installed Python packages on the declared Python 3.12 floor and
  packaged Rust code on Rust 1.85, including real native parsing, queries,
  malformed-input refusal, parser reuse, and owner/thread controls.
- Gate publication on the exact commit's `release-ready` result, version
  parity, main ancestry, folded notes, and successful builds of every channel.
  Probe registries before uploading and verify published artifact bytes and
  native behavior before finalizing the GitHub release.

### Scope and limitations

The bindings are experimental. Language and scanner coverage varies with the
pinned grammar, and query support covers a subset of tree-sitter notation.
Consumer finding parity does not imply universal tree/query equivalence or a
performance guarantee. A successful CLI parse may include repairs; use the
strict binding contract when recovery must not count as understood source.

This first release consolidates the accumulated development fragments into
curated product notes. The complete source-qualified development record is
preserved at the
[pre-release commit](https://github.com/The-Billy-Company/joints/tree/d20f7e95dc73fb726b272bed32a591e9010ed037/changelog.d)
and in the research dossiers; its historical figures are not current support
or benchmark promises.

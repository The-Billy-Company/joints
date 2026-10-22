# Working specimen reference

These 66 recordings use the same private Zig executable as the first JSON
reference, SHA-256
`709bf8c0ce4a3c9ad5deb400e42d5025439e76c45bbcfaaf0959be31cff768ec`.
The manifest records each grammar, source, scanner book, assertion file, raw
output, command, exit code, and strict verdict. The source population is the
existing working specimens under `research/joinery/specimen`; the sealed
`holdout/vendor` population was not inspected.

Reconstruct after completing the original reference freeze and fetching the
pinned grammars:

```sh
mise exec zig@0.16.0 python@3.12.15 -- python3 tool/capture_migration_specimens.py --reference .local/rust-migration/reference-verified --out OUTPUT
```

The recorder refuses an existing output directory, validates the frozen binary,
and brackets the capture with binary and input hashes. Raw outputs preserve LR
state numbers and arena occupancy for investigation.

The desired assertions remain unchanged. The reference fails some assertions
in five specimens: Bash regex in a test command, an erroneous HTML closing tag,
Kotlin's greedy close and unterminated string, and PHP heredoc. These are
existing defects, not automatically migration regressions. The Rust gate must
preserve previously held claims, report improvements and outstanding desired
claims separately, and compare exact published trees on strict reference
cases. It must also retain first-stop and repair evidence on refused cases.
Internal state numbering and speculative arena occupancy are excluded from
semantic equality, as specified in [the design](../../../RUST_DESIGN.md).

# Private Rust migration profiles

The [Python projection patch](adapters/python-projection-v3.patch) contains
four narrowly scoped consumer production corrections against the exact source
hashes in its [lineage record](adapters/python-projection-lineage.json).
It handles bare generator arguments, decorator collector scope scheduling,
semantic statement ends, parenthesized `with` lists, handler references,
chained assignments, and conditional context-manager bindings. It also corrects a
separately verified Ruff 0.0.7 reference-visitor defect that visited `elif`
conditions twice. The native projection keeps one visit; the portable
projection has an `If`-only override with independent exact-count tests.

The [68 authored controls](adapters/python-projection-controls.json) retain
counterexamples for comments, delimiters, real tuple values, shadowing, and
reference multiplicity. They and eight unchanged real-source representatives
pass the private diagnostic, as do all 166 residual real-source cases and all
64 original default consumer tests. Lambda parameter bindings and imports are
excluded from expression references; default-value and body uses remain included.
Original assertions, policies, grammar profiles, corpus bytes, and the complete
failed baseline remain preserved. Complete governed qualification is still
required on the final Rust candidate. This patch is not applied to the live
consumer and does not select a new default.

`grammar/python314-rust-v2.json` is an explicit candidate derived from
Regulator's `regulator-python314-v1` recipe. It leaves all 30 authored rule
changes intact and adds two exact conflict groups independently requested by
Tree-sitter 0.26.11:

1. `primary_expression`, `_default_primary_expression`, `list_splat_pattern`
   after `return * identifier` before `.`.
2. `_default_primary_expression`, `list_splat_pattern` after `return * print`
   before `,`, exposed after declaring the first group.

The original recipe fails generation. The intermediate three-party-only recipe
also fails. This candidate generates successfully; the raw diagnostics and
their hashes are retained in `evidence/` and `lineage.json`. Generation alone
does not establish Regulator compatibility.

The exact upstream base is the pinned Python grammar at commit
`26855eabccb19c6abf499fbc5b8dc7cc9ab8bc64`, SHA-256
`d933cfea6197e57354c9ec86888adbb95971b4372efef514b82e601b5067580d`.
The candidate derived grammar is SHA-256
`c901af1e95bfb72287491a32af098067262a194ecc123599fa512ed1c1af8d7d`.
The upstream grammar is fetched by the existing pin workflow, rather than
copied into this fixture. Its MIT notice is retained beside the recipe.

Prepare a fresh local grammar with the consumer's reviewed preparer:

```sh
mise exec python@3.12.15 -- python \
  ../billy/libs/tools/regulator/crates/python-joints/grammar_profile.py \
  upstream/grammars/python.json \
  --recipe test/migration/regulator/grammar/python314-rust-v2.json \
  --output .local/rust-migration/regulator-python314-rust-v2.json
```

The preparer refuses a mismatching base, recipe output hash or license. It
creates the output exclusively and never replaces an existing grammar.
`lineage.json` records the observed consumer commit and dirty source hashes;
the dirty preparer and release gate have not been edited by this migration.

This recipe does not select a new consumer default. Before adoption, the
local-source Rust C library must pass the existing binding suites, all
Regulator compatibility facets and governed corpus checks with this profile.
The consumer's published-release `ci.py` archive gate remains separate.

The existing adapter tests recognize modern syntax only under the original v1
profile ID. `candidate-profile.patch` is a test-only admission of the explicit
v2 identity for a private source snapshot. It changes no assertions or grammar
semantics and is not applied to the live consumer. Apply it only to the pinned
private test copy; do not label the v2 grammar as v1 to bypass the identity check.

`grammar/go127-rust-v2.json` similarly preserves all six authored Go profile
rules and adds only the exact conflict `type_parameter_declaration`,
`_simple_type`. Tree-sitter 0.26.11 refuses the parent profile after
`func parameter_list identifier [ identifier` before `,` and independently
requests that group. The candidate generates successfully, with derived SHA-256
`ffc8a018d1af9c45dbc2b2638a353a180d179247b9e82524cbcc3c263301ead4`.
`go-lineage.json` retains its inputs and raw generation diagnostics. The
separate `go-candidate-profile.patch` admits the explicit v2 identity in two
private dialect tests without changing their assertions. Full consumer tests
remain required; neither generation nor this patch selects a consumer default.

`grammar/typescript-rust-v2.json` and `grammar/tsx-rust-v2.json` preserve all
authored TypeScript/TSX rules, extras, precedence and other metadata. Each adds
only three exact conflict groups requested sequentially by Tree-sitter 0.26.11:

1. `_intrinsic_import_type`, `_intrinsic_import_type_member`.
2. `_intrinsic_import_type`, `_intrinsic_import_type_generic`.
3. `primary_expression`, `_import_type_query_arguments`.

The originals and both intermediate recipes fail independent generation; each
reviewed candidate generates successfully. The same candidate grammar bytes
compile, mint and load under the unchanged Rust finite defaults. Raw official
diagnostics and native construction traces are retained in
`evidence/typescript-v2-generation.json` and `evidence/typescript-v2-native.json`;
`typescript-lineage.json` pins the original dirty consumer version and all input
hashes. The derived TypeScript/TSX hashes are respectively
`06578a5fc60e1685625a321989663b5faeb3acb3ca17c19e096ddd32c782aa4f` and
`66984eca07047c6d3aa12acdedf8043e79040d9afb10c84b2b4fc684fa20531a`.
The two explicit v2 identities require no consumer test changes. Their selection
is limited to the private candidate gate; published defaults remain unchanged.

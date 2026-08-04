# test/grammar

One real tree-sitter grammar, committed, so that `zig build test` needs nothing
from the network.

`json.json` is `src/grammar.json` from
[tree-sitter/tree-sitter-json](https://github.com/tree-sitter/tree-sitter-json)
at commit `001c28d7a29832b06b0e831ec77845553c89b56d`, byte for byte. Its sha256
is `6a823bbabc1bbf85f4d7bedfff359e1751011294ac670bd51788c9aff0d68637`, the same
pin `grammars.toml` carries for `json`, and `python3 tool/grammars.py verify`
checks that this copy still matches it. Two copies of a file are a drift risk
unless something says so out loud; that is the something.

## Why this one is committed when the other ten are not

The other ten live in `upstream/grammars/`, which is gitignored and fetched by
`python3 tool/grammars.py fetch`. They are a study corpus: the eleven-language
measurement in `research/joinery/TESTING.md` reads them, and a study corpus is
allowed to cost a download.

This one is a build input. `build.zig` hands it to the test module, and Zig
resolves that path while it is building the graph, not while it is compiling —
so pointing it at a fetched file makes `zig build test` fail on a fresh clone
with `failed to check cache: … file_hash FileNotFound`, before a single test
runs. A repository should build from a clean checkout of itself, on a plane, in
a sandbox, with no prerequisites. 13 KB is a cheap price for that.

## Why a real grammar at all

A hand-built symbol table can only tell you the importer agrees with itself.
Only a file tree-sitter actually generated can tell you the importer and the
scanner agree about what tree-sitter actually writes. json is the smallest
grammar that is still genuinely one of those.

## License

`json.json` is third-party. tree-sitter-json is MIT, Copyright (c) 2014 Max
Brunsfeld; the full text is in that repository's `LICENSE` at the commit above,
and the attribution is recorded in this repository's `NOTICE`.

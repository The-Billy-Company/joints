# joints: Grammars as Data

joints is an experimental parsing engine written in Zig. It imports
tree-sitter `grammar.json` files and compiles them into tables stored as data.
A **folio** holds one grammar; a **codex** holds several. The same native
engine reads those artifacts, parses source, and answers structural queries.
It does not link or invoke the tree-sitter runtime.

The implementation includes a CLI, a C ABI, and Python and Rust source
bindings. It is being integrated into Billy's Regulator for Python linting.
Language coverage, query compatibility, and performance still need to be
established for each consumer's inputs.

## Current status

Version **0.1.0** is experimental. The Python and Rust packages require a
separately supplied, target-matching `libjnt` with **ABI 2**. The release
provides native archives for Linux x86_64 and macOS arm64. They are built and
tested on Ubuntu 24.04 (glibc 2.39) and macOS 14 respectively; other targets
currently require a source build.

| Interface | Implemented today |
|---|---|
| CLI | Grammar compilation, parsing, incremental edits, queries, and diagnostics. |
| C ABI | Grammar banks, parsing, incremental weave, queries, node traversal, and repair evidence. |
| Python | Strict and diagnostic parsing, queries, node traversal, and checked handle lifetimes. Requires Python 3.12 or newer. |
| Rust | Strict and diagnostic parsing, queries, node traversal, borrowed or owned parsers, and checked owner lifetimes. Requires Rust 1.85 or newer. |

Python and Rust currently expose immutable parses. Incremental editing is
available through the CLI and C ABI; it has not been wrapped in those bindings.

Billy's [Regulator](https://github.com/The-Billy-Company/billy/tree/main/libs/tools/regulator)
replaces its custom Python lint ratchets. Its required native compatibility
leg pins Joints and irregex and compares the configured facets, locations,
suppressions, findings, and baselines with the incumbent frontend. The
incumbent remains Regulator's default. That consumer contract does not establish
full tree or query equivalence for every grammar.

## Build from source

Use **Zig 0.16.0** and clone irregex beside joints: the build manifest resolves
it through `../irregex`. The commands below select the irregex commit used by
Billy's native compatibility gate.

```sh
git clone https://github.com/The-Billy-Company/irregex
git -C irregex checkout 508ad3158efc8346469427e18276f01790c17229
git clone https://github.com/The-Billy-Company/joints
cd joints
zig build
```

The build installs `zig-out/bin/joints`, shared and static `libjnt` libraries
under `zig-out/lib`, and `zig-out/include/jnt.h`. Initial builds may download
pinned build dependencies. Compiling a grammar into a folio does not require a
per-language C compiler.

## Parse and query

The committed JSON grammar provides a quick start without fetching a language
repository:

```sh
mkdir -p .local/quickstart
./zig-out/bin/joints mint test/grammar/json.json -o .local/quickstart/json.folio
printf '%s\n' '{"answer": 42}' > .local/quickstart/example.json
./zig-out/bin/joints parse .local/quickstart/json.folio .local/quickstart/example.json --json
printf '%s\n' '(number) @value' > .local/quickstart/numbers.scm
./zig-out/bin/joints query .local/quickstart/json.folio .local/quickstart/numbers.scm .local/quickstart/example.json --captures
```

`mint` also accepts several grammar or folio paths and writes a codex with
`-o`. Select a language from a codex with `--language=NAME` when parsing,
querying, or editing. A `grammar.json` can be passed directly in place of a
folio, at the cost of compiling its tables when it is opened.

The CLI has eight verbs: `mint`, `parse`, `amend`, `query`, `grammar`, `lex`,
`state`, and `survey`. Run it without arguments for the synopsis, or use
`--version` for the package version. `amend` accepts edits as
`FROM..TO=TEXT`, with byte offsets in the current source.

A successful CLI parse can contain repairs. Its exit status alone is not a
strict CI verdict: inspect the confidence and repair evidence, or use the
strict binding API described below.

## Python and Rust

After the native build, use the Python source binding from this checkout:

```sh
PYTHONPATH="$PWD/bindings/python" python3 - <<'PYTHON'
from joints import Bank

with Bank(".local/quickstart/json.folio") as bank, bank.parser() as parser:
    with parser.parse(b"[1, 2, 3]") as tree:
        with parser.query("(number) @value") as query:
            for node in query.captures(tree).get("value", []):
                print(node.text, node.start_point)
PYTHON
```

The binding searches the checkout's native build. Set `JOINTS_LIB` to an
explicit library path when deploying elsewhere: `libjnt.so` on Linux or
`libjnt.dylib` on macOS. Importing the Python package alone does not verify that
the native library is available.

The Rust binding finds `zig-out/lib` in this checkout and links the static
archive by default:

```sh
cargo test --manifest-path bindings/rust/Cargo.toml
```

For a different checkout or packaged crate, set `JOINTS_LIB_DIR` to the
matching native library directory. `JOINTS_LINK_KIND=dynamic` selects shared
linking; a downstream application must arrange its runtime library path.
Neither binding bundles a native library or grammar bank. See the
[Python](bindings/python/README.md) and [Rust](bindings/rust/README.md) guides
for installation, API examples, ownership, and worker reuse.

## Confidence and compatibility

A strict binding parse requires **acceptance, a structurally sound tree,
exactly one root, and no deleted or supplied tokens**. Acceptance and soundness
alone do not prove that the source was understood without repair.

Python raises `ParseError` on strict refusal; `strict=False` retains the
forest and repair evidence for diagnostic tools. Rust returns
`ErrorKind::ParseRefused`; `parse_partial` provides the diagnostic form.
Nodes expose the original bytes, byte spans, zero-based row and byte-column
positions, children, fields, parents, and siblings. Handles remain bound to
their owners and threads; create a bank and parser inside each worker.

Queries use tree-sitter's `.scm` notation and retain capture names, pattern
indices, and ordered matches. Supported text predicates read the original
source. Some query constructs and filters remain unsupported; CI callers
should use the refusal policy for foreign predicates. See the
[query engine](src/kernel/gloss/README.md) for its contract.

[`grammars.toml`](grammars.toml) pins the grammar artifacts used by the core
research, breadth checks, and native consumers, including TSX. A pin makes an
input reproducible; it is not a guarantee of complete language support.
External scanner support combines built-in Zig mechanisms and scanner rules
stored as data in [`customary/`](customary/). Grammar constructs whose
scanner behavior is not implemented can still stop or require repair.

## Design and validation

The press imports a grammar, constructs LR tables, and writes the folio. The
runtime combines lexical transitions and parser stack effects along a balanced
tree, retains a live tree for edits, and exposes nodes and queries to hosts.
Scanner books describe supported stateful scanner behavior for a shared
interpreter. The research examines where these mechanisms compose and what
they cost on real inputs.

The code and the research are linked, with separate responsibilities:

| Path | Purpose |
|---|---|
| [`src/press/`](src/press/README.md) | Grammar import, table construction, and conflict handling. |
| [`src/folio/`](src/folio/README.md) | Grammar artifacts, mapping, verification, and codices. |
| [`src/kernel/`](src/kernel/) | Lexing, stack effects, trees, repair, incremental edits, and queries. |
| [`src/surface/abi/`](src/surface/abi/README.md) | C ABI; [`include/jnt.h`](include/jnt.h) is its normative header. |
| [`bindings/`](bindings/) | Python and Rust source interfaces over `libjnt`. |
| [`research/`](research/README.md) | Claims, prior art, falsifiers, and recorded measurements. |
| [`tool/`](tool/README.md) | Reproducible grammar fetching, validation, and comparisons. |

Recorded coverage, size, and throughput results apply to the sources, grammar
pins, binaries, and workloads named in their dossiers. They are not a current
support matrix or a general performance guarantee. For the design argument,
start with [LANDSCAPE.md](research/LANDSCAPE.md) and the
[joinery tests](research/joinery/TESTING.md).

## Checks

```sh
zig build check
zig build test
zig build idiom
python3 tool/roll.py
PYTHONPATH=bindings/python python3 -m unittest discover -s bindings/python/tests
cargo test --manifest-path bindings/rust/Cargo.toml
```

Build the native library before running binding checks. `zig build test`
reaches the library, CLI, and C ABI tests; `face` and `abi` select the latter
roots. Core tests use the committed JSON grammar. Broader grammar checks
fetch the immutable inputs separately:

```sh
python3 tool/grammars.py fetch
python3 tool/grammars.py verify
python3 tool/rung1.py
python3 tool/standing.py
```

The [CI workflow](.github/workflows/ci.yml) checks Linux and macOS builds and
native bindings, grammar pins, import topology, and measurement provenance.
[CONTRIBUTING.md](CONTRIBUTING.md) explains the gates and how to measure against
an immutable binary instead of a shared build directory.

## Releases and support

[Release assets](https://github.com/The-Billy-Company/joints/releases) include
`joints-0.1.0-linux-x86_64.tar.gz` and `joints-0.1.0-macos-arm64.tar.gz`.
Each extracts into its own versioned directory with `bin/`, `lib/`, `include/`,
`grammar/`, and an integrity manifest. Install the Python package or Rust crate
separately, then select that archive's native library using `JOINTS_LIB` or
`JOINTS_LIB_DIR`. The bindings do not download a native library for you.

The [release workflow](.github/workflows/release.yml) builds all channels,
tests actual installed packages with the matching native library, and checks
versions, notes, main ancestry, and CI before publication. Published registry
artifacts are checked again before the GitHub release is finalized. A manual
workflow run builds and verifies without publishing. See the
[release notes](CHANGELOG.md) for the scope of 0.1.0.

Report bugs through this repository's issues, including the grammar pin,
source bytes, command or API call, and confidence or error evidence. Report
vulnerabilities through a private repository security advisory.

joints is part of The Billy Company's family built on
[irregex](https://github.com/The-Billy-Company/irregex), alongside
[gist](https://github.com/The-Billy-Company/gist),
[relate](https://github.com/The-Billy-Company/relate), and
[blast](https://github.com/The-Billy-Company/blast). Each has its own tracker.

Apache-2.0; see [LICENSE](LICENSE) and [NOTICE](NOTICE).

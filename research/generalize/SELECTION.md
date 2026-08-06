# The selection rule — written before it was run

This file exists so that "we did not curate toward shapes we handle" is a thing
you can check rather than a thing I say. It was written, and the predictions
beside it were written, **before any grammar outside `upstream/grammars/` was
fetched, pressed or parsed**. Nothing below mentions outliner, its results, its
walls, its externals, or any property of a grammar this project has an opinion
about. Every condition is about a third party's roster and an upstream
repository's own contents.

`tool/holdout.py select` is this document as code. It is deterministic: the same
roster commit produces the same twenty on any machine, in any order, forever.

## The roster

    nvim-treesitter/nvim-treesitter
    commit  3d3321b560a63ff92a8692401f303a5123336b86   (2026-08-05)
    path    lua/nvim-treesitter/parsers.lua
    sha256  4a8f2aac6a74475e52ddb0dd3b2cc12b190786191dd5caaf932455ec51a92403
    size    73900 bytes
    entries 323

A third party's list, authored for a different purpose (which parsers a Neovim
user can install), carrying a `url` and a pinned `revision` per entry and a
`location` for the 27 that live inside a monorepo. I did not choose which
languages are on it and I cannot add or remove one without changing the pin,
which is recorded and checked.

## Eligibility

Evaluated against the **pinned revision of each grammar's own repository**, in
this order. A parser failing any condition is ineligible and the condition is
recorded, so the shape of what fell out is itself an observation.

| | Condition | Why, stated now |
|---|---|---|
| **E1** | `url` is on `github.com` and `revision` is 40 hex | anything else I cannot pin |
| **E2** | `<location>/src/grammar.json` exists at that revision | Tier A's denominator; there is nothing to press without it |
| **E3** | the parser is not already in `grammars.toml` — by name (`-`/`_` folded) **or** by (repo, path) coinciding with a corpus pin | the working corpus is what a holdout is held out from |
| **E4** | the repository declares at least one file-type extension for this grammar, read from `<location>/tree-sitter.json` → `grammars[].file-types`, falling back to `<location>/package.json` → `tree-sitter[].file-types` | the extension comes from upstream, never from me — I do not get to decide what a `.rs` file is |
| **E5** | the recursive tree listing at that revision is **not truncated** by the API | a truncated listing cannot be enumerated deterministically |
| **E6** | the repository contains at least one **candidate source file** (below) | a grammar with no real source in its own repo cannot be given one without me choosing it |

### A candidate source file

A path in the repository at the pinned revision such that:

- its extension is one E4 declared;
- its size is in **[1024, 65536]** bytes;
- its path does **not** start with `src/`, `bindings/`, `test/`, `queries/`,
  `node_modules/`, `docs/`, `.github/`;
- and does **not** contain `/src/`, `/test/`, `/node_modules/`, `/fixtures/`.

Each exclusion, with its reason fixed in advance:

- **`src/`** is tree-sitter's generated output — `parser.c`, `grammar.json`,
  `node-types.json`. It is not source in the language.
- **`bindings/`** is generated FFI glue.
- **`test/`, `/fixtures/`** hold tree-sitter's own corpus format (`.txt` with
  `===` headers) and deliberately-broken inputs. The working corpus's files are
  valid real programs; the holdout must be asked the same kind of question.
- **`queries/`** is `.scm`.
- **`node_modules/`, `docs/`, `.github/`** are vendored or non-source.
- **`examples/` is deliberately kept.** It is where a grammar repository puts
  real code in its own language, and it is curated toward what the *grammar*
  handles — which is upstream's bias, not mine, and is exactly the bias a
  holdout is allowed to inherit.
- The **1 KiB floor** is because a 40-byte file has no derivation worth
  comparing.
- The **64 KiB ceiling** is a cost bound, not a difficulty one. The comparison
  is a Python walk over two spines at every byte; the corpus's own largest file
  (`picorv32.v`, 67 KB) already costs minutes. It is applied uniformly and was
  fixed before selection.

## Selection

Sort the eligible parser keys ascending by Unicode code point. Let `N` be the
count. Take the entries at indices

    floor(i * N / 20)    for i = 0 .. 19

An **even alphabetical stride**. It is deterministic, reproducible, independent
of everything about our results, and it spreads the twenty across the whole
alphabet rather than clustering. It is not a popularity ranking — I considered
one and rejected it, because every popularity source I could reach (stars,
download counts) is a live number that would make the selection unreproducible
next week.

## The source file

For each selected grammar, the candidate with the **largest** size; ties broken
by the lexicographically smallest path. One file per grammar.

Largest rather than random because the largest file in a grammar repository is
the one most likely to be a real program rather than a stub, and because a
larger file gives the comparison more bytes to be wrong about — which is the
direction that makes the holdout harder, not easier.

## If fewer than twenty are eligible

Stated in advance so it cannot be invented afterwards: **drop the 1 KiB floor to
256 bytes and re-evaluate once.** If the count is still under twenty, the
holdout is reported at whatever size it reaches and the shortfall is reported as
a fact about the field. It is not patched by relaxing a rule a second time, and
no grammar is hand-added.

## What this rule cannot promise

It does not promise the twenty are representative of anything. It promises they
were not chosen by me, they were not chosen after seeing a result, and they can
be reproduced from two pinned commits by anyone. Their shape distribution —
external counts, sizes, families — is reported in `RESULT-2-holdout.md` **as an
observation afterwards**, which is the only honest place for it.

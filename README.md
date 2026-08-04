# outliner: One Binary, One File, Every Language

- [Status](#status)
- [Overview](#overview)
- [Why this over tree-sitter?](#why-this-over-tree-sitter)
- [The idea](#the-idea)
- [Vocabulary](#vocabulary)
- [Layout](#layout)
- [Where this came from](#where-this-came-from)

## Status

**The falsifier has been run, and it did not kill the design.** There is no
parser yet - what exists is the press (a tree-sitter `grammar.json` importer, an
LR(0) collection, LALR lookaheads, and conflict resolution that reaches zero
residual conflicts on eleven real grammars), the stack-effect monoid M2 with the
cursor that composes it, a terminal scanner, a single-stack reference walk to
check the algebra against, and the CLI that measures all of it.

That order is on purpose: the central claim has a falsifier measurable *before* a
parser exists, so the measurement came first. It says the product of segment
effects reproduces the whole-file effect no matter how finely the file is cut,
across eleven grammars, with nothing disagreeing. Read
[`research/LANDSCAPE.md`](research/LANDSCAPE.md) for the argument,
[`research/joinery/`](research/joinery) for the part that had to be earned, and
[rung 1's verdict](research/joinery/TESTING.md) for what the numbers were - including
the part where the kill condition as originally written was not met, and why that
number turned out to be the wrong one to have chosen.

Every number there is reproducible from a clone. `zig build test` needs nothing;
the eleven-grammar sweep needs the grammars, so fetch them first:
`python3 tool/grammars.py fetch`, then `zig build && python3 tool/rung1.py`.
[CONTRIBUTING.md](CONTRIBUTING.md) has the rest.

What is *not* built is most of the product: the balanced tree the joints hang
from (M3), the tree it yields, repair (M4), the quotient (M5), the folio
artifact, and `libotl`. The table below marks each monoid's real state.

Every number quoted about tree-sitter below was read out of its source, its
issue tracker, or a measurement taken on 2026-08-02. Every number about outliner
is a target with a kill condition attached, and it is labelled as one.

## Overview

outliner is a parsing system for editors and agents: give it a file, get back a
concrete syntax tree that survives edits, tolerates broken code, and answers
structural queries. Same job as tree-sitter.

The difference is what a grammar becomes. In tree-sitter a grammar becomes a C
program, and that one choice is upstream of everything painful about it - a
30 MB `parser.c`, a shared library per language, a grammar that needs 20 GB of
RAM to build, 25 MB of WASM before a browser can highlight ten languages.

Here a grammar becomes **data**: a table in a file. One binary plus one
**folio** is every language you support. No C compiler in the loop, no `.so` per
language, no ABI window, no Emscripten pin, no `parser.c` in git.

The runtime is arena-only and freestanding-capable, which is the part that
matters for reach. It runs in a browser, in an editor, on a phone, in a sandbox,
inside another language's FFI, with no per-surface build story.

## Why this over tree-sitter?

Honestly: today, nothing, because today it does not yet return a tree. When it
does, the pitch is four things, and speed is not one of them.

**Size.** Tree-sitter's dense parse table is 64% of `parser.c` at 24.3% density.
Predicate minterms plus action-bisimulation plus a DAFSA should land materially
under its in-flight CSR work, which itself takes C# from 29 MB to 8.5 MB.

**Reach.** One artifact, no toolchain. The grammars that cannot be built today
because CI runs out of memory are the clearest possible statement of the
problem.

**Recovery you can steer.** Tree-sitter's `error_cost` is a greedy heuristic with
no author-facing knob, which is why typing `justif` in a CSS rule gives you an
`attribute_name` inside an `ERROR`. Here repair is a shortest path in the
tropical semiring with weights declared in the grammar, so that case is a
one-line grammar edit rather than a core patch.

**Edits that do not invalidate the suffix.** Tree-sitter reuses left to right,
so opening a block comment at the top of a file re-parses the file. Because a
segment here stores a *function* rather than a *state*, that edit costs
`O(log n)`.

Do not reach for outliner over tree-sitter for throughput. Tree-sitter's
throughput is fine, and nobody is waiting on a parser.

## The idea

A monoid is a set with an associative product and an identity. That is the whole
prerequisite for three things at once: parallel evaluation (re-bracket freely,
so a product is a prefix scan of `O(log n)` depth), incremental update (keep the
product in a balanced tree and one changed factor costs `O(log n)`), and
composition with no base point (an element is a *function*, so it does not care
what came before it).

That third property is the one tree-sitter gives up, and it is where the suffix
invalidation comes from. A state must be recomputed when its predecessor
changes. A function need not.

outliner runs five monoids over one balanced tree:

| | The monoid | What it buys | State |
|---|---|---|---|
| **M1** | lexical transition functions | data-parallel lexing; an edit does not invalidate downstream lexing | a scanner that tokenizes real files, still missing the externally-scanned terminals |
| **M2** | LR stack effects, the **joints** | position-independent reparse; parallel parse; GLR paid only where the element is multi-valued | built and measured - rung 1 |
| **M3** | balanced parentheses | the tree itself, at 2n+o(n) bits, navigated by range min-max | not built |
| **M4** | a semiring parameter | least-cost repair, ranking, ambiguity counting - one walk, different `⊕` | not built |
| **M5** | Myhill-Nerode quotients | the size win: coarser alphabets, minimized tables | not built |

Four features, one splice implementation, one set of tests. That economy is the
actual argument; the individual monoids are mostly known.

The one genuinely new thing is M2 maintained in a balanced tree, and it has a
clean way to die: if joints do not converge toward rank one on real grammars and
real files, composition costs `|Q|` per join and tree-sitter's O(1)-per-token
walk wins. That measurement needs no parser and is
[rung 1](research/joinery/TESTING.md).

## Vocabulary

The metaphor is bookmaking, and it carries weight rather than decoration:
**you write a rubric; the press compiles it into a folio. At runtime the grain
reads the material, joints compose along the spine, mend repairs what is torn,
gloss answers questions, and the result settles from quire into vellum.**

| Word | What it is |
|---|---|
| **rubric** | the grammar source you write (`.rubric`) |
| **press** | the compiler: rubric to LR(1) to quotient to DAFSA to folio |
| **folio** | the artifact: N languages, one mmap-able file |
| **grain** | the SIMD first pass - strings, comments, brackets, indent columns |
| **joint** | one stack-effect element |
| **spine** | the monoid-annotated balanced tree everything is bound to |
| **mend** | least-cost repair under the tropical semiring |
| **quire** / **vellum** | the live editable tree, and its settled succinct encoding |
| **gloss** | the query engine |

The C ABI is `libotl`, symbols prefixed `otl_`, matching irregex's `libirgx` /
`irgx_`.

## Layout

What exists:

```
research/          the argument, and the claim that has to be earned
  LANDSCAPE.md     the map: incumbent measured, five monoids, order of proof
  joinery/         CLAIM · PRIOR_ART · TESTING for the one new thing
  joinery/corpus/  one ledger program in eleven languages - every per-language number
grammars.toml      the eleven tree-sitter grammars every number is measured over, pinned
tool/              fetch and check those grammars; run rung 1 as a gate
test/grammar/      the one grammar committed, so the test build needs no network
src/press/         the compiler: grammar.json in, LR(0) → LALR → resolved tables out
src/kernel/lex/    the terminal scanner (M1)
src/kernel/joint/  the stack-effect monoid (M2) and the cursor that composes it
src/kernel/walk/   a single-stack reference LR walk, to check the algebra against
src/surface/       the CLI: grammar · lex · state · joints
```

Still to come:

```
src/kernel/spine/  the monoid-annotated balanced tree everything binds to (M3)
src/kernel/quire/  the live editable tree, and vellum, its settled encoding
src/kernel/grain/  the SIMD first pass
src/kernel/mend/   least-cost repair (M4)
src/kernel/gloss/  the query engine
src/folio/         the artifact: pack, read, verify, slice
contract/          the prose contract and the ward import topology
```

The importer is not a nice-to-have. Three hundred maintained grammars with
`highlights.scm` are person-decades and cannot be out-engineered, so they get
imported. `grammar.json` is a declarative data file committed in most grammar
repos, and if the importer preserves node names the query files come along
unmodified.

## Where this came from

outliner is the fifth package in a family built on
[irregex](https://github.com/The-Billy-Company/irregex), the regex engine and
C-ABI floor the others stand on. Its siblings are
[gist](https://github.com/The-Billy-Company/gist) (indexed ripgrep-parity
search), [relate](https://github.com/The-Billy-Company/relate)
(compression-as-search kinship and repetition), and
[blast](https://github.com/The-Billy-Company/blast) (provenance and live blast
radius).

Most of what outliner needs already exists down there: mmap portals, BLAKE3
signets, atomic artifact publishing, the dual-clock freshness model, bitsets,
hash-consing, union-find, byte-balanced parallel fan-out, and the succinct
rank/select and wavelet structures. Seven pieces are missing - a monoid concept
with a parallel prefix scan, the measured balanced tree, Paige-Tarjan
refinement, balanced parentheses with a range min-max tree, a semiring
abstraction, a DAFSA, and an unsealed minterm alphabet. All seven are general
mathematics, so all seven belong in irregex rather than here.

The payoff runs back the other way too. relate currently finds function
boundaries by counting braces and climbing sixteen lines looking for something
that resembles a signature, and normalizes identifiers to `I` and numbers to `N`
against a hand-unioned keyword list. Both are honest approximations of a parse.
An actual parser retires both.

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

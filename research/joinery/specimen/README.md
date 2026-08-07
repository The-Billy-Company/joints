# specimen — the constructs the corpus is silent about

The corpus is one real-world file per grammar, ~526,798 bytes, and it is honest
about typical code and silent about everything else. The silence is
load-bearing: `Maps.kt` and `Chunked.swift` between them contain no
interpolation, no triple quote and no raw string, so a **stateless** hand — one
keeping no memory across a string body, and therefore wrong the moment a string
interpolates — measures byte-perfect on every number this repository takes.

That is not hypothetical. A lane proved Kotlin's entire 19,705-byte orphan
problem is the string wall and then declined to seat the fix, because nothing
in the tree could tell a correct hand from a wrong one.

This directory is that missing population, and `tool/specimen.py` is the
instrument over it.

## The two questions

**"Did the hand get this *right*?"** is a specimen. Small files carrying the
awkward cases on purpose: interpolation inside interpolation, a triple quote
with an embedded quote, a raw delimiter appearing in its own body, an escape at
a boundary, an unterminated opener at end of file. Its verdict is a **tree**,
never a byte count — folding a specimen into a percentage says nothing about
whether interpolation nested twice came back correctly shaped.

**"Which of this grammar's declared externals does anything here exercise?"** is
the coverage gate, and it is the larger deliverable. Both halves of that join
already existed and had never been put together: a grammar declares its
externals in `grammar.json`, and joints already knows which terminals it has
no stand-in for.

## Layout

```
specimen/
  README.md
  PREDICTION-1-coverage.md    written before the gate existed
  RESULT-1-coverage.md        eight predictions, three failed
  kotlin/  swift/  julia/     <specimen>.<ext> beside <specimen>.<ext>.expect
```

A specimen is a source file. Its claims live in a `.expect` beside it, one per
line, `#` to end of line for comment:

| claim | holds when |
|---|---|
| `roots N` | the forest is exactly N trees |
| `mends N` | the parse repaired exactly N times |
| `holds NAME` | a node by that name exists |
| `lacks NAME` | no node by that name exists |
| `spans NAME START END` | a node by that name covers exactly those bytes |

`lacks` catches a **confidently wrong shape** — Kotlin's `${n + 1}` currently
returns a `lambda_literal`, which the troupe contract in `outside.zig` calls
worse than an unanswered token. `spans` catches a **right name at a wrong
extent**, and it is the claim the tier rests on: a first-match reader closing
`"""a""""` at byte 15 instead of 16 produces a node of the correct name, and
nothing but the extent tells them apart. Every extent here is read off the
**source text**, never off a parser.

## Using it

```bash
python3 tool/specimen.py coverage              # the gate, all 30 grammars (~25s)
python3 tool/specimen.py coverage -v --grammar kotlin   # and name the difference
python3 tool/specimen.py coverage --corpus-only # what the real corpus reaches alone
python3 tool/specimen.py run                   # judge every specimen
python3 tool/specimen.py show <path>           # one specimen, its forest, its claims
python3 tool/specimen.py verify                # prove this instrument can say no
python3 tool/specimen.py list | status
```

## Four populations, and how much each is worth

**declared** — the named entries of `externals[]`. Exact; it is a field in a
file. **blind** — what joints has no stand-in for. Exact, but it has to be
pried out: every reporting path caps its list at eight names and appends
`+N more`, so the gate rotates `externals[]` by eight and unions the windows.
That is sound because `provision` resolves a troupe **by name**, never by
position — and the blind total is compared across every rotation anyway, so a
grammar where order does matter is refused rather than averaged.

**seated** = declared − blind. **exercised** — a seated external some file here
actually reaches, witnessed as a node in a real parse.

`exercised` is a **floor twice over** and the gate says so on every run. A
hidden terminal — the `_`-prefixed ones — never becomes a node, so it can be
leaned on hard and never counted; 216 of the 252 seated externals in this tree
are hidden, so the instrument can only witness 36 of them. And a construct can
parse whole with its external blind, because the press keeps an ordinary token
for any spelling it can lex — which is why Swift's line strings work with all
33 of its externals blind. `seated` is therefore a floor on *capability* too,
and only a specimen settles a given construct.

## What it does not touch

Specimens are enumerated from this directory and are never written to
`upstream/sources/` or `research/joinery/corpus/`, which is where `breadth.py`
and the board read from. No board number moves because this tier exists, so
every measurement taken today stays comparable to every other. `verify` asserts
that separation against the live board file list rather than trusting it.

## Anti-vacuity

A gate reporting everything clean because it measured nothing is the exact
failure this tier was built to prevent, so it is required to demonstrate a red
rather than argue it would produce one. `verify` runs five assertions, three of
which exist only to show a predicate can still say **no**:

- specimens are disjoint from both corpus populations;
- a claim can fail (one true and one impossible claim, judged);
- `spans` separates an exact extent from an off-by-one;
- the seven zero-external grammars are `n/a`, never scored clean;
- **a hand regression reddens a green specimen** — `_end_cmd` is renamed in a
  scratch julia.json, which unseats the command troupe, and `command.jl` drops
  from 6/6 to 0/6. Performed, not asserted.

A specimen asserting nothing is failed rather than passed, for the same reason.

## Where the numbers are

`RESULT-1-coverage.md`, including the two lies this instrument told before it
was trusted — one of which reported `seated 0` for all 23 scorable grammars,
and was caught only because a specimen passing 6/6 disproved it.

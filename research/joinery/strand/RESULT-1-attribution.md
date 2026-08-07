# Result 1 — the 22,179 stranded bytes are 96.3% the peel's own scissors

Scored against `PREDICTION-1-attribution.md`, written before any state was read.
**Two of four predictions failed**, including the one about the largest row.

Measured on `joints 5c962f8d5` (`.local/strand/joints`, pinned out of
`zig-out/` before measuring), with `JOINTS_WORK=.local/strand/work` of its own.
Reproduce with:

```sh
python3 tool/walls.py warm --grammar swift   --json > .local/strand/swift-warm.json
python3 tool/walls.py warm --grammar verilog --json > .local/strand/verilog-warm.json
python3 research/joinery/owners/owners.py --json > .local/owners/labelled.json
python3 research/joinery/owners/cut.py --warm .local/strand/swift-warm.json \
                                       --warm .local/strand/verilog-warm.json
```

## The finding

| population | bytes | share |
|---|---:|---:|
| the cold peel's own cut — text that is not a program | 21,350 | 96.3% |
| survives a peel that keeps its prefix | 611 | 2.8% |
| in grammars nobody warm-peeled — neither claimed nor dismissed | 218 | 1.0% |

`stranded` was the right label and it was doing its job. It says *the state
cannot own this*, and the reason it could not is that for 96.3% of the bytes
there is no construct to own: the wall is a fragment refusing a closer whose
opener the peel left behind.

## How the artifact is made, in one file

`tool/walls.py` says it in its own words — "resuming means parsing the remaining
bytes from a clean start, so each round begins in state 0 rather than in
whatever state the product loop had actually accumulated."

`Chunked.swift` reads 1,492 bytes cleanly, then walls at `)` in state 141
**with three braces still open**. The tail the peel hands the parser next
begins:

```
)
    }
  }
}

extension ChunkedByCollection: Collection {
```

Four orphan closers. Each `}` is refused at whatever file-level state the
fragment's own prefix reached, and **the state number is only a count of how
many statements came first**. Three hand-built witnesses reproduce all three
states exactly (`witness/sw-cut-*.swift`):

| fragment | wall | on the board |
|---|---|---:|
| `}` | `}` in state **0** | 13,475 B (already excluded as a resume artifact) |
| `let x = 1` ⏎ `}` | `}` in state **681** | 9,160 B (priced as construct damage) |
| two statements ⏎ `}` | `}` in state **1166** | 3,896 B (priced as construct damage) |
| three statements ⏎ `}` | `}` in state **1166** | — saturates |

The board's `Wall.real` is `not shadow and state != 0`. It catches the first row
and misses the next two, which are the same artifact with a statement in front
of them. That is where 13,056 of swift's bytes came from.

## The discriminator is not a state number

A rule about state 0, or about closers, would be the exclusion restated. The
test used here asks a **different peel**: `walls.py warm` never restarts, so it
always has the real accumulated prefix. A wall it never reaches in 400 rounds
needs the state-0 restart to exist.

It can say no, which is the only reason to believe it: `) in state 141` and
verilog's `; in state 701` and `: in state 701` all survive. The check is in
`research/joinery/owners/cut.py` and prints its own anti-vacuity column — a
grammar whose warm set shares no wall with its cold set is a broken reader, not
a finding.

## The three fold bodies, attributed and priced

**#1 swift `_top_level_statement _semi` → `source_file`, 9,160 B (41.3%)**
**#3 swift `_top_level_statement source_file_repeat1 _semi` → `source_file`, 3,896 B (17.6%)**

One thing, not two: the same file-level position with and without its repeat.
**Owner: the peel.** Cold-only; absent from 400 warm rounds. The fold body is
incidental — it is just what a file-level swift state happens to hold, and the
separator plays no part. Reclassify 13,056 B as resume artifact, beside the
13,475 B of `}` in state 0 already there.

The real swift wall underneath is **`) in state 141`, 95 B**, and it is honestly
`stranded`. State 141 holds `constructor_expression -> user_type .
constructor_suffix` and `_navigable_type_expression -> user_type .`, admits four
terminals of 224 (`(`, `{`, `^{`, and `.` to fold), and arrives on `user_type`
from **196 states**. The fold's single lookahead looks like merge damage and is
not: `FOLLOW(_navigable_type_expression)` really is `{_dot_custom}`, because the
symbol has exactly one production site. The table is right; the mistake is
folding to `user_type` at all, several constructs earlier, which is precisely
what `stranded` means.

**#2 verilog bare `_identifier`, 8 walls, 6,591 B (29.7%)** — see
`RESULT-2-verilog.md`. **Owner: the peel**, cold-only, all 6,591 B.

## Predictions

**P1 — swift is `scanner`, an unseated `_semi` external. FAILED.**
Swift does declare `_implicit_semi` and `_explicit_semi` as externals with no
rule body, and our lexer does emit them — `_implicit_semi in state 398` is a
wall in its own right. All of which is true and none of which is the mechanism.
Both walls are the peel's cut. I reasoned from the fold body's *contents* to a
cause, and the fold body was the one part of the row carrying no information.

**P2 — the verilog eight are NOT one reduce-reduce family. PASSED**, and the
predicted number was right to the tenth: I said ≥95% of the row's bytes are the
`macro_text` path and measured **6,477 of 6,591, 98.3%**. The mechanism is
stronger than predicted — see `RESULT-2-verilog.md`.

**P3 — ≥2 walls and ≥60% of bytes get a named owner. PASSED, 96.3%.** The bar
was set so swift alone (58.9%) could not clear it. Honest caveat: the owner that
carried it is `peel`, a category I did not list when I wrote the bar, so this
passed on a verdict I had not imagined rather than on the ones I had.

**P4 — at least one body lands on the `gather` wrong-limb defect in
`src/kernel/quire/`. FAILED.** None of the three does. Nothing here needs
handing to that lane. The attribution landed on the measurement instrument, and
`src/kernel/quire/` was never in the causal path.

## What this costs the board

Nothing on the damage total and everything on its shape. These bytes were never
in the workable 14.1% — they were in the 22,179 B nobody could own. The change
is that 21,350 B of them stop being an open question:

- **They are not a backlog.** No lane should be sized against them.
- **They are not evidence of grammar difficulty**, and the two swift rows would
  have read as one if the peel had kept its prefix.
- **The unowned population deserves the same test.** 73.7% of damage is unowned
  and unadjudicated, `Wall.real` uses the same too-narrow predicate, and nobody
  has asked how much of that is also the scissors. `cut.py` answers it per
  grammar for the price of one warm peel; I ran two of thirty.

I did not change the board. Re-pricing another lane's instrument on my own
verdict is the failure this dossier is about.

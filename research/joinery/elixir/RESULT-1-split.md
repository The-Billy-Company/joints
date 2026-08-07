# Result 1 — the same-name split does not hold on runs

A lane split the corpus's racked bytes in two by asking whether our node's
*name* matches the oracle's: swift/ruby/kotlin at 100% same-name (an extent
slip, cheap to correct), elixir/verilog/ocaml/sql/julia at 0% (a genuinely
different parent). That number was read off `rack.py show`'s `worst` list,
which prints the **twenty widest runs of each kind** — and the lane said
itself that the population it cannot see is exactly the population a
boundary-slip claim is about, since a three-byte extent gap is a small run by
construction.

It was right to worry. `every.py` asks `survey` for **every** run instead
(`measure(case, top=1<<30)`; `top` is a slice width and nothing else in `rack`
depends on it, so this is the same classifier over the same parse with the
ranking turned off).

| grammar | crooked | runs | same% ALL runs | same% WIDE runs | same% ALL bytes | same% WIDE bytes |
|---|---|---|---|---|---|---|
| elixir | 22,210 | 141 | **37.6%** | 0.0% | 8.9% | 0.0% |
| verilog | 13,981* | 1,853* | 0.0% | 0.0% | 0.0% | 0.0% |
| swift | 10,506 | 242 | 98.3% | 100.0% | 99.6% | 100.0% |
| scala | 9,087 | 166 | **86.1%** | 5.0% | 19.2% | 0.6% |
| ocaml | 2,184 | 51 | 0.0% | 0.0% | 0.0% | 0.0% |
| haskell | 2,115 | 328 | 6.7% | 20.0% | 9.9% | 17.3% |
| kotlin | 247 | 6 | 33.3% | 33.3% | 59.1% | 59.1% |
| ruby | 211 | 7 | 100.0% | 100.0% | 100.0% | 100.0% |
| sql | 179 | 35 | 0.0% | 0.0% | 0.0% | 0.0% |
| julia | 158 | 4 | 0.0% | 0.0% | 0.0% | 0.0% |

`racked` runs only, which is the class the split was a claim about. Measured on
a pinned arm against a frozen oracle — see *Provenance* below. Every row above
reproduced exactly on a second run **except verilog**, whose lane is rebuilding
it live and which read 15,533 crooked over 1,461 runs an hour later; its `0.0%`
held on both, which is the only part of that row this file relies on.

The `crooked` column here is on the ruler that predates the `plumb.hurt()`
ancestry→cover correction, so it does not line up byte-for-byte with
[RESULT-2](RESULT-2-do-block.md) (elixir reads 22,089 there, ocaml 2,113). The
*percentages* are the claim and every one of them is a ratio taken inside one
run of one instrument, so none of them moves.

## What is wrong with it, precisely

**Two of the ten rows invert.** Elixir was reported at 0% and is 37.6%. Scala
was reported at 5% and is 86.1% — a seventeen-fold error, and the largest row
the split misclassifies.

The mechanism is not that the widest list is noisy. It is that **the widest
list is a byte-weighted sample being read as a run-weighted statistic.** Where
a grammar's crooked bytes concentrate in a few enormous different-name runs and
its crooked *count* concentrates in many small same-name ones, sorting by width
and taking twenty returns only the first population. Swift and ruby are immune
because their bytes and their counts agree; elixir and scala are not because
theirs do not.

Restated so it is true, the split is a claim about **bytes**:

> elixir 8.9% same-name by byte, verilog/ocaml/sql/julia 0.0%, against swift
> 99.6% and ruby 100.0%.

That version survives the check, and the grouping it draws is the same one. So
the read that the 0%-by-byte group tracks grammars with an implied statement
terminator is not damaged — but "elixir's crooked bytes are 0% same-name" was
being repeated as a fact about elixir's *runs*, and 53 of its 141 racked runs
are `arguments` under `arguments`.

## The complement, which is worth more than the correction

Every same-name run in elixir carries `Run.edge`, and no different-name run
does. Same in the corpus at large. `edge` is `rack`'s flag for *same start,
different end* — so the two classifications are the same classification:

| kind | ours | theirs | runs | bytes | edge |
|---|---|---|---|---|---|
| racked | `arguments` | `do_block` | 88 | 20,126 | 0 |
| racked | `arguments` | `arguments` | 53 | 1,963 | **53** |
| askew | `arguments` | `do_block` | 39 | 68 | 0 |
| askew | `arguments` | — | 49 | 49 | 0 |
| askew | `arguments` | `arguments` | 4 | 4 | **4** |

That is elixir's entire crooked population, and it has exactly one interesting
row: **`arguments` where the oracle says `do_block`, 88 runs and 20,126 bytes,
91% of the racked total.** The same-name runs beneath it are not a second
defect — they are the same construct's left edge, seen from the outside: our
`arguments` starts where theirs does and runs 11 bytes further because it
swallowed the block. Repair the 20,126 and the 1,963 goes with it, which
[RESULT-2](RESULT-2-do-block.md) confirms by taking both to zero at once.

So a reader wanting the same-name share does not need `every.py` at all;
`rack`'s own `edge` flag already carries it, per run, for free. `every.py` is
how that was found, not something to keep running.

## What this does *not* say

`every.py` re-uses `rack.bucket` and `rack.widest` rather than re-deriving
either, so it cannot disagree with `rack` about what a run is or how one is
classified — it can only disagree about which runs get printed. If `bucket` is
wrong, both are wrong together. This checks a sampling claim and nothing else.

## Provenance

Arm `.local/lane-elixir/base` (`zig build -Dcli-optimize=ReleaseFast` from a
snapshot of the tree, its own `JOINTS_WORK`), oracle frozen with
`attest.py freeze elixirlane` — `d85e736fa` over 30 grammars, tree-sitter
0.26.11 — so both halves of every comparison in this dossier saw the same
oracle. `rack.py verify` reads 38 of 38 on this arm.

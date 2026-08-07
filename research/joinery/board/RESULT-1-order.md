# Result 1 — the board that routes the other boards

Measured 2026-08-05 against `.local/pin/kdocA` (`joints b6cf8b5a3`, tree
`98abef26d`), `generation: uniform`, `cache: kept 30`. Totals `354,893 built +
56,766 orphan + 27,667 rubble + 87,472 spoil = 526,798`, `standing 67.3679%`,
`unbound 115,139` — the same board `research/joinery/orphan/` was taken against,
so every number here is comparable to that dossier's.

Five predictions in `PREDICTION-1-order.md`. **Four held, one failed**, and the
failure changed what I built. A sixth thing I did not predict is in
`RESULT-2-flatter.md`, because I found it inside my own fix.

---

## P1 — HELD. `stamp.ask().mends` is 0 on every row that mends

All **17** rows the board scores at `roots > 1` report `mends == 0` **or**
`roots == 1` from `stamp.ask(tree=True)` — bash, c, cpp, elixir, haskell,
julia, kotlin, latex, markdown, ocaml, php, ruby, scala, sql, swift, verilog,
zig. Not one of them returns the mend count `research/joinery/orphan/gate.py`
reads off the same binary (kotlin 142, verilog 2,109, haskell 1,806, php 1).

The cause is one line. `stamp.verdict()` takes the *last non-blank* stderr
line; a walled grammar prints three, and the last is `inquest`'s owner line,
not the stop line. `MENDED` and `ROOTS` are searched over the verdict, while
`BLIND` and `UNSOUND` are searched over the whole stderr — so exactly the two
fields that ride the stop line are lost on exactly the rows that mended, and
the two that don't stay correct. A field that is right on every quiet row and
wrong on every interesting one is the shape this project has now caught
twenty-two times.

**Routed, not fixed.** `tool/stamp.py` belongs to another lane today. The
correction is one line — search `MENDED`/`ROOTS` over the whole stderr the way
`BLIND` already is — and it is theirs to make.

**One reader downstream is already inverted.** `tool/walls.py`'s `voice` is
mends per distinct wall, which its docstring calls the bounded-tail-versus-
second-project ratio. Fed a constant 0 it reads **0.0 for every walled
grammar**: every tail all depth, no repetition. That is the exact inversion of
what `research/joinery/orphan/` measured, and it is not `walls.py`'s fault.

**And it decided the design.** I did not put `mends` on the board — not because
I could not get it, but because every other column is a property of the tree
the board scored and `mends` is a property of a stderr line. The gate is stated
in `roots` and `leaves` instead, measured off the same tree as `built`. See P4.

---

## P2 — **FAILED**, and the failure is the honest part

Predicted the top five by `damage` and the top five by `1 − standing` would
share **at most two** members.

```
top 5 by damage : verilog, haskell, kotlin, yaml, julia
top 5 by 1-stand: yaml, markdown, haskell, verilog, kotlin
shared: 4 (verilog, haskell, kotlin, yaml)
```

Four. I was wrong by a factor of two, and in the direction that shrinks my own
contribution: at the very top, ranking by bytes and ranking by share mostly
agree, so `damage` is not rescuing the board's default sort. It never was — the
board's default sort is `standing` **ascending**, which was already a share of
damage. The thing that was broken was never the default view; it was
**`unbound`, the number the dispatches actually came off**, which is a
different column and disagrees with both.

That correction is worth more than the prediction was. It means the headline
sort was fine, the priority column was not, and I would have mis-stated which
half of the board failed if I had not written the number down first. It also
means `damage`'s real job is narrower than I pitched: it is the column that
makes the *share* the board already showed sortable **in bytes**, so a reader
can see that scala's 0.5% adrift and 20.6% missing are the same grammar.

Where the two orders do diverge is below the top five, and the divergence is
large: markdown is 2nd by share and 9th by bytes (3,126 bytes on a 3,304-byte
file), elixir is 96.6% standing and still carries 1,559 bytes. Both orders are
on the board for that reason and neither is presented as the work order alone —
the `worst share` line now says in words that it disagrees with the line above
it and that both are the work order.

---

## P3 — HELD. The ranking is a property of the tree, not the pin

Re-measured against the live `zig-out/bin/joints` (tree `3046af30f`, an
unrelated lane's later build):

```
base 98abef26d  verilog haskell kotlin yaml julia php swift scala
live 3046af30f  verilog haskell kotlin yaml julia php swift scala
```

Same eight, same order, across two binaries and two trees. The dispatch list
does not have to name its binary.

---

## P4 — HELD, all three parts, and the third part had to be rebuilt

- **exact** — `leaves == 0` ⟺ `roots ≤ 1` holds on **30 of 30**. At `== 1` it
  breaks on **yaml**, exactly as predicted: yaml builds no tree and hands back
  **zero** roots. So `mends == 0` really does have two meanings — parsed whole,
  and parsed nothing — and the stderr framing cannot tell them apart while the
  board's `basis` column can (`whole` versus `void`). The board prints the
  count of such rows inside the check so the `≤` is never mistaken for
  sloppiness.
- **non-vacuous** — 13 rows at `roots ≤ 1`, 17 above it. Both sides inhabited,
  so the biconditional was asked of a real partition and had a counterexample
  available.
- **graded** — held at **26.1×** (`scala 159.6` vs `elixir 6.1` bytes per root).

**But the guard I shipped is not the guard I predicted, because the predicted
one is a false red.** I wrote `spread ≥ 10×`. It passes on the full corpus and
**reddens on `--set=corpus`**, where the four mending rows are all small
C-family files and the spread is 2×. Nothing is wrong there — the sample is
homogeneous. The threshold was measuring the homogeneity of a subset and
calling it proportionality.

Lowering 10× to 2× to go green would have been the floor-lowering this project
forbids, so I asked the actual question instead: **do the two orders
disagree?** Rank the mending rows by `roots`, rank them by `damage`, and report
the largest displacement. On the corpus subset that reads:

```
by roots  ruby cpp c bash          by damage  c ruby bash cpp
```

Not one row in the same place, at a spread of 2×. The count would have routed a
lane somewhere else entirely, which is the claim — and it needs no constant. If
`damage` ever did become proportional to `roots` the two orders would coincide
and the check reddens on its own terms. The spread rides along as evidence
rather than as the gate. Over the thirty it reads *scala 10 places from where
damage puts it, 26× spread*.

---

## P5 — HELD. My own column is gameable, measured

`verilog · picorv32.v`, `--mend=fell` against `--mend=keep`:

```
policy      built   damage  orphan  rubble   spoil   stand  describes  roots leaves
fell       30,720   63,937   3,267  14,057  46,613  32.5%     22,222  3,544  2,481
keep       56,177   38,480   3,099       8  35,373  59.3%     12,672    186     48
                   -25,457                         +26.9%     -9,550
```

Predicted `damage` falls ≥ 25,000 while `describes` falls ≥ 5,000. Measured
−25,457 and −9,550. **Twenty-five thousand bytes of work order bought by
describing 43% fewer nodes.**

Every guard on the board except one clears it — `covered` rises, `spoil` falls,
`rubble` collapses 14,057 → 8, bare leaves fall 2,481 → 48, roots fall 3,544 →
186. **Only `describes` catches it.** So `describes` is not a footnote to
`damage`; it is the other half of reading it, and sorting by `--damage` now
prints a four-line note saying exactly that, naming the counter-column and the
measurement.

---

## The decision I recorded in advance, and whether it survived

I said I would not classify damage by the bracketed stand-in terminal name,
because `inquest`'s stand-in name is a guess that has been wrong twice, and a
family computed from a guessed name would manufacture families. I said I would
print the rows adjacent under their owner word instead, and that **if that
turned out too weak to show what a lane found by hand, that is a failure of
this design and I would say so.**

It was not too weak. The board groups by `most` — which of `orphan`, `rubble`,
`spoil` holds more than half the damage, arithmetic on three columns, no
strings read — and inside `orphan` the rows sort by damage:

```
orphan    48253  over 12 grammar(s)
  kotlin   20974  19705  ...  [no stand-in for _string_start]
  php       8699   8091  ...  [no stand-in for encapsed_string_chars]
  swift     5337   3997  ...  [no stand-in for multiline_comment]
  scala     4150   4046  ...  [no stand-in for _simple_string_start]
```

The three the lane found by hand are lines 1, 2 and 4 of the group, with swift
between them — a fourth grammar with the same shape, worth another 3,997 orphan
bytes, that the hand search did not name. **Seven of the twelve `orphan` rows
stop on a blind external**; those seven carry 37,575 orphan bytes and 41,290
damage. The board shows the pattern and does not claim it: `most` is a
statement about which bucket, and the verdict text beside it is the grammar's
own words, marked a guess where it is one.

`most` also refuses a plurality that is not one. haskell is 36% spoil, 32%
orphan, 32% rubble and reads **`mixed`** — naming the largest would have
described a three-way split as a spoil problem, which is how a classifier
manufactures a family. Two rows read `mixed`; twelve read `orphan`; four read
`spoil`.

**And nothing reads `rubble`.** No grammar in thirty has misattributed
structure as the plurality of its damage. That is a standing fact about the
sort order the board already offered, so the tally prints the empty group
rather than omitting it: `--rubble` sorts by a bucket that is the plurality of
nobody's damage.

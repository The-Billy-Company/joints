# Result 1 — a frame nobody built, and an oracle that finally has a name

`tool/rack.py`. Predictions in [`PREDICTION-1-frame.md`](PREDICTION-1-frame.md),
written first and unedited after.

Everything here is taken on **pin `frame`** (`cf697da9f`, tree `986eb8ece`)
against **oracle `800ede524`** — tree-sitter 0.26.11, thirty grammars, seat
`frame`. That second half of the stamp did not exist when the predictions were
written, and it is the largest thing this lane produced.

## The oracle had no name, and it moved

`rack` stamped fourteen fields and all fourteen were about outliner. The oracle
is half of every number it prints, and a sibling lane caught what that costs:
**scala read 1,278 crooked in one run and 9,087 in the next — same pin, same
unedited script, stamp byte-identical.** Three oracle libraries under
`.local/differential/` were rebuilt mid-session by other lanes. Nothing in the
tree recorded it, so no rack figure quoted before today is reproducible, and
"old and new side by side" would have compared two different oracles and called
the difference mine.

`tool/attest.py` is the fix. It digests the **sources** each grammar is built
from — not the library — seats them under a tag, and `rack` and `absent` both
print the seat on every run. Its own `verify` says why the sources and not the
library, in four claims it re-measures against this machine:

| claim | measured |
| --- | --- |
| one grammar's oracle is several different files at once | 28 of 29 |
| …and divergence is not a parser: verilog differs in | 0.0003% of bytes |
| …nor is it cosmetic: css differs in | 62.3% of bytes |
| a library older than its sources — the CLI's rebuild trigger | 23 of 29 |

Rows two and three are the argument. A library digest calls a plain rebuild of
the same parser a change, and it cannot tell that apart from the case where the
tree really is holding two different oracles at once. Twenty-eight of
twenty-nine grammars are in that state right now.

## Two deltas, and they point opposite ways

The brief asked for them separately, because averaged together they cancel and
look like nothing happened.

### Delta one: −12,439 bytes, subtracted from what I would defend

A parent **both sides agree on** whose right edge moved. Same name, same
namedness, same start; it stops somewhere else. That is a real defect and it is
not "a shape tree-sitter does not build", which is the sentence those bytes were
feeding. `soft` now subtracts them behind whitespace and extras, so the three
columns partition rather than overlap.

| | crooked | blank | extra | edge | soft | **HARD** |
| --- | --- | --- | --- | --- | --- | --- |
| before | 83,169 | 1,386 | 21,645 | — | 27.7% | **60,138** |
| after | 83,169 | 1,386 | 21,645 | 12,439 | 42.6% | **47,699** |

The sibling that found this class priced it at **8,334** and put the defended
figure at 52,439. My rule reads **12,439** on this pin and lands at 47,699. I
cannot reconcile the 4,105 without their predicate; the difference is probably
the precedence — mine charges whitespace and extras first and only then asks
whether the edge moved, so a moved `pair` containing a blank line is not
subtracted twice. Both numbers agree on the direction and the order of
magnitude, and both say the published 60,138 was too high.

**toml is the clean confirmation.** The sibling adjudicated it and the verdict
was against the instrument: zero declared conflicts, zero contested cells across
175 states, both parsers hanging `comment` under the same `pair`. `soft` now
reads toml at **29 crooked, 100.0% soft, 0 HARD** — 4 blank, 9 extra, 16 edge.
The instrument agrees it was wrong.

### Delta two: +60,067 bytes, in a column that did not exist

**A frame is missing when the oracle has a bracket, other than its own root,
wholly containing two or more of outliner's built roots, and outliner has no
node with that extent.** Charged to a new `unframed` bucket, taken only from
`square` and `renamed`.

```text
before  265,603 sq + 47 ren + 44,059 askew + 39,110 racked
                                    + 35,896 unjudged = 384,715
after   205,583 sq +  0 ren + 44,059 askew + 39,110 racked
                 + 60,067 unframed + 35,896 unjudged = 384,715
```

`square` fell 60,020 and `renamed` fell 47. 60,020 + 47 = **60,067**, exactly
the new bucket, and `askew` and `racked` did not move by a single byte.

**`unframed` is not added to `crooked` and the two must not be summed.** One
says the derivation over a byte differs; the other says there is a node above it
on one side and nothing on ours. Different questions, different columns.

## The nine bytes

`research/joinery/specimen/html/erroneous-end-tag.html`, which the previous
author demonstrated and did not close:

```html
<p>x</q>
```

The oracle reads one `element [0, 8)` over three children. Outliner reads two
roots and no `element`. The rule this file shipped with scored that **7 square,
0 crooked — a perfect row.** It now scores **7 of 7 unframed, 0 square**, and
`verify` asserts the old scoring as a tripwire so the hole cannot reopen
silently.

## The predictions

| | claim | |
| --- | --- | --- |
| **P1** | specimen charges 7 of 7 `unframed`, `square` 7 → 0 | **held** |
| **P2** | `askew` stays 44,059, `racked` stays 39,110 | **held**, to the byte |
| **P3** | a 0-crooked grammar stops reading 0 | **falsified as worded** |
| **P4** | none of the twelve 100.0% grammars moves | **held**, all twelve |
| **P5** | `haskell` is the widest new charge | **falsified** |
| **P6** | corpus `unframed` under 38,471 bytes | **falsified** — 60,067 |
| **P7** | `unframed` is less soft than crooked's 27.7% | **held** — 1.9% |
| **P8** | the html corpus row stays 72,288 square | **held** |

P5 named haskell; the widest is **elixir at 26,756**, then php 18,354, with
haskell third at 6,070. P6 bounded the total at 10% of built and it landed at
**15.61%** — the failure mode the prediction itself named, for the reason the
next section gives.

**P3 was self-contradictory and I did not notice when I wrote it.** P2 pins
`crooked`, so nothing keyed on a seam between two roots can move it — the
question P3 asked cannot be answered in either direction. The substance behind
it did land, and on the two candidates named in advance and no third: `c` goes
872 built / all square → 105 unframed, and `markdown` goes 178 built / all
square → **178 unframed, its entire file**. Those are the grammars that stop
being clean, and the brief asked for exactly that list.

**P4 contradicted the brief on purpose and the corpus sided with the
prediction.** All twelve whole grammars hand back a single root, and a rule
keyed on the seam between two roots cannot fire without a second root. "Which
clean grammars go dirty" is not a question the corpus can answer for those
twelve; that structural fact is the answer.

## What I said would make me distrust the result

> A grammar charging its whole file to one depth-1 wrapper node. […] I will
> look for exactly that shape before quoting any total, and if it is there I
> will name it and hold it out rather than average it in.

It is there, and it is most of the number. `engulf` counts the bytes under the
**single widest missing frame on a row**:

**56,715 of 60,067 unframed bytes — 94.4% — are one frame per file.** Elixir's
entire 26,756 is a single file-wide `do_block`. Where a file is one construct,
that is the forest-versus-tree difference wearing a new name, and `orphan`,
`rubble` and `spoil` already price it.

**3,352 bytes are every other missing frame.** That is the seam charge: 0.87% of
built. It is a twentieth of the headline and it is the part I would defend.

The board prints the split rather than the total alone, and `verify` holds both
shapes — haskell's 624 roots costing it 6,070 of 9,192 (strictly between none
and all of it), and elixir's 26,756 of 26,756 being one node.

## The free finding: a diagnostic nobody read

`standing.py` has been printing this on the toml row the whole time, on a
grammar the board scores **100.0% standing** and `whole`:

```text
UNSOUND: 1 loose, 0 disorder, 0 torn
  [child outside its parent: comment [47, 56) in pair [27, 45)]
```

That is outliner's own words about its own forest, and no board read them.
`rack board` now surfaces every such row under the table. One row carries one
today. It is the same defect the moved-edge class prices, arrived at from the
other side — the parser said so itself before any oracle was consulted. The
handover for that lane is [`HANDOVER-standing.md`](HANDOVER-standing.md).

## How much of the 60,138 was a floor

Plainly, since the brief asked plainly: **none of it.** 60,138 was a **ceiling**
that has come down to 47,699, because 12,439 of it was a class nobody disputes.
The floor question belongs to the other column: `unframed` adds 60,067 bytes the
instrument could not see at all, of which 3,352 are seams and 56,715 are the
forest-versus-tree difference already priced elsewhere. The honest pair of
numbers is **47,699 defended crooked** and **3,352 defended seam**, over 384,715
built, on oracle `800ede524`.

## Reproducing

```sh
python3 tool/attest.py show                     # each grammar's oracle and seat
python3 tool/attest.py verify                   # why sources, not libraries
python3 tool/rack.py board  --oracle=frame      # the split + unread complaints
python3 tool/rack.py soft   --oracle=frame      # blank / extra / edge / HARD
python3 tool/rack.py show   --oracle=frame html # widest runs, with their bytes
python3 tool/rack.py verify                     # 19 tripwires, five this lane's
```

`--oracle=` without a seat runs against the shared tree four lanes write to, and
says so.

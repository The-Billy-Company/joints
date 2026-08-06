# Result 4 — the bucket that borrowed, repriced

Scored against `PREDICTION-4-borrow.md`, written before a number was taken.
Every measurement below is one pinned arm, `borrow`, sighted, its own oracle
minted inside it; the control is the same arm read before the edit, so the two
readings share a binary, a folio cache and an oracle and differ in one line of
`tool/standing.py`. `square` reads 311,540 on both, which is also what
`RESULT-8-sighted.md` published, so the arm is the tree everyone else measured.

## The repair

Repair 1: `standing.audit()`'s soft sample is restricted to the kinds `crooked`
is made of. `CROOKED = ("askew", "racked")`, and the constant is not trusted —
per row, the runs it admits must total `rack.Seen.crooked`, or `audit` prints
`DRIFT`. If rack ever counts a third kind the sample starts *under*-reading
instead of over-drawing: same defect, other sign, and it now says so.

Repair 2 — keep the wide sample, subtract its unframed share from `unframed` —
is wrong rather than unchosen, on three counts argued in P1 and unchanged by
the measurement. It is repair 1 plus an unargued discount on a second column; it
puts `standing.py` at odds with the two other copies of the soft rule
(`rack.soft`'s `hollow`, `flag/spans.py`'s `GUILTY` test) where repair 1 puts it
back in step; and it shrinks the total charge `crooked + unframed` by the
overdraw where repair 1 conserves it. It is also the flattering direction, and
it discounts the column the rack lane is moving bytes into this hour.

## The corrected board

| row | crooked was | now | move | of true value | soft was | now | drawn from |
|---|---|---|---|---|---|---|---|
| haskell | 1,357 | **2,065** | +708 | +52.2% / 34.3% missing | 794 | 86 | askew 56, racked 30 |
| ocaml | 2,083 | **2,113** | +30 | +1.4% / 1.4% missing | 101 | 71 | askew 71 |
| cpp | 631 | **652** | +21 | +3.3% / 3.2% missing | 49 | 28 | askew 28 |
| swift | 8,740 | **8,754** | +14 | +0.2% | 927 | 913 | askew 913 |
| sql | 176 | **179** | +3 | +1.7% | 3 | 0 | — |
| julia | 156 | **158** | +2 | +1.3% | 2 | 0 | — |
| corpus | 51,448 | **52,226** | +778 | | 9,377 | 8,599 | |

The handoff's "understated by 34%" and this table's "+52.2%" are the same fact
from the two ends: 708 is 34.3% of the true 2,065 and 52.2% of the printed
1,357. Each row lands on `borrow.py`'s `restricted` column to the byte.

**`square` does not move, on any of thirty rows.** Nor do `unframed`,
`unaudited` or `built`. The redistribution is confined to `crooked` against
`soft`, and `crooked + soft` is conserved per row, so the total charge is
unchanged and only its split into *charged* and *excused* moves. `trued` is
`square / size`, so it stands at 59.1% and every conclusion in
`RESULT-8-sighted.md` — whose whole table is `square` and `damage` — stands
untouched. What moves is any conclusion quoting `crooked`: `widest by CROOKED`
now reads elixir 22,089 · verilog 13,841 · swift 8,754 · ocaml 2,113 · haskell
2,065, with haskell rising from sixth to fifth and displacing scala from the
printed five. Every move is in the unflattering direction.

## The negative arms

Not re-measured, and the reason is worth recording rather than working around:
the three reproducing arms are scala with the block-comment row out, their
folios re-press under any binary but the one that made them, and that binary is
a Zig build this lane is barred from. Copying `work-r4`'s folios into my own
scratch and re-auditing re-minted all thirty — the board said so — and gave the
base scala row back, `built 15,957`, not the fixture's `13,550`.

The sign claim does not need the fixture. The shipped rule subtracted the whole
of `soft` from `seen.crooked`, so each cache carries its own true value:

| arm | shipped | soft | seen.crooked | true crooked |
|---|---|---|---|---|
| `sighted/scratch2/work-r4` | −8,669 | 9,687 | 1,018 | in [0, 1,018] |
| `aud-iso/work-r4` | −335 | 1,353 | 1,018 | in [0, 1,018] |
| `sighted/scratch2/work-union` | −8,279 | 10,217 | 1,938 | in [0, 1,938] |
| `sighted/scratch3/work-r0-4` | −8,279 | 10,217 | 1,938 | in [0, 1,938] |

The arm that read −8,669 was pricing a bucket worth at most 1,018 bytes; it
borrowed eight and a half times its own balance. And under the repair the
negative is not merely absent but unrepresentable: `soft` is a subset-sum of the
runs that total `seen.crooked`, asserted per row, so `crooked − soft ≥ 0`
identically. That is a stronger statement than any arm could have given, and it
is the reason clamping at zero would have been the wrong shape of fix — it would
have made the impossible number disappear and left all six rows understated.

## The check, proved by breaking it

`research/joinery/consort/restore.py` restores the shipped sample rule into a
*sibling work dir*, with the arm's folios copied across so every digest matches
and the board accepts the verdicts as live. `tool/standing.py` is never wrong on
disk; ten lanes share this tree. It refuses to report unless its `crooked` and
`soft` equal a kept pre-fix cache on every row — **30 of 30 match**, so the
counterfactual is the shipped bug and not an imitation of it. The one thing it
adds is provenance, because the shipped rule kept none: the check is proved
against *the same sample rule with the field the repair introduced*, not against
a weaker bug that would be easier to catch.

Reading it, the board turns **1 of 8 gates red**:

> **BROKEN** — and `soft` is drawn from the population it is charged against:
> askew+racked and nothing else — haskell drew 708 of unframed, swift drew 14,
> sql 3, ocaml 30, julia 2, cpp 21.

Exactly the six rows of the handoff's base table, with the exact overdraws,
totalling the 778 bytes the repair moved. Every other audited row is green, and
so are the seven other gates — **including both audit gates that already
existed**. The sum identity and the no-negative-bucket check certify the
borrowing partition, on that run, in that table. That is the finding: passing
them means the arithmetic closed.

## Predictions, scored

| | claim | verdict |
|---|---|---|
| P1 | ship repair 1, for three checkable reasons | **right** |
| P2 | six rows land on `restricted` to the byte | **half** — the claim held on all six; the values I transcribed (cpp 553→591, haskell 1,375→2,074) were the handoff's arm, not mine, and none matched |
| P3 | three scala arms go positive, r4 → +988 | **half** — sign now proved structurally and per-cache bounded to [0, 1,018]; +988 unverified and unverifiable without the fixture binary |
| P4 | `square` moves on zero rows | **right** — 30 of 30 |
| P5 | `unframed` moves on zero rows | **right** — 30 of 30, and this is what separates the two repairs |
| P6 | `unaudited`, `built`, `trued` unchanged | **right** |
| P7 | `soft` falls by exactly the overdraw, ∓787 | **half** — exactly equal and opposite held to the byte, the magnitude was 778 and the per-row numbers were the handoff's arm again |
| P8 | haskell rises at least one place in `widest by CROOKED` | **right** — sixth to fifth, displacing scala |
| P9 | no conclusion resting on `square` or `damage` moves | **right** |
| P10 | sum identity green in both directions, including with the bug restored | **right** — green on the adverse cache |
| P11 | negative-bucket assertion green on the base board with the bug restored | **right** — green on the adverse cache |
| P12 | provenance reddens exactly the six rows, no seventh, no fewer | **right** — six, named, with exact overdraws |
| P13 | a pre-provenance verdict reads unattributable, not clean | **right** — observed on the first board against the old cache, cleared on re-audit |
| P14 | the two lanes' changes commute and share no line | **half** — argued and structurally sound (my change never reads or writes `unframed`, it only stops spending it), but `tool/rack.py` is untracked in this tree so there is no diff to compose against and this is unmeasured |

Nine right, five half, none wrong. The five halves are one mistake made five
times: I quoted the handoff's tables as if they were my arm's. They were taken
against a different oracle, so every transcribed figure was off by a little and
haskell's by 700. The falsifiable form of each claim — *lands on `restricted`*,
*equal and opposite* — is what survived, and it survived because it named a
relation instead of a number. The lesson is cheap here and would not have been
if I had predicted only the numbers.

## How the two lanes compose

The rack lane is moving bytes from `unwindowed` into `unframed`, having found
97.9% of `unwindowed` mislabelled and the classification leaning flattering.
Both columns are downstream of `bucket()` and counted in `Seen`. My change never
reads `unframed` and never writes it; it only stops spending it. So the
composition is one-way: whatever `unframed` becomes, `crooked` no longer borrows
from it — and the larger that lane correctly makes `unframed`, the larger this
borrowing *would have been* had it stayed. The two repairs are complements, not
a race, and shipping mine first means their bytes arrive into a column nothing
is drawing on.

## The instrument I trust least

**The pin I measured on.** Every number here is one arm, and `pin.py arm` told
me it was sighted, and the sum check, the negative-bucket check, the four-digest
refusal and now the provenance check were all green on it. None of that clears
it, for the same reason the sum identity did not clear the six rows: a gate
tells you a stated property held, and the property I actually need is that this
arm is the tree the rest of the board was priced on — which no gate on it
states. What I have instead is one coincidence worth more than all four gates:
`square` reads 311,540 here and `RESULT-8-sighted.md` published 311,540. That is
corroboration from outside the instrument, and it is the only evidence in this
dossier that the arm is not privately consistent and publicly wrong.

The nearest miss is the control-after-arm rule I honoured but could not fully
buy: my before and after are the same arm minutes apart, which rules out a
sibling landing a fix between the pins — but not a sibling landing one *during*
the 57-second audit sweep. Nothing in either cache would show it.

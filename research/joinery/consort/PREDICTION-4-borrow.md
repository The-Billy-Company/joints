# Prediction 4 — repairing the bucket that borrows from its neighbour

Written before a single number was taken on this lane. `HANDOFF-crooked.md`'s
tables are the published starting point and are quoted, not re-derived; every
prediction below is about what happens to them *after* the repair, and about
what a check written to catch this would do when the bug is put back.

The subject is one line of `tool/standing.py`. No Zig moves, no `tool/rack.py`
moves, so the two arms below are one binary and one oracle — the `--null` shape,
where sharing a binary is the requirement rather than the defect.

## Which repair, and why the other is wrong

**P1 — I will ship repair 1, restricting the sample to the kinds `crooked`
contains.** Not because repair 2 is merely unchosen. Three reasons, all
checkable:

- The soft rule already exists twice more in this tree and **both other copies
  are restricted**. `rack.soft` walks the same `seen.worst` and files an
  `unframed` run's blank share as `hollow`, a separate number it never
  subtracts from anything, closing with *"the frame is missing either way"*.
  `research/joinery/flag/spans.py` softens a byte only when that byte's own
  class is in `GUILTY`, so an `unframed` byte cannot be softened there at all.
  `standing.audit()` is the third copy and the only drifted one; repair 1
  restores three-way parity and repair 2 puts standing.py at odds with both.
- `soft`'s own definition cannot describe an `unframed` run. The board says
  `soft` is *"the disagreement is where an EXTRA hangs. Not a misreading by
  either side"* — two placements of one node. An `unframed` run is a node on
  the oracle's side and **nothing on ours**. The qualifying test that fires on
  scala is `w.theirs in was`: tree-sitter built a `comment` and we built no
  comment, and the name of the node we failed to build is being used to excuse
  failing to build it.
- Repair 2 is repair 1 **plus an unargued policy change to a second column**,
  and that column is the one the adjacent lane is moving bytes into this hour.
  Discounting `unframed` inside `standing.py` would make one word mean two
  things in two instruments, and every byte the rack lane reclassifies out of
  `unwindowed` would arrive pre-discounted. It is also the flattering direction:
  repair 2 shrinks the total charge `crooked + unframed` by the overdraw, where
  repair 1 moves the overdraw back into the column it was taken from and leaves
  the total exactly where it was.

## What the corrected board reads

**P2 — the six understated rows land exactly on `borrow.py`'s `restricted`
column**, to the byte: cpp 553→591, haskell 1,375→2,074, ocaml 2,083→2,113,
julia 157→160, sql 176→179, swift 8,740→8,754. haskell is +50.8% of what the
board printed (the handoff's "understated by 34%" read against the true value).

**P3 — the three scala arms stop being negative and land on `restricted`**:
r4 −8,669 → **+988**. r0-4 and union move by their own overdraw, which I have
not measured; I predict both land positive and both land on the same number as
each other, since the two arms agree on every other column today.

**P4 — `square` does not move on any row, on either set.** The repair touches
only which runs the soft sample sums. `Held.square` is `seen.square +
seen.renamed` and `seen` is not re-derived. 30 of 30 identical. If `square`
moves at all, my account of the mechanism is wrong and I stop.

**P5 — `unframed` does not move either**, and this is the observable that
separates the two repairs: under repair 1 it is untouched, under repair 2 it
falls by the overdraw. 30 of 30 identical.

**P6 — `unaudited` unchanged, `built` unchanged, `trued` unchanged.** `trued`
is `square / size`, so P4 implies it.

**P7 — `soft` falls by exactly the overdraw** on the six rows: cpp 38→0,
haskell 799→100, ocaml 101→71, julia 3→0, sql 3→0, swift 927→913. Corpus-wide
`soft` falls by **787** and `crooked` rises by **787**, the two exactly equal
and opposite.

**P8 — the AUDIT block's ranking moves.** `widest by CROOKED` prints the top
five; haskell gains 699 and is the largest single move, so I predict haskell
rises at least one place. I have not read the other rows' `crooked`, so I do not
predict the resulting order.

**P9 — no published conclusion that rests on `square` or `damage` changes.**
`RESULT-8-sighted.md`'s whole table is those two columns and its ten scored
predictions are about `square`; every one of them stands. The conclusions that
do move are any quoting `crooked` — six rows of the base board and the three
negative arms — and they move in the **unflattering** direction, which is the
direction that never gets caught by suspicion alone.

## What the checks do

**P10 — the sum identity is green before and after, on every row, in both
directions.** `soft` is added in one bucket and subtracted from another, so it
cancels; the identity is *algebraically* incapable of seeing which population
the sample was drawn from. That is not a bug in the assertion, it is the
assertion's scope, and it means the sum check will still be green when I
deliberately restore the borrowing.

**P11 — the negative-bucket assertion is green on the base board both before
and after, including with the borrowing restored.** It fires on the tail only;
on the base arm no row crosses zero, so it certifies six understated rows
without complaint. It goes red only on the scala arms.

**P12 — the check that catches the body is provenance, not magnitude.** `soft`
must carry the kinds it was summed from, and the assertion is that every one of
them is a kind `crooked` counts, plus that the recorded widths total the `soft`
the row printed. Restoring the borrowing turns it red on **exactly the six rows
in the handoff's base table** and leaves every other audited row green. If a
seventh reddens, my reading of `borrow.py` is incomplete; if fewer than six do,
the check is not seeing what `borrow.py` sees.

**P13 — a verdict written before the provenance existed reads as unattributable
rather than as clean.** A cached `soft > 0` with no recorded population is the
same amount of evidence as a wrong one, so it reddens and says to re-run
`--audit`. I expect this to be visible on the first board I take against an
older cache, and to clear on re-audit.

## How the two lanes compose

**P14 — the two changes commute and do not overlap.** The rack lane moves bytes
from `unwindowed` into `unframed`; both are downstream of `bucket()` and both
are counted in `Seen`. My change never reads `unframed` and never writes it — it
only stops *spending* it. So the composition is: whatever `unframed` becomes,
`crooked` no longer borrows from it, and the larger the rack lane makes
`unframed`, the larger the borrowing would have been had it stayed. I predict
the two changes touch no common line and that a board taken after both reads a
`crooked` identical to a board taken after mine alone on every row where the
rack lane moves no byte.

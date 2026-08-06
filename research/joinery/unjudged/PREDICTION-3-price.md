# Prediction 3 - the price of a byte under a frame we never built

Written before anything ran, against the brief in
[`RESULT-6`](RESULT-6-residue.md): `rack.survey` tests `not t_sp[k]` before it
tests `missing[p]`, so a byte under a frame the oracle has and we never built is
filed `unwindowed` - which reads as the oracle's silence - as soon as we put any
structure of our own underneath it. The previous lane measured the population
(1,237 of 1,264 corpus-wide, 97.9%) and deliberately did not re-price it. I am
re-pricing it.

Four jobs, twenty claims. Each is a thing that can come back false.

## How this is measured, and why there is no arm hazard

The re-pricing is a **Python-side reclassification of one parse**. Both rules
read the same `plumb.Read` - the same forest, the same oracle tree, the same
windows, the same renames - so before and after are not two runs, two binaries
or two oracles. They are one measurement priced twice, which is the strongest
form of controlled comparison available on this tree and the only one where
"pin the control after the arm" cannot bite.

Arm `shade` (`.local/pin/shade`), its own folio cache, its own oracle seat,
tree-sitter 0.26.11. `square` is confirmed live on the arm before anything else
is read - javascript 1,080 of 1,080 - because an isolated work directory that
silently drops the oracle column reads exactly like perfect agreement.

## Job 1 - the re-priced board

**P1.1 - nine rows move, not ten.** `RESULT-6`'s table has ten rows with
`unwindowed > 0`, but kotlin's under-a-missing-frame count is 0 and ruby's is 2
of 23. So exactly **nine** rows change any column, and kotlin's `unwindowed`
survives the re-price intact. I am predicting against the brief's own count
here.

**P1.2 - the corpus moves by exactly 1,237.** `unframed` rises 25,796 →
27,033; `unwindowed` falls 1,264 → 27; `blind` falls 5,564 → 4,327 (1.40% →
1.09% of built).

**P1.3 - `square` is untouched on all thirty rows, and so is everything else
below the frame.** `built`, `square`, `renamed`, `askew`, `racked`, `crooked`,
`gap`, `their_nodes`, `shared`, `frames`, `framed` are byte-identical under both
rules on every row. The branch being re-pointed is reached only when the oracle
has nothing inside the window, which is disjoint from every branch that produces
those columns.

**P1.4 - the honest share gets *better*, and that is the uncomfortable half.**
`share` is `crooked / judged`. The numerator cannot move (P1.3) and the
denominator grows by 1,237, so the corpus crooked share **falls**. I predict it
falls by less than 0.2 points. A re-price that only ever made the board look
worse would be a re-price nobody needed to be careful about.

**P1.5 - haskell is 1,013 of the 1,237 (81.9%) and the largest single move.**

**P1.6 - `engulf` rises too, strictly between 0 and 1,237.** The new charge has
to be counted under the widest missing frame on its row exactly as the existing
charge is, or `engulf` starts under-reporting the share of `unframed` that is
one wide node - which is the flattering direction, since `engulf` reads as an
excuse.

**P1.7 - no conclusion published today changes sign.** verilog's 611 square
stands; the corpus square total is unchanged; `RESULT-2`'s before/after table
moves only in its blind column.

## Job 2 - the tripwire, and the other branch orders

**P2.1 - the falsifier is corpus-shaped, not row-shaped.** A tripwire naming
haskell is a tripwire a press lane can dissolve, which is the mistake
`RESULT-5`'s `engulf` row was fixed for this morning. The assertion is: some
row's `unwindowed` population under a missing frame must be non-empty, and under
the shipped rule **none of it may be filed `unwindowed`**.

**P2.2 - broken on purpose, exactly the shade-bearing rows go red.** Under
`--price=windowed` the new assertions fail and **all nineteen pre-existing
tripwires stay green**, because not one of them asserts anything about this
branch - which is the whole finding.

**P2.3 - the same shape lives in one other branch, and it is `unjudged`.**
`unjudged` is tested first of all, before `missing[p]`, so a byte under a frame
we never built that also carries plumb's ERROR taint reads as silence too. I
predict that overlap is **over 1,000 bytes corpus-wide** and concentrated in
verilog and sql.

**P2.4 - and 100% of that overlap arrives through the ERROR arms, none of it
through `them is None`.** A missing frame *is* an oracle bracket, so every byte
under one has an oracle node over it and `t_who[p] < 0` is impossible there.
This is the mechanism argument that decides whether the branch should move, so
it is predicted rather than asserted afterwards.

**P2.5 - and I predict it should NOT move.** In the `unwindowed` case the
oracle's frame is its verdict. In the ERROR case the oracle's own tree is
damaged over the byte, so the frame is not evidence and `unjudged` stays
plumb's rule verbatim. Falsifiable half: if the overlap turns out to sit under
frames the oracle builds *outside* any ERROR subtree, I am wrong and it should
move.

## Job 3 - verilog's damage

**P3.1 - both figures reproduce to the byte, by a second reader.** Computed
from `plumb`'s own node list rather than from `standing.rows`' text parse:
`built` 30,720, honest built 26,538, so `size − built` = 63,937 and
`size − honest` = 68,119, and the gap is 4,182.

**P3.2 - the board's number is exactly right and exactly wrong.** It is
`1 − standing` in bytes by definition, so it is not an error; and it is wrong
every time it is quoted as *bytes verilog never built*, because 4,182 bytes
inside `built` have no leaf standing on them. The correction is a column that
says so, not a redefinition of `damage`.

**P3.3 - verilog is the corpus's widest stretch row**, and corpus stretch is
over 10,000 bytes.

**P3.4 - a majority of verilog's 4,182 stretch bytes are not whitespace.** They
are source text under a root with no token on it, which is what makes them worth
a column rather than a footnote.

## Job 4 - the mutant population, pointed somewhere else

**P4.1 - it is cheap, because `brood()` is already the whole generator.**

**P4.2 - and the corpus is as poor a population for `rack` as it was for the
reader.** Over the thirty corpus rows I predict rack's plumb-ERROR arms fire on
**two rows**, and that over a mutant population of the same grammars they fire
on more than fifteen. A branch that fires on 2 of 30 real rows is a branch whose
next defect will be found by a dossier and not by a gate.

**P4.3 - and at least one rack column that reads alive on the corpus takes only
one value over the corpus.** Named after measurement, because naming it now
would be choosing the column I already suspect.

## What would make me wrong in the way that matters

The failure mode of this lane is reclassifying until the board looks the way I
expect. The guard is P1.3: **`square` may not move.** If it moves, the branch I
re-pointed was not the branch I thought it was, and the correct response is to
stop and say so rather than to explain the movement.

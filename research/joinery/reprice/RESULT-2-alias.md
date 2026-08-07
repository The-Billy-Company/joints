# Result 2 — the warm peel manufactures walls too, and the falsifier that is a presence

Same pin as `RESULT-1-provenance.md`. This file is about the instrument I was
handed as the clearing evidence, and it did not clear anything.

## The three-parse probe

`Chunked.swift`, one grammar, three bodies:

| body | verdict |
|---|---|
| as written | `unexpected ) at 1492 in state 141, 308 roots, mended 31` |
| `)` at 1492 blanked | `unexpected } at 1498 in state 141, 308 roots, mended 30` |
| `}` at 1498 blanked, `)` left alone | `unexpected ) at 1492 in state 141, 308 roots, mended 30` |

Row three says **`}` at 1498 is not a wall in the file as written.** Row two says
it becomes one the moment the `)` before it is blanked — in the same state 141,
with the same 308 roots, and the same reach 28,467. Nothing was bought. The
parser is standing in exactly the same place refusing the next token it is
offered, and warm's first six blanks are six of those: `)`1492, `}`1498, `}`1502,
`}`1504, `extension`1507, an identifier at 1508. Four hundred rounds to reach byte
2,904 of 28,467, spent on aliases of one wall.

This matters past warm's own rows, because `../strand/RESULT-3-instrument.md` and
my own byte join both use *warm agrees* as the evidence that clears a cold wall.
An agreement that can be warm's own cascade convicts nothing.

## The falsifier: did the blank buy anything?

Both numbers are already on every round's parse, so it costs nothing to ask:
**blank this wall and does the parse close a root it could not close before, or
read a byte it could not read before?** Either alone is a purchase — a blank that
unlocks structure without moving the frontier is still a repair. Neither is a
cascade.

`Warm.bought` records it per round; `Warm.paid` is the subset of the seat a
purchase stands behind; `cut.stand` splits a byte-join match into `witnessed`
(paid) and `alias` (barren).

**1,812 of 1,983 priced warm rounds bought nothing — 91.4%.**

| grammar | rounds | barren | frontier |
|---|---|---|---|
| verilog | 400 | 393 | 12,466 |
| sql | 400 | 365 | 4,390 |
| haskell | 400 | 362 | 1,906 |
| swift | 400 | 355 | 2,904 |
| bash | 97 | 84 | 1,068 |
| markdown | 79 | 64 | 3,304 |
| ruby | 64 | 58 | 1,005 |
| zig | 46 | 38 | 16,125 |
| c | 35 | 31 | 1,444 |
| kotlin | 26 | 23 | 35,815 |
| cpp / julia / ocaml / scala | 19 / 15 / 15 / 3 | 11 / 14 / 13 / 1 | — |

Twenty-one grammars complete in one round and are not in the table. The four that
burn the budget are 89–98.5% barren, so **the budget is not being spent on depth;
it is being spent on one wall's aliases.** The `stranded` population's `witnessed`
bucket went from 15,527 B under the plain byte join to **2 B** under the purchase
test, and swift — 13,475 B of that 15,527 — contributes zero. A replicate below
gets 0 B rather than 2 B, so read that collapse as four orders of magnitude to
*at most* two bytes.

## The second falsifier, which is a presence rather than an absence

The lane before me named its own weakest instrument correctly: *the verdict is an
absence, and an absence from a bounded run looks stronger the weaker the run is.*
`Warm.frontier` bounds that absence honestly but cannot remove it. So the peel now
carries a falsifier of the opposite shape.

**`Cold.canopy`** is every span round 1 built a node over — round 1 alone, because
every later round's offsets are into a suffix this loop cut. If round 1, reading
the file nobody touched, **consumed a token at byte B**, then it did not refuse at
B, so a later round refusing at B is refusing in text the peel made. A shorter run
cannot manufacture that evidence; it can only fail to find it. One parse per
grammar, no blanking, no budget, and no cascade, and it rides on a parse the peel
was already doing.

**It convicts four walls corpus-wide, and its abstention is the interesting
result.** Round 1's forest on `Chunked.swift` covers `[1477, 1492)` and then jumps
straight to `[1507, 3501)` — a fifteen-byte hole over exactly the `)`, `}`, `}`,
`}` the cold peel walls on. The whole-file parse **also built nothing there**. It
mended over them instead, and `stamp.outcome` reports a mended parse's *first*
stop and nothing else.

So the sharper statement, which is neither the inherited one nor the one I set out
to make: **the cold peel is not inventing wall locations. It is inventing wall
attributions.** The bytes it stops at are bytes the whole-file parse also failed
to build over; what the fragment manufactures is the *terminal and the state*, and
therefore the owner, the family, and the price.

## The blocking hole, which is not mine to close

Deciding whether swift's `} in state 681` is the document's wall or the cut's
needs one thing this binary cannot do: **a whole-file parse that enumerates its
mend sites.** `joints parse` names the first stop; `--ranges --all` gives the
forest, which shows a hole but not what refused in it; `joints amend` takes an
edit and is a different question. Every instrument in `tool/` is downstream of
that verdict, so all three of them — cold, warm, and canopy — are working around
one missing number.

That is `src/`'s to add and I have not touched it. Until it exists, 18,146 B of
the board (15.0%) is `untested` and should stay that way rather than being
credited to whichever instrument is cheapest to run.

## Predictions, scored

**P7 — over half of warm's rounds barren, over 80% on the budget four. RIGHT, and
under-predicted.** 91.4% corpus-wide; 89.0% (swift) to 98.5% (verilog) on the
four.

**P8 — `witnessed` falls below 3,000 B and swift contributes 0. RIGHT.** 2 B, and
swift contributes 0.

**P9 — nothing moves into `document`; `document` under 4,000 B. HALF WRONG.**
Nothing moved into `document` (it is definitionally round 1). But it is
**4,749 B**, not under 4,000 — markdown's single 3,284 B round-1 wall is 69% of
it, and I did not think about the one-wall grammars when I guessed.

**P10 — `untested` beats `torn` on the four budget grammars and loses everywhere
else. WRONG on two counts.** It beats `torn` on haskell (4,211 vs 0), sql (93 vs
4) and swift (13,406 vs 0) but **loses on verilog** (356 vs 7,292) — verilog's
frontier is 12,466, far enough in that most of its walls are inside warm's view
and get a real verdict. And cpp, which is not budget-bound, has `untested` 80 vs
`torn` 0 because its warm run ends on `unclosed, which names no byte` at byte 795.
The clean statement is *frontier position decides this, and the budget is only one
of the things that shortens a frontier.*

**P11 — 80–93% instrument, and a number above 96.3% should be disbelieved.
RIGHT.** 81.1% corpus-wide, and the `stranded` column specifically comes out at
**39.9%** — well under the inherited 96.3%, as a widening that carves out its own
blind spot should.

Four of five here, and P9 and P10 are both magnitude misses. Across both
prediction files: **eight of eleven.** The three misses are P2 (three orders of
magnitude, and the one I would have published), P6 (8× on a runtime) and P10
(a mechanism I had half right).

## An unplanned replicate: `witnessed` does not reproduce

The warm survey ran twice under the same pin, ten minutes apart, because the
first run was backgrounded and I re-ran it rather than wait
(`.local/reprice/warm.json` at 20:54, `warm2.json` at 21:04). Both cover all
thirty grammars. That is a replicate nobody designed, and it is worth more than
the run I meant to take.

Everything is byte-identical across the two: `document` 4,749 B, `torn` 37,433 B,
`untested` 18,146 B, the roofed subset 3,910 B, and all four owner columns'
standing totals (734 / 6 / 3,480, `stranded` aside). **The single exception is
`witnessed` — 0 B on the first run, 2 B on the second**, and the two walls are
exactly the two this dossier tabulates:

| grammar | wall | bytes | run 1 | run 2 |
|---|---|---|---|---|
| scala | `" in state 1791` | 1 | `alias` | `witnessed` |
| zig | `} in state 83` | 1 | `alias` | `witnessed` |

So the `stranded` column's standing figure is **114 B or 116 B depending on the
run**, and the board's floor is 4,749 B or 4,751 B — a 0.002% spread on the
headline, which is stability I did not earn and will take. The finding is the
other direction: **`witnessed` is the only verdict where the warm peel adds a
standing byte the canopy did not already supply, that population is two bytes,
and it is not reproducible.** `Seat.bought` decides it by comparing roots and
reach between rounds, and on a one-byte wall a single root's difference flips
the answer — on a board where two shards are known to flap on byte-identical
source.

I am not pinning either value. Both are honest readings of the same instrument
and the disagreement is the result: read `witnessed` as *at most 2 B*, treat the
warm peel as contributing nothing dependable to the standing side of this table,
and note that this is a measurement of the claim below rather than an argument
for it — the canopy carries the table because the warm peel's positive verdict
does not survive a second run.

## The instrument I trust least

**`Cold.canopy`, the falsifier I added.** It passed its own check — it convicts
four walls, it abstains on the swift rows, and its arithmetic is auditable
(`Cold.under` sums to 27,428 of 28,467 bytes on swift). None of that clears it,
for one reason: **a node in a mended forest is not a claim that the text under it
is right.** A mend puts the stack down and starts again, so the parser chooses
where its own nodes begin, and a node beginning at byte B means "the parser
resumed here", which is *nearly* but not exactly "the parser did not refuse here".
On a heavily mending grammar — verilog mends 2,109 times — I cannot currently
distinguish a node the parse built by shifting into it from a node it built by
recovering onto it, and the second kind would convict a wall the document really
has.

It errs toward calling a wall `torn`, which is the flattering direction for a
re-price whose headline is *most of this board is the instrument*. That is the
same failure-mode alignment I criticised in the warm peel's absence, and the only
honest thing to do about it is say so, keep the convictions to four rows, and
leave the 18,146 B `untested` where the missing mend-site enumeration leaves it.

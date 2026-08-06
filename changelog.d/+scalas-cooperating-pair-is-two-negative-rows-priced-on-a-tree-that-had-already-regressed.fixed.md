Scala's pair was reported at residual **+5,500** and called *cooperating*. Read
the signs on the row it came from: `worth(_indent/.offside/.slashes)` is
**−4,970** and `worth(block_comment/.marrow/.kotlin_block)` is **−10,326**, and
negative means removing the row *reduces* scala's damage. Both seatings are net
harmful on that snapshot, so the sub-additivity is two harms overlapping rather
than two benefits compounding - you cannot spoil the same bytes twice.

They overlap because `Option.scala` is **15,872 of 20,107 bytes inside a block
comment** (79%), with 499 of its 629 lines opening on a comment glyph. Both rows
act on that one region and neither consults the other: the marrow row lexes each
`/* … */` into a token, and `offside.lead` skips comments *itself*, from raw
bytes, with its own nesting-aware walk. `Note.slashes` is a spelling, not a
subscription. On a scala fixture with indentation and no comment the pair is
additive and `worth(block_comment)` is **0** exactly; it is 0 on two more
fixtures including one where a non-nesting reader would swallow an `object`
declaration.

Also worth knowing before quoting either number: the pair arms were pinned from
a snapshot where **scala's control damage is 16,883**, where the fourteen-arm
table days earlier had it at **4,150**. Elixir moved 0 → 8,795 over the same
gap. Same seatings on both days, so something un-seated regressed them - the
press regression already handed over in `vacuity/RESULT-3-press.md`. Two
consequences: figures from `RESULT-2-arms.md` and `RESULT-5-pairs.md` must not
be subtracted from each other, and scala's pair wants re-pricing once the press
clears. Until then the honest word for scala's two seatings is *unknown*, not
*cooperating*.

For scala, unlike kotlin, `built` is not monotone in reach either - the arm that
stops earliest (byte 75) builds the most (13,550 against the control's 3,224)
while also describing 4× the nodes, so a scala `worth` is not a
distance-to-first-wall number and cannot be read as one.

`research/joinery/consort/RESULT-3-scala.md`.

# Result 3 — scala's pair is two overlapping regressions, priced on a broken tree

> **Holds, and its own open question is now answered (2026-08-06).** This page ends
> by refusing a verdict: *"Both rows may well be positive on a healthy tree; nothing
> here says they are not. Until then the honest statement about scala's seatings
> is unknown, not cooperating."* `RESULT-8-sighted.md` is that healthy tree, audited,
> and they are positive — **both of them, and by more than the file has to give:**
>
> | row | on the broken snapshot | on the audited base |
> |---|---:|---:|
> | 0 `_indent/.offside/.slashes` | −4,970 `damage` | **+6,739 `square`** |
> | 4 `block_comment/.marrow/.kotlin_block` | −10,326 `damage` | **+6,536 `square`** |
> | pair residual | +5,500 | **+6,547** |
>
> 6,739 is scala's *entire* agreement with tree-sitter, so **each row alone accounts
> for nearly all of it and the pair is a ceiling** — sub-additive, as this page
> said, but a ceiling of benefit rather than an overlap of harm. The sub-additivity
> mechanism it derived (two independent readers of one dominant construct, 79%
> of the file) is what a ceiling *is*, and it transfers intact.
>
> Two signs flipped here, which is the largest inversion this lane found: ocaml's
> fragment flipped one row from a 721-byte loss to a 448-byte gain, and this page's
> two rows go from *net-harmful* to *worth every byte of agreement scala has*. Both
> flips are the same mechanism — a `damage`-only reading of a comment is biased
> in a known direction — and this page is where it cost the most,
> for the reason the page itself names: `Option.scala` is 79% block comment.
>
> The word *unknown* was the right call and it is discharged. Nothing here was
> re-measured, and the press regression this page hands back is still `src/press/`'s.

## The claim

`vacuity/RESULT-5-pairs.md`: `worth(0) = −4,970`, `worth(4) = −10,326`,
`joint = −9,796`, residual **+5,500**, verdict *cooperating*.

`gate.py` re-derives all four numbers to the byte off the retained pins, so the
arithmetic is not in question. Two other things are.

## Read the signs first

Every one of those numbers is **negative**, and negative means removing the row
*reduces* scala's damage:

| arm | first stop | built | of 20,107 | nodes | roots |
|---|---|---:|---:|---:|---:|
| both in | 9,441 | **3,224** | 16.0% | 1,305 | 281 |
| row 0 out (offside) | 314 | 8,194 | 40.8% | 1,569 | 315 |
| row 4 out (block comment) | 75 | **13,550** | 67.4% | 5,784 | 1,273 |
| both out | 75 | 13,020 | 64.8% | 5,426 | 1,315 |

On this snapshot **both scala seatings are net harmful**, on `built` and on node
count together - so this is not the "one enormous construct over the wreckage"
shape `standing.py`'s own docstring warns about. The pair sweep's word
*cooperating* is describing two harms that overlap, not two benefits that
compound. Sub-additive damage is what you get when two rows spoil the same
bytes: you cannot spoil them twice.

Note also that the arm which stops **earliest** (byte 75) builds the **most**.
For scala, unlike kotlin, `built` is not monotone in reach, so a scala worth is
not a distance-to-first-wall number at all.

## The mechanism: same bytes, no shared state

| row | seat | terminals |
|---|---|---|
| 0 | `_indent/.offside/.slashes` | `_indent` `_dedent` `_newline` |
| 4 | `block_comment/.marrow/.kotlin_block` | `block_comment` `_suppress_block_comment` |

Disjoint. And the coupling I predicted (P9) - that the offside hand's
comment-skipping consults what the block-comment row lexed - is **wrong**.
`offside.lead` skips comments *itself*, from raw bytes, with its own
nesting-aware `through()`; `Note.slashes` is a spelling, not a subscription. The
two rows never exchange a byte of state.

What they share is the **file**. `Option.scala` is 20,107 bytes of which
**15,872 (79%) sit inside a block comment**, and 499 of its 629 lines open with
a comment glyph - a fact `offside.zig`'s own docstring already records. Both
rows act on that same region:

- the marrow row lexes each `/* … */` into one token;
- the offside row reads through each `/* … */` to find the real column of the
  code after it.

Two independent readers of one dominant construct. Their effects cannot add,
because there is only one comment population to get wrong.

## Falsifier — single-construct fixtures

| fixture | worth(0) | worth(4) | joint | residual |
|---|---:|---:|---:|---|
| `witness/scala-indent-only.scala` (indentation, no comment) | 48 | **0** | 48 | **+0** |
| `witness/scala-comment-only.scala` (nested comment, flat code) | 0 | **0** | 0 | **+0** |
| `witness/scala-nested-comment.scala` (comment hiding code) | 70 | **0** | 12 | −58 |
| `Option.scala` | −4,970 | −10,326 | −9,796 | **+5,500** |

The offside row carries the whole worth on a fixture with no comment, and the
pair is additive there. And on all three small fixtures `worth(4) = 0` exactly -
even the one where a non-nesting reader would swallow an `object` declaration.
So the block-comment row's −10,326 on `Option.scala` is not the row doing
block-comment work; it is the row changing where a 20 KB parse gives up.

## The larger problem, handed back rather than chased

The pair arms were pinned from a snapshot on which **scala's control damage is
16,883**. The fourteen-arm table in `vacuity/RESULT-2-arms.md` was taken days
earlier with scala's control at **4,150**. Same seatings, both days.

| grammar | control on the fourteen-arm day | control on the pair-arm snapshot |
|---|---:|---:|
| scala | 4,150 | **16,883** |
| elixir | 0 | **8,795** |
| kotlin | 246 | 244 |
| swift | 5,337 | 5,337 |
| ocaml | 2,182 | 2,182 |

Something un-seated regressed scala by 12,733 bytes and elixir by 8,795 between
those two days - `RESULT-5` names a press regression that was live on its
snapshot, and `vacuity/RESULT-3-press.md` is the handover. So scala's +5,500
residual, and both of its negative worths, describe a tree in that state. They
are not evidence about the two seatings on a healthy tree, and `src/press/` is
not this lane's.

Two consequences worth writing down:

1. **The fourteen-arm table and the pair table are not one measurement.** Their
   controls differ by 4× on scala and by 8,795 bytes on elixir. Numbers from the
   two pages should not be subtracted from each other, which is a second way
   that `worth` column can be misread.
2. **Scala's pair should be re-priced once the press regression clears.** Both
   rows may well be positive on a healthy tree; nothing here says they are not.
   Until then the honest statement about scala's seatings is *unknown*, not
   *cooperating*.

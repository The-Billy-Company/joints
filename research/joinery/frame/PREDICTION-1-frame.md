# Prediction 1 — a frame that was never built

Written before any of it was measured. Pin `frame` (`cf697da9f577`, tree
`986eb8ece1`), which reproduces `rack`'s published split to the byte:
265,603 square + 47 renamed + 44,059 askew + 39,110 racked + 35,896 unjudged
= 384,715 built, **83,169 crooked**.

## The hole, restated so the fix can be judged against it

`rack` compares spines **inside built windows**, one window per built root, and
`within()` drops every rung as wide as the window or wider on both sides. That
drop is load-bearing - it is what stopped zig charging 11,914 bytes to a frame
disagreement the two parsers have by construction - and it is also the hole. A
node joints never built is in no window, so it is dropped from the oracle's
side and nothing on ours ever stood where it was.

`research/joinery/specimen/html/erroneous-end-tag.html`, nine bytes, reproduced
today on this pin:

```
built 7 · square 7 · askew 0 · racked 0 · brackets 6/6 · frames 2 · framed 0
```

The oracle reads one `element [0, 8)` over three children; joints reads the
three children as three roots and no `element`. `framed` reads 0 because
`their_frame` is the *tightest* oracle bracket containing each window, which is
`start_tag [0, 3)` - the same name we have. So the column that looks like it
should notice is looking at something else, correctly.

## The rule I am going to add

**A frame is missing when the oracle has a bracket, other than its own root,
that wholly contains two or more of joints's built roots, and joints has no
node with that extent.** Its built bytes are charged to a new bucket,
`unframed`, taken **only** from `square` and `renamed`.

Three deliberate narrownesses, each of which can be wrong in the direction that
makes me look good, so each gets a prediction:

- **depth 0 is excluded.** tree-sitter always returns one tree and joints
  returns a forest on 18 of 30 grammars; the oracle's own root is that
  difference and nothing else. `orphan`, `rubble` and `spoil` price it already.
- **wholly contains two roots**, not overlaps two. A bracket that covers one
  root and half of the next is a regrouping the spine walk inside the second
  window already has an opinion about.
- **taken only from `square` and `renamed`.** A byte the walk already calls
  `askew` or `racked` keeps that verdict; a byte the walk calls `unwindowed` or
  `unjudged` keeps that one too. So `askew` and `racked` must not move by a
  single byte, and the number I am adding is a floor by construction.

## The predictions

| | claim | falsified by |
|---|---|---|
| **P1** | the html specimen charges **7 of 7** built bytes `unframed`, and its `square` goes 7 → 0 | any other pair of numbers |
| **P2** | corpus-wide `askew` stays **44,059** and `racked` stays **39,110**, exactly | either moving by one byte |
| **P3** | at least one grammar that reads **0 crooked today stops reading 0**. My candidates are `c` (10 frames, 872 built, all square) and `markdown` (14 frames, 178 built, all square) | every zero-crooked grammar still reads zero |
| **P4** | **none of the twelve grammars the board reads at 100.0% standing moves**, because all twelve build exactly **one** frame and a rule keyed on the seam between two roots cannot fire without a second root | any of the twelve moving |
| **P5** | `haskell` is the widest new charge by bytes - 624 frames over 9,192 built, a frame every fifteen bytes, and 1,013 bytes already `unwindowed` | another grammar charging more |
| **P6** | corpus-wide `unframed` is **under 38,471 bytes** (10% of `built`). A new bucket that charges freely is the failure mode next to this one | 38,471 or more |
| **P7** | `unframed` is **less soft** than `crooked`'s 27.7%: a missing construct is not a comment hanging in two places | the soft share of `unframed` reaching 27.7% |
| **P8** | the corpus `viewer.html` row stays at **72,288 square, 13,971/13,971 brackets, 0 crooked**. html is believed clean for a reason and most of it really is | html reddening at all |

**P4 contradicts the brief.** The brief asks which grammars currently reading
clean stop reading clean and says that if html is not the only one, that is the
finding. I predict the corpus cannot answer that question at all in either
direction for the twelve, because every one of them hands back a single root -
and that structural fact, not a count of newly-dirty grammars, is what the
measurement will actually establish.

## What would make me distrust the result

A grammar charging its whole file to one depth-1 wrapper node. If tree-sitter's
root has a single `program`-shaped child covering everything and joints hands
back a forest, my rule charges the entire file for what is really the
forest-versus-tree difference wearing a new name. I will look for exactly that
shape before quoting any total, and if it is there I will name it and hold it
out rather than average it in.

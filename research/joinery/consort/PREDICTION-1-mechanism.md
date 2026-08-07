# Prediction 1 — why two rows interact, written before a measurement

`vacuity/RESULT-5-pairs.md` priced five pairs and found two that are not the sum
of their parts: kotlin at −20,288 residual and scala at +5,500. It did not say
**why**, and a residual with no mechanism behind it is a number waiting to be
re-derived by the next lane. This lane owes the mechanism, a resized claim
wherever kotlin's seating is credited solo, and a verdict on swift's inert row.

Everything below is written before I build or run anything. The retained pins
under `.local/aud-iso/joints/.local/pin/` make every arm re-derivable with no
rebuild, so there is no excuse for scoring these generously.

## What is already arithmetic and is therefore not a prediction

`arms.json` and `pairs.json` already contain, for kotlin, `D(none) = 244`,
`D({2}) = 20,981`, `D({12}) = 19,473`, `D({2,12}) = 19,922`. Those four numbers
already say the standalone worths:

- row 2 (`_string_start/.fence/.kotlin`) with row 12 **absent** is worth
  `19,922 − 19,473 = +449 B`;
- row 12 (`_automatic_semicolon/.caesura/.kotlin`) with row 2 **absent** is worth
  `19,922 − 20,981 = −1,059 B` — a regression.

I am stating that here so I cannot later present the subtraction as a discovery.
What is genuinely unknown is *why*, and every P below is about that.

## Kotlin

**P1 — the two rows do not compete for a terminal.** Their required terminal
sets, as `ablate.needs()` computes them, are disjoint. Falsifier: any name in
both.

**P2 — the coupling runs one way through consumption, and it is the fence that
protects the caesura.** Kotlin's caesura row spells no `hushed` list, where
ecma's spells `_template_chars` and `jsx_text` precisely so a break is never
inserted inside a template body. Kotlin's row is safe today only because the
fence has already eaten the string interior before the caesura is asked. So with
the fence removed, `_automatic_semicolon` fires at newlines the fence would have
consumed. Falsifier: kotlin's caesura row turns out to carry a suppressor, or the
fence-out arms show the caesura firing nowhere new.

**P3 — that is why row 12 alone is negative.** Removing the caesura from a
fence-less tree *improves* kotlin, so the caesura-in / fence-out arm (`aud-r2`)
should carry **more roots and more mends** on kotlin than the both-out arm
(`aud-r2-12`), not fewer. Falsifier: `aud-r2` has roots ≤ `aud-r2-12`.

**P4 — the live record already corroborates P3 and nobody joined it up.** The
caesura landing fragment records kotlin's `built` falling 1,075 bytes and its
standing falling three points when the caesura went in **before** the fence. That
is the same −1,059 the pair arm derives, measured by a different instrument on a
different day. Falsifier: the fragment says something else on re-reading.

**P5 — the record credits the solo figure in at least three places.** The
`worth` column in `vacuity/RESULT-2-arms.md` and in the fourteen-rows changelog
fragment lists both kotlin rows in one sorted column with no marker that the two
cannot be added; downstream dossiers quote −20,728 as what the fence is worth.
The honest number for kotlin's seating is the **pair's +19,678**, and a
Shapley split of it is +9,839 each. I predict I find ≥3 places needing the
qualifier and 0 places that are simply arithmetically false — the marginals are
each *true*, the sum is what is not.

## Swift's `multiline_comment`

**P6 — the row is alive, and the corpus is what is silent.** `tool/absent.py`'s
own header already says `Chunked.swift` contains no `/*`. The board therefore
cannot move whether the row is right, wrong or absent. Falsifier: a `/*` in
`Chunked.swift`.

**P7 — it is already exercised, by a specimen, and the pair sweep could not see
that either.** `research/joinery/specimen/swift/multiline-comment.swift` and
`nested-comment.swift` exist. Run against the retained `aud-r3` pin — the arm
with exactly this row deleted — I predict at least one of them goes **red**. If
they do, the row is not dead, `RESULT-5`'s "does nothing in any combination
available to it" is an over-claim scoped to the board, and the correct action is
to correct the sentence rather than delete the row.

**P8 — the row is at the right target.** Swift's 3,997 orphan bytes and 8,807
crooked bytes are not comment bytes; they belong to the separator and the
adjudication lanes. Falsifier: swift's orphan or crooked runs land on `/*`
spellings.

## Scala

**P9 — the same shape as kotlin, through the same organ: consumption.** The
offside row carries `note = .slashes`, which is the offside hand measuring a
line's indentation *through* comments. The block-comment row makes a `/* … */`
one token. With the comment row seated, lines inside a scaladoc block never
reach the offside hand as lines at all; with it gone, each of them is measured
and pushes or pops a column. So the two rows meet on the comment, not on a
terminal. Falsifier: `offside.Note` turns out not to be consulted at a line
start, or scala's fixture has no multi-line comment.

## The fourteen-row clearance

**P10 — it survives, and only as a statement about `damage` on the corpus
board.** Two further blind spots follow from the same construction, and neither
is about pairs:

- **The audit family never populated `square`.** Every arm was given its own
  `JOINTS_WORK` by the third house rule, `standing.py`'s audit overlay is a
  per-work-dir `audit.json`, and nothing re-ran `--audit` per arm. So every row
  of `arms.json` and `pairs.json` is `graded: —`, `square 0`, `unaudited =
  built`. The clearance is on joints's own words about its own forest and
  never on agreement with tree-sitter. I predict the retained base board shows
  `square = 0` on all thirty rows.
- **Corpus silence is indistinguishable from no collateral.** A row whose
  construct is absent from the corpus reads zero in *every* board arm, single or
  pair. Swift's row 3 is the standing proof, and it means "moves nothing"
  can never be upgraded to "changes nothing" by any arm of this family.

Falsifier for the first: a non-zero `square` anywhere in `.local/aud-iso/base-board.json`.

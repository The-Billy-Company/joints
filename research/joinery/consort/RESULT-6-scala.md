# Result 6 — scala's pair, re-taken on a clean tree with both arms sighted

`RESULT-3-scala.md` established that scala's pair was priced against a control
reading `damage 16,883` while the live board read `4,150`, and handed the
regression back rather than chasing it. The brief named it: an uncommitted
`src/press/` intermediate held a 12,733-byte scala regression for about ten
minutes, and 4,150 + 12,733 = 16,883 exactly.

`retake.py` re-takes the whole two-row population — both rows in, each one out,
both out — from a snapshot refreshed off today's `src/`, with `standing.py
--audit` paid inside each arm's own work dir so `square` is a number.

## The control was the only poisoned arm

| arm | built | damage | nodes | roots | square | crooked | graded |
|---|---|---|---|---|---|---|---|
| both in | 15,957 | **4,150** | 1,772 | 26 | **6,739** | 1,938 | read |
| row 0 out (offside) | 8,194 | 11,913 | 1,569 | 315 | **0** | 1,071 | read |
| row 4 out (block comment) | 13,550 | 6,557 | 5,784 | 1,273 | **203** | −335 | part |
| both out | 13,159 | 6,948 | 5,487 | 1,261 | **11** | 758 | part |

The two solo arms come back at **11,913 and 6,557 — the exact damages
`arms.json` recorded**. Both single-row arms were always right. What was wrong
was the number they were subtracted from, and the arithmetic follows:

```
was   control 16,883   worth  row 0 −4,970   row 4 −10,326   residual +5,500
now   control  4,150   worth  row 0 +7,763   row 4  +2,407   residual −7,372
```

So the answer to *"does the cooperation survive?"* is **no, and neither does
its sign**. The +5,500 residual was the regression counted twice: once in the
control and once out of each solo. The clean residual is −7,372, which by the
1,000-byte rule still prints `cooperating`, but it is now *sub*-additive rather
than super-additive, and it means the opposite thing — each row alone recovers
most of what both recover together.

The joint arm is the one place today's snapshot and the retained one really
differ: 6,948 here against 7,087 there, 139 bytes. Four files separate the two
trees, and a parse that has already lost both rows is close enough to floor that
a press regression has almost nothing left to spoil. That is the honest reading
of why the solos match to the byte and the joint does not.

## `square` says the residual is a ceiling, not a coupling

| | base | row 0 out | row 4 out | both out |
|---|---|---|---|---|
| square | 6,739 | 0 | 203 | 11 |
| Δ from base | — | **−6,739** | **−6,536** | −6,728 |

sum of solos −13,275, joint −6,728, residual **+6,547**.

Read that as coupling and you get nonsense. There are only 6,739 square bytes in
scala's whole fixture, and **each row alone costs essentially all of them** —
100.0% for the offside row, 97.0% for the comment row. Two rows cannot each
destroy 100% of a quantity and also sum. The residual is the ceiling pushing
back, and the two residuals having opposite signs (−7,372 on `damage`, +6,547 on
`square`) is the clearest statement available that the `damage` residual was
never measuring what it was quoted for.

What *is* true, and is now supported rather than inferred: the two rows are
mechanically entangled. `specimen/scala/offside-through-comment.scala` is
42 bytes carrying one block comment inside one indentation region, and it fails
under **either** row alone — the comment survives row 0's removal but the
template body does not survive row 4's. Forty-two bytes is small enough that
fixture layout cannot be the explanation, which is the objection the brief
raises against reading any residual off a `built` reach measure over one file.

## The node rise reproduces, and does not mean what it was read to mean

Removing row 4 takes scala from 1,772 nodes to **5,784** on a clean tree. The
original observation (1,305 → 5,784) was against the regressed control, which
was itself already a wreck — 3,224 built, 281 roots — so the low number was the
control being broken rather than the arm being whole.

The reading offered was *"a parser giving up early and reducing one huge
construct over the wreckage"*. It is not that, and the column that says so is
`roots`, which goes **26 → 1,273**. One huge construct is one root. Twelve
hundred roots, `built` falling 15,957 → 13,550, and `square` collapsing 6,739 →
203 are all the same event: the file is being shredded into small correct-looking
pieces hung in the wrong places. More nodes here is fragmentation, and it is the
direction `damage` is least able to see — the shredded arm's `damage` is *lower*
than the whole file's would be if the parse simply stopped.

## What this changes about `damage` as an instrument

Two of the three rows in `RESULT-7-witnesses.md` were negative-worth only
because their control was poisoned. The third was not, and it is the more
uncomfortable case: ocaml's comment row costs 721 bytes of `damage` and earns
448 bytes of `square`. `damage` rewards a wrong-but-large structure — the
un-seated arm lexes `(* … *)` into `mult_operator` and `value_path` nodes that
count as `built`, where the correct parse files the same bytes as an extra and
scores them `orphan`. On `damage` the broken arm wins by 721 bytes; on the only
column that is a claim about a second parser, it loses.

## The instrument I trust least: `crooked`

The row-4 arm above reads **`crooked −335`**. There cannot be a negative number
of misread bytes.

`crooked` is `rack`'s crooked total less the `soft` share attributed off the
crooked *runs* — extras placement, where a parser hangs a comment, which is an
internal choice rather than a claim about structure. On a shredded parse that
subtraction runs out of room: 1,273 top-level roots, blank and extra-named runs
everywhere, and the soft attribution exceeds the total it is being taken out of.

**And the board's own consistency check passed on that row.** It asserts
`square + crooked + soft + unframed + unaudited == built`, and −335 satisfies it
perfectly — 203 + (−335) + 1,353 + 3,878 + 8,451 = 13,550 = `built`, on the nose.
A bucket that borrowed from its neighbours totals just as well as one that did
not. That is why passing its own check did not clear it: the check was written to
catch a *redefinition* of `built`, and it is structurally blind to a
redistribution inside it.

A fourth assertion now runs beside the sum, and it is a strengthening rather than
a repair — the −335 still prints, and the board now says it is impossible:

```
CHECK       the audit splits `built` and does not redefine it: … == built on 29 of 29
**BROKEN**  and every part of it is a count: no negative bucket on 29 of 29 audited
            rows — BROKEN: scala crooked -335; the sum identity above cannot see
            this, because a bucket that borrowed from its neighbours still totals `built`
```

Green on the healthy control, red on the arm. The arithmetic in `rack.soft` is
another lane's, so it is named here and handed back rather than chased — but no
number off a row in this state should be quoted, including the `square 203` and
`crooked −335` in the table above. That is the caveat this lane's own headline
depends on: scala's *base* arm and the row-0 arm are `graded: read` with every
bucket non-negative, and they carry the 6,739 the argument rests on. The two
`part` arms are corroborating, not load-bearing.

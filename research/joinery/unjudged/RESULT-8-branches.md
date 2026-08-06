# Result 8 - the tripwire for the branch nobody tested, and the other branches

Scores [`PREDICTION-3`](PREDICTION-3-price.md) job 2. **`verify` holds 28 of 28
under the shipped rule; under the restored branch order exactly one row goes
red, and every other row - including all the pre-existing ones - stays green.**

## Why nineteen tripwires could not have caught this

Not one of them mentioned the branch. `rack.survey`'s walk asked *"did the
oracle have anything to say inside this window"* before it asked *"is the frame
overhead one we failed to build"*, so the column could be 97.9% mislabelled with
every gate green. A gate that passes because it never looked is the failure mode
this repository has retired six instruments for in two days, and it is
indistinguishable from a gate that looked and approved.

## The falsifier is corpus-shaped, not row-shaped

Written against the lesson [`RESULT-5`](RESULT-5-tripwire.md) paid for this
morning: **a red pinned to a named row is a red a sibling can delete.** The
`engulf` tripwire named elixir, a press change let elixir build its `do_block`,
and the assertion failed for a reason that had nothing to do with what it
guarded. Naming haskell here would have bought the same bug.

So the population itself is asserted. `rack.py verify` now measures the disputed
bytes over the whole slate and says:

```text
ok  the disputed population exists to be priced: 1486 byte(s) over 9 row(s) sit
    under a frame we never built with our own structure and none of the oracle's,
    widest haskell 998
ok  no byte reads as silence while standing under a frame we never built:
    0 sheltered of 1486
ok  re-pricing moves nothing else on haskell: square 5 either way, and crooked
    2174, and unjudged 0
ok  and it moves exactly the disputed bytes: unframed 5991→6989, unwindowed
    998→0, shade 998
ok  and `--price=sheltered` restores the branch order rather than approximating
    it: 998 of 998 sheltered under the retired rule, 0 under this one
ok  `unwindowed` still means something on its own: 26 byte(s) over 3 row(s) are
    the oracle framing a window from outside with no missing frame of ours
    under them
```

Two columns exist only to make this checkable. **`shade`** is the disputed
population and does not move with the price at all - it is the same bytes under
either rule, which is the whole point the previous lane was making. **`shelter`**
is how many of them the *active* price still files `unwindowed`, so the
assertion is `shelter == 0` and it is a statement about the shipped rule rather
than about any grammar.

The last line is the anti-vacuity half, and it is the one that would catch the
opposite mistake. A rule that charged *every* unwindowed byte would satisfy
`shelter == 0` trivially; 26 bytes over three rows survive as genuine
`unwindowed` - the oracle framing a window from outside with no missing frame of
ours underneath - so the column still means something and was not abolished.

## Broken on purpose

```bash
python3 tool/rack.py verify --price=sheltered
```

```text
FAIL  no byte reads as silence while standing under a frame we never built:
      1486 sheltered of 1486 — haskell 998, verilog 395, cpp 38, ocaml 27,
      swift 14, julia 8, sql 3, ruby 2, bash 1. THE RETIRED BRANCH ORDER IS IN
      FORCE: `unwindowed` reads as the oracle's silence and is a charge.

27 of 28 held
```

**One row red, and it names all nine grammars and the exact byte count.** The
other 27 stay green, which is the finding restated as an experiment: the
pre-existing tripwires cannot see this branch, so restoring the defect does not
move them. The assertions that internally compare the two prices also stay green
under either global rule, which is correct - a check that compares hot against
cold must not itself depend on which one is default.

`--price=sheltered` is the retired branch order, not an approximation of it.
That is asserted rather than assumed: 998 of 998 of haskell's disputed bytes
land back in `unwindowed` under it, and 0 under the shipped rule.

## The other branches, audited

`bucket()` now exists as one function because the order **is** the content, and
because a second copy of the rule already lives in
[`../flag/spans.py`](../flag/spans.py) - it re-implements the walk to file one
record per interval and does not have the `missing` test at all, so what `rack`
calls `unframed` that file calls `square`. An unwatched second copy is how this
tree has arrived at two instruments spelling one word two ways, repeatedly and
always in the flattering direction.

Four branches decide a bucket. Three of them were already asking `missing`
first; one was not, and it is fixed. The remaining question was whether `blind`
- tested before all of them - has the same shape.

**It does have the same population, and it should not move.** Of the 4,712 bytes
the oracle could not adjudicate, **3,735 (79.3%) also stand under a frame we
never built** - verilog 3,617, sql 118, nothing else. That is the identical
overlap, on a much bigger population than the one the re-pricing moved.

It stays where it is, for a reason that is measured rather than argued:

```text
verilog: mute 3617  via `them is None` 0  via an ERROR arm 3617
sql:     mute 118   via `them is None` 0  via an ERROR arm 118
```

**100% of the overlap arrives through the ERROR arms and none of it through
"the oracle has no node here."** In the `unwindowed` case the oracle's frame
*is* its verdict - it built a construct there and we did not - so the frame is
evidence. In the ERROR case the oracle's own tree is damaged over the byte, so
the frame is not evidence about us, and charging it would be this file deciding
a byte the second parser never adjudicated. The day `square`'s denominator
includes bytes no oracle judged is the day it stops meaning anything.

Counted rather than moved, therefore, and counted **in the instrument** as
`mute` rather than in a dossier a future lane has to rediscover. `verify`
asserts it exists and asserts it is a subset of `unjudged` on every row, never a
second charge for the same byte.

## Predictions, scored

| | claim | |
|---|---|---|
| P2.1 | the falsifier is corpus-shaped, not row-shaped | **right** |
| P2.2 | broken on purpose, exactly the shade-bearing rows go red, all pre-existing stay green | **right** - 1 of 28 red, and it names all nine |
| P2.3 | the same shape lives in `unjudged`; over 1,000 bytes, concentrated in verilog and sql | **right** - 3,735, and verilog+sql are 100% of it |
| P2.4 | 100% of it arrives through the ERROR arms, none through `them is None` | **right**, exactly |
| P2.5 | and it should NOT move | held, on P2.4's mechanism |

Five of five. P2.4 is the one that mattered: it was written as the mechanism
argument that would decide P2.5 either way, and had it come back with bytes
under frames the oracle builds *outside* an ERROR subtree, the branch would have
had to move.

## One repair that is not in the brief

The red tripwire was pinned to `specimen/go/selector-field.go` -
`fmt.Print("x")` read as a `type_conversion_expression` over a `qualified_type`,
100.0% standing, zero damage, 5 misread bytes to `plumb` and the whole call to
this file. **A press lane fixed go and the witness dissolved.** The specimen now
scores 60 square of 60 built and agrees with the oracle node for node, so four
assertions written against it went red for the best possible reason.

That is the second falsifier on this file a sibling has deleted by fixing the
product, and picking a different row only picks the next one to be deleted. So
the claim is asked of the corpus: some row must carry `racked` bytes - the
deepest node agreed on both sides, a node above it not - and `plumb`, which
compares only that deepest node, must charge the **same file** strictly less.

```text
ok  some row is charged for a shape its leaves agree about: elixir carries
    22089 racked byte(s)
ok  and the byte-indexed instrument scores the same file cleaner: `plumb`
    charges 0 misread where this charges 22210 crooked
ok  and the widest runs say so at a rung ABOVE the leaf: 9 of 18 carry kind
    `racked`
```

The dissolved witness is kept as the regression guard for the fix that
dissolved it: the day go reads a call as a conversion again, `60 square of 60
built, 0 crooked` stops holding and that line says so. Note that this
particular red currently lands on elixir, whose baseline is unstable and in
flight - which does not matter here, because the assertion is about whichever
row is widest and not about elixir.

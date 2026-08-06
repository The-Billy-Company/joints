# Result 6 - haskell's 1,013 bytes were never unjudged

Scored against [PREDICTION-2](PREDICTION-2-rederive.md) P4.1–P4.2. Same arm as
[RESULT-3](RESULT-3-rederive.md) (`outliner 94d59d9ad`, oracle `d85e736fa`).
Tool: [`unwindowed.py`](unwindowed.py), which walks the same windows
`rack.survey` walks and files each byte the same way, keeping the runs and the
oracle's own frame over each one.

> **haskell's `unjudged` is 0. All 1,013 bytes are `unwindowed`, and all 1,013 of
> them sit under a frame the oracle has and we never built - so they are
> `unframed`'s own population, reaching a branch of the walk that is checked
> before `missing[p]` is.**

## Where the number came from

`Seen.blind` is `unjudged + unwindowed`, and the `NOT JUDGED` block printed
`blind` under one sentence - *"carry no oracle verdict"* - with the reason column
reading `plumb rule, byte by byte`. Both halves of that line were wrong for
haskell. No plumb rule fired on any of its bytes:

| | haskell |
|---|---|
| built | 9,192 |
| `unjudged` | **0** |
| `unwindowed` | **1,013** |
| runs | 295 (widest 30 bytes, then 28, 23, 23) |
| windows | 624 |

## What `unwindowed` actually is

From `survey`, in the order the branches are tested:

```text
o_sp[k] == t_sp[k]  →  missing[p] ? unframed : square
not t_sp[k]         →  unwindowed          ← here
excused(...)        →  missing[p] ? unframed : renamed
otherwise           →  askew / racked
```

`unwindowed` is *"the oracle has nothing strictly inside this window here and
outliner does"*, and its docstring is right that the oracle's silence inside a
window is not a verdict. What the column cannot say is **why** the oracle has
nothing inside: on every one of haskell's 295 runs the narrowest oracle bracket
covering the window is the oracle's own root, `haskell`. `within` drops a rung
that spans the window - correctly, because a forest and a tree disagree about a
root's extent by construction - and what is left inside is empty. So the oracle's
structure at those bytes **is** the frame we did not build.

That reading is measurable, and it is not haskell-specific:

| row | `unwindowed` | of those, under a frame we never built |
|---|---|---|
| haskell | 1,013 | **1,013** (100%) |
| verilog | 111 | 110 |
| cpp | 42 | 38 |
| swift | 35 | 35 |
| ocaml | 27 | 27 |
| ruby | 23 | 2 |
| julia | 8 | 8 |
| sql | 3 | 3 |
| bash | 1 | 1 |
| kotlin | 1 | 0 |
| **corpus** | **1,264** | **1,237 - 97.9%** |

Our own deepest node over those bytes is `apply` (172 runs), `variable` (107),
`case` (12), `negation` (3), `match` (1), and 221 of the 295 runs are one level
below the frame. In content they are two things: whitespace runs we hung under a
node, and token-interior positions where we split an identifier tree-sitter keeps
whole (`ilesInArchive`, `efinitionList`).

## So: a third mechanism, and not the kind the dossier was collecting

The other two entries here are **reader defects** - our arithmetic against
tree-sitter's renders. This one is neither a reader defect nor an oracle
limitation. It is a **classification** in `rack.survey`, and it leans the
flattering way:

> Building **more** structure under a frame you are missing moves bytes out of
> `unframed`, which is a charge, and into `unwindowed`, which reads as silence.

Same bytes, same missing frame, and the column depends on whether we put anything
of our own underneath. That is the family this tree has retired six instruments
for, so it belongs in the record whether or not anyone reclassifies it.

## What was changed, and what deliberately was not

**Changed - the report stops mislabelling it** ([`tool/rack.py`](../../../tool/rack.py)):

```text
NOT JUDGED - 5564 of 396158 built bytes (1.40%) got no verdict: 4300 `unjudged`, where the oracle
had nothing to say, and 1264 `unwindowed`, where it framed the window from outside and we built inside it.
Only the first is the oracle's silence about the byte; most of the second is `unframed`'s
own population under another name. ...
  verilog                4293   14.0% of 30720  unjudged 4182   unwindowed 111     plumb rule, byte by byte
  haskell                1013   11.0% of 9192   unjudged 0      unwindowed 1013    no oracle refusal at all - every byte is unwindowed
```

The reason column is now derived from the row's own split rather than being a
constant, which is what let haskell read `plumb rule, byte by byte` for a day
with a plumb count of zero.

**Not changed - the classification itself.** Charging these bytes `unframed`
would be the stricter and probably the correct rule, and it is a one-line move:
test `missing[p]` in the `not t_sp[k]` branch as the two branches around it
already do. I have not made it, for one reason: **it moves `unframed` on ten rows
while three lanes are holding baselines against this board**, and a re-price is
not this lane's to spend on someone else's behalf without saying so first. The
finding is written down, the report no longer misreads it, and the change is
whoever's who wants to re-pin the board for it.

## Scoring

| | claim | verdict |
|---|---|---|
| **P4.1** | ≥ 90% of the 1,013 comes from `plumb`'s ERROR-taint arms, so tree-sitter cannot parse haskell's own corpus file; **not** a third mechanism | **wrong, on the premise.** 0% comes from any plumb arm - haskell's `unjudged` is exactly 0, and the oracle parses its corpus file cleanly. It *is* a third mechanism, in `rack`'s classification rather than in either reader. I predicted the wrong column and the wrong instrument. |
| **P4.2** | not one wide node; fewer than 20 maximal runs | **half.** Not one wide node - the widest run is 30 bytes of 1,013, so nothing here is one node standing over a row. But 295 runs, not "fewer than 20": I reasoned from `ERROR` taint being contiguous, and this is not taint at all, so the shape argument was inherited from the wrong mechanism. |

Nought for two on Job 4, and the load-bearing miss is the same one the previous
lane made: I predicted a mechanism from the name of a column instead of reading
what the column counts.

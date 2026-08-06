# Result 7 - the re-priced board

Scores [`PREDICTION-3`](PREDICTION-3-price.md) job 1. **Nine rows move, 1,486
bytes, and `square` does not move on any row.**

Arm `shade`: binary `c1041f198` over tree `86c6f3e81`, oracle `d85e736fa`,
tree-sitter 0.26.11, seat `pin-shade`, 30 of 30 verdicts live. The arm was
pinned before the control, because the control does not exist - see below.

## There is no before-arm and no after-arm

The re-pricing is a **Python-side reclassification of one parse**, so the
strongest available form of this comparison is not a pair of boards. It is one
board classified twice:

```bash
eval "$(python3 tool/pin.py arm shade)"
python3 tool/rack.py reprice
```

`rack.py reprice` calls `plumb.read` **once per grammar** and hands the single
`Read` it gets back to `survey` under both rules. Same forest, same oracle tree,
same windows, same renames, same bytes. There is no term in the delta for a
sibling landing a press change between two runs, which is the term that cost a
lane twenty minutes this morning and is the reason
[`TESTING.md`](../TESTING.md) says to pin the control after the arm.

Two `--price=` boards taken three minutes apart agree with it to the byte on
every column, which is worth saying because it is the falsifiable half: if the
one-parse form and the two-run form had disagreed, the disagreement would have
been a sibling's commit and not the rule.

## The nine rows

| grammar | `unframed` | `engulf` | `unwindowed` | share of judged |
|---|---|---|---|---|
| haskell | 5,991 → **6,989** | 5,941 → 6,929 | 998 → **0** | 26.61% → 23.71% |
| verilog | 11,751 → **12,146** | 8,564 → 8,664 | 396 → **1** | 48.77% → 48.08% |
| cpp | 179 → **217** | 114 → 146 | 42 → **4** | 61.88% → 59.52% |
| ocaml | 320 → **347** | 13 → 14 | 27 → **0** | 14.89% → 14.86% |
| swift | 1,179 → **1,193** | 1,179 → 1,193 | 14 → **0** | 38.26% → 38.24% |
| julia | 857 → **865** | 857 → 865 | 8 → **0** | 0.63% → 0.63% |
| sql | 992 → **995** | 607 → 607 | 3 → **0** | 4.52% → 4.52% |
| ruby | 229 → **231** | 229 → 231 | 23 → **21** | 31.18% → 31.05% |
| bash | 118 → **119** | 118 → 119 | 1 → **0** | 11.62% → 11.60% |

Corpus: `unframed` 22,080 → **23,566**, `unwindowed` 1,512 → **26**, `blind`
6,224 → **4,738**, `judged` 393,647 → 395,133, crooked share of judged 15.249%
→ **15.192%**.

**1,486 of 1,512 - 98.3% - of what the retired rule filed as the oracle's
silence was a charge against us under another name.** The previous lane measured
97.9% on its own arm; the population grew with the tree and the fraction did
not move.

### The twenty-one columns that did not move

`reprice` derives this list from `Seen._fields` rather than carrying it in
prose, so a column added tomorrow is checked tomorrow:

> size, built, **square**, renamed, askew, racked, unjudged, shade, mute,
> stretch, airy, gap, ours_nodes, their_nodes, shared, frames, framed, crooked,
> damage, honest, text

**`square` is byte-identical on all thirty rows: 311,540 either way.** So is
`crooked`, at 60,027. That is not a coincidence and it is not luck about which
rows happened to move: the branch that was re-pointed is reached only where the
oracle has *nothing* inside the window, which is disjoint from every branch that
can produce a square or a crooked byte. If `square` had moved, the branch I
re-pointed would not have been the branch the previous lane found, and the
correct response would have been to stop rather than to explain it.

## What changes sign, and the uncomfortable half

Nothing published today changes sign. verilog's **611 square** stands - it is
in the untouched column. The corpus square total is unchanged. No row crosses a
threshold anybody has quoted.

And the honest half: **the re-pricing makes the crooked share look slightly
better, not worse.** `share` is `crooked / judged`; the numerator cannot move
and the denominator grew by 1,486, so every one of the nine rows' shares falls.
haskell falls 2.90 points and cpp 2.37. This is correct - those bytes really are
adjudicable and really were being left out of the denominator - but it is the
direction a lane re-pricing its own instrument should be most suspicious of, and
it is why the twenty-one-column check above is computed instead of asserted.

## Landing it without a flag day

Three lanes hold baselines taken under the old rule. Nothing here invalidates
one:

- **`--price=sheltered` re-derives any held board exactly.** Not approximately:
  `verify` asserts that under the retired rule all 998 of haskell's disputed
  bytes are filed `unwindowed` again and 0 under the shipped one, so the toggle
  is the branch order and not a subtraction that happens to land in the same
  place.
- **Every board says which rule it was taken under.** `price: charged · rule
  a59f94cff34f` closes `run`, `whole`, `board`, `reprice` and `against`, and it
  is in the JSON as `{"price": {"name", "rule"}}`.
- **The rule carries a digest, not just a name**, following
  [`still/RESULT-5-oracle.md`](../still/RESULT-5-oracle.md) and `attest.rule()`
  one level up. The name is what a lane holding a baseline needs; the digest
  catches the case the name cannot, which is the same word meaning something
  else next week. It folds the six functions that decide a bucket
  (`bucket`, `unframed`, `excused`, `inorder`, `within`, `cover`) and the price
  table, and deliberately does **not** reach `plumb` - folding the trees in
  would move the digest on every rebuild, which is a rule that changes for no
  reason. Three attributions, three questions: `stamp` says which binary,
  `attest` says which oracle, `price` says which classification.
  `python3 tool/rack.py rule` prints what the digest reads and what it does not.
- **`rack.py against <board.json>` refuses across a rule change at exit 4**,
  *before* it sweeps - a refusal that costs three minutes of measuring first is
  a refusal nobody runs twice, and the whole value of it is that it arrives
  instead of thirty phantom drifts. A board with no `price` key predates the
  field, which dates it exactly: there was one rule then and it was `sheltered`.
  Re-derived under `--price=sheltered`, a board taken before today diffs to
  **zero moved cells**.

## Predictions, scored

| | claim | |
|---|---|---|
| P1.1 | nine rows move, not the brief's ten | **right** - kotlin has no bytes under a missing frame and ruby has 2 of 23 |
| P1.2 | 1,237 bytes; `unframed` 25,796→27,033; `unwindowed` 1,264→27 | **wrong, every figure** - 1,486; 22,080→23,566; 1,512→26 |
| P1.3 | `square` and everything below the frame untouched on all thirty | **right**, and computed rather than claimed |
| P1.4 | the crooked share *falls*, by less than 0.2 points | **right** - 15.249% → 15.192%, 0.057 points |
| P1.5 | haskell is the largest single move, 81.9% of the total | **half** - largest yes, but 998 of 1,486 is 67.2% |
| P1.6 | `engulf` rises strictly between 0 and the total | **right** - +1,146 of +1,486 |
| P1.7 | no conclusion published today changes sign | **right** |

Six and a half of seven, and the miss is the interesting one. **P1.2's figures
were the previous lane's, carried across an arm boundary without re-deriving
them.** Its board read `built` 30,720 on verilog and this arm reads 32,193; a
press change landed in between. That is the third time today a figure has been
quoted off the wrong arm, it is the rule this dossier itself wrote down, and I
broke it in the prediction I wrote to test it.

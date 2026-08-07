The lane before this one measured it and deliberately left it alone: `rack.survey`
tested `not t_sp[k]` — *the oracle had nothing to say inside this window* — before
it ever tested `missing[p]` — *is the frame overhead one we failed to build*. So a
byte under a construct tree-sitter has and joints never built was filed
`unwindowed`, which reads as the oracle's silence, **as soon as we put any
structure of our own underneath it**. Same bytes, same missing frame; the column
depended only on how much wrong structure we built under it. Building more moved
bytes out of a charge and into silence.

The `missing` test now runs inside that branch. **1,486 of 1,512 bytes — 98.3% of
what the column filed as silence — are a charge**, over nine rows:

| grammar | `unframed` | `unwindowed` |
|---|---|---|
| haskell | 5,991 → **6,989** | 998 → **0** |
| verilog | 11,751 → **12,146** | 396 → **1** |
| cpp | 179 → **217** | 42 → **4** |
| ocaml | 320 → **347** | 27 → **0** |
| swift | 1,179 → **1,193** | 14 → **0** |
| julia · sql · ruby · bash | +8 · +3 · +2 · +1 | 8 · 3 · 23 · 1 → 0 · 0 · 21 · 0 |
| **corpus** | 22,080 → **23,566** | 1,512 → **26** |

**`square` does not move on any row: 311,540 either way.** Nor does `crooked`, at
60,027, nor eighteen other columns — `reprice` derives that list from
`Seen._fields` and checks it rather than claiming it, so a column added tomorrow
is checked tomorrow. The branch re-pointed is reached only where the oracle has
nothing inside the window, which is disjoint from every branch that can produce a
square byte. The honest half of the same fact: the crooked *share* falls, from
15.249% to 15.192% of judged bytes, because the numerator cannot move and the
denominator grew.

The classification is extracted into `bucket()`, one function, because the order
**is** the content and because a second copy of the rule already lives in
`research/joinery/flag/spans.py` without the `missing` test at all — what `rack`
calls `unframed` that file calls `square`.

**It is not a flag day.** Three lanes hold baselines under the old rule and none
of them is invalidated:

- `--price=sheltered` restores the retired branch order exactly — asserted, not
  assumed: all 998 of haskell's disputed bytes land back in `unwindowed` under it
  and 0 under the shipped rule.
- Every report and every JSON says which rule it was taken under, with a **digest**
  as well as a name, following `attest.rule()` one level up. The name is what a
  lane holding a baseline needs; the digest catches the same word meaning
  something else next week. It folds the six functions that decide a bucket and
  deliberately does not reach `plumb`, because a rule that changes on every
  rebuild is a rule that changes for no reason.
- `rack.py against <board.json>` refuses across a price or rule change at **exit
  4, before it sweeps** — a refusal that costs three minutes of measuring first is
  a refusal nobody runs twice. A board with no `price` key dates itself exactly:
  there was one rule then and it was `sheltered`. Re-derived under it, a board
  taken this morning diffs to zero moved cells.
- `rack.py reprice` prices every row **both ways off one parse** — one
  `plumb.read`, two `survey` calls, same forest and same oracle tree — so the
  delta has no term in it for a sibling landing a press change between two runs.

`rack.py rule` prints what the digest reads and what it does not.

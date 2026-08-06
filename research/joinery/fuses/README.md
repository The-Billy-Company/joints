# fuses — every capacity constant, re-read for series

`crowd`/`skeins` were in series and no sweep found it, because a sweep that
moves one knob against a fuse it shares can only ever observe the lower of the
two. Three of that pair's four corners were worthless and the fourth was worth
23,879 square bytes on elixir alone.

This lane assumes the same defect is elsewhere. It inventories every capacity
constant in the tree, argues from the **code** which of them share a fuse,
prices only the pairs that can interact, and repairs the comments that record a
one-knob answer.

## Files

| File | What |
|---|---|
| `PREDICTION-1-series.md` | The inventory, the reduction, and what I expect each arm to pay — written before any measurement |
| `RESULT-1-series.md` | What the arms actually paid, scored against the prediction |
| `arm.py` | Edit a constant, pin a binary, put the file back — and refuse to restore if a sibling wrote it during the build |
| `score.py` | Per-grammar `square` across a set of boards, with a total that withholds verilog |
| `cost.py` | The other axis: parse wall-clock and peak RSS per pin, **from pre-minted folios**, because pressing the grammar is two orders of magnitude the parse and a harness that reads json reports every runtime cap as free |
| `denied.sh` | Splits taken and splits refused per grammar, off one pin's trace — the cheapest falsifier for "is this fuse a limit on anything" |

## The reduction in one line

Twenty-two capacity constants; nine on the path that can move `square`; six
pairs that share a fuse by construction; **three** worth an arm.

## The answer in one line

All four runtime fuses are **saturated where they stand** — nine arms, one
frozen oracle, and six of them byte-identical to the control at 309,356 square
without verilog, cleared by two crippled arms that move it by 110,337 and
143,879. The surviving defect is in the survey, on the cost axis: a corner one
knob priced at ninety seconds was killed unfinished at forty minutes.

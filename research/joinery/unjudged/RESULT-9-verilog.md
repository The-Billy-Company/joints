# Result 9 - verilog's damage, reconciled and put on the board

Scores [`PREDICTION-3`](PREDICTION-3-price.md) job 3. **Both figures are
correct about different populations, neither is arm-invariant, and the number a
work order should be given is neither of them.**

Arm `shade`, tree `86c6f3e81`, oracle `d85e736fa`. Every figure below is that
arm's; see the last section for why that sentence is load-bearing.

## The two numbers, and the third one

`damage` is `size - built` and it is [`tool/standing.py`](../../../tool/standing.py)'s
column. It is not redefined here and it is not wrong. What it is not is *"bytes
verilog never built"*, and that is the sentence three lanes optimised against.

`built` is the union of the extents of our **top-level roots that have
children**, so a root reaching over a hole carries the hole with it: the bytes
inside it are counted `built`, are not counted `damage`, and were never built.
`rack` now has a column for them.

| | verilog | corpus |
|---|---|---|
| `damage` = `size - built` | **62,464** | 126,927 |
| `stretch` - built bytes under no leaf of ours | 4,594 | 79,628 |
| `airy` - of those, whitespace between two tokens | 4,170 | 76,719 |
| `honest` = `damage + stretch` | **67,058** | 206,555 |
| `text` = `honest - airy` | **62,888** | 129,836 |

`rack.py board` prints all five in a `STRETCH` block, sorted by the third
figure rather than the second, so a row that is mostly blank sorts below a row
that is mostly source.

## And the correction is 424 bytes, not 4,594

**This is the part that came back the opposite way from the prediction.** I
predicted a majority of verilog's stretch would be source text. **90.8% of it is
whitespace.** A leaf is a token, so the space between two tokens is inside their
parent and under no leaf on any tree - real by the definition, and not a
construct anybody failed to build. Corpus-wide it is worse: 76,719 of 79,628,
96.3%.

So the honest reconciliation is:

- **62,464** is what the board prints, and it is exactly `size - built`.
- **67,058** is the same file's bytes with every unleafed byte inside `built`
  put back. It is 7.4% larger and it is 91% whitespace.
- **62,888** is the figure a work order should be given: source text inside
  `built` that no token of ours stands on. It is **424 bytes** more than the
  board's, which is 0.7%.

The brief's framing - *"verilog's honest damage is 68,119, not the 63,937 the
board prints"* - is right that a second number exists and right that the board's
was being quoted for something it does not measure. It is wrong that the second
number is the better one to quote. Splitting `stretch` was worth doing precisely
because it dissolves the correction it was written to make: **verilog's damage
figure was very nearly right all along, and the 4,182 that looked like a
discrepancy is mostly indentation.**

Verilog is not even the row this column indicts. By raw stretch the widest is
**html at 25,241**, then php 12,229, then elixir 6,690; verilog is fourth. By
source-text stretch the widest is **toml at 1,552 of 1,972** - a row that scores
100.0% standing, zero damage, and carries 1,552 bytes of source under no token,
and which also prints an `UNSOUND` complaint the board never reads.

## Why 49,446 and 8,175 do not partition anything

Re-derived on this arm by [`reconcile.py`](reconcile.py), which reads `plumb`'s
own node list rather than parsing `standing.rows`' text:

```text
  damage, whole file                        62,464
  damage inside picorv32 [1863, 71067)      49,426   <- the 49,446 census
  damage outside it                         13,038
  ablation delta, honest built              +9,576   <- the 8,175, in honest-built units
  ablation delta, raw built                +13,385   <- the same ablation in DAMAGE's units
  of that raw delta, inside picorv32        +2,222   <- NOT disjoint from the census above
  the same subtraction on THIS arm           3,462   <- the third term is not arm-invariant
```

Three separate faults, and they compound:

1. **Different units.** 49,446 is `size - built` bytes. 8,175 was a delta in
   *honest built*, which is a different quantity from `built`; expressed in
   `damage`'s own units the same ablation is 13,385.
2. **Not disjoint.** 2,222 of the raw delta lands *inside* `picorv32`, so the
   two terms overlap and their sum double-counts.
3. **Not arm-invariant.** It was +8,175 on one arm, +9,422 on another, and
   +9,576 here, while the census term moved 20 bytes and the whole-file damage
   moved with `built`. A residue computed by subtracting a term that moves by
   1,400 bytes across arms is a residue that means nothing: the record's own way
   gives 4,863 and the same subtraction here gives 3,462.

The fourth number sometimes quoted beside them, the peel's `behind` at 11,070,
is not damage at all in either sense: **6,163 of its 11,070 bytes are `built`**,
so it is not a slice of `damage` even in principle.

## Predictions, scored

| | claim | |
|---|---|---|
| P3.1 | both figures reproduce to the byte by a second reader | **right about the method, wrong about the numbers** - they reproduce, but at 62,464 / 67,058 / 4,594 on this arm, not 63,937 / 68,119 / 4,182 |
| P3.2 | the board's number is exactly right and exactly wrong; the correction is a column, not a redefinition | **right** |
| P3.3 | verilog is the corpus's widest stretch row, and corpus stretch is over 10,000 | **wrong on the first** - fourth by raw (html 25,241), second by source text (toml 1,552). Right on the second, by 8x: 79,628 |
| P3.4 | a majority of verilog's stretch bytes are not whitespace | **wrong, and backwards** - 90.8% are |

Two of four, and both misses are the same error: **I predicted from the name of
a column instead of from what it counts.** "Stretch" sounded like a root reaching
over a hole full of code, and it is mostly a root reaching over indentation.
That is precisely the error the previous lane named as its own, twice, and I
made it twice in the same job.

## Which arm

Every figure here is arm `shade` and every figure in the brief is the arm before
it. `built` on verilog moved 30,720 → 32,193 between them - a press change
landed - and every derived figure moved with it. Nothing in the reconciliation
changed shape; all four numbers slid together.

That is the point rather than a caveat. `damage`, `honest` and `text` are all
functions of `built`, and `built` moves several times a day on a tree ten lanes
are writing to. **A verilog damage figure quoted without its arm is not a
figure**, which is what `stamp:` and `oracle:` on the bottom of every report are
for and why `rack.py against` refuses across trees at exit 4.

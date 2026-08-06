# The order pair

Two javascript files that are the same work in a different order.

|                    | `many-then-one.js`            | `one-then-many.js`            |
| ------------------ | ----------------------------- | ----------------------------- |
| bytes              | 152,010                       | 152,010                       |
| nodes              | 28,011                        | 28,011                        |
| first half         | 4,000 `let aNNNN=1;`          | one 100,000-byte string        |
| second half        | one 100,000-byte string        | 4,000 `let aNNNN=1;`          |
| what a parse costs | 16,175 ms                     | 4,232 ms                      |

Nothing differs but which end the bulk token sits at. Today the first costs
**3.8x** the second, and that ratio is the whole finding: the cost of scanning a
byte is proportional to how much has already been read, which makes the parse
quadratic in file length. `research/joinery/bench.report.md` carries the profile
that attributes it - 98.2% of samples under the scanner's `longestAmong` - and
the reach/allow counter the scanner lane is fixing against.

## Why the construction matters

Holding **bytes** constant is not holding **work** constant, and that sentence
cost four wrong hypotheses to arrive at. The first attribution of this defect
was retracted because its ablation replaced every newline with a space: the byte
count held exactly, and 99.96% of the file quietly became one line comment. The
"fast" run it produced parsed seventeen lines of tree. It measured nothing.

This pair is the first construction in the project that pins **both** axes at
once. Same bytes, same nodes, same tokens, same tree shape - only the order
moves. That property *is* the evidence; a pair without it is two javascript
files. So it is asserted rather than trusted, from two directions:

- `python3 tool/order.py verify` re-derives both files from the construction in
  `tool/order.py` and refuses committed bytes it would not have produced, so the
  fixture and the generator cannot drift apart;
- `python3 tool/order.py` re-counts bytes and nodes on **every** run and, if
  they ever stop matching, says the pair proves nothing and to fix the
  construction - rather than reporting the ratio as a defect.

## The gate

`python3 tool/order.py` is a complexity gate, not a speed gate. It asserts no
duration - every absolute time in this project is laptop-specific and the report
says so. It asserts a **ratio between two parses on the same machine in the same
process**, and it runs the same construction over five grammars because the
order swing is what separated the blind-external grammars from the flat ones,
and it is the cheapest early warning if a fix only helps javascript:

```
grammar       many-then-one  one-then-many    swing     bytes    nodes
rust                 3779 ms          933 ms     4.0x   160,023   24,019
typescript           7974 ms         1985 ms     4.0x   152,010   28,011
javascript          16175 ms         4232 ms     3.8x   152,010   28,011
json                    9 ms           10 ms     0.9x   132,005   20,008
java                 2368 ms         2956 ms     0.8x   160,040   32,026
```

The ceiling is **1.6x**, picked from what the flat grammars already achieve
rather than from taste: over three replicates each, json ran 0.96 / 1.01 / 1.00
and java ran 0.88 / 0.96 / 0.99, so the widest excursion without the defect is
12%. 1.6x leaves that roughly five times its own noise, and today's tree still
fails it from 2.8x to 4.1x. `--calibrate` reprints that spread; re-derive the
number from it rather than nudging it upward when a row gets close.

Those last two rows are also the gate's own control. A gate that had broken
green would show json passing and mean nothing; a gate that had broken red would
show json failing too. Both directions are exercised in the same run, which is
why all five grammars stay in even after three of them go quiet.

## `lex` is a false-negative surface

The bare lexer walks the same 152,010 bytes in **46 ms and 47 ms** - the two
orders indistinguishable - where `parse` pays 16,175 ms and 4,232 ms. The defect needs the admitted set that the
parse loop supplies at each position, and the lexer has none to supply, so it
cannot see it - at a three-hundred-and-fiftieth of the cost, with a flat ratio,
looking exactly like health.

A gate built on `lex` would have passed forever while `parse` stayed quadratic.
This one goes through `stamp.ask`, which parses. The gate re-runs the lexer over
the worst pair on every run and prints the comparison, so the trap is
demonstrated rather than written down once and forgotten.

## Rebuilding it

```bash
python3 tool/order.py build     # write the pair from the construction
python3 tool/order.py verify    # the committed bytes are what it makes
python3 tool/order.py list      # which grammars are pinned here
python3 tool/order.py status    # measure all five, gate nothing
python3 tool/order.py           # measure and hold to the ceiling
```

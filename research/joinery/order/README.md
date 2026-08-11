# The order pair

Two javascript files that are the same work in a different order.

|                    | `many-then-one.js`            | `one-then-many.js`            |
| ------------------ | ----------------------------- | ----------------------------- |
| bytes              | 152,010                       | 152,010                       |
| nodes              | 28,011                        | 28,011                        |
| first half         | 4,000 `let aNNNN=1;`          | one 100,000-byte string        |
| second half        | one 100,000-byte string        | 4,000 `let aNNNN=1;`          |
| what a parse cost  | 16,175 ms                     | 4,232 ms                      |
| what it costs now  | 20 ms                         | 20 ms                         |

Both cost rows are the folio path, which is the one those first numbers were
taken on and the one the product ships; the grammar path reads 122 ms and 121 ms
today. Nothing differs between the two files but which end the bulk token sits
at, so the ratio across a row is the whole instrument. It read **3.8x** when this pair was built,
and that was the finding: the cost of scanning a byte was proportional to how
much had already been read, which made the parse quadratic in file length.
`research/joinery/bench.report.md` carries the profile that attributed it - 98.2%
of samples under the scanner's `longestAmong` - and the mechanism the scanner
lane found underneath: `Munch` groups the slate into voices, and one permissive
member of a voice surviving to end-of-file made every pattern sharing that voice
pay a walk to end-of-file, whether or not the permissive one was permitted.

**It is closed.** The reachability mask bounds the walk, the folio carries it
across a round-trip, and the pair reads 1.0x on both paths. The `16,175 ms`
column stays on the page because a gate whose defect has been deleted from its
own fixture is a gate nobody can check the calibration of. `bench.report.md`'s
"Collected" and "Closed, 34 minutes later" sections carry the close and the
before/after ns/B table.

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
and it is the cheapest early warning if a fix only helps javascript.

Each grammar is measured **twice**, once named as a `grammar.json` and once as a
folio minted from it, and each path is keyed and judged on its own. That is not
thoroughness, it is the lesson of the afternoon the mask was live on import and
absent from the folio: 0.14 s one way and 15.40 s the other from the same
executable. A gate that took the better of the two would have reported 1.0x
that day, which is exactly the failure it exists to make impossible.

```
grammar                   many-then-one  one-then-many    swing     bytes    nodes
rust via grammar                  294 ms          287 ms     1.0x   160,023   24,019
json via grammar                   19 ms           19 ms     1.0x   132,005   20,008
javascript via grammar            122 ms          121 ms     1.0x   152,010   28,011
typescript via grammar            456 ms          456 ms     1.0x   152,010   28,011
javascript via folio               20 ms           20 ms     1.0x   152,010   28,011
json via folio                     19 ms           20 ms     1.0x   132,005   20,008
java via grammar                   92 ms           96 ms     1.0x   160,040   32,026
typescript via folio               23 ms           24 ms     1.0x   152,010   28,011
rust via folio                     23 ms           25 ms     0.9x   160,023   24,019
java via folio                     18 ms           23 ms     0.8x   160,040   32,026
```

The ceiling is **1.6x**, picked from what the flat grammars already achieved
rather than from taste: over three replicates each, json ran 0.96 / 1.01 / 1.00
and java ran 0.88 / 0.96 / 0.99, so the widest excursion without the defect is
12%. 1.6x leaves that roughly five times its own noise. Every row is now inside
that band - javascript reads 0.96 / 0.98 / 0.98 on the grammar path and 0.99 /
0.99 / 0.99 on the folio over three replicates, which is the flat grammars' own
noise and not a smaller version of the defect. `--calibrate` reprints that
spread; re-derive the number from it rather than nudging it upward when a row
gets close.

The two flat grammars are the gate's own control, and keeping them mattered more
after the fix than before. A gate that had broken green would show json passing
and mean nothing; a gate that had broken red would show json failing too. Both
directions are exercised in the same run, which is why all five grammars stay in
now that all ten rows are quiet.

## `lex` is a false-negative surface

While the defect was live, the bare lexer walked the same 152,010 bytes in **46
ms and 47 ms** - the two orders indistinguishable - where `parse` paid 16,175 ms
and 4,232 ms. Flat ratio, a three-hundred-and-fiftieth of the cost, looking
exactly like health.

The reason is better than "the lexer has no admitted set to supply", which is
what this section said first. `lex` permits everything, so the to-EOF match was
both recorded *and taken*: the file went down in a handful of enormous wrong
tokens and there were about **ten positions in the whole file**. With a narrow
`allow` the identical walk happened, the giant match was discarded, the parse
took a three-byte keyword, advanced three bytes and paid the to-EOF walk again -
about **28,000 times**. The admitted set never made a call cost more. It made
the correct number of calls, and every one of them was always that expensive.

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

# Result 2 - verilog, priced against another parser for the first time

Predictions for this half were written with the others, as P1.7 (the sweep),
P1.8 (`square < 50%` of built, `unframed` large) and P1.9 (`damage` survives and
turns out uninformative rather than wrong) in
[`PREDICTION-1`](PREDICTION-1-disagreement.md); all three are scored in
[`RESULT-1`](RESULT-1-disagreement.md) and all three held.

Every number here is one arm: pin `unjudged`, its own folio cache, its own
oracle seat (`pin-unjudged`), tree-sitter 0.26.11, binary `94d59d9ad` over tree
`05a18fcd1`. Before and after are the *same* arm - only the oracle reader
differs - so nothing below is two runs of two trees compared.

## The sweep: who was unjudged, and how much

`plumb.oracle` refused a grammar outright when the two renders disagreed, and
`rack` filed every built byte of it as `unjudged`. Across all 30, the refusal
lands exactly on the two rows whose oracle tree has errors in it:

| | before | after |
|---|---|---|
| verilog | **30,720 unjudged** (100% of built) | 4,293 (14.0%) |
| sql | **3,967 unjudged** (100% of built) | 121 (3.1%) |
| haskell | 1,013 | 1,013 |
| cpp · ocaml · swift · ruby · julia · bash · kotlin | 137 together | 137 together |
| **corpus** | **35,837** of 396,158 built - **9.05%** | **5,564** - **1.40%** |

`yaml` builds nothing at all and is a third condition, correctly reported as
such rather than as a refusal.

The 5,564 that remain are `plumb`'s own per-byte rule - no oracle node over the
byte, or an interior under an `ERROR` - and `unwindowed`. That is a local,
per-byte silence with a reason attached to each byte, not a grammar the
instrument cannot open.

## verilog

`upstream/sources/picorv32.v`, 94,657 bytes.

```text
  94,657  the file
  30,720  built          <- 32.5% standing
  63,937  damage         <- size - built, and exactly the figure three lanes have been working
```

**`damage` is confirmed to the byte.** 63,937 is right, and nothing in this lane
moves it. What this lane adds is the other column:

| of the 30,720 built | bytes | of built | of the file |
|---|---|---|---|
| **square** - the oracle defends the derivation | **611** | 2.0% | **0.65%** |
| askew - the deepest node itself disagrees | 1,125 | 3.7% | |
| racked - right leaf, wrong parent | 12,112 | 39.4% | |
| unframed - agrees under a frame we never built | 12,579 | 41.0% | |
| unjudged - no verdict over the byte | 4,293 | 14.0% | |

`crooked` = askew + racked = **13,237**, which is 43.1% of built and **50.1% of
the 26,427 bytes the oracle could adjudicate**. Node-weighted bracket recall is
88.2%, so this is not one wide node dragging a byte count around.

**The sentence the board could not say until today: on the largest damaged row
in the corpus, 611 bytes of 94,657 are structure tree-sitter agrees with.** The
`trued` column now prints that as 0.6%, beside a `standing` of 32.5%.

### Where the 12,579 unframed bytes go

337 distinct spans the oracle frames and we do not. The widest is
`module_declaration [1863, 71067)` - 69,204 bytes, the whole module - against
the 3,544 roots outliner hands back, so most of this is the forest-versus-tree
difference. `rack` already charges that separately: 8,573 of the 12,579 are the
single widest missing frame on the row (`engulf`), leaving 4,006 that are
genuinely a construct-by-construct absence. Under it, in descending width:
`module_ansi_header`, `list_of_port_declarations`, sixteen
`ansi_port_declaration`s, then a long tail of `statement_or_null`,
`generate_block`, `case_generate_construct`, `clocking_drive` and `expression`.

### Where the 12,112 racked bytes go

Right leaves under wrong parents, and the widest families name one confusion:
outliner builds `list_of_variable_decl_assignments` where tree-sitter builds
`blocking_assignment`, and `list_of_net_decl_assignments` where tree-sitter
builds `list_of_net_assignments`. It is reading procedural assignments as
declaration lists. That is a fork-selection question and belongs to the press
lane, not to this one - it is recorded here because until today no instrument
on this tree could name it.

## Against the two prior claims

Neither is refuted and neither is confirmed, and both are claims about the wrong
half of the file.

- **8,175 bytes said to be unfixable grammar limitations** and **49,446 bytes
  said to be four defects in procedural blocks** sum to 57,621 against a damage
  of 63,937, leaving 6,316 - close enough to the parallel lane's finding that
  **6,591 bytes of the wall inventory are an artifact of the peel restarting at
  state 0** that the two should be reconciled by whoever owns `walls.py`. This
  lane does not touch that arithmetic.
- What this lane can say is that **both claims are about `damage`, and `damage`
  is outliner's own words about its own forest.** They partition the 63,937
  bytes verilog never built. They are silent about the 30,720 it did build, and
  the oracle's verdict on those is 611 square.
- So the expected value of converting damage into built, at verilog's own
  current rate, is **two square bytes per hundred converted**. A work order that
  ranks by `damage` alone is ranking by a number that has never once been
  checked against another parser, on the row where that check is worst.

## The instrument responded to the treatment

The self-check the house rules demand, on this arm:

```text
before:  301,782 square ·  3,942 askew · 42,496 racked · 12,101 unframed · 35,837 unjudged
after:   305,011 square ·  5,067 askew · 54,720 racked · 25,796 unframed ·  5,564 unjudged
                                                                  = 396,158 built, both
```

`built` is identical because nothing about the parse changed; the split moved
because 34,687 bytes that had no verdict now have one. `rack verify` holds 18 of
19 tripwires before and after, byte for byte - see the README for the one that
fails and whose it is. `differential.py run` reports `45 compared, 0 skipped ·
37 partial, 20 unexplained` under both readers, so no case that was being
compared changed its answer.

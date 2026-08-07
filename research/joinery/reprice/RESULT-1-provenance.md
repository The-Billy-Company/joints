# Result 1 — the peel re-priced, and what each prediction was worth

One pinned binary (`strandprice`, `joints 1b4e50ce0` built from `9d26ca82e`),
separate `JOINTS_WORK` for the cold and warm arms so neither read the other's
folio. Every number below is from that run.

    eval "$(python3 tool/pin.py arm strandprice)"
    JOINTS_WORK=.local/reprice/coldwork python3 tool/walls.py run  --json > .local/owners/priced.json
    JOINTS_WORK=.local/reprice/warmwork python3 tool/walls.py warm --json > .local/reprice/warm2.json
    python3 research/joinery/owners/owners.py --warm .local/reprice/warm2.json --json > .local/owners/labelled.json
    python3 research/joinery/owners/cut.py --owner "" --warm .local/reprice/warm2.json

## The three decisions I was asked to argue

**1. What the peel should do with a restarted tail: report it, and label it.**

The two easy answers are both wrong. *Resume with the stack it had* is not
available to this instrument — the peel drives the binary through a CLI that
takes a file and returns a verdict, so there is no stack to hand back; making one
available is a change to `src/`, which is not my lane, and it would make the peel
a different measurement rather than a fixed one. *Refuse to report walls in a
restarted tail* throws away the peel's only reason to exist: a census that reports
one wall per file was what `walls.py` was written to improve on, and going back to
it would cost a board that names 161 distinct walls to save it from naming them
badly.

So the peel keeps every round and **the provenance of the text each round was
handed rides beside the wall**. That is `Priced.turn` — the earliest round that
met a wall — and it costs one integer per row. It is the only one of the three
that is honest about what the instrument did: round 1 read the file, round *i>1*
read a suffix whose openers round 1 left behind, and a reader can now tell those
apart without trusting me.

**2. `Wall.real`: the predicate is provenance, not any property of the wall.**

`not shadow and state != 0` was a right instinct against a wrong predicate. The
state number is a count of the statements before the wall, and
`../strand/witness/sw-cut-*.swift` reproduces one orphan `}` at states 0, 681 and
1166. No rule over state numbers, terminal shape, bracket-ness or `FIRST(start)`
can separate those three, because the artifact is not a property of the wall — it
is a property of the text the round was handed. `Wall.real` is now
`self.stand in cut.STANDS`, and `cut.stand` is the single place the taxonomy is
decided. The state-0 rule had a **second copy** in `owners.py`
(`w.endswith(" in state 0")`), which is `sole.py`-shaped and had only ever been
fixed in one of the two; both are gone.

**3. Five stands, because two of them are the instrument confessing.**

    document   round 1 met it - the parse read the file as written
    witnessed  a whole-file peel refuses the same byte AND blanking it bought
               that peel a root or a byte  (see RESULT-2)
    alias      a whole-file peel refuses the same byte and blanking it bought
               nothing - warm's own cascade  (see RESULT-2)
    torn       a whole-file peel read past that byte without complaining, or
               round 1 built a node over it
    untested   past the furthest byte any warm round reached, or nobody
               warm-peeled that grammar

## The re-price

Whole board, every owner, 161 distinct walls over the 14 grammars that have one:

| stand | bytes | share | walls |
|---|---|---|---|
| `document` | 4,749 | 3.9% | 14 |
| `witnessed` | 2 | 0.0% | 2 |
| `alias` | 60,502 | 50.1% | — |
| `torn` | 37,433 | 31.0% | — |
| `untested` | 18,146 | 15.0% | — |
| **priced** | **120,832** | | **161** |

**4,751 B stands**, and 4,749 B of that needs no instrument's opinion at all —
it is round 1 reading the file. That is 3.9% of what the peel prices. Everything
that stands is sixteen rows — fourteen `document`, two `witnessed`, the latter
pair reproducing only on one of two runs — and they fit on one screen:

| grammar | wall | bytes | owner |
|---|---|---|---|
| markdown | `stray b'\n'` | 3,284 | scanner |
| cpp | `" in state 907` | 638 | unowned |
| haskell | `. in state 7` | 411 | withheld |
| ocaml | `stray b'@'` | 196 | scanner |
| swift | `) in state 141` | 95 | **stranded** |
| zig | `{ in state 715` | 58 | unowned |
| verilog | `` ` in state 3438`` | 21 | unowned |
| kotlin | `. in state 253` | 11 | stranded |
| scala | `" in state 610` | 9 | unowned |
| c | `, in state 822` | 8 | unowned |
| bash | `[ in state 1163` | 8 | stranded |
| julia | `_delimiter_str_1 in state 136` | 6 | conflict |
| sql | `_identifier in state 256` | 3 | withheld |
| ruby | `uninterpreted in state 1523` | 1 | withheld |
| scala | `" in state 1791` | 1 | stranded, *witnessed* |
| zig | `} in state 83` | 1 | stranded, *witnessed* |

The last two rows are the whole `witnessed` population, and a second warm run
under the same pin calls both `alias` instead while agreeing on every other byte
in this table. Read them as *at most* standing; the replicate is in
`RESULT-2-alias.md`.

### The `stranded` column

22,033 B on this pin (22,179 B when the inherited finding was written; the tree
moved — see `RESULT-3-verilog.md`).

| stand | bytes | share |
|---|---|---|
| `document` + `witnessed` | **116** | 0.5% |
| `alias` | 3,005 | 13.6% |
| `torn` | 5,777 | 26.2% |
| `untested` | 13,135 | **59.6%** |

**The honest headline is not 96.3%.** It is *39.9% demonstrably instrument, 0.5%
standing, and 59.6% nobody can say from here* — and the third number is the
finding. Widening from two grammars to thirty made the claim **weaker**, which is
the direction a widening should be able to go, and the direction the inherited
one could not: with `untested` folded into `artifact`, a warm run that stalls
earlier acquits more.

### The 13,056 B sold as construct damage

Swift's `} in state 681` (9,160 B) and `} in state 1166` (3,896 B). Neither is
construct damage and neither is a demonstrated artifact:

- Both are `turn > 1`, so both were refused in a fragment.
- Both stand past byte 10,989, and swift's warm run reached byte **2,904** of
  28,467 before its 400 rounds ran out. Warm never looked.
- Round 1's forest has no node over either byte, so the canopy cannot convict
  them either (`RESULT-2`).

So the 13,056 B re-prices to **`untested`**, not to zero. That is worse for the
board than the inherited claim and better for whoever reads it: nothing in this
repository can currently say whether those two rows are the document's walls or
the peel's, and the reason is named in `RESULT-2`.

## Predictions, scored

**P1 — the warm/cold diff was a state-number join. RIGHT, and worse than
predicted.** Under the retired phrase key the byte join's advantage is visible per
grammar in `cut.py`'s second table: on every one of the fourteen, `by phrase`
equals or nearly equals `round 1`. The warm peel was contributing what
`Priced.turn` knows for free.

**P2 — the byte join raises the surviving population to 2,000–15,000 B. WRONG,
and in the direction I said I expected.** It raised it to 15,527 B before the
purchase test and to **2 B** after. I predicted a range and got an answer three
orders of magnitude below it, because I predicted the join's *reach* and never
asked whether what it reached was evidence.

**P3 — ≥5 grammars have short frontiers; `untested` ≥10% of the two-valued
artifact population. RIGHT.** Nine grammars end their warm run without clearing
the file (four on the 400-round budget, two on `unclosed, which names no byte`,
three on other stops), and `untested` is 15.0% of the board and 59.6% of
`stranded`.

**P4 — verilog's 63,937 B does not move; the 6,591 B subtraction would be wrong.
RIGHT on the number, WRONG on the second half.** `standing.py` still reports
63,937 B on this pin (94,657 − 30,720 built). I also predicted I would find a
place in the tree already mixing the two; I looked, and **nobody is** — every
citation of 6,591 keeps it as a peel figure. That was a cheap slur on other
lanes' work and it did not hold. See `RESULT-3-verilog.md`.

**P5 — no predicate computable from the wall alone can fix `Wall.real`; the
second copy in `owners.py` is a `sole.py`-shaped defect nobody filed. RIGHT on
both.** The second copy was there and is gone. The `sole.py` half of that
observation turned into Job two.

**P6 — the warm corpus run costs 15–60 minutes; verilog, haskell and kotlin
stall. WRONG on both.** It cost **2 minutes** on thirty grammars, not fifteen.
Four grammars burn the budget and they are haskell, sql, swift and verilog —
kotlin finishes in 26 rounds. I named the wrong third grammar and was 8× out on
the time.

Four of six, and both misses are about magnitude rather than mechanism. The one
that matters is **P2**, because it is the row I was proudest of: I built a better
join, measured that it matched more, and would have published 15,527 B of
"witnessed" walls if I had not gone looking for what the join was matching.

## What moved, in the tree

- `tool/walls.py` — `Priced.turn` / `Priced.first` / `Priced.torn`, `Cold.turns`,
  `Warm.frontier`, and (`RESULT-2`) `Warm.bought` / `Warm.paid` / `Cold.canopy`.
- `research/joinery/owners/cut.py` — the whole taxonomy, in one function.
- `research/joinery/owners/owners.py` — `Wall.stand` / `Wall.real` / `Wall.made`,
  and the second state-0 rule deleted.

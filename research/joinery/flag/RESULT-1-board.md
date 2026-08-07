# Result 1 — the board stops counting wrong structure as success

Scored against [PREDICTION-1-board.md](PREDICTION-1-board.md), written before
the corpus sweep. **Five of six held; P2 failed, and it is the one I named in
advance as the one I most expected to be wrong about.**

    binary   .local/pin/flag/bin/joints  ·  joints 7aa79135a from tree 9346ded81
    oracle   tree-sitter 0.26.11, via tool/rack.py (read-only for this lane)
    corpus   30 grammars, 526,798 bytes

## The correction

```
AUDIT — `built` against tree-sitter's derivation, over 27 of 30 rows (350028 of 384715 built bytes)
  265650 square + 60138 crooked + 23031 soft + 35896 unaudited = 384715
  was       73.0% standing   `built / size`, which scores a confidently wrong tree exactly like a right one
  now       50.4% trued      `square / size` — bytes whose DERIVATION the oracle defends. A floor.
            61.6% at most    everything not proven wrong. The 35896 unaudited bytes are between the two.
            11.4% of the corpus is built, counted, and WRONG — 60138 bytes, 15.6% of `built`.
```

**The headline falls 22.6 points, from 73.0% to 50.4%.** That is a correction,
not a regression: no parse changed, and the 60,138 bytes were always wrong. The
board was reporting them as success because `built` meant *placed under a root*
and never meant *placed correctly*.

`standing` is still printed, on the same line, first. Nobody reading this board
should have to reconcile a number that moved without being told what moved.

**The baseline is 73.0%, not the 69.09% the brief quotes.** I did not reproduce
69.09% at any point today. Between the brief's generation and mine, seventeen
grammars were mended by another lane; `standing` went up while `trued` was not
being measured. That is the whole thesis of this rung in one sentence, and it is
also a warning: the 22.6-point drop is measured within one generation, both
numbers from the same run of the same binary. **Do not subtract 50.4 from 69.09.**

## The three numbers, and which one to quote

    60138   crooked, defended        the derivation is wrong. Quote this.
    23031   crooked, soft            where a comment hangs. A parser's choice, not a claim.
    83169   crooked, both            never quote this.

`soft` is 27.7% of the crooked total, matching rack's own 27.7% to the decimal
(P6 held). It is computed here from `standing.extras()` where rack uses SYMBOL
extras only; the two readings agree because a PATTERN extra's value is a regex
and can never match a node name.

## Predictions

| | claim | falsifier | outcome |
|---|---|---|---|
| P1 | the floor falls > 8 points | a floor above 61.1% | **held** — 50.4%, a 22.6-point fall |
| P2 | ≥ 6 of the 12 grammars at 100.0% lose bytes | 5 or fewer | **FAILED** — 3 of 12 (go 17, python 27, toml 16) |
| P3 | ≥ 1 grammar's crooked exceeds its damage | every row `crooked <= damage` | **held** — 8 rows |
| P4 | the work order moves ≥ 3 places on ≥ 3 rows | everything within 2 places | **held** — 5 rows; toml 30→21, elixir 11→4 |
| P5 | the four-bucket identity survives; the split totals `built` per row | any row where it does not | **held** — 27 of 27, and 526,798 unchanged |
| P6 | soft lands within 5 points of 27.7% | outside 22.7–32.7% | **held** — 27.7% |

### P2 is the interesting failure

I predicted at least six of the twelve 100.0%-standing grammars would lose
bytes. Three did, and they lose 60 bytes between them. **The board's blind spot
is real, large, and concentrated — it is not a fog over every green row.**

php alone is 25,394 of 60,138 (42%), elixir 17,660 (29%), swift 8,063 (13%).
Three grammars hold 84% of it. The correct read is not "every 100% row is a
lie"; it is "`standing` is roughly honest where it is high and catastrophically
dishonest on exactly five rows, and it had no way to tell you which."

That failure also kills a claim I would otherwise have made: that the go exhibit
(`fmt.Print("x")` read as a cast, 100.0% standing, zero mends) generalises. It
does not. It is 17 bytes.

### P3 is the work-order finding

Eight rows carry more crooked bytes than damage bytes:

```
php 25394 vs 8699 · elixir 17660 vs 1559 · swift 8063 vs 5337 · kotlin 848 vs 246 · cpp 603 vs 411
```

`--damage` — the board's work order all day — ranks by the smaller number on
those eight rows. elixir sat at 96.6% standing and 11th on the work order while
holding the second-largest pile of wrong structure in the corpus. It is now 4th.

## What moved in `tool/standing.py`

Every other lane reads this board, so, precisely:

**Three new columns.** `trued` (square/size, the corrected headline per row),
`crooked` (defended misread bytes), `graded` (whether the row has a verdict, and
why not if it does not). Nothing was removed. `standing`, `covered`, `built`,
`orphan`, `rubble`, `spoil`, `damage`, `roots`, `leaves` all read exactly what
they read yesterday.

**A new sort order, `--crooked`**, and it is the default. `--damage` still works
and still sorts by `size - built`.

**A cache at `.local/standing/audit.json`.** The oracle sweep costs about twelve
minutes; the board costs a second. `python3 tool/standing.py --audit` refreshes
it. Rows are keyed by a triple digest of folio, binary and source, so a verdict
computed against a different generation reads `stale` and its bytes leave the
headline rather than being silently kept. **A board run without the cache still
runs** — every audited column reads `—` and `graded` reads `none`.

**`graded` distinguishes four states**, because three different things were
reading as one:

    read     the oracle adjudicated this row
    stale    a verdict exists but for a different folio/binary/source
    none     no verdict is possible — tree-sitter's own parse has errors in it
    void     nothing was built, so there is nothing to adjudicate

verilog and sql read `none`, not `stale`. That is the oracle's hole, and it is
34,687 bytes, and the board now says so on the row rather than in a footnote.

**Two new checks**, both in the existing `CHECK` block:

    the audit splits `built` and does not redefine it:
      square + crooked + soft + unaudited == built on 27 of 27 audited rows
    and not vacuous:
      11 audited row(s) carry no crooked byte and 16 do

The second is there because the first passes trivially if the oracle files every
row identically. See [tamper.py](tamper.py) — it is the check that catches the
laundering.

## The oracle's holes, stated

- **34,687 bytes have no verdict at all.** verilog (30,720 built) and sql
  (3,967 built) are `none`: tree-sitter's own CST and XML disagree, which means
  the reference parse has errors in it. For `picorv32.v` the ERROR *is* the root,
  though tree-sitter still returns 63% of the file under named nodes inside it.
  Those bytes are neither square nor crooked. They sit between `trued` (50.4%)
  and `at most` (61.6%), and the board prints both bounds rather than picking one.
- **23,031 bytes are soft** and are excluded from the charge.
- **`renamed` is folded into `square`.** A spine that matches once the grammar's
  own ALIAS applies is a right derivation, not a near-miss.

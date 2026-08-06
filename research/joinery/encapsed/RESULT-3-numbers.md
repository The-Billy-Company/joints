# Result 3 — the numbers, and the two predictions that failed

Both arms measured against **frozen oracle `encapsed`** (`attest.py freeze`,
tree-sitter 0.26.11, php dylib `db2f75824`), each with **its own
`OUTLINER_WORK`** — see the note at the bottom, which is a finding of its own.

## `tool/standing.py`, php row

| | before | after |
|---|---:|---:|
| standing | 87.2% | **100.0%** |
| built | 59,146 | 67,845 |
| damage | 8,699 | **0** |
| strewn | 8,120 | 0 |
| orphan | 8,091 | 0 |
| spoil | 579 | 0 |
| roots | 119 | **1** |
| where it stops | `unexpected / at 26849` | `accepted, 1 root` |

Board: **73.0% → 74.7% standing**, and php leaves the widest-by-damage list
entirely (`verilog · haskell · yaml · php · swift` becomes `verilog · haskell
· yaml · swift · scala`).

## `tool/rack.py run`, the derivation

php: `662 square + 40,130 askew + 18,354 unframed = 59,146 built`, bracket
recall 29.5%, **67.8% crooked** — the worst row on the board — becomes
`67,845 square + 0 + 0 = 67,845 built`, recall **100.0%**, **0.0% crooked**.

Corpus-wide: square **205,583 → 272,766** (+67,183), askew **44,059 → 3,929**
(−40,130), unframed **60,067 → 41,713** (−18,354), racked 39,110 unchanged.
Crooked as a share of `built`: **21.62% → 10.94%**.

**No other grammar's row moves by one byte.** rack's own without-php split
reads `204,921 square` identically on both arms, which is that claim stated by
the instrument instead of by me.

## Scoring the five predictions: three held, two failed

1. **The `text` node goes to zero.** HELD — no `text` node survives.
2. **`square` rises >30,000 and `askew` falls >30,000.** HELD, and by more
   than double the threshold either way.
3. **`built` falls while `square` rises.** ***FAILED***, on the falsifier I
   wrote for it myself: "`built` rises". It rose 8,699. I predicted the fix
   would *cost* coverage — that a real parse would leave comments and
   inter-statement whitespace as `orphan` and `spoil`, the way every working
   grammar does, and php's headline standing might drop from 87.2%. It didn't
   drop, it went to 100.0%, because php's `program` genuinely spans the file:
   the 8,699 bytes of damage were the un-built tail *before* byte 26,850 and
   they came back too. I was braced for a trade that wasn't there.
4. **Bracket recall rises above 90%.** HELD — 29.5% → 100.0%.
5. **`unbound` stays small and `spoil` grows.** ***FAILED***, same root cause:
   spoil went 579 → 0 and unbound 0.9% → 0.0%.

Both failures are the same misreading in the same direction, and it is the
comfortable direction to be wrong in — I predicted a price and there was none.
Worth saying plainly because the reverse would have been the flattering error:
had I predicted "everything improves" and gotten it, nobody could tell whether
I had reasoned or just hoped.

## What did not move, exactly as predicted

`Str.php` holds **zero** backticks and **zero** `<<<`. So
`execution_string_chars` and its after-variable twin are seated and never once
exercised by the corpus, and the two heredoc members are left blind with the
corpus unable to say so. Two of the four rows shipped are, on this corpus,
unfalsifiable — which is why they ship as specimens or not at all
(`RESULT-6`).

## Measurement note — two pins sharing one `OUTLINER_WORK`

A sibling lane found that `tool/order.py::miss` compares a folio's mtime to the
binary's, and two pinned binaries are both older than a folio either just
minted, so two arms sharing a work directory can measure one side twice — and
always flatteringly, since two runs of one table always agree.

My first sweep did share one. I re-ran both arms with `OUTLINER_WORK` per arm,
from empty, and then diffed the two folio sets: **all 30 folios byte-identical,
including php's.** So the seating lives in the binary, not in the pressed
table, and this particular change could not have been laundered by the cache.
The numbers above are the isolated-arm run and they reproduce the shared-arm
run exactly. The general warning stands and cost nothing to obey; what it
bought here is that "no collateral" is now a measurement rather than an
assumption.

# Result 1 — the verdict reader, and the four generations of it

Scored against [PREDICTION-1-verdict.md](PREDICTION-1-verdict.md). Every number
below comes from the pinned binary `.local/pin/mendlane` (`33a3dac8b`, tree
`bd7b3e939`), which is the point of pinning: the repo moved eight times while
this ran and `stamp` said so each time (`DRIFT - … measures a tree that no
longer exists`). Nothing here compares two binaries.

## What was wrong

`verdict()` took the **last non-blank line** of stderr. On a grammar that mends,
that line belongs to `inquest`, which prints *after* the stop and prefixes
itself with the **grammar name** rather than the source path. All eighteen
walled rows have one. So the reader returned inquest's prose, and since
`outcome()` derives `kind`, `reach`, `roots`, `at` and `wall` from that single
string, five fields moved together.

`BLIND` and `UNSOUND` search the whole stderr with a regex and were correct the
whole time. That is the diagnostic shape worth keeping: **the two fields nobody
suspected were the two that scanned instead of counting.**

## The repair, and the claim that it was one line

The brief said one line. It is one line of *logic* and it is the fourth rule to
read this string:

| gen | rule | wrong on |
|---|---|---|
| 1 | last line, take the tail after its last `": "` | 6 of 20 shapes |
| 2 | last line, strip the prefix we passed in | 5 of 20 shapes |
| 3 | this one: **search** in reverse for the line the *source* names | 0 of 20 |

Generation one ate python's whole verdict down to `at 482 in state 880`, because
the payload names the token it refused and that token is a colon. Generation two
fixed the boundary and kept the wrong line. Both now live in `tool/stamp.py` as
named functions, and `--probe` runs all three side by side across 20 shapes and
prints how many each prior rule gets wrong. That is the anti-vacuity: the gate
that existed before this had **no fixture with an inquest line under the
verdict**, so it passed green against the broken reader. I watched the new
shapes fail under generations one and two before trusting them passing under
three.

## Scoring

**P1 — held.** `mends` now reports on every mending row. Corpus-wide, both rules
run over the *same* captured stderr: `mends` **0 -> 4,551**, `reach` **100,399
-> 507,850** bytes (19.1% -> 96.4% of 526,798), `roots` **30 -> 8,435**, kinds
`{state: 15, whole: 12, other: 3}` -> `{mended: 17, whole: 12, other: 1}`.

**P2 — held.** `walls.py`'s `voice` divided by `mends` and read **0.0 for every
walled grammar** - a zero on both sides of the divide, which reports every tail
as pure depth. It now separates repetition from depth: markdown 79x, verilog
53x, haskell 32x, sql and ocaml 14x are one wall hit over and over; the corpus
peel names **181 distinct walls** across 18 walled grammars, deepest haskell at
56.

**P3 — falsified, and it cost me the gate.** I predicted `--probe` would already
catch the regression once I reverted the fix. It did not: its fixtures had no
inquest tail. The prediction that a test would bite is worth writing down
precisely because this is how it fails.

**P4 — falsified.** I predicted other readers of the same field would turn up
broken. They did not. `tool/sole.py` reddens, but it reddened before this work
and its cause is `tool/specimen.py`, another lane's untracked file. The honest
finding is smaller than the brief's: `walls.py` was the only downstream victim.

## Residual — the thing I trust least in my own work

`walls_named` goes 0 -> **15**, not 0 -> 17. Two of the seventeen mending rows
still name no wall after the repair. I did not chase it and I am not claiming
the field is now correct everywhere - only that it is correct on the seventeen
rows the brief named, and that two rows have a second defect underneath this
one. Anyone reading `wall` as complete should start there.

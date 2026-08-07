# Result 3 — what the re-price does to verilog, for the lane measuring a press repair

Short version, for whoever is holding a baseline right now:

> **63,937 does not move. Not by one byte.** The peel's verilog worklist drops
> from 11,070 B to **21 B**. Those are two different instruments over two
> different runs and neither is a term in the other.

## The two numbers, and why they cannot be subtracted

`standing.py` on this pin (`strandprice`, `joints 1b4e50ce0`):

| | verilog |
|---|---|
| size | 94,657 |
| built | 30,720 |
| **damage = size − built** | **63,937** |
| roots | 3,544 |
| mends | 2,109 |

That comes from **one whole-file parse**. No peel runs, no byte is blanked, no
tail is cut. `damage` is the file the forest did not cover.

`walls.py run` on the same pin, same file:

| | verilog |
|---|---|
| prefix (before the first wall) | 3,712 |
| behind (priced across 40 distinct walls) | 11,070 |
| unpeeled (past where peeling stopped) | 79,875 |
| sum | 94,657 ✓ |

`behind` is a **partition of the file by which wall you would have to get past to
reach each stretch**. `Depth.behind`'s own docstring already says it is not
damage. The 6,591 B that turned out to be peel was a slice of *this* column, and
subtracting it from 63,937 would be subtracting a number measured by one
instrument from a number measured by another over a run that never saw the first.

If you want the peel's opinion of verilog after the re-price, it is this:

| stand | bytes | walls |
|---|---|---|
| `document` | **21** | 1 (`` ` in state 3438`` at byte 3,712) |
| `alias` | 3,401 | 8 |
| `torn` | 7,292 | 18 |
| `untested` | 356 | 13 |

**One wall stands, and it is 21 bytes.** Verilog's frontier is 12,466, deep enough
that most of its walls get a real verdict rather than an `untested`, so this is one
of the better-evidenced rows on the board.

## The eight `_identifier` walls no longer exist

The inherited finding is *verilog's eight `_identifier` walls are 6,591 bytes,
98.3% of them the `macro_text` path*. On this tree there are **zero** walls whose
terminal is `_identifier`. There are three whose terminal is `macro_text`:

| wall | bytes | turn | stand |
|---|---|---|---|
| `macro_text in state 562` | 2,483 | 2 | `alias` |
| `macro_text in state 513` | 2,262 | 4 | `torn` |
| `macro_text in state 164` | 1,732 | 37 | `torn` |
| | **6,477** | | |

6,477 is **exactly** the sub-figure the strand lane measured as the `macro_text`
share of 6,591. So this is the same population, renamed: someone landed
`06dcd26 fix: name a stuck byte by the shortest reading, not the widest one`, and
the lexer now reports the refusal under the terminal it actually stuck on. The
inherited 6,591 B figure is no longer reproducible on this tree, and its
`macro_text` sub-measurement is corroborated to the byte by an independent run.

**All 6,477 B of it is `alias` or `torn`.** None of it stands. So the direction of
the inherited claim holds for verilog even though its spelling moved.

## What to do with your baseline

1. **Keep 63,937.** It is the work order, it is `size − built` off one parse, and
   nothing in this re-price is a term in it. If a press repair moves it, the repair
   moved it.
2. **Re-pin before and after, in that order, and re-pin the control after the
   arm.** This lane found the tree moving underneath it inside one session: the
   `_identifier` → `macro_text` rename above is exactly the failure the pinning
   note warns about, and it changed the *name of the population* rather than a
   number, which no folio-sha comparison would have caught.
3. **Do not size the repair against the peel's verilog column.** It was 11,070 B
   and 21 B of it stands. If the repair is aimed at `macro_text`, aim it at what
   the whole-file parse does there rather than at what the peel prices, because
   6,477 of those 6,477 bytes are the instrument.
4. **`damage` and `behind` are not comparable and nobody in this tree was mixing
   them.** I predicted I would find at least one place already doing it and looked
   for one; every citation of 6,591 keeps it a peel figure. That prediction was
   wrong and the tree was cleaner than I guessed.

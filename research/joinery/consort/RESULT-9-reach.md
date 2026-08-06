# Result 9 — how far the blindness reaches, and what a `square` reading would move

`RESULT-5-blindness.md` established that 28 of the 33 boards on this disk never
read a `square` byte. That is a fact about *boards*. This is the fact about
*pages*: **347 markdown pages under `research/` and `changelog.d/`, of which 116
quote a number of ours — `damage`, `built`, `standing`, `worth`, `rubble`,
`spoil`, `orphan` — and never once quote a number of the oracle's.**

`onlydamage.py` does the classification and ranks by how much a sighted reading
could move the page: how many *comparisons* the page makes (a page that only
describes one measurement has no verdict to overturn), how many times it talks
about a **comment, docstring or other declared extra** (the class where
`damage`'s bias has a known direction), and whether it already carries a
tree-identity proof (which is oracle-free and does not need `square`).

**P10 is scored: RIGHT.** The blindness reaches far more than eight published
conclusions, and far more than three of them are about extras.

## The free settlements — pages this lane can close with data already taken

Four of the top ten need no new measurement at all. The base board of
`RESULT-8-sighted.md` is a sighted reading of every grammar those pages are
about, and its arms are a sighted reading of the very rows they seated.

| page | its claim | sighted |
|---|---|---|
| `vacuity/RESULT-2-arms.md` | fourteen rows, no collateral | **holds**, now on 24 columns incl. `square` |
| `vacuity/RESULT-5-pairs.md` | two pairs *cooperating* | **overturned** — every pair is a ceiling, and elixir joins them |
| `semi/RESULT-2-seated.md` | the separator seating moves exactly two grammars | **holds**, and the rows are worth far more than it claimed |
| `changelog.d/+ocamls-comments-…` | the day's one regression | **overturned** — the sign flips, +448 square |

`semi/RESULT-2-seated.md` is the happiest case: it priced the caesura rows on
`unbound` falling 12,712 bytes. Sighted, `_automatic_semicolon/.caesura/.kotlin`
is worth **30,830 square**, `_implicit_semi/.caesura/.swift` **13,874**, and
`_newline_before_do/.caesura/.elixir` **23,878 — eighteen times what `damage`
prices it at.** The page's conclusion survives; its own estimate of what it
achieved was low by an order of magnitude on one row.

## The ranking, and what settling each would cost

| # | page | why a `square` reading moves it | cost to settle |
|---|---|---|---|
| 1 | `research/joinery/bench.report.md` | the corpus-wide report: **70** extras mentions, seven comparisons, and it is what everyone else cites. It carries the ocaml regression this lane just inverted, and its `standing` table calls elixir a 100% grammar | **free for the headline** (below), ~4 min for a full re-board |
| 2 | `research/joinery/verilog/RESULT-1-wall.md` | the single biggest `damage` figure on the tree (63,937) and 14 extras mentions; three lanes have optimised against it | **free** (below) for the correction; an arm per construct otherwise, ~2 min each |
| 3 | `research/joinery/orphan/RESULT-2-wall.md` | 29 extras mentions and the page that *established* the orphan-vs-built trade — the exact bias direction | **free** (below) |
| 4 | `research/joinery/interior/RESULT-2-board.md` | five comparisons, 14 extras, no oracle number anywhere | ~4 min, one audited board |
| 5 | `research/joinery/layout/RESULT-1-scala.md` | scala's layout, 12 extras — and scala is the grammar whose whole square is 6,739 of 15,957 built | ~4 min |
| 6 | `research/joinery/reprice/RESULT-2-alias.md` | re-prices a seating on `damage` alone | ~4 min |
| 7 | `research/joinery/board/RESULT-2-flatter.md` | a page about the board flattering itself, taken on the board's own columns | ~4 min |
| 8 | `research/joinery/vacuity/RESULT-4-witness.md` | five comparisons of row worth, all on `damage` | free — `RESULT-8` covers its rows |

Everything below rank 8 is a page with one or two comparisons, where a sighted
reading resizes a number rather than changing a verdict.

## The three headline corrections, free, from the base board

These are the numbers a reader of those pages does not have, taken from the
same audited base arm as `RESULT-8-sighted.md`:

| grammar | size | built | **damage** | **square** | **crooked** |
|---|---|---|---|---|---|
| php | 67,845 | 67,845 | **0** | **67,845** | 0 |
| kotlin | 35,815 | 35,571 | **244** | **35,324** | 186 |
| elixir | 46,089 | 46,089 | **0** | **23,879** | **22,089** |
| verilog | 94,657 | 32,193 | **62,464** | **2,184** | **13,128** |
| haskell | 34,240 | 9,168 | **25,072** | **5** | 1,375 |

**`damage = 0` means two completely different things and `damage` cannot tell
you which.** php's zero is real: 67,845 bytes built, 67,845 square, nothing
crooked. **elixir's zero is not: it builds every byte of the file and derives
22,089 of them — 48% — under different parents than tree-sitter.** Any page
that reads elixir as a finished grammar because it stands at 100% is reading a
column that was never asked the question. This is the single sharpest
consequence of the blindness on the tree and it is free to state.

**verilog's wall is not overturned, it is re-pointed.** The 63,937-byte figure
is honest (`rack.honest` puts it at 68,119 once `stretch` is added back), and
the page's own headline paragraph — that the trap is real and larger than
advertised — survives. What the page cannot say is that the 32,193 bytes verilog
*does* build carry only **2,184 square against 13,128 crooked and 12,146
unframed**: of the bytes the oracle rules on structurally at all, **7.9% are
square**, and set square against crooked alone and six bytes in seven are
derived differently. Work
that converts damage into built on this grammar is, on today's evidence, work
that converts unbuilt bytes into misderived ones. That belongs in front of the
next lane that opens the file.

**orphan/RESULT-2-wall.md is the one that mostly survives**, and it is worth
saying so rather than only naming casualties. Its subject is kotlin, and
kotlin's sighted board is 35,324 square against 186 crooked — the grammar
really is nearly finished, so its orphan-vs-built argument was reasoning about
a tree that agrees with the oracle. The page's *mechanism* — a correct extra is
an orphan and a misread one is `built` — is exactly right and is what makes
every other page on this list suspect.

## The shape to look for

A page is at risk in a *known direction* when it does all three of:

1. quotes `damage`, `built`, `standing` or `rubble` and no oracle column;
2. is about a comment, docstring, string body or other declared **extra**; and
3. concludes that a seating **cost** something.

That is ocaml's fragment exactly, and it was wrong by 1,169 bytes in the
direction the mechanism predicts. `onlydamage.py --json` emits the full 116 with
their counts, so the list can be re-run rather than re-read as new pages land.

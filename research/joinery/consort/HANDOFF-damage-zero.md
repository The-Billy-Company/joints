# Handoff — `damage 0` is two different facts and the board prints one column

**Owner: whoever holds `tool/standing.py`** (`tool/rack.py` supplies the
verdicts it would print). Held by a live lane tonight, so this is a
recommendation and not an edit.

## The trap, from tonight's audited base board

| grammar | size | built | `damage` | `standing` | `square` | `trued` |
|---|---|---|---|---|---|---|
| php | 67,845 | 67,845 | **0** | **100.0%** | 67,845 | **100.0%** |
| html | 72,288 | 72,288 | **0** | **100.0%** | 72,288 | **100.0%** |
| elixir | 46,089 | 46,089 | **0** | **100.0%** | 23,879 | **51.8%** |

Three identical rows on the two columns every page in this repository quotes.
php and html are finished. **elixir builds every byte of `router.ex` and derives
22,210 of them under parents tree-sitter does not use** — 48% of the file, and
`damage` and `standing` are structurally incapable of saying so, because both are
outliner's own words about outliner's own forest.

This is not hypothetical damage to the record. `RESULT-9-reach.md` found 116 of
347 pages quoting our columns and never the oracle's, and the two most-cited
pages on the tree — `bench.report.md` and `verilog/RESULT-1-wall.md` — both
described a grammar's state from a column that had never asked the question.
`cpp/RESULT-1-crooked.md` and `unjudged/RESULT-5-tripwire.md` had already found
the shape from the other end and named elixir as the exhibit; what neither could
do was stop the board printing it.

## Why a note on a page is the wrong fix

The pages are downstream. A reader who copies a row out of `standing.py`'s output
into a new page copies a bare zero, and the correction has to be written again.
The trap is in the printer, and it survives every correction anybody makes to
prose.

## Three changes, cheapest first

1. **Never print `damage` in a row that has no `trued` in it.** When an audit was
   paid, `trued = square / size` is already computed. When it was not, print
   `trued —` or `trued unasked` rather than omitting the column, so the *absence
   of a second parser is visible in the row itself* and a page that quotes the
   row inherits the label. A blank column reads as "fine"; an em dash reads as a
   question nobody asked. This is the whole fix and it is one column.

2. **Split the `whole N of 30` tally, which currently means reach.** `whole`
   today is *one root over every byte* — a coverage fact that four pages already
   read as a correctness fact. Two tallies, named for what they are: `reached
   whole` (today's meaning, unchanged) and `agreed whole` (`trued == 100%`).
   On tonight's base board **15 grammars read `damage 0` and 13 of them are
   `trued 100%`** — the two that are not are elixir (51.8%) and toml (99.2%). The
   pair is self-explaining in a way a footnote is not.

3. **Stamp an unaudited board `unsighted` in its header.** The board already
   records the tree it read and refuses cross-tree comparison; the same header is
   the right place to record that no oracle was consulted. 28 of the 33 boards on
   this disk had never read a `square` byte, and none of them said so on their
   face — which is why the blindness spread by inheritance rather than by
   anybody's decision.

## The measurement to keep it fixed

`sighting.py --gate --since <ref>` fails when a page changed since REF reports a
measurement and never asks a second parser. It is read-only, needs no board, and
takes ~0.4 s over the whole record. Two blind pages were written in the 40
minutes after the first sighted board existed, so the population regrows at
roughly a page every twenty minutes of lane work; a gate is the only thing that
converts that flow into a fixed backlog.

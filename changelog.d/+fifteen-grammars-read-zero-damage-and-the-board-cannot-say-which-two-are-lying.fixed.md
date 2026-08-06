php, html and elixir all read **`damage 0` and `standing 100.0%`** — the two
columns every page in this repository quotes. php and html are finished. **Elixir
builds every byte of `router.ex` and derives 22,210 of them under parents
tree-sitter does not use**, 48% of the file. On the audited base board **15
grammars read `damage 0` and 13 of them are `trued 100%`**; the two that are not
are elixir (51.8%) and toml (99.2%).

A note on a page cannot fix that, because the next page copies the row and not the
note — which is what happened: `bench.report.md` read elixir off a `standing`
column as the rubble table's finished row. `cpp/RESULT-1-crooked.md` and
`unjudged/RESULT-5-tripwire.md` had already found the shape from the other end and
named elixir as the exhibit, and neither could stop the board printing it.

The fix is one column in the printer, handed to whoever holds `tool/standing.py`
as `consort/HANDOFF-damage-zero.md`: **never print `damage` in a row with no
`trued` in it, and print `trued —` rather than nothing when no oracle was asked**,
so the absence of a second parser is visible in the row instead of reading as a
pass. Two smaller changes ride with it — split the `whole N of 30` tally into
`reached whole` (today's meaning: one root over every byte) and `agreed whole`
(`trued == 100%`), and stamp an unaudited board `unsighted` on its face the way
it already stamps the tree it read. 28 of the 33 boards on this disk had never
read a `square` byte and not one said so, which is how the blindness spread by
inheritance rather than by anybody's decision.

Read-only in the meantime: `askance.py --grammars` prints
`damage`/`standing`/`trued`/`unvouched` one row per grammar, so the gap between
what we cover and what the oracle corroborates is arithmetic rather than prose.
Ranked by uncorroborated bytes it opens verilog 30,009, elixir 22,210, swift
10,860, scala 9,218, haskell 9,163.

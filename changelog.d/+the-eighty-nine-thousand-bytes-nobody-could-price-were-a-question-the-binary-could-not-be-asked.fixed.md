The peel's re-price left **18,146 B (15.0%) `untested`** and named exactly what
it was missing: enumerating mend sites, which was not in the binary. It is now.
`research/joinery/scars/seat.py` hands the peel that capability and the category
closes to **0 B**.

Not against the published 18,146 B, and that is deliberate. That labelling puts
swift's round-1 wall at byte 1492; a sibling has since landed a lexer fix and
today's binary reads to **24,582** before it refuses at all, so every swift wall
in that file is a wall that no longer exists. `seat.py` refuses to print a table
until every round-1 wall the board already found reproduces as the *first*
credited scar, and it caught this by exiting 1 rather than mapping across a
number that would have looked tidier. The resolution below is against a fresh
board on the arm pin, where the same instrument prices **88,975 B** untested -
a larger population than the one it was sent to resolve, not a subset of it.

| provenance | was | now | delta |
|---|---|---|---|
| `document` | 4,857 B | **11,211 B** | +6,354 B |
| `alias` | 0 B | **48,124 B** | +48,124 B |
| `torn` | 3,910 B | **38,407 B** | +34,497 B |
| `untested` | 88,975 B | **0 B** | -88,975 B |

**86,531 B (88.5%) is an instrument. 11,211 B (11.5%) stands.** That direction
flatters the re-price, so it ships bounded on both sides rather than as a
headline. If the cascade call is wrong the standing floor is **59,335 B**, not
11,211 B. And asking the same question of a `--mend=fell` parse - the peel's own
resume, where every segment reads a suffix from state zero - answers **70,330 B**
`document`, which is what a lane picking the convenient policy would have
claimed. Floor 11,211 B, disputed ceiling 59,335 B, convenient answer 70,330 B.

The hole itself is now a number instead of an argument. `Cold.canopy` asks "does
a node cover this byte"; under `--mend=keep`, **51,108 B of the 258,877 B under
a node (19.7%) was deleted by a repair anyway** - covered *and* walked past.

**Who else was blind, since anything reasoning from node coverage has the same
hole.** `research/joinery/scars/blind.py`:

- **The board does not paper, and that is a fact about its policy rather than
  its care.** `standing.py` parses `--mend=fell`, and felling puts the stack
  down at a break, so no construct root can reach across one and `papered` reads
  **0 B** on every row. The zero is a measurement because the other policy makes
  it enormous: under `--mend=keep` the same corpus builds **+62,990 B** more and
  **51,108 B (81%) of the gain is over bytes a repair deleted** - verilog alone
  is +61,445 B of it. Any lane tempted to switch the default because `built`
  reads higher under `keep` is reading that.
- `built` is honest about what it says and silent about context: **111,557 B of
  399,871 B (27.9%)** corpus-wide sits downstream of the file's first repair,
  and **61.9%** across the fourteen grammars that mend at all.
- `tool/rack.py` has **no scar-aware column**, and `square` is a subset of
  `built`, so the exposure is bounded rather than guessed: **19.9%-23.0%** of
  its 311,540 squared bytes. 96 B is provably out of context by arithmetic -
  ruby, haskell and markdown build nothing before their first repair. The
  finding is that `square` wants a companion column, not that rack is wrong; its
  own argument, that `square` is the one column a stretched root cannot buy, is
  untouched, because a repair is not a stretched root.

The prediction that verilog would *not* dominate was wrong and backwards:
verilog is **48,967 B of the 51,108 B papered (95.8%)**, swift 490 B. I had
reasoned from warm's frontiers, which measure how far a 400-round budget got and
not how much file lies past it - the same class of mistake this dossier is
about, made about my own instrument.

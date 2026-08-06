# `covered` is a watermark too, one level down

Handoff to the bench lane, which owns the board and its columns. **Nothing here
edits the report.** The raw measurement is checked in beside this file as
`standing-audit.json`, thirty grammars, and the instrument that produced it is
[`tool/standing.py`](../../../tool/standing.py) - promoted out of a lane's
`.local/` scratch so it survives the person who wrote it.

## The finding

`reach-audit.md` retired `reach` because a watermark cannot see a hole, and
replaced it with `covered`: the union of the top-level root spans. That was
right and it is still right. It is also not the last watermark in the stack.

`covered` counts a byte as read when a **bare leaf token** stands over it - and
a mend leaves exactly that, a lone token where a subtree should have been. So a
file the parse shredded into 2,596 one-token roots and a file it parsed whole
can report the same `covered`, and the shredded one has no structure at all.

Split the number by whether the root covering a byte is a **construct** (has at
least one child) or a **leaf** (has none):

```
covered  = built + strewn      did the parse READ these bytes
standing = built               did it UNDERSTAND them
```

Over all thirty: **73.0% covered against 56.1% standing.** A sixth of every byte
this project currently calls read is a token lying where a tree should be -
89,146 bytes of it.

## The grammars where the two numbers disagree most

Full table in the JSON; these are the rows that change what the board says.

| grammar | covered | standing | gap | strewn bytes | roots / leaves |
|---|---:|---:|---:|---:|---:|
| swift | 77.0% | 27.4% | 49.6 | 14,134 | 1,883 / 1,371 |
| kotlin | 91.5% | 42.8% | 48.8 | 17,464 | 1,155 / 702 |
| ruby | 85.6% | 37.5% | 48.1 | 491 | 68 / 47 |
| bash | 96.2% | 59.5% | 36.7 | 392 | 37 / 21 |
| c | 96.4% | 60.4% | 36.0 | 520 | 28 / 18 |
| julia | 67.2% | 35.0% | 32.2 | 8,800 | 2,596 / 1,724 |
| go | 59.9% | 29.3% | 30.6 | 364 | 39 / 21 |
| sql | 90.6% | 62.1% | 28.5 | 1,822 | 194 / 136 |
| cpp | 94.1% | 69.0% | 25.1 | 353 | 29 / 13 |
| haskell | 23.1% | **0.0%** | 23.1 | 7,915 | 90 / 90 |
| verilog | 49.3% | 29.9% | 19.4 | 18,348 | 3,865 / 2,707 |

Ten grammars parse whole - one root, no gap by construction. yaml is 0/0: it has
no lexable terminal at all, so there is nothing for either column to measure and
it should not be read as "no gap".

**kotlin is the row that reorders the board.** 91.5% covered reads as nearly
finished; 42.8% standing with 17,464 bytes under leaves says the opposite. Its
wall count is not what is wrong with it.

**haskell is worse than any column has said.** 23.1% covered, **0.0% standing**,
ninety roots and ninety leaves - not one construct in the file. Every byte it is
credited with is a bare token. A grammar at 0% standing is not partly working.

**c, bash, cpp, go and ruby are the same shape at corpus scale.** All five sit
in the nineties on `covered` and the fifties-to-sixties on `standing`. They are
small files, so the byte counts are small, but the *ratio* is the same defect as
kotlin's and they are cheaper to chase.

## Why carry both rather than replacing one with the other

Because they move independently, and reading either alone gets a real change
wrong in opposite directions. The engine fix that landed this round moved julia
21.2% -> 67.2% covered, +12,579 bytes. Of those, **8,847 landed under a
construct and 3,732 under a bare token**: identifiers that now lex correctly
inside a docstring whose external scanner still walls, so they are named rubble
rather than tree.

Reporting `covered` alone would have overclaimed roughly five thousand bytes.
Dismissing the gain on a spot-check of the tree - which was the first
impression, and the tree does look like rubble - would have thrown away 8,847
real ones. Neither number is the honest one on its own.

swift's +7,848 from the same fix landed almost entirely under constructs, which
is why its `standing` moved and julia's moved less. Same headline, different
meanings.

## Reproducing

```bash
python3 tool/standing.py            # the table, worst standing first
python3 tool/standing.py --gap      # worst gap first, which is the work order
python3 tool/standing.py --json     # what is checked in beside this file
```

It reads the same roster `walls.py` reads and mints its own folio through
`order.folio_for`, so a grammar added to either set is measured here with
nothing to update, and a folio older than the binary is re-pressed rather than
believed. Every run carries a `stamp` line; the one in the JSON beside this file
is not stale.

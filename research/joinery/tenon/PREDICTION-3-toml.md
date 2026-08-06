# Prediction 3 — toml, and the instrument that reported it

Written before any measurement. `rack`'s own author says it thinks `rack`
decides wrong on toml's 29 bytes and reported them anyway. Adjudicating that is
worth more than the 29 bytes, so it gets its own predictions.

## P7 — `rack` does decide wrong on toml

toml's whole disagreement is where a `comment` hangs, and `comment` is a
declared `extra` in `toml.json`. An extra attaches wherever a parser chooses,
so charging its bytes to whichever spine it is not on is a statement about
attachment policy and not about a misread. `rack soft` will attribute the
**majority** of toml's crooked bytes to extras placement.

**Falsifier.** `rack soft` attributes under half of toml's crooked bytes to
`blank` + `extra`, or the disagreeing bytes are not the comment's own.

## P8 — and there is a real toml defect it is not reporting

`rack.py`'s own `cover()` docstring records that `standing.py` reports toml
`UNSOUND — child outside its parent`, on one of the twelve grammars the board
calls perfect. A child outside its parent is a worse structural claim than a
misplaced comment, and it is not in the 29 bytes.

**Falsifier.** toml no longer reports UNSOUND, or the unsoundness turns out to
be the same comment and therefore the same soft finding.

## P9 — the GAP/CONFLICT axis does no work on this population

The closure that earned its verdicts on verilog was built for **walls** —
positions where a parse stops. Mine are positions where a parse succeeds with
the wrong shape, so the derivation demonstrably exists on both readings by
construction. I predict the closure returns **CONFLICT on all four** and
therefore separates nothing, and every verdict in this lane has to be earned
from the table instead.

**Falsifier.** Any one of the four returns GAP. That would be the more
valuable answer — an unseatable wrong shape — and I would rather be wrong here.

# Prediction 2 — Tier B, what the sealed twenty comes back with

Written before selection ran, and before any holdout grammar was fetched,
pressed or parsed. `SELECTION.md` in this directory carries the rule, and it was
written and committed to before it was executed — that ordering is the whole
point of both files.

The number these are predictions about is **`trued`**: `square / size`, where
`square` is bytes whose derivation tree-sitter defends, renames excused. It is
the board's own floor, computed by the board's own code path
(`plumb.read` → `rack.survey` → `standing`'s soft rule), not a second copy of
it. The working corpus reads **50.4%** today.

## P2.1 — the holdout's trued rate comes in below 25%

Half the corpus number. The brief predicts "well below 50.4%" and I am naming a
figure so it can be wrong in a stated direction. The reasoning: the corpus's
50.4% is carried by twelve grammars the board reads whole, and those twelve are
whole *because a month of walls was fixed against them*. Nothing has ever been
fixed against a holdout grammar.

**Falsifier:** 25% or above. If it lands near 50.4% the polyglot claim is real
and this is the strongest evidence the project has produced; if it lands near
zero the claim needs rewriting today. Either falsifies this.

## P2.2 — no holdout grammar reads 100% trued

Twelve of thirty do in the corpus. I expect zero of twenty here, because
`trued` requires the whole derivation to match on every byte, and a single
unseated external anywhere in a file fells the stack for the rest of it.

**Falsifier:** any holdout row at 1.000. That would be the single best result
available from this lane — an unseen grammar and an unseen file, byte-exact
against tree-sitter, with nothing tuned toward it.

## P2.3 — unseated externals dominate the failures, not tables

Operationally: among holdout rows with `trued < 0.5`, **more than 70% declare at
least one external the press reports as unlexable**, and **fewer than 25% carry
any RESIDUAL cell**. This is the brief's own prediction and I expect it to hold,
which is why P2.4 and P2.5 below are aimed at the places I think it *won't*.

**Falsifier:** either threshold missed. In particular, if RESIDUAL is common
among the failures, the press's conflict resolution — which the corpus says
reaches zero residual on eleven grammars — is overfitted to eleven grammars.

## P2.4 — the corpus's own trued, re-measured by me in the same run, is not 50.4%

I will not quote 50.4% from the brief. A comparison whose two halves were taken
by different instrument versions against different oracle libraries is not a
comparison, and this tree has already been bitten by exactly that: the same
script read scala at 1,278 crooked in one run and 9,087 in the next off a
byte-identical stamp. `rack.py` is under repair *right now* by another lane.

**Falsifier:** my re-measure lands within ±0.5 points of 50.4%. That would be
good news about the tree's stability and would mean I could have quoted it.

## P2.5 — the gap between the two numbers is NOT a clean estimate of overfitting

The holdout also differs from the corpus in **what its files contain**. If
`absent.py` reads the holdout's twenty files as presenting a *lower* share of
their grammars' declared spellings than the corpus's 39.4%, then part of any gap
is the holdout's files being thinner, not the grammars being unseen — and part
runs the other way, since a thinner file is an easier file.

I predict the holdout presents **below 39.4%**, and therefore that the raw gap
over-states overfitting on the file-thinness axis and under-states it on the
difficulty axis, with no way to net the two from this lane alone.

**Falsifier:** the holdout presents at or above 39.4%. Then the two populations
are comparable on the one axis anybody measured, and the gap reads more cleanly
than I am claiming.

## P2.6 — at least three of the twenty cannot be measured at all

`unaudited`, `absent oracle`, `nothing built`, a `tree-sitter generate` that
fails, an external scanner that will not compile. **Absence is its own outcome
and is never a zero**: `specimen.py`'s `stop()` defaulted a missing stop line to
one root and no mends — the exact shape of a perfect parse — and scored a file
HELD against a binary that had not read a byte of it.

**Falsifier:** all twenty produce a live verdict. Then the machinery travels
further off-corpus than I expect.

## P2.7 — I can violate my own seal, and the ledger will catch me doing it

Not a prediction about the parser. `collate.py prove` corrupts a verdict in
memory to confirm the gate can still say no, and that is the pattern here. I
will attempt to read a holdout grammar's per-wall detail through the gate, and
the gate will refuse; I will then unseal one deliberately and show that the
grammar is permanently retired out of the twenty and into the working corpus,
with the reason recorded.

**Falsifier:** the gate hands me sub-grammar detail without an unsealing, or an
unsealing leaves the holdout at twenty.

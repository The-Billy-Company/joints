# Prediction 2 — where the 18,146 B fall, and who else was blind

Written before running the resolver. Same pin discipline as Prediction 1: no
parse has been run for this lane.

## What the question actually is

`../reprice/` prices 120,832 B of peel over five provenances and leaves
**18,146 B (15.0%) `untested`** — walls past the furthest byte any warm round
reached, so neither claimed as real nor dismissed as the instrument's own. It
declined to resolve them because the only test it had was the warm peel, and the
warm peel could not see that far.

The test I am handing it is different and stronger. `cut.stand` calls a wall
`document` when **round 1 — the whole file, as the author wrote it — refused at
that byte**. That is not a byte-coverage question and it is not a second parse
with something blanked; it is a direct read of what the parser did on the file
itself. A scar list makes it answerable for every byte, frontier or no frontier.

**The flattering direction is `instrument`.** Every untested byte that resolves
as torn or alias makes the re-price's 81.1% headline bigger. Every one that
resolves as `document` makes the parser look worse and raises the standing floor
that the re-price worked hard to get *down* to 4,749–4,751 B. I am predicting
both move, and I am naming the shape of a result I would disbelieve.

## Predictions

**P5 — the majority resolves as instrument, and that is not a win.** I predict
**over 60%** of the 18,146 B carries no round-1 scar at its refusal byte and
therefore resolves as the peel's own resume artifact, consistent with the 81.1%
the re-price already found on the bytes it could test. Falsifier: under 40%,
which would mean the untested tail is qualitatively unlike the tested body and
the re-price's headline does not generalise past its frontier.

**P6 — but the standing floor goes up, by a lot in relative terms.** I predict
**1,500–6,000 B** of the untested set lands on a real round-1 scar, taking the
corpus standing floor from 4,749–4,751 B to somewhere in **6,300–10,700 B** —
a 1.3x to 2.3x increase in the damage this parser genuinely owns. Falsifier
either way: under 500 B, or over 9,000 B.

**P7 — a result of "essentially all instrument" should be disbelieved.** If the
resolver comes back with **over 95%** of the untested bytes as instrument and
under 900 B standing, I will treat that as evidence my join is broken rather
than as a finding, and say so. That shape — a new instrument arriving to
retroactively confirm the previous instrument's most flattering reading, on the
exact population the previous lane refused to guess about — is the thing this
tree has caught four times this month.

**P8 — swift dominates and verilog does not.** Warm's frontiers are 1,906
(haskell), 2,904 (swift), 4,390 (sql), 12,466 (verilog), and the twenty-one
grammars whose warm run reads to end-of-file contribute no untested bytes at
all. I predict swift is **over half** of the 18,146 B by itself, and that swift
resolves overwhelmingly *instrument*, because `../reprice/PREDICTION-2-alias.md`
already showed swift's post-1492 walls are one refusal re-reported. Falsifier:
swift under a third of the total, or swift resolving majority-document.

## Who else reasons from "a node covers this byte"

**P9 — the board is blind in the same place, and it is not a small blindness.**
`tool/standing.py` prices `built` and `covered` from node spans. A byte under a
node built *after* a mend restarted the stack at state 0 is counted exactly like
a byte under a node built in context. I predict that on the 30-grammar board,
**over half of all `built` bytes sit downstream of the first scar in their
file**. Falsifier: under 20%, which would make this a real but marginal hole
rather than a headline. I am not predicting the board is *wrong* — `built` is
outliner's own word about its own forest and it never claimed context — only
that it cannot currently be asked the question.

**P10 — `tool/rack.py` is blind differently and worse.** `square` is a claim
about agreement with the oracle: our leaves under the oracle's parents. A leaf
built after a mend can still sit under the right oracle parent by accident, and
`square` will book it as agreement. I predict rack has **no scar-aware column at
all** and that the share of squared bytes that are downstream of a mend is
**above 30%** on the mending grammars (haskell, swift, sql, verilog). Falsifier:
under 10%. If it holds, `square` needs a companion column and this lane should
say so rather than fix it — rack is an instrument lane's file.

## Tree-sitter

**P11 — level on enumeration, ahead on attribution, behind on insertion.**
Tree-sitter reports repairs as `ERROR` and `MISSING` nodes in the tree.
`MISSING` is an *insertion* — the token the grammar wanted, materialised
zero-width. `gather.mended()` only ever deletes, so we have no `MISSING`
equivalent and cannot get one without a runtime change out of this lane's
scope. I predict the honest scoreboard row is: **level** on "can a consumer
enumerate every repair site" (after this lane; before it, we could not),
**ahead** on per-site cost attribution (bytes deleted, tokens since, felled,
root count, refusing state — Tree-sitter's `ERROR` node carries none of that),
and **behind** on insertion repair, which is a capability gap and not a
reporting one. Falsifier: finding that Tree-sitter's `ERROR` node does carry
cost detail I have not accounted for, in which case "ahead" is wrong.

## What I am not predicting

Whether the untested bytes that resolve as `document` are *good* damage — that
is, whether the parser refusing there is the grammar's fault or ours. That is
`../owners/`'s question and it has a five-column table for it. I am answering
provenance, not ownership.

# Prediction 2 — provoking the mixed-generation board

A fix for a race that was never made to fail once is not a fix. The event to
reproduce is the one that happened: **a re-mint of the whole folio cache lands
while the board is walking it**, so the rows measured before the publish read
one generation of folio and the rows after read another, and the atomic publish
guarantees no reader ever sees a torn byte to notice it by.

## The construction

Two real processes, because the hazard is ten interpreters on one directory and
a thread would share the pid the temp filename is made unique with:

- the board, over a **private cache** (`JOINTS_WORK`), so the shared
  `.local/standing` that nine other agents read is never touched;
- a re-minter that waits a beat and then republishes every folio in that cache
  through `order.press` - the real function, the real `os.replace`.

The poison has to be a *different* generation, not the same bytes rewritten.
Prediction 1 decides how to get one: if minting is deterministic the re-minter
must run an **older pinned binary** (`.local/bench/pin/joints`, built
2026-08-04), the way the previous lane used a real older binary rather than a
staged corruption. If minting is not deterministic the same binary suffices.

## Predictions

1. **The board today says nothing.** `cache:` reports `kept 30` (the cache is
   asked before each row, and each folio is present and fresher than the binary
   at the moment it is asked), and no `stamp:` warning fires, because the
   re-minter touches no file under `src/` and `MOVED` surveys `src/`.

   *Falsifier:* any line of today's output that names the split.

2. **The split is real and lands mid-table.** With the board at ~0.8s over
   thirty rows (~27 ms a row) and a re-mint of thirty folios costing a press
   each, at least one row is measured before the publish and at least one after.

   *Falsifier:* the re-minter finishes entirely before the first row or entirely
   after the last, in which case the stage is not exercising anything and the
   timing has to be moved rather than the claim weakened.

3. **The new rule names exactly the rows on the old side.** Every folio the
   re-minter replaced after that folio's row read it comes back with a
   read-time digest that disagrees with the reconcile digest; every row after
   the publish agrees. So the count of flagged rows is the number of rows that
   ran before the publish, and it is not zero and not thirty.

   *Falsifier:* the flagged set is empty, or all thirty, or does not form a
   prefix of the row order.

4. **A same-binary re-mint is quiet.** If Prediction 1 holds, running the exact
   same stage with the *current* binary as the re-minter flags nothing at all -
   thirty folios republished, thirty atomic renames, and one generation, because
   the bytes never changed. This is the control that separates "the file was
   replaced" from "the measurement changed", and it is the half an mtime rule
   gets wrong.

   *Falsifier:* the control flags any row.

## What I am NOT predicting

I am not predicting the board's numbers change. Two generations of folio minted
by two binaries a day apart may well parse the corpus to the same byte, and if
they do, the mixed board is *numerically* fine and still unattributable - that
is the whole point. A rule that only fired when the number moved would be the
same instrument one level in.

`stamp.Ledger.moved` and `republished` read `[]` on all 76 ledgers this tree
has written. A ledger whose whole purpose is naming the artifact that moved
under a run has never named one, and `stamp.py --hazards` has always shown its
SPLIT detector firing.

Both are true, because `--hazards` plants the sighting itself. What nothing
asked is where sightings come from. `ask` feeds the grammar and the binary;
`order.press` feeds the binary; **nothing fed the folio** - and the folio is
the one artifact in this system that gets re-minted while boards are running.
`reconcile`'s own docstring is about that event and names the clock on it: a
sibling's `zig build` landed at 11:43:49 and something re-minted all thirty
folios between 11:43:55 and 11:44:04 while a board was running and printing
`cache: kept 30`. The ledger watching that run was watching thirty
`grammar.json` files, which are checked in, and one binary, which was not
replaced. It truthfully reported that nothing moved. `Ledger.artifacts` reading
`31` on all 76 rows - thirty grammars and a binary - is the same sentence said
in a number.

`order.folio_for` is the seam and its own docstring says so: "a folio of our
own this binary will actually read". Both of its returning branches - `kept`
and re-minted - now feed it.

Falsified by a new `stamp.py --plumbed`, which asks the question `--hazards`
structurally cannot: not *does the detector fire* but *is it ever shown the
artifact*. Two temp files, one rewritten under the run and one republished with
identical bytes and a new mtime, prove `moved` names the first with its row and
`republished` tells the second apart. Then the real `order.folio_for` is driven
twice against a private `JOINTS_WORK` - once minting, once kept, never into
the cache ten agents share - and the folio must be in `FED`. Take the two new
lines back out and exactly those two rows go red while the two detector rows
stay green.

One trap worth recording, because it would have made the falsifier lie rather
than fail: run as `python3 tool/stamp.py`, this module is `__main__`, and
`order`'s `from stamp import fed` imports a **second copy** of it with a second
`FED`. Asserted against the local dict, the check reported zero artifacts fed
whatever `order` did.

The two columns stay red on the board, correctly. The plumbing is repaired and
the detector is proven; the column fills the first time a re-mint actually
lands mid-board, which is a real event on this tree and not one to manufacture.
Writing a plausible `moved` into a document to green the row is the defect this
whole instrument exists to catch.

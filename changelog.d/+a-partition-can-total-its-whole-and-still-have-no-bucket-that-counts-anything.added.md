The board's audit gate asserted `square + crooked + soft + unframed + unaudited
== built`. That assertion passed on all three arms where `crooked` read
*negative*, because `203 − 8,669 + 9,687 + 12,287 + 42` totals `built` exactly.
It was written to catch a redefinition of `built` and is structurally blind to a
redistribution inside it: `soft` is added to one bucket and subtracted from
another, so it cancels whatever population it was sampled from. A fourth
assertion added later fires on a negative bucket, which catches the arms where
the borrowing exceeded the balance — the tail — and certifies the six base rows
where it did not.

The property neither expresses is that a bucket must be a count of the bytes it
names. So `soft` now carries what it was summed from. `Held.drawn` records the
per-kind tally — `askew 56, racked 30` — and the gate asserts, per row, that
every kind in it is a kind `crooked` counts and that the recorded widths total
the `soft` the row printed. A cached verdict from before the field existed, with
`soft > 0` and no recorded population, reads as unattributable rather than as
clean and says to re-run `--audit`; that is the same amount of evidence as a
wrong one. `audit()` also checks its own copy of the definition: the runs it
believes are crooked must total `rack.Seen.crooked`, because a copy of a
definition drifting from the original is exactly how this arrived.

Proved by breaking it. `research/joinery/consort/restore.py` restores the
shipped sample rule into a sibling work dir — never into `tool/standing.py`,
because ten lanes share this tree and a two-minute window in which the board is
wrong on disk is a window somebody else measures in — copies the arm's folios
across so every digest matches, and hands the board the cache that rule would
have written. It refuses to report unless its `crooked` and `soft` equal a kept
pre-fix cache on every row, so what it demonstrates against is the shipped bug
and not an imitation of it: 30 of 30 rows match.

Reading that cache, the board turns **1 of 8 gates red** and names exactly the
six rows and their exact overdraws — haskell 708, ocaml 30, cpp 21, swift 14,
sql 3, julia 2, totalling the 778 bytes the repair moved. The other seven gates
stay green, and that includes both audit gates that already existed: the sum
identity and the no-negative-bucket check both certify the borrowing partition,
on the same run, in the same table. Passing them means the arithmetic closed.

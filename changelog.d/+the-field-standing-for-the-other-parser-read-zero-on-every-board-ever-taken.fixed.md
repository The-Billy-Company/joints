`still.take` records the world one arm was measured in, and one of its fields is
the oracle — the second parser `square` is a claim of agreement with, and the
only input on the board whose drift would move every correctness number without
touching a byte of ours. Every witness on disk reads `0 oracle(s)`. Both of the
two that were taken by a run which really did shell out to `tree-sitter` read it
too.

The population rule took **the stem of every `.json` the run was fed** and asked
`oracle_home` about it, so a run that fed `lang/latex/src/grammar.json` looked up
a grammar called `grammar`, found nothing, and reported no oracles. There is no
input for which that rule returns anything: a grammar's file is always called
`grammar.json`, so the stem is always `grammar`, so the answer is always zero.
Meanwhile `attest.SEATED` — the court, recorded at consult time by the two
instruments that actually put a question to tree-sitter — sat in memory unread.

`seen_oracles` now reads the seated court, and falls back to recovering the
grammar from the *fed path* rather than from a filename, so an instrument that
consults an oracle without going through `attest` is still witnessed. A board
seats its court through the new `attest.attribute`, which is `consult` minus the
two side effects a board has no business paying: it neither feeds the oracle's
sources into the generation ledger nor digests scala's 28 MB `parser.c`, because
a board reading a cached verdict opens neither. What it records is the judge its
numbers are *attributed* to, and the witness says `attributed` rather than
`consulted` so the two can never be read as the same claim.

A board's footer now reads `30 oracle(s) d85e736fa attributed`, which is the same
digest the derivation comparison has been printing all along, and the two can
finally be checked against each other.

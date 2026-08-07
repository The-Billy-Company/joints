A lane read scala at **1,938** where prior runs read **1,278** and **9,087** and
warned that no before/after on a tail row meant anything until that was
resolved. Two of the three are explained and the explanation is arithmetic:
`rack.crooked` is 9,087, scala's `soft` is 7,149, and `standing.audit` prints
their difference. Both numbers have been quoted as "scala's crooked" in this
repository. That is a naming defect and the board is not nondeterministic — 900
numbers over five runs on one pin do not move, and they do not move when every
folio is re-pressed between runs either, which also re-confirms the 30/30
byte-reproducible press.

The third number is why the guard changed. `Held` carried three digests — folio,
binary, source — **and all three describe joints.** `crooked` is a comparison
of two parsers, and the second one was unattributed: a sibling regenerating one
grammar's tree-sitter sources moved the number while every guard on the page read
clean and the row printed `graded: read`.

`Held` now carries a fourth, `attest`'s per-grammar oracle identity
(`<source-digest>/<cli version>`), and a verdict whose oracle moved prints
**`other`** rather than `stale` — different news, because `stale` says the thing
being judged moved and `other` says the *judge* did. Demonstrated on real data
rather than staged: the audit cache written before this change carries no oracle
and the new board refuses all thirty rows. Cost is **283 ms** on an audited
board and zero on an unaudited one, because the identity is computed only where
there is a verdict to attribute.

What that guard is **not**: proof that a rebuilt oracle moves a number. Two
seats holding two byte-different `scala.dylib` files built four minutes apart
from identical sources returned **thirty identical verdicts**. The library is
not the identity; the sources are, which is what `attest` already argued and
this had treated as a detail. So 1,278 stays unexplained and bounded — one
reading, one instrument, one afternoon in a tree with no oracle attribution at
all — and the guard now keyed on sources is the reason it cannot recur silently.

Found on the way, and it was on the page the whole time: the board's own
partition check was **red on 14 of 27 audited rows** before any of this was
touched. `rack` grew an `unframed` bucket and took it out of `square`;
`standing.audit` never learned, so `square + crooked + soft + unaudited` was
short by exactly that — 105 bytes on c, 178 on markdown (*its entire file*),
18,354 on php, 60,067 corpus-wide. `Held` carries `unframed` and the check is
green on 27 of 27.

The way this project loses a guard is by adding a field and not adding the case
that notices the guard is ignoring it, which is precisely what happened to
`unframed`. So every run now offers each live verdict back four times with one
digest replaced and asserts all four are refused, on 27 of 27.

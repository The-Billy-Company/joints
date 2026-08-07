# twice — is the board reproducible, and if not, why

A lane read scala's `crooked` at **1,938** where prior runs read **1,278** and
**9,087**, and warned that until that was resolved no lane's before/after on a
tail row meant anything. Several lanes were producing exactly such comparisons
at the time.

**The board is deterministic.** 900 numbers over five runs on one pin do not
move, and they do not move when every folio is re-pressed between runs either.
The press is still 30-of-30 byte-reproducible, checked rather than trusted.

**Two of the three numbers are two different columns**, and the arithmetic
between them is exact: `rack.crooked` is 9,087, scala's `soft` is 7,149, and
`standing.audit` prints their difference — 1,938. Both have been quoted as
"scala's crooked" here. That is a naming defect, not an instability. **1,278 is
unexplained and bounded**: one reading, one third instrument, one afternoon in a
tree that recorded no oracle identity at all. It predates the guard that would
have caught it and the state that produced it is gone.

Predictions were written before the measurements that judge them; results and
the honest score are in [RESULT-1](RESULT-1-board.md).

| # | Prediction | Verdict | Result |
|---|---|---|---|
| 1 | the board is deterministic across runs, folio and press | held | [RESULT-1](RESULT-1-board.md) |
| 2 | the 7x is columns, and the cache lies about which pin made an artifact | held, except P5 | [RESULT-1](RESULT-1-board.md) |
| 3 | `oracle_build` is an unlocked mutation, and it wrote the divergence | **3 of 8 wrong, and the shape is worse than predicted** | [RESULT-2](RESULT-2-oracle.md) |
| — | the instrument I trust least, and why its own check did not clear it | — | [RESULT-2](RESULT-2-oracle.md#the-predictions-scored) |

## Nobody has two oracles

Three lanes measured three different populations and read them as one dispute.
[RESULT-2](RESULT-2-oracle.md) reconciles them: **159 oracle source trees, 30
grammars, zero divergent authored bytes.** The copies that looked like several
parsers are two artifacts of our own instruments — a pre-seat library orphan that
gets rebuilt before it can answer (53 bytes from its seat's own), and a generated
`parser.c` that a scanner refresh deleted while rewriting a file with its own
contents. Both self-heal on first use, which is why nothing measured against
them was ever wrong.

`oracle_build` was a genuine unlocked mutation of a shared tree — nine of twelve
callers took the lock, three did not — and racing it produced one torn tree and
**three silent readings of the other arm's grammar**. The lock lives in the
writer now. That makes four instruments with one failure mode, and the shape has
a name: *the comparison's setup writes to the thing being compared*, so the error
is always in the direction of agreement and the falsifier runs too late to see
it.

**P5 failed usefully.** I predicted a sibling *rebuilding a tree-sitter dylib*
was the mechanism behind 1,278. Two seats holding two byte-different
`scala.dylib` files, built four minutes apart from identical sources, returned
**thirty identical verdicts**. The library is not the identity; the sources
are — which is what `attest` already argued and I had treated as a detail, and
it is why the guard I built is keyed on sources.

## What changed

| | |
|---|---|
| `tool/order.py` | a folio carries a ticket naming the binary that pressed it; `miss` compares digests instead of asking an mtime which binary made a path |
| `tool/standing.py` | the audit verdict carries the **oracle**'s identity as a fourth digest, and `unframed` — which had been silently breaking the board's own partition check on 14 of 27 rows for four days |
| `tool/standing.py` | default order is `max(damage, crooked)` with a `by` column, because the two partition the file and each is blind to exactly the other |
| `tool/standing.py` | `--twice[=N]` and `--against=FILE` — the stability guarantee a lane can run |
| `tool/pin.py` | `arm` prints the three exports a measurement needs: binary, its own folio cache, its own oracle seat |

## The pins every number here was taken against

| Half | What | Digest |
|---|---|---|
| A | `.local/pin/tenon/bin/joints` | `fa7fcaee5e14`, built 2026-08-06T00:05:08Z |
| B | `.local/pin/derive-only/bin/joints` | the second arm of the two-pin cache staging |
| oracle | seat `twice` | `d952e2aa2c90` / tree-sitter 0.26.11 |
| oracle | seat `twice2` | same sources, a **separately built** `scala.dylib` — the P5 falsifier |

Each arm ran in its own `JOINTS_WORK`, from empty, which is the rule this lane
then made the cache enforce rather than ask for.

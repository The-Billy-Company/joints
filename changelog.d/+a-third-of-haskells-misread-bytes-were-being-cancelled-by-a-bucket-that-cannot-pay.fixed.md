One arm printed `crooked = −335` and the board's own consistency check passed.
Reproduced across twenty-one fresh arms it is **−8,669**, on three of them, all
scala, all with scala's `block_comment/.marrow/.kotlin_block` row ablated. The
check passes because the five buckets still total `built`
(`203 − 8,669 + 9,687 + 12,287 + 42 = 13,550`) - a bucket that overdraws from
its neighbour leaves the sum alone, and the check was written to catch a
redefinition of `built`, not a redistribution inside it.

**The cause is a population mismatch that `rack.widest()`'s own docstring
predicts in so many words.** `standing.audit()` computes `soft` over
`seen.worst`, subtracts it from `seen.crooked`, and `seen.crooked` is
`askew + racked` and deliberately nothing else - while `seen.worst` is the widest
runs **of each kind**, and `unframed` is a kind. Un-seat scala's comment vein and
tree-sitter frames construct after construct we never build; every one of those
frames is named `comment`, which is a declared extra, so all of them qualify as
soft. `soft` becomes a near-copy of `unframed` (9,657 of its 9,687 bytes) and is
charged against a `crooked` of 1,018.

**The negative is only the tail.** The same overdraw is live on the base board
right now, on six of thirty rows, always shrinking `crooked` in the flattering
direction: cpp's entire soft sample is `unframed`, julia's is, sql's is, and
**haskell's `crooked` reads 1,375 where its own runs say 2,074 - understated by
34%.**

`research/joinery/consort/borrow.py` reproduces it per grammar and prints, beside
the charged figure, what the charge would be if the sample were restricted to the
kinds `crooked` contains - so whichever repair the owning lane picks can be
checked rather than asserted. **Not repaired here**: the two defensible fixes
(restrict the sample, or move the subtraction into `unframed`) differ on what
`soft` is a sample *of*, which is `tool/rack.py`'s question and another lane's
file this hour. Handed over with the evidence in
`consort/HANDOFF-crooked.md`.

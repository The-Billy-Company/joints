`comment/.marrow/.ocaml_comment` seats a `marrow` vein for ocaml's nesting
`(* *)`, so the parser stops reading comment prose as code. It is the **only
seating today whose grammar got worse on the board**: damage 1,461 → 2,182,
standing 91.34% → 87.07%, and it is the row that had no fragment of its own.

The cost is real and it is the right direction. ocaml's `rubble` - bytes of
genuinely unstructured code, the column `bench.report` says to trust - falls
**293 → 88**, and the orphan column that read a suspiciously round **0** against
a comment-bearing file now reads 1,829, because comment bytes are finally
covered by comment leaves instead of by constructs folded over prose. `standing`
counts bytes under constructs, so deleting structure that was never structure
has to show as a loss on it. Same shape as scala's `/* */` vein in the same
landing: −1,855 corpus rubble, +0.8 covered, **−1.1 corpus standing**.

Published, not hidden - the trade was argued in `research/joinery/bench.report.md`
and carried in `orphan/RESULT-2-wall.md` when it landed. What was missing was a
fragment, and the day's one regression is the wrong row to leave undocumented.

Re-measured since against its own isolation arm (today's tree with exactly this
row deleted, every seam and vein left standing): it moves ocaml and **no other
grammar by a single column of thirty-one**, and ocaml is reachable by no other
row seated today, so the +721 is attributable to this seating alone.

**Withdrawn verdict, kept arithmetic (2026-08-06).** *"The only seating today
whose grammar got worse"* does not survive a sighted reading, and this is the one
row on the board whose **sign flips**. `damage 1,461 → 2,182` and `standing
91.34% → 87.07%` re-derive exactly and are left standing above. But the same
isolation arm, re-taken with a tree-sitter oracle minted inside it, reads
`square 12,165 → 11,717`: **un-seating this row lowers agreement with tree-sitter
by 448 bytes.** The seating is a 448-byte gain that `damage` prices as a 721-byte
loss.

The mechanism is the one the paragraph above already argues and is the reason it
will keep happening to somebody: **a correctly-recognised comment is an `orphan`
and a misread one is `built`**, so a column counting bytes-under-constructs
actively rewards misreading an extra. Every `damage`-only reading of a comment,
docstring or declared extra is biased in that single known direction. This row is
the proven case; there are 113 pages on this tree quoting a column of ours and
never one of the oracle's.

So the day had **no** published regression, and the fragment that documented one
was documenting the instrument. `research/joinery/consort/RESULT-8-sighted.md`
(arm r5), `research/joinery/consort/RESULT-9-reach.md` for the reach.

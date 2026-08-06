`research/joinery/owners/closure.py` was reported to filter external
declarations on `type in ("SYMBOL", "STRING")` and so drop the corpus's two
`PATTERN` externals. It does not, and there is no such filter anywhere in the
tree. `declared()` special-cases `SYMBOL` and sends **everything else** through
`names()`, which renders a `PATTERN` fine, and the docstring two paragraphs down
had already argued by name against writing the narrow version.

What was stale was the prose. The docstring said the narrow read "dropped 21 of
them across 8 grammars". Measured:

| unit | count |
|---|---:|
| non-named declarations | **23 across 9 grammars** |
| the spellings they carry | **31** |
| by shape | 461 `SYMBOL`, 21 `STRING`, 2 `PATTERN` |

`21 across 8` is neither. It is the count **under the filter the code refuses** -
23 declarations minus the 2 patterns, with haskell dropping out of the grammar
count entirely because its only non-named external is the pattern. A
counterfactual written down beside the argument against it, then read later as a
description of the live population. Both sites now carry the measured numbers,
and `owners.py --externals` prints declarations and spellings as separate
columns with a line saying they are different units, because that conflation is
what produced the sentence. It also prints the by-shape census, so a third shape
appearing upstream is visible without anyone re-deriving it.

**Re-pricing: 0 bytes of 181,588.** The brief expected something small and cited
a 524-byte precedent; this is smaller. Measured over all 170 walls through
`spellings()`, which is what `verdict()` actually tests, no wall's verdict moves
under either reading. Neither `\n` is the terminal of any wall and no walled
terminal's kin set reaches one, so **"both of which are walled" is false** -
both are in grammars that *have* walls, which is much weaker and is what the
docstring says now. Bash has two walls, `] in state 35` (scanner, 495 B) and `[
in state 1163` (stranded, 8 B); haskell's 56 are withheld anyway at a 94%
control, below the 95% floor.

Totality is worth zero today and is kept anyway, on the argument that a
declaration is a declaration whichever shape it is written in - not on the
argument that it paid. Bash's `]` is what that same reasoning was worth the one
time it did: 495 bytes published as a grammar gap for an afternoon. The honest
price is recorded beside the argument so nobody re-derives it and nobody quotes
it as a win.

The reason this looked open is the same reason the previous lane believed
`outliner state --holding` had never existed: `research/joinery/owners/` is
entirely untracked, so a stale read of an uncommitted file briefed two separate
tasks that were already done.

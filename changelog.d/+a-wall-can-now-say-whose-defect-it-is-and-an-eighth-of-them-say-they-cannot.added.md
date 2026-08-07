A wall is a place the parse stopped, and until now nothing in this tree could say
whose defect it was without a person reading the grammar. The damage board said
verilog cost 63,937 bytes; it could not say whether a lane should spend a week in
`src/press/` or whether the construct has no derivation in the `grammar.json` we
vendored, in which case the week buys nothing.

`research/joinery/owners/` answers it mechanically for the whole corpus. For each
wall it reads the LR state the parse stopped in (`joints state`), computes that
state's LR(1) viability set from the grammar's own nullable/FIRST/FOLLOW, and
asks whether the offending terminal is in it. In is a **conflict** - the grammar
admits it here and we refuse it anyway, ours. Out is a grammar **gap** - no LR
parser over this file accepts it, tree-sitter included, since it reads the same
`grammar.json`.

**170 distinct walls over 17 walled grammars: 42 gap, 13 conflict, 30 stranded,
9 scanner, 76 withheld.** Priced off the peel over 181,588 B: 134,358 B gap,
17,797 B conflict, 22,179 B stranded, 7,254 B scanner. So **9.8% of the priced
bytes are provably ours and 74.0% provably upstream** - and 12.2% cannot be owned
from the wall's state at all, which is 1.2x the half that is ours.

That third verdict is the change worth arguing for, because the two-owner split
this was commissioned as would have been wrong in the expensive direction.
`inquest.zig`'s `Owner.weave` header already said a wall state is frequently
*downstream* of the defect: the parser folded early and the state you are looking
at is the consequence. A closure that ignores that calls every early-fold refusal
an upstream grammar limitation. On the four verilog walls a human had already
labelled by hand, the naive version does exactly that - it calls all four a
grammar gap when three are press conflicts, filing **20,381 bytes** of work this
tree can do as work nobody can. So a state holding a completed item now returns
**stranded**: a fold could have caused this refusal, the state cannot name the
owner, and the honest answer is that this instrument does not know. It never says
upstream, which is the only guarantee that matters here.

Two controls, both able to fail. The automatic one: every terminal a state's
action row admits is by construction a terminal that position takes, so the
closure must derive all of them - it derives **6,142 of 6,396 (96.0%)**, and a
grammar under 95% has every verdict **withheld** rather than caveated (haskell
94%, sql 86%, ruby 71% - 76 walls, unpublished). The falsifiable one, `--vacuity`,
scores each row against a *neighbouring* state: latex falls 100% to 0.3%, zig to
6.6%. **C only falls to 47.9%**, because its states share too much frontier for
the control to discriminate there, so C's five verdicts rest on a thinner bridge
than its 100% suggests - printed, not smoothed.

Where it goes wrong is `settled`, the completed-item test, and it gates the
verdict carrying 74% of the bytes. "A fold could have happened" is static
over-approximation, not a claim any fold did; three of the four hand-checked
walls land on `stranded`, so exactly **one** hand-checked wall exercises the
`gap` branch at all. The row-admitted control tests viability, not settledness -
so the load-bearing half of this instrument has one example behind it.
`RESULT-1-owners.md` scores all six predictions against that, including the one
this instrument falsified by more than a factor of two (a predicted 45 scanner
walls; there are nine) and the one it met only by counting a verdict invented
after the prediction was written.

18 of the 42 gaps are walls on the file rather than on the peel's own resume,
106,798 B, and `--gaps` writes them out for the tree-sitter scoreboard lane. Each
is a place tree-sitter reads the same grammar and almost certainly fails the same
way - a divergence available to take deliberately, not a place we are behind.

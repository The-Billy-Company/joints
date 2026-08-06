`plumb.hurt()` asked whether an *ancestor* was a recovery node, and every
column that consumes it reads its answer as "the oracle cannot name this byte."
Tree-sitter wraps `picorv32.v` in one `ERROR` spanning all 94,657 bytes and then
builds 48,883 nodes and 17,290 leaves underneath it perfectly well - its actual
recovery nodes, excluding that root, cover 12,526. So one node's verdict was
inherited by the whole file, and the board reported the oracle declining on
bytes it had already named. `hurt()` now asks the node that *covers* the byte -
the one `plumb.paint` already computes - and the ancestry answer keeps its own
name, `engulfed()`, so a caller that wants a recovery region can have one and a
caller that wants a verdict can no longer be handed a region by accident.

Nine call sites read it. Eight were asking "can the oracle name this byte" and
all eight were wrong; every one of them spelled the same rule twice - once by
ancestry, once by cover - with the ancestry arm guarded to fire only on
non-leaf bytes, which is why this was survivable and why it was invisible. The
guard kept tree-sitter's 17,290 verilog tokens out of the refusal, so only
interstitial bytes were written off, and interstitial bytes are the ones nobody
looks at. The four instruments that genuinely want the region - `collate`'s
`refusals`/`survivors`, `scars/against.py`, `specimen`'s error count - already
painted extents by hand and are untouched.

**`veiled` was 93.5% wrong and `owed` does not move.** On the `coverlane` arm
(binary `346d880fc`, tree `05e300803`, its own oracle) corpus `veiled` goes
4,615 -> 300 and `unjudged` 4,704 -> 389, while `owed` holds at 126,917,
`damage` at 126,754 and `warp` at 163, all to the byte. `stretch == warp +
slack + veiled` held throughout, because the three exhaust the population
however you mis-split them. The 4,315 freed bytes land in real buckets -
`unframed` +2,016, `square` +908, `racked` +820, `askew` +569, `unwindowed` +2 -
and **1,389 of them are a charge**: verilog's `crooked` rises 10,964 -> 12,353
while its `share` *falls* 40.48% -> 39.34%, because the denominator grew faster.
A report quoting only the percentage would have called this an improvement.

Two of thirty rows carry a bracket wider than the rest of their recovery:
verilog (94,657 vs 12,526) and **sql** (258 vs 515, 121 disputed bytes), which
nobody had named. haskell and scala were the suspects and both are clean -
neither carries a single recovery node on this corpus. sql's 121 are all
leaf-covered, so the old guard was already handling them and its row is
byte-identical; only verilog moves.

`plumb.py decline` is the corpus-shaped guard, and its load-bearing assertion is
not the rule - it is `PARTS`, which fails when **no row can tell the two rules
apart**, because 27 of 30 rows carry no recovery node and on those the check
holds for free. Watched failing: restoring the ancestry paint reds `SOUND` (a
refused byte whose own cover is healthy) and reds `PARTS` (nothing left to
witness with), while `SPOKEN` goes *green on a population of zero* - the vacuity
`PARTS` exists to catch, catching it. `plumb.py verify` carries the same claim
against a four-node synthetic tree in ~5s, including the byte class that is the
whole defect: interior to a construct built *inside* the bracket, where a check
that only looked at leaves would have been green throughout.

The RED tripwire asserting swift's `/* c\n d */` comes back askew was dissolved
by the `multiline_comment` seating and was already failing before this lane
touched anything. It is kept, pointed at the same bytes, now demanding the
correct reading - the regression guard for the fix that dissolved it - and the
negative it used to supply is supplied by a synthetic pair that does not depend
on the parser still being wrong about anything. `plumb.py verify` goes 2-of-4 to
**10-of-10**.

`research/joinery/cover/residue.py` closes the finding lane's open caution with
Verible in ~5s: of the 840 residue bytes where the two trees name the cover
differently, **no token stands on any of the 794 Verible lexed**, and **six
covers cut a Verible token in half over 8 bytes** - `clocking_drive [46430,
46501)` begins one byte inside a `` `ifdef ``, tree-sitter having read the
backtick as a clocking-drive operator. The bound is 271 + 8 = 279, no longer a
floor over this population. The check made this lane's own version of the same
mistake first: Verible captures a macro-call argument whole as one `MacroArg`
rather than lexing it, and reading that blob as tokens charged 38 single spaces
and 27 spurious misplacements - a refusal to answer, counted as an answer, with
the parsers swapped. `MacroArg` is now a third state, reported rather than
folded either way.

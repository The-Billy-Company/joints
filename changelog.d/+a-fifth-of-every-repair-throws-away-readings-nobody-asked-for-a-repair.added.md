A fifth of every repair throws away readings nobody asked for a repair.

Taken on `joints 1885792a7` · tree `4f018b60f` (pin) · oracle `d85e736fa`
(30 of 30 live, 30 attributed).

`research/joinery/supply/RESULT-2-heads.md` measures the population behind the
per-reading error cost item, which had been carried on the strength of an
argument from the tables alone. Nothing in `src/` changed to get it: the
runtime already prints `Scar.heads` under `joints parse --scars`, and already
traces why a supply stands down.

**The premise holds, and harder than written.** Both arms of `mended`
(`gather.zig:1182-1208`) and `supply` (`1378-1382`) clear `x.live` and leave
exactly one reading whose `rank` and `heft` are the struct defaults - so a
repair does not merely fail to distinguish readings, it erases the two numbers
`beats` compares. Between any two repairs every live reading descends from the
single reading the previous repair left standing. That is why the rung is
vacuous; `x.mends` being per-parse is the symptom, not the cause.

**The population is not vacuous.** Over thirty grammars: 3,326 scars, of which
**637 (19.15%) fire with more than one reading standing**, up to 39 - haskell
355 of 919, verilog 266 of 2,015, then markdown, kotlin, scala. **636 of those
637 are deletions; one is a supply.** Supplies appear at 1.2% of multi-head
walls against a 19.15% base rate, because `supply` asks `x.spent` - one perch,
and only ever the *table's own* reading, since both write sites are guarded by
`if (rank == 0)`. `PREDICTION-1-insert.md` clause 3 wrote the rule as unique
"across every live reading"; the implementation narrowed it to one perch for a
sound reason (a dangling perch index, `gather.zig:1283-1285`) and this is the
first time the narrowing has been priced.

So per-reading error cost is not a rung that can be added to `beats`. It is
downstream of per-reading *repair*: at a wall every reading refused the token
and every one is about to take the same repair, so a cost field would separate
nothing. The cheap first rung is widening `supply`'s question to the live set -
the rule as originally written, with a measured population of 637 sites and no
cost field required.

A staleness hypothesis about `x.refused`/`x.spent` was tested and left open:
4 of 473 multi-head scars report a state that admits the symbol they refused,
but `gather.zig:2433`'s fold-failure arm produces that report legitimately and
the test cannot separate the two. The first run of that test said zero, and the
zero was `joints state` exiting 2 on a folio and printing nothing - the
tool's silence read as the table's answer, which is the same trap `Scar.heads`
itself fell into once. Re-run with the exit code asserted and controls both
ways.

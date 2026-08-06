`gather.collapse` merged two readings standing on the same states and kept the
one with the lower `rank`. `first` and `close` used the same key. But `rank` is
how many declared conflicts a reading took the losing side of - a fact about the
parse loop's own bookkeeping, not about the language - so at a cell whose author
declared both sides equally valid, keeping the lower rank was keeping the
press's coin toss.

There was a better number available and this runtime was already carrying it.
`prec.dynamic` is the one rank a grammar writes that the press deliberately
cannot spend: a static rank deletes an action while the table is being built, a
dynamic one is left for exactly the moment when both derivations it orders
actually exist. `leaf.zig`, `impose.zig` and `bind.zig` all round-tripped it
through the folio and nothing downstream ever read it. Three docstrings in this
tree already named the gap, including `close`'s own - *"the least speculative
wins: without dynamic precedence there is nothing better to compare them by."*

`Reading.heft` is that number summed over everything a reading has folded, and
the key at all three comparison sites is now higher `heft`, then lower `rank`.
One `i32` add per fold, on the forking path only. Upstream reaches the same
total by two accumulations that compose to this one add - a subtree's rank is
the sum over its children plus its own production's (`subtree.c:353,407`), a
stack version's is the previous total plus what it pushed (`stack.c:164,171`),
and versions are ordered by it at `parser.c:284`. Rank stays as the last word,
so a grammar that declares no dynamic precedence cannot reach the new
comparison at all and no table without an opinion to spend can move.

**It is worth 44 square bytes** - python +27, go +17, and nothing else on the
board moves by a byte. Reported that way on purpose. The prediction written
before the measurement expected the delta in c and cpp, reasoning from how many
dynamic precedences each grammar declares; cpp declares 29, the most anywhere,
and moved zero. How many an author writes and where one actually decides
something are different questions. The rule is right and the population it
governs is small: these cells only exist where a fork already stood *and*
already reached a merge.

Guarded by an isolation arm rather than by folio identity, since a runtime
change mints no new tables and folio identity would have been vacuous for it.

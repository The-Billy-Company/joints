`press/` was twenty-five files at one address and `kernel/lex/` was thirteen, and
in both cases the layering was already in the import graph - just nowhere a
reader or a tool could see it. `press/` is now four files at its root over
`copy/` (9), `cast/` (4), `quarrel/` (6), and `docket/` (2); `kernel/lex/` is six
at its root over `hand/` (7). Every file moved as-is.

The layers were measured, not chosen, and two of them are shaped by things that
turned up in the measuring:

`quarrel/` is six files because it has to be. `settle` and the five diagnostics
it drives - `attribution`, `bench`, `column`, `forks`, `ladder` - are one mutual
recursion with no cut in it, so any finer split would have been a directory cycle
wearing a layer's name. It is the one area here whose interior is genuinely flat,
and now that is a fact the tree states rather than one you find out by trying.

`outside.zig` stays at the `kernel/lex` root. It is the hub the other seven hands
hang off and the only one that reads the grammar, and moving it down would have
put `press/press.zig` three `../` away, over the two-hop ceiling this package
declares. The ceiling was right and the instinct to move it with its dependents
was wrong.

`docket/` is the interesting one, because it retires the four ratified variances
this package has been carrying - `zoning` now reports zero allowed edges. All
four were one direction out of two integration tests, `carry_test` and
`census_test`, which check the press by running a whole job through the shop and
so read every zone above it. They were never unit tests; they only had a unit
test's address. What kept them there is that zone paths must partition the
module, so a test cannot be zoned by what it is while it sits loose in a
directory beside what it tests. Splitting `press/` removed that: once the area
has interior directories, `docket/` is just one more of them, and the colocation
nothing was willing to pay for turns out to cost nothing at all.

Five new READMEs, one per new directory, each saying what its layer may read.

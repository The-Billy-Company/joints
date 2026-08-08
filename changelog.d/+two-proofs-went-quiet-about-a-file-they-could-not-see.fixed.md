Three areas landed in one wave - `grain`, `vellum`, and a quotient in the press -
and integrating them turned up the same fault twice in two different gates. Each
one was **passing about code it could not see**, and in both cases the thing
hiding the code was that the file was new.

**A zone violation that read as zero violations.** `press/quotient_test.zig`
imports `folio/folio.zig` and `folio/leaf.zig`, which points up the page, and
`zoning verify` said `0 violation(s)` anyway - because it reads git, and the file
was untracked. `--untracked` shows both. That would have gone red the moment the
file was committed and not one second earlier. The remedy is not a variance: the
zone for this already exists. `press/docket/**` sits above `folio` and its README
says why in as many words - the two tests in it "wore a unit test's address" and
"the charter carried four ratified variances to excuse it". A test that presses a
grammar and then reads the folio section back is that shape exactly, so it moved
in beside them, and `zoning verify --untracked` now reports **0 violations over
342 imports** with the charter's `no ratified exceptions` intact. There were five,
then four, then none, and this did not make it one.

**The lifecycle proof was walking a smaller package than it thought.** `idiom.zig`
keeps its roster as a hand-written list of `@import` lines, so all three new areas
were outside it, and `minterm.Alphabet`, `dafsa.Set`, `Sheet`, `Word` and
`Ruling` - five types that own memory - were not being held to the ownership rule
at all. Adding the six files that declare them fired **no violation**, which is
the good outcome and also the point: those five were correct, and nothing in the
tree knew it. The pin moves 63 → 73, and seven of those ten are from files the
roster had no line for, so they were never judged against a stale number - they
were never judged. Before touching the pin I checked the half it exists for: no
`pub fn deinit` was deleted anywhere in the wave, so the whole delta is additions
and no type went missing behind them.

One note worth keeping: both of these were invisible specifically because a file
was new, and one of them is a hand-kept list. The count in `idiom.zig` is a
workaround for a roster nobody derives - it can tell you a type moved and it
structurally cannot tell you an area was never listed. Deriving that roster from
the tree is filed rather than done, because it wants its own change and not a
line in an integration pass.

Go refused `&T{}`. Not in some corner of the language - `x := &T{}`,
`return &T{}`, `var v = &T{}`, `g(&T{})` and `*(&T{})` all died on the `{`, and
go's row read `press? on { in state 188` with 316 bare leaves under it.

The cause is one comparison. `composite_literal` is ranked `prec(-1)`; the fold
standing against it across `{` is ranked by nobody; and `compare` reads an
absent rank as zero, so -1 loses. That much is upstream's ordering and it is
right. What was wrong is what the ladder did next: it *deleted* the read. With
the read gone the cell had one surviving action, `standing` came to 1, and the
recorder was never reached - no conflict, no fork, nothing in the report to say
the language had just lost a construct. A defect that erases its own evidence.

So the rule is now that an unranked fold may **order** an authored reading and
may not **erase** it. The cell keeps the action the ladder gave it; the reading
that lost is recorded as the conflict's `other` and `Forks` offers it, so the
parse takes the fold first and speculates on the read. Those cells get their own
class, `unwritten`, because they are neither a declared ambiguity nor a residue:
the author wrote a rank, and the only thing missing is the zero on the other
side of the comparison. `Tally` counts them apart for the same reason.

Costing nothing is the whole claim, and it is why this is narrower than it could
have been. Nothing is overruled and no row moves: an `unwritten` cell has the
same primary action in both directions, so 28 of the 30 grammars come out
byte-identical. Python gains three forks and parses the same bytes it did.
Go goes to `accepted, 1 root` at 100% covered, nodes 427 -> 437 and bare leaves
316 -> 0 - reading *more* structure, which is the denominator that would have
caught the opposite. Across the corpus, whole grammars 11 -> 12, standing
62.05% -> 62.12%, nodes 94,191 -> 94,198.

Elixir is the second mover and it goes the other way: 44,524 -> 44,530 bytes for
6,963 -> 6,960 nodes and nine more rubble. Six bytes bought with three nodes is
noise that reads slightly less structure than it did, and it is written here
rather than left out of the average, because a policy that lifts bytes while
lowering nodes is exactly the one a byte-only board flatters.

One thing was built, measured, and then deleted. A `merged` cell was originally
also required to fail an arrival test - does the fold chain from here consume
this terminal after *every* path into the state, or only some? - on the theory
that the forkable population needed governing. A third arm that skipped the test
and forked every candidate rendered identical trees in all thirty grammars, at
no measurable cost. A governor for a decision nobody is making is a second
implementation of nothing, so it went, along with the runtime gate the two arms
were spelled with.

The last paragraph is about the instrument rather than the fix. This change
nearly died as a no-op, twice over. `Conflict` grew a field, `ConflictRecord`
had no room for it, `mint` dropped it on the floor, `bind` filled it with its
default, and the board - which presses most rows from folios - reported thirty
grammars byte-identical and nothing moved. That is a lie in the direction of
*your change did nothing*, whose correct response is to abandon a fix that
works; it survived only because go's repro presses from `grammar.json` while
go's corpus row presses from a folio, and the two disagreed out loud. `impose`
now carries a comptime ledger naming every press-side field the writer is
answerable for, so a new one fails the build with its own name and the two
things that may be done about it, and the folio round trip compares conflict
records by reflection over their fields rather than by a list somebody
maintains. The other trap was smaller and worse: `OUTLINER_SEAM=` reads as
**on**, because `getenv` hands back a pointer to `""`, so the baseline arm ran
the treatment and printed nine go repros accepted under a baseline that refuses
six. Both arms agreeing is what that looks like. It is in `CONTRIBUTING.md` now.

One instrument is left standing with a known lean, named here rather than
touched because another lane is in that file. `inquest`'s `awaited` returns the
first blind external whose cell in the wall state is a shift, and a declared
extra shifts in nearly every state, so it wins that scan almost always: every
swift wall prints `[no stand-in for multiline_comment]`, including the ones that
are plainly `_implicit_semi`. The verdict's `owner` word and the state's item are
earned and can be read as given - it is only the *name* of the stand-in that is
a guess dressed as a fact. The cure is to make an extra the last resort in that
scan rather than the first hit, since a symbol admitted everywhere discriminates
nothing.

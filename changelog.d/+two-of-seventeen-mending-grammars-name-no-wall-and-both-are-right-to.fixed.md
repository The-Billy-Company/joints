After `stamp.verdict()` was repaired, fifteen of the seventeen grammars that
mend named a wall and two did not, and that residue was reported as a probable
second bug underneath the first. It is not a bug and the count is not fifteen.

Markdown stops at `stray byte at 20` and OCaml at `stray byte at 1996`. Those
are **lexical** stops - no terminal in the grammar matches there, so the lexer
never produced a token and no LR state was ever consulted. There is no wall to
name, `Outcome.wall` returning `None` is the correct answer, and
`Outcome.stray` was already modelling the distinction: `walls.py` branches on it
at both its cold and warm sites and peels markdown correctly today. The
fifteen-of-seventeen was a digest counting `wall is not None` and reading a
modelled second stop-kind as a missing field - the same flattering-number
pattern this tree keeps finding, running in the direction of alarm rather than
comfort.

What was genuinely missing is that `None` means two different things and nothing
kept them apart. `stamp.py --stops` now drives `wall` **and** `stray` together
over every stop shape and reports how many name a state, how many name a byte,
and how many name neither, so a count that expects every row to name a wall is
told on the spot that it is counting the wrong thing.

The gate is built to bite rather than asserted to. It reddens under a `stray`
that returns `at` unconditionally, under a `wall` that invents a state when none
is named, and under `verdict` reverting to the take-the-last-line rule that
caused the original defect - and the last of its six rows exists because the
first three would pass against the unconditional `stray`, which is the same
over-claim in the other direction.

Writing it also surfaced a live hazard worth naming: `behind()` matches the
source path **verbatim**, so a caller that spells the path differently from the
way it invoked the binary - relative against absolute, a resolved symlink, a
trailing `./` - silently re-arms the fourth reader's defect and gets an
`inquest` line back as a verdict. Every caller in this tree passes the object it
invoked with, so it holds today; nothing makes it hold tomorrow. A `path spelled
differently` row pins the current behaviour so a future reader that quietly
starts guessing a stop out of that case reddens here instead of shipping.

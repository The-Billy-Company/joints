The sixth instance of the shape, and the only one where nothing is wrong with
the arms. A lane offered **all 30 folios byte-identical** as proof its `Troupe`
seating broke no other grammar. Every folio carried its minter's digest,
`before/latex.folio.by` really did record the before binary, both arms had their
own cache and their own oracle seat, the tickets in `order.py` worked exactly as
designed, and nothing wrote to anything. **The check is sound and it is about the
wrong object.** A folio is the *pressed table*; a seat does not change one, so
latex's folio is identical between the arm scoring 108 and the arm scoring 5,246.
Only the `roll` provision moved a folio at all. An earlier lane had already
shipped the same clearance about a scanner fix.

A machine cannot generally know which artifact a change *should* move. It can
know something narrower and sufficient: **an instrument that did not respond to
the treatment cannot clear it.** `still against` now pools each arm's evidence by
kind, and if the two binaries differ while *every* item of a kind is
byte-identical, that kind is reported `vacuous` and the run exits 1 - because
either it is the wrong instrument for this change or the change did nothing, and
under both readings a negative result from it is not evidence of absence. It is
the mirror of the rule that already refused two arms equal by construction,
reached from the other side: that one refuses arms that cannot differ, this one
refuses *evidence* that did not.

Oracles are deliberately not pooled. An oracle is a controlled variable - the
third case refuses precisely because two arms' oracles diverged - so asking one
to move would invert the rule holding it still. Vacuity is a question about
outcomes, and only the artifacts a run produced are that. `--inert` declines the
whole rule, which is the honest claim a refactor makes: *identity is my result,
not my clearance.*

Restored against the other five, it fires unbidden on three of them and finds the
same theatre from the other side - row 1 because a shared folio cache makes both
arms read one artifact, rows 3 and 5 because a scanner refresh and a lex fix
cannot move a pressed table either. Row 6 carries `folio!` and nothing else,
which is exactly why two lanes read it as clearance.

The rule of thumb is now a house rule rather than folklore: **folio identity
clears a press change and nothing else; for lex, quire or runtime work the
control is your own rows removed from today's tree.** That isolation arm beats a
scratch tree pinned at a moment, which freezes out your siblings' edits and puts
you back to scoring their afternoon as your own - the lane that built the first
one saw nine grammars move in its `before`/`after` pair, none of them its own,
and exactly two move against isolation with no third moving a byte. It is also
self-checking: the isolation arm is *defined* as the arm differing from today by
only your rows, and `--mine` is exactly that predicate, so an isolation that took
out a shared seam on the way past fails at the file, by name, before it prints a
number. `tool/README.md` no longer lets a folio cache per arm read as a
collateral check.

`impose`'s comptime ledger now covers `g.Step`, and `folio_test` round-trips a
grammar that really contains a spliced rank.

The ledger exists because a new field on `settle.Conflict` was once silently
dropped during `mint` — `leaf.ConflictRecord` had no slot for it, `bind` filled
it with its default, every check passed, and the board reported "30 grammars
byte-identical, 0 moved" for a change that takes Go whole. It covered
`lalr.Conflict`, `settle.Frayed` and `lalr.Tables`. It did not cover `g.Step`,
which is the record a press-side field is most likely to be added to.

Demonstrated rather than asserted: add a sixth field to `g.Step` and build.
With `accounts(g.Step, ledger.step)` the build stops with the field's name and
the two things that may be done about it. With that one line removed — the
ledger as it stood this morning — the same field compiles clean and reaches
nothing. The roster records that `alias` and `field` are written while `prec`,
`assoc` and `spliced` are not, so their absence from the file is a decision
somebody made instead of one nobody noticed.

The round trip needed the same treatment. It presses `sample`, whose
productions are built by hand, so no step in it was ever substituted into
anything: `spliced` is false everywhere for reasons that have nothing to do with
the writer, and a section of records that all happen to be zero round-trips
perfectly however wrong the writer is. The new test builds verilog's splice in
miniature, folds it, and asserts *before* packing that exactly one step is
spliced and that the surviving rank is the victim's rather than the host's. It
is not vacuous either: corrupt the writer so it never emits an alias and the
test fails with `expected 0, found null`. A `comptime` block beside it refuses
any future field on `g.Step` that is neither round-tripped nor listed as spent
during the press.

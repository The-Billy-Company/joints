Four things the press decides are stored in a folio as an ordinal, which makes
the ordinal the file format: an action's verb, a conflict's kind, its class, and
a frayed cell's harm. Each has a `leaf` twin declared separately on purpose -
one type is a verdict, the other is a promise about a file - so each needed
converting in both directions, and each direction was a hand-written
prong-by-prong `switch`. Eight of them, 34 lines, in `bind` and `impose`.

All eight were already provably redundant. `impose` had a `concurs` that checks
two enums have the same names on the same ordinals, and `bind` had a `mirrors`
that checked the same thing for the action verbs by hand - so the ordinals were
known to agree, and once they agree the switch is a restatement of it. Both
proofs and both conversions now live in `forme.zig`, which already described
itself as the one place the two action spellings meet, and the conversion is one
function that calls the proof on the types it was handed. There is no way to
spell a conversion that is not proved, which is the part that changed: `mirrors`
was invoked from one of the four functions in `bind` that depended on it, and
held only because all four compiled together in one file.

Reading a cell back was the other half. It was a bare `@bitCast` at four sites;
it is `forme.action` now, checked by the same comptime block the write side is.

Verified by adverse test, one sabotage at a time in `leaf.zig`: reordering
`Action.Verb`, inserting a `ConflictClass` mid-list, dropping a `Harm` member,
and swapping the two `ConflictKind`s each fail the build with the name of the
member that moved and where it moved to. And by measurement, against a build of
the previous commit: all 30 corpus grammars mint to byte-identical folios, a
folio the old binary wrote reads identically through both, and a parse through
an old-written folio agrees byte for byte. 29 lines of code net, and the two
verilog rows `abide` flags are the same two it flagged before this - the
adjudication is byte-identical run with either binary.

A wall on an external terminal used to name one owner. `inquest` classified every
one of them as the lexer's - `awaited_external`, "this state admits a terminal
the grammar hands to an external scanner we cannot run" - which was true while
the only two states were *a hand exists* and *nothing does*.

A customary is a third state, and it changes the work order rather than the
verdict. Three populations now, split out of `blind` because they have three
different owners: **blind**, where nothing answers the terminal at all;
**handed**, where a hand cast answers it; **transcribed**, where this grammar's
own book claims it. All three are answered-but-not-seated - no pattern in the
slate covers those bytes - so the wall reads the same to a user and points
somewhere different to whoever fixes it. `Owner.customary` with
`Because.awaited_customary` means *a rule in `customary/<grammar>.json` declined
here*, which is a file you can open; `awaited_hand` means our Zig declined, and
bare `awaited_external` still means nobody has written either.

Absence outranks both, and that ordering is the pinned part. A terminal nothing
answers is a more fundamental gap than a rule that ran and said no, so `blind`
is searched first and `transcribed` last; where a hand and a book both claim a
terminal the book owns the report, because `outside.step` prefers the
transcription and a report naming the loser is a wrong work order. The test
drives all three and the precedence, and fails if the branches are reordered.

`lex` and `parse` both close with the counts, so the ceiling is visible without
reading source: swift reports `blind to 7 externally scanned terminal(s)` and
`24 answered by customary, 2 by hand` - where before the books it was blind to
ten and answered four by hand and none by data.

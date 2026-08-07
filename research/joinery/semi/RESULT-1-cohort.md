# Result 1 — the cohort rule is not the wall, and never was

Measured with the built binary, not by reading the file. `joints grammar`
prints the *declared* external count (`gr.externals`); `joints parse` prints
the *post-provision* blind count (`sc.blind`). The gap between them is how many
externals this lexer already stands in for.

| grammar | external terminals | blind after provision | **seated** |
|---|---|---|---|
| python | 8 | 0 | 8 (all) |
| rust | 11 | 3 | **8** |
| bash | 22 | 16 | **6** |
| ruby | 29 | 18 | **11** |
| haskell | 48 | 34 | **14** |

**Prediction 1 holds.** Four of the five grammars that declare an external ship
a strict subset seated. bash answers 6 of 22 and parses; haskell answers 14 of
48 and went 23.8% → 73.6% this morning doing exactly that.

So the sentence in my brief —

> if a grammar declares N externals, you spell all N or you spell none

— is a misreading of the word *cohort*. `scanner.zig`'s compile loop is
per-terminal (`for (0..gr.terminal_count)`): each external independently gets a
hand, a roll row, or a seat in `blind`. A `Provision.cohort` names *the other
externals the scanner that row was transcribed from also emits* — it is evidence
that this grammar's scanner is the one the row was read off, so `comment` does
not hand python's `#` to ocaml. `Troupe`/`seated` demands the full **cast**, i.e.
the parts one troupe names, for the same reason. Neither quantifies over the
grammar's whole external set.

## The consequence: the fail-closed partial already exists

The brief's second design question was whether a partial cohort can be made to
refuse rather than guess. It already does, and the refusal is stronger than any
I could have designed:

**Blindness is per-terminal.** An external nothing answers is appended to
`blind` and is never offered to the slate at any offset. A construct that needs
it gets no token, the parse stops, and that stop is provable from the byte at
hand in the strongest available sense — *no hand and no slate row made an offer
at all*. There is no branch where we guess.

So `outside.Provision` needs no design change. Nothing has to be relaxed, and I
should not touch it.

## What this reclassifies

The php decline in my brief — 608 bytes left on the floor because php "also
declares `heredoc_start`/`heredoc_end`/`nowdoc_string`, which must remember a
delimiter" — was not the cohort rule refusing. Those are **three other
terminals**, and seating `encapsed_string_chars` would leave all three blind and
every heredoc in php unparseable rather than mis-parsed. The judgement that
stopped it was a lane's, applied one scope too wide. I am not taking php on in
this lane, but the argument that stopped it does not survive this table and
somebody should re-run it.

## Instrument note

`joints grammar` and `joints parse` print two different numbers with almost
the same words. `grammar` says "external scanner tokens cannot be lexed here"
and lists **every declared external**, including the six bash and rust
provisions that demonstrably *are* lexed here. Read alone it says bash is blind
to `file_descriptor`, which is false — the roll has a `file_descriptor` row with
bash's exact trailing-context guard. Only `parse`'s count is post-provision.

Twenty-two rows left the binary. The **Provision roll** - a table in
`outside.zig` giving an external terminal a pattern, and a spelling of trailing
context to refuse on - now carries seventeen rows where it carried thirty-nine,
and swift's nineteen, kotlin's two and elixir's one are rules in those grammars'
own books.

The migration is not a relocation, because a `Provision` and a customary rule
cannot state the same thing. A row is a function of bytes: the only refusal it
can spell is what may or may not *follow* the match, which is why the struct has
`after` and `never` and nothing else. That was enough to be a faithful reading
of swift's `OP_ILLEGAL_TERMINATORS` and no part of the condition beside it -
every one of those twenty branches is reached under `valid_symbols`, and the
roll had no parse table to ask. A rule is asked at the seam, where the
permission set is in scope, so the same nineteen rows now carry `wanted` as
well, which is what the C actually consults.

**The half we could not state was load-bearing.** Seated in the flat slate,
`_eq_eq_custom` competed with `custom_operator` at the same offset and lost, so
`a == b` came out an `infix_expression` with a `custom_operator` inside it. Asked
at the seam it is an `equality_expression`, which is the tree tree-sitter builds
- seven sites in one 25 KB file, and the differential's own oracle says
`equality_expression [2082, 2134)` where we had been saying otherwise. The rows
that fire only where the grammar has no terminal of its own are unchanged: at
offset 3076 the oracle wants `custom_operator` and `wanted` declines there, which
is the same answer by a better argument.

Kotlin's book said these belonged elsewhere - "four keyword look-aheads whose
every branch is gated on `valid_symbols`, so they belong to a caller that has a
permission set and are out of the cohort here". It is that caller now, so
`_import_dot` and `_primary_constructor_keyword` are transcribed whole rather
than as their bytes: the dot is refused when a newline and an `import` follow it,
because there the answer is an automatic semicolon at a position marked *before*
the dot, and the constructor keyword reads `!valid_symbols[STRING_CONTENT]` off
the C directly, which is what lets it sit behind the string phases without
racing them. Automatic-semicolon insertion is still out, and now for a stated
reason rather than by omission.

Gated per grammar, and the gate is tree equality rather than a token census: the
offline falsifier deliberately models `wanted` as "everything", so it reports a
`wanted`-gated rule as a mismatch by construction - swift's 131 "spurious" are
all inside comments, and its four "missed" are `-` glued to an identifier, which
is a plain `"-"` the internal lexer owns and the C refuses under
`NON_WHITESPACE`. So each grammar was compared engine-side, book against book,
on the sources the differential already reads: byte-identical trees, and the
verdict, offset, root count and survey totals identical with the rows deleted.
Swift holds at 666 unexplained and 9 partial, kotlin at 18 and 198, elixir at
12 - all three the numbers they had before any of this moved. Falsified rather
than assumed: breaking the derived `->` probe in a throwaway copy of the book
fails the parse at `unexpected - at 15`, so the rules are the thing answering.

Scala's four string rows stay. They look mechanical and are not - they are the
stateless approximation of a scanner that tracks whether it is inside a
multiline string, and scala's book holds one rule today. That is a string
customary to write, not a table to lift.

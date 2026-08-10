Haskell reads 56.9% standing where it read 50.2%, with 928 roots where it had 1717 and
1426 misread bytes where it had 3549. The book grew the symbolic-operator family:
`_consym`, `_varsym`, and the two section conditions that gate them.

The board had been pointing at it the whole time and I had been reading the wrong half of
the message. `stray byte at 4798` is line 131 of the pandoc fixture, `in first:splitBy
isSep (dropWhile isSep rest)`, and the byte is the cons operator. The book declined the
whole symop family on the grounds that its guards are not zero-width and run a second
lookahead, which is true and was the wrong call: a file that cannot lex `:` cannot build a
list anywhere in it, so every list in 34kB of Haskell was rubble behind one declined rule.

`lex_symop` is a classifier with eleven special cases and `LSymop` as its default, so the
rules state the eleven once as one `no_probe` and let the default be the default. Five of
those cases are conditional on the byte **after** the operator rather than on the
operator: `lex_prefix` returns its special reading only when an `opening_token` follows and
otherwise falls back to `LSymop`, and `lex_splice` the same for a varid or a paren. My
first pass routed `! ~ @ % $` away unconditionally and lost `f $ x`, which is roughly the
most common operator in the language. The extent is the whole maximal run, because
`symop_lookahead` consumes it before `MARK`.

The two section conditions are zero-width and come first: `(1 - 2 +)` cannot be decided on
one lookahead token, so the scanner looks past the run for the `)` and says which reading
this is. When there is whitespace instead, `_cond_no_section_op` fires to retire
`_cond_left_section_op` for the next ask, and the run comes back as a varsym on the re-ask.

**What is left on this row is not the scanner.** The wall is now `unexpected - at 4929 in
state 620`, the third `->` of `splitTextBy :: (Char -> Bool) -> T.Text -> [T.Text]`, and
the scanner's only correct answer there is silence: both dot conditions require a `.` at
the offset and the bytes are ` ->`. State 620 arrives on `name`, holds only
`_modid_prefix -> name . _qual_dot` and `. _tight_dot`, and folds nothing, so a `name`
shifted into it must be followed by a dot. The state that completes `T.Text` exists - 805,
holding `_qualified_type -> _qualifying_module name .` - and the parse had no head in it.
83 of the 86 remaining stray bytes are the `>` left over after each felled `-`. The one
genuine lexer gap left on this fixture is `haddock`, worth two bytes.

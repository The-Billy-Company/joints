`writ` closes a layout on a keyword the parse refuses, so haskell's `where` stops
reading as a variable: 137 misread bytes to 11 on the pandoc fixture, and 674 more
bytes placed under the node tree-sitter puts them under.

A `where` is indented *deeper* than the block it ends - which is how every Haskell
file in the world writes one - so the offside comparison reads `.inside`, the block
never closes, `where` is never admitted as a keyword, and the parser takes the only
reading left to it. No measurement of any column reaches that, because no column
licenses the close. The Report does, as `parse-error(t)`: a layout ends when the
next token would be a parse error, which a scanner handed a permission set can read
directly - the word at the next lexeme is a keyword this grammar spells that the
parse would not take.

The keyword set is **derived, not declared**: a keyword is a literal terminal whose
spelling is a word, which the grammar already says, so this is one arm of algebra
and not four rows of haskell in the binary. It clears `writ`'s own warrant from the
other side - a close happens only on a keyword *absent* from the union of live
readings, so if any reading would take it, none of them wants the block closed and
the hand stands down. Unanimity by absence.

Haskell hands four zero-width terminals to its external scanner that are not
tokens at all but orders: `_cmd_texp_start` and `_cmd_texp_end` around a tuple
expression, `_cmd_brace_open` and `_cmd_brace_close` around a record. They carry
no bytes, so no literal can stand in for them and the supply rule cannot reach
them by construction. They are seated on the `writ` troupe as bracket frames on
the layout stack it already keeps, so a bracket and a layout nest in one order
rather than in two structures that can disagree about which is inside which -
and nesting order is the whole question a bracket asks.

The clause that makes them worth seating is `bracketed`. `(case a of a -> a, do
a; a)` opens two layouts inside one `(`, and no column can close either: the `)`
shares a line with the block it ends, so the offside rule reads `.inside`
forever and both frames strand. A stranded marker is worse than an unseated one,
because a marker on top silences layout for the rest of the file. The Report has
no clause for this; GHC gets it from `parse-error(t)` and tree-sitter-haskell
encodes it as a distinct sort so a delimiter can end a layout, so the test here
is a stack test rather than a column one.

A zero-width node is a hypothesis, and the standing rule is that a supply is a
hypothesis with a one-token warrant. These four are the case where the table
grants it outright - each is the sole shift in every state that admits it, with
zero co-admission - and `unrivalled` re-derives that from the live action row on
every call rather than trusting a census, reading the `named` set so that
auto-admitted extras cannot dilute a warrant they never earned. `_phantom_bar`
is the counter-example that keeps the rule honest: 33 states, sole in none, and
it stays unseated.

Measured against a control that deletes the two-row data field, which makes the
seat inert rather than merely unused - nothing resolves, both loops run empty,
and no marker frame is ever pushed, so the widened `standing` test collapses
back to the one it replaced. Over nineteen grammars carrying a real source,
eighteen rows are identical and haskell alone moves: roots 2683 to 2003, mends
1661 to 873 over 1872 bytes to 906, supplies 128 to 46. The column that is not a
refusal count is the one to read - the tree grows 6,868 nodes to 12,051, so this
is structure being built that was not built before rather than a mend being
suppressed. php, scala and elixir are held in the arm permanently, because a
corpus total is exactly what hid the keyword seat that repaired verilog while
taking php from 67,697 square bytes to 662.

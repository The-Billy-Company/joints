Twenty-four walls worth 27,560 bytes sat outside the owners board marked
*resume artifact* - the peel restarts mid-file, so a wall in state 0 is a
fragment refusing its own first token rather than evidence about a construct.
Nobody had tested it. Two lanes promised the check and neither shipped it.

`owners.py --artifacts` tests it from the grammar alone. State 0 is the start
state, so the terminals a file may legally begin with are `FIRST(start)`,
computed over `grammar.json` without consulting our table at all. A terminal
outside it is an artifact by construction - no parser over this grammar accepts
a file beginning there, tree-sitter included. A terminal inside it is **not**
an artifact: the grammar says a file may begin here and our start state refused,
which is the same shape as every `conflict` on the board and has been excluded
from it.

**35 of 35 excluded walls are artifacts** (31,475 B over all owners; the
`unowned` subset is exactly the 24 walls and 27,560 B in question). The
exclusion was right.

A rule that answered `artifact` unconditionally scores exactly that, so the
column is worthless without the other half: every grammar in the population is
re-asked about a terminal its own start set does contain, and all seven come
back NOT an artifact. It discriminates inside a single grammar - sql `)` reads
artifact while sql `(` reads opener, verilog `$` artifact while `$unit` opener.

`owners.py --terminals` closes the second half from the other direction, and it
is the one that could have gone badly. The board's least trustworthy instrument
is the wall's own name, and a warm whole-file parse never restarts, so a
state-0 wall it reports verbatim would be a real refusal. Over the five
grammars carrying all 27,560 bytes: **0 of 24.** Each warm parse stops
somewhere else entirely - scala `"` in 610, swift `)` in 141, verilog `` ` ``
in 3438, zig `{` in 715, cpp `"` in 907 - and every one of those matches the
damage line `standing.py` already prints for that row, which is two instruments
agreeing that were built from different bytes.

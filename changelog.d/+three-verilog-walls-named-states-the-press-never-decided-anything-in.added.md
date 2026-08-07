`joints state <grammar.json> --holding <item>` names every state whose kernel
spells an item, dot position included, and exits 1 when none does. It is the
inverse of the number a parse prints when it stops, and it exists because that
number turned out to be worth less than the brief that warned about it said.

Three verilog walls were handed to a lane with authored witnesses and standing
controls: `;` in state 701, `(` in 3772, `=` in 2394. **All three states have no
contested cell.** 701 holds one item, `casting_type -> constant_primary .`, and
admits one terminal, `'`. Probing `Bench.decide` across all three prints
nothing: they are not states the settle bench ever visited, so reading one as
"the cell that went wrong" is reading a cell that was never in question. Three
of three, which was the whole sample. The number is not stable either - two
binaries differing in one line of step-precedence splicing renumbered the entire
LR(0) collection, 9,763 states to 9,276, so "the defect is at state N" is scoped
to one build of a tree that has ten agents in it.

`--holding 'variable_lvalue -> _identifier .'` returns 92 of 9,763 states in
about a second, and 1184 among them is where the defect actually is: the state
after an identifier, holding `clockvar -> _identifier .` complete beside
`variable_lvalue -> _identifier . select1`, with no shift on `[` in its row.
`variable_lvalue` is authored `prec.left(37)` and polls at 0, because
`fold.zig::expand` gives a spliced boundary step the host's rank only where the
victim wrote none and `hierarchical_identifier` wrote `prec.left(0)`. Rung 2
therefore sees a tie, rung 3 folds on a `left` that `clockvar` also inherited
from `hierarchical_identifier`, `standing` comes to 1 and the cell is never
recorded. `c[i] = 0;` has nowhere to go, and `c[i] <= 0;` only stands by being
built as a clocking-block drive - `built` counting wrong structure, caught in
the act beside the witness that shares its cause.

What this costs: nothing, and that is also what it fixes. The verb is read-only,
30 of 30 grammars stay tree-identical with it in, and none of the four repairs
built on the diagnosis was worth shipping. Preferring the host's rank at the
splice seats four witnesses and *raises* verilog damage 63,937 -> 67,349, because
8,817 cells stop being contested and this grammar is disambiguated by its 181
declared conflicts rather than by its ranks. Recording the cell the side rung
decided seats the same four with all seventeen controls standing and verilog
down to 62,645, and costs scala 12,733 bytes and elixir 7,358 - scala's
`@SerialVersionUID(0) class Some[+A]` stops being one `class_definition` and
sheds its annotation as a root, which is a fork the press was right to offer and
`gather` took the wrong limb of. All four are measured either side on pinned
binaries in `research/joinery/verilog/RESULT-2-splice.md`, compared as trees.

`built`, `nodes` and `standing` are unions over spans, so none of them can say
which node covers a byte. That is not a gap in the board, it is the shape of a
union - and it means a table change can swap the structure underneath every
headline column while all of them hold still. Verilog's `parameter` stopped
building a `parameter_declaration` at `[89368,89412)` and started lexing as a
`simple_identifier`, over the same bytes, and nothing on the board moved.

`collate.py adjudicated` is the one instrument that reads interior structure -
it re-derives both trees and holds each hand verdict to the two names it was
judged against. It caught that regression. It caught it because somebody
happened to ask, and a check that runs when somebody happens to ask is the
check that is not there on the day it matters.

So it has a trigger now. `tool/abide.py` asks git what a change touches, and any
change under `src/press/` or `src/folio/` - the table, and the bytes it is
written to - has to re-read every hand verdict before it lands. Wired into
`.githooks/pre-push` beside the Markdown gate, since that is where this
repository already scopes a gate by diff.

Not in CI, and that is deliberate rather than a shortcut: `adjudicated` needs
the oracle, and `ci.yml` says in its own header that it installs no tree-sitter
and never will. That is the whole reason `sound.py` exists in the shape it does
- it is the structural gate that can answer *without* an oracle. This one
cannot, so it runs where the oracle actually is.

It fails closed twice over. A drifted verdict fails, naming the grammar, the
span, its width, both readings and which way each side moved. And a press
change the gate could not check fails too, as UNASKED - the `sound.py` lesson
one level up, because a machine with no oracle must not read as a tree that was
checked and found clean.

Asked of the tree that found the defect, it exits 1 on
`verilog [89368,89412) parameter_declaration -> —`.

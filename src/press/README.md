# press - a grammar in, tables out

Everything here runs once, at build time, and nothing here ever sees a byte of
the text you are parsing. A `grammar.json` written for tree-sitter arrives, and
what leaves is an LR automaton with an action table that `folio` can write down
and the kernel can drive. The whole folder is one function with a lot of
argument.

## Four layers, and they are not a taste

The interior is a straight line, and it was derived from the import graph rather
than drawn on it. Each directory reads only the ones below it, `charter.zone`
judges that against the real `@import` edges, and the reason the line has four
segments instead of the two this README used to claim is that a three-way cut
makes a cycle across directories - which is a hard failure, not a style note.

| Layer | Reads | What it is |
|---|---|---|
| [`copy/`](copy/README.md) | **nothing** | Somebody else's grammar, lowered to the IR. The floor. |
| [`cast/`](cast/README.md) | `copy` | The LR(0) automaton, FIRST, the bit-set matrix, the backwards walk. |
| [`quarrel/`](quarrel/README.md) | `copy` `cast` | Deciding a cell that could both read on and fold up. Six mutually recursive files that cannot be cut. |
| this directory | all three | The door, the table it builds, and the verdict on that table. |
| [`docket/`](docket/README.md) | everything, downstream included | The two integration tests, which check the press by running the whole job. |

`copy/` and `cast/` meet only at `grammar.zig`, which is deliberately smaller than
a tree-sitter grammar: EBNF is already gone by the time the automaton sees
anything, so nothing above `copy/` ever learns what a `repeat` is.

## One door out, and it is bolted

`press.zig` publishes the IR that crosses this boundary, and the list is short
because it was measured rather than chosen: a sweep for what files outside `press/`
actually name found twenty-nine symbols where a hundred and seventy-five were
reachable. Three doors were added afterwards for the callers that had a legitimate
need and no way in - `fold`, `lr0`, `lalr`, all three for tests that isolate one
stage of the build - which is what made the surface *complete*, and a complete
surface is the precondition for the next line.

`charter.zone` now **seals** this directory through `press.zig`. Before that seal,
four call sites entered around the side; they come through the door now, and the
seal is what stops the fifth. So the files below can be moved and renamed without
a search across the repository first, and that is enforced rather than hoped for.
Reach for `press.Grammar`, not `copy/grammar.zig`.

## This directory

Three files and a test. They are the top of the line: everything here reads all
three layers below and nothing reads it except the rest of the repository, through
the first of them.

| File | Role |
|---|---|
| `press.zig` | The door. It publishes the IR anything outside this directory may use, and it is the entry point tables are built through - including the loop that exists because LALR is not quite enough. |
| `lalr.zig` | LALR(1) lookaheads by DeRemer-Pennello, and the action table they decide. It sits here rather than in `cast/` because it consults `quarrel/`, and `quarrel/` reads `cast/`. |
| `inquest.zig` | Why a parse stopped where it did, in one sentence per verdict. Reads the wall state's row and items and names the cause; nothing here presses. |
| `wall_test.zig` | Asking the table what it decided at one symbol, across the whole automaton - because the state a parse dies in is rarely the state that killed it. |

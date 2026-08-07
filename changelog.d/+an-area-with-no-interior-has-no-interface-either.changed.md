`press` and `kernel/joint` each have one door now, and the door says what it
publishes. Before this, `kernel/joint` was six files and ninety-six public
symbols with nothing internal at all, and `press` left a hundred and
seventy-five reachable from outside; consumers named whichever submodule looked
right and took whatever was in it. Nothing in either directory could be moved or
renamed without finding out afterwards who had been holding it.

What each door publishes was measured rather than chosen - a sweep for the names
files outside the directory actually use - and the surprise was how little it
was. `press.zig` serves twenty-nine symbols where a hundred and seventy-five
were reachable, `joint.zig` thirteen declarations against ninety-six. The other
several hundred were never anyone's business; they just had no way of saying so.

Two findings fell out of doing it by measurement instead of by eye:

`lalr.Conflict` and `settle.Conflict` are one type, re-exported under the same
name in two places, so the "collision" that looked like it would force a rename
was itself the leak - `folio` reached one door and `quire` the other for the same
struct. And `lr0.build` paired with `lalr.build` by hand appears only in tests,
six times in `kernel/joint/reverse.zig`, which is the thing `press.tables` exists
to stop anyone doing: it owns the unfolding an LALR merge artifact needs. Neither
`build` is published, so those sites are now the only ones left and they are
findable.

Published flat where a name means one thing, since the alias it replaces at each
call site was `g`. `press.Grammar` says where the type is from; `g.Grammar` said
nothing. Names that only mean something qualified stay behind the module that
qualifies them - `Pool` is four different pools, and `retrace.Step` is a path
step where `Grammar.Step` is a production step.

Seventy-six submodule import lines are gone from thirty-two files, the real
import graph is down from 285 edges to 241, and `root.zig` lost fifty lines: it
named thirteen `press` submodules and six `joint` files and now names two doors.
`kernel/walk` collapsed too, being one file all along.

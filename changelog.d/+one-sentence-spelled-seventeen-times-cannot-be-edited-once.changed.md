The CLI face is one verb per file behind a dispatcher that knows nothing about
any of them. `main.zig` went from 442 lines of code to 148: the two verbs that
were living inside the dispatcher moved out to `grammar.zig` and `lex.zig`, the
seven-arm `std.mem.eql` chain and its seven hand-written arity guards became a
`verbs` table and one loop, and the usage synopsis is now built from that table
at comptime, so the list a reader is shown and the set a run dispatches through
cannot describe different verbs.

Every verb's `run` is `(gpa, io, w, args) !u8` now, where `args` is everything
after the verb. Three of them used to take `(…, grammar_path, rest)` and have
the dispatcher do the splitting; `state`'s four sub-forms - `--census`,
`--holding`, `--chain`, and the bare state number - were parsed in `main.zig`
too, which meant adding a fifth question to `state` meant editing the file that
dispatches to it. They live in `state.zig` now, where they are that verb's
grammar and nobody else's.

`intake.zig` grew from one step to four: `slurp` for the bytes, then `grammar`,
`tables`, and `scanner`. Its own doc comment already argued the case for the
first one - five verbs said "cannot read" five different ways - and the other
three had been pasted seven, six, and four times respectively. Seventeen copies
of three sentences, each free to drift the moment one is edited.

Two things worth writing down about doing it:

The four copies of the scanner block **disagreed** - `lex` and `survey` exited
`1` where `parse` and `amend` exited `2` on a grammar with no lexable terminal -
and the first read of that was a copy-paste bug, since `README.md` names `1` for
exactly this condition. It is not a bug. `lex` and `survey` were asked what a
grammar tokenizes to and "nothing" is that question's answer; `parse` and
`amend` were asked for a tree, and the same grammar is one they could not
attempt rather than one they built and refused. `tool/sound.py` tells a yaml
SKIP from a wiring failure by this exact code. So `intake.scanner` hands back
*which* failure happened and each verb says what it is worth, rather than one
policy being imposed on four call sites - which is what the first draft did, and
it would have silently reclassified yaml in the harness.

And this did not save the seven hundred lines the plan estimated. The face is
2705 lines of code where it was 2677 - flat, slightly up. A table row is a line
too, and two new files carry two new import blocks. What the pass bought is that
each sentence is spelled once, the verb set is enumerated once, and each verb's
argument grammar sits with the verb; the line count was never the thing, and the
estimate that said it was should not have been believed.

Nothing about the binary's behaviour moved. Verified by building the previous
commit in a scratch worktree and diffing 290 invocations against it - every verb,
every failure mode, all four `state` sub-forms, `grammar`/`state` over all 31
corpus grammars and `lex`/`parse`/`survey`/`amend` over the 19 corpus sources -
byte-identical on stdout, stderr, and exit code, but for the wall-clock
microsecond counters.

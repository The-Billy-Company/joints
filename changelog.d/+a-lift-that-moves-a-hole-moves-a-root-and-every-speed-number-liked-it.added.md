Nothing in this tree asked whether an amended tree is the tree a cold parse of
the same bytes gives. `rack --square` is the honest guard against a policy that
buys speed with wrong structure and it is **blind to every incremental change**,
because it measures the cold open and a cold open has no graft - `graft.stoop` is
never called on the path it is guarding. `research/keystroke/abide.py` is the
guard for the other path: 24 keystrokes per grammar, and after every one of them
the amend's tree against a cold parse of the edited file, element for element.
Reuse is an optimization, so those two are the same tree or reuse is broken.

It earned itself immediately. `graft.stoop` opens with `if (q.roots.len != 1)
return gr.chain.items;`, and a mend leaves a forest, so on the 17 corpus
grammars that mend it nominates no lift at any offset - **11,606 probes across
seven of them get past the fork and alignment gates on one keystroke each and are
handed an empty chain.** It reads exactly like an unfinished descent: roots are in
source order and do not overlap, `Quire.survey` holds them to it on every parse,
so picking the root that covers the offset is the same binary search every step
below it already used. I wrote the twelve lines, and they are spectacular. 22 of
29 grammars faster. zig's keystroke 13,783us to 583us. html 3,205 to 304. ocaml
31,165 to 2,369. elixir 21,721 to 2,030. The median gain over the mended set 1x
to 3x, and not one of the clean twelve left at 1x.

Then `abide` went from 27 of 29 grammars to 23. html holds on 13 of 24
keystrokes instead of 24; swift and verilog break on the **first** one. The
disagreement is the root count - verilog 2,974 amended against 2,971 cold, swift
215 against 220 - and that is the whole story: a lift carried out from under one
root and spliced into a parse whose mends fall elsewhere moves a hole's boundary,
and a hole's boundary is where the roots are. The two conditions the header gives
for a safe lift are conditions on the node. Neither one constrains the mend
structure the node is being replanted into, because on a clean parse there isn't
any. So the gate is not a TODO, it is the only thing between those two conditions
and a file with holes in it, and the header now says so with the numbers
attached.

The change is reverted. `stoop` keeps the `holder` helper, which is
behaviour-identical with the gate restored and makes the descent one search
instead of two spellings of the same one. What ships is the guard and the reason.

`--prove` is the demonstration that it can refuse. It corrupts the amended tree
in memory - one character, after a parse that was correct, before the comparison
- and the run has to fail; five grammars, five refusals, and the same five clean
without it. A guard nobody has watched say no is a guard.

The lane also came in to explain why php gets a 65x keystroke gain when the other
28 grammars get 1x - the scoreboard read that as "the machinery works and the
rest is a re-mint policy". It doesn't. **php's first collate keystroke lands at
byte 3, and byte 3 is inside `<?php`.** The tag stops being a tag and the
remaining 23 keystrokes are timed against a file that reads as 73 tokens instead
of 2,744, returning a tree that begins `(_php_tag)` and stops. Take that one edit
out and php is 1.8x, which is what every other mended grammar gets. There was no
working exception to generalize from. `collate.keystrokes` is not wrong about
anything it claims - `p` inside `php` is an identifier interior by every test it
applies, and it has no way to know one language spells its file-scope opener as a
word - but a single destroyed keystroke propagating through 23 measurements is
the thirtieth instrument on the list, and it was the premise of the work order.

Two defects `abide` reports on the **unmodified** tree, neither this lane's:
**toml diverges at k=1** - one keystroke and a `(comment)` moves out of a
`(pair)`'s array into the table, on a grammar with one root that the board calls
perfect - and **python at k=16**, where the amend keeps 9 roots against a cold
parse's 1. `python3 research/keystroke/abide.py toml python` is both.

The instrument I trust least is the one I wrote. `abide`'s first version applied
the unshifted keystroke offsets to a growing buffer, so from the second edit on
the cold side inserted one byte too early and the two sides were comparing
derivations of different files. It reported **27 of 29 grammars diverging from a
cold parse** - a number large enough to bury this lane's actual result, arriving
with the authority of a fresh guard, and entirely its own. It survived because
the shape was plausible: k=1 mostly passed, divergence appeared early and grew,
and that is what a real incremental bug looks like. What caught it was that toml
and swift failed at k=1 where the change provably cannot act, so the instrument
had to be lying about something. `research/keystroke/RESULT-2-forest.md` scores
the four predictions logged before the change compiled: three falsified, and the
three failures are the finding.

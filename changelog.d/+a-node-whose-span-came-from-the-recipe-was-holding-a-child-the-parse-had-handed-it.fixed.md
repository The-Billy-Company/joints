`Gather.reduce` computed a node's extent from the production's right-hand side
and assembled its children from the parse, and nothing reconciled the two. On
`b = "2"  # c` that minted `pair [8, 15)` holding `comment [17, 20)` - a child
with no byte in common with its parent. Tree-sitter builds the identical
children and spans them `[8, 20)`; only the parent's extent differed.

The span pass has to skip a perch that consumed nothing, and that refusal is
right: a nullable child's perch carries a bare offset sitting ahead of the
whitespace, which is a position and not a span, and letting one set an edge
drags thirty grammars back over their own leading trivia. But Rule 2 reads the
extras between two symbols out of the *next* perch's `lead`, so on toml's
`pair -> _inline_pair _line_ending_or_eof` the zero-width external is skipped by
the span while the comment in its lead rides into the child list. Any grammar
whose last symbol is nullable and can be preceded by an extra has the hole;
toml is the one in the corpus that exercises it.

Now a second pass widens the span over the children the node actually holds -
over minted **nodes**, never over perches, which is the whole difference from
the rule the first pass had to refuse. Two arms of one source tree differing
only in this hunk, on one oracle seat: `square` 313,440 -> 313,469, `crooked`
52,359 -> 52,343, `soft` 8,634 -> 8,621, `built` unmoved at 401,787, toml
`trued` 99% -> 100%, and no other row moves.

`tool/sound.py` is the gate that would have caught it: `Quire.survey` over the
whole roster, oracle-free, ~10s, hard in CI. `src/kernel/quire/survey_test.zig`
is its falsifier - hand-built arenas that make `survey` say no on demand, so the
gate keeps its counterexample after every grammar in the corpus is sound.

The reason nobody had to notice for so long is the finding underneath:
`standing` and `damage` are functions of the root frontier alone. `built` is the
union of top-level construct spans and `tops()` discards every indented row
before it is computed, so on any file one root covers whole, `standing` is 100%
and `damage` is 0 no matter what the tree beneath looks like. A child outside
its parent, a child out of order, a node reached twice, a subtree under the
wrong parent - all free. toml was the witness, never the case.

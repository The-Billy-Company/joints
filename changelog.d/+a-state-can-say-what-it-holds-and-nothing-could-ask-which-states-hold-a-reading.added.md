`outliner state <grammar> <n>` has always answered "what does this state hold?"
There was no way to run that backwards, and the backwards direction is the one
attribution needs: a wall names a state, and the question "who is at fault for
this wall" is usually a question about states the wall's own state never
mentions. Two verbs now close it.

`outliner state <grammar> --holding '<item>'` names every state holding a
reading. The query is an item pattern with three optional halves, so it can be
asked at whatever precision you have. `variable_lvalue -> _identifier .` is
exact; `-> _identifier .` drops the left-hand side and asks which left-hand
sides compete for that body; `-> _identifier` drops the dot and finds every
position the body appears in. It matches structurally, not textually, which is
the whole difficulty - a substring test for `variable_lvalue -> _identifier .`
also matches `variable_lvalue -> _identifier . select1`, a different item with a
different meaning, and reports a count that looks like evidence.

`outliner state <grammar> --chain <n>` answers the other half: how a parse
arrives at a state, and where a fold there goes. Handle origins are **exact, not
a radius** - stepping back `|body|` times while ignoring the edge symbols
returns every state within `|body|` steps, which on a small automaton is usually
the right answer and never the right reason.

**None of that walk is new, and this lane wrote it twice before noticing.**
`src/press/retrace.zig` has done exactly this since 3 August - a CSR of inverted
edges and an unwind that crosses only edges labelled by the body symbol at that
position - and `root.zig` exports it as `press.retrace` with a doc comment
naming the very question this verb asks. A whole second copy got written,
reviewed, formatted and split into its own module first, because the search that
should have found it went looking for the *word* the new code used. The
duplicate is deleted and `whence.zig` calls the incumbent; `--holding` and
`--chain` produce byte-identical output across the swap, checked with a separate
`OUTLINER_WORK` per arm.

What survived the deletion is the one thing the incumbent lacked: its two tests
check hand-picked positions on a five-production toy, which is precisely what a
walk that ignored the edge symbols would also pass, since on a small automaton
"every state within `|rhs|` steps" is frequently the same set as the right
answer. The property is now asserted directly - over every completed item of
every state of a grammar pressed through the real tree-sitter front end, every
uncovered origin must read the body forward and land back where it started -
with an anti-vacuity count, because a walk that reaches nothing passes a
for-all. That test lives in `src/press/retrace.zig` beside the code it
constrains rather than in the caller that happened to need it.

**What it is not.** It is a navigation and falsification instrument, not an
attribution one. Used on this lane's own population it named the states, showed
the competing left-hand sides, and let three hypotheses die in an afternoon -
and the verdict that ended up on the population came from a second peel, not
from either verb. `--chain` discriminated the two swift walls that mattered and
put them in a category the lane had not listed. Anyone reaching for this to
*settle* an owner should read `research/joinery/strand/RESULT-3-instrument.md`
first, where the prediction that it would settle one is scored and only half
passes.

The previous lane asked for exactly this and reported it absent, and `git log
-S` agreed, because a partial and much weaker version of `--holding` was sitting
untracked in the working tree the whole time - it matched by substring and broke
after the first item per state. Two of this lane's four briefed tasks were
briefed off a stale read of an uncommitted file. `research/joinery/owners/` is
still entirely untracked and will do this again.

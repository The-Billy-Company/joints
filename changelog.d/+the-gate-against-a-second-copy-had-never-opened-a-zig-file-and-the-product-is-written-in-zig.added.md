`tool/incumbent.py` - does this exported function already have an owner, under
another name?

A lane needed the backward walk from a state over a production's right-hand side,
built one, and found `press.retrace` - exported since 3 August with a doc comment
naming that precise question - while reading `root.zig` for something unrelated. It
was caught by accident, and there is a gate for exactly this: `tool/sole.py`, whose
own docstring has been saying for weeks that its corpus is `tool/*.py` "and nothing
else, which is a hole rather than a scope". The hole has now been paid for twice.

**Only a similarity check catches this, and this is that check rather than an exact
match dressed as one.** The duplicate shared no text with the incumbent - its own
struct, its own locals, a nested dedup loop instead of `indexOfScalar`. Two people
implementing one reverse BFS on separate days do not produce the same tokens, so
nothing decidable over token equality separates them from two genuinely different
functions.

Two channels, and they are not equally strong. **Shape** is parameter types and
return type with names, `comptime` and the declaring container erased - sound and
threshold-free, and usually innocent, because a dozen `deinit(*Self) void` share a
shape and all of them should exist. **Skeleton** is the body's tokens with every
identifier flattened to `id`, compared as 5-grams. That is the similarity channel,
with everything a similarity channel implies, and it is a ranking rather than a
verdict: nothing here fails a build.

**The ranking is shared mass, not Jaccard, and that correction is the whole
result.** The first spelling ranked by Jaccard and put 144 one-line accessors at
the top: `Node.end` returning `self.span[1]` matches `Split.total` at **1.000**
because a six-token body has one 5-gram and they share it. The function this gate
was built to find came **145th**. A rate over a tiny denominator is free - the same
correction `Priced` already carries, where `hits` is recurrence and `cost` is bytes
and a count is not a price. Ranked by how many k-grams the two bodies actually
share, an independently rewritten `press.retrace.back` comes **8th of 889** real
same-shape pairs, and the seven above it are the two container types and the three
`run` verbs of `surface/face` - a list a reviewer wants, not boilerplate.

`--probe` is the anti-vacuity check and prints that rank on every run, because a
gate nobody has watched catch anything is a gate nobody knows works. It plants the
near-miss - written from the question, not from the incumbent's text - and fails if
half the corpus shares as much body with an unrelated function as the plant does.
The failing measurement is kept in `Pair.mass`'s own docstring rather than deleted,
since the gate that would have passed with it is the gate this one replaced.

478 exported functions over 63 files, 888 same-shape pairs across files, tests
excluded because a test is meant to restate what it tests. What it cannot do is
said out loud in its docstring: it reads tokens rather than types, and a duplicate
that recurses instead of iterating, or splits itself in two, has a different
skeleton. It catches the copy that was written the obvious way twice, which is the
one that happened.

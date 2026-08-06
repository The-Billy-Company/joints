A frayed cell where an unranked fold lost to a read was classed `residual`, and
`residual` is the one class `forks.zig` declines to offer a fork for. Both
readings survived the ladder, the cell was recorded, and then its own label threw
the loser away.

`residual` means the grammar left a contest nothing can settle. That is not this
cell. Here the fold loses on a *level nobody wrote* — the default that stands in
for silence — against a read from an arrival that never ranked anything either.
The press's own test says it in the sentence it was already written in: *"one of
the two arrivals is exactly that — silent."* Silence is not a decision, and the
true class for a comparison no author wrote is `unwritten`, which does fork.

598 cells across 10 grammars change class. No cell changes `chosen`: the table
still takes the read, still reports the contest, and still drops no reading —
what changes is that the reading it kept now gets a strand.

Swift's `if let limit = limit {` is the witness. The `{` was shifted as a
trailing closure, so the `if` never got its `_block`:

    func f() -> Int { if let limit = limit { return limit }; return 0 }

    before   press? on integer_literal in state 1103 (0 dropped, 3 misfolded)
    after    accepted, 1 root

On the 28 KB fixture it is worth 20 roots (128 → 108) and 812 bytes of `built`
that were `damage`. It is worth **no square**, and this is the honest half:
swift's crooked went *up* 839 bytes on the same change, because the newly built
bytes are built under the oracle's frames and not with them. Ruby moves the same
way and by the same shape, 88 bytes, +66 crooked. 28 of 30 rows are
bit-identical. Judged on `square` — the only column that is a claim about
agreeing with a second parser — this change buys a construct and not a byte, and
the fixture's remaining wall is a different defect at `let baseStartIdx =` that
this does not touch.

The press test that counted these cells as `residual` now asserts their
addresses instead of a bucket total: each contested cell is at a state that reads
`=`, carries the read as `chosen`, and is offered exactly one fork. A count in a
bucket is satisfiable by an unrelated cell arriving in the bucket; the addresses
are not.

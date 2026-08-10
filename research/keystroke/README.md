# keystroke — why typing one character costs what opening the file costs

The scoreboard next door found joints's largest gap: tree-sitter's re-parse
after an edit is 8x cheaper than re-opening the file, and joints's is **1x**,
on 17 of 29 grammars, with swift at 30,740 µs against tree-sitter's 73. It also
found one grammar at a 65x gain - php - and read that as proof the machinery
works and the rest is a re-mint policy. This folder was sent to generalize php.

**There is nothing to generalize. php's 65x is one keystroke landing inside
`<?php`,** and the machinery does not work anywhere on the mended set. Both
halves of reuse are off there, for two unrelated reasons, and neither is a
re-mint policy.

| | |
|---|---|
| [`RESULT-1-mechanism.md`](RESULT-1-mechanism.md) | the explanation: php debunked, the forest gate, and `holds` re-lexing with a slate the parse never used |
| [`PREDICTION-2-forest.md`](PREDICTION-2-forest.md) → [`RESULT-2-forest.md`](RESULT-2-forest.md) | the policy change, its very large speed win, and the guard that killed it. Four predictions, three falsified |
| [`PREDICTION-3-slate.md`](PREDICTION-3-slate.md) → [`RESULT-3-slate.md`](RESULT-3-slate.md) | the prefix half attempted three ways, its speed measured on a single-variable arm, and one keystroke of haskell that refuses all three. Eight predictions, two falsified |
| [`RESULT-4-book.md`](RESULT-4-book.md) | a third reason `holds` declines, found from the other side of the house: it restored the scanner only for a hand-written one, so a grammar whose scanner is a book replayed with stale memory. yaml 0.97 → 0.49 prefix. No prediction file |
| [`PREDICTION-1-mechanism.md`](PREDICTION-1-mechanism.md) | written first, before any measurement past the scoreboard's own |

## The two halves, and which one owns Swift

Cost is `(1 − p) × cold` where `p` is the edit's position, **except** where the
tiling was dropped, and then it is `cold`.

- **Suffix reuse** is off on every mended file because `graft.stoop` refuses any
  old tree with more than one root, and a mend leaves a forest. 11,606 probes
  across seven grammars return an empty chain on one keystroke each. The refusal
  turns out to be **load-bearing for tree correctness**, not unfinished - see
  Result 2.
- **Prefix reuse** is off on swift, verilog, ocaml and scala because
  `gather.holds` re-lexes each recorded token with the terminals of one state's
  raw table row, where `offer` unions every live reading, narrows with
  `shiftable`, and admits every sprig. Different slate, different maximal munch,
  different token, ring declined. `unheld=4` with `unseamed=0 unfit=0`.
  It was also off on yaml and html for a **second, unrelated** reason - the
  replay restored the scanner only when the grammar had a hand-written one, so a
  grammar whose scanner is a book replayed with another attempt's memory. Fixed;
  see Result 4.

Swift is the second one. It is the row a user feels and the smaller job - **but
not the larger prize, and Result 3 measured that.** Where a ring sits relative to
the edit decides what a resume buys, and swift's nearest ring is 1,030 bytes below
its edit where verilog's is 12,000: the same fix is 3% of swift and 25% of
verilog. `(1 − p)` is the ceiling; the ring spacing is the floor.

## The two instruments

    python3 research/keystroke/probe.py [grammar…]     which half is failing, per grammar
    python3 research/keystroke/abide.py [grammar…]     is the amended tree the cold tree
    python3 research/keystroke/abide.py --prove        the guard refusing on purpose

Both take `JOINTS_BIN` (use `tool/pin.py` - in this tree a path is not a
version) and `JOINTS_WORK` for the folio set.

`probe` reads the two halves out of the report line `joints amend` already
prints and nothing was reading that way: `lifts` is the suffix half, and `read`
against the open's own `read` is the prefix half. Its `open` column is the
**open** verdict and the lift gate reads the **previous edit's** verdict, which
is a conflation that cost a prediction - java, rust and typescript open cleanly
and accept only 5 of 24 warm parses.

`abide` is the guard `rack --square` cannot be for an incremental change, because
`rack` measures the cold open and a cold open has no graft. It compares the
amended tree against a cold parse of the same bytes after **every** keystroke.
On the unmodified tree, 27 of 29 grammars hold; **toml diverges at k=1 and python
at k=16**, and neither has anything to do with this lane.

## What is left, in the order a user would feel it

1. **`offer`'s slate, computed where `holds` runs** - and *only* that. Result 3
   tried the two cheap routes around it and `abide` refused both: descending past
   a decline costs haskell 6 of 24 keystrokes, and so does either rule that
   narrows the slate by a token's shape. The slate is the whole defect and
   nothing about token shapes can settle it, because every such rule guesses
   whether the walk or the bytes are what differs. `shiftable` needs the stack,
   the stack changes under each fold, so the walk must drive `absorb` over the
   stretch and discard it - a third of `remount`. Worth 25% of verilog's
   keystroke and 41% of lua's on the measured arm; **swift is 3%**, because its
   rings sit 1,030 bytes below the edit and not half a file.
2. **Holes in the recorded stream.** scala re-lexes from a ring at 9,538 while
   the first recorded token in the stretch starts at 9,902 - 364 bytes a mend
   stepped over that no token covers. `Graft.seam` exists for this on the prefix
   side and the walk does not consult it token by token.
3. **Mend boundaries in the lift offer.** The only sound way to turn the suffix
   half on for the forests. A candidate must be refused when its span crosses a
   hole in either tiling, and `stoop` can see neither.
4. **`turned_fork`.** 65% of swift's offsets are inside a live GLR fork and can
   never be lifted into. This is a ceiling on 3, not a bug.
5. **A ring whose `at` and `token` describe two different places.** haskell,
   kotlin and elixir replay from a ring and land *behind* the token that ring
   indexes - kotlin by 7 bytes, with `public` sitting in the gap. Neither the
   slate nor the scanner; the ring itself disagrees with itself. Result 4 has the
   three reproductions and no diagnosis.

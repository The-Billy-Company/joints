# RESULT-3 — there is no structural rung at the merge to port

[RESULT-2-reach.md](RESULT-2-reach.md) named the defect: on the two keyless
grammars that hold 95% of the corpus's wide cells, `Reading.heft` is identically
zero, so `Reading.beats` falls through to `rank` — and `rank` at a merge is which
reading was born first. Its closing line named the rung that would pay: *a
structural tie-break in `Reading.beats`, which tree-sitter's
`ts_parser__condense_stack` has and we don't.*

I read `ts_parser__condense_stack` at v0.26.11, built the tie-break in both
directions it admits, and measured each against its own one-change-away control.

**Both directions lose, and the premise is wrong three separate ways.**
`ts_parser__condense_stack` has no structural comparison. Upstream's structural
comparison lives a layer down, it is reached only after two rungs we cannot
reach, and upstream's own name for its outcome is `select_earlier` — it is a
canonicalisation, not a judgement. Nothing here shipped but the paper trail.

---

## What upstream actually compares, and in what order

Read from `.local/stretch/ts/parser.c` and `subtree.c` (v0.26.11, the version the
oracle seat runs), plus `lib/src/stack.c` fetched at tag `v0.26.11`
(sha256 `f70b7e5823e82901801193562908037db4c1a73721e48da0fe54cdb2a6b5856d`,
912 lines) because the local copy has no `stack.c`.

### `ts_parser__condense_stack` — `parser.c:1772-1838`

It prunes halted versions (`1777-1781`), tracks the minimum error cost
(`1785-1788`), and compares each pair of live versions through
`ts_parser__compare_versions` (`1796`). That is the whole of it. The comparison
it calls, `parser.c:246-287`, reads exactly three things:

1. **in-error before not-in-error** — `252-266`
2. **error cost, lower winning** — `268-282`, with the *margin* scaled by
   `node_count` so a small cost gap on a big version is only a *preference*
3. **dynamic precedence, higher winning** — `284-285`

and when all three tie it returns `ErrorComparisonNone` (`286`).

**`ErrorComparisonNone` does not pick.** The loop's response to it is
`ts_stack_merge` (`1806`), and `ts_stack_merge` (`stack.c:708-720`) splices
head2's links onto head1 (`712-714`) and keeps *both* derivations as alternative
links on one node. Its precondition, `ts_stack_can_merge` (`stack.c:722-729`), is
same state and same byte position — the same precondition our `twinned` is.

So upstream's answer to "the keys tie" is **don't choose yet**. That door is
already closed to us by measurement: declining the merge costs 57,627 bytes
([RESULT-5-merge.md](../verilog/RESULT-5-merge.md)).

### The structural comparison — `parser.c:842-885` → `subtree.c:596-623`

`ts_parser__select_tree` decides between two candidate subtrees for one slot:

1. **lower error cost wins** — `846-854`
2. **higher dynamic precedence wins** — `856-868`
3. if either tree carries any error cost at all, stop and take the left — `870`
4. otherwise `ts_subtree_compare` — `872`

and `ts_subtree_compare` (`subtree.c:596-623`) is a lexicographic pre-order walk,
first difference wins:

- **lower symbol id wins** — `605-606`
- **fewer children wins** — `607-608`
- otherwise push the children right-to-left and recurse — `614-619`

Upstream logs the outcomes as `select_earlier` and `select_existing`
(`parser.c:875, 882`).

## What ports, honestly

| upstream rung | here |
|---|---|
| in-error / error cost (`parser.c:846-854`) | **vacuous.** `mended` (`gather.zig:1146`) is called on a refusal of the *whole* parse — both its branches clear `live`, and `x.mends` is a per-parse counter. A mend happens only when every live reading has died, so two readings standing at a merge have taken exactly the same mends. There is no per-reading error cost to compare, and there cannot be one without moving mends inside the fork loop. |
| dynamic precedence (`parser.c:856-868`) | **already here.** `Reading.heft`, and it already leads `beats`. |
| symbol id (`subtree.c:605-606`) | **vacuous.** `twinned` requires the same state chain, and the same state chain pins the same symbols. It can never differ at a merge. |
| child count (`subtree.c:607-608`) | the only rung left — and it is first-difference lexicographic, which is a rule for naming a determinate representative. `rank` already is one. |
| the recursion (`subtree.c:614-619`) | ditto. |

Two aggregate readings of the child-count rung are defensible and they point
opposite ways, which is itself the tell that it carries no judgement:

- **fewer children, read as a total** — fewer interior nodes, so *the smaller
  derivation wins*. Minimal attachment: a fold the grammar did not force is
  structure nobody asked for.
- **fewer children, read at the root** — fewer immediate children means more
  nesting, so *the larger derivation wins*. A root with 5 leaf children has one
  interior node; the binarised reading of the same span has four, and upstream's
  rung prefers the second. It is also the direction this repo's own metric
  argues for, since `built` counts bytes under a construct and `strewn` counts a
  bare leaf where a subtree should have been.

I built both. `Reading.folds` counted the reductions a reading had taken since
`roost` last put the parse back to one reading — one `+= 1` beside the existing
`heft +=` in `absorb` and `close`, copied at the fork exactly as `heft` is, so
two readings compared on it always counted from the same divergence. The only
difference between the two arms is the direction of one comparison.

## The arms

Two isolation pairs. Every pin has its own `OUTLINER_BIN`, its own
`OUTLINER_WORK` and its own oracle seat (`pin.py arm` reports 30 of 30 verdicts
live on all four). Each pair's two `world.json` manifests were diffed
file-by-file and **differ in exactly `src/kernel/quire/gather.zig`** — which is
the only reason these are comparisons at all, because four sibling lanes moved
`outside.zig`, `scanner.zig` and `forks.zig` under me while I built.

| pair | commit | control | arm | the one line |
|---|---|---|---|---|
| A | `459c0975c` | `flat` | `folds` | `a.folds < b.folds` |
| B | `97218d61e` | `ctl4` | `deep4` | `a.folds > b.folds` |

A third arm, `few4`, was built to put both directions on one tree and is
**discarded**: a sibling landed `scanner.zig` during its build, so it differs
from `ctl4` in two files and is not a control. Its board is not quoted here.

The oracle is frozen across a pair in the strongest sense available: pair A's two
`audit.json` seats were diffed field by field and every tree-sitter verdict is
identical; the only fields that move are the ones recording our own forest.

### The instrument can say no

| control | expected | got |
|---|---|---|
| `ctl4` board against itself | nothing moved | `STABLE — every one of the 1020 numbers is identical`, exit 0 |
| `ctl4` board against pair A's control (different tree) | refused | `REFUSE - the two arms were built from trees differing in 5 file(s), 4 of which you have not claimed`, exit 4 |
| `deep4` against `ctl4` | numbers moved | exit 1 |

The refused one is worth quoting, because taken at face value it reads
`zig square 14,690 → 10,322`. Four sibling files, and the board would have
published a 4,368-byte regression that no change of mine caused.

`reach.py` was run under both arms and is armed under both (5,614 wide cells,
5,598 entered, keyless: haskell 92 and verilog 5,241 — unchanged, as it must be,
since a tie-break cannot move a table).

## Per-row deltas, all thirty

Twenty-two of thirty rows are bit-identical on **both** arms. Every row that
moved:

| row | A: `square` | A: `built` | A: `crooked` | B: `square` | B: `built` | B: `crooked` |
|---|---|---|---|---|---|---|
| elixir | . | . | . | **−651** | . | +635 |
| haskell | . | **−937** | −357 | . | . | . |
| kotlin | . | . | . | **+53** | . | −44 |
| markdown | . | . | . | . | **−178** | . |
| python | **−15** | . | +13 | . | . | . |
| sql | . | . | . | **−11** | . | +9 |
| swift | . | . | . | . | . | +17 |
| verilog | **−31** | **−167** | −2,375 | . | **−62** | +664 |
| **total** | **−46** | **−1,104** | −2,719 | **−609** | **−240** | +1,281 |

`damage` is the exact negative of `built` on both arms (+1,104 and +240).

- **cpp does not appear on either arm.** Its board is bit-identical both ways,
  which is the requirement this lane was given: heft leads, and cpp's seven
  heft-decided merges of seventeen decide the same way they always did. Neither
  arm reached the new rung on a single cpp merge.
- **verilog's `crooked −2,375` on arm A is not a win.** 3,896 of those bytes
  moved to `unaudited` — the oracle could no longer frame them — while `built`
  fell 167. The parse stopped building bytes; it did not build them better.
- **markdown on arm B is the clearest single result.** `built 178 → 0`,
  `standing 5.4% → 0`, `graded read → void`. Preferring the larger derivation
  drove a grammar from a small tree to no tree at all.

## What I did not predict and had to go back for

Arm A was built first and I expected it to be the faithful port. It is not: I
had read "fewer children wins" as "smaller tree wins", and at a root the two are
opposite. Arm B is the corrected reading of the same two lines. That correction
came *before* arm B's board and is the reason arm B exists — but it should be
read for what it is, which is that the rung's direction was not obvious from the
source, and a rung whose direction is not obvious from the source is not
carrying a judgement.

Which is why the sign was not then chosen by score. Arm B is the faithful port
and arm B is the worse of the two.

## Did the right reading survive?

`square` is the column that answers this by identity rather than by count: it is
per-byte agreement with a frozen tree-sitter, so a byte that moves from `square`
to `crooked` is one where a *different* reading survived the merge and the oracle
says it was the wrong one. Both arms move bytes that way and neither moves a
useful number the other way:

- arm A takes python from `trued 100%` to `99.13%` — 13 bytes that agreed with
  tree-sitter before the rung and disagree after it. python was one of fifteen
  rows standing at zero damage.
- arm B costs elixir 651 square bytes against kotlin's 53.

So: no. The right reading survived *less* often with a structural rung than
without one, in both directions.

## What is left

The one upstream rung that is a genuine quality judgement is the one above
dynamic precedence — error cost — and it is unavailable here for an
architectural reason, not a missing-line reason: mends are per-parse, so every
live reading carries the same scar count. Giving a `Reading` its own error cost
means moving recovery inside the fork loop. That is a real piece of work in the
`supply` / `fell` / `keep` path, it is much larger than a tie-break, and it is
the only version of this rung that would have information in it.

Until then the honest statement is the one this dossier is for: **when heft says
nothing, there is nothing else at the merge that knows anything.** `rank` is not
a bad tie-break being kept for want of a better one — it is a determinate one,
which is all the merge has the information to be.

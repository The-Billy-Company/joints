# kernel/spine — M3, the tree that makes an edit cheap

The claim: **an edit costs the branches above the leaf it landed in, and nothing
else.** A leaf holds one segment's element, a branch holds the product of its
two children, and because the product is associative, every product that does
not contain the edit is still true. tree-sitter structurally cannot do this: an
LR state has to be recomputed when its predecessor moves, where a function need
not.

| File | Role |
|---|---|
| `spine.zig` | The entry point: re-exports `Tree`, and binds the real joint as `Joint`. The generic-versus-concrete argument lives in its doc comment. |
| `tree.zig` | The file's view: which leaf a byte is in, which leaves a cut disturbed, and the four entry points - `build`, `splice`, `replace`, `edit` - plus the `verify` that re-derives every product and checks the tree against itself. |
| `arbor.zig` | The wood underneath: nodes in an arena, their annotations, and the AVL rotations. Knows nothing about bytes. |
| `toy.zig` | Two monoids to prove it against - `Tally` (total, order-sensitive) and `Sieve` (partial, refuses) - plus the from-scratch `fold` every claim is stated against. |
| `tree_test.zig` | The boring cases: empty, one leaf, either end, a cut that lands on a boundary, a rebalance, a refusal. |
| `stream_test.zig` | The test that matters: random edit streams checked after every edit, a shrinker, and the measurement. |

## Generic over the monoid

`Tree(M)` for any `M` with an `Element`, a `Ctx`, an `identity`, and a partial
`compose`. Monomorphized, so `M.compose` is a direct call and there is no vtable
and no boxing; the generality is free, and it is already used three times over
(M1's lexical maps, a tropical `compose` for recovery, and a spine over *sets*
of effects, which is what rung 1's residue verdict points at). The full argument
is in `spine.zig`.

## The product is partial, so a branch may hold nothing

`joint/effect.zig` refuses a pairing no parse ever produced, which is the
pruning that keeps a joint small. So a branch's annotation is `?Element` and a
refusal absorbs. That lift is sound for exactly the reason `effect.zig`'s
associativity test is written the way it is: it asserts `(a·b)·c` and `a·(b·c)`
are *both* refused or *both* equal, never one of each - which is the law you
need to adjoin a zero to a partial operation and keep it associative.

## The tree does not segment, and will not

`edit` takes a byte range and hands back the *new* byte range that went stale;
the caller mints the segments covering it. Where a segment ends is a fact about
tokens, and the only thing that knows is whatever drives the cursor. A tree that
guessed would be guessing about the grammar.

## What the measurement says

`splice` costs exactly the tree's height and `edit` a small multiple of it,
measured over 4000 edits per row:

| leaves | height | splice | keystroke | resegment |
|---|---|---|---|---|
| 16 | 5 | 4.0 | 4.0 | 11.9 |
| 256 | 9 | 8.0 | 8.0 | 29.2 |
| 4096 | 13 | 12.0 | 12.0 | 45.9 |
| 65536 | 17 | 16.0 | 16.0 | 59.9 |

Four thousand times the leaves for a factor of four in cost. `splice` is
`log₂ n` on the nose because a bulk-built tree is perfectly balanced;
`resegment` - one edit straddling a boundary, so a real split and join - is
about `3.8·log₂ n` and its ratio has stopped climbing by 4096.

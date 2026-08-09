# cursor — what the neighbourhood accessors cost

`zig build bench-cursor`

## The question

A query matcher asks a tree nine questions: who holds this node, what is beside
it, what is beside it that a pattern could name, what is filed under this field,
what covers these bytes, how deep is it, how big is it. Until this wave `Quire`
answered five much smaller ones, and every one of the nine existed only as a
private helper inside `src/kernel/vellum/sheet_test.zig` - written the slow
obviously-correct way in order to check the settled tree's clever way.

So the honest question is not "are the accessors fast". It is **what changed when
those walks became public**, and for most rows the answer is *nothing*: the
accessor is that walk, moved. Those rows read `1.0x` and they are the point. A
matcher can call a walk that six grammars' worth of differential already proved
instead of writing a fifth one from memory.

Two rows are not the same algorithm, and they are where a claim lives.

## The four sections

| section | what it measures |
|---|---|
| `reach` | ns an op, the oracle walk against the accessor, one row per accessor |
| `vellum` | ns an op, the live tree against the settled sheet - the trade a matcher has to make when it picks a representation |
| `lift` | ns a `name`+`isNamed` pair, the old inline spelling against the lifted free functions - the only thing this wave changed on the parse path |
| `flat` | a cold parse and a keystroke, so the path everything above sits on has a tracked number of its own |

## What the board says

Numbers below are one run on an M-series laptop with other agents working on it,
min-of-7 per row. They are the shape, not a contract - the rung prints and does
not assert, because a wall-clock floor on a shared machine cries wolf.

**`descendant_for_byte_range` is the real win, and it needed a threshold to be
one.** The accessor bisects each sibling run; the naive walk scans it. Bisecting
unconditionally was **1.4x slower than the scan on every corpus file**, because
a real file's widest parent is a few dozen children and an unpredictable branch
per halving costs more than walking the whole run. With the scan kept below 48
children and the bisection above it, every row wins:

| file | oracle ns | accessor ns | ratio |
|---|---|---|---|
| json (163 nodes) | 52.90 | 54.28 | 0.97x |
| big-json | 452.93 | 213.99 | 2.12x |
| huge-json | 279.68 | 211.82 | 1.32x |
| wide (20k siblings) | 8039.32 | 67.52 | **119x** |

A second run on the same machine reproduced the shape row for row - 0.96x, 2.12x,
1.38x, 122x - so the threshold is not an artefact of one sample.

**The sibling walks got 1.1-1.5x faster for free**, and on the wide shape 5-8x,
because `std.mem.indexOfScalar` vectorises the search for a node's own seat where
the oracle's `for (among, 0..)` loop does not. That is the whole of the
difference: same algorithm, better std function.

**Where it wins least.** `parent` reads 0.58x on the small file - 0.31 ns against
0.54 ns, which is one load either way and the accessor's `?Ref` wrapping showing
up at a scale where nothing else is happening. `subtree_size` reads 0.63x on the
wide shape, where every subtree is a single node and the accessor's stack setup
is pure overhead against an oracle handed an already-allocated buffer. Both are
real and neither is worth an API change; a caller doing millions of these in a
row is describing `vellum`, not this.

**`subtree_size` needed the frontier off the heap.** Allocating an `ArrayList`
per call made it **1.8x slower than the same walk with a caller-held buffer**.
`std.heap.stackFallback` over 64 refs closed it to parity (0.94-1.02x on the real
files) without putting a scratch buffer in the signature, because most nodes are
leaves and most subtrees are tiny.

**The published vellum trade reproduces.** `Sheet.parent` is 25-33x slower than
a stored back-pointer and `Sheet.depth` is 5-7x faster than a climb, which is
the ~29x / ~9x the vellum rung already reported. Neither direction is a defect:
they are the two halves of the same choice, and a matcher on a static file
should read depth off the sheet and parentage off the quire.

`next_sibling` is the one row where the sheet wins big and the quire cannot
follow: 971 ns against 11 ns on a twenty-thousand-child parent, because finding
your own seat in a flat child list is linear and finding it in a parenthesis word
is arithmetic. A bisection on `start` would close it, and it is deliberately not
here - it would make `nextSibling` depend on an ordering invariant `survey`
treats as *checkable rather than given*, so a tree `survey` would flag as
disordered would get a silently wrong sibling instead of a slow correct one.
`descendantForByteRange` already makes that trade because a byte-range query is
meaningless without it, and its doc comment says so.

**The lift cost nothing.** 1.00x, 0.95x, 0.99x, 1.00x - the free functions
inline exactly as the two lines they replaced did, which is what makes the drift
hazard worth closing rather than a tradeoff to weigh.

## House rules

The ones in `bench/README.md`, plus one this rung adds: **every op is
cross-checked against its oracle on every node of the tree before a single trial
is timed**, and a disagreement exits nonzero. Unlike the timings, that part is an
assertion - a fast wrong answer is not a result.

The slate is the three corpus files the vellum rung uses plus one shape the
corpus does not contain: a twenty-thousand element json array, i.e. one parent
twenty thousand children wide. Without it the board would report that the
bisection bought nothing, which is true of the corpus and false of the structure.

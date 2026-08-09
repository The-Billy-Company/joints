# vellum — the quire settled

A quire is the loose gathering of leaves before it is bound. Vellum is what it
gets bound onto: the same tree, written as a balanced-parenthesis word instead
of as a struct with pointers in it.

Serialize a tree depth-first, writing `(` when you enter a node and `)` when you
leave, and the shape of the tree is a `2n`-bit string. Every question about the
tree then becomes a question about that string's excess walk - the running count
of opens minus closes - and the answers come out of arithmetic rather than out of
following a pointer. The mechanism is Sadakane & Navarro's range min-max tree,
which lives in `irregex.math.succinct.parens`; none of it is re-rolled here.
This directory is the binding: how a live quire becomes one of those words, what
you can ask it afterwards, and what the trade actually costs.

## Two forms, and the difference between them is the honest part

| | What it is | What an edit costs |
|---|---|---|
| `Sheet` | The file at rest. Static, mmap-shaped, every query off immutable storage. | Rebuild, end to end. |
| `Word` | The same word on the spine over `Excess`. | Re-multiply the branches above the touched blocks. |

The brief that produced this area asked a fair question: is vellum the settled
form for a file at rest, or a structure that survives edits? The answer measured
out to *both*, and the second half is the one with a number on it - **a
keystroke costs ~112x less on the word than re-deriving the sheet's index**
(3.25 us against 363 us, on a 188k-node file). `Word` is not a full dynamic BP
and the section below says exactly where it stops short.

## The measure

`spine.Excess` is a triple over a run of parentheses: where the run ends
(`total`), how far below its start it dipped (`min`), and how far above it
climbed (`max`). Composition shifts the second run's dips and climbs by the
first run's endpoint, which is the whole homomorphism:

```text
(a · b).total = a.total + b.total
(a · b).min   = min(a.min, a.total + b.min)
(a · b).max   = max(a.max, a.total + b.max)
```

`min` and `max` range over the **empty** prefix too, which is why both bracket
zero, and it is the one decision here that is easy to get wrong. Leave the empty
prefix out and `identity · w` still equals `w` while `w · identity` does not - a
law that survives every hand-written case and dies on the first random one. So
the laws are property tests over words drawn at random rather than a remark in a
comment (`word_test.zig`): identity on both sides, associativity over triples,
the homomorphism `measure(uv) == measure(u) · measure(v)` against a direct scan,
every element as a product of the two generators, and `balanced()` against
`Parens.fromShape`'s own independent refusal.

This is the second monoid on the spine, and it landed the way `spine.zig`
promised a second one would: a `pub const` beside `Joint`, no change to
`tree.zig`, no change to `arbor.zig`, no parameter added anywhere, no dispatch.
`Leaf.bytes` counts parentheses here rather than source bytes, which is the
claim the generic was always making - the tree never asked what an extent was
made of.

## What it costs and what it buys

From `zig build bench-vellum`, on this machine, against the live quire. Both
arms walk the same shuffled node order.

**Size, bytes a node.** The live tree is a 28-byte `Node` plus its slot in the
flat child list.

| file | nodes | live B/n | shape bits/n | ink B/n | sheet B/n | ratio |
|---|---|---|---|---|---|---|
| json | 397 | 32.0 | 3.06 | 16.0 | 16.4 | 1.95x |
| java | 306 | 33.2 | 3.35 | 16.0 | 16.4 | 2.02x |
| go | 438 | 36.4 | 2.92 | 16.0 | 16.4 | 2.22x |
| python | 520 | 34.2 | 3.38 | 16.0 | 16.4 | 2.08x |
| big-json | 188167 | 32.0 | 2.82 | 16.0 | 16.4 | 1.96x |
| huge-json | 88354 | 32.0 | 2.87 | 16.0 | 16.4 | 1.96x |

Read the two size columns separately, because they answer different questions.
The **shape** is where the claim is: 2.8 bits a node against 32 bytes, about
**91x**. The **ink** - kind, start, length, field - is a fact about the grammar
and the file rather than about the tree, and settling does not make it smaller,
so the whole sheet is **~2x** the live tree and not 91x. A headline quoting only
the shape would be advertising the part that was already free.

Two things keep the shape above a flat two bits, and both are visible above. A
512-bit block carries its rank sample and its min-max entry whether it holds
four hundred parentheses or four, which is the small rows reading over three;
and the min-max tree is a constant fraction of the word rather than a vanishing
one, which is why 188k nodes still reads 2.82 and not 2.05. `2n + o(n)` is
asymptotic in the block size, not in `n`.

**Navigation, nanoseconds an operation.** The 188k-node file, which is the row
worth judging by - the small ones are all fixed cost.

| op | live ns | settled ns | |
|---|---|---|---|
| parent | 1.01 | 28.98 | **29x slower** |
| firstChild | 3.08 | 2.65 | 1.16x faster |
| nextSibling | 15.88 | 23.11 | **1.5x slower** |
| subtreeSize | 24.64 | 20.49 | 1.20x faster |
| depth | 80.68 | 8.98 | 8.98x faster |

This is the trade, in both directions and without a thumb on the scale.
`parent` is a single load in the quire and a range-min search here, so it loses
by a lot and there is no version of this structure where it does not. What is
bought back is that `depth` and `subtreeSize` stop being walks: the quire has to
climb to a root and enumerate a subtree, and the sheet reads them off the excess
walk, so their cost stops depending on how deep or how large the answer is.
`depth` gets nine times better as the file gets bigger precisely because the
quire's arm gets worse.

**Editing, microseconds a keystroke.**

| nodes | rebuild the sheet's index | amend the word | |
|---|---|---|---|
| 397 | 0.79 | 0.29 | 2.7x |
| 88354 | 171.08 | 1.71 | 100x |
| 188167 | 363.75 | 3.25 | **112x** |

## What `Word` is not

Sadakane & Navarro's dynamic variant puts the **bit string itself** into the
leaves of a balanced tree, so an insertion is `O(log n)` end to end.
`Tree(M)`'s leaf is `{ bytes: u32, element: M.Element }` - a count and a measure,
with nowhere to hang a block of bits - so the word here stays flat and an
insertion still `memmove`s the tail. What the spine removes is the *larger* of
the two costs, re-deriving the index; what is left is raw bytes moving, which is
the 112x above and not an asymptotic win.

Closing the gap needs two things `tree.zig` deliberately does not have, and
neither is a small addition:

1. **A leaf payload.** A leaf would have to own a block of bits alongside its
   measure, which changes `Leaf` for every monoid including the joint's.
2. **Measure-guided descent.** BP navigation on a dynamic word is "descend to
   the leftmost position where the running product first satisfies `p`", and
   `tree.zig` navigates by leaf index and by extent - both counts - with no
   predicate entry point.

Both are reported rather than built. Adding either to serve M3 would widen the
surface the joint monoid rides on, and the joint path is shipped, measured code;
a generalization that slows it is not a trade this lane gets to make quietly.
Until then `Word` maintains the measure and answers `excess`, `balanced` and
`product` in `O(log n)`, and hands the word to `Parens` when the file settles.

An unbalanced word is a **legal state** in `Word` and a refused one in `Sheet`,
which is the same posture split across the two forms. An editor passes through
non-forests on the way between forests - delete a `{` and the file is unbalanced
until you type the next one - so `amend` takes any run of the two letters and
`balanced` reports rather than refuses. `seal` is where a non-forest genuinely
has no meaning, and `error.NonCanonical` is what it says there.

## The files

| file | what |
|---|---|
| `vellum.zig` | The door: `Sheet`, `Spot`, `Ink`, `settle`, `Word`. |
| `sheet.zig` | The settled form and `settle`, the depth-first walk that makes one. |
| `word.zig` | The same word on the spine, and the measure `spine.Excess` is scanned against. |
| `sheet_test.zig` | Every op against the live quire, over five grammars and the adverse shapes. |
| `word_test.zig` | The monoid laws as property tests, and the word under edit streams. |

**A node is the bit position of its own `(`**, not its preorder index. That is
the whole of the handle design and it is the difference between a fast sheet and
a slow one: `preorder(spot)` is `rank1`, which is O(1), where recovering a spot
from a preorder index is `select1`, which is a binary search. Every payload
lookup goes through the cheap direction; `spotOf` exists because settling hands
out preorder indices and something has to turn one back, not because a walk
should use it.

## Follow-ups for whoever owns them next

- **A quire accessor, to retire a second spelling.** `Sheet.name`, `isNamed` and
  `field` are `Quire.name`, `isNamed` and `field` with the `Ref` lookup taken
  out. The mapping is a fact about a `Kind` and a `Grammar`, not about which
  tree is holding it. Three free functions in `quire.zig` would collapse both:
  `pub fn nameOf(gr: *const press.Grammar, kind: Kind) []const u8`,
  `pub fn namedKind(gr: *const press.Grammar, kind: Kind) bool`, and
  `pub fn fieldName(gr: *const press.Grammar, field: u32) ?[]const u8`.
- **The weave seam.** A settled sheet is the right thing for the weave to hold
  once a file goes quiet, and `Word` is the right thing for it to hold while the
  file is being typed into - the weave already owns the spine an edit walks. The
  seam wanted is a place for the weave to keep a `vellum.Word` beside its joint
  spine and settle it to a `Sheet` on idle. Not built here: the weave is another
  lane's this wave.

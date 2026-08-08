# rung: vellum

> `zig build bench-vellum`

What does settling a live tree into a balanced-parenthesis word cost, and what
does it buy? Three sections, and each of them can embarrass the design.

## `size` — bytes a node, live against settled

The live quire is a 28-byte `Node` plus a slot in the flat child list, about 32
bytes a node. The sheet is two numbers, kept apart on purpose:

- **shape** — the parenthesis word and its index. Where the claim is: ~2.8 bits
  a node, about **91x** smaller than the pointer tree's shape.
- **ink** — kind, start, length, field. A fact about the grammar and the file
  rather than about the tree, so settling does not shrink it. 16 bytes a node.

Together the sheet is about **2x** smaller, not 91x, and quoting only the shape
would be measuring the part that was already free.

**Why not a flat two bits.** A 512-bit block carries its rank sample and its
range min-max entry whether it holds four hundred parentheses or four, so small
files read over three bits a node; and the min-max tree is a constant fraction
of the word rather than a vanishing one, so 188k nodes still reads 2.82. The
`o(n)` in `2n + o(n)` is asymptotic in the block size, not in `n`.

## `walk` — nanoseconds an operation

Five ops, both arms over the same shuffled visit order. Two rows go the wrong
way and are supposed to: `parent` is a load in the quire and a range-min search
in the sheet. What is bought back is that `depth` and `subtreeSize` stop being
walks, so their cost stops depending on how deep or how large the answer is -
which is why `depth` improves as the file grows.

Judge the rung by the largest file. The few-hundred-node rows are fixed cost in
both arms: a subtree walk over a subtree of three is free, so the sheet has
nothing to beat.

## `edit` — microseconds a keystroke

Re-deriving the static sheet's index end to end, against re-multiplying the
spine above the blocks a cut touched. This is the section that answers whether
vellum is only an at-rest form. It is not: ~112x at 188k nodes.

The amend arm still `memmove`s the flat word, because `Tree(M)`'s leaf cannot
hold a block of bits. `src/kernel/vellum/README.md` says what closing that would
cost.

## The floors

Two, and only the deterministic ones:

- **`ShapeStoppedBeingSuccinct`** — over 3.0 bits a node for the shape, checked
  only at 4096 nodes and up, where the per-block term has amortised.
- **`SheetLargerThanQuire`** — at every size. Settling must never be a
  regression on what it settles.

Timings are printed and not asserted. A wall-clock floor on a laptop ten agents
are working in cries wolf, and a gate that cries wolf teaches you to stop
reading it.

## The slate

Six corpus files across five grammars, plus two large json documents. The corpus
files are a few hundred nodes each, which is not a regime any asymptotic claim
survives being measured in, so `big-json` and `huge-json` (tree-sitter's own
verilog and scala grammars, read as json - 188k and 88k nodes) carry the rows
that matter. `upstream/` is fetched rather than committed, so a row whose
fixtures are not underfoot prints `skipped` and the rung goes on.

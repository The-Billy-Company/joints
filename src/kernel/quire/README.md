# quire — the tree a parse yields

A quire is the loose gathering of leaves before it is bound. That is this
folder's job: the concrete syntax tree while it is still a thing you can change,
as against vellum, the settled succinct encoding. Both are the same tree under
different measures, not two subsystems.

The compatibility surface with the tree-sitter ecosystem is **names**, not shape.
Every `highlights.scm` in the world is keyed on node kind names and field names,
so a tree with the right structure and the wrong spellings is worthless. That is
why a node stores an index and reads its name out of the grammar when asked: the
process holds exactly one spelling of `binary_expression`, and it is the one the
press interned.

| File | What it is |
|---|---|
| `quire.zig` | The tree itself: `Node`, `Ref`, `Quire`, and the s-expression printer. Read-only once handed over. |
| `gather.zig` | `Gather`, a second parse loop that keeps what the reduction was for and builds the tree from it. |
| `gather_test.zig` | Hand-derived expectations for json and for the recipe's hard cases, plus the differential against `walk/drive.zig`. |

## Nodes are indices, not pointers

A tree of a large file is the data structure everything downstream pays for. A
consumer wants to map it, slice it, hand it across the C ABI, or hand it to the
spine to hold; a pointer is none of those. So `Ref` is a `u32` into one flat
`nodes` array, a node's children are a contiguous run inside one flat `kids`
array, and `parent` and `field` are the same kind of index. The whole tree is two
allocations, and the storage stays a decision that can be revisited because
construction lives in `gather.zig` rather than on the type.

`Quire` is read-only on purpose. Edits belong to the spine (M3), which is not
built yet.

## Why there is a second parse loop

`walk/drive.zig` walks the same automaton and says in its own comment that
symbols are not kept, because nothing it serves needs them. A tree needs them.
Extending the oracle would have cost the thing the oracle is for: two independent
implementations of the same walk can be checked against each other, and when they
disagree about a token or a state one of them is wrong. With one implementation a
disagreement is unfindable. `gather_test.zig` runs that check on every case,
including a whole real file.

Lexing here is state-directed for the same reason it is there, and it is not
optional: the terminals the current state has any non-error action for are read
off its action row and handed to the scanner, which restricts the regex walk
rather than filtering its answer. Offer the whole slate instead and json's
`string_content` eats the rest of the line.

## The recipe, in one table

What a reduction does to the tree is decided by three facts the press carries:
a symbol's `Shape`, and a step's `alias` and `field`. Per child, left to right:

| At the site | The tree gets |
|---|---|
| `Step.alias` on a **visible** symbol | the node it already made, renamed in place. An alias replaces a node; it does not wrap one. |
| `Step.alias` on an **invisible** symbol | a new node under the alias name, holding whatever the symbol spliced. |
| `.hidden` or `.invented`, unaliased | nothing of its own; its children splice into the parent. |
| `.named` or `.anonymous`, unaliased | the node it already made, under the symbol's own name. |

Splicing is recursive without any recursion in the code: a hidden child's own
reduction already spliced whatever it was hiding, so its frame holds a finished
list.

`Step.field` is orthogonal to all four rows. It files the node the step produced
or, when the step spliced, **every** child spliced in from it. That last clause is
load-bearing rather than an edge case: `repeat(seq(',', field('init',
$.expression)))` lowers to an invented list symbol, and the children it splices
in are the ones that have to carry `init`.

Alias and field are use-site facts, never properties of a symbol. C and
TypeScript both rename the same symbol at one site and leave it alone at another,
and hanging the rename on the symbol collapses both sites onto whichever was read
last.

## Spans

A node runs from the first byte of its first token to the last byte of its last,
taken from the parse stack's frames rather than from the child nodes. The
difference shows up exactly where it matters: a token that produced no node - an
inline `/regex/` is `.invented` - still consumed bytes, and the rule containing it
covers them. A rule that consumed nothing sits at zero width where the last token
ended, rather than dragging its parent back over the whitespace in front of it.

## A stop is reported, never papered over

Only `Stop.accepted` is a whole tree. `stray`, `unexpected` and `truncated` each
name the byte or token that ended the parse, and the tree is still handed back as
a forest of everything that had completed - a partial tree plus the reason beats
an error with no prefix. Ten of the eleven corpus grammars stop early today for
lexer reasons that are another lane's work; nothing here is tuned to hide that.

A parse that mends carries the count in `Quire.mends`, and a reader that treats
`stop` as an end has to look at it: `stop` names where the trouble began, not
where the forest ends. That distinction is not decoration - a measuring script
that missed it filed twenty of twenty-five recovered files as having stopped at
their first wall while the forest plainly ran past it.

### Crown when the grammar says so, wrap when the caller says so

Tree-sitter hands back one root spanning the file however broken it is. We hand
back the forest. The tempting repair is a synthetic root over the whole text,
and it is worth writing down why there isn't one, because the argument is not
the obvious one.

A crown only pays as *compatibility* if it is called `program` - and a node
named `program` over a file that is not one is a stronger claim than any
`MISSING`: it asserts the whole file derives from the start symbol. Call it
`forest` instead and the consumer has to learn a new name, which is the same
work as handling a forest, so the compatibility win evaporates. What is left is
the real question a consumer asks - *what node is at this offset* - and over a
sorted disjoint forest that is a binary search, the same complexity a single
root would have given.

So: **crown when the grammar says so, wrap when the caller says so, never
confuse the two.** A root here is a derivation that happened. A container over
several of them is a view, and a view belongs to whoever is doing the viewing.

### A hole is the absorbing element, never the identity

The same rule decides what the spine does with the bytes a mend stepped across.
They are laid as a leaf carrying `Effect.hole`, which `compose` refuses on
either side of, so every spine node spanning a break carries the zero and every
node to one side of one carries its real product. The identity would have been
the wrong choice for exactly the reason a crown named `program` is: it composes
away, which claims the two runs were adjacent - the one thing a mend exists to
deny. See `src/kernel/weave/README.md` for what that buys.

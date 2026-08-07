# Prediction 1 — what tree-sitter will say about the gap between two tokens

Written before any board was taken on this lane, after reading three things and
nothing else: `node.c` / `subtree.h` / `tree.c` from tree-sitter v0.26.11,
`src/kernel/quire/README.md`'s **Spans** section, and the seventeen lines of
`tool/rack.py:survey` that compute `stretch` and `airy`.

The sentence under adjudication, from the lane that shipped both columns:

> *a leaf is a token, so whitespace between two tokens is under no leaf and is
> not a defect.*

Its own closing words were **"nothing in the repository adjudicates the
sentence."** The predictions below are about what happens when something outside
the repository is asked.

## The trap I am trying not to walk into

The lane before me scored two of four and named the cause itself: it predicted
from a **column's name** rather than from what the column counts. "Stretch"
sounded like a root reaching over a hole full of code and turned out to be a
root reaching over indentation.

So every prediction here names the line of code it is derived from. Where I have
only a name to go on, the prediction says so and is not made.

`airy` is not the sentence. The sentence says *whitespace **between two
tokens***; the code says

```python
airy = sum(1 for a, b in saw.scope
           for c, on in zip(saw.blob[a:b], stood[a:b]) if not on and c in WHITE)
```

which is *a whitespace **byte** with no leaf **of ours** over it*. Those two
populations are the same only where our token boundaries are the language's.
Everything below follows from that gap.

## P1.1 — tree-sitter's own tree has the same hole, and it is not small

Restricted to joints's own `built` scope, **tree-sitter's own tree will leave
a non-zero count of bytes under no leaf of its own**, of the same order as the
79,628 `stretch` the board carries.

Derived from `node.c:94` in `ts_node_child_iterator_next` — for every child past
the first, the walking position advances by that child's `padding` **before** the
child's node is constructed — and from `ts_node_start_byte` returning that
position verbatim. A gap between two siblings is exactly the second one's
padding, and no node's `[start_byte, end_byte)` contains it.

**Kill condition.** If tree-sitter's own unleafed count inside our windows is
zero, the sentence is false in the strongest possible way: the leaves of a
correct tree tile their root, and every one of the 79,628 bytes is ours to
answer for. `damage` would then be 206,555 and `text` would be a fiction.

## P1.2 — the two questions are different, and only one of them is about leaves

Inter-token whitespace will be **inside the parent's span** and **inside no node
at all** — not merely no *leaf*. Same two lines: `padding` is excluded from
every node, interior or leaf, and a parent's span reaches from its first child's
padding-excluded start to its last child's padding-excluded end.

So the sentence's clause *"a leaf is a token"* is true of tree-sitter and is not
what does the work; what does the work is *padding belongs to no node*. That
distinction matters for `stretch` because `stretch` is defined against leaves,
and a byte under an interior node but no leaf is exactly the population.

## P1.3 — `airy` and the oracle will disagree, in both directions

They are not the same set, and I expect the disagreement to be visible on the
board rather than a rounding term.

- **Whitespace the oracle puts *inside* a leaf.** A token we failed to build and
  it did — verilog's `macro_text`, html's `text`, php's swallowed `text`, any
  string body or comment — contains whitespace that is *not* between two tokens.
  `airy` excuses it; the oracle charges it. I expect **thousands** of bytes here,
  concentrated in the widest-`stretch` rows (html 25,241, php 12,229) rather than
  spread evenly. This is the direction that makes `text` **too small**.
- **Non-whitespace under no oracle leaf.** An unnamed `extras` pattern is skipped
  and never nodified — C's `/\s|\\\r?\n/` puts a line-continuation backslash in
  exactly this class. `airy` charges it; the oracle cannot defend charging it.
  I expect **tens** of bytes, not thousands.

**Kill condition for the column, not for the sentence.** If `airy` and the
oracle-derived split agree to within a few bytes corpus-wide, the byte class was
a fair stand-in for the second parser and `airy` needs no successor — only a
tripwire.

## P1.4 — the corrected corpus figure lands strictly between the two on offer

`129,836` (`damage + stretch − airy`) is a **floor**, not the conservative
reading it is presented as, because P1.3's first direction excuses bytes the
oracle stands a token on. The adjudicated figure will be **strictly greater than
129,836 and far below 206,555**, and nearer the low end, since most of the
stretch really is indentation.

I am **not** predicting where in that interval, and I want that on the record:
the interval is derivable from the code and the position inside it is not. The
lane before me guessed a position and was wrong by the width of the interval.

## P1.5 — verilog's figure will have moved for a reason that is not this lane

`built` on verilog moved 30,720 → 32,193 between two arms while that lane worked,
and `damage`, `honest` and `text` are all functions of `built`. So verilog's
figures on my arm will differ from 62,464 / 67,058 / 62,888 **before any
re-pricing**, and the re-derivation has to be taken on one arm end to end rather
than differenced against the record.

## P1.6 — the falsifier that survives a sibling fixing the product

Two lanes have had falsifiers dissolved this week by siblings *fixing the
product the witness stood on* — the `engulf` tripwire named elixir, elixir's
`do_block` got built, and the assertion failed for a reason unrelated to what it
guarded.

So the tripwire this lane leaves must be asked **of the corpus and of both
poles**: some row's stretch must be the shared representation and some row's must
be a token the oracle has and we do not, whichever rows those are today. A
corpus that has stopped producing either pole must go red rather than green,
because a column with only one pole left is an alias for its own denominator.

I predict the both-poles assertion is **satisfiable today** and that naming any
single row would be dissolvable within the week.

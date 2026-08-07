# joint — the stack-effect monoid (M2)

This is the part of joints that has to be proved rather than cited. Everything
else in the package is engineering over known results; this folder is the bet.

## The claim, in one paragraph

Consuming a run of tokens does exactly one thing to an LR stack: it takes some
symbols off the top and leaves some string of symbols in their place. Write that
as `(k, σ)` — pop `k`, push `σ` — and composing two of them is

```
|σ₁| ≥ k₂   →   (k₁,               σ₁[0 .. |σ₁|−k₂] · σ₂)
|σ₁| <  k₂   →   (k₁ + k₂ − |σ₁|,   σ₂)
```

which is associative with identity `(0, ε)`. Associativity is the whole point.
A monoid can be **scanned**: the product over a range is derivable from the
products of its parts in any grouping, so a file's parse becomes a balanced tree
of effects instead of a left-to-right walk. An edit then rebuilds the O(log n)
products above it and nothing else, *wherever it lands* — which is the thing
tree-sitter's directional reuse structurally cannot do, and the reason a
block-comment open at the top of a file costs it the rest of the file.

The pop turned out to need more than a count and the composition more than a
concatenation — see *What the measurement changed* below — but the shape above
is still what an element is.

## What is here

| File | What it is |
|---|---|
| `stack.zig` | A persistent, hash-consed stack of grammar symbols. Composition truncates one stack and appends another, and the surviving prefix is shared rather than copied; hash-consing makes a stack one `u32` and stack equality one comparison. |
| `roster.zig` | A hash-consed *set* of automaton states — the guard an element carries about what was standing under the part of the stack it popped away. Interned for the same reason a stack is: every question about it is an equality question. |
| `effect.zig` | The monoid itself: `Effect{floor, pop, push}`, a **partial** `compose`, `fold`, and the two generators every parse is built from — `shift` and `reduce`. |
| `reverse.zig` | The goto automaton read backwards, over the *resolved* LALR table rather than the raw LR(0) graph. A segment that pops below its own base needs the state that pop exposed, which belongs to whatever preceded it — but the popped symbols are *known*, and walking those symbols backwards through goto names the candidates. |
| `cursor.zig` | Running a segment: a set of parses over one shared symbol stack, splitting only where the table tells two scenarios to do genuinely different things. Turns a run of tokens into the elements it could be. |

## What the measurement changed

Three things the paper version got wrong, each found by running it:

* **The pop is a string, not a count.** With a count, two segments that owe three
  symbols downward are the same element, and a left neighbour cannot tell which
  one was true. Composition then picks arbitrarily, which is wrong rather than
  imprecise.
* **An element is guarded.** Even with the string, several elements can line up
  against the same left neighbour. So an element also carries the set of states
  it claims was under the pop, and composition *refines* that set against where
  the left neighbour actually landed — returning nothing when the two were never
  adjacent. Composition is partial, and the partiality is what does the
  disambiguating a fork would otherwise have to do.
* **A run is scenarios over one stack, not one parse per state.** Popping a JSON
  value uncovers the four places a value may be written; all four go on to push
  the identical symbols. Branching per state multiplies the run for no
  information. So a limb carries a floor roster and a state *per scenario*, and
  splits only where the table's verdict — shift versus reduce, or which
  production — actually differs. Different shift targets are not a
  disagreement.

## Why equality has to be cheap

Every question this layer answers is an equality question. Is this joint the
same as that one? How many distinct effects does this segment have across entry
states? Did the edit change anything above the splice point? Hash-consing the
symbol stack turns all of them into integer comparisons, which is what keeps the
measurement cheaper than the parse it measures.

## What is not here yet

The scan that folds a file's worth of elements into a spine, and the answer to
the open question below.

## The falsifier, and where it currently stands

Rung one of [the order of proof](../../../research/LANDSCAPE.md): instrument a
real grammar and measure how many distinct effects a segment has across entry
states, over real files. If those tables do not collapse toward rank one, an
element costs `|Q|`, composition loses to tree-sitter's O(1)-per-token walk, and
the honest outcome is to write that down and stop.

Run it with `joints survey <grammar.json> <file…>`. On tree-sitter-json over
its own 12,913-byte `grammar.json` (2,166 tokens, 37 states, no unresolved
conflicts), across six segmentations from 8 tokens to 16 KiB:

* Roughly **80% of (segment, entry state) pairs are refuted outright** — the
  action table proves the state was never the one. That convergence is real and
  it is the mechanism the design counts on.
* **0.1%–6% of pairs fan** past the limb ceiling, rising with segment length.
* The one segmentation with a single segment agrees with the whole-file parse.
  Every finer one has at least one segment where the oracle cannot finish,
  always the same way.

The failure has a single shape, and `JOINTS_CEILING=1` prints it: a segment
entered inside deep nesting reduces below its own base, and each dip has to
guess which of two prefixes it uncovered (`{ string :` or
`{ pair object_repeat2 , string :`). The guesses compound, so the pop strings
enumerate hypothetical left contexts at 2^depth. Every one of them is true of
*some* file; only one is true of this one, and the segment cannot know which.

So rung one has not passed. The open question is whether a pop can be
represented as the *obligation* it really is — reduce by this production, still
owing k symbols — rather than as the string it would have removed, which is the
only part that is unbounded. Until that is answered, this folder is a bet with
a measured counterexample against it, which is a better place to be than a bet
with nothing against it.

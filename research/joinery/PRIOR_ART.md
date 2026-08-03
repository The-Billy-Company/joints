# Joinery - prior art

Who got here first, how far they got, and what each one leaves unclaimed. The
purpose of this document is to shrink [`CLAIM.md`](CLAIM.md) until only the part
nobody has done is left.

---

## 1. Stack effects composed, without incrementality

**Fischer, *On Parsing Context Free Languages in Parallel Environments*
(Cornell TR 75-237, 1975).** The origin. Splits input into segments, parses each
from an unknown stack, and composes the partial results. Every idea in M2 is
already here in outline; there is no data structure for reusing the composition
across successive edits, because in 1975 the workload was a batch compile.

**Mickunas & Schell, *Parallel Compilation in a Multiprocessor Environment*
(ACM 1978).** The same decomposition made practical, with the reconciliation of
segment boundaries worked out.

**Later parallel-LR work** (Vagner & Melichar; various parallel-GLR papers)
refines the segmentation and the reconciliation. It is consistently framed as
throughput on a batch parse, and consistently evaluated that way.

*What they leave:* the monoid is used **once, left to right, in one pass**.
Nobody keeps the product around in a structure that supports splicing one factor
and repairing the product in `O(log n)`. That gap is the whole claim.

---

## 2. Incrementality that is position-independent, without stack effects

**Ghezzi & Mandrioli, *Incremental Parsing*, TOPLAS 1(1), 1979.** States the
goal exactly: thread the parse from both ends so cost does not depend on *where*
the edit is. Achieves it with a specialized bidirectional LR construction rather
than an algebraic object, and the construction does not obviously extend to
error recovery or parallelism.

**Wagner & Graham, *Practical Algorithms for Incremental Software Development
Environments* (Berkeley, 1998).** The thesis tree-sitter and Lezer both
implement. Reuse is a left-to-right walk with node reuse, so a downstream
context shift invalidates the suffix. This is the behaviour we are attacking.

**Sijm, *Incremental Scannerless Generalized LR Parsing* (TU Delft, 2021).** The
best modern measurement: 99% average reuse over real git histories, 9x speedup
on sub-1% edits, 24% overhead on batch parses. Also the important negative
result - scannerless non-determinism *degrades* incrementality, which argues for
keeping a separate lexical monoid (M1) rather than folding lexing into the
parse.

*What they leave:* the reuse unit is a **subtree with a state**, not a
**function**. A state must be recomputed when its predecessor changes; a
function need not. That distinction is the entire O(n) versus O(log n) argument
for the block-comment edit.

---

## 3. The nearest neighbour: Lezer's context hash

**Lezer** ([system guide](https://lezer.codemirror.net/docs/guide/)) is the most
sophisticated production answer to reuse validity. An external tokenizer may
declare a **context**, and Lezer hashes it; a subtree is reusable only when the
context hash matches. It also stores small nodes as four `uint16`s in a flat
buffer rather than tree-sitter's individually refcounted heap nodes, and it
makes GLR opt-in per grammar.

*What it leaves:* the context hash is **a hash of what a joint's domain
actually is**. It is a scalar fingerprint used for an equality test, not a
composable element, so it cannot be multiplied, scanned in parallel, or
maintained in a tree. Lezer arrives adjacent to the object and uses it as a
checksum. Similarly, opt-in GLR is the right instinct at the wrong granularity -
per grammar, where the rank of a joint gives it per segment.

Tree-sitter's external-scanner `serialize`/`deserialize` pair, with its
**1024-byte** budget, is the same idea implemented worse: a lossy, size-capped,
hand-written encoding of exactly the state a joint would carry exactly.

---

## 4. Logarithmic reparse, from the PEG side

**Yedidia & Chong, *Fast Incremental PEG Parsing* (SLE 2021, best paper).** GPeg
memoizes in an interval tree with lazy shifts and gets **logarithmic**
reparse, with sub-5 ms edits on inputs from tens to hundreds of megabytes. It
also independently confirms the grammar-as-data thesis: a grammar compiles to
parsing-machine bytecode the runtime interprets.

*What it leaves:* PEG, so ordered choice, no ambiguity, and a different error
story. It is the strongest evidence that the `O(log n)` target and the
interpreted-grammar target are both reachable, arrived at by memoization rather
than by algebra - which means it does not generalize to parallelism or to a
semiring recovery layer.

---

## 5. The monoid machinery itself

**Ladner & Fischer, *Parallel Prefix Computation* (JACM 27(4), 1980)** and
**Hillis & Steele, *Data Parallel Algorithms* (CACM 29(12), 1986)** - any monoid
product is `O(log n)` deep. Standard.

**Mytkowicz, Musuvathi & Schulte, *Data-Parallel Finite-State Machines* (ASPLOS
2014)** - the transition monoid of a DFA, executed as a gather; up to 3x on one
core and 21x on eight, with `_mm_shuffle_epi8` where hardware gather is absent.
This is M1 already proved, on regex and HTML rather than on code lexers.
Critically it also establishes the **convergence** phenomenon we are betting on
one level up: real automata collapse to constant functions fast.

**Finger trees / measured ropes** (Hinze & Paterson, JFP 2006) - monoid-annotated
sequences with `O(log n)` splice, and the standard structure behind every serious
text buffer. Universally applied to *text*, and to our knowledge never to a
*parse*.

*What they leave:* nothing in the monoid literature is about parsing, and
nothing in the parsing literature reaches for the monoid-annotated sequence. The
two halves exist; the join does not.

---

## 6. Semiring parsing

**Goodman, *Semiring Parsing* (Computational Linguistics 25(4), 1999)** -
recognition, Viterbi, inside-outside, and counting as one algorithm
parameterized by semiring. Definitive and long settled.

**Hutchison, *The Squirrel Parser* (arXiv 2601.05012, January 2026)** - recovery
derived from four axioms and twelve constraints with a necessity proof per
component, `O(n·|G|)` preserved under arbitrary errors. The correctness bar for
M4. **Hutchison, *Pika parsing* (arXiv 2005.06444)** - bottom-up right-to-left
DP gets optimal recovery free, at a per-character constant too large for big
grammars, which establishes that optimal recovery is achievable and that the
naive route to it is expensive.

*What they leave:* the semiring layer is claimed here only as *composing with
M2 at no additional structure*. The semiring theory is entirely borrowed.

---

## 7. Data-dependent grammars, i.e. deleting the C scanner

**Afroozeh & Izmaylova, *Iguana* (CC 2016)** - desugars `offside`, `align`,
`ignore`, follow restrictions, and keyword exclusion into data-dependent
grammars, validated on OCaml, Haskell, Java, and C#. **Jim, Mandelbaum & Walker
(POPL 2010)** - the underlying formalism.

*What they leave:* nothing, in theory. This is a straight adoption, and it is
the principled replacement for tree-sitter's external scanners, its 1024-byte
serialization budget, and its Emscripten libc allowlist. The only contribution
on our side is feeding it a SIMD structural index (`grain`) so that indentation
columns and string spans are already computed when the grammar asks.

---

## What survives

After all of the above, the unclaimed intersection is narrow and specific:

> **Maintaining the LR stack-effect monoid product in a monoid-annotated
> balanced tree, so that position-independent incremental reparse, parallel
> parse, and rank-triggered lazy GLR are one implementation - with the tree
> store itself maintained as a fourth measure on the same structure.**

Everything else on this page is either borrowed with attribution or a free
consequence. If a reader finds that intersection in the literature, the right
outcome is a `CLOSED.md` and a thank-you note.

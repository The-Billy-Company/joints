# Joinery - what is ours

**Status: M2 measured, the rest unproved.** The stack-effect monoid below is
built and instrumented, and [`TESTING.md`](TESTING.md) rung 1 records what it
did on real grammars and real files - including the part where the kill
condition as originally written was not met, and why the number turned out to be
the wrong one to have chosen. Everything else here states precisely what
joints claims is new, so that the claim can be attacked before it is built.

---

## The claim in one paragraph

An LR parser's effect on a segment of input is a **stack effect**: pop `k`
symbols, push the string `σ`. Stack effects compose associatively, so a parse
is a product in a monoid rather than a left-to-right walk. If that product is
maintained in a **monoid-annotated balanced tree**, then an edit anywhere in the
file costs `O(log n)` re-multiplications regardless of position, the same
product evaluates in parallel as a prefix scan, and **GLR is paid only where the
element is genuinely multi-valued** rather than everywhere a conflict is
reachable. We call one element a **joint**. The claim is not any one of those
three properties; it is that all three are the same implementation.

---

## The object

Represent the parse stack as a string of grammar symbols in `V*`, recovering LR
states by replaying `goto` from whatever the stack exposes. Then a segment's
effect, per entry state, is

```
J : Q ⇀ (ℕ × V*)
```

and composition of `(k₁, σ₁)` followed by `(k₂, σ₂)` is

```
if |σ₁| ≥ k₂:   (k₁,                 σ₁[0 .. |σ₁|−k₂] · σ₂)
else:           (k₁ + k₂ − |σ₁|,     σ₂)
```

Associative, with identity `(0, ε)`. This is the stack-effect monoid, a
quotient of the free product on push and pop; the same algebra types
concatenative languages.

A **joint** is that map tabulated over entry states, carrying the parsed
subtrees the effect produced. Two joints compose by pullback through `goto`.
The **rank** of a joint is the number of distinct outcomes its table takes.

---

## The three properties, and which are new

**1. Position-independent incrementality.** Maintaining the joint product in a
balanced tree makes an edit cost `O(log n)` joint compositions plus the cost of
re-deriving the one changed leaf. Tree-sitter's reuse is left-to-right: it walks
from the edit forward until lex mode *and* parse state both re-match, so an edit
that shifts downstream context - opening a block comment, opening a string,
changing an indentation level - invalidates the entire suffix. A joint has no
direction and no base point, so downstream joints are unchanged by construction
and only the `O(log n)` products above the edit are recomputed.

*Novel?* The idea that incrementality should not depend on edit position is
Ghezzi & Mandrioli, 1979. The idea of composing stack effects is Fischer, 1975.
**The balanced-tree maintenance of that product for editor-scale incrementality
is what we have not found in the literature.**

**2. Parallel parse as a prefix scan.** The same monoid scanned Ladner-Fischer
gives `O(n/p + log p)`.

*Novel?* No. Parallel LR by segment composition is 50 years old. It is claimed
here only as a free consequence - it is literally the same code path as
property 1, which is the economy being argued for.

**3. Lazy GLR by rank.** A rank-one joint is deterministic and composes as a
pointer join; a joint of rank > 1 is exactly the place where the parse genuinely
forks. ast-grep's instrumentation of tree-sitter found **98.898% of stack nodes
have exactly one predecessor**, each costing 160 bytes. Under this formulation
that 98.898% never allocates a graph node at all, because determinism is a
property of the element rather than a runtime discovery.

*Novel?* Adaptive and lazy GLR variants exist, and Lezer already makes GLR
opt-in per grammar. **Making determinism a measurable property of an algebraic
element, per segment, rather than a per-grammar or per-state decision, is
what we claim.**

---

## The corollary we actually sell

The three properties are the mechanism. What a user sees is:

- **A grammar is data, not a C program.** A monoid presentation plus a
  homomorphism from bytes is a table. Tables go in a file. One binary plus one
  **folio** is every language, against tree-sitter's per-language `.so`, its
  30 MB `parser.c`, and its grammars that need >20 GB of RAM to build.
- **Recovery is a semiring parameter.** Joint entries carry semiring weights, so
  least-cost repair under the tropical semiring is the same product with a
  different `⊕`. Recovery, incrementality, and parallelism stop being three
  subsystems.
- **Reuse validity is decidable from the object.** Lezer's context hash and
  tree-sitter's 1024-byte scanner serialization are both lossy stand-ins for a
  joint's domain. Here it is the actual object and equality is exact.

---

## What is explicitly not claimed

- **Not faster batch parsing.** Tree-sitter's throughput is fine and nobody is
  waiting on it. Sijm measured incremental GLR at a 24% batch overhead as the
  price of being incremental at all. Speed is not the pitch; size, reach,
  recovery quality, and one install are.
- **Not a better grammar corpus.** Three hundred maintained grammars are
  person-decades and cannot be out-engineered. The plan is to import
  `grammar.json`, not to rewrite it.
- **Not new succinct-tree theory.** M3 is Sadakane-Navarro applied, with the
  single observation that a range min-max tree and a joint index are the same
  balanced tree under different measures.
- **Not new semiring theory.** Semiring-parameterized parsing is Goodman, 1999.
  The claim is that it composes with M2 at no extra structure.

---

## The falsifier, stated up front

**If joints do not converge toward rank one on real grammars and real files,
this design is dead.** A joint table is `|Q|`-sized in the worst case; composing
two of them then loses to tree-sitter's O(1)-per-token walk by a wide margin,
and every property above becomes an expensive way to be slower.

Convergence is measurable **before any parser is written**: instrument an
existing LR automaton, run it over a real corpus, and histogram the rank and
domain size of the induced effects. That is [`TESTING.md`](TESTING.md) rung 1,
and if it fails the honest outcome is a `CLOSED.md` in this directory.

It has now been run, and the answer amends this section rather than settling it.
Joints do **not** converge toward rank one; a segment routinely holds several
unrefuted effects because it cannot see the stack under it. What does converge
is the *product*: the running set of pairings the guards have not yet refuted
stays bounded no matter how finely the file is cut, and multiplies back to the
whole-file effect every time. Rank was a proxy for the cost of a join and a poor
one. The falsifier that replaces it is residue growth, and the read on it is in
rung 1's verdict.

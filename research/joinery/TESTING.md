# Joinery - how the claim dies

Every rung states a premise, names the measurement, and names the number that
kills it. They are ordered so the cheapest falsifier runs first. No rung may be
skipped because a later one looks more interesting.

House rule, inherited from irregex's automata dossier: **a claim is not credible
until it has been timed against bytes, and you must price both halves of every
exchange.** An `O(log n)` splice that allocates is not automatically better than
an `O(n)` walk that does not.

---

## Rung 1 - do joints converge? (the falsifier for everything)

**Premise.** A joint table is `|Q|`-sized in the worst case. The design only
pays if real segments induce **low-rank** effects, most of them rank one, the
way lexical DFAs collapse to constant functions.

**Measurement.** No parser required. Take an existing LR(1) automaton for a real
grammar - the tree-sitter `grammar.json` for C, Python, Rust, TypeScript, Go,
Java - and for each, over a corpus of real source files:

- segment the file at fixed byte boundaries (1 KB, 4 KB, 16 KB) and at token
  boundaries;
- for each segment, compute the induced effect from every reachable entry state;
- histogram **rank** (distinct outcomes) and **domain size** (entry states that
  reach a defined outcome).

**Kill condition.** If the median rank is not 1, or if the 99th-percentile rank
exceeds a small constant (say 4), the monoid is dense and composition costs
`|Q|` per join. Tree-sitter's O(1)-per-token walk wins, and this design is dead
on arrival. Write `CLOSED.md` and move on.

**Secondary output.** The rank histogram directly predicts how much GLR work is
real, and should be compared against ast-grep's measured 98.898% single
predecessor. If our number is far below theirs, the segmentation is wrong before
the algebra is.

**Cost.** One instrumented afternoon.

---

## Rung 2 - does the lexical monoid collapse?

**Premise.** M1 elements are `|Q|`-entry tables, cheap only because real lexers
converge to constant functions within a few bytes.

**Measurement.** Same corpus. Build the minterm DFA for each language's lexer,
then histogram, as a function of chunk length, the fraction of chunks whose
transition function is constant.

**Kill condition.** If constancy is not reached within a chunk length small
enough to keep the tree shallow, M1's elements stay `|Q|`-wide and the SIMD
single-register composition story evaporates.

**Prior expectation.** Should hold. ASPLOS 2014 measured it for regex and HTML;
code lexers have more states but similarly aggressive convergence at whitespace
and delimiters. **If it fails for code, that is a genuinely new negative result
and worth writing up.**

---

## Rung 3 - is the splice actually cheaper?

**Premise.** `O(log n)` beats `O(n)`, but only past a crossover, and only if the
constant is honest.

**Measurement.** Against tree-sitter on identical files and identical edits,
four edits that matter:

| Edit | Why it is on the list |
|---|---|
| type one character mid-function | the common case; tree-sitter is already good here and we must not lose |
| open a block comment at line 1 | tree-sitter's worst case: total suffix invalidation |
| paste 500 lines | bulk insert; tests splice cost, not walk cost |
| delete a closing brace | maximum structural disturbance, and it runs into recovery |

Report wall-clock, allocations, and peak resident. Sweep file size from 1 KB to
10 MB to find the crossover, and **report the crossover** rather than only the
win.

**Kill condition.** Losing on edit 1 at any realistic file size is fatal - it is
99% of an editor's keystrokes. Losing on edit 2 means the central argument was
wrong.

---

## Rung 4 - is the quotient worth its build time?

**Premise.** Predicate minterms plus action-bisimulation plus DAFSA beat CSR.

**Measurement.** Forty grammars. Report **bits per production**, not megabytes -
megabytes are a grammar-size confound. Baselines: current tree-sitter
`parser.c`, tree-sitter's CSR branch (C# 29 MB to 8.5 MB), and our
quotient-then-DAFSA. Also report **press time and peak RSS**, because
tree-sitter's real failure is not that vim's table is big, it is that vim's
table needs >20 GB to build.

**Kill condition.** Not materially below CSR on bits per production, or a press
that cannot build the forty grammars inside a CI runner's memory.

---

## Rung 5 - is recovery actually better?

**Premise.** Tropical-semiring least-cost repair produces the node a human
expects, where tree-sitter's greedy `error_cost` produces `ERROR`.

**Measurement.** The acceptance test is Pulsar's case, verbatim: CSS with
`justif` typed inside a rule body must yield an incomplete `property_name`, not
an `attribute_name` inside an `ERROR`. Beyond that, a corpus of mid-keystroke
snapshots - take real files, truncate at every token boundary, and score the
recovered tree against the tree of the completed file.

**Kill condition.** The CSS case failing is disqualifying, because it is the
exact complaint that motivated the feature. Also disqualifying: recovery whose
cost is not bounded, since Squirrel holds `O(n·|G|)` under arbitrary errors and
that is the bar.

---

## Rung 6 - does the importer work?

**Premise.** The corpus is imported, not written. If it is not, there is no
product regardless of how good the algebra is.

**Measurement.** Forty `grammar.json` files in. Assert:

- every node kind name is byte-identical to tree-sitter's;
- the existing, unmodified `highlights.scm` runs against our tree and produces
  the same captures over a held-out corpus;
- parse trees are structurally equal on a large corpus, with every divergence
  enumerated and explained rather than counted.

**Kill condition.** Node-name divergence, because it silently breaks every
downstream `.scm` file in the world. This one is pass/fail with no tolerance
band.

---

## Standing adverse tests

Not rungs; these run forever once there is code.

- **Differential against tree-sitter** on the full grammar corpus, with any
  structural divergence a hard failure until explicitly accepted.
- **Edit-sequence fuzzing.** Random edit streams, asserting that the incremental
  tree equals a from-scratch parse after every single edit. This is the only
  test that catches a wrong joint composition, and it must run on every commit.
- **Adversarial grammars.** Deep right recursion, dangling else, heavy ambiguity,
  and the grammars that break tree-sitter's build (vim, zsh) - both for
  correctness and for press memory.
- **No-libc, arena-only build.** A freestanding target in CI, because "runs
  anywhere" is a claim that rots the instant nobody compiles it.
- **Folio format stability.** Byte-exact round-trip plus a rejection test per
  malformed field. A grammar artifact that a future version silently
  misinterprets is worse than one it refuses to load.

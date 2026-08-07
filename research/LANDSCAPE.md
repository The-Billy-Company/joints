# The landscape - the mathematics joints is built on

This is the map that has to exist before a line is written. It states what
tree-sitter actually is, where it is genuinely soft, and the algebra we intend
to beat it with. **Nothing here is implemented yet.** Every number attributed to
an incumbent was read out of that incumbent's source, its issue tracker, or a
measurement taken on 2026-08-02; every claim attributed to us is a hypothesis
with a falsifier attached.

---

## 0. The thesis

**Tree-sitter treats parsing as code generation. Joints treats parsing as
algebra.**

That single choice is upstream of every pain tree-sitter has. A grammar becomes
a C program; the program becomes a binary; the binary becomes an installation
problem. `tree-sitter-c-sharp`'s `src/parser.c` is **30.54 MB** today. The zsh
and vim grammars need **more than 20 GB of RAM to build**, which means they
physically cannot be built on a GitHub runner. Ten mainstream languages in a
browser is **~25 MB of WASM downloaded before a single line highlights**. None
of that is a parsing problem. It is the shadow cast by "the grammar becomes a
program."

Take the other branch and the shadow goes away. A grammar becomes a
finitely-generated **monoid presentation** plus a homomorphism from bytes.
Parsing is evaluating a product in that monoid. Incremental reparse is replacing
one factor in a product you were already maintaining in a balanced tree.
Parallel parsing is a prefix scan. Error recovery is the same product taken in a
different **semiring**. The tree is *itself* a word in a monoid, maintained in
the same structure. One data structure, five monoids, one file format, one
binary.

That is not a slogan. It is a factoring in which five separately-hard features
fall out of one implementation.

---

## 1. The incumbent, measured

Tree-sitter is good, and the parts that are good are not the parts people
praise. Its algorithm is a 1980s deterministic LR(1) table with GLR splitting at
conflict points, and its incremental reparse is a faithful implementation of
Wagner's 1998 thesis. Several systems in the literature already have strictly
better asymptotics. Its actual moat is three things:

1. **~300 maintained grammars** with `highlights.scm` / `tags.scm` /
   `injections.scm`. No new project bootstraps that.
2. **A C ABI with no runtime**, which is why Neovim, Emacs, Helix, Zed, GitHub,
   and Pulsar all converged on it.
3. **Recovery that is mediocre but never crashes.**

The soft targets, each with a number:

| Soft spot | The measurement |
|---|---|
| Artifact size | `parser.c`: C# 30.54 MB, Scala 27.21 MB, C++ 24.66 MB; third-party Nim 65.5 MB, SystemVerilog 59.3 MB. The dense parse table is **64% of the file at 24.3% density**. |
| Build cost | vim and zsh need **>20 GB** to compile. zsh ships no WASM artifact because CI cannot build it. |
| Per-node memory | Every internal node is an individually heap-allocated `SubtreeHeapData` with an **atomic refcount**. Lezer's counterexample stores small nodes as **four `uint16`s in a flat buffer**. |
| GLR paid but unused | ast-grep instrumented the stack: **98.898% of `StackNode`s have exactly one predecessor**, at **160 bytes each**. The graph-structured stack is a linked list 99% of the time. |
| Recovery is unsteerable | `error_cost` is a greedy heuristic with no author-facing knob. Pulsar's canonical case: CSS `justif` inside a rule parses as an `attribute_name` in an `ERROR` node, so completions got *worse* than the TextMate grammar they replaced. |
| Context-sensitive lexing needs C | Indentation, heredocs, and string interpolation require an external scanner in C, with a **1024-byte** serialization budget and a curated libc allowlist that `web-tree-sitter` must pre-export at Emscripten link time. |
| Query predicates run in the binding | `#match?` regexes are evaluated by the *host language*, once per candidate match, not by the core. |
| Suffix invalidation | Reuse requires lex mode *and* parse state to match, left to right. Open a block comment at the top of a file and **nothing after it is reusable**. |

The last row is the one worth staring at, because it is the crack the whole
algebra goes into.

---

## 2. The five monoids

A monoid is a set with an associative product and an identity. That is the
entire prerequisite for three things we want simultaneously: **parallel
evaluation** (associativity means you may re-bracket, so a product becomes a
prefix scan of depth O(log n)), **incremental update** (maintain the product in
a balanced tree and one changed factor costs O(log n) re-multiplications), and
**composition without a base point** (a monoid element is a *function*, so it
does not need to know what came before it).

That third property is the one tree-sitter gives up. It stores a *state*; we
store the *function*. A state must be recomputed when its predecessor changes. A
function does not.

### M1 - the lexical transition monoid

Classical, and the easy one. Over a byte-class alphabet the lexer is a DFA, and
the effect of a byte string `w` is the function `δ_w : Q -> Q`, with
`δ_uv = δ_v ∘ δ_u`. Associative; identity is `id`.

An element is a `|Q|`-entry table of state ids. For `|Q| <= 16` on NEON or
`<= 32` on AVX2 that is **a single SIMD register, and composition is one
`vpshufb` / `tbl` instruction**.

Two consequences:

- **Data-parallel lexing.** A prefix scan over M1 lexes with O(log n) depth
  (Ladner-Fischer). This is Mytkowicz-Musuvathi-Schulte's "enumeration, not
  speculation" from ASPLOS 2014, whose central identity is *enumeration for an
  FSM is a gather*: they measured up to 3x on one core and 21x on eight. Nobody
  has ever done this to a *code* lexer.
- **Convergence makes it cheap.** Real lexers collapse: after a few bytes every
  start state maps to the same target, so `δ_w` is a **constant function**,
  which is one byte rather than `|Q|`. The practical representation is a tagged
  union of `constant` and `full`, and composing two constants is O(1).

**And the reparse win falls straight out.** Because a chunk stores a *function*
and not a *state*, an edit that changes the lexical context of everything after
it - opening a block comment, opening a string, changing an indentation level -
does **not** invalidate the suffix. The suffix's functions are unchanged; only
the O(log n) products above the edit are recomputed. Tree-sitter re-lexes to the
point of reconvergence, which for a block-comment-open is the rest of the file.
That is O(n) against O(log n), on the single most common catastrophic edit in
an editor.

### M2 - the joint monoid (stack effects). This is the new one.

An LR parser's stack is not arbitrary; it is a path in the goto automaton, so
represent it as a string of **grammar symbols** and recover states by replaying
`goto` from whatever is exposed. Then the effect of consuming a token segment
is, per entry state, *pop k symbols, push the symbol string σ*:

```
J : Q ⇀ (ℕ × V*)
```

Composition of two effects `(k₁, σ₁)` then `(k₂, σ₂)`:

```
if |σ₁| ≥ k₂:   (k₁,                    σ₁[0 .. |σ₁|−k₂] · σ₂)
else:           (k₁ + k₂ − |σ₁|,        σ₂)
```

Associative; identity `(0, ε)`. This is the **stack-effect monoid**, the same
algebra as concatenative-language stack types and a quotient of the free
product. A `J` is a table over entry states, and tables compose by pullback
through `goto`. We call one a **joint**, because that is what it is: the
description of how a parsed segment joins to whatever precedes it, independent
of what precedes it.

What this buys, and it is the centre of the whole design:

- **Incremental reparse in O(log n) regardless of where the edit lands**, by
  maintaining the joint product in a balanced tree instead of walking
  left-to-right. Tree-sitter's reuse is directional; a joint has no direction.
- **Parallel parse** in O(n/p + log p) by scanning the same monoid. It is the
  same code path as M1.
- **GLR paid exactly where it is used.** A joint whose table is single-valued is
  deterministic; a joint that is genuinely multi-valued is where you branch.
  Given the measured 98.898%, more than 98 in 100 joints are rank-one and
  composing them is a pointer join.
- **Reuse validity is decidable from the object**, not from a heuristic. Lezer's
  "context hash" is a hash of a joint's domain. Tree-sitter's scanner
  serialize/deserialize is a lossy stand-in for one. Here it is the actual
  algebraic object, and equality is exact.

The prior art is partial and that matters. Parallel LR by stack-effect
composition goes back to Fischer (1975) and Mickunas & Schell (1978), and
Ghezzi & Mandrioli's 1979 TOPLAS paper already knew that threading a parse from
both ends makes cost independent of edit position. What does **not** appear in
the literature is the intersection: maintaining the stack-effect product in a
**monoid-annotated balanced tree** for editor-scale incrementality, with lazy
GLR on the rank of the element. That intersection is [the joinery
claim](joinery/CLAIM.md), and it is the one thing here that has to be proved
rather than cited.

### M3 - the tree monoid (balanced parentheses)

Serialize the tree depth-first as `(` and `)`. That is a word in the free monoid
on two letters, and the measure

```
μ(w) = (total_excess, min_excess, max_excess)
μ(uv) = (t_u + t_v,  min(m_u, t_u + m_v),  max(M_u, t_u + M_v))
```

is a monoid homomorphism. This is exactly Sadakane & Navarro's **range min-max
tree** (SODA 2010), under which `parent`, `firstChild`, `nextSibling`,
`subtreeSize`, `depth`, and `LCA` are all `fwdsearch`/`bwdsearch` over the same
annotated tree. The information-theoretic floor for an ordinal tree is
**2n + o(n) bits**, roughly two bits per node, against tree-sitter's ~48-64
bytes plus an atomic refcount.

The beautiful part is not the compression. It is that **an edit splices the
parenthesis word, and a splice on a monoid-annotated balanced tree is the same
O(log n) operation as M1's and M2's.** The tree store and the incremental parse
index are literally the same data structure with a different measure.
Sadakane-Navarro's dynamic variant is the only credible succinct base for an
editor, and it is exactly a finger tree over this monoid.

### M4 - the semiring layer (recovery, ranking, counting)

A parse is a path through the product graph of (position x configuration). That
graph is a **trellis** in the coding-theory sense, and the algorithm you run on
a trellis is a semiring shortest path. Change the semiring, change the question:

| Semiring | ⊕ | ⊗ | Answers |
|---|---|---|---|
| Boolean | ∨ | ∧ | does it parse |
| Tropical (min, +) | min | + | **minimum-cost error repair** |
| Viterbi (max, x) | max | x | ranked disambiguation |
| Counting (ℕ, +, x) | + | x | how ambiguous is this grammar |
| Parse forest | ∪ | x | the SPPF |

**One engine, parameterized.** Tree-sitter hardcodes a greedy `error_cost` and
gives authors no knob. Under the tropical semiring, recovery is a Viterbi pass
returning a *provably minimum-cost* repair, with the weights declared in the
grammar. Pulsar's CSS complaint is then a one-line grammar edit: say that an
incomplete `property_name` costs 1 and a dropped token costs 100, and the
algebra does the rest. Hutchison's Squirrel paper (arXiv 2601.05012, January
2026) derives recovery from four axioms and twelve constraints with a proof of
necessity for each component; that is the correctness bar to hold ourselves to,
and the semiring formulation is how we reach it without giving up LR's
throughput.

Critically, the semiring composes *with* M2: joint entries become
semiring-weighted, so incremental, parallel, and error-tolerant are one code
path rather than three.

### M5 - the quotient lattice (where the size win comes from)

Two Myhill-Nerode quotients, both of which irregex has already proved out on
regexes:

1. **Predicate minterms for the alphabet.** irregex's
   `kernel/regex/linear/symbolic/alphabet.zig` refines by transition set rather
   than cutting at range boundaries, and
   measured against `regex-automata --minimize` that is **2.32x coarser
   alphabets and 2.38x smaller tables**. Applied to grammars it deletes
   tree-sitter's `ts_lex_modes` array outright (1.1 MB in C# alone) and shrinks
   every lexer table quadratically, since determinization work is
   `states x classes`.
2. **Action-bisimulation on the LR automaton.** LALR merges states by *core*,
   which is a crude proxy. The principled merge is the coarsest partition that
   preserves observable action behaviour - Paige-Tarjan / Hopcroft refinement
   over the table's rows. It is strictly coarser than LALR and provably
   parse-preserving. Then the residual table is a **DAFSA over (state x
   minterm)** built by Daciuk-style incremental minimization, which captures the
   row-level redundancy that CSR only partially reaches.

For scale: tree-sitter's own in-flight CSR work takes C# from 29 MB to 8.5 MB.
Quotient-then-DAFSA should land materially below that, and the number worth
publishing is **bits per production**, not megabytes, because megabytes are a
grammar-size confound.

### M6 - hash-consing is grammar-based tree compression

A footnote that turns out to be load-bearing. Hash-consing the tree
(`irregex/src/kernel/math/dag.zig`, already built) produces a DAG whose shape is
exactly a **straight-line tree grammar**, which is precisely what TreeRePair and
top-tree compression produce offline. rowan's node interning and Lohrey's
compression literature are the same object arrived at from two directions.
Source code has enormous subtree repetition - five hundred identical `pub fn`
headers store once - and succinct structures are *blind* to it, because their
space is never o(n). So the settled representation should be **succinct for
navigation, hash-consed for identity**, and we get the second half from a
primitive that exists today.

---

## 3. One structure: the spine

Everything above is maintained in a single **monoid-annotated balanced tree** - a
measured rope, a finger tree, whatever you want to call the shape. We call it
the **spine**, because it is what every other structure is bound to.

```
spine over M1  ->  the lexical index      (edit costs O(log n), suffix survives)
spine over M2  ->  the parse index        (edit costs O(log n), position-independent)
spine over M3  ->  the tree itself        (navigation is fwdsearch, 2n+o(n) bits)
spine over M4  ->  recovery and ranking   (same walk, different semiring)
```

Four features, one splice implementation, one set of tests, one cache-line
discipline. That is the economy the whole package is buying.

---

## 4. The distribution answer: one binary, one folio

Because a grammar never becomes code, it becomes data: a **folio**, a single
mmap-able, versioned, content-addressed file holding N languages' quotiented
tables, minterm alphabets, node-kind names, injection rules, and compiled query
programs. One binary plus one folio is every language you support. No C
compiler, no `.so` per language, no ABI version window, no Emscripten pin, no
20 GB CI build, no `parser.c` in git.

ANTLR already proved grammar-as-data works in production - it serializes its ATN
into a blob the runtime interprets - and, more usefully, it proved the failure
modes to avoid:

- **16-bit elements are not enough.** Real grammars overflow it
  (`Serialized ATN data element out of range 0..65535`). Use 32-bit fields.
- **Never embed the artifact in a host language's literals.** ANTLR must split
  its blob across Java string literals because of the 64 KB constant-pool limit.
  A folio is a file, mmapped, with a BLAKE3 signet - machinery irregex already
  ships in `corpus/index/frame/`.

GPeg (Yedidia & Chong, SLE 2021 best paper) is the other proof: a grammar as
parsing-machine bytecode, with **logarithmic reparse and sub-5 ms edits on
inputs from tens to hundreds of megabytes**. It is PEG-shaped where we are
LR-shaped, but it settles the question of whether an interpreted grammar can be
fast enough. It can.

The runtime must also be **arena-only and freestanding-capable**: no libc
requirement, allocation through a caller-provided arena. That is what "a wider
array of surfaces" means in code. It runs in a browser, in an editor, on a
phone, in a sandbox, inside another language's FFI, with no per-surface build
story.

---

## 5. What must grow in irregex

irregex is the math floor for this family, and most of what joints needs is
already sitting in it: `portal.zig` (mmap), `signet.zig` (BLAKE3),
`frame.zig` (atomic artifact publish), `fresh/` (the dual-clock freshness
model), `bits.zig`, `dag.zig` (hash-consing), `mix.zig` (`SliceCtx` interning),
`forest.zig` (union-find), `lease.zig` (warm-state leases), `parallel.zig`
(byte-balanced fan-out), `scan/{simd,teddy,aho}.zig` (keyword recognition),
`succinct/{rrr,wavelet,sais}.zig`, plus the whole brigade / ward / contract
discipline.

Seven things are missing, and every one of them is general mathematics that
belongs in irregex rather than in joints:

| Add to irregex | Why it belongs there | Who else wants it |
|---|---|---|
| `kernel/math/monoid.zig` - the Monoid concept plus a generic **parallel prefix scan** (Ladner-Fischer / Blelloch over `parallel.zig`'s fan-out) | irregex runs DFAs; the `shuffle` rung is already a special case of scan-parallel automaton execution, arrived at by hand | irregex regex rungs; joints M1 + M2 |
| `kernel/math/spine.zig` - the monoid-measured balanced tree, with O(log n) splice | irregex needs a line index and incremental index amendment today | joints M1/M2/M3; relate's fragment spans; gist's line index |
| `kernel/math/refine.zig` - Paige-Tarjan / Hopcroft coarsest stable partition | `linear/automata/reduce.zig` hand-rolls Moore for the symbolic road; the sieve's SP-closure ascends the same lattice from the other end | irregex determinizer; joints M5 |
| `kernel/math/succinct/parens.zig` - BP plus range min-max tree | `succinct/` already has RRR rank/select and a wavelet tree; parentheses is the missing third leg | joints M3; any hierarchical index |
| `kernel/math/semiring.zig` - Boolean / tropical / Viterbi / counting | approximate matching is a tropical walk over an automaton irregex already builds | joints M4 |
| `kernel/math/dafsa.zig` - Daciuk incremental minimal automaton | table and dictionary compression | joints M5, folio packing |
| Unseal the **symbolic minterm alphabet** for external consumers | `contract/irregex.ward` seals `kernel/regex` behind `regex.zig`, but a predicate-minterm alphabet is alphabet theory, not regex opinion | joints M5 |

The payoff runs back into the family too. relate's `spans.zig` currently finds
functions by counting braces and climbing sixteen lines looking for something
that resembles a signature, across exactly two strategies and twenty-eight file
extensions; its `silhouette.zig` normalizes identifiers to `I`, numbers to `N`,
and strings to `S` against a hand-unioned keyword list. Both are honest
approximations of a parse, and both get replaced by an actual one. blast's live
blast radius stops guessing at definitions.

---

## 6. The package, and its vocabulary

The metaphor is bookmaking, and it is load-bearing rather than decorative:
**you write a rubric; the press compiles it into a folio. At runtime the grain
reads the material, joints compose along the spine, mend repairs what is torn,
gloss answers questions, and the result settles from quire into vellum.**

| Word | What it is | Why that word |
|---|---|---|
| **rubric** | the human-authored grammar source (`.rubric`) | a rubric is the set of structural rules a scribe marks a text with |
| **press** | the grammar compiler: rubric -> LR(1) -> quotient -> DAFSA -> folio | it is what turns loose rules into a bound artifact |
| **folio** | the compiled bundle: N languages, one mmap-able file | a folio is one bound volume holding many gatherings |
| **grain** | the SIMD stage-one structural pre-pass | you read the grain of the material before you cut or fold it |
| **joint** | an M2 stack-effect element | it describes how a segment joins to what precedes it |
| **spine** | the monoid-annotated balanced tree (lives in irregex) | everything is bound to it |
| **mend** | tropical-semiring least-cost repair | you mend a torn page rather than discarding it |
| **quire** | the live, editable tree region | the working gathering of sheets, not yet bound |
| **vellum** | the settled succinct BP encoding | the durable finished surface |
| **gloss** | the query engine | a gloss is an annotation keyed to a span of text |

```
src/
  kernel/
    grain/    string and comment spans, bracket positions, line starts,
              indentation columns - one SIMD pass, patchable in O(log n)
    lex/      M1 - the minterm lexer and its transition monoid
    joint/    M2 - the stack-effect monoid, its scan, lazy GLR on rank
    mend/     M4 - tropical-semiring least-cost repair
    quire/    M3 - the live tree; vellum/ is its settled succinct encoding
    gloss/    query programs, static reachability, predicates in the core
  folio/      the artifact: pack, read, verify, slice one language out
  press/      the compiler, plus import/ - the tree-sitter grammar.json importer
  surface/
    face/joints/   the CLI
    ffi/             libjnt, the C ABI (jnt_* symbols)
```

`grain` deserves its own note, because it is the one place SIMD unambiguously
wins. simdjson's stage one identifies every structural character in 64-byte
batches with vectorized classification and a branchless prefix-XOR for quoted
regions, hitting UTF-8 validation at 13 GB/s. Parabix generalizes the same idea
to arbitrary regular languages via transposed bit-planes. Applied to source
code, one pass yields string and comment spans, bracket positions, line starts,
and per-line indentation columns - which is *exactly* the input a data-dependent
grammar needs for `offside` and `align`, and exactly what tree-sitter makes you
write C for. The structural index is also trivially patchable, so it survives
edits at the same O(log n) as the rest of the stack.

---

## 7. What we cannot win by writing better software

Be clear-eyed. **The grammar corpus and the query files are the moat, and they
cannot be out-engineered.** Three hundred grammars with highlight queries
represent person-decades. The answer is not to write them; it is to *import*
them. `grammar.json` is tree-sitter's declarative serialized intermediate, it is
committed in most grammar repos, and it is a data file. A
`grammar.json -> .rubric` importer is not a nice-to-have, it is the entire
go-to-market, and it has to work on day one for the top forty languages or none
of this ships. Query files are S-expressions over node names; if the importer
preserves node names, the `.scm` files come along.

Equally honest about the algorithm: **tree-sitter's throughput is fine.** Sijm's
incremental-GLR measurements against real git histories found 99% average parse
reuse and a 24% overhead on batch parses as the price of being incremental at
all. Nobody is waiting on a parser. Do not sell speed. Sell *size*, *reach*,
*recovery quality*, and *one install*.

---

## 8. The order of proof

Each rung is cheap, states a premise, and can kill the one above it. The house
rule from irregex's automata dossier applies verbatim: a claim is not credible
until it has been timed against bytes, and you must price **both halves** of
every exchange.

1. **The joint converges.** Instrument an LR automaton for a real grammar and
   measure the domain size of joints over real files. If joint tables do not
   collapse toward rank one, an element costs `|Q|` and composition loses to
   tree-sitter's O(1)-per-token walk. **This is the falsifier for the entire
   design and it is measurable before anything is built.**
2. **The lexical monoid collapses.** Same measurement for M1. Known to hold for
   regex and HTML from the ASPLOS 2014 work; must be confirmed for code lexers.
3. **The spine splice is cheap enough.** Price a splice against tree-sitter's
   reuse walk on the four edits that matter: type a character, open a block
   comment at the top of a file, paste 500 lines, delete a brace.
4. **The quotient is worth its build time.** Bits per production against
   tree-sitter's CSR branch, on the same forty grammars.
5. **Recovery is better, and provably.** Pulsar's CSS `justif` case is the
   acceptance test; the tropical repair either produces the node a human expects
   or the claim is dead.
6. **The importer works.** Forty grammars in, byte-identical node names out,
   existing `highlights.scm` running unmodified.

Rung 1 is the whole bet. If joints do not converge, the honest outcome is to
write that down in a `CLOSED.md` and go do something else, and finding it out
costs one instrumented afternoon rather than a year.

---

## Annotated sources

Everything cited above, with what each one establishes.

**Tree-sitter, as it is**

- [`lib/src/subtree.h`](https://github.com/tree-sitter/tree-sitter/blob/master/lib/src/subtree.h) - `SubtreeInlineData` packs leaves into a word; every internal node is a refcounted `SubtreeHeapData`. The memory story in one file.
- [`lib/src/parser.c`](https://github.com/tree-sitter/tree-sitter/blob/master/lib/src/parser.c) - `ts_parser__can_reuse_first_leaf` is the reuse predicate: lex mode *and* parse state must match, which is why suffix invalidation is total.
- [`lib/src/query.c`](https://github.com/tree-sitter/tree-sitter/blob/master/lib/src/query.c) - `ts_query__perform_analysis`; `QueryState` is the unit of combinatorial blowup, and predicates are not evaluated here at all.
- [PR #5488, CSR parse-table compression](https://github.com/tree-sitter/tree-sitter/pull/5488) - the richest source of hard numbers anywhere: C# 29 MB to 8.5 MB, dense table 64% of the file at 24.3% density, zsh needing >20 GB, and the ABI-16 adoption deadlock.
- [Improving Tree-sitter's GLR algorithm and memory layout](https://ast-grep.github.io/blog/optimize-tree-sitter.html) - the 98.898% single-predecessor measurement and the 160-byte `StackNode`.
- [Modern Tree-sitter, part 7](https://pulsar-edit.dev/blog/20240902-savetheclocktower-modern-tree-sitter-part-7.html) - the best qualitative critique in existence: the CSS `justif` recovery failure, the `web-tree-sitter` libc-export dilemma, Emscripten version locking.
- [Stack graphs](https://github.blog/open-source/introducing-stack-graphs/) and [arXiv 2211.01224](https://arxiv.org/abs/2211.01224) - how GitHub builds file-incremental name resolution on top of CSTs, and therefore what a semantic layer above us would look like.

**The nearest neighbour**

- [Lezer system guide](https://lezer.codemirror.net/docs/guide/) - states its differences from tree-sitter outright: the 16-bit-quad tree buffer, opt-in GLR, contextual tokenization including contextual whitespace, and external-tokenizer **context hashes** as the reuse-validity check. The context hash is a hash of what we call a joint's domain.

**Incremental parsing**

- Ghezzi & Mandrioli, [Incremental Parsing, TOPLAS 1(1), 1979](https://doi.org/10.1145/357062.357066) - threading the parse from both ends makes cost independent of *where* the edit is. Tree-sitter is left-to-right and pays for it.
- Wagner & Graham, *Practical Algorithms for Incremental Software Development Environments* (Berkeley, 1998) - the thesis tree-sitter and Lezer both implement.
- Sijm, [Incremental Scannerless Generalized LR Parsing](https://repository.tudelft.nl/record/uuid:6ddf9fbd-c39e-4aae-b6ce-13389def6a9f) (TU Delft, 2021) - measured on real git histories: 99% reuse, 24% batch overhead, 9x on sub-1% edits, and the negative result that scannerless non-determinism *degrades* incrementality.
- Yedidia & Chong, [Fast Incremental PEG Parsing](https://zyedidia.github.io/preprints/gpeg_sle21.pdf) (SLE 2021, best paper) - interval-tree memo table with lazy shifts gives **logarithmic** reparse; GPeg is grammar-as-data in a parsing machine. The closest thing to our O(log n) target, from the PEG side.

**Error recovery**

- Hutchison, [The Squirrel Parser](https://arxiv.org/abs/2601.05012) (arXiv 2601.05012, January 2026) - recovery derived from four axioms and twelve constraints with a necessity proof per component; O(n·|G|) preserved under arbitrary errors. The correctness bar.
- Hutchison, [Pika parsing](https://arxiv.org/abs/2005.06444) (arXiv 2005.06444) - bottom-up right-to-left DP gets optimal recovery for free, at a per-character constant too large for big grammars. Establishes that optimal recovery is achievable, and expensive the naive way.

**Data-dependent grammars, i.e. deleting the C scanner**

- Afroozeh & Izmaylova, [Iguana](https://dl.acm.org/doi/10.1145/2892208.2892234) (CC 2016) - desugars `offside`, `align`, `ignore`, follow/precede restrictions, and keyword exclusion into data-dependent grammars. The direct, principled replacement for tree-sitter's external scanner, validated on OCaml, Haskell, Java, C#.
- Jim, Mandelbaum & Walker, *Semantics and Algorithms for Data-Dependent Grammars* (POPL 2010) - the underlying formalism: parameterized nonterminals, binding, constraints.

**Parallelism**

- Mytkowicz, Musuvathi & Schulte, [Data-Parallel Finite-State Machines](https://www.microsoft.com/en-us/research/publication/data-parallel-finite-state-machines/) (ASPLOS 2014) - "enumeration for FSM is gather"; up to 3x on one core, 21x on eight, with `_mm_shuffle_epi8` standing in where hardware gather is absent. The M1 result, already proved on other automata.
- Ladner & Fischer, *Parallel Prefix Computation* (JACM 27(4), 1980); Hillis & Steele, *Data Parallel Algorithms* (CACM 29(12), 1986) - the scan primitives that make any monoid product O(log n) deep.
- Langdale & Lemire, [Parsing Gigabytes of JSON per Second](https://arxiv.org/abs/1902.08318) (VLDB J 28(6), 2019) - the two-stage design; the structural index is what `grain` generalizes to source code.
- Cameron et al., *Bitwise Data Parallelism in Regular Expression Matching* / *Parallel Scanning with Bitstream Addition* (LNCS 2011) - Parabix; lexical scanning as bitstream arithmetic, more general than simdjson's fixed structural set.

**Trees**

- Sadakane & Navarro, [Fully-Functional Succinct Trees](https://dl.acm.org/doi/10.5555/1873601.1873614) (SODA 2010) - the range min-max tree; 2n + O(n/polylog n) bits, constant-time operations, implementable, and the first **dynamic** succinct trees. M3 is this structure with a parser attached.
- Jacobson (1989); Munro & Raman (2001) - the 2n+o(n) bound and its constant-time word-RAM realization.
- Bille et al., [Tree Compression with Top Trees](https://arxiv.org/pdf/1304.5702) - notes that succinct structures are never o(n) and therefore blind to subtree repeats. Why M6 exists.
- Lohrey et al., [Tree structure compression with RePair](https://arxiv.org/pdf/1007.5406) - grammar-based tree compression with traversal on the compressed form; the same object hash-consing produces online.

**Grammar as data**

- [antlr4#76](https://github.com/antlr/antlr4/issues/76) and [PR #3438](https://github.com/antlr/antlr4/pull/3438) - the serialized ATN's 16-bit element overflow and the Java constant-pool splitting hack. Both failure modes a folio must not reproduce.
- [ANTLR `CHANGES.txt`](https://github.com/antlr/antlr4/blob/dev/CHANGES.txt) - "add 2 to each element" to dodge UTF-8-expensive byte values, and UUID-based ATN versioning. What happens when your artifact format lives inside someone else's string literal.

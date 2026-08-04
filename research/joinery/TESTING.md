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

### Rung 1 - verdict: **conditional pass, and the condition is the table**

Run it yourself: `outliner joints <grammar.json> <file>...`, which reports every
segmentation on one line each. `--exact` picks the other fusion pole and
`--confess` prints the limbs at a ceiling. Two grammars, both real files.

**json** - 44 states, no contested cells at all, 27,714 tokens:

| span | rank med / p99 | domain med | plural | undetermined | chain |
|---|---|---|---|---|---|
| 4 tok | 3 / 64 | 6 | 10.9% | 0% | agreed, residue ≤ 34 |
| 16 tok | 11 / 72 | 6 | 15.4% | 0% | agreed, residue ≤ 31 |
| 128 tok | 24 / 84 | 6 | 16.8% | 0% | agreed, residue ≤ 28 |
| 16 KB | 20 / 74 | 2 | 12.3% | 0% | agreed, residue ≤ 3 |

**The stated kill condition is not met.** Median rank is 3 to 24, not 1, and the
99th percentile is 64 to 84, not 4. By the letter of the rung above, write
`CLOSED.md`.

It is not being written, and the reason is that rank turned out not to measure
what the rung assumed it measured. The kill number was chosen as a proxy for
"composing two joints costs `|Q|`". It is not that, for two reasons the
instrument had to exist to see:

- **Rank counts plural answers, not table entries.** Domain is 2 to 6 of 44
  states, so the *table* is tiny; rank exceeds `|Q|` because one entry state
  yields several effects. Those are not distinct table rows to be joined
  through, they are unrefuted hypotheses about a stack the segment cannot see.
  A segment ending inside a nested object genuinely does not know whether it
  popped two levels or eight, and json's object nesting is a six-state cycle, so
  nothing that guards over *states* can ever tell those apart. Later input can,
  and does.
- **What the guards owe is that the product still comes out right, and it
  does.** The chain agrees at every segmentation on the file: the product of the
  segment effects is the effect of the whole file, over 6929 segments and over
  9. That is the property the design actually needs, and rank was standing in
  for it badly.

So the sharper falsifier, and the one to hold this to from here, is **residue**:
how wide the running product of unrefuted pairings ever gets. A residue bounded
independently of the file is a fan; a residue that grows with the file is a
graph-structured stack with extra steps, which is the thing this replaces.
Measured, it is bounded and *not* a function of how finely the file is cut -
6929 segments peak at 34 and 9 segments peak at 3. It never grew.

**The one trade left.** Fusing two limbs by depth widens their interior claims;
fusing them only on identical claims does not. Exact fusion drives the residue
to **1** - composition alone singles out the branch at every step, no fan at all
- for segments up to 16 tokens, and past 32 the limb count runs away. Depth
fusion never runs away and never disagrees, at a residue in the low thirties.
Since a balanced tree over the stream chooses its own leaf size and only ever
runs the cursor over a *leaf*, both poles are live and the choice is a leaf-size
decision rather than an algebra one. `depth` is the default.

**go** - 814 states, and this is where the condition bit. tree-sitter grammars
are GLR grammars, so the LALR table kept **184 conflicts it could not resolve**
even with tree-sitter's own declared precedences applied. Relative to `|Q|` the
ranks were *better* than json's (median 3 to 13, p99 15 to 20), but ~20% of
(state, segment) pairs came back undetermined, and at fine spans the oracle
could not run even from the state the parser really was in. Widening either
capacity only moved pairs between the two failure columns - see `fan_ceiling`
for the sweep - because the width was a symptom of the nondeterminism rather
than the cause.

**That was a press bug, four of them, and Go's table is now deterministic.**
1029 states, **23 contested cells, all 23 of them groups Go's author declared,
none residual**. Read the classification yourself with `outliner grammar
<grammar.json> --conflicts`, which groups every contested cell by whose rules
were arguing and spells out the two productions. What the conflicts turned out
to be, in the order the measurement surfaced them:

- **Nonterminals reported as deriving nothing that derived plenty.** The report
  flagged any rule with no productions, which indicts `fold.nonterminals` for
  succeeding: a folded rule has none *because* it was substituted away. The
  honest question is whether a right-hand side still names it, and whether it
  derives a terminal string - which is its own fixpoint, not FIRST being empty
  and not a production count. Every flagged rule was a false alarm.
- **The same production twice.** Normalizing EBNF reaches one body down two
  paths whenever optionals nest, so Go's `parameter_list` had `( )` twice.
  Two identical productions cannot be told apart by any parser, so every state
  where both complete is a reduce/reduce conflict about nothing. **50 of Go's
  77 reduce/reduce conflicts were `literal_value -> { }` against itself.**
- **`repeat` given an epsilon base.** An auxiliary `L -> ε | L x` makes a parser
  decide whether a list is empty at the point the list begins, before it has
  seen anything to decide with. Spelling `repeat` as what it is -
  `optional(repeat1)`, with the optionality in the *host* production - moves the
  decision to where the evidence is. **This removed every shift/reduce residual
  in all four grammars**: java 133 to 0, c 157 to 0, python 4 to 2.
- **Precedence dropped inside a repeat body, and one list per occurrence.**
  Python's `union_pattern` is `repeat1(prec.left(...))` and the `prec.left` was
  being discarded, leaving the ladder nothing to settle with; Java writes
  `repeat($.catch_clause)` in two alternatives of one rule and got two
  auxiliaries, distinguishable only by a name the language does not have.

| grammar | residual at start | after dedup | after repeat shape | now |
|---|---|---|---|---|
| json | 0 | 0 | 0 | **0** |
| go | 79 | 2 | 0 | **0** |
| python | 4 | 4 | 2 | **0** |
| java | 189 | 189 | 48 | 46 |
| c | 258 | 258 | 33 | 33 |

**What this decides.** M2 is sound and its product converges on a deterministic
table, which is the thing rung 1 existed to find out - and three real grammars
now have one, so the claim is no longer resting on json alone.

Two things were still open, and neither was the monoid:

- **Go's rung 1 is now blocked on M1, not the press.** With a clean table the
  run stops partway through a real Go file, because the scanner is not yet
  state-directed enough for Go's newline handling. That is rung 2's problem, and
  the section below finds nine more of it.
- **Java's 46 and C's 33 are all reduce/reduce, and all one shape** - two hosts'
  copies of the same list arguing over which of them is being built. Sharing the
  list across rules fixes Java (46 to 11) and *breaks* C (33 to 70), because a
  shared list that can sit next to itself is genuinely ambiguous about where the
  first one stops. Java's author declared exactly the 3- and 4-rule groups that
  only arise if those hosts share one annotation list, which is good evidence
  that sharing is what upstream does; doing it soundly means gating the merge on
  an adjacency check over the finished grammar. Every remaining conflict being
  reduce/reduce also matters on its own: an LALR shift/reduce conflict is always
  a real LR(1) one, so canonical LR(1) item sets could not have helped before
  this and can only help now.

### Rung 1 - eleven grammars, and what the second condition turned out to be

The list sharing landed, gated on adjacency, and canonical LR(1) is *still* not
needed: **every one of the eleven grammars now presses to zero residual
conflicts** - every contested cell either declared by its author or a repetition
the shape fix explains. What replaced it is a subtler kind of merge damage,
which the residual count could not see and a parse notices immediately.

Everything below is over one corpus, `research/joinery/corpus/`: the same little
ledger program written eleven times, once per language, so a rank number differs
because the *grammar* differs and not because the file did. Reproduce any row
with `outliner joints upstream/grammars/<lang>.json research/joinery/corpus/<file>`.

| grammar | states | unfold rounds | residual | frayed (refuse a token) | press |
|---|---|---|---|---|---|
| json | 44 | 0 | 0 | 0 (0) | 0.03 ms |
| go | 1455 | 1 | 0 | 2 (0) | 11 ms |
| java | 2728 | 1 | 0 | 6 (0) | 43 ms |
| javascript | 3514 | 1 | 0 | 121 (0) | 113 ms |
| python | 3352 | 1 | 0 | 246 (1) | 71 ms |
| c | 3562 | 1 | 0 | 577 (5) | 31 ms |
| typescript | 12516 | 1 | 0 | 415 (16) | 578 ms |
| rust | 8559 | 1 | 0 | 795 (65) | 185 ms |
| cpp | 9274 | 1 | 0 | 1640 (116) | 297 ms |
| ruby | 3312 | 1 | 0 | 845 (369) | 163 ms |
| bash | 14042 | 1 | 0 | 562 (438) | 697 ms |

**A cell can be wrong without ever being contested.** LALR merges states by
LR(0) core, so a fold's lookahead is the *union* over the contexts that merged.
Where a shift and that fold meet, the ladder settles it by precedence and calls
it resolved - correctly for the contexts the fold's lookahead really came from,
and wrongly for every other context sharing the state, whose shift has just been
deleted. C's `p->q = 1` was exactly this. In a statement, folding `e -> f` can
only be followed by `;`, so nothing contests the `=`. Under a `*` the same fold
*can* be followed by `=`, because `* f = e` assigns through the pointer - and
both arrivals reach one LR(0) kernel. Merged, the fold is legal on `=` and
outranks the read, whose step carries the negative rank an assignment carries in
every C-family grammar. Zero conflicts, and the language lost a sentence.

So the press computes both the union and the **meet** of each fold's lookahead
and calls a cell **frayed** when a terminal is in one and not the other. Frayed
cells are classified by harm - `read_dropped` when a shift was deleted, the
column above, and `fold_dropped` when two folds disagreed - and the state
splitter is driven by a lexicographic objective over (residual, distinct
read_dropped). Splitting marks a state by a **hash of its predecessor's kernel**
rather than by a predecessor id, which is what makes it converge: a mark that
names a state is invalidated by the split that renames it, so a cycle grows
states forever, where a mark that names a kernel is a fixpoint. C's five
survivors are what one round buys; bash and ruby keep hundreds, and both are
grammars whose real lexer is an external scanner, so the parse cannot be run far
enough to say whether those cells are reachable.

**The rung 1 sweep, on the eleven pressed tables.** All eight segmentations,
defaults everywhere. `stops` is where the token stream ran out and why:

| grammar | tokens | stops | worst p99 rank | widest residue | chains held | refused |
|---|---|---|---|---|---|---|
| json | 277 | accepted | 42 | 2 | 8/8 | - |
| rust | 271 | stray byte in `format!("arg{i}")` | 56 | 1 | 3/8 | 5 |
| c | 130 | stray `*` in `(Ledger *l)` | 68 | 1 | 3/8 | 5 |
| typescript | 75 | stray `>` of `=>` | 20 | 1 | 4/8 | 4 |
| java | 62 | `(` unusable after a scoped type fold | 19 | 1 | 4/8 | 4 |
| go | 51 | `{` unusable after `&Ledger` | 30 | 1 | 4/8 | 4 |
| cpp | 50 | identifier unusable after `std::size_t` | 26 | 1 | 4/8 | 4 |
| javascript | 28 | `)` unusable after `= []` | 11 | 1 | 5/8 | 3 |
| bash | 7 | stray `(` of `rows=()` | 7 | 1 | 7/8 | 1 |
| ruby | 3 | `:` unusable after an identifier | 4 | 1 | 8/8 | - |
| python | 0 | stray `"` of the module docstring | - | - | nothing measured | - |

**Nothing disagreed, anywhere, and the residue never got past two.** That is the
sharper falsifier from the json section, held to across ten grammars: where a
chain ran, composition alone singled out the branch at every step, and json's
`residue ≤ 2` is the single segmentation where it needed a second pairing. The
refusals sort cleanly by cut size and by nothing else - **every byte span holds
on every grammar**, and all 30 refusals are at token spans, heaviest at the
finest. A four-token segment beginning at the `,` inside a parameter list owes
its entire left context to a rewind, and C has hundreds of answers for what a
declarator's prefix was. c and rust are the two that still refuse at 128, and for
the same reason at a coarser grain: they are the two files long enough (130 and
271 tokens) to have a *second* 128-token segment, which begins mid-declaration
like every other refusal does.

**The binding constraint on rung 1 is now the lexer and the fork, not the
monoid.** Only json reads to the end, and every one of the other ten stops is
one of three known-and-owned things:

- **A terminal no lexer rule can produce** - python, ruby, rust, bash. Each
  grammar hands some terminals to a hand-written external scanner, and outliner
  has no equivalent yet: ruby is blind to 29 of its own, bash 22, rust 11,
  typescript 9, python 8, javascript 7, cpp 2. python's docstring is the extreme
  case, since its string start is external, so the file dies at byte 0 and rung 1
  cannot see python at all. ruby's `attr_reader :rows` is the same hole wearing
  the other error message: the state offers `simple_symbol`, which nothing can
  produce, so it is handed a bare `:` and calls it unusable rather than stray.
- **A declared ambiguity a single stack cannot take** - go, java, javascript,
  cpp, and all four are a conflict the grammar's own author wrote down for
  tree-sitter to fork on. `&Ledger{` needs go's `['_simple_type', '_expression']`;
  `rows.addAll(` needs java's `['_unannotated_type', 'primary_expression',
  'scoped_type_identifier']`; `(s = [])` needs javascript's `['array',
  'array_pattern']`; `std::size_t i` needs cpp's `['qualified_type_identifier',
  'qualified_identifier']`. The press honors the declaration by picking a side, and
  the reference walk - which owns one stack by construction, and which the scanner
  asks for the live terminal set - then arrives in the side it wasn't. So the walk
  ends, and the token stream every segmentation is measured over ends with it: the
  cursor is never asked about the bytes past the stop. **Carrying both readings is
  the joint machinery's job**, and rung 6's differential against tree-sitter is
  where that gets settled; the oracle is single-stack on purpose and stays that
  way, since a reference that forked would no longer be a reference.
- **A state-directed scanning gap that costs a keyword** - c, typescript. `long
  f(int a) { return a; }` stops at `a`, because `int` scanned as an identifier:
  the scanner asks the state which terminals are live, the state after `long f (`
  does not offer `primitive_type`, and an identifier is what is left. `int f(int
  a)` and `void f(char *p)` both read fine, which is what makes it scanner-side
  rather than a fray. typescript losing the `>` of `=>` after `(v, i)` is the same
  gap. It is the same M1 work Go's newline handling needs.

**Three instrument bugs the sweep found, in the order they mattered:**

- **A limb could walk a grammar's cycle forever.** A fold that takes one symbol
  and gives one back leaves the stack the length it was, so `A -> B` answered by
  `B -> A` is a closed loop - and an imported grammar has those, since a hidden
  rule inlined into its own alternative is one. Python spent minutes on a
  four-token file. The fix is not a ceiling: everything a limb does next is a
  function of the configuration it is in and the token it is reading, so
  returning to a configuration *proves* the loop is closed and the limb is
  refuted. Six of the eleven grammars had been exceeding a 120-second timeout;
  the whole sweep now runs in 11 seconds, tables included.
- **The limb ceiling was counting slots, not limbs.** `used` includes the slot
  every refuted limb left behind, so a run gave up having touched 256 of them
  while holding nine, and reported on its own bookkeeping. Counting what stands
  costs more and answers the question asked.
- **A bound on what stands is not a bound on what it cost.** Counting honestly
  put C's file at 49 seconds, because a fold storm sprouts and buries thousands
  of limbs to leave nine. So the standing count decides what is reported and a
  separate birth budget decides when a run has done enough work. Swept with
  `--churn`, C's rank climbs 38 → 62 → 68 over 256 → 1024 → 4096 births per token
  and then holds at 68 through 65536, while every other grammar is already final
  at 1024 - so the default buys the whole answer at 4096, for 4.4 seconds instead
  of 49.

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

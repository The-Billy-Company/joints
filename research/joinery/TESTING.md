# Joinery - how the claim dies

Every rung states a premise, names the measurement, and names the number that
kills it. They are ordered so the cheapest falsifier runs first. No rung may be
skipped because a later one looks more interesting.

House rule, inherited from irregex's automata dossier: **a claim is not credible
until it has been timed against bytes, and you must price both halves of every
exchange.** An `O(log n)` splice that allocates is not automatically better than
an `O(n)` walk that does not.

Second house rule, learned the hard way and enforced by `tool/stamp.py`: **no
number appears here without the instrument that took it.** Every instrument runs
one binary, prints that binary's commit, and says so if it was told which binary
to use, if the tree was newer than it, or if the tree moved while it ran. Nine
instruments have been wrong at some point in this document's life; eight of them
flattered us and one did the opposite.

Third house rule, and the newest: **two numbers are only a comparison if each
arm owned its own binary, its own folio cache, and its own oracle seat.** One
command sets all three, and a before/after pair that skips it has read one arm
twice - always agreeing with itself, which is why nobody notices:

```sh
eval "$(python3 tool/pin.py arm before)"   # JOINTS_BIN + JOINTS_WORK + JOINTS_LANE
python3 tool/standing.py --json > before.json
eval "$(python3 tool/pin.py arm after)"
python3 tool/standing.py --against=before.json   # every cell, and what the runs differed in
python3 tool/standing.py --twice=3               # is this row stable at all?
```

`--twice=N` re-runs the board as **N separate processes**. That is the whole
point of it and the part people get wrong: a loop inside one interpreter keeps
the folio cache decisions, the `accepts` memo and the oracle identity from the
first pass, so it re-prints the first answer N times and calls the agreement
stability. It cannot fail. Only a fresh process re-asks every question.

`--against` prints what moved **and what the two runs differed in**, separately,
so a column that moved because the oracle moved is never read as a board that
wanders. Full recipe in [`tool/README.md`](../../tool/README.md#pinpy---a-path-is-not-a-version).

Fourth house rule, and it is about the **clock** rather than the workspace:
**pin the control after the arm.** An arm pinned first ages while you work, and
it ages in the direction of whatever your siblings shipped meanwhile - so the
gap between your two pins is not your change, it is your change plus theirs.

A lane pinned its baseline, worked for eight minutes, pinned its arm, and read
`latex -1,185`. The lex lane had landed a latex fix inside those eight minutes.
Each arm had its own binary, its own `JOINTS_WORK` and its own seat; the folio
shas were checked and matched. **The third house rule is fully satisfied by that
run and does not cover this**, because nothing wrote to anything being compared -
the tree simply moved between the two pins, and a work directory per arm cannot
see a tree it does not contain.

```sh
# ... make your change ...
eval "$(python3 tool/pin.py arm after)"     # the ARM first, while the tree is yours
python3 tool/standing.py --json > after.json
# ... revert your change ...
eval "$(python3 tool/pin.py arm before)"    # the CONTROL last, minutes younger
python3 tool/standing.py --against=after.json
python3 tool/still.py against after before --mine src/kernel/lex/latex.zig
```

That last line is the check, and it is the one that does not depend on you
remembering the order. `pin.py build` records a **per-file manifest** of the tree
it built from, so `still against` can say not merely *your two arms differ* -
which is true of every before/after all day - but **in which files**, against the
ones you claim. A file you did not name is somebody else's afternoon in your
number.

And the falsifier that found this one is worth stealing: **pin the reverted tree
last and diff it against your own baseline.** The subject is byte-identical on
both sides, so the board must come back inert; if it does not, the apparatus is
indicting itself and no arm you have taken means anything yet. `still against A B
--null` is that comparison - it inverts the binary rule, so two arms running one
binary is the requirement rather than the defect.

Fifth house rule, and it is about **which artifact you are looking at** rather
than which world it came from: **folio identity clears a press change and nothing
else. For lex, quire or runtime work the control is your own rows removed from
today's tree.**

A folio is the *pressed table*. A press change moves folios, so "these 12 moved
and the other 18 held" is a real statement about collateral damage. A `Troupe`
seating, a scanner fix, a parse-loop change - none of those can move a pressed
table at all, so "all 30 folios byte-identical" is true, verifiable, mints
correctly, passes every ticket, and means **nothing whatsoever**. A lane offered
exactly that as proof its seating broke no other grammar, then noticed latex's
folio is identical between the arm scoring 108 and the arm scoring 5,246. An
earlier lane had already shipped the same clearance about a scanner fix.

The control for those is an **isolation arm**: today's tree with *your rows
deleted and the plumbing left in*. Not a scratch tree pinned at some moment -
that is strictly worse, because it freezes out your siblings' edits too and you
are back to attributing their afternoon to yourself. The isolation arm shares the
whole world including the six files that landed while you worked, and differs
from it by exactly the change under test.

```sh
eval "$(python3 tool/pin.py arm after)"     # today's tree, your rows in
python3 tool/standing.py --json > after.json
# ... delete ONLY your rows; leave every seam, signature and call site ...
eval "$(python3 tool/pin.py arm alone)"     # today's tree, your rows out
python3 tool/standing.py --against=after.json
python3 tool/still.py against after alone --mine src/kernel/lex/troupe.zig
```

The lane that built the first one found nine grammars moving in its `before`/
`after` pair and **none of them its own**; against the isolation arm exactly two
moved and no third moved a byte.

That last line is also how you know your isolation arm is one. The isolation arm
is *defined* as the arm differing from today by only your rows, and `--mine` is
exactly that predicate - so a botched isolation that took out a shared seam on
the way past fails at the file, by name, before it prints a number. The rule that
was folklore is now the thing the gate already checked.

And `still against` now refuses the vacuous clearance directly, from the other
side of the same shape as `--null`. If every folio is byte-identical across two
arms whose **binaries differ**, that evidence never observed your change, and an
instrument that did not respond to the treatment cannot clear it - so it reports
`vacuous` and exits 1 rather than passing in a silence somebody will read as
agreement. If identity genuinely is your result - a refactor claiming
equivalence, not absence of collateral - say `--inert` and it holds.

Sixth house rule, and it is the fourth one made **automatic**: **a board carries
the tree it read, and two boards read from different trees are not a
comparison.** Nothing to remember, and the refusal exits 4.

`--twice` asks *is this binary's board reproducible*. It does not ask *is this
board's tree the tree I think it is*, and those diverge here. A lane took two
controls four minutes apart, ran `--twice` on each, got 930 numbers identical
across three separate processes both times - and the two controls **disagreed by
63 standing points on scala**. A third, ten minutes later, agreed with the
first. All three passed every check this document had; any one quoted alone was
a different claim about the corpus. The failure mode is not noise, it is
**confident timestamping of a moment presented as a property of a change**.

So `standing.py` now takes a `still` witness on every run and prints it, `--json`
carries it, and `--against`/`--twice` compare the two trees before they compare
the numbers. The three controls above are judged by the gate today:

```sh
python3 tool/standing.py --against=before.json --mine=src/press/,src/kernel/lex/x.zig
```

```
before.json vs this tree: REFUSE - subject: the two arms were built from trees
    differing in 1 file(s), 1 of which you have not claimed and could move the binary
    src/kernel/quire/gather.zig  NOT YOURS
```

That one file is what separated the two controls' *trees*. **The board could not
have said it and `pin.py`'s manifest always could** - the rule is just that the
manifest now rides the measurement instead of waiting to be asked.

And it is worth knowing what it did *not* say, because the difference is the
whole point of recording four fields instead of one. Re-boarded today, each in
its own folio cache and its own oracle seat, those two binaries agree on scala
**to the byte** and differ in 3 of 930 numbers, none of them scala; all thirty
folios are byte-identical. So the tree difference is real, the refusal is
correct - and the 63 points came from somewhere else. The witness says where to
look next: two of my own board runs eighteen seconds apart carry different
`live` digests, because a lane landed something while I measured. A board that
cannot name its inputs cannot tell those two stories apart, and neither could
the lane that hit it.

Three lines to know:

- **`--mine` takes a file, a directory, or a glob.** A lane's change is
  `src/press/`, not one path, and a flag that makes you enumerate fourteen files
  is a flag whose list stays empty - after which everything is unclaimed and
  everything refuses. Claiming a directory is the normal case.
- **An unclaimed `*_test.zig` is a note, not a refusal.** No product binary is
  built from one, and with ten lanes editing tests continuously a gate that fired
  on those would fire most of the time. The refusal is for files that could have
  moved a number.
- **A board saved before this carries no witness and still diffs**, with a note
  saying the tree question could not be asked. Nothing that already exists on
  disk breaks; the gate switches itself on as boards are saved.

And the same witness makes the *arms* judgeable without a board at all, which is
the cheap check to run before you trust a pair of pins:

```sh
eval "$(python3 tool/pin.py arm before)"; python3 tool/still.py witness before
eval "$(python3 tool/pin.py arm after)";  python3 tool/still.py witness after
python3 tool/still.py against before after --mine src/kernel/lex/latex.zig
```

## Where it stands

| | | instrument |
|---|---:|---|
| grammars pressed | 30 | `census.py` |
| byte-identical to real tree-sitter | **8** | `differential.py` · `breadth.py` |
| parse whole, one root over every byte | 9 of 30 | `census.py` |
| corpus bytes covered | **100.0%** (was 71.6%) | `census.py` |
| all thirty, bytes covered | 96.4% | `census.py` |
| broken files where code after the break still gets nodes | **25 of 25** (was 0) | `recover.py` |
| held-out findings nobody has explained | 669 | `breadth.py` |
| of those, with a named cause and a lane | **669** | this document |
| axes measured against real tree-sitter | 6 of 6 | `bench.py` |
| of those, axes we win | **3** (artifact · install · press) | `bench.py` |
| of those, axes we lose | 2 (throughput · incremental) | `bench.py` |
| worst single row | **incremental typescript, 153.8x** (was 14,746x, pre-`torn`) | `bench.py` |
| grammars whose parse is superlinear in what it has already read | **3 of 5** | `order.py` |
| distinct walls behind every mending grammar, all thirty | **315** (was 24), of which 58 are the peel restarting -> **257** real | `walls.py` |
| ...collapsed to distinct terminals, in five families | **120** | `walls.py board` |
| walls whose family nothing on the board claims | **0**, gated | `walls.py gate` |
| real-code javascript, after the scanner lane's mask, **on the folio path, which is what ships** | **407 ns/B**, was 42,917 | `bench.report.md` |
| the two paths, priced side by side on five grammars | agree within noise; the folio is now the **faster** one | `bench.report.md` |
| every incremental row, which needs **two** labels | folio path, and `@98%` **relative** to each file - never an absolute byte | `bench.report.md` |
| the wall board on both paths, nine grammars | **identical, wall for wall** - and now gated | `walls/README.md` |

Two of those moved because the parser got better, and two moved because an
instrument stopped lying. The sections below keep the old number beside the new
one in every case, because a reader who remembers 71.6% is owed the reason it
moved and the fact that no parser code was involved.

The head-to-head is new and it is not flattering. It has its own dossier at
[`bench.report.md`](bench.report.md); the short version is below under
[Against tree-sitter](#against-tree-sitter---six-axes-three-wins-two-losses-and-one-unmeasurable).

**One number in that dossier has already been retracted, and it was mine.** The
first draft blamed `_automatic_semicolon` on the strength of a newline ablation
that held the byte count constant and did not notice it had turned 99.96% of the
file into a line comment. A twelfth instrument, and the twelfth to flatter a
story rather than test it. The real cause is a quadratic scan, attributed by
profile and by a witness that holds bytes **and** nodes constant; the retraction
is kept on the page beside it for the same reason the 71.6% is.

That witness is no longer two files in `/tmp`. It is committed at
[`research/joinery/order/`](order/README.md) with the construction that makes it,
and `python3 tool/order.py` holds all five grammars to a **1.6x** ceiling on the
ratio between the same bytes and the same nodes in a different order. It is red
today at 2.8x to 4.1x, which is what a gate written before a fix is supposed to
be.

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

Run it yourself: `joints survey <grammar.json> <file>...`, which reports every
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
none residual**. Read the classification yourself with `joints grammar
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
with `joints survey upstream/grammars/<lang>.json research/joinery/corpus/<file>`.

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
defaults everywhere.

I widened the corpus first. Until now the eleven files had zero tokens that
crossed a newline between them, which for a package whose weakness is lexical
meant the corpus could not see the thing that is broken. Every file now carries a
block comment and a multi-line string in whatever form its language really has;
the corpus README's fourth column says which. **That moved most of the rows
below**, so both readings are here rather than only the flattering one. The
state counts and the residue did not move, and could not have: those are the
press talking, not the files. b is the old corpus,
a is the widened one, both taken minutes apart against **one** binary
(`62bdf90aa`, tree `985f14d12`), which matters more than it sounds like: an
earlier draft of this table was measured against a binary built before a lexer
fix landed, and every number in it was wrong in the parser's favour.

| grammar | states | p99 rank b/a | residue b/a | chains held b/a | refused b/a | where it stops now |
|---|---|---|---|---|---|---|
| json | 44 | 42/54 | 2/2 | 8/8 -> 8/8 | 0/0 | read to the end |
| ruby | 5168 | 24/6 | 1/1 | 6/8 -> 8/8 | 2/0 | stopped early, held every chain it could run |
| bash | 8254 | 14/7 | 1/1 | 5/8 -> 7/8 | 3/1 | 1 refused at a ceiling |
| cpp | 7275 | 30/19 | 1/1 | 4/8 -> 5/8 | 4/3 | 3 refused at a ceiling |
| javascript | 3144 | 13/20 | 1/1 | 5/8 -> 5/8 | 3/3 | 3 refused at a ceiling |
| python | 3054 | 66/19 | 1/1 | 6/8 -> 5/8 | 2/3 | 3 refused at a ceiling |
| go | 2025 | 24/16 | 1/1 | 4/8 -> 4/8 | 4/4 | 4 refused at a ceiling |
| java | 3298 | 17/51 | 1/1 | 4/8 -> 4/8 | 4/4 | 4 refused at a ceiling |
| typescript | 11789 | 23/24 | 1/1 | 4/8 -> 4/8 | 4/4 | 4 refused at a ceiling |
| c | 2946 | 64/66 | 1/1 | 3/8 -> 3/8 | 5/5 | 5 refused at a ceiling |
| rust | 9590 | 91/- | 1/- | 3/8 -> 0/0 | 5/0 | nothing measured; blind to `_block_comment_content` |

**The three invariants held on both corpora: zero residual conflicts, nothing
disagreed anywhere, and the residue never got past two.** That is the sharper
falsifier from the json section, and the widened corpus did not dent it. Where a
chain ran at all, composition alone singled out the branch at every step, and
json's `residue ≤ 2` is still the one segmentation needing a second pairing. The
refusals sort by cut size and by nothing else, and every byte span holds on every
grammar. The count fell from 36 to 27: rust dropping out is five of that, ruby
and bash between them are four more, and python is the one that went the other
way.

**A number moving here is not the parser moving.** The state counts are the same
in both columns because they have to be - same grammars, same press - and only
the files differ. Read the b column as what the old corpus was able to ask, and
the a column as what a corpus with a block comment in it asks instead. Some rows
got better at it: ruby went from six chains to all eight, because a heredoc
gives rung 1 more token to work with than the file used to contain.

### Eight grammars are byte-identical to tree-sitter

Not close on eight languages; **identical on eight languages**, node for node,
name for name, field for field, span for span, against the real tree-sitter CLI
rather than against a description of it.

| grammar | nodes, both sides | what was parsed |
|---|---:|---|
| lua | 973 | `uri.lua` from neovim/neovim, 3,707 B |
| css | 795 | `normalize.css` from necolas/normalize.css, 6,138 B |
| embedded-template | 506 | `application.html.erb` from discourse/discourse, 6,006 B |
| rust | 490 | `research/joinery/corpus/ledger.rs`, the whole program |
| typescript | 442 | `research/joinery/corpus/ledger.ts`, the whole program |
| json | 397 | `research/joinery/corpus/ledger.json`, the whole file |
| javascript | 324 | `research/joinery/corpus/ledger.js`, the whole program |
| java | 306 | `research/joinery/corpus/Ledger.java`, the whole program |

Taken by `differential.py run` on the corpus five and by `breadth.py run` on the
held-out three, both on `joints f6a34cd7c`.

**It said four for several rounds, and three of the four missing rows were
already true.** css, embedded-template and lua were byte-exact and nobody knew,
because the sweep that would have shown it was the held-out one, and that sweep
had its own copy of the scanner walk - so it never laid the external scanners
down and never built an oracle to compare against. A duplicated instrument hid a
win. rust is a real change: it was the widening's one casualty, blind at byte 0
to `_block_comment_content`, and it now parses `ledger.rs` whole.

**toml is the near miss, and it is worth naming rather than rounding up.** 731
nodes on both sides, one root, whole file - and one finding, an extent rather
than a name. That is the extras predicate, below; a grammar can be node-for-node
identical and still not be byte-exact, so it is not on this list.

Three of the corpus rows are a whole real program in the widened corpus, which
means each contains a block comment and a multi-line string that the eleven
files did not contain a month ago. Eighteen more span fixtures in
`research/joinery/spans/` compare byte-exact too, and json's eight-fixture gate
is `no differences at all`.

**One qualifier, and it is not small.** Every statement in `ledger.js` and
`ledger.ts` ends in an explicit `;`. JavaScript does not require one - the spec
inserts it at a newline, and tree-sitter's scanner emits that insertion as a
zero-width `_automatic_semicolon`, the first of the eight externals javascript
declares. We are blind to it, so `const a = 1` on its own line stops us at byte
12, exactly where the missing `;` would go, while tree-sitter reads two clean
`lexical_declaration` nodes. So the claim is **byte-exact on
semicolon-terminated JavaScript**, and a large fraction of real-world JS omits
them by house style. Four reduced probes are kept at `research/joinery/valid/`
and swept by `recover.py --valid`; the terminal is routed to the externals lane,
where it wants a zero-width external, a shape none of the others have.

Reproduce with `python3 tool/differential.py run`;
every number here is identical on `joints 1a9a951fa` (tree `c0cdbde69`) and on
`db3e41054` (tree `211abb346`), a lane landing apart, corpus as committed. Two
tree states agreeing is the corroboration; one is an anecdote.

**Where the other six stop, and who owns the byte.** This map is worth more
than the totals, because every row names a lane rather than a mood.

| grammar | first stops at | the byte it stops on | why, and whose |
|---|---:|---|---|
| c | 1354 | `,` in `fputs(BANNER, stdout)` | press: a parse state, not a lexeme |
| cpp | 690 | `"` in `"seed" + std::to_string(i)` | press; it cleared the raw string it used to die on at 486 |
| bash | 565 | `^-?[0-9]+$` after `=~` | scanner: bash's bare-regex external. **Was 408, `<<'RECEIPT'`** - the heredoc wall fell, and the wall behind it is the next row of the same lane |
| go | 535 | `{` of `&Ledger{tags: ...}` | press: `composite_literal` carries a static `prec(-1)`, so the cell resolved and `settle.Forks` has no second action to give back. On `b50f6ad84` the `{` stopped lexing at all - same byte, worse verdict |
| python | 482 | `:` of `seed: list[int] \| None` | press: an annotated parameter. Same verdict change on `b50f6ad84` |
| ruby | 357 | `<<~RECEIPT` | scanner: heredoc, 1 of 30 externals |

**rust was the seventh row and is now byte-exact**, so it moved up to the table
above. It read 0 bytes for the whole of the widened-corpus era, blind at `/*` on
line 1 to `_block_comment_content`, which is external because rust nests block
comments and no regex can match that. It parses `ledger.rs` whole.

Two buckets, and the sizes are the useful part: **two walls are external
scanners, four are the press.** Declaring externals is not itself the wall -
javascript declares eight, typescript ten and rust eleven, and all three read to
the end - the wall is a needed external actually appearing in the bytes.

**A wall hides the wall behind it, and bash is the worked example.** Two lanes
disagreed about bash: this map called it a scanner, and the frayed lane proved
its fourteen `(?:\s+)` states were uncuttable and routed the wall to `offer()`
admitting on shift-reachability. Both are right, and the order settles it. Take
`ledger.sh`, replace the heredoc with a plain string and change nothing else:

```
ledger.sh          stray byte at 408          <<'RECEIPT', heredoc_start, an external
same file, no heredoc  unexpected (?:\s+) at 416 in state 1641    the offer() wall
```

Eight bytes apart. The heredoc is genuinely first, so the scanner attribution
is what an instrument can see; `offer()` is the wall waiting behind it, and no
corpus measurement will ever name it while the heredoc stands. Read every row of
this map that way - it names the **first** wall, not the only one.

**The heredoc has since fallen, and the prediction was half right.** bash now
reads to 565 rather than 408, so the probe above no longer needs the fixture; it
is the file. What stands there is not the `(?:\s+)` state the probe found but
bash's bare-regex external at `=~`, which is the same lane one row later.
`offer()` is still behind that. Two walls turned out to be at least three, which
is what "the first wall, not the only one" was warning about.

**That warning has since been turned into a number**, and it is far smaller than
this section feared: twenty grammars wall, and between all of them the tail
holds **24 distinct walls**, eighteen of them exactly one deep. See
[How deep is the tail](#how-deep-is-the-tail-twenty-four-walls-and-eighteen-grammars-are-one-wall-deep).

**And a `stray byte` does not always mean a lexer.** It means no terminal was
produced at that offset, which happens both when nothing *could* lex those bytes
and when the terminal exists but the state never offered it. Those are opposite
findings. C separates them in five lines, and C declares **zero** externals, so
nothing lexical is available to blame:

| probe | verdict |
|---|---|
| `const char* s = "x";` | accepted |
| `void g(void) { const char* s = "x"; }` | accepted |
| `const char* g(void) { return "x"; }` | accepted |
| `void g(void) { f(y); }` | accepted |
| `void g(void) { f("x"); }` | **stray byte at 17** |
| `void g(void) { f(1); }` | **stray byte at 17** |
| `void g(void) { f('x'); }` | **stray byte at 17** |

A string lexes in an initializer, in an assignment and in a return. As a call
argument no literal lexes at all, while an identifier does. The terminal is not
missing; the state after `f(` does not offer it. That is `offer()` again, wearing
a lexer's clothes, and it is why the census below counts twenty `lexical` walls
that cannot all be lexers.

### The reach census - all thirty grammars, one table

The eleven have had a reach table since the beginning; the nineteen held-out
grammars never had one, because until the oracle reader learned to read a
multi-line token there was nothing to put in it. `python3 tool/census.py` asks
all thirty the same question and sorts the answers by what stopped each one.

| | grammars | bytes |
|---|---:|---:|
| parse whole, one root over every byte | **5** of 30 | |
| stop mid-file | 25 of 30 | |
| reached | | **31,980 of 526,798 - 6.1%** |

The five whole are json, java, javascript, typescript **and
`embedded-template`**, which is held-out and had never been counted. The walls
sort into four kinds, and the kind is read off the verdict rather than assigned
by hand:

| wall | `b81f8337f` | `b50f6ad84` | what the verdict says |
|---|---:|---:|---|
| `lexical` | 20 | 24 | `stray byte at N` - no terminal was produced at N |
| `whole` | 5 | 5 | accepted |
| `state` | 4 | 0 | `unexpected T at N in state S` - T lexed and the state refused it |
| `other` | 1 | 1 | yaml, which has no lexable terminal at all |

**Two builds eighteen minutes apart, and every reach byte is identical while
four walls changed what they say.** go's `{` at 535, python's `:` at 482,
latex's `command_name` at 3,057 and zig's `{` at 4,101 each moved from
`unexpected T in state S` to `stray byte at` the same offset. A terminal that
used to lex and be refused now does not lex. Reach did not move by a byte, so
nothing here got worse at parsing; what got worse is the diagnosis, and it is
the difference between a wall that names its state and one that does not. That
belongs to whoever owns the lexer this hour. **Nothing in this table is safe to
quote without its stamp**, which is the whole argument for having one.

**Eighteen of the twenty-four lexical walls are in a grammar declaring externals
we cannot run**, and that is the one missing feature that would move the most
bytes: rust, ocaml, haskell, scala, julia, kotlin, lua, elixir, php and markdown
all stop at or near byte 0 for it. The rest are the `offer()` family above, and
c's probe is the proof the two kinds are told apart only by experiment.

The big files are the honest part of the 6.1%: php is 67 KB and reaches 17
bytes, html 72 KB and reaches 18, verilog 94 KB and reaches 3,057. A percentage
of bytes flatters nothing here.

**One row has since moved, and only one number with it.** php's byte-17 wall
fell on `684d6e04b`, taking it from 17 bytes to 39.6% of 67,845 and the corpus
total from 6.1% to **11.2%**. Every other figure in the table above is
unchanged: still 5 parse whole, 25 stop mid-file, 18 lexical walls, 6 state
walls, 1 other. That is what a large byte share bought by one grammar looks
like, and it is the argument for reading the wall column rather than the
percentage.

### The census was wrong about us, by 28 points

Every number in the section above is superseded, and the correction runs the
wrong way from the usual one: **we had been under-reporting our own reach.**

| | corpus bytes covered | |
|---|---:|---|
| the old rule | 9,782 of 13,656 | **71.6%** |
| the rule now | 13,652 of 13,656 | **100.0%** |

Both taken by `census.py` in one run on one binary, so nothing about the parser
is in that gap. The old rule read the verdict `mended at N` as "stopped at N"
and credited the file with `N` bytes. But a mended parse does not stop; it names
its first stop and keeps reading, and the forest it hands back covers the rest.
So the rule was **reporting the parses that read the most as the ones that read
least** - the further past its first stop a parse got, the worse it scored.

That rule had been copied into four instruments and fixed in one of them. Only
`recover.py` knew what `mended` meant, and the fix that taught it never reached
the other three, so the census and the sweeps kept quoting the defect for
rounds. The six copies are now one, in `stamp.py`, and `sole.py` fails if a
seventh appears.

**Read the covered number with its qualifier attached.** Of the 507,847 bytes
now counted across all thirty, 482,653 are forest over mended input: covered,
walked, given nodes, and **not vouched for as the right nodes**. `census.py`
prints that split on its own line for exactly this reason. Byte-exactness is the
differential's question, and the answer to that one is eight grammars.

| | grammars | bytes |
|---|---:|---:|
| parse whole, one root over every byte | **9** of 30 | |
| hit a wall and read on (mended) | 20 of 30 | |
| no lexable terminal anywhere | 1 of 30 | |
| covered, all thirty | | **507,847 of 526,798 - 96.4%** |
| covered, the corpus eleven | | **13,652 of 13,656 - 100.0%** |

The nine whole are json, java, javascript, typescript, rust, css,
embedded-template, lua and toml. **yaml is the only grammar that reaches
nothing**, and it is not a wall in the sense the rest of this document uses the
word: no terminal is producible anywhere in the file, so there is no first byte
to name. Every other grammar in the set now reads to the last byte or to within
one of it.

Taken by `census.py` on `joints f6a34cd7c`, whose stamp reads `TOLD` and
`STALE` - a private binary, deliberately, so the eight other lanes rebuilding
this tree could not move the floor under a three-minute measurement. The corpus
row was then re-taken an hour later on the tree's own `4d0d74316`, which reads
13,653 of 13,656: **one byte apart on two binaries, both 100.0%**. Two tree
states agreeing is the corroboration; one is an anecdote.

### How deep is the tail? 315 walls, and the first answer I gave was wrong

**Retracted: "24 distinct walls, eighteen grammars one wall deep."** That number
was an artifact of my own instrument and it survived about two hours. The peel
stepped past `reach` - where the parse *got to* - rather than past the byte the
verdict *names*. For a mending parse those are opposite ends of the file:
haskell says `unexpected . at 681 in state 7, 94 roots, mended 4940` over 34,240
bytes, so the peel read `34,239`, stepped past the end, and terminated after one
round having found exactly one wall. Every grammar whose wall was a refused
token got the same treatment, which is why almost every row came back "1" and
why the total looked so encouraging.

The tell was there and I walked past it: the two lexical rows peeled properly -
julia 5, markdown 79 - because `stray` returned the named byte while the state
path returned reach. One code path in the same function using the right number
and the other using the wrong one, producing a result that flattered. That is
the thirteenth instrument in this document to do it, and the first one I built
knowing the pattern.

`stamp.Outcome` now carries `at` - the byte the verdict names - beside `reach`,
with the distinction written down where the next caller will read it, because
this is the third time these two have been confused in this project.

**The corrected measurement.** `python3 tool/walls.py --depth 400`:

| | |
|---|---:|
| grammars that hit a wall | 20 of 30 |
| **distinct (terminal, state) walls** | **315** |
| ...and those collapse to distinct terminals | **120** |
| ...in five families | **5** |
| deepest grammar | kotlin, at 52 |
| still walled at the 400-round ceiling | 8 |

So the tail is an order of magnitude larger than the retracted number, and it is
**a floor**, not a total: eight grammars were still finding new walls when the
depth ceiling stopped them.

**What survives the retraction is the shape, and it is the part worth having.**
Mends were still counting volume rather than depth - haskell's 4,940 mends are
**10** distinct walls, verilog's 1,652 are **22**, julia's 4,749 are **44**. A
94x-to-494x ratio between mends and distinct walls is the same finding the first
pass made, with a denominator that is no longer fabricated.

**And the families route.** Grouping the 315 by the shape of the terminal rather
than by grammar gives five buckets and three lanes
([the full board](walls/README.md), rendered by `walls.py board`):

| family | lane | walls | shapes | grammars |
|---|---|---:|---:|---:|
| permissive body pattern | **scanner** | 105 | 22 | 16 |
| bracket refused | **weave** | 63 | 8 | 14 |
| named terminal / keyword | *unassigned* | 59 | 45 | 12 |
| separator refused | **press** | 55 | 12 | 12 |
| unrunnable external | **scanner** | 33 | 33 | 5 |

The largest family is **the same defect as the largest cost**. A permissive body
pattern is exactly the shape the scanner lane's voice analysis describes - a
member that matches a run of anything-but-a-delimiter, survives to end-of-file,
and drags its whole voice with it - and it accounts for 105 of the 315 walls
across sixteen grammars. `(?:[^\\"\n]+)` alone stands in c, cpp, verilog and
zig; scala's `xml_text` is 28 walls by itself. That the throughput defect and
the correctness tail turn out to be one family was not visible from either side
alone.

**The brackets are weave's, and `offer()` now has three witnesses rather than
one.** 63 walls across fourteen grammars are an opener or closer the state
refused. Narrowing to the exact terminal zig was routed on:

```
go     { in state 188
ocaml  { in state 239
zig    { in state 715
```

A refused `{` in one grammar makes a predicate *plausible*; the same terminal
refused at a block opener in three unrelated grammars makes it **testable** -
a fix can be checked against two grammars it was not designed on. The wider
family is `)` at 26 walls over eight grammars and `}` at 17 over ten, which is
either the same predicate or its neighbour and is worth checking before the
narrow fix is called done.

**59 walls are unassigned and stay that way.** Keywords and named terminals -
verilog's `begin`/`end`/`endcase`, sql's nine `keyword_*`, latex's
`\documentclass` - have no shape that routes them, so the classifier prints them
as residue rather than guessing. That is the honest size of what shape alone
cannot answer.

#### 315 is a floor, and the count is the wrong thing to quote

The peel resumes from a clean start, so it begins each round in state 0 rather
than in the state the loop had accumulated - which means a wall that only exists
after four thousand lines cannot be reached at all. That biases in one
direction, so the question is how far. `python3 tool/walls.py warm` answers it
by never restarting: it parses the **whole file** every round and blanks the
offending byte, so the prefix stays real and the state is the one the parser
would actually be in.

| grammar | rounds | cold | warm | **warm-only** | last new at | quiet since | per 100 |
|---|---:|---:|---:|---:|---:|---:|---:|
| haskell | 300 | 9 | 10 | **9** | 219 | 81 | 1.3 |
| julia | 300 | 35 | 36 | **11** | 215 | 85 | 2.7 |
| verilog | 300 | 19 | 13 | **11** | 171 | 129 | 2.0 |

Both peels in that run are at depth 300, so the `cold` column sits below the
survey's 400-round figures (haskell 10, julia 44, verilog 22). They have to be
compared at the same depth or the diff measures the ceiling instead of the
resume.

**It is a floor, decisively.** 31 walls over three grammars exist only in
accumulated context - nine of haskell's ten, and every one of them in states 7
and 48; all eleven of julia's in a single state 45. So 315 undercounts, and it
will keep undercounting for as long as anyone keeps peeling: new walls were
still arriving at round 219 of 300.

**But the arrival rate is low and falling**, 1.3 to 2.7 per hundred rounds in
the back half, with 81 to 129 quiet rounds at the end of each run. That is not
saturation and it is not an explosion either. It is the third world, which
neither of the two we set out to distinguish quite describes:

> **Every one of the 31 warm-only walls lands in a family that already existed.**
> 16 named terminals, 8 separators, 4 permissive body patterns, 3 brackets. No
> new family appeared, and the states repeat - one state refusing eleven
> different terminals is one broken state, not eleven.

So the honest instruction is: **quote the families and the rate, not the total.**
The total is a floor that grows with how long you peel and will never be a
number I can defend. The five families are closed under an extra 900 rounds of
peeling in the hardest three grammars, which is the property that makes the
board a work list rather than a running tally. If a sixth family ever appears,
that is the finding - and `python3 tool/walls.py gate` is now what goes red when
one does. Fixed roster of nine grammars chosen for family spread, fixed 40
rounds, both peels, 44 seconds, in CI. It gates **closure, never the count**,
because the count is a floor and a longer budget would fail it for nothing.

The gate earned its place before it shipped. Its first run failed on three walls
belonging to no family - `:=` in go and `@` in kotlin - which were not a sixth
family at all but a hole in the classifier: separators were an *enumeration* of
the operators someone had already seen. That is now a predicate ("made only of
punctuation, and not a bracket or a quote"), which needs no new row when a
grammar spells assignment differently. Four adverse shapes (`end task`, `0x`,
`<<EOF>>`, `3quarters`) still return no family, so the check remains capable of
failing - a total classifier could never have reported the surprise it exists to
catch.

#### 58 of the 315 are the peel restarting, not the parser failing

Asked once more whether a number was a floor or a ceiling, and it was neither -
it was inflated. **18% of the walls sit in state 0**, the start state, which the
cold peel enters on every round after the first while holding the middle of a
construct. A sql start state refusing `end`, `else` and `or` is correct
behaviour, not a defect.

Two independent checks agree: **no grammar's first wall is in state 0** - round
one reads the whole file from byte 0 and is the only round that could honestly
land there - and **the warm peel, which never restarts, produces none at all**,
against nine of haskell's ten from the cold peel.

So the defensible figure is **257**, and haskell really is one wall deep - which
the retracted first pass said for entirely the wrong reason. sql loses 22 of its
31. This is the third bias the floor-or-ceiling question has found, and the
first that made the tree look *worse* than it is, which is the direction that
never gets caught by suspicion alone.

#### The retracted first pass, kept for the reason the 71.6% is

The first pass reported **24 distinct walls, eighteen grammars one wall deep,
deepest julia at 5**, and concluded the tail was bounded and nearly flat. It is
kept on the page rather than deleted, for the same reason the 71.6% is: a reader
who saw that number is owed the reason it moved, and the reason is not that the
parser changed. Nothing in `src/` moved between the two measurements. What moved
is that the peel started stepping past the right byte.

The retracted table's per-grammar claims map onto the corrected ones directly -
haskell 1 -> **10**, verilog 1 -> **22**, julia 5 -> **44**, kotlin 1 -> **52**,
scala 1 -> **43**, elixir 1 -> **32**, go 1 -> **7**. Only the two lexical rows
were right the first time, and they were right by accident.

One claim from the first pass does survive intact, because it came from the
grammar report rather than from the peel: zig's `{` in state 715 is corroborated
by the tree's own suite, which prints `press on { in state 715` from
`src/press/census_test.zig` on a full `zig build test` - a different instrument,
a different code path, the same state number.

### yaml is not a wall, it is a grammar that never starts

yaml is the only grammar that reaches nothing, and printing it as a wall with
a lower bound - which is what the survey does - undersells what it actually
needs. The reason is categorical rather than positional, and
`joints grammar upstream/grammars/yaml.json` says it outright:

```
symbols      328  (113 terminal, 215 nonterminal)
terminals    0 literal, 0 regex, 113 external
lr(0) states 910  ...  0 RESIDUAL (0 s/r, 0 r/r)
```

**Every one of its 113 terminals is an external.** There is no first byte to
name because there is no terminal producible at any byte, so "reach 0%" is not
a parse that stopped early - it is a lexer that never starts. And the same
report is the cleanest evidence in the project that the two halves are
independent: the press builds yaml's table to **zero residual conflicts** over
910 states while the scanner has nothing at all to hand it. The press is not
what is missing here.

It belongs to the scanner lane, as the extreme case of the blind-external
stand-in machinery rather than as a thirtieth wall: every other grammar has some
terminals to lex and loses a few to externals, and yaml is the limit point where
the stand-in has nothing whatsoever to stand on. Whatever bounds the general
case has to answer for this one, so it is worth keeping as the acceptance test
rather than as a footnote - a stand-in that gets yaml to a non-zero reach has
been proven to work without any real terminals to lean on.

**What the peel is, and is not.** Resuming parses the remaining bytes from a
clean start, so each round begins in state 0 rather than in the state the
product loop had actually accumulated. A peeled wall is therefore a wall this
grammar hits reading that text *cold* - real and reproducible, and not
guaranteed to be the identical wall the mending loop met at that byte. It
enumerates the tail's distinct *difficulties*, which is the question asked; it
can name a wall the loop would have mended past. Doing better needs the loop to
report its own stops, which is `src/`, which is another lane's. Every row says
how it was obtained, and the one row that did not finish - yaml, which has no
lexable terminal anywhere - is printed as a lower bound rather than a zero.

Taken on `joints 1e91ef9c8`, built from `95b3f4ee5` over a tree at
`3d980e308+43`. The scanner lane rebuilt three times while this was being
measured; nothing above is a duration, so none of it moved.

### The held-out nineteen: 669 findings, and not one of them is unattributed

The held-out set exists to answer whether the eleven grammars this was built
against were being fitted rather than parsed. `breadth.py run` presses all
nineteen, lays down each one's external scanners, builds tree-sitter's own
parser from the same pinned sources, and compares. Nothing in it has ever been
used to fix anything.

| | |
|---|---:|
| pressed and parsed | **19** of 19 |
| compared against a real tree-sitter oracle | 16 |
| refused an oracle, and said why | 3 |
| byte-identical | 3 |
| findings nobody has explained | **669** |

**The three refusals are honest ones**, and each names its reason rather than
disappearing: sql and verilog have no oracle we can build from their pinned
sources, and yaml produces no lexable terminal at all, so there is nothing to
compare. A skipped row prints `skipped` and keeps its reach.

**And the 669 is not a number, it is three causes.** Every finding is now
attributed to a mechanism and a lane, which is worth more than the total,
because a board that reads `669` and a board that reads `662 external · 6
offer() · 1 extras` say different things about what to build next:

| grammar | findings | externals declared | cause | lane |
|---|---:|---:|---|---|
| elixir | 317 | 26 | `_newline_before_do` | scanner |
| html | 209 | 8 | `_start_tag_name` | scanner |
| kotlin | 60 | 10 | externals | scanner |
| swift | 35 | 33 | externals | scanner |
| ocaml | 19 | 6 | externals | scanner |
| scala | 14 | 25 | externals | scanner |
| julia | 6 | 16 | externals | scanner |
| zig | 6 | **0** | `offer()` refuses `{` | weave |
| php | 2 | 12 | externals | scanner |
| toml | 1 | 5 | extras extent | press |

**662 of 669 are behind an external scanner we cannot run**, which is one
missing feature rather than 662 bugs. **6 are `offer()`**, in the one grammar in
the whole set that declares zero externals, so nothing lexical is available to
blame. **1 is the extras predicate.** Nine of the nineteen have no findings at
all.

#### The two terminals that are 526 of the 662

Both were proven with a minimal pair rather than inferred from a name list,
because "this grammar declares externals and also has findings" is a
correlation, not a cause.

**html: 209 findings, one terminal, and it is not attributes.** `<p>hi</p>` is
enough. `_start_tag_name` is external, so `p` is never recognised as a tag name,
and everything between the brackets falls to `text`. Every attribute-shaped
finding downstream is that same collapse seen again at the next tag.

**elixir: 317 findings, one terminal, and the pair separates it cleanly.**

```
def f, do: 1        parses
def f do 1 end      collapses
```

The difference is `_newline_before_do`, external #20 of elixir's 26. The 76
`block` and `arguments` findings are not separate problems; they are the same
collapse counted where the block should have been.

#### Rows for the lanes that own them

**To the scanner lane**, in the shape its own census ranks by, so it can price
these against haskell without re-deriving the work:

| terminal | grammar | kind | findings | reach behind it | witness |
|---|---|---|---:|---:|---|
| `_start_tag_name` | html | word start, `<` then a name | 209 | 72,288 B | `<p>hi</p>` |
| `_newline_before_do` | elixir | zero-width, newline-sensitive | 317 | 46,089 B | `def f do 1 end` vs `def f, do: 1` |

Both are single terminals, both gate a whole file's structure rather than a leaf,
and between them they are **79% of everything the held-out set cannot explain**.
`_newline_before_do` is zero-width and layout-driven, which puts it in the same
family as javascript's `_automatic_semicolon`; `_start_tag_name` is an ordinary
word start with a context condition.

**To the weave lane**: zig's refused `{`. zig declares **zero** externals, so
the 6 findings cannot be scanner blindness. The parse refuses `{` at 4,101 and
the initializer that follows reads as a struct body. This is `offer()`, and it
is the same wall already routed to weave for c, cpp and bash - **four grammars,
one predicate**, which makes it the single largest lever in the tree that is not
the scanner.

**To the press lane**: toml's trailing-comment extent. One finding, an extent
rather than a name, on a file that is otherwise 731 nodes identical on both
sides. `comment` is in toml's `extras`, so the question is where an extra
attaches when it trails - the extras predicate. **lua is the control**: it is
also extras-heavy, it is now byte-identical, and it did not move, so whatever is
wrong is specific to the trailing position rather than to extras in general.

### What one parse-loop feature is worth: 11.2% becomes under 82.4%

Before grinding those walls down one at a time, it is worth knowing what the
alternative is worth. `python3 tool/resync.py` prices it by denial, the way
ruby's wall was priced before anyone fixed it: parse; when it stops, skip the
offending token and parse the rest as a fresh file; add up what each pass
reached. **Recovery does not have to exist to be measured.**

| | bytes | share |
|---|---:|---:|
| today, one pass per file | 59,091 | **11.2%** |
| if the parse resynchronised | <434,031 | **<82.4%** |

A 7.3x gain from one feature, and **it is an upper bound**, generous on purpose
in three ways: a resumed pass starts in the *start state*, which admits far more
than the stack state a real resynchronisation would resume in; it counts bytes a
pass *reached*, not bytes it *placed correctly*; and it steps over a single
punctuation byte at a time, which is the most chances the parser could possibly
get. What would tighten it: resume in the real stack state, score the resumed
nodes against tree-sitter instead of counting bytes, and raise the hop cap,
since haskell, verilog and yaml hit it and their rows are themselves floors.

The shape matters more than the total. **Resumptions are cheap where they
matter** - the corpus eleven need 0 to 41 hops each, and php needs **one**: its
whole 67,845 bytes sat behind a single word at byte 17. **Nineteen of thirty
land above 90%.** And **yaml is the one row recovery cannot help**, 0.0% before
and after, because its wall is not a token we cannot lex but that no terminal is
producible anywhere, so there is no next plausible point to resume at; haskell
at 24.3%, julia at 41.2%, lua at 60.1% and swift at 63.1% are the rest of the
genuine tail.

So the ordering: **the parse loop before the externals**, for everything except
those five.

The number was taken on two binaries a lane apart, and **27 of the 30 rows are
byte-identical across them** - the control. On `0fb53dbb4` it read 6.1% today
against a <77.4% bound, a 12.7x ratio; nineteen minutes later on `ed4d4a61b` it
reads 11.2% against <82.4%, 7.3x. As walls fall the counterfactual's marginal
value shrinks, which is the number behaving correctly.

**Both columns of that table were taken with the broken reach rule, and the
"today" column is the one it broke.** Corrected, today is 96.4%, which is inside
the bound this section quoted as the *prize*. The counterfactual has largely
been collected, and not by building what it priced: the parse loop was already
resynchronising, in the form of the mending the old rule refused to count. What
the section still gets right is the shape - yaml cannot be helped at all, and
the hop distribution says where a real resynchronisation would earn its keep -
so it stays here as the reasoning, with its totals marked superseded. Re-pricing
it against the corrected baseline is worth a run; it will be a much smaller
multiple, which is the point.

### On broken input we do not recover, and tree-sitter does

Every file above is valid, and so is every held-out file, so every number in
this dossier was measured on input that parses. That is a strange thing to be
true of an *incremental* parser, whose whole reason to exist is a buffer being
edited - and a buffer under edit is syntactically broken most of the time.
Between `if (` and `if (x)` every intermediate state is invalid.

`research/joinery/broken/` asks what happens then: twenty-five files, one
deliberate break each, in four of the grammars that are byte-exact on valid
input, each with valid code after the break so "does it recover, or just stop?"
has an answer. `python3 tool/recover.py` runs them.

| | tree-sitter | joints, then | joints, now |
|---|---:|---:|---:|
| one root spanning the whole file | **25** of 25 | 0 of 25 | 1 of 25 |
| repairs marked in the tree | 10 MISSING, 30 ERROR | none | none; neither node kind exists |
| code after the break still gets nodes | 25 of 25 | 5 of 25 | **25** of 25 |

**The bottom row is the one that moved, and it moved all the way.** Every one of
the twenty-five broken files now gets nodes over the code after the break;
nineteen of them do it by mending, thirty-seven mends in all, and the rest by
the older `truncated` and `unclosed` verdicts where the lexer read to the end
and no root closed. The forest is one to fifteen partial roots rather than one
whole tree, so an editor gets structure past the caret without being told a lie
about it. Taken by `recover.py` on `joints f6a34cd7c`.

The top row has not moved and mostly should not. Never inventing a node is
deliberate and documented - `Only Stop.accepted is a whole tree`, and a partial
tree plus the reason for stopping beats an error with no prefix. tree-sitter's
25 of 25 is 25 files with an `ERROR` or `MISSING` node standing in for the
break; ours is a forest that says where it broke. The one row we hand it without
argument is that a client wanting a single spanning root has to stitch ours
itself.

One fixture turned out not to be broken. `javascript/dangling-keyword.js` is a
bare `return` at program level, which tree-sitter-javascript **accepts** - zero
ERROR, zero MISSING - and we stop at byte 25. That is an ordinary differential
finding on valid input that the corpus never thought to ask, and it is worth
more than the fixture that carried it in.

Five differences survive across the eleven, and they are two questions rather
than five:

- **c, three findings at byte 612.** `long total;` reads as one
  `sized_type_specifier` spanning `long total` where tree-sitter reads `long`
  plus a `field_identifier`. Both are legal: tree-sitter-c writes
  `field('type', optional(choice(prec.dynamic(-1, $._type_identifier), ...)))`
  and declares `['sized_type_specifier']` and `['type_specifier',
  'sized_type_specifier']` as conflicts. So it is a declared fork whose winner
  is chosen by **dynamic precedence**, and the `-1` sits on exactly the branch
  that swallows the identifier. It is not keyword extraction and not a
  longest-match tie-break; the ranking that consumes `Production.dynamic` is
  the press lane's.
- **cpp, two findings**, the template argument, the same shape.

**The binding constraint on rung 1 is now the lexer and the fork, not the
monoid.** Rung 1 can only ask what the parse reached, and the parse reaches the
end on five of eleven - json, java, javascript, typescript and rust. Every one
of the other six stops is one of three known-and-owned things:

- **A terminal no lexer rule can produce** - python, ruby, bash. Each
  grammar hands some terminals to a hand-written external scanner, and joints
  has no equivalent yet: ruby is blind to 29 of its own, bash 22, rust 11,
  typescript 9, python 8, javascript 7, cpp 2. **rust used to be the widening's
  one casualty and has since left this bucket.** Rust nests block comments,
  which no regex can match, so tree-sitter-rust makes `_block_comment_content`
  external; blind to it, the file died at byte 0, and it now parses whole and
  byte-exact. python is the
  one that has since been answered: its string start is external, and the lexer
  now has an entry for it, so the docstring and the triple-quoted banner both
  lex. ruby's `attr_reader :rows` is the same hole wearing
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

### Against tree-sitter - six axes, three wins, two losses, and one unmeasurable

Full dossier: [`bench.report.md`](bench.report.md). Two sweeps, `bench.py`,
tree-sitter 0.26.11, the same 128 KB files, both stamped.

**Lead with the loss.** One space typed and deleted near the end of a 131,565 B
typescript file costs us **66,224 us against tree-sitter's 430.6 us - 153.8x**.
Our first keystroke costs 66,497 us and our own cold open of that file is
75,206 us, so on this grammar **the edit costs 88% of reopening the file.**

**And typescript is now alone in that.** This row read 14,746x, with javascript
at 10,066x and java at 326x, until the weave lane's `torn` fix gave each live
reading its own strand. Re-taken on a current binary at the same `@98%` relative
cut, java is **1.6%** of a cold open and javascript **1.1%**, beside rust's 2.7%
and json's 1.7%. A three-grammar defect became a one-grammar defect, which makes
it a better bug: whatever typescript does differently is now the whole question.

| axis | span | verdict |
|---|---|---|
| press | 0.01x - 0.50x | **ours**, and by the widest margin on the board |
| artifact | 0.14x - 0.68x | **ours** - cpp 779,024 B of folio vs 5,636,440 B of `.so` |
| install | 0.19x tooling | **ours** - one binary + N folios vs the CLI + N dylibs |
| memory | 0.60x - 1.16x | **ours on 4 of 5**; typescript loses at 1.16x |
| throughput | 1.14x - 724x | **theirs**, on all five, json nearly level - *see the collapse below* |
| incremental | 0.89x - 153.8x | **theirs on 4 of 5**; json is the one row we take, and typescript is now the only bad row |
| startup | - | **unmeasurable** while the parse swamps it; see below |

**The throughput row is out of date in our favour, and only on one code path.**
The scanner lane's reachability mask landed, and the prediction written down
before it did - javascript and typescript collapsing toward a 700-900 ns/B band
while rust and java barely move - was met: javascript went **42,917 -> 320
ns/B** and typescript **50,818 -> 478**, while rust moved 1.5x and java 2.7x.
The 60x-280x spread that made the two blind-external grammars outliers on real
code is gone; all five now sit between 64 and 608 ns/B.

**For 34 minutes it was live on only one of two code paths, and the product ships
the other one.** The same binary parsed the same file in 0.14 s from a grammar
and 15.40 s from a folio it minted itself, because the mask was derived at import
and never written into the folio. The scanner lane closed the round-trip, and the
folio is now the *faster* path - it skips the import the grammar path pays every
time. `order.py` gates both paths separately and is flat on all ten rows;
javascript's folio row went 15,654 ms to 45 ms.

**Every number in `bench.report.md` now says which path it was taken on.** The
performance axes were all folio already, which is luck rather than design; the
exceptions were the prediction-collection numbers taken by hand through a
grammar, and those were exactly the flattering ones. Re-taken on the folio path
they agree within noise. On real corpus code through folios the whole eleven-
grammar table now reads 109-777 ns/B, javascript at **407** and typescript at
**565**. `research/joinery/bench.report.md` carries the audit.

**The cause is attributed, and the first attribution was wrong.** The previous
draft of this section led with a newline ablation - `\n` replaced by `' '` took
javascript-122.js from 18,237 ms to 11.9 ms at an identical byte count - and
named `_automatic_semicolon` from it. **That is retracted.** The file holds 244
line comments, the first at byte 251, so replacing the newlines turned the rest
of the file into one line comment: the tree goes from **39,407 lines to 17**. The
fast run was not a cheaper parse of the same program, it was a parse of almost no
program. Holding bytes constant is not holding work constant.

Held properly - bytes **and** node count fixed, only the newline count varied -
line terminators do not matter at all: 2,000 newlines costs 987 ms and 32
newlines costs 942 ms over the same 24,890 bytes and 28,001 nodes. ASI is not the
cause.

**What is.** A sampling profile of one 18-second run puts **98.2% of 2,354
samples** under `Scanner.read` at `scanner.zig:801` - which is `s.reach(...)`,
the slate walk - and into `Munch.longestAmong`. The fold path takes **0.13%** and
minting **0.04%**, so the scanner is the site and the parse loop is not.

The defect is that **scanning a byte costs in proportion to how much has already
been read**, which makes every parse quadratic. The witness holds bytes and nodes
exactly constant and moves only the order of two halves:

```
4000 statements, then a 100 KB string literal    152,010 B   28,011 nodes   16,175 ms
a 100 KB string literal, then 4000 statements    152,010 B   28,011 nodes    4,232 ms
```

**3.8x-4.7x from order alone** across four takes on three binaries, and
isolated, that tail costs 12,877 ms read last against 116 ms read first -
**111x for the same bytes**. Five hypotheses are tested and discarded in the
report: ASI, mending (all five parse **whole, 0 mends, 1 root**), folio size
(rust's folio is 2x javascript's and parses 40x faster), identifier vocabulary
(6%) and sibling count (2.2x).

That pair is now **committed**, at `research/joinery/order/`, alongside the
construction in `tool/order.py` that makes it and the gate that holds it. It
used to be two files in `/tmp`. The construction is the finding: **holding bytes
constant is not holding work constant** - the retracted ASI ablation held bytes
exactly and turned 99.96% of the file into a line comment - and this is the first
pair here that pins bytes *and* nodes at once. So both axes are re-checked on
every run, and a pair that stopped matching would report "this proves nothing"
rather than a ratio.

`python3 tool/order.py` is the gate: not a duration, which would be
laptop-specific, but a **ratio between two parses on the same machine in the
same process**, ceilinged at **1.6x**. The number comes from what the flat
grammars already achieve - json 0.96 / 1.01 / 1.00, java 0.88 / 0.96 / 0.99 over
three replicates, so 12% is the widest excursion without the defect - with about
five times that in headroom against the 4.3x load swing measured below. Today
three of five rows fail it at 2.8x to 4.1x, which is the point; a gate that
passed before the fix would not be a gate. It is `continue-on-error` in CI for
the reason rung 1 does not gate its thirty refusals, and that comes off the day
all five rows are under the ceiling.

The narrowing that goes with it is checkable rather than asserted, and all five
grammars now carry the swing as a measured row rather than three rows and two
dashes - because that column is what separated the groups, and it is the cheapest
early warning if a fix only helps javascript:

| grammar | blind externals | order swing |
|---|---:|---:|
| rust | 3 | **4.0x** |
| typescript | 4 | **4.0x** |
| javascript | 2 | **3.8x** |
| json | 0 | 0.9x |
| java | 0 | 0.8x |

**Every grammar with zero blind externals is flat; all three with blind
externals swing about 4x.** Presence separates the groups; count does not order
them within one, so this names where to look first and is not proven to carry the
whole magnitude.

**`lex` is a false-negative surface for this class**, and it is the trap the next
person would walk into. The same pair through the bare lexer costs **46 ms and
47 ms** - flat in both orders, 350x cheaper, indistinguishable from health -
because the defect lives in the per-position admitted set that the parse loop
supplies and the lexer has none. A gate built on `lex` would pass forever while
`parse` stayed quadratic. `order.py` goes through `stamp.ask`, which parses, and
re-runs the lexer over the worst pair on every run so the trap is demonstrated
rather than filed.

Four things this section will not round up:

- **`startup` is not an axis yet.** It is a fixed cost subtracted from a slope,
  and the subtraction goes negative wherever the parse is slow - javascript
  `-207 ms, +-809%`. Exactly one grammar survived, on one sweep. It becomes
  measurable the day the quadratic is gone, and a published negative duration
  would have been worse than three "skipped" lines carrying their arithmetic.
- **The throughput table is the flattering subset.** Six grammars are absent
  because joints stops early on their 128 KB file.
- **The double take is the weaker kind.** The census's two runs were one byte
  apart; these two sweeps ran on *different binaries* because another lane's
  `scanner.zig` landed between them, and both printed `MOVED` saying so. 35 of
  39 guarded numbers still held across a **4.3x change in machine load**, and the
  four that moved were all wall-clock. That is the argument for quoting the
  ratios and not the absolute times.
- **The incremental losses are two defects, not one** - and the argument is
  confirmed by how they were fixed. java carried **zero blind externals** and was
  nowhere near the quadratic, yet was 326x, so the two could not be one bug.
  Fixing the mask did nothing for it; fixing strands took it to 1.6% and left the
  throughput row untouched. What survives is typescript at **88.4%** of a cold
  open, on a harness where four other grammars are under 3%. It reads as a
  predicate rather than an algorithm, and it is carried as its own handoff row so
  it cannot be absorbed into the
  quadratic's story.

A pathology found on the way that now shares a signature with the main defect: a
file of nothing but whitespace is quadratic under the rust folio (`n^2.0`,
409,600 B in 73 s) and linear under json's (102 ns/B) - **the same
json-against-the-rest split as the order test**. It does not transfer to real
files (collapsing whitespace in a real rust file moves 144 ms to 139 ms), so it
was logged separately; it should now be retested against the same fix rather than
chased alone.

Hardware-independence, since two of these axes are byte counts and four are
clocks: `artifact` and `install` are **exact anywhere**. All ratios are
**near-independent** - both sweeps agree inside 8% across the 4.3x load swing.
Every absolute duration and **the whole `memory` axis** are **laptop-specific**;
peak RSS on 16 KB-page arm64 macOS is not a number to quote on a 4 KB-page Linux
box.

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

**First measurement, and it is the kill condition.** `bench.py`'s `incremental`
axis is edit 1 - one character typed and deleted at **98% of each file's own
length**, relative and never an absolute byte - and we lose it on four grammars
of five: typescript 153.8x, rust 7.1x, java 3.0x, javascript 1.2x, against a win
on json at 0.89x. Two distinct defects sat behind that: the quadratic scan above,
and three grammars **not engaging the incremental path at all**. The second is
now one grammar - typescript, whose first keystroke is 88.4% of a cold open while
java is 1.6%, javascript 1.1%, rust 2.7% and json 1.7%. java is what proved they
were two defects: zero blind externals, nowhere near the quadratic, and 326x
anyway. The
rung is not dead - json shows the splice works where nothing obstructs it, and
rust is 97x cheaper than reopening - but the premise is unproven until those two
defects are cleared and it is re-measured across the size sweep this rung
actually asks for. See [`bench.report.md`](bench.report.md).

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

**First measurement, on the megabyte half only.** `bench.py`'s `artifact` and
`press` axes cover eleven grammars against tree-sitter's own generated C, and
both go our way: folio is **0.14x - 0.68x** of the compiled `.so` (cpp 779,024 B
against 5,636,440 B, from 25,860,012 B of C we never emit), and press is
**0.01x - 0.50x** of generate-plus-build (ruby 148 ms against 12,429 ms). Both
are pure byte counts and wall-clock ratios, so both reproduce anywhere. This does
**not** discharge the rung: it is eleven grammars not forty, megabytes not bits
per production, and it has no CSR baseline in it. See
[`bench.report.md`](bench.report.md).

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

## How to read `zig build test`, since three of us read it three ways

The suite is a twelfth instrument that has been misread, and the misreading goes
both directions - one lane calling a green run red, another calling a red run
green. Three rules:

- **Assert on the `Build Summary` line and the `FAIL` count.** A clean run says
  `Build Summary: 73/73 steps succeeded` and prints no `FAIL`. The last run here
  said `71/73 steps succeeded (1 failed)` with **exactly one** `FAIL`:
  `kernel.weave.amend_test.test.weave: the same, on rust, which is the grammar
  that forks`, in shard 15/32.
- **Never assert on `$?`.** It reads **0** on a run that failed a shard. A
  wrapper swallows it, so the exit code is not a verdict and never was.
- **Never grep for `expected`.** The thirteen `expected .accepted, found
  .unexpected` lines and the eleven off-by-ones under `weave: negative control`
  are **the negative control's own printed diagnostics**, not failures. They
  print on a passing run.

The proof of the last two: rerunning the one failing shard alone gives
`brigade 15/32: 10 passed, 0 skipped, 0 failed` three times in a row, while still
printing the `expected .accepted` lines. That row is **parallel-load flake**, not
a defect - which also means a `FAIL` count of one is not automatically a red run,
and the shard has to be rerun alone before it is called either way.

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
- **Leaf coverage against an outside lexer.**
  `python3 research/joinery/verilog/leaf.py --check`, floors in
  `leaf.floor.json`. Every other column here is computed from our own forest -
  `standing` and `damage` read top-level root spans, `square` reads agreement
  with an oracle that can go blind over a whole file, `spoil` reads whether a
  byte was reached - and **not one of them can see a token nobody stood on**.
  An independent lexer's token stream can, needs no agreement about tree shape,
  and is the one number directly comparable to tree-sitter. Verilog was at
  59.4% of Verible's token bytes to tree-sitter's 98.8% for the life of the
  project with nothing on the board able to say so
  ([verilog/RESULT-7-leaf.md](verilog/RESULT-7-leaf.md)).

  Two habits make it a test rather than a reading. **A missing instrument skips
  loudly and never passes** - no yardstick, no folio, or a second source whose
  sha256 moved, each says so by name. And it carries **witnesses with their
  verdicts written down**, including verdicts that are defects: a witness
  expected to be `refused` fails the moment somebody repairs it, which forces
  the repair to be acknowledged rather than absorbed, and turns the falsifier
  into the regression guard for the fix that dissolved it.

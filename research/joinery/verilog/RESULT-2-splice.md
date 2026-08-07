# RESULT-2 — the splice, not the ladder

Against `PREDICTION-2-splice.md`. Six predictions, **three failed**, and the
failures are the finding: the mechanism is exactly what I said it was, and every
one of the four repairs I could build on top of it costs the corpus more than it
buys. **Nothing seated. The lane ships an instrument and this dossier.**

| | prediction | outcome |
|---|---|---|
| P1 | `c[i] = 0;` parses, control holds | **held** under two of four repairs |
| P2 | `c[i] <= 0;` was standing while wrong | **held** — it builds `clocking_drive` |
| P3 | state 701 goes away | **FAILED** — 701 survives every repair |
| P4 | `$signed` is not fixed by this | **FAILED** — it is, by two of four |
| P5 | the board moves up | **FAILED** — every repair moves it down |
| P6 | 29-or-30 of 30 tree-identical | held, at 29 and at 30 |

## The three named states are not where anything is decided

The first thing to check was the brief's own warning, and it is worse than
advertised. Instrumenting `Bench.decide` to print its survey for a given state:

- **state 701** holds exactly one item, `casting_type -> constant_primary .`,
  and admits exactly one terminal, `'`. Nothing was ever contested there.
- **state 3772** and **state 2394**: no contested cell at all.

All three are places a committed parse ran out of road. So `--holding` was
built (below) to ask the automaton the inverse question, and it names
**state 1184** — the state after an identifier in statement position:

```
clockvar         -> _identifier .
variable_lvalue  -> _identifier . select1
variable_lvalue  -> _identifier .
nonrange_variable_lvalue -> _identifier . nonrange_select1
_assignment_pattern_expression_type -> _identifier .
…
```

Its row has no shift on `[`.

## The mechanism, in one cell

```
PROBE state 1184 t=118 [ reading=true frayed=false
  above=false below=false level=true continues=false grounded=false unwritten=false
  sole=916 one_rule=false
  fold=clockvar prec=.{ .level = 0 } left=true right=false loose=false tied=false
  ladder=fold
   poll t=[ read variable_lvalue           dot=1 rank=.{.level=0} vs fold .{.level=0} -> eq
   poll t=[ read nonrange_variable_lvalue  dot=1 rank=.{.level=0} vs fold .{.level=0} -> eq
   poll t=[ read hierarchical_identifier_repeat154 dot=1 rank=.{.level=0} -> eq
```

Read it left to right and the whole defect is on one line.

`variable_lvalue` is authored `prec.left(37, …)` in `verilog.json`. **It polls at
0.** With 37 the survey would be `above && !below` and rung 2 returns `.read`
before associativity is ever asked. At 0 it is a tie, rung 3 asks
`purely(f, .left)`, and `clockvar`'s fold answers yes — because `clockvar` is
`$.hierarchical_identifier` and `hierarchical_identifier` is `prec.left(0, …)`.
So the read is deleted. Then `f.tied()` is false, `standing` comes to **1**, and
`decide` returns at `if (standing <= 1)` **without recording the cell**. No
conflict, no fork, no `[` in the row.

Where the 37 goes is `fold.zig::expand`. Inlining splices a victim's steps into
its host and the boundary step takes the host's rank *only where it has none of
its own* — `if (last.prec == .none) last.prec = host.prec`.
`_hierarchical_variable_identifier` reaches `_identifier` through
`hierarchical_identifier`, which wrote `prec.left(0)`, so the boundary arrives
carrying an authored zero and the host's authored 37 is dropped. Upstream never
inlines a hidden rule, so upstream never has to choose between the two.

**Two authored ranks meet at a boundary that only exists because joints
inlines. Whichever survives, it is not what anybody wrote.** That is the shape,
and it is not verilog's: any grammar with a `prec` wrapper around a reference to
a hidden rule that carries its own `prec` has it.

## Four repairs, all measured, all rejected

Every row below is a **pinned binary either side** (`tool/pin.py`), its own
folio cache (`JOINTS_WORK`), the full board, and a tree-by-tree comparison of
all thirty grammars — never a folio digest. Baseline: corpus damage **142,083**,
`describes` **97,898** nodes, verilog damage **63,937**.

| repair | verilog | scala | elixir | describes | witnesses seated | trees |
|---|---|---|---|---|---|---|
| *(baseline)* | 63,937 | 4,150 | 1,559 | 97,898 | — | — |
| **A** host's rank wins the boundary | **67,349** | 4,150 | 1,559 | 96,261 | W5 W6 W7 W8 | 29/30 |
| **B** record every side-rung cell | **62,645** | **16,883** | **8,917** | 94,981 | W5 W6 W7 W8 | — |
| **C** B, but only across different rules | 63,937 | **16,883** | 1,559 | 97,431 | W7 W8 | — |
| **D** drop a spliced side where ranks clash | 63,937 | 4,150 | 1,559 | 97,886 | none | 30/30 |

**A — prefer the host's rank at the boundary.** The obvious repair, and the
board says no in a way I did not predict. It seats four witnesses and *raises*
verilog's damage by 3,412 bytes. The press explains itself: contested cells
**18,732 → 9,915**, of which declared **18,715 → 9,900**. Verilog is
disambiguated by its 181 declared conflicts, not by its ranks — teaching
precedence to speak deleted 8,817 GLR forks. It also silenced the unfold round
(`unfolded 1 → 0`, frayed 3,509 → 7,056, LR(0) states 9,763 → 9,276). Every
other grammar is byte-identical, so the whole trade was verilog's and verilog
declined it. Flipping only `assoc` rather than `prec` changes nothing — the
prec flip is the whole effect, measured separately.

**B — record the cell the side rung decided.** Purely additive by construction:
`spared` runs after `r[t]` is already written, so no cell changes its primary
action; the reading just survives as something the parse may split on. On the
witnesses this is the best result anyone got — W5, W6, W7 and W8 all stand and
**all seventeen controls stand**, up from eight both-stand rows. And it costs
scala 12,733 bytes and elixir 7,358. Scala's is legible in the tree: before,
`@SerialVersionUID(0) class Some[+A] …` is one `class_definition`; after, the
annotation splits off as its own root and the class shreds. **The press offered
a legitimate fork and `gather` took the wrong limb.** That is a second defect,
one layer down, and it is the reason this dossier has no fix in it.

**C — B, narrowed to cells whose parties are different rules.** `prec.left` on
`E -> E + E` orders a rule against itself; using it to delete a *different*
rule's reading is the over-reach, so `!survey.one_rule` should be the guilty
subset. It splits the damage instead of removing it: elixir's regression is in
the `one_rule` cells and comes back clean, scala's is in the others and stays.
W5/W6 turn out to need the `one_rule` arm and go red again.

**D — where two authored ranks clash at a splice, keep the level and drop the
side.** The tightest statement I could make without a new `Step` field. It
fires, and it cannot reach this cell: the clash is on the *read's* step
(`variable_lvalue`, 37 vs 0) and rung 3 consults the **fold's** side, which
`clockvar` inherited from `hierarchical_identifier` with no clash to detect.
Board byte-identical, `describes` −12. An inert change with a small cost, so it
is not shipped either.

The honest next step needs provenance on the step — a bit saying "this rank was
spliced" — so rung 3 can decline a side it inherited. `Step` is
`leaf.StepRecord`, an `extern struct` in the folio format, so that is a format
change and `impose`'s ledger owns it. I did not start it.

## What state 701's composition failure *was*

`{a, b}` parses. `a[3]` parses. `{a[3], b}` does not, and the wall is a `;` in
a state holding one item, `casting_type -> constant_primary .`.

The press is not missing the combination. Inside the concatenation the parser
reads `a` and reaches a state that holds both `constant_primary -> _identifier .
constant_select1` and the completed foldable readings beside it. The `[` reading
is deleted by the same rung-3 fold, so the only surviving derivation for `a`
followed by `[` is the one where `a` is a whole `constant_primary` and what
comes next opens a **cast** (`casting_type -> constant_primary`, then `'`). The
element commits to the one interpretation still alive and dies at the first
token that is not `'`.

So: **the composition failure is a deleted fork, not a missing rule.** The
press holds `{…}` and it holds `a[3]`, and it cannot hold both at once because
composing them requires *carrying two readings past the identifier*, which is
precisely what `standing <= 1` discarded. A grammar whose two pieces each parse
alone and refuse to compose is the signature of a fork that was resolved
instead of recorded — and repair B, which records it, is the only one of the
four that moves verilog's damage down. It just cannot pay for scala.

Worth stating plainly against the brief: 701 is **not** a GAP the closure
mis-called. `reach.py` was right that the grammar derives it.

## `built` counting wrong structure, caught live

P2 held and it is the most useful thing here. `c[i] <= 0;` — the *control*, the
half that "stands" — builds:

```
(statement_item (clocking_drive
  (clockvar_expression (clockvar (simple_identifier))
                       (select1 (bit_select1 …)))
  (expression …)))
```

A `clocking_drive` is what a clocking block does to a signal. This is a `reg`
array element under a blocking-domain assignment in an `always` block; it is a
`nonblocking_assignment` over a `variable_lvalue` and nothing else. The control
stands, contributes to `built`, and is wrong — for exactly the reason the
witness beside it fails. Same deleted reading, two different symptoms, and only
one of them is visible to the board.

That is the 9.24% floor in person, and it is why the 93-byte row was worth
starting on: **the 93 bytes were the part of this defect that `built` could
see.**

## Board, unchanged

The lane ships no table change, so the board is the board. With the shipped
tree (`.local/pin/final`), one folio generation, every row measured against
what this tree holds now:

- **73.0% standing** · 84.6% covered · 20.0% unbound
- `built + orphan + rubble + spoil = 526,798`, damage **142,083** over 18 of 30
- `describes` **97,898** nodes — the column that catches a policy reading less
- **bare leaves 5,586** over 60,702 strewn bytes; `orphan basis: bare 1 (markdown)`
- verilog: size 94,657, built 30,720, strewn 17,324, **damage 63,937** =
  orphan 3,267 + rubble 14,057 + spoil 46,613, 3,544 roots, **2,481 bare leaves**
- sound 1 of 30 UNSOUND (toml, pre-existing)
- **tree-identical 30 of 30** against the pinned baseline

The headline reads 73.0% where the brief says 69.09%; that is other lanes'
work landing on the shared tree between the brief and this run, not mine. My
own before/after rows are identical to the byte.

## The instrument I trust least

**`joints parse`'s failure state**, and not as a hedge — the brief already
warns it is "a location, not a diagnosis" and the warning is too gentle. Here is
the demonstration:

```
$ joints state upstream/grammars/verilog.json 701
state 701 of verilog
  items:
    casting_type -> constant_primary .
  row — shifts: (none)
  row — lookahead:
    '   fold  casting_type -> constant_primary
  shift 0, lookahead 1 — 1 terminal(s) accepted of 444
```

**All three** states this lane was handed — 701, 3772, 2394 — have *no contested
cell*. Not one of them is a state where the press decided anything. Probing
`Bench.decide` across each prints nothing at all. The number is not merely
downstream of the defect; it is a state the settle bench never visited, so a
lane reading it as "the cell that went wrong" is reading a cell that was never
in question. Three of three, which is the whole sample.

Worse, the number is not even stable across builds. Comparing state 1359 between
two binaries that differ only in one line of step-precedence splicing gives two
completely different item sets: the LR(0) collection went 9,763 → 9,276 states,
so **every state number renumbered**. Any note of the form "the defect is at
state N" is scoped to one build of one tree, and this tree has ten agents in it.

The repair is not to distrust the number harder, it is to have the inverse
query. So the one thing this lane ships is:

```
joints state <grammar.json> --holding <item>
```

which names every state whose kernel spells the item, dot included:

```
$ joints state upstream/grammars/verilog.json --holding 'variable_lvalue -> _identifier .'
710: variable_lvalue -> _identifier . select1
1184: variable_lvalue -> _identifier . select1
…
92 of 9763 state(s) hold a kernel item spelling variable_lvalue -> _identifier .
```

Read-only, exits 1 on no match, 30 of 30 grammars tree-identical with it in.
It is how 1184 was found after the three handed state numbers went nowhere.

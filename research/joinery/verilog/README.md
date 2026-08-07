# verilog — the board's largest damage, attributed

`picorv32.v` is 94,657 bytes and the top row of the board ranked by
`damage = size - built`: **63,937 bytes**, 32.5% standing, 2,109 mends. This
folder is what those bytes turned out to be.

Read [RESULT-2-witness.md](RESULT-2-witness.md) first - it is the answer. Read
[RESULT-7-leaf.md](RESULT-7-leaf.md) next if you want the competitive number
rather than the anatomy: it is the only chapter measured against something other
than our own tree, and it is the one that says which of the two defects below
generalises past this file.
[RESULT-1-wall.md](RESULT-1-wall.md) is how the file was fenced off;
[PREDICTION-1-wall.md](PREDICTION-1-wall.md) was written before any of it ran
and two of its five predictions failed.

Then [RESULT-2-splice.md](RESULT-2-splice.md), which took the three **conflict**
rows below and found the cell they share - and shipped no fix. All three walls
named states that hold no contested cell at all; the reading is deleted in state
1184, and every repair built on that costs another grammar more than it buys.
[PREDICTION-2-splice.md](PREDICTION-2-splice.md) went three-for-six.

Then [RESULT-3-provenance.md](RESULT-3-provenance.md), which built the fix
RESULT-2 named and refused to start: a provenance bit on the step, so the ladder
can decline a side a rule never wrote. It is free on twenty-nine of thirty
grammars where every earlier repair taxed two, and it does **not** seat verilog.
It converts the deleted reading into an honest fork that `gather` then answers
wrong, so the remaining half is `src/kernel/quire/` and now has a three-line
reproducer. [PREDICTION-3-provenance.md](PREDICTION-3-provenance.md) went
seven-for-nine, and one of the two it "held" was held on a falsifier too weak to
see that the witness it seated came back the wrong shape.

Then [RESULT-5-merge.md](RESULT-5-merge.md), which took that reproducer into
`src/kernel/quire/` and found the handover half wrong: the `=` cell is
`residual`, so **gather is never offered the limb it is accused of declining**,
and four of the seven wrong statements are unreachable from quire. The `<=` cell
*is* a declared fork and gather does answer it wrong — one trace line shows the
fork opening and the next shows it merged away — and both directions out of that
merge are now closed by measurement: keeping the higher rank costs 23,985 bytes
of agreement with tree-sitter, and declining the merge costs 57,627 bytes and
hands back the same trees. [PREDICTION-5-merge.md](PREDICTION-5-merge.md) went
six-for-eight. It also carries the stale-baseline mistake that first read the
arm as a win, which is the one procedural thing worth copying out of this
folder: on a shared tree the control is pinned **after** the arm.

Then [RESULT-6-compose.md](RESULT-6-compose.md), which ran the pair three lanes
had converged on and none had measured — A and B together. They **concatenate
rather than compose**: A empties 8,922 cells at rung 2, B records cells rung 3
decided, and B replaces 5.3% of what A deletes, so A+B is the worst arm on every
column of the board. It also re-judged both halves on `square` instead of
`built` and found **A buys zero bytes of agreement with tree-sitter** while
breaking four controls RESULT-2 and RESULT-3 both record as standing, and **B
costs 29,348** — elixir falls from 23,879 square bytes to **one**. The larger
finding is underneath all six chapters: verilog is **100% unjudged**, its oracle
disagreeing with itself, so every verilog number in this folder rests on
`damage`, which one stretched root buys.
[PREDICTION-6-compose.md](PREDICTION-6-compose.md) went four-for-six. It missed
by predicting the shipped `Step.spliced` would have moved B out from under
RESULT-2's numbers — it reproduces them exactly — and by predicting all three
arms would keep 17/17 controls on the strength of the older table, which is the
row that turned out to be wrong.

Then [RESULT-7-leaf.md](RESULT-7-leaf.md), which stopped asking our own tree and
measured against **Verible's token stream** instead — the first number in this
folder that is directly comparable to tree-sitter. We stand a leaf on **59.3%**
of the bytes an outside lexer calls tokens; tree-sitter stands on 98.8%. It
partitions that deficit and finds it is **98% reach**, spread over 4,693 runs
with a **median of two bytes** — a mend trail, not a construct. Verilog declares
**zero externals**, so it cannot be starved the way haskell was. And it takes the
table below to **three further real verilog sources**, where the two rows invert:
the concatenation row is the wall on two of them and worth **their entire
deficit**, while the directive row — the larger here — is picorv32's own, worth
+6.0 points and nothing elsewhere. It also names the cell the earlier chapters
hunted in 1701 and 1184: a split at **state 2979 on `]`**, `constant_primary`
kept over `primary`, **rank 0 on both sides**. It ships a permanent leaf-coverage
check rather than a parser change, because the seam is `Reading.beats` and a lane
is in it.

**The short version.** The whole file is **four grammar defects**, and two of
them carry 98.4% of the bytes that refuse to stand:

| defect | witness | control that stands | wall | owner | bytes |
|---|---|---|---|---|---|
| a directive in statement position | `` `assert(a); `` | `` x = `WIDTH; `` | `` ` `` in 1108 | **gap** | 21,535 |
| a select inside a concatenation | `x = {a[3], b};` | `{a, b}` · `a[3]` | `;` in 701 | conflict | 19,928 |
| `$signed` both sides of an operator | `$signed(a) < $signed(b)` | `$signed(a) < b` | `(` in 3772 | conflict | 360 |
| an indexed **blocking** lvalue | `c[i] = 0;` | `c[i] <= 0;` | `=` in 2394 | conflict | 93 |

The last row's control is the one to watch. `c[i] <= 0;` stood while building
`clocking_drive`, which is the wrong reading of an array element in an `always`
block, so the row was already resting on a control that was standing-and-wrong.
After RESULT-3 it does not stand at all: the same fork that seats the witness
walls the control. Both halves are the wrong-limb defect in `quire`.

The first has **no derivation in the grammar at all**: `_directives` is
referenced by exactly three rules and neither statement position nor a port list
is one of them, so no work on the press can seat it. That gap at the port-list
position is the same construct earlier priced at 6,935 honest bytes, so roughly
half this file is upstream's and half is ours.

`--mend=keep`, which the board calls the largest describing-less trap it has, is
one - but `covered` and `spoil`, the columns the tree checks that with, both say
it is fine, because a stretched root moves them in the flattering direction too.
`stretch` is the column that catches it: 71.3% of `keep`'s `built` has no token
on it, and netted out it stands over 10,410 fewer real bytes than `fell`.

## The scripts, in the order they were written

Each takes `JOINTS_BIN` and scores through `standing`'s own arithmetic, so no
row here can disagree with the board about what a root is.

| script | question | what it settled |
|---|---|---|
| `ablate.py` | does blanking one construct move `built`? | directives move it; comments do not, to the byte |
| `ladder.py` | do the ablations compose, and is `--mend=keep` a trap? | they compose; the trap needs its own parse per policy |
| `stretch.py` | is a large `built` a tree or one root over a hole? | `keep` is **71.3%** hole to `fell`'s 13.6% - the column that catches it |
| `climb.py` | how many walls between this file and a whole parse? | 120 warm rounds, no saturation - wrong question |
| `modules.py` | which of the eight modules stand alone? | three stand whole; contamination costs 3,243 bytes |
| `named.py` | price the three walls the split named | A +9,788, B +1,704, C +0; two modules 54% -> 100% |
| `core.py` | walk the main module's stops | 61 rounds, `built` down 1,508 - stops are resync, not walls |
| `header.py` | is the main module's header the wall? | no: −2,972 bytes of header moves `built` by 0 |
| `procedural.py` | declarative half vs procedural half | 90.3% vs 16.2%; 1,400 of 1,506 mends are procedural |
| `inside.py` | which statement form inside them? | every arm negative - the method's blind spot |
| `blocks.py` | partition the damage per block, no ablation | 92.1% procedural, 69.9% in three `always` blocks |
| `lvalue.py` | price the one-line reproducer | −167 bytes: a perfect diagnosis worth nothing |
| `braces.py` | price the other two reproducers | +68 and −2,176 |
| `reach.py` | gap or conflict? off the grammar's own closure | two gaps, four conflicts - no parse, no oracle needed |
| `witness.py` | how many distinct defects, and what does each cost? | 178/204 statements stand alone; 13 walls, 42,166B |
| `smallest.py` | what *is* each one, authored beside a control? | 9 fail beside a standing control, 8 suspects innocent |
| `leaf.py` | of the bytes an outside lexer calls tokens, how many do we leaf? | 59.3% to tree-sitter's 98.8%; 98% of the deficit is reach; `--check` is the permanent floor |

## Three method notes worth carrying to another grammar

**Ablation cannot separate a grammar gap from a productive construct.** Blanking
a construct that partly parses removes the bytes it was contributing, so both
read as a negative delta. Everything in `inside.py` is uninterpretable for that
reason. What worked instead was **building the smallest module that fails, from
nothing** - four walls named exactly that way, each a single line.

**Clip `built` to the span you are claiming it for.** A module parsed alone in a
file of blanks hands back one root spanning the blanks, and the union counts
them. That printed `6790.4% standing` here, which is only caught because one
module was tiny enough for the number to be absurd.

**Rank walls by bytes, never by counts.** On this file the two orderings
disagree twice. By statements stopped, `` ` `` in 1108 leads with nine; by bytes
`` ` `` in 1953 leads with one statement and 16,289 bytes. And state 2394, which
takes seven of nine warm-only walls in `walls.py`'s peel, costs **−167 bytes**
and lands twelfth of thirteen here - the state that recurs most is very nearly
the one that costs least. Anything ranking from `distinct` (including `voice`)
is ranking the wrong thing; `witness.py` sorts by bytes and prints which wall a
count ordering would have led with, so the disagreement is visible rather than
rediscoverable.

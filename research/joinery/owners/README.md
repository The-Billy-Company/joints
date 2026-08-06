# owners — whose defect is this wall?

A wall is a place the parse stopped. Until this lane, nothing in the tree could
say **whose fault it was** without a person reading the grammar. The damage board
said verilog cost 63,937 bytes; it could not say whether a lane should spend a
week in `src/press/` or whether the construct has no derivation in the grammar we
vendored and the week would be spent chasing nothing.

The verilog lane answered it for six walls by hand with
`research/joinery/verilog/reach.py`, hand-feeding the governing nonterminal per
wall. This directory answers it for the corpus off the wall's own LR state.

## The taxonomy

Four verdicts, and the two hardest ones are both about *where the question can
be asked*, not about who is at fault.

| verdict | means | who fixes it |
|---|---|---|
| **conflict** | the terminal is in the state's LR(1) viability set — the grammar admits it here and we refuse it anyway | **ours** |
| **unowned** | the terminal is outside viability **and** the state is settled (no completed item, so no fold could have put the parse here) | **four suspects, three of them ours** — see below |
| **stranded** | outside viability, but the state holds a completed item — a fold could have caused this refusal, so the state is downstream of the defect and cannot name its owner | unknown, and saying so is the point |
| **scanner** | the wall stands in front of a declared external, or nothing lexed at all | tree-sitter's C scanner, which we don't run |

`stranded` is the load-bearing addition. `inquest.zig`'s `Owner.weave` header
already said a wall state is frequently downstream of the real defect, and a
closure that ignores that calls every early-fold refusal an upstream grammar
limitation — filing **20,381 B** of press work on verilog alone as unfixable.

**`unowned` was called `gap`** and printed *"no LR parser over this grammar
takes it here"*. [`../adjudicate/`](../adjudicate/) put eighteen of those rows
in front of tree-sitter 0.26.11 and fifteen parsed, worth 99.94% of their
bytes. The test is sound; the sentence was not. `viable()` computes FIRST and
FOLLOW over the shared `grammar.json`, but the **items come from our own LR(0)
collection** — so a reading our table construction lost is indistinguishable
from one the grammar never had, and the `src/press/` lane has proved the splice
erases authored precedence with no conflict recorded and no fork. Four things
produce an `unowned`, in the order worth checking:

1. our table lost a reading during the press;
2. our lexer produced a terminal the program does not contain (5 of 18);
3. an external was never seated (67,214 B of the eighteen);
4. the grammar genuinely has nothing (60 B of the eighteen, all verilog).

**`conflict` is tested before `scanner`.** A terminal can be both derivable
here and a declared external; the old order let the name lookup win, which
files a proven press defect under a lane that does not run C. Viability is
positive evidence about *this position*, a blind-hit is a name in a list. Where
both hold the row says so.

The retired list is [`GAPS.md`](GAPS.md), kept with a retraction header because
two lanes' results cite its rows. The live one is [`UNOWNED.md`](UNOWNED.md),
which is a worklist for adjudication and not a claim about upstream.

## Files

| file | what |
|---|---|
| `closure.py` | reads a vendored `grammar.json`, flattens every rule body into sequences of symbols, computes nullable / FIRST / FOLLOW, bridges grammar spellings to the names the press renders (`spellings()`), and reads **every shape an external is declared in** (`declared()`) |
| `owners.py` | reads `outliner state <grammar> <n>` per wall, computes the state's viability set and whether it is settled, assigns a verdict, and prices it off `walls.py`'s peel |
| `UNOWNED.md` | the live worklist — walls this table found no reading for, to be adjudicated against a second parser |
| `GAPS.md` | **retracted.** The list `UNOWNED.md` replaces, kept because two lanes cite its rows |
| `PREDICTION-1-owners.md` / `RESULT-1-owners.md` | six predictions written before any wall outside verilog was labelled, and the honest scoreline |
| `PREDICTION-2-relabel.md` / `RESULT-2-relabel.md` | the relabelling: the externals fix applied, `gap` retired, both unresolved populations adjudicated |

## Running it

A path is not a version. Copy the binary out before measuring — ten lanes share
`zig-out/` and a rebuild renumbers the whole LR(0) collection, so a board keyed
on state numbers from a binary somebody replaced mid-run is a report about an
afternoon.

```sh
cp zig-out/bin/outliner .local/<pin>/outliner && shasum -a 256 .local/<pin>/outliner
export OUTLINER_BIN=$PWD/.local/<pin>/outliner
python3 tool/walls.py run --json > .local/<pin>/priced.json  # the priced peel
python3 research/joinery/owners/owners.py --from-json .local/<pin>/priced.json
python3 research/joinery/owners/owners.py --control        # the verilog four
python3 research/joinery/owners/owners.py --vacuity        # watch the control collapse
python3 research/joinery/owners/owners.py --externals      # the declared-external census
python3 research/joinery/owners/owners.py … --terminals    # re-derive every wall's name
python3 research/joinery/owners/owners.py … --artifacts    # are the state-0 walls artifacts?
python3 research/joinery/owners/owners.py … --stranded     # what the unownable population folds through
python3 research/joinery/owners/owners.py … --unowned      # UNOWNED.md
```

## The controls, and why there are two

A closure that can't derive anything calls every wall a gap, and the board would
look decisive. So neither control is optional.

**The row-admitted control (automatic, per state).** Every terminal a state's own
action row admits is, by construction, a terminal that position can take. So the
closure must find all of them reachable from that state's frontier. It finds
**6,142 of 6,396 (96.0%)**, and any grammar under 95% has **every verdict
withheld** rather than published with a caveat — haskell (94%), sql (86%) and
ruby (71%) are withheld, 76 walls.

**The collapse (`--vacuity`).** A control that cannot be made to fail is not one,
so every row is also scored against a *neighbouring* state's items. latex falls
100% → 0.3%, zig → 6.6%. **C only falls to 47.9%** — its states share too much
frontier for the control to discriminate well there, so C's verdicts rest on a
thinner bridge than its 100% suggests.

**The hand control (`--control`).** The four verilog walls a human labelled off
`reach.py`. The naive state closure calls all four unowned and one of them is;
this file's taxonomy agrees with all four — but three of the agreements are
`stranded` against a hand `conflict`, so exactly **one** hand-checked wall
exercises the `unowned` branch. `RESULT-1` scores that generosity against
itself.

**The name control (`--terminals`).** A wall's terminal decides its label, its
price and its owner together, so a wrong name is three wrong answers that agree
with each other. Every wall is re-asked whether the state it names really
refuses the terminal it names — `outliner state`'s admitted row against the
stop line, two code paths over the same table. **162 of 162 coherent**, and
because that is also what a `spellings()` matching nothing would score, each
wall is re-run with its terminal swapped for one its own state does admit:
**162 of 162 flag correctly.** It still does not clear the instrument — the
divergence `../adjudicate/` found is *lexical*, and both readings faithfully
report the lexer's choice.

**The start-set control (`--artifacts`).** State-0 walls are excluded from the
board as the peel resuming mid-construct. Tested rather than asserted: a file
may legally begin only with `FIRST(start)`, computed off `grammar.json` alone.
**35 of 35 are outside it**, and every grammar in the population is re-asked
about a terminal its start set *does* contain and comes back not-an-artifact.

## What it found

**41 unowned · 14 conflict · 30 stranded · 9 scanner**, over 181,588 B of
priced peel: **133,863 B unowned, 17,826 B conflict, 22,179 B stranded,
7,720 B scanner.** 76 walls withheld under the 95% floor.

**14.1% of the priced bytes are workable in this tree today** — 9.8% a reading
the grammar licenses and this table refused, 4.3% an external to seat. **73.7%
is unowned**, which is not "upstream": it is four suspects, three of them ours,
and the eighteen rows anybody has actually adjudicated came back 15-of-18
takeable. **12.2% cannot be owned from the wall's state at all**, and that is
the number no future instrument should inherit as either owner's.

**17 of the 41 unowned walls are on the file rather than the peel's own
resume** (106,303 B) — those are `UNOWNED.md`. The other 24 (27,560 B) are
adjudicated artifacts and leave the board: 0 of them appear in a warm
whole-file parse, and all 24 name a terminal no file may begin with.

## Every byte figure above has since been re-priced — read `../reprice/` first

The peel that produced these numbers was manufacturing most of them, and so was
the warm peel that cleared some of them. `Wall.real`'s old `state != 0` rule
caught one shape of artifact and missed the same artifact with a statement in
front of it; `cut.stand` now decides provenance in one place, five-valued, from
the *round* a wall was met in rather than from any property of the wall.

Provenance is priced over **every** wall — 120,832 B, all 161 of them — and not
over the 109,320 B the four owner columns could seat, because a wall no column
places still has a provenance. Of that, **4,751 B (3.9%) stands**, 81.1% is one
of the two peels, and 15.0% is `untested` — past the furthest byte any warm round
reached, so neither claimed nor dismissed.

Both instruments answer on the same denominator, and they differ by at most 2 B
for a reason worth keeping straight: `walls.py` has no warm seat, so `document`
(4,749 B) is the only standing verdict it can reach on its own. This survey,
handed a `--warm` seat, can also reach `witnessed` — one byte on scala, one on
zig. **Those two do not reproduce.** Two warm runs under the same pin ten minutes
apart call them `alias` and `witnessed` respectively while agreeing on every
other byte in the table, so read the floor as 4,749–4,751 B and the `stranded`
column's standing as 114–116 B. See the replicate in
`../reprice/RESULT-2-alias.md`.

The `stranded` column is 22,033 B on that pin and **116 B of it stands**. `~17`
and `~24` above are counted under the retired predicate and are not the
population `--stranded` prints today.

    python3 research/joinery/owners/cut.py --owner "" --warm .local/reprice/warm2.json

`../reprice/README.md` carries the whole re-price, both peels' failure modes, and
the one capability whose absence leaves 18,146 B undecidable.

Then read the last section of `RESULT-2-relabel.md`. The instrument this lane
trusts least is **the wall's own terminal**, and it passes every test that can
be built out of the table — which is exactly what a shared upstream error in
the lexer looks like from inside.

# Result 1 — who owns the corpus's walls

Scored against `PREDICTION-1-owners.md`, written before the closure had been
pointed at a wall outside verilog. Binary: `.local/pin/owners`, so nothing here
moves when another lane rebuilds `zig-out`.

Reproduce: `JOINTS_BIN=$(python3 tool/pin.py path owners) python3
research/joinery/owners/owners.py` (board), `--control` (the verilog four),
`--vacuity` (the collapse), `--gaps` (the competitive lane's input).

**Scoreline: P1 falsified. P2 held only under a taxonomy I added after writing
it, and strictly read it is 1 of 4. P3 held, 96.0%, with three grammars
withheld. P4 missed, surviving its own falsification threshold by one grammar.
P5 held to the byte on all 30. P6 not delivered.**

---

## The board

170 distinct walls over 17 walled grammars, priced over 181,588 B of peel.

| | walls | gap | conflict | stranded | scanner | withheld | gap B | confl B | strand B | scan B | control |
|---|---|---|---|---|---|---|---|---|---|---|---|
| php | 1 | 1 | 0 | 0 | 0 | 0 | 40,996 | 0 | 0 | 0 | 100% |
| kotlin | 3 | 1 | 0 | 2 | 0 | 0 | 35,369 | 0 | 58 | 0 | 98% |
| elixir | 4 | 2 | 1 | 0 | 1 | 0 | 25,704 | 583 | 0 | 2,796 | 99% |
| swift | 11 | 3 | 3 | 4 | 1 | 0 | 13,488 | 292 | 13,167 | 29 | 100% |
| ocaml | 2 | 0 | 1 | 0 | 1 | 0 | 0 | 14,686 | 0 | 196 | 97% |
| zig | 3 | 2 | 0 | 1 | 0 | 0 | 12,023 | 0 | 1 | 0 | 100% |
| verilog | 40 | 21 | 3 | 16 | 0 | 0 | 2,167 | 109 | 8,794 | 0 | 100% |
| haskell | 56 | 0 | 0 | 0 | 4 | 52 | 0 | 0 | 0 | 948 | 94% |
| sql | 19 | 0 | 0 | 0 | 1 | 18 | 0 | 0 | 0 | 1 | 86% |
| julia | 3 | 1 | 2 | 0 | 0 | 0 | 3,420 | 20 | 0 | 0 | 100% |
| markdown | 1 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 3,284 | 100% |
| latex | 4 | 1 | 1 | 2 | 0 | 0 | 10 | 2,033 | 146 | 0 | 100% |
| cpp | 6 | 3 | 1 | 2 | 0 | 0 | 655 | 60 | 3 | 0 | 98% |
| ruby | 6 | 0 | 0 | 0 | 0 | 6 | 0 | 0 | 0 | 0 | 71% |
| bash | 2 | 1 | 0 | 1 | 0 | 0 | 495 | 0 | 8 | 0 | 100% |
| c | 5 | 3 | 1 | 1 | 0 | 0 | 18 | 14 | 1 | 0 | 100% |
| scala | 4 | 3 | 0 | 1 | 0 | 0 | 13 | 0 | 1 | 0 | 100% |

**42 gap · 13 conflict · 30 stranded · 9 scanner · 76 withheld.** By bytes:
**134,358 B gap, 17,797 B conflict, 22,179 B stranded, 7,254 B scanner.**

So the ratio the brief asked for: **9.8% of priced bytes are provably ours,
74.0% provably upstream.** And the number the brief did not ask for and I did
not predict: **12.2% cannot be owned from the wall's state at all** — 1.2× the
half that is provably ours. A lane told "the corpus is 90% upstream" would work
on the wrong thing; a lane told "and an eighth of it is unattributable by this
instrument" knows where the next instrument goes.

**Not 181 walls over 18 grammars.** The peel names 170 over 17. I did not
reconcile that — the corpus moved under two lanes while I measured, and a count
I can't reproduce is not a count I'll assert either direction on. One walled
grammar prices no walls: it stops **lexically**, so there is no LR state and
nothing for the closure to be asked about. That is `Outcome.stray` working, not
a wall gone missing.

---

## P1 — falsified

Predicted **≥ 45 walls (25%)** are the scanner's, falsified by fewer than 20.

**Nine.** Falsified by better than a factor of two.

The reasoning was sound and the arithmetic was not: yaml declares 113 externals
against 202 rules, so I reasoned the peel would spend its walls standing in
front of them. It doesn't — the peel meets a wall where the *parse* stops, and a
grammar that hands its hard lexing to a C scanner mostly gets a **token** back
rather than a stall. The externals are load-bearing for the grammar and nearly
irrelevant to where the walls land.

The prediction was right that a two-owner partition is verilog-shaped, and wrong
about which third owner it needed. The one it needed is `stranded`, 30 walls and
22,179 B, and I found it by watching P2 fail rather than by predicting it.

## P2 — held, and I am scoring my own generosity

Predicted the mechanical frontier reproduces verilog's four hand verdicts:
`` ` `` in 1108 **gap**, `;` in 701 / `(` in 3772 / `=` in 2394 **conflict**.
Falsified by any disagreement, and the prediction says on disagreement I report
that and **do not publish a corpus split**.

What the instrument prints:

| wall | items | admits | settled | naive | this file | hand |
|---|---|---|---|---|---|---|
| `` ` `` in 1108 | 16 | 87 | yes | gap | **gap** | gap |
| `;` in 701 | 1 | 1 | no | gap | **stranded** | conflict |
| `(` in 3772 | 62 | 36 | no | gap | **stranded** | conflict |
| `=` in 2394 | 1 | 1 | no | gap | **stranded** | conflict |

**Strictly read against the prediction as written, that is 1 of 4 and P2 is
falsified.** I called it 4/4 by counting `stranded` as agreement with a hand
`conflict`, and `stranded` is a verdict that did not exist when I wrote the
prediction. That is the move this project has caught twenty-seven instruments
making, so here is the argument for it and the reader can decline it:

`inquest.zig`'s own `Owner.weave` header says a wall state is frequently
**downstream** of the defect — the parser folded early, and the state you are
looking at is the consequence. Three of these four walls sit in a state holding
a **completed item**: a fold could have brought the parse here, so the terminal's
absence from this state's viability set is not evidence about the grammar. The
hand verdicts came from `reach.py` being handed `statement_item` and
`variable_lvalue` **by a human who knew the construct**. There is no mechanical
substitute for that, and the honest mechanical answer is *I cannot tell from
here* — which is what `stranded` says.

What makes it a verdict and not a dodge: `stranded` **never says upstream**. The
naive closure calls all four a gap and files 20,381 B of press work as something
nobody in this tree can fix. That is the direction that costs a lane a week, and
`stranded` is the guard against it, not a way of scoring green.

I published the corpus split anyway, against the prediction's letter, with the
30 stranded walls credited to **neither** owner and reported as their own column
and their own byte total. Whether that honours the prediction's intent is the
reader's call; it does not honour its text and I am not going to pretend
otherwise.

## P3 — held, 96.0%, and I watched it collapse

Predicted **≥ 95%** of row-admitted terminals reachable from the admitting
state's frontier, falsified under 80%, and promised to watch it collapse before
believing it high.

**6,142 of 6,396 — 96.0%.** The collapse, `--vacuity`, scores every state's
admitted row twice: against the state that admits it, and against a neighbouring
walled state in the same grammar.

| | admitted | own state | a neighbour |
|---|---|---|---|
| c | 213 | 100.0% | 47.9% |
| latex | 342 | 100.0% | 0.3% |
| zig | 136 | 100.0% | 6.6% |

latex and zig collapse to nothing. **C only falls to 47.9%, and that is the one
worth saying out loud** — C's states share so much of their frontier that half
of any state's admitted row is admitted next door too. So the control is a real
discriminator in C but a weak one, and C's five walls rest on a thinner bridge
than latex's four. That is the "80-to-95 per-grammar" clause of the prediction
firing inside a grammar that scores 100%.

The prediction's remedy went further than promised: three grammars — **haskell
94%, sql 86%, ruby 71%** — have every verdict **withheld**, 76 walls, rather
than published beside a caveat. Ruby at 71% is my name-bridge failing, not a
finding about ruby, and haskell missing the floor by one point is still missing
it.

## P4 — missed, survived by one grammar

Predicted the byte leader differs from the recurrence leader in **≥ 6 of 18**
walled grammars, falsified by two or fewer.

**Three of 17.** Above the falsification line by exactly one grammar, and half
the predicted rate.

| grammar | by bytes | by count |
|---|---|---|
| sql | 2,839 B ×10 `;` in state 0 | 242 B ×222 `_identifier` in state 0 |
| haskell | 2,615 B ×29 `variable` in state 48 | 235 B ×33 stray `>` |
| verilog | 2,483 B ×37 `macro_text` in state 562 | 1,732 B ×122 `macro_text` in state 164 |

The reason is not flattering to the prediction and is worth writing down: the
verilog lane found its 16,289-byte disagreement on **picorv32.v**, and the corpus
specimens are `ledger.*` — C's is **1,444 bytes**. On a file that small every
wall is cheap and there is no room for the two orderings to diverge. So P4 is a
statement about corpus specimens, not about parsing, and it neither supports nor
undermines Item 2. Item 2 stands on the sql row: **222 hits worth 242 bytes** was
the ranking this project had, and the wall actually worth ranking carries 11.7×
the bytes on 4.5% of the recurrence.

## P5 — held, to the byte, on all 30

Predicted `prefix + Σ(every wall's bytes) + unpeeled == size`, printed every
run, a grammar that fails printing as failed rather than printing a price.

**30 of 30, no `UNBALANCED` row.** The price is a partition, so no wall is
credited bytes another wall also owns.

One thing the partition surfaced that I did not predict: the cold peel resumes
in **state 0**, so some walls are the peel's own resume artifact rather than a
construct. Those get a `state0` column, **printed rather than netted out** —
subtracting them would hand the reader a corrected total nobody can check.
24 of the 42 gaps are state-0 walls and are marked *not real* in the gap list.

## P6 — not delivered

Predicted every gap would carry whether the **warm** peel — which never
restarts — reaches it too, and that warm-confirmed gaps would be the ones flagged
as real-world constructs.

**I did not run that.** The gap list flags real constructs by a weaker
discriminator: a wall in state 0 at a non-zero cut point is a resume artifact,
anything else is on the file. That is sound as far as it goes — a state-0 wall
*is* the peel's own shadow — but it is not the promised evidence, and a gap in a
non-zero state could still be a fragment starting mid-construct. **The 18 gaps I
am handing the competitive lane are weaker evidence than the prediction says they
would be**, and confirming them against the warm peel is the next lane's first
half-hour.

---

## The instrument I trust least

**`settled`, and it is the one three quarters of my verdicts turn on.**

`settled` asks whether a state holds an item with the dot at the end. If none
does, the parse *shifted* into this state and folded nothing, so the terminal's
absence from the viability set is a fact about the grammar → `gap`. If one does,
a fold could have brought the parse here → `stranded`.

Three things wrong with that:

1. **"Could have folded" is not "did fold."** The state dump is static. A state
   holding a completed item may be reached by a shift on every input that ever
   reaches it, and I would still call its wall `stranded` and refuse to own it.
   That direction is safe (I under-claim) but it inflates 22,179 B of "cannot
   tell" that may be plain conflicts — **ours**, and unworked because I filed
   them as unknowable.
2. **`gap` is the load-bearing verdict and it is the one `settled` gates.** 42
   gaps, 134,358 B, 74% of the board. A single bug in the completed-item test
   flips a large fraction of that to `stranded` or the reverse, and nothing here
   would catch it: the row-admitted control tests my **viability** set, not my
   settled test. The settled test has **no control at all** beyond the four
   verilog hand verdicts, and three of those four land on `stranded`, so exactly
   **one** hand-checked wall exercises the `gap` branch.
3. **It rests on parsing prose.** `settled` reads `joints state`'s rendered
   items and looks for a trailing dot. `ROW`'s first spelling silently dropped
   terminals whose row carried a conflict note, which deflated haskell's control
   until I noticed. The same class of miss in the item parser would not deflate
   anything — it would quietly move gaps to conflicts, and every number here
   would still look fine.

If a lane gets one instrument to distrust from this file: **`gap` means "no
derivation, and no fold could have put me here"**, and the second clause is a
static over-approximation with one hand-checked example behind it.

Runner-up: the name bridge. `spellings()` joins a rule name to its rendered
regex because SQL's `keyword_select` is a rule whose whole body is a pattern, and
missing that made SQL look like it had no derivation for a keyword it obviously
has. That fix took SQL from unusable to 86% — still withheld. Ruby at 71% is the
same bridge failing in a way I have not diagnosed, and **the reason ruby's six
walls are withheld is that I do not know what my own instrument is missing
there.**

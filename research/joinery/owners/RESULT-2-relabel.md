# Result 2 — every wall relabelled, and what the relabelling did not do

Predictions in [`PREDICTION-2-relabel.md`](PREDICTION-2-relabel.md), written
before the fix was applied and before anything was run.

**Pin.** `.local/relabel/joints`, sha256 `7aa79135a2bb…`, built from tree
`5a91974c4`, repo `f7ba40004`+114 dirty, run 2026-08-06T01:39Z. It is a private
copy: `zig-out/bin/joints` is shared with ten lanes and a rebuild renumbers
the LR(0) collection, so the binary was copied out and every command below ran
under `JOINTS_BIN`. `standing.py` stamps the run `TOLD` and `STALE` for
exactly that reason, and both are correct — `src/kernel/weave/weave.zig` is
newer than my binary because another lane is editing it right now.

This pin reports **verilog 9,763 states**, which is the same collection the
owners lane measured on. That is luck, not method, and it is why the comparison
below is legitimate at all.

---

## The peel reproduced, which is the precondition for everything else

`walls.py run --json` over the thirty: **170 distinct walls, 17 walled
grammars, 181,588 B priced** (193,100 B priced in total across all rows,
105,176 B unpeeled). The survey JSON is **byte-identical** to the previous
lane's. So I am relabelling the board that exists, not one that moved under me,
and the retraction condition I wrote down did not fire.

## What the fix moved: one wall, 495 bytes

Two walls changed owner in total, in opposite directions, and both are fully
accounted:

| wall | bytes | was | is | why |
|---|---:|---|---|---|
| bash `] in state 35` | 495 | `gap` | `scanner` | `]` is one of bash's six literal-declared externals, dropped by the named-only census |
| swift `_implicit_semi in state 398` | 29 | `scanner` | `conflict` | state 398 *derives* it; the old ordering let the name lookup beat the derivation |

Nothing else. 524 bytes of 181,588, **0.29% of the peel**, over 2 of 170 walls.

### The prediction the brief said this rehabilitates, scored

The owners lane predicted **≥ 45 scanner walls** and found **9**, scoring it
falsified by better than 2×. With literal-declared externals restored the count
goes to **10**. Predicted ≥45, got 10: falsified 4.5× where it was falsified
5.0×.

The brief asked me to say by how much the fix rehabilitates it. **By almost
nothing.** And after the ordering repair beside it the scanner column is back
to **9 walls**, so on the board as published the fix rehabilitates it by zero.
The prediction was not wrong because of the census bug; it was wrong because
`scanner` is a small verdict on this corpus and the lane over-estimated it 5×.

---

## The corrected board

Ranked by **`crooked`** — bytes built and confidently wrong, `standing.py`'s
default since it began exceeding `damage` on eight rows. Owner bytes are the
peel's price.

| grammar | crooked | damage | walls | unowned B | conflict B | stranded B | scanner B | withheld |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| php | 25,394 | 8,699 | 1 | 40,996 | 0 | 0 | 0 | 0 |
| elixir | 17,660 | 1,559 | 4 | 25,704 | 583 | 0 | 2,796 | 0 |
| swift | 8,063 | 5,337 | 11 | 13,488 | 321 | 13,167 | 0 | 0 |
| ocaml | 2,113 | 2,182 | 2 | 0 | 14,686 | 0 | 196 | 0 |
| haskell | 2,023 | 25,048 | 56 | 0 | 0 | 0 | 948 | 52 |
| scala | 1,938 | 4,150 | 4 | 13 | 0 | 1 | 0 | 0 |
| latex | 1,061 | 1,185 | 4 | 10 | 2,033 | 146 | 0 | 0 |
| kotlin | 848 | 246 | 3 | 35,369 | 0 | 58 | 0 | 0 |
| cpp | 603 | 411 | 6 | 655 | 60 | 3 | 0 | 0 |
| julia | 160 | 1,953 | 3 | 3,420 | 20 | 0 | 0 | 0 |
| ruby | 130 | 532 | 6 | 0 | 0 | 0 | 0 | 6 |
| bash | 75 | 413 | 2 | 0 | 0 | 8 | 495 | 0 |
| zig | 10 | 1,375 | 3 | 12,023 | 0 | 1 | 0 | 0 |
| verilog | 0 | 63,937 | 40 | 2,167 | 109 | 8,794 | 0 | 0 |
| sql | 0 | 2,423 | 19 | 0 | 0 | 0 | 1 | 18 |
| markdown | 0 | 3,126 | 1 | 0 | 0 | 0 | 3,284 | 0 |
| c | 0 | 572 | 5 | 18 | 14 | 1 | 0 | 0 |
| **all** | | | **170** | **133,863** | **17,826** | **22,179** | **7,720** | **76** |

Control: the closure derived **6,142 of the 6,396** terminals these states
already admit (96.0%). haskell, ruby and sql fall below the 95% floor and have
their 76 state verdicts withheld rather than reported. The four verilog hand
verdicts agree **4/4**.

### Old and new side by side, so nobody reads an inverted split

| | walls | bytes | share | | walls | bytes | share |
|---|---:|---:|---:|---|---:|---:|---:|
| `gap` | 42 | 134,358 | **74.0%** | → `unowned` | 41 | 133,863 | **73.7%** |
| `conflict` | 13 | 17,797 | **9.8%** | `conflict` | 14 | 17,826 | **9.8%** |
| `stranded` | 30 | 22,179 | 12.2% | `stranded` | 30 | 22,179 | 12.2% |
| `scanner` | 9 | 7,254 | 4.0% | `scanner` | 9 | 7,720 | 4.3% |

**The board did not move, and that is the finding.** The brief describes a
split inverting from 9.8% ours / 74.0% upstream to 72.6% workable / 0.03%
upstream. That inversion is real but it is **the adjudicating lane's**, not
this one's: it comes from putting eighteen rows in front of tree-sitter, and it
covers those eighteen rows. Applying the withheld fix and relabelling all 170
walls moves 524 bytes.

What actually changed is what the largest column *claims*. It said *no LR
parser over this grammar takes it here*. It now says: this table found no
reading, four things produce that, three of them ours. 73.7% of the corpus went
from "somebody else's problem" to "unadjudicated", which is a different
sentence about the same bytes and the only one the test supports.

**Workable-here, honestly bounded.** `conflict` + `scanner` = 25,546 B,
**14.1%** — those are proven now, from this instrument alone. The 72.6% figure
requires extrapolating the adjudicating lane's 15-of-18 hit rate across the
whole `unowned` column, and eighteen rows chosen as the largest gaps are not a
random sample of forty-one. I am not extrapolating it; the honest statement is
14.1% proven workable and 73.7% unadjudicated with a strong prior that most of
it is ours.

### Ranking on `crooked` is right for the board and wrong for this lane

The brief says rank on `crooked`. Done above, and it puts the money first —
php, elixir and swift hold 80,208 B of walls. But two things have to be said
next to it.

**`crooked` is blind to verilog, which carries 40 of the 170 walls, 21 of the
41 unowned and 16 of the 30 stranded.** verilog's crooked is **0** and its
damage is **63,937** — its bytes are `spoil`, never built, and `crooked` is a
claim about bytes that *were* built. Ranking this lane's populations on crooked
alone buries the grammar that dominates them. The honest work order is
two-keyed: crooked for what is confidently wrong, damage for what never got
read, and they disagree by 14 places on verilog.

**`crooked`'s tail does not reproduce.** I read scala at **1,938**. The brief
reports the same pin reading **1,278** in one run and **9,087** in the next.
Three runs, three values. The top three (php 25,394, elixir 17,660, swift
8,063) are an order of magnitude above the unstable band and survive it; below
about 2,000 the column is not evidence. My audit is cached (`kept 30`, 27 of 30
rows graded) and I did not re-run it, because `rack.py` belongs to a lane
mid-repair on exactly this.

---

## The two unresolved populations

### 27,560 bytes of state-0 artifacts — they are artifacts. Verdict: close it.

Excluded for two lanes on an untested assertion. Two independent tests now,
`owners.py --artifacts` and `--terminals`:

- **From the grammar.** State 0 is the start state, so a file may legally begin
  only with `FIRST(start)`, computed over `grammar.json` and never consulting
  our table. **35 of 35 excluded walls are outside it** (31,475 B over all
  owners; the `unowned` subset is exactly the 24 walls / 27,560 B in question).
  Anti-vacuity: every one of the seven grammars in the population is re-asked
  about a terminal its start set *does* contain and all seven come back NOT an
  artifact — it discriminates inside a single grammar, sql `)` artifact vs sql
  `(` opener, verilog `$` artifact vs `$unit` opener.
- **From the parser.** A warm whole-file parse never restarts, so a state-0
  wall it reports verbatim would be real. Over the five grammars carrying all
  27,560 B: **0 of 24.** Each stops elsewhere — scala `"` in 610, swift `)` in
  141, verilog `` ` `` in 3438, zig `{` in 715, cpp `"` in 907 — and every one
  matches the damage line `standing.py` independently prints for that row.

The exclusion is right. 27,560 B leave the board and the `unowned` column's
real content is **17 walls / 106,303 B**.

### 22,179 stranded bytes — they need a query this tree does not have

By whole completed item the population is 22 items with 14 singletons, which
reads as *thirty separate problems*. By the **body** the fold is over, the top
two carry **71%** and the top three **88%**, over nine walls. I wrote the first
conclusion before regrouping and it was wrong.

| fold body | walls | bytes | folded as |
|---|---:|---:|---|
| swift `_top_level_statement _semi` | 1 | 9,160 | `source_file` |
| verilog `_identifier` | 8 | 6,591 | `class_type`, `data_type`, `net_decl_assignment`, `variable_decl_assignment` |
| swift `_top_level_statement source_file_repeat1 _semi` | 1 | 3,896 | `source_file` |
| verilog `[ constant_range ]` | 4 | 1,650 | `packed_dimension`, `unpacked_dimension` |

Eight verilog walls folding a bare `_identifier` under four competing left-hand
sides is **one reduce-reduce family wearing eight faces**, and it was invisible
as four separate item rows.

**What it needs:** an item-indexed inverse query — which states can reach this
fold — and then a fold chain from the wall back to the state that committed.
Neither exists. `state` takes a state number or `--census <terminal>`;
`--census` is indexed by terminal and cannot ask this. **`--holding` has never
been in this tree** — it is not in the binary and `git log -S'--holding' --
src/` returns no commit. `inquest` agrees from the other side on every `press?`
line: *"no fold chain was supplied to say whether this wall is downstream of
it"*. Until one of those exists the population stays where it is; when one
does, 71% of it is two questions.

---

## The instrument I trust least, and the demonstration

Inherited: **the wall's own terminal.** Four of eighteen witnesses refused a
different terminal than `GAPS.md` named, and `verilog-sized` is named after a
construct that parses whole. A wrong terminal makes the label, the price and
the owner wrong together, and they agree with each other while being wrong.

So I re-derived rather than inherited. `joints state` prints the terminals a
state's row **admits** — those are cells, not opinions — and `unexpected T in
state N` is the claim that `T` is not among them. Different code paths over the
same table, so they can disagree.

**162 of 162 state walls are coherent. 0 incoherent.**

That result is worth exactly nothing on its own, because a `spellings()` that
matched nothing scores 100% too. So every wall is re-asked with its terminal
swapped for one its own state does admit, and the check must flag all of them:
**162 of 162 flag correctly.** It can say no.

**And it still does not clear the instrument.** 100% coherence rules out one
failure mode — stale state numbers, a mis-parsed stop line, a wall keyed to a
build that renumbered — and rules out nothing about the mode that actually bit.
The adjudicating lane's finding was that in 5 of 18 walls *the refused terminal
is not in the program at all*: the lexer chose it, under a per-position admitted
set, and both the stop line and the state row faithfully report the lexer's
choice. My check reads both of those and cannot see between them. It is
consistent, and consistency is what a shared upstream error looks like.

The honest narrowing: the divergence is **lexical, not tabular**, and catching
it needs a third arm that reads the program's bytes — which is what
`../adjudicate/` is and why it cost a lane a week for eighteen rows.

---

## Predictions, scored

| | claim | outcome |
|---|---|---|
| **P1** | ≥1 wall moves from a verdict other than `gap` **into** `scanner` | **falsified.** Zero did. The only non-`gap` move went the other way, `scanner`→`conflict`. My named candidate, ocaml's `"`, did not touch its 14,686 B conflict. |
| **P2** | ≤5 walls change owner; bytes moved in [495, 20,000] | **held** — 2 walls, 524 B. Weakly: the 495 floor was already demonstrated and the interval was 39× wide, so only the ≤5 bound carried content. |
| **P3** | ≥1 wall is both blind-hit and viable | **held.** swift `_implicit_semi in state 398`. This is the one that produced a real repair. |
| **P4** | ≤3 of the 24 state-0 walls appear in a warm whole-file parse | **held at 0 of 24**, over all five grammars carrying all 27,560 B. |
| **P5** | ≥90% terminal agreement with the previous survey **and** ≥1 grammar renumbers | **1 of 2.** Terminal agreement is 100% — the survey is byte-identical. Zero grammars renumbered; my pin shares the owners lane's 9,763-state collection. I predicted the instability the brief warned about and did not observe it. |
| **P6** | peel-byte top-5 differs as a set from `crooked`'s and from `damage`'s | **held, narrowly.** Peel {php, kotlin, elixir, swift, ocaml} vs crooked {php, elixir, swift, ocaml, haskell} — differs by one member. vs damage {verilog, haskell, yaml, php, swift} — differs by three. Against `crooked` this is much weaker than the prediction's spirit. |
| **P7** | for ≥2 of the 5 dearest stranded walls, `--holding` names exactly one state | **unscored — unrunnable.** The flag does not exist and never has. The prediction was written off the brief without checking the binary, which is the error this lane is supposed to be immune to. |

**4 held, 1 falsified, 1 partial, 1 unscored.** P2 and P6 both held in a way I
would not defend hard: P2's interesting half was pre-demonstrated, P6 cleared
its bar by one set member.

## Where I contradict the brief

1. **The fix does not rehabilitate the ≥45-scanner prediction.** 9 → 10 walls,
   and back to 9 after the ordering repair. 5.0× falsified → 4.5×.
2. **The fix as written down is incomplete.** `type in ("SYMBOL", "STRING")`
   still drops two `PATTERN` externals — bash's and haskell's `\n`, both walled
   grammars. 23 declarations across 9 grammars, not 21 across 8. Enumerating
   the shapes someone has already met is how the original line got it wrong.
3. **`joints state --holding` does not exist**, has never existed, and is the
   named technique for the largest population I was asked to resolve.
4. **Relabelling did not invert the split.** 524 bytes moved. The inversion is
   the adjudicating lane's over eighteen rows; extrapolating it to 72.6% of the
   corpus treats a sample chosen for being the largest gaps as a random one.
5. **Ranking on `crooked` alone buries verilog**, which carries 24% of the
   walls and 40% of the stranded bytes at crooked 0.

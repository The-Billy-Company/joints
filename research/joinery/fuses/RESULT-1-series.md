# RESULT-1 — every capacity constant, re-read for series

Scored against `PREDICTION-1-series.md`, written before any arm was built.

**The headline is a negative and it is the useful kind: the four runtime fuses
are saturated where they stand.** `crowd`/`skeins`/`climb`/`chase` were raised
eight-fold, four-fold, and jointly, seven arms on one tree against one frozen
oracle, and every board is byte-identical to the control at **309,356 square
without verilog**. There is no more free money behind the pair that sent me
here. The lane before me took all of it.

The money that *is* still on the floor is on the cost axis, in the survey, and
it is the same defect with the sign flipped.

---

## 1. What was measured

Nine pins, all built from `f7ba40004+135`/`+136`, each with its own folio cache
and its own audit, every board taken against the frozen `limb` oracle so the
reference cannot drift between arms. Control pinned after the arms.

| arm | `crowd` | `skeins` | `climb` | `chase` | square (no verilog) | Δ |
|---|---|---|---|---|---|---|
| `g-control` | 64 | 512 | 8 | 32 | **309,356** | — |
| `g-crowd512` | **512** | 512 | 8 | 32 | 309,356 | 0 |
| `g-skeins4096` | 64 | **4096** | 8 | 32 | 309,356 | 0 |
| `g-both-hi` | **512** | **4096** | 8 | 32 | 309,356 | 0 |
| `g-climb32` | 64 | 512 | **32** | 32 | 309,356 | 0 |
| `g-chase128` | 64 | 512 | 8 | **128** | 309,356 | 0 |
| `g-walk-both` | 64 | 512 | **32** | **128** | 309,356 | 0 |
| `g-cripple` | **4** | **4** | 8 | 32 | 199,019 | **−110,337** |
| `g-crawl` | 64 | 512 | **1** | **2** | 165,477 | **−143,879** |

Six arms moved nothing. That is exactly what a harness reading the wrong binary
looks like, so it does not count until something moves it.

**The positive controls are the whole result's licence.** `g-cripple` and
`g-crawl` are the same rig, the same oracle, the same script, and they move the
board by 110,337 and 143,879 square bytes. The instrument responds to these four
constants; the six flat arms are flat because the constants are flat.

## 2. Why they are flat — the denial census

A cap that refuses nothing cannot be costing anything, and this is one command
rather than an arm. Splits and denials per grammar at 64/512, read out of the
parse's own trace:

**Twenty-nine of thirty grammars deny nothing at all.** The whole corpus's
refusals are swift's 80 out of 987 splits — and all 80 are the same state on the
same token at byte 24283 in `value_argument_repeat15`. One fold storm, not a
starved parse.

Then the pair is separated, which no previous measurement had done:

| arm | swift splits | swift denied | swift square |
|---|---|---|---|
| `g-control` (64/512) | 987 | **80** | 14,419 |
| `g-crowd512` | 1083 | **0** | 14,419 |
| `g-skeins4096` | 987 | **80** | 14,419 |
| `g-both-hi` | 1083 | **0** | 14,419 |

`crowd` is the live fuse and `skeins` is slack everywhere on today's board.
`crowd = 512` clears every denial and opens **96 more readings that are worth
zero square**. That is the cleanest statement of saturation available: the cap
binds, un-binding it works, and the thing behind it is empty.

## 3. The other side of the trade

Corpus parse time from pre-minted folios, best of three, and peak RSS:

| arm | time | peak RSS | square |
|---|---|---|---|
| `g-control` | 1.000x | 1.000x | 309,356 |
| `g-both-hi` (512/4096) | 1.021x | 1.000x | 309,356 |
| `g-walk-both` (32/128) | 0.995x | 0.998x | 309,356 |
| `g-cripple` (4/4) | **0.777x** | — | 199,019 |

The knee is where it stands. Below it the curve is a cliff — 22% of the parse
time is buying 110,337 square bytes. Above it the curve is flat to 2%. What
stops these rising further is that there is nothing above them, not the cost;
and what stops them falling is that everything is below them.

## 4. Where the defect actually still lives — the survey trio

`limb_ceiling` × `spawns` are in series by construction (`spawns × limb_ceiling`
is the birth budget) and were swept one at a time. Go's survey, per corner:

| limbs | churn | time | survey reported |
|---|---|---|---|
| 256 | 4096 | **1.09 s** | rank 18 · 1 residue · 4/8 chains · 4 refused |
| 256 | 65536 | 1.32 s | *identical* |
| 256 | 262144 | 1.35 s | *identical* |
| 1024 | 1024 | 3.40 s | *identical* |
| 1024 | 65536 | **99.5 s** | *identical* |
| 4096 | 4096 | **251.6 s** | *identical* |
| 4096 | 65536 | **killed at 40 min** | — |

Every corner reports the same survey. The entire curve is cost with no answer
behind it, and **one knob cannot see it**: churn alone is 1.09 → 1.35 s and
reads free, while churn with the ceiling already up is 3.4 → 99.5 s. The
comment on `limb_ceiling` recorded "a second into ninety" from the cheaper
fuse; the real corner is past forty minutes.

`fan_ceiling` is a third axis and is *not* in series with those two: 256 costs
3x and moves worst rank 18 → 43 regardless of the other two. It is also the
only one of the three that changes the survey at all, and it changes it for the
worse.

## 5. Scoring the prediction

| Predicted | Outcome |
|---|---|
| A — `climb`/`chase` in series | **Right**, and by a mechanism I had backwards. I predicted a wider budget would be permissive; it is *stricter* (three `return false` arms before the permissive exit), which is why the failure mode is a cliff below rather than a gain above. |
| A — 32/128 byte-identical to control ⇒ arm vacuous | **Right that it is identical, wrong that this makes it vacuous.** The positive controls turn the same identity into evidence of saturation. An unmoved board is only vacuous while nothing has shown the board can move. |
| B — more free money above 64/512 | **Wrong.** Zero on every corner. I expected swift's 80 denials to be worth something; they are worth nothing. |
| `skeins` is the slack one | Not predicted; found. |
| Survey trio in series | **Right**, and it is the only place the defect survives — in the cost direction, where a one-knob sweep *understates* rather than overstates. |
| `rounds`/`growth` coupled, `rounds` a dead knob | Half right: `rounds` is dead at `growth = 4` but live at 1 and 2, and every grammar reaching round 2 builds an automaton it discards (swift 8,408 states, ocaml 6,825). Priced but not repaired — that is a press lane's call. |

## 6. The instrument I trust least

**`pin.py arm`, and passing its own check is exactly the problem.**

Every arm in this dossier printed `oracle: NONE` and every `rack` board written
in that state came back with `square` at 0 on all thirty rows — and zero is also
what a board prints when a grammar agrees perfectly, so nothing about the output
says which one you are looking at. The banner does warn, on stdout, in a comment,
inside a string a lane is *supposed* to pipe into `eval`. I read past it once
already and spent a batch of boards on it.

What did not clear it: `arm` succeeded, exit 0, three exports correct. Its own
check is about the exports, and the failure is one directory over. What cleared
it was minting the oracles and watching a number appear that had been absent —
which is a falsifier I had to know to run.

The same shape is why §1's six flat arms needed §1's two crippled ones. A board
that did not move is indistinguishable from a board that was never connected,
and only a treatment known to move it can tell you which you have.

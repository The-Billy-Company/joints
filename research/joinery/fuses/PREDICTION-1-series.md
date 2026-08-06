# Prediction 1 — which of the other fuses are in series, and what each corner pays

Written before any arm was built or any board taken in this lane. Everything
below is derived from reading the source, which is the standard the
`crowd`/`skeins` finding set: that pair was readable before it was measurable,
and the sweep that missed it did so by measuring instead of reading.

## The inventory

Twenty-two capacity constants. I take a constant to be a *capacity* when it
bounds a quantity the program produces rather than describing the data — so
`folio/leaf.zig`'s `header_len = 96` is a format, not a fuse, and
`lex/scry.zig`'s `css_colon = 1` is an index.

| # | Constant | Where | Value | Comment cites a measurement? |
|---|---|---|---|---|
| 1 | `crowd` | `kernel/quire/gather.zig:355` | 64 | yes — **already repaired**, four-corner |
| 2 | `skeins` | `kernel/quire/gather.zig:371` | 512 | yes — **already repaired**, four-corner |
| 3 | `fuse` | `kernel/quire/gather.zig:391` | 3 | yes — "where the measurement separates" |
| 4 | `whole` | `kernel/quire/gather.zig:392` | 4 | (denominator of 3) |
| 5 | `climb` | `kernel/quire/gather.zig:1587` | 8 | **no** — never swept |
| 6 | `chase` | `kernel/quire/gather.zig:1588` | 32 | **no** — never swept |
| 7 | `rounds` | `press/press.zig:63` | 4 | yes — "no grammar tried has improved twice" |
| 8 | `growth` | `press/press.zig:77` | 4 | yes — "smallest multiple that fits the cut ruby stops on" |
| 9 | `lr0.Options.ceiling` | `press/lr0.zig:170` | 1<<19 | no — a seatbelt, overwritten after round 0 |
| 10 | `fold.fan_budget` | `press/fold.zig:37` | 1024 | yes |
| 11 | `spread.seq_budget` | `press/spread.zig:47` | 1024 | yes — "typescript's worst is 768" |
| 12 | `lexeme.max_depth` | `press/lexeme.zig:24` | 32 | no |
| 13 | `Spent.ceiling` | `kernel/lex/outside.zig:1502` | 256 | yes — sized off the three lex stacks |
| 14 | `Spent.cohort` | `kernel/lex/outside.zig:1503` | 8 | yes |
| 15 | `Columns.max` | `kernel/lex/offside.zig:205` | 96 | yes |
| 16 | `Tags.max` | `kernel/lex/lineage.zig:103` | 64 | yes |
| 17 | `Spans.max` | `kernel/lex/fence.zig:105` | 16 | yes |
| 18 | `bough.stride` | `kernel/quire/bough.zig:147` | 32 | yes |
| 19 | `bough.budget` | `kernel/quire/bough.zig:148` | 1<<18 | yes |
| 20 | `limb_ceiling` | `kernel/joint/cursor.zig:112` | 256 | yes — "a ceiling ten times higher buys no answer" |
| 21 | `spawns` | `kernel/joint/cursor.zig:139` | 16 | yes — "where the answer stops changing" |
| 22 | `fan_ceiling` | `kernel/joint/reverse.zig:63` | 64 | yes — "raising it does not buy answers" |

Two more that are knobs but not fuses: `tidemark` (16, a *threshold* — when to
start collapsing, not how much is allowed) and `entry_sample` / `residue_ceiling`
in `joints.zig` (a sample size and a runaway detector).

## The reduction

A full grid over twenty-two knobs is 2^22 corners at two values each. The
reduction is the same one `crowd`/`skeins` would have yielded to a reader:
**two constants are in series when one bounds a quantity the other consumes.**
That relation is visible in the code, and it partitions the twenty-two.

### First cut: what can move `square` at all

`square` is agreement with the oracle over a **cold parse** of a corpus file.
The reachable path is `press → lex → quire.gather`. That deletes:

- **#20, #21, #22 and `tidemark`** — `cursor.zig` and `reverse.zig` are imported
  by `root.zig` and by `surface/face/outliner/joints.zig`, and by nothing on the
  parse path. `gather.zig` imports neither. They are the rung-1 **survey
  instrument**. They still get audited below, on the survey's own numbers,
  because two of the three carry a demonstrably one-knob comment — but no arm of
  theirs can move a board.
- **#18, #19** — `bough` snapshots for incremental re-parse. A board parses each
  file once, so `stride` and `budget` are priced in re-parse cost, not `square`.
- **#9** — `lr0.Options.ceiling` is overwritten from `growth` after round 0. It
  is #8 wearing a different name.

Nine remain on the square path: `crowd`, `skeins`, `fuse`/`whole`, `climb`,
`chase`, `rounds`, `growth`, and the two press budgets.

### Second cut: which of those nine share a fuse

| Set | The shared quantity | Series? |
|---|---|---|
| `crowd` × `skeins` | a fork needs a slot **and** a strand | **yes, an AND** — already priced |
| `climb` × `chase` | one `shiftable` walk | **yes, partial** — see below |
| `rounds` × `growth` | how much automaton the unfolding search may spend | **yes** — see below |
| `fuse`/`whole` × `crowd` | mends demanded, not mends allowed | no — coupled, not in series |
| `fold.fan_budget` × `spread.seq_budget` | different phases, different quantities | no |
| `Spent.ceiling` × `cohort` × the three lex stacks | zero-width hands at one offset | **yes** — documented as such in the source |

Six sets from twenty-two knobs, of which three are worth an arm.

## The three arms, and what I expect each to pay

### A — `climb` × `chase`, and the cost fuse nobody has named

Neither has a measurement in its comment, and they sit in the hottest loop in
the parser. `offer` runs `shiftable` once **per terminal per live reading per
token**; each `shiftable` is up to `chase` table reads.

They are in series, but not as an AND — they bind on *different shapes*. Per
reduce, `ups → ups − min(ups, n) + 1`. So `ups` grows only where a production
consumes fewer stack cells than the virtual stack already holds, which means
`climb` is reachable only down a chain of epsilon-ish reductions, and `chase` is
reachable only down a long chain of real folds. A one-knob sweep over either
would have found *partial* saturation, not total.

Both fail **open**: past the bound the answer is "yes, shiftable". Every blown
fuse therefore *widens* the set handed to the scanner, and the file's own
argument for the loop existing is that a widened set is how "a greedy whitespace
or content pattern out-matches the token that was really there". So raising the
bounds narrows the set toward the truth.

**Prediction.** 32/128 buys **positive square**, total across the corpus in the
range **0 to +3,000 bytes**, with **most grammars at exactly 0** because most
stacks resolve inside 8/32 and never touch either bound. I hold ~55% that the
total is nonzero and ~20% that it clears +3,000.

**The cost fuse, and this is the finding I most expect to stand up.** `offer`
costs `live × terminals × chase` table reads per token, and `live` is bounded by
**`crowd`**. So `crowd` and `chase` are in series *on the cost axis* while being
independent on the correctness axis. The previous lane took `crowd` from 8 to
64 — an 8× rise in the worst-case width of the hottest loop in the parser — and
its dossier prices the *benefit* in square bytes and the *cost* only as "a
strand is allocated when a fork opens, not reserved", which is `skeins`' cost,
not `crowd`'s. **I predict the board's wall-clock rose at that landing and no
one measured it**, and that this, not the byte count, is where the knee is.

### B — `rounds` × `growth`

`rounds = 4` is, I claim, a **dead knob**. The loop runs `rounds + 1` times but
breaks the first time a round is `!better`, and the comment itself says every
grammar improves once and none twice — so the break fires at round 1 and the
bound at 4 is never approached. Raising `rounds` alone therefore buys **exactly
zero**, and I hold ~90% on that.

`growth` is the live fuse, and it is frozen wrong:

```zig
if (best == null) {
    ceiling = @max(4096, growth * @as(u32, @intCast(round_result.collection.states.len)));
}
```

`best == null` is true only on round 0, so the ceiling is `growth × |S₀|` for
*every* later round. Round 2 stands on `|S₁| > |S₀|` and is allowed
`4 × |S₀|` — an effective multiple that shrinks every round, toward 1. A later
round that cannot grow cannot improve, and `dare /= 2` truncates its plan until
it fits. **"None of them improves on any later one" was measured under a ceiling
that forbade a later one from trying.** That is the `crowd`/`skeins` shape
exactly: the observation is real and the inference from it is not.

**Prediction.** At `--growth=32`, **at least one grammar improves on round 2**,
which falsifies the sentence in `rounds`' comment. Confidence 40% — deliberately
under half, because the alternative story (the search really is one-step and a
disagreement the lookaheads cannot reach in one step is unreachable in this shape
at any ceiling) is the one the file argues and it is a good argument. If no
grammar improves twice at growth 32, `rounds` is cleared and the honest repair is
to say *why* it is saturated: the break, not the bound.

The falsifier is the press's own per-round trace line, which already prints
`round N: … residual R, contested C`, and it is cheap: `--growth=` is a CLI flag,
so this arm needs **no rebuild**.

### C — the survey trio, `fan_ceiling` × `limb_ceiling` × `spawns`

This one I expect to be the clearest one-knob artifact in the tree, because
**its own comment contains the evidence against its conclusion**:

> Swept against go — 814 states, 184 conflicts the table could not resolve — 64
> leaves 14% of pairs undetermined here and 7% branching past the limb ceiling;
> 256 leaves 0% here and **20% there** … widening relabels the failure rather
> than removing it.

Widening the fan took 14% of the failure off the fan and put 13pp of it onto the
limb ceiling. That is not a relabelling; that is a **second fuse blowing**, and
it is the same sentence the `crowd` comment used to carry. The inference
"widening relabels the failure" is sound only if the thing the failure moved onto
was raised too, and it was not: `limb_ceiling`'s own comment records its sweep as
"a ceiling ten times higher buys no answer", taken at **fan 64**, where only 7%
of pairs ever reach the limb ceiling. Of course it buys no answer. And `spawns`
is a *third* fuse in the same series — `born_max = spawns × limbs_max` — swept at
limbs 256 and fan 64.

Three fuses in series, three one-knob sweeps, no joint corner ever taken.

**Prediction.** At `--fan 256 --limbs 4096 --churn 65536`, go's *total*
unanswered rate (undetermined at the fan **plus** refused at the limb ceiling)
falls **below both one-knob arms**. Confidence 65%.

**And the counter-prediction, which I think is the real result.** `spawns`
already prices churn 65536 at 49 s on C; `limb_ceiling` already prices limbs 4096
at 90 s on an 800-state grammar. The joint corner is the *product* of those, so I
predict it costs **minutes per grammar** and that the defensible sentence at the
end is not "widening buys answers" but **"the answers exist and the instrument
cannot afford them"** — which is a different claim from "widening relabels the
failure", and repairing that difference in the comments is this arm's deliverable
whichever way the number lands. This project has a standing rule that local
tooling must not tax the machine, and a survey that takes minutes per grammar
breaks it.

## The four sets I am declining to measure, and why

- **`fuse`/`whole` (3/4).** Coupled to `crowd`, not in series with it: `crowd`
  bounds forks *allowed*, the mend budget bounds recovery *demanded*, and a
  refused fork makes the parse refute earlier and mend more. The direction is
  favourable — the budget was calibrated at crowd 8 / skeins 64, which is peak
  fork starvation and therefore peak mend demand, so today's constants can only
  make it bind *less*. Its comment is a bytes-not-events argument and does not
  claim saturation. Prediction: raising to 7/8 buys 0. Cheap falsifier available
  in `tool/fuse.py` if any row sits at the cap.
- **The two press budgets (1024 / 1024).** Different phases; `spread`'s comment
  prices the worst real grammar at 768 and `fold`'s says anything near the bound
  is a grammar misusing the substitution. Prediction: 0 from both, 85%.
- **The lex series (#13–#17).** Documented as a series *in the source*, which is
  the right thing to have done, and structurally slack today: 96 + 64 + 16 = 176
  against a 256 ceiling. The live fuse there is `cohort = 8` (distinct symbols at
  one offset), not the total. `src/kernel/lex/` belongs to the seating-audit lane
  and I will not edit it; this is a report.
- **`bough.stride` × `budget`.** In series and *self-regulating* — exceeding the
  budget doubles the stride, which is a fuse wired to its own governor. Off the
  cold-parse path, so structurally incapable of moving a board.

## What kills each prediction

- **A.** If `climb`/`chase` at 32/128 produce a byte-identical board, the arm is
  `vacuous` by `still`'s own rule and I have learned that the bounds are never
  reached — which is a finding, and the repair is to say so in the comment where
  today there is nothing.
- **B.** If growth 32 changes no round count anywhere, `rounds` is cleared and my
  reading of the frozen ceiling was a real defect with no consequence.
- **C.** If the joint corner is *worse* than the one-knob arms — more refusals,
  not fewer — then the "widening relabels the failure" conclusion was right for a
  reason its author did not state, and I should say what that reason is.
- **All three.** If the treatment moves a test's count, the question is whether
  the table moved or only the recording. A capacity is not permitted to be
  cleared by editing the number a test expects.

## The instrument I already distrust

`square` is the only metric here that is a claim about a second parser, so it is
the one to judge on — but a *capacity* change is exactly the class of change that
cannot move a folio, so folio identity clears none of this and `still`'s vacuity
gate is the only thing standing between me and an arm that did nothing. I will
report `denied`, round counts, and refusal rates alongside every byte count,
because those are the numbers that say whether the fuse I moved was ever the one
that was blowing.

**Verilog is withheld from every total below.** Its oracle row was repaired hours
ago and a lane is re-deriving whether the repair is sound; a freshly-repaired
reference agreeing with my change looks identical whether I am right or the
reference drifted toward me.

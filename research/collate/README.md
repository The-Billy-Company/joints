# collate — the scoreboard against tree-sitter

Joints exists to beat tree-sitter. Nobody had measured whether it does. This
folder is the measurement, on thirty grammars, against tree-sitter 0.26.11
generated from the same `grammar.json` files the press reads.

Every row below is **gap**, **improvement** or **neutral**, and an improvement
has to answer *why this tree is better for a consumer* — not "we return
something and they don't". An honest `ERROR` beats a confident wrong tree, and
this corpus contains proof of it.

Pin `collate` (tree `735a2c2ee2e8`, binary `a01fcb3448c4`), 2026-08-05.

## The scoreboard

| axis | verdict | number | where |
|---|---|---|---|
| artifact size, per grammar | **improvement** | folio 0.34x the dylib, 28 of 28 | [Result 2](RESULT-2-cost.md) |
| installation, 1 language | gap | joints 2.07 MB against ~1.6 MB | [Result 2](RESULT-2-cost.md) |
| installation, 2+ languages | **improvement** | crossover at two; 16 MB against 76 MB at thirty | [Result 2](RESULT-2-cost.md) |
| no C toolchain | **improvement** | 22 of 28 grammars ship 486,301B of scanner C; 0 folios need a compiler | [Result 2](RESULT-2-cost.md) |
| externals seated from structure | **improvement**, narrower than claimed | 263 of 461 tokens, but 7 of 23 grammars | [Result 2](RESULT-2-cost.md) |
| grammar → artifact | **improvement** | 19.6x faster to mint; 8.6s against 212.1s | [Result 2](RESULT-2-cost.md) |
| cold parse | gap | 2.9x slower at the median; latex 31.7x; a tie on html | [Result 2](RESULT-2-cost.md) |
| **incremental re-parse** | **gap, the largest** | 5.6x slower, and **gain 1x on 18 of 29** | [Result 2](RESULT-2-cost.md) |
| ~~incremental, php~~ | **withdrawn** | the 65x is one keystroke landing inside `<?php`; php is 1.8x | [keystroke Result 1](../keystroke/RESULT-1-mechanism.md) |
| structure where tree-sitter refuses | **improvement**, adjudicated | 8 verdicts, 1,343B, verilog only | [Result 1](RESULT-1-refusal.md) |
| structure where tree-sitter refuses | gap, same region | 7 verdicts, 166B; plus 1,215B where both are wrong | [Result 1](RESULT-1-refusal.md) |
| honesty about failure (the tree) | **gap** | flag recall **0.00**, by construction | [Result 1](RESULT-1-refusal.md) |
| honesty about failure (stderr) | **improvement** | names terminal, state, offset, admitting half; 16 of 29 files | [Result 1](RESULT-1-refusal.md) |
| polyglot coverage | gap | 69.09% standing, and `built` counts wrong structure as success | [Result 1](RESULT-1-refusal.md) |
| memory | **not measured** | — | — |

## The four things worth knowing

**Joints is not incremental on most of the corpus.** Median gain from having
an existing tree: 1x. Swift is 30,740 microseconds per keystroke against
tree-sitter's 73. This is the axis editors adopt tree-sitter for and it is the
worst row here by a distance.

**The candidate win was two files, not a corpus, and it splits.** tree-sitter
`ERROR`s on 2 of 30 files, not the 5 predicted, and 99.4% of those bytes are
`picorv32.v`. Hand adjudication of twenty spans there: joints right on 8,
tree-sitter right on 7, both wrong on 2 — and the two `neither` rows carry 1,215
of the 2,724 disputed bytes.

**"Tree-sitter produces nothing usable for that file" is false.** Inside its
root `ERROR` it hands back 59,611 bytes under named nodes, 63% of the file. It
parses and says don't trust it. That is a feature joints does not have.

**Joints's tree can never mark its own misreadings.** Misread bytes live in
`built`; `damage` is everything outside `built`. Flag recall is 0.00 as an
identity, on every grammar, forever, for as long as the board is defined this
way. php misreads 25,338 bytes, flags none, and reports 87.2% standing.

## The instrument

`tool/collate.py`, seven verbs. `JOINTS_BIN` picks the binary — in this tree a
path is not a version, and a benchmark against a binary you do not control is
worthless.

| verb | question |
|---|---|
| `refusal` | where does tree-sitter `ERROR`, how much survives inside it, and what does joints build there |
| `disputed` | inside a recovery region, where do the two trees disagree byte by byte — **evidence, never a verdict** |
| `adjudicated` | do the twenty hand verdicts still describe both live trees; exits 1 on drift |
| `probe` | both trees over one span, side by side, for judging the next one |
| `honesty` | of the bytes each side reads wrong, how many does it mark untrustworthy |
| `cost` | folio against dylib, mint against generate+cc, cold parse throughput, scanner C |
| `keystroke` | microseconds per typed character, each side on its own inner clock |
| `prove` | every guard above, asked to say no on an input where no is right |

```bash
export JOINTS_BIN=.local/pin/collate/bin/joints
python3 tool/collate.py adjudicated   # the tracked correctness gate
python3 tool/collate.py prove         # the anti-vacuity
```

## How the improvements are tracked

Correctness improvements are **not** a number in a document. Each is a span in
[`verdicts.toml`](verdicts.toml) carrying what both trees said and why the
verdict went the way it did. `collate.py adjudicated` re-derives both from the
live binary and the live oracle, reports any row that no longer matches as
`DRIFTED`, **excludes it from every total**, and exits 1. A hand verdict about a
tree that has since changed is not a weaker verdict; it is not a verdict.

A drifted row says **which side moved, which way, and both readings** — `lost`,
`gained`, `renamed`, `deeper`, `shallower` — because a row whose innermost name
went away moved its verdict and a row that only grew an ancestor moved its
transcript, and those are different work orders.

**The reference is a stored artifact, so it has an anchor.** The cheap way out of
a red row is to paste today's two names in and leave `side` alone — and then the
file claims one parser is right about a span where both now say the same thing.
`prove` refuses that: on every live row, `ours == theirs` must be exactly
`side in {agree, neutral}`. So a re-capture that skips the re-judgement fails a
different check than the one it silenced, and it is driven negative on whichever
row can answer it today rather than on a named row a sibling can dissolve. A row
whose defect a sibling genuinely fixed is re-judged to `agree` and **kept as the
regression guard for the fix that dissolved it** — go's `fmt.Print("x")`, php's
two, swift's comment.

**Some drift cannot be re-judged into anything true, and that drift gets written
down rather than left red.** verilog `[89368,89412)` lost a `parameter_declaration`
tree-sitter never had, so both sides read `—`; the only `side` the anchor would
accept there is `agree`, which would file a live regression as two parsers
concurring. Such a row keeps its verdict as judged and gains a
`[verdict.drifted]` note — what both trees say **now**, the move named, when it
was read — reads `HELD`, and still **counts toward nothing**. The note is a
record, not a rehabilitation.

That is also what keeps the gate legible. A check that fires on drift everybody
already knows about fires every run and stops being read, which is how the
`parameter` regression stayed unattributed for thirteen pins. `adjudicated` now
exits 1 on drift nobody has read, on a note whose drift has **moved again**, on
a note that **misnames** what it read, and on a note whose row **no longer
drifts** — and `prove` drives all three negative, including dropping a note to
confirm the note is what is holding the row.

`collate.py prove` corrupts a verdict in memory and requires the drift check to
catch it, requires the anchor above to refuse a claimed disagreement the trees do
not have, requires the honesty identity to hold, requires the honesty verb to
find php's misreadings, and requires the cost noise guard to refuse a
sub-millisecond slope. Each watched failing before it was trusted passing.

Cost and keystroke rows are recorded against the pin rather than gated, because
a timing gate on a laptop shared with nine agents is a flake generator. The
reproduction commands are in Result 2 and the raw rows are in
`.local/collate/{cost,keystroke,honesty,refusal}.json`.

## The instrument I trust least

Mine. `disputed` compares deepest nodes byte by byte, and inside a recovery
region that measures the two **lexers**, not the two trees. It scores 96.1%
agreement on `picorv32.v`, and on the 1,188-byte module instantiation that
**both parsers call a class type** it reports 57.7% agreement and 0%
disagreement. Two parsers that are wrong in the same way score as agreeing.

The full demonstration is in [Result 1](RESULT-1-refusal.md). It is why the only
correctness claims here that count are the twenty hand verdicts.

## Predictions

Written before the instruments existed, each naming what would falsify it.
Sixteen predictions: **two failed outright and one split**, and all three carry
findings. The candidate win was two files rather than five (P1). No grammar has
a bigger folio than its dylib (Q2) — though Q2's *reason* was right, since the
per-grammar ratio omits a fixed cost that flips the one-language case. And the
adjudicated sample came out better than predicted by count and worse by bytes
(P3), because two spans where both parsers are wrong carry most of the bytes.

- [Prediction 1 — the bytes tree-sitter refuses](PREDICTION-1-refusal.md)
- [Prediction 2 — size, build, speed](PREDICTION-2-cost.md)

## What this lane did not measure

Memory, on either side. Table construction time is folded into the build column
rather than isolated. Twenty-nine grammars, not thirty, because tree-sitter
cannot compile yaml's scanner here — and twenty-eight on the cost axis, because
it cannot compile embedded-template's either.

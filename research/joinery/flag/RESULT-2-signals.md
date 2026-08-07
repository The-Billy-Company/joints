# Result 2 — no. Joints does not already know.

Scored against [PREDICTION-2-signals.md](PREDICTION-2-signals.md), written
before `spans.py score` was run once. **Four of six predictions failed**, and
the failures are the finding.

> **Flat statement, as the brief asked for.** None of the nine signals
> extractable from joints's current output predicts a misread region with
> useful precision. The best of them scores 29.0% precision against an 18.46%
> base rate. A control that reads **nothing about the parse at all** — "is this
> byte in php or elixir" — scores 48.5%. And under a null that scatters guilt at
> random inside each grammar, the two highest-scoring signals score **the same or
> better**, so their apparent lift contains no per-byte information whatsoever.
> Every hit on the slate is the corpus's composition wearing a parser's clothes.
> The honest self-report has to come from somewhere else.

## The populations

```
guilty     60,138 bytes   hard crooked         rack defends these as misread
innocent  265,650 bytes   square + renamed     rack defends these as RIGHT
excluded   58,927 bytes   soft + unaudited     the oracle said nothing usable

prevalence = 60,138 / 325,788 = 18.46%
```

`excluded` is named rather than folded into `innocent`. A byte the oracle could
not adjudicate is not evidence for a signal and not evidence against one, and
counting it as innocent would have inflated every precision on the table.

## The slate

```
signal        fires on    base  precision   recall   lift  median   >1.2   what it says
----------------------------------------------------------------------------------------------------
declared         69346   21.3%      29.0%    33.4%   1.57    0.51   7/16   a node here is in a conflict the author declared
forest          225402   69.2%      26.7%    99.9%   1.44    1.00   0/16   the parse handed back more than one root
shallow         110235   33.8%      25.3%    46.3%   1.37    0.10   1/16   the derivation over this byte is <= 3 rungs
broad           150745   46.3%      20.4%    51.2%   1.11    0.05   2/16   the deepest node is >= 64B wide
mend64           87126   26.7%      14.2%    20.6%   0.77    0.74   4/16   within 64B of a root boundary
anon             39436   12.1%      14.2%     9.3%   0.77    1.06   6/16   the deepest node is an anonymous token
mend16           63739   19.6%       8.6%     9.1%   0.47    0.43   2/16   within 16B of a root boundary
mend0            47890   14.7%       4.9%     3.9%   0.26    0.05   1/16   within 0B of a root boundary
external         30955    9.5%       0.2%     0.1%   0.01    0.00   0/16   a node here is a terminal handed to a scanner

CONTROL          88827   27.3%      48.5%    71.6%   2.63                  the byte is in elixir+php
```

`lift` is precision over prevalence. `median` is the same lift recomputed one
grammar at a time and taken at the median; `>1.2` is how many of the 16 grammars
with guilty bytes it beat a coin on.

### The identity control is the whole result

A flag that reads no parser state whatsoever — *is this byte in one of these two
languages* — outscores the best real signal by **1.7x on precision and 2.1x on
recall.** php and elixir hold 43,054 of 60,138 guilty bytes (71.6%).

That is why the `median` column exists, and why it is the column to read.
`declared` scores 1.57 corpus-wide and **0.51 per grammar** — below a coin. It is
not detecting conflicts near misreadings; it is detecting that php and elixir
declare a lot of conflicts and also happen to hold the misread bytes. `shallow`
does the same thing harder: 1.37 corpus, 0.10 median. `forest` is 1.44 corpus
and 1.00 median on 0 of 16 grammars — a per-file fact painted onto every byte
in the file.

Only `anon` has a median (1.06) roughly equal to its corpus lift (0.77), and it
is a control with 9.3% recall.

### `external` is not merely weak, it is empty

30,955 bytes sit under an external terminal. **62 of them are misread.**
Precision 0.2% against an 18.46% base rate — external tokens are ~90x *safer*
than the corpus average.

This kills the story I most expected to survive, and I said so in advance. The
brief's evidence for it was that the four widest `orphan` rows all stop on a
blind external. That is true, and it explains `orphan` — bytes never placed. It
says nothing about `crooked` — bytes placed wrongly. **Two different defects
have been sharing one explanation.** Where joints's scanner is blind, joints
tends to *stop*, and stopping is visible. Misreading is what happens when
nothing goes wrong.

### The mend signals are inverted, and that is a real result

`mend0` scores 4.9% precision against 18.46% prevalence — lift 0.26. Bytes
adjacent to a mend boundary are nearly **four times less likely** to be misread
than an average built byte, and the effect weakens monotonically with distance
(0.26 → 0.47 → 0.77 at 0/16/64 bytes).

Mends do not mark bad regions. They mark the regions where joints **noticed**.
The misread bytes are, definitionally, the ones it did not notice, so the
existing damage machinery is not merely blind to them — it is *anti*-correlated
with them. Any future flag built by widening the mend radius will move away from
the target.

## Predictions

| | claim | falsifier | outcome |
|---|---|---|---|
| P1 | `external` beats prevalence by 1.5x | precision below 27.8% | **FAILED** — 0.2%, lift 0.01 |
| P2 | `mend0`: high precision, useless recall | precision below prevalence | **FAILED** — 4.9% vs 18.46%; recall 3.9% as predicted |
| P3 | `forest` worthless, lift near 1.00 | lift above 1.3 | **FAILED as written** — 1.44 corpus. Median 1.00 on 0/16; the falsifier caught composition, which is P6 |
| P4 | ≥ 2 of 3 controls stay quiet (lift ≤ 1.2) | two or more above 1.2 | **FAILED** — `declared` 1.57 and `shallow` 1.37 both fired |
| P5 | nothing reaches precision 0.50 at recall 0.20 | any signal clearing both | **held** — best precision 29.0% |
| P6 | ≥ 1 signal above 1.4 corpus lift and below 1.1 median | the two rankings agree on the top signal | **held twice** — `declared` 1.57/0.51, `forest` 1.44/1.00 |

P4 failing is the credibility warning I wrote it to be: two innocent controls lit
up, which meant the extractor was measuring something other than the parse. P6
then names what. Together they are the reason the identity control was added
after the fact and the reason nothing on this table can be read as a hit.

## What I could not measure, and why it is the whole remaining question

The brief named five candidates. **Three cannot be seen from outside `src/`**,
and that is not a hedge — it is the specification:

| candidate | why not | who would emit it |
|---|---|---|
| GLR fork survivor counts; forks that died late | nothing emits them. `JOINTS_TRACE` has no weave lens; the folio carries the press's conflict table, not a per-parse fork history | the weave/spine lane |
| a conflict resolved **under duress** — an unranked fold ordering an authored reading | `settle.zig` classifies these at press time (`residual`/`unwritten`) but per LR *state*, and nothing in the parse output says which state reduced over which byte | `src/press/` + the parse |
| a reduction where `inquest` would have named a wall one byte later | requires re-parsing every prefix of every file | offline, but not this lane |

What I *could* measure — `declared` — is the shadow of the second one: which
symbols the grammar declares ambiguous, rather than which reductions actually
resolved under duress. It scored 0.51 median lift. **That is weak evidence
against the real signal, not evidence for it**, and the distance between them is
large: `declared` fires on 69,346 bytes because php's grammar declares a lot of
conflicts; a duress event fires where a specific reduction had no ranking to
break a tie.

## The specification, conditional

No emitter is justified by anything on this table. If a lane inside `src/` wants
to test the three unmeasured candidates, the cheapest experiment that would
settle it:

**Emit, per reduction, a byte range and three bits**: `unranked` (the fold that
won had no precedence to break the tie), `late` (the losing fork survived more
than N tokens), `standin` (a terminal was seated by a stand-in rather than a
scanner match). One line per event on a trace lens; no format work.

`research/joinery/flag/spans.py` will score it as-is — add the flag to `flags()`
and it appears in the table with precision, recall, base rate, per-grammar
median, the identity control and the null beside it. **Two bars, and the second
is the one that matters:** clear 2.63 lift, because a signal that cannot beat
"which language is this" has not found anything about the parse; and move away
from its own scrambled null, because `declared` clears neither and it is the
best thing on the current slate.

If it clears that bar, the emitted span is tree-sitter's `ERROR`, graded, over
the case tree-sitter has no node for: a region that parses cleanly and is wrong.
If it does not, the honest conclusion stands as stated at the top — the parser
does not know, and the self-report has to be built rather than surfaced.

## The thing I trusted least, and what breaking it showed

`spans.py check` proves this file's six buckets equal `rack.survey`'s own on
every grammar — **81 of 81**, including php (19,016 square / 40,130 crooked,
14,736 soft removed → 25,394 hard). But that is a claim about **totals**, and
every precision above is a claim about **which bytes**. A per-byte attribution
scrambled *inside* a grammar would pass all 81 tripwires — and it would fail in
the direction of my conclusion, because scrambled labels make every real signal
score at chance, which is exactly what I observed. I could not tell "the signals
don't predict" from "my labelling is noise."

So `spans.py score` now runs the null. Keep each grammar's guilty byte budget,
spend it on a shuffled cut order, re-score the whole slate, five seeds:

```
signal          real  scrambled    moved
------------------------------------------
mend0           0.26       1.59     1.32
mend16          0.47       1.55     1.08
mend64          0.77       1.51     0.74
external        0.01       0.30     0.29
shallow         1.37       1.23     0.14
declared        1.57       1.70     0.13     <- real is BELOW its own null
broad           1.11       1.24     0.13     <- real is BELOW its own null
anon            0.77       0.81     0.04
forest          1.44       1.44     0.00     <- exactly zero information
```

**The doubt is cleared and the table is worse than I reported.** The labelling
is not noise: `mend0` moves 1.32 away from its null, which a scrambled
attribution could not produce. But the two signals at the *top* of the slate
carry no per-byte information at all. `forest` moves 0.00 — its 1.44 lift is
entirely which grammars it fires in. `declared`, the best number on the page at
1.57, scores **1.70 when guilt is scattered at random** — it is not merely
uninformative, it is very slightly worse than the corpus composition it rides on.

The only signals with real positional content are the three mend distances, and
they point backwards: they mark where joints **noticed**, which is definitionally
not where it misread. `external`'s null is 0.30 rather than 1.00 because external
tokens concentrate in low-guilt grammars — and its real 0.01 is 30x below even
that, so it is genuinely anti-correlated within grammars too.

Read the two controls together: the **identity** control says the corpus-wide
numbers are language composition, and the **null** says which signals have
anything underneath that. Two of nine have. Both are inverted.

`spans.py prove` corrupts the scorer deliberately — **6 of 6**: a flag firing on
every byte scores recall 100% at lift 1.00 (the shape a report would misread as
a hit), a flag firing on nothing scores 0/0 rather than an empty 100%, an
`unjudged` byte lands in neither population, and a soft crooked byte is excluded
from `guilty` so the signals are scored against the defended 60,138.

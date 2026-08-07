# Prediction 1 — is the board reproducible at all

Written **before** any of the three tiers ran. Scored in
[`RESULT-1-board.md`](RESULT-1-board.md), failures included.

The question is the one the owners lane raised without meaning to: it read
scala's `crooked` at **1,938** where prior runs read **1,278** and **9,087**,
same grammar, same corpus file, same tool. Until that is settled, no lane's
before/after on a tail row is worth anything.

## The three tiers, and what I expect each to say

**Tier 1 — one pinned binary, a private `JOINTS_WORK`, folios minted once,
the board run five times.**

> **Nothing moves.** Every byte column identical on all five runs, including
> `crooked` once an audit is cached.

The parse is a pure function of (binary, folio, source) and `standing.py` reads
its render with a regex. Nothing in that chain samples a clock, a hash seed or
a directory order. If this tier moves, the finding is enormous and everything
below it is noise.

**Tier 2 — same pin, the folio cache wiped and re-minted before each run.**

> **Nothing moves**, and all thirty grammars press to byte-identical folios
> twice in a row.

The uninitialized-padding defect in `lexicon.Head` / `Dfa.PatRun` was fixed and
gated by `seamless(T)`. I expect the gate to still hold, and I am checking it
rather than believing it: it is cheap, and nine of thirty is the kind of number
that comes back.

**Tier 3 — across the binaries that could have produced 1,278 / 1,938 / 9,087.**

> **The 7x is not a flake. At least two of those three numbers are different
> columns, and nobody noticed because they are all called `crooked`.**

The arithmetic that made me write this down before running anything:
`research/joinery/tenon/RESULT-4-instrument.md` prints scala at `crooked 9087`,
`span soft 194`, `shape soft 6955`. That is 7,149 soft. And
`9,087 − 7,149 = 1,938`, which is the owners lane's number **exactly**, to the
byte, on the first arithmetic I tried.

So the specific prediction:

- **9,087** is `rack`'s raw crooked, soft included.
- **1,938** is `standing.py`'s crooked, which is defined as `rack.crooked − soft`
  and is therefore a *different question* — `standing.py` deliberately refuses
  to charge extras placement as a misreading.
- **1,278** is the only one of the three that is a genuine second reading of the
  same question, so the real spread to explain is **9,087 against 1,278**, and I
  predict its cause is **the oracle, not the board**: a sibling lane rebuilding
  `.local/differential/lang/scala/src` between the two runs.

Confidence: high on the first two (it is arithmetic), medium on the third (the
tenon lane already suspected it and explicitly declined to claim it).

## The mechanism I expect to find behind the third

`standing.py --audit` caches each grammar's verdict in `audit.json` keyed on
three digests — **folio, binary, source** — and refuses a verdict whose
generation has moved. All three describe *joints*. The oracle is the other
parser in every one of those comparisons and **none of the three names it**.

> A sibling rebuilding one grammar's tree-sitter sources changes `crooked` while
> every guard on the board reads `graded: read` and no row prints `stale`.

If that holds, the board's newest column is the one column with no generation
guard at all, which is a poor thing to be ranking a work list by.

## What would falsify each

| prediction | dies if |
|---|---|
| tier 1 flat | any column moves across five runs on one folio set |
| tier 2 flat | a grammar presses to two different folios, or a column moves |
| 1,938 = 9,087 − soft | the subtraction does not land on 1,938 when I re-run it |
| the oracle is the third cause | scala's `crooked` is stable across two different oracle generations |

## Two things I am deliberately not predicting

**Whether 1,278 is reproducible at all.** The tenon lane could not reproduce it
and said so. I may not either, and if I cannot I will say the spread is
*unexplained but bounded*, not that it was a flake.

**Whether the press is still deterministic on this tree.** I have not looked. I
would rather write "I expected 30/30 and got 30/30" than skip the rung because
somebody already fixed it once.

# Result 2 — presence as a node, and the 22.8% the old column carried

`tool/absent.py`. Predictions in
[`PREDICTION-2-presence.md`](PREDICTION-2-presence.md), written first and
unedited after. Same pin and same seated oracle as Result 1: `frame`
(`cf697da9f`), oracle `800ede524`, tree-sitter 0.26.11.

## What was wrong, in the previous author's own words

> A spelling counts present if its bytes occur anywhere, including inside a
> comment. **34 of 211 multi-byte spellings called present never occur outside
> a comment or string — 16.1%**, and 45.5% for css, 31.7% for scala.
> `ledger.scala` contains `true` 17 times and `false` 16 times and **not one is
> a `boolean_literal`.**

They declined to intersect with the oracle and the reason was good: `absent.py`
is the only reading available on the 34,687 built bytes where tree-sitter itself
ERRORs, and an instrument that needs an oracle cannot be that. So the byte
reading stays. A second one sits beside it and the gap is the finding.

## The rule

**A spelling is present as a node when some occurrence of its bytes is covered
by an oracle node named by a rule that spells it** — or by the name that grammar
aliases that rule to.

The test is not "is it inside a comment". It is "is it inside the thing that
declares it". That distinction is the whole reason this does not repeat the
previous detector's defect, which flagged lua `--` at 44 occurrences and css
`/*` at 71 — comment *openers*, which of course sit inside the node they open.

## The overcount

Of the **1,767** spellings the byte reading calls present over the 27 grammars
that have an oracle:

| count | what it is |
| --- | --- |
| **506** | spelled only inside a `token(...)`; no tree can answer |
| **1,261** | the node reading can judge |
| **973** | …and does call present as a token |
| **288** | **never tokenised by the oracle at all — 22.8%** |
| **253** | …of those, every occurrence sits inside another token |

**288 is the byte reading's overcount, and it is the number `present` was
quietly carrying.** The 253 are the sharp part, because each one names the token
that swallowed it:

```text
bash   STRING  'until'  inside comment
bash   STRING  '|'      inside "||"
bash   STRING  '<'      inside "<<"
c      STRING  '%'      inside string_content
scala  STRING  'true'   inside block_comment
scala  STRING  'false'  inside block_comment
```

Widest share is **css at 16 of 30 — 53%**. The previous author reduced scala's
`true`/`false` by hand; the instrument now derives it and prints the host.

Corpus-wide, `present` goes **2,050 → 1,762 of 5,198 judgeable — 39.4% →
33.9%.**

## `impossible` is a range, not a number

The byte reading cannot invent an absence and misses some; the node reading
cannot miss one and invents some, because a literal folded into a `token(...)`
or a C scanner is never a token of its own however often the construct occurs.
So the two readings bracket the answer rather than replacing each other:

| | over the 27 oracled | corpus, carrying the other three |
| --- | --- | --- |
| floor — byte reading | **903** | **1,319** |
| ceiling — node reading | 1,094 | 1,510 |
| ceiling, minus its own error | **1,089** | **1,505** |

The ceiling's error is countable from the same tree: **5 of its 1,094 rules are
rules the oracle actually BUILT a node for**, so 1,089 is the most that reading
can honestly claim. The floor's error is not countable by any means here — a
rule the oracle did not build may still be possible. This file will not pick one
of the two, and the published 1,319 should be read as the lower end of a range
rather than a measurement.

## The predictions

| | claim | |
| --- | --- | --- |
| **Q1** | node presence lands below 39.4% | **held** — 33.9% |
| **Q2** | the drop is at least 5 points | **held**, barely — 5.5pp |
| **Q3** | scala's `true`/`false` come back absent | **held**, host named |
| **Q4** | lua `--` and css `/*` stay present | **split**, see below |
| **Q5** | at least two grammars get no node reading | **held** — three |
| **Q6** | latex stays lowest, at or under 9.1% | **held** — 6.5% |
| **Q7** | corpus `impossible` rises above 1,319 | **held on the carry** |
| **Q8** | at least 500 spellings unwitnessable | **held** — 506, and it hurt |

Q3's host is `block_comment`, derived rather than counted by hand. Q5's two
named candidates were verilog and sql; the third is yaml. Q7 rises 903 → 1,094
on the comparable population, and 1,319 → 1,510 corpus-wide only if you carry
the three unoracled grammars at their byte floor — state the carry or the
number is not a number.

**Q4 split, and the split is the better outcome.** lua `--` comes back
**present as a node** — the innocent control survives, and the exact pair that
fooled the previous detector does not fool this one. css `/*` comes back
**sealed**: css spells it only inside a `token(...)`, so the node reading
declines to judge it rather than calling it absent. Not "present", but the
failure mode Q4 was built to catch — a comment opener falsely reported missing —
did not occur. Withholding a verdict is the floor discipline the prediction
demanded: *it may miss an absence, never invent one.*

**Q8 is the one I said would hurt, and it does.** 506 of the 1,767 byte-present
spellings — **28.6%** — are outside the node reading entirely. So the honest
headline is not "the number was 39.4% and is really lower". It is **two
readings, each blind where the other sees**, and my fix buys materially less
coverage than it looks like it buys. That is a worse sentence to write and a
better one to be true.

## What I said would make me distrust the result

> A grammar whose node presence *rises*. That is arithmetically impossible under
> the rule as stated, so if one rises I have a bug in the alias or unwitnessable
> handling and the whole column is suspect, not just that row.

None rises. `token ≤ asked ≤ present` on all 27 rows.

Two rows nearly became false findings and were run down rather than shipped.
TypeScript's `string` rule collided with an anonymous `string` token in
`type Foo = string;`, and toml's `escape_sequence` is produced by an `ALIAS`
from a different rule — both would have printed as "the oracle built a rule this
file calls impossible", which is a defect in the instrument and not a finding.
`witness` now filters to named nodes and resolves aliases, and the cross-check
prints `none — the two readings never contradict each other`. That line is a
tripwire, not decoration; if it ever names a rule, believe it over the column.

## Reproducing

```sh
python3 tool/absent.py run                     # the byte reading, unchanged
python3 tool/absent.py oracle --oracle=frame   # both readings, and the gap
python3 tool/absent.py verify                  # 18 tripwires
```

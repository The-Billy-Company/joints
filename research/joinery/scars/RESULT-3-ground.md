# Result 3 — the residual bucket, and the ground under `square`

Two instruments, one disease. `residue.py`'s `none` was a residual wearing a
positive name, and `rack.py`'s `square` could not say what ground it stood on.
Both are now positive, and both can fail.

Read on tree `f7ba40004+144`, binary
`.local/lane-scar/bin/joints` (build `60727cf12f63…`, source tree
`1f6a711f0ffa…`), oracle tree-sitter as `plumb.py` pins it. Every number below
was taken on that tree. **The population moved between the authoring lane's
sweep and this one** — see the last section, it matters.

## 1 — `none` is a positive test now, and it was 74.5% real

`Gather.follows` returned a bool. It returns false for five reasons and only two
of them are the table answering:

| the walk | verdict |
|---|---|
| reached an `err` cell | a table fact — `no` |
| reached the end column accepting | a table fact — `no` |
| crossed a cell the author declared ambiguous | **cannot tell** |
| filled the `climb` overlay | **cannot tell** |
| spent `chase` steps without a shift | **cannot tell** |

`supply` looped every anonymous literal, folded all five into one `false`, and
printed `none` — a *universal* claim, that no literal could stand for the
refused external, established by none of them.

`follows` now returns `Ahead.Says`, and `Ahead` records which wall it hit.
`none` is reported only when every literal reached a table verdict; one
untellable candidate out of two hundred disqualifies the claim, because the
claim is about all of them.

**The twelve grammars, `--mend=fell`, the 1,288 the brief named:**

| | count | share |
|---|---:|---:|
| honest miss — every literal reached a table `err` | **959** | 74.5% |
| the walk declined — `forked` | **329** | 25.5% |
| the walk declined — `climbed` | 0 | 0.0% |
| the walk declined — `chased` | 0 | 0.0% |

haskell owns 1,263 of the 1,288 and splits 936 / 327 the same way. Over all
thirty grammars the figures are 1,405 / 1,468 under `fell` and 32,890 / 673
under `keep`.

So the hypothesis in the brief is **refuted, usefully**. Nobody needs to raise
`climb` or `chase`. What the 329 want is a walk that can carry two readings
across a declared fork — `absorb`'s machinery, and a different brief from the
959.

### The zeros are real, and that was checked

Two columns reading zero on every row is the `budge.py` shape this lane was sent
to audit for. Building the same tree at `climb=1, chase=2` and re-running the
twelve lights them up at **45 `climbed`** and **968 `chased`** (haskell 34/876,
kotlin 6/56, swift 4/14). The columns are alive; the zeros are measurements.

The constants were flipped into a throwaway prefix and reverted in the same
command under a shell trap, and the revert was verified with `git diff` before
anything was read off it. The procedure is recorded here rather than shipped as
a script — ten agents share this tree and a script that rewrites `gather.zig`
is a footgun, not a falsifier.

## 2 — the other four buckets

| bucket | verdict |
|---|---|
| `stray` (444) | **positive.** `blame` asks the scanner a second time with the state filter off, so a byte that lexes fine but that no live state wants is no longer filed as a byte no lexer could read. A sibling fixed exactly this disease here already. |
| `spurned` (54) | **positive** — two literals both returned `yes`. But it returns *mid-loop*, so it has no untellable-candidate count. A real hole, left visible. |
| `ground` (20) | **positive** — `deep(spent) == 0`, a fact about the stack. |
| `supplied` (130) | **the same disease pointing the other way.** A supply made while another candidate was untellable is the one literal that said yes, not provably the only one. The runtime now emits an `unsure (...)` line whatever the outcome; **1,468** refusals under `fell` had at least one untellable candidate. |
| `adrift` | **was a residual, and it was the column meant to catch residuals.** `cut + gave - sum(seen.values())` is identically zero whenever the counter is complete, and the counter is always complete. It also hardcoded the reasons it summed, so when the runtime grew three words it silently lost 50 of bash's 90 deletions. Now derived from the other side and signed. `--selftest` shows it reading `+40` where the old form read `+0`. |

`unseated` and `fuse` are positive threshold tests and read 0 everywhere.

## 3 — the ground under `square`

`ground.py` calls `rack.survey` verbatim three times over one `plumb.Read`,
narrowing only the *judged byte range*. Not a sixth price, and `rack.py` is
untouched. The clip narrows a window's judged range and never its frame,
because `unframed` reads the set of root extents to find seams and dropping one
invents a seam; a window outside the slice is kept with an empty judged range.

The halves must add back up on all **19 byte columns × 30 rows**, and do.
`--selftest` builds the wrong clip on purpose and shows the check catching it.

**Board, binary-default mend:**

| population | scarred `square` | of | share |
|---|---:|---:|---:|
| all thirty rows | 67,231 | 313,469 | **21.4%** |
| the twelve that repair at all | 67,231 | 113,248 | **59.4%** |
| the seventeen that never repair | 0 | 200,221 | 0.0% |

21.4% lands *inside* `RESULT-2-untested.md`'s 19.9–23.0% — but that denominator
includes seventeen grammars with no repairs anywhere. Restricted to rows where
the question is meaningful the share is **59.4%**.

## 4 — what it does to the `+3,124`

Both arms split at one common cut, `--mend=keep`:

| | ctl `square` | arm `square` | Δ | Δ clean | Δ scarred |
|---|---:|---:|---:|---:|---:|
| sql | 3,437 | 3,718 | +281 | +9 | +272 |
| swift | 11,172 | 12,346 | +1,174 | +0 | +1,174 |
| verilog | 8,087 | 9,756 | +1,669 | +0 | +1,669 |
| | 22,696 | 25,820 | **+3,124** | **+9** | **+3,115** |

**+3,115 of +3,124 (99.7%) stands on repaired ground.** The authoring lane
guessed larger than 23%; it is larger by far more than it expected.

**Half of that is structural, and the instrument says so.** The arms are
byte-identical up to the first refusal, and the first repair lands there in both
— `ctl 1st` / `arm 1st` are 2,907/2,907, 24,582/24,582, 3,712/3,710 — so the
movement cannot be upstream of the cut except through an extent change, which is
what sql's `+9` is.

The non-structural statistic is the enrichment: the gain's downstream share
divided by that grammar's `built` downstream share.

| | file | cut | `built` downstream | gain downstream | enrichment |
|---|---:|---:|---:|---:|---:|
| verilog | 94,657 | 3,710 | 97.1% | 100.0% | **1.03×** |
| sql | 6,390 | 2,907 | 54.9% | 96.8% | **1.76×** |
| swift | 28,468 | 24,582 | 6.0% | 100.0% | **16.7×** |

verilog's 1,669 is a whole-file effect the cut cannot resolve. **swift's 1,174
is real and local**: every byte of it lands in a repaired tail that is one
sixteenth of the file.

## 5 — the population moved, and this is why the digest matters

`RESULT-1-insert.md`'s twelve-grammar `--mend=fell` figures reproduce here
exactly — `stray` 444, `spurned` 54, `supplied` 130, and `none`+`forked` = 1,288
— as does the whole `+3,124` and each of its three components. That is the
regression guard for this change: a diagnostic-only edit to `follows` must not
move a single one of them, and it did not.

Under `--mend=keep` the same twelve now read **17,504** refusals where the
authoring lane's sweep read a fraction of that, because a sibling's `gather.zig`
change landed in between. Any `keep`-arm count quoted off the earlier sweep is
about a different tree. The `fell` arm is stable.

## What I trust least

The **99.7%**, and specifically the temptation to read it as "the gain was
worthless." It is not that. It is mostly a consequence of where the cut has to
be: a supply *is* a repair, the arms only diverge after the first refusal, and
the first refusal is the first repair. The number that survives that objection
is swift's 16.7× enrichment, which is one grammar and 1,174 bytes.

Second: `blind.py`'s cut is the first repair in the *file*, which for verilog is
byte 3,710 of 94,657. "Downstream of a repair" is a very coarse instrument at
that scale and this file inherits it deliberately, so the number is comparable
to the interval it narrows. A per-scar-span attribution would be sharper and is
not what was bounded.

Third: `spurned` still has no untellable count, because it returns mid-loop.
Fixing that means restructuring the candidate scan, which would change behaviour,
and this lane's whole warrant was that it did not.

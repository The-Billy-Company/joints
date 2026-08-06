# Result 4 — what "fourteen rows, no collateral" is a clearance of

## The verdict

**It survives, narrowed twice.** No arm in the family moved a grammar its row
cannot seat, and this lane found nothing that overturns that. What it clears is:

> On one snapshot, over one fixture per grammar, scored on **`damage`**, no
> seating moved a grammar other than its own.

Three things that sentence does not say, one of which the previous lane already
found and two of which follow from the same construction.

### 1. It is not a claim about agreement with another parser (measured)

Every arm was given its own `OUTLINER_WORK` by the third house rule.
`standing.py`'s oracle overlay is a per-work-dir `audit.json` written by
`--audit`, and no arm re-ran it. So on the retained base board and on every
retained arm board:

```text
square 0 · crooked 0 · unframed 0 · graded — · unaudited = built
```

30 of 30 rows, 6 of 6 retained boards, and `graded: —` on all fourteen
single-row and five pair ledger entries. `square` is the only column that is a
claim about agreement with tree-sitter, and the ablation family never computed
one. The clearance is entirely in outliner's own words about its own forest.

That is checkable rather than fatal - `--audit` in an arm's own work dir would
mint real squares - and it is expensive (thirty grammars racked per arm), which
is presumably why nobody did.

### 2. Corpus silence and inertness are the same reading (measured)

A row whose construct is absent from its grammar's fixture reads zero in **every
arm of this family** - single, pair, and the fourteen-row union. `Chunked.swift`
has no `/*`; `multiline_comment/.marrow/.swift_block` reads 0, 0, 0; and the
family has no arm that can tell that from a row which does nothing. It was
written up as the latter and it is the former (`RESULT-2-swift.md`).

So **"moves nothing" can never be upgraded to "changes nothing"** by any board
arm, at any subset size. That is not a bug in the pair sweep; adding a third row
would not help.

The repair is a second tier, and it already existed. `witnessed.py` joins each
row's board arm to the specimen tier:

| | rows |
|---|---|
| **witnessed** — a specimen flips when the row is un-seated | **11** |
| **corpus-only** — the board moved, no specimen flips | 3 |
| **unwitnessed** — neither moves | **0** |

Eleven of fourteen rows are answering a bound falsifier that does not care what
the corpus contains, and swift's row - the one called inert - is one of them.

The three `corpus-only` rows are worth naming, because they are exactly the
three rows whose board worth is **negative**:

| row | seat | grammar | board worth |
|---|---|---|---:|
| 0 | `_indent/.offside/.slashes` | scala | −4,970 |
| 4 | `block_comment/.marrow/.kotlin_block` | scala | −10,326 |
| 5 | `comment/.marrow/.ocaml_comment` | ocaml | −721 |

The three seatings that currently make their grammar worse are the three with no
specimen watching them. Nothing here says they are wrong; it says nothing here
would notice if they were.

### 3. A `worth` column is not a per-row credit (measured)

`RESULT-1-kotlin.md` is the whole argument. In summary: a solo arm measures
*"the file behind every gate"*, so where two of a grammar's constructs sit in
front of the same body of text, both solo arms return the same bytes and the
column double-counts. Kotlin is 40 KB of one 20 KB stretch.

And the fourteen-arm table and the pair table were taken days apart on trees
whose controls differ by 4× on scala and 8,795 bytes on elixir
(`RESULT-3-scala.md`), so subtracting across the two pages is a third way to be
wrong with true numbers.

## Predictions, scored

Written in `PREDICTION-1-mechanism.md` before anything was built or run.

| | prediction | outcome |
|---|---|---|
| P1 | kotlin's two rows compete for no terminal | **right** — emitted sets disjoint |
| P2 | the coupling runs through consumption: the fence protects the caesura | **WRONG** — each row moves its own construct identically in either state |
| P3 | `aud-r2` carries more roots than `aud-r2-12` on kotlin | **WRONG** — 424 against 1,140 |
| P4 | the caesura's landing fragment records the same ≈ −1,059 | **right** — −1,075, a different instrument on a different day |
| P5 | ≥3 places credit the solo figure; 0 are arithmetically false | **half** — 2 places, and the 0 holds; the historical +20,728 pages are true marginals |
| P6 | swift's row is alive and the corpus is silent | **right** — zero `/*` in `Chunked.swift` |
| P7 | ≥1 swift comment specimen goes red against `aud-r3` | **right** — both did, 4/4 → 2/4 |
| P8 | the row is at the right target; swift's orphan is not comment bytes | **half** — orphan is 100% `comment` and 0% `multiline_comment`, so the *construct* is right and the *motivation* was wrong; the crooked half is unmeasurable here (see §1) |
| P9 | scala's rows couple through the offside hand reading the comment row's token | **WRONG** — `offside.lead` skips comments itself from raw bytes |
| P10 | the clearance survives, scoped to `damage`; `square` is 0 everywhere; corpus silence is a second blind spot | **right** — both falsifiers checked |

**Five right, two half, three wrong** - and the three wrong are one mistake
made three times. P2, P3 and P9 all assumed that a residual describes the rows.
It describes the file. That is precisely the error the brief warned about in the
previous lane's swift call, committed again in the opposite direction: they read
a zero as a hidden mechanism, I read a residual as a hidden mechanism, and
neither number was about a mechanism at all.

## The instrument I trust least

**`gate.py`, this lane's own — and the reason is that it reproduces
`pairs.json` to the byte.**

On `Maps.kt` it returns 35,571 / 14,834 / 16,342 / 15,893 and a residual of
−20,288; on `Option.scala` it returns −4,970, −10,326, −9,796 and +5,500. Every
figure matches the ledger the previous lane wrote with a different tool. That
looks like the strongest possible clearance and it is not one, for two reasons.

**It is a calibration, not a corroboration.** Both instruments drive the same
pinned binaries, read the same `--ranges --all` render, and take `built` from
the same `standing.union` over the same definition of a construct - mine
literally imports theirs, deliberately, so a fourth reader of that render would
not exist. Agreement proves I copied the definition correctly. Two readers of
one opinion agreeing is not two opinions.

**And the opinion is the wrong column.** The brief's own instruction is that
`square` is the only metric that is a claim about agreement with another parser,
and every number on this page is `built`. `gate.py` cannot produce a `square` at
all: it has no oracle seat, and the fixtures it invented for the falsifiers have
no tree-sitter tree to be square against. So my central result - *the residual
follows the fixture* - is a statement about how outliner's own reach responds to
where a construct sits, defended by a metric that never asks a second parser
anything.

What would clear it is the expensive thing nobody has done: `--audit` per arm,
and the same four-arm sweep scored on `square`. If two rows really are
independent, their `square` contributions should be additive on a fixture that
has an oracle tree, and non-additive `built` beside additive `square` would be
the finding stated properly. Until then this page has a mechanism argument -
the probe table, which is categorical and does not depend on `built` at all -
and an arithmetic argument that rests on a column the brief told me not to
judge on.

Second place, for the record: **the retained pins**. They are the right control
and their per-file manifests prove it (each arm differs from `aud-base` in
exactly `src/kernel/lex/outside.zig`, checked for all eleven arms used here).
But they are frozen on a tree with a live press regression in it, which is why
`RESULT-3` can say what scala's numbers *are* and not what they *mean*.

## One note on the tooling, as asked

`still.py against <arm> <arm> --mine …` could not reach these pins: it resolves
`ROOT` from its own location, so it looked for `.local/still/witness/aud-base.json`
in the repo while the audit family's pins live under
`.local/aud-iso/outliner/.local/pin/`. Not wrong - the pins were minted with
`pin.py` inside that checkout - but it meant the `--mine` predicate had to be
taken by hand out of each pin's `world.json`. That is recorded here rather than
worked around silently, and the hand-taken result is in `README.md`: eleven
arms, one changed file each, and it is the file this lane owns.

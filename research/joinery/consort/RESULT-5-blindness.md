# Result 5 — the blast radius of an empty column, and the three places it is now closed

`RESULT-4-clearance.md` §1 found that all nineteen arms in the ablation family
read `square 0 · crooked 0 · graded —`, and that the clearance they were quoted
for was therefore measured on `damage` alone. This lane asked how far that
goes, fixed it where it starts, and made the comparison say so at the point of
use.

## 1. The blast radius — 28 of 33 boards on this disk

`blind.py` walks every retained board under `.local`, sums the `square` a board
**accepted** (rows whose `graded` is `read` or `part`, not the cache's own
claim), and reports the shape:

```
  blind 28  ·  sighted 4  ·  told 1
```

| state | what it means | boards |
|---|---|---|
| `blind` | 30 rows at `graded —`, no audit was ever offered | 28 |
| `sighted` | live verdicts, `square` is a measurement | 4 |
| `told` | 30 verdicts offered and all 30 refused as `stale` | 1 |

The four sighted ones are `.local/pin/oracle-base/board.json`,
`.local/scars/arm-audit.json`, `.local/scars/arm-audit2.json` and
`.local/twice/board.json`. **Every one of them paid `--audit` explicitly inside
its own work dir.** None of them is sighted by inheritance, which was the
mechanism I predicted, and the reason is worth stating: the shared default cache
`.local/standing/audit.json` holds thirty verdicts of which **zero** carry an
`oracle` field, so it predates the identity work in
`research/joinery/still/RESULT-5-oracle.md` and confers nothing on anybody. The
separator is not care and it is not the default dir. It is a lane having decided
in advance that it was going to need the other parser.

**Every `damage`-only claim in the family is labelled by this table**, including
the fourteen singles and five pairs of `vacuity/RESULT-2-arms.md` and
`RESULT-5-pairs.md`: none of them said anything about agreement with
tree-sitter, and a change can leave `built` untouched while moving every leaf to
a different parent. `RESULT-6-scala.md` is what that looks like when the column
is filled in — a row whose `damage` worth is negative and whose `square` worth
is positive.

### The `told` row is a second defect, and it is upstream of all of this

`.local/scars/control-audit.json` is the interesting one: a lane paid the
four-minute sweep inside an isolation arm, wrote thirty verdicts, and the board
refused every one of them. Two of the twelve audit caches on this disk are
**30-of-30 `folio: missing`**:

```
 30/30  folio missing   .local/lane-seat3/before/audit.json
 30/30  folio missing   .local/scars/cwork2/audit.json
```

`standing.py audit()` took its digests with `marks()` *before* `plumb.read()`,
and `plumb.read` is what presses `WORK/<name>.folio` into existence. On a work
dir nobody had measured in yet — which is precisely the work dir `pin.py arm`
hands out — the folio digest recorded is the literal string `missing`, and
`Held.matches` then refuses all thirty rows on the next board. So arming
correctly did not merely leave the column empty; it made the column
*unfillable*, and a lane that noticed and paid for the audit got the same zero
with four minutes less of its evening.

The read is now first, with the reason written where the order is:

```python
saw = plumb.read(case)
if saw is None:
    continue
folio, binary, source, oracle = marks(case.name, case.source)
```

The four caches this lane minted afterwards read **0/30 `folio: missing`**.

## 2. The fix — an arm carries the oracle, and says when it does not

Seeding is not the fix, and the machinery already knew: a verdict is keyed on
folio + binary + source + oracle, and two arms differ in the binary by
construction. Copying `work-base/audit.json` into a sibling arm's work dir and
taking a board there:

```
graded: {'stale': 30}
total square: 0
```

Thirty verdicts offered, thirty refused, no code change required to refuse them.
So the verdicts have to be **minted per arm**, and the only thing worth building
is making that one command instead of three exports in the right shell.

**`pin.py oracle <name>`** runs the sweep inside the arm's own environment and
answers with how many verdicts the arm can actually read back, exiting 1 if that
is zero — a sweep that wrote thirty verdicts none of which this arm can accept is
the failure the verb exists to end, not a success with a sad number in it.

**`pin.py arm <name>`** now closes on the arm's oracle state, on stderr, so it
survives `eval` and changes nothing a lane pipes:

```
# arm 'fz-control' — binary, its own folio cache, its own oracle seat.
# oracle: NONE — every `square`/`crooked` column off this arm will read 0, and
#         a comparison against it is not a claim about agreement with tree-sitter.
#         Mint one: python3 tool/pin.py oracle fz-control
```

and on a sighted one, `# oracle: 30 of 30 verdict(s) live here — square is a
measurement on this arm.` The check is deliberately cheap — a digest of the
binary and one `stat` per folio — because `arm` is a line of shell lanes
evaluate constantly and a check that opened thirty folios is a check somebody
turns off.

## 3. The refusal — a square-silent comparison is not a comparison

`standing.py --against` now asks the oracle question in the same place it asks
the tree question, **before any delta is printed**, because a reader who has
already seen `crooked 0 → 0` has already formed the claim. Two shapes are
refused and they are different news:

* **square-silent** — no board on either side read a square. Nothing below is
  about agreement.
* **one-eyed** — one side read a square and the other did not. The delta between
  a measurement and a silence is neither, and it prints as an enormous
  improvement.

`--unjudged` declares the narrow reading rather than buying silence: the label
prints beside the numbers and travels with them. Measured on four boards built
for the purpose:

| comparison | exit | verdict printed |
|---|---|---|
| blind vs blind | **4** | `NOT A CLAIM ABOUT AGREEMENT` |
| blind vs blind `--unjudged` | 1 | `UNJUDGED (declared)` |
| sighted vs blind | **4** | `NOT A CLAIM ABOUT AGREEMENT` |
| sighted vs sighted | 1 | silent |
| `--twice`, one binary | 0 | silent |

The `--twice` row is the one that mattered to get right. A stability run asks
whether a board is reproducible and makes no claim about a second parser, so the
precondition is the same one `comparable` uses for demoting `subject`: two arms
and two binaries. A gate that reddened `--twice` would be a gate lanes learn to
pass.

## 4. Prediction scoring — 4 right, 2 half, 2 wrong

Wrong first.

* **P3 wrong.** I predicted **at most two** boards on this disk carry a live
  `square`. Four do. I underestimated how many lanes had already gone looking
  for the oracle on their own.
* **P5 wrong.** I predicted the 1,305 → 5,784 node rise would not reproduce and
  the gap would shrink by more than half. On a clean tree it is 1,772 → 5,784,
  a gap of 4,012 against the original 4,479 — 10%, not half. The rise is real.
  See `RESULT-6-scala.md`: it is the *reading* of the rise that does not
  survive, not the rise.
* **P1 half.** The corollary held — the discipline that makes an arm trustworthy
  is what blinds it, 28 of 33. The mechanism did not: I said sighted lanes were
  sighted by inheriting the default work dir, and no board on this disk is,
  because the default cache carries no oracle identity and grants nothing.
* **P4 half.** Both worths moved from negative to positive, which is more than
  the "at least one" I claimed. `|residual| < 1000` and the verdict `additive`
  did not happen; the residual is −7,372 and still reads `cooperating`.
* **P2 right.** A seeded audit reads `stale` 30/30 with no code change, so "seed
  it" was the wrong design for the reason predicted.
* **P6 right.** All three corpus-only rows flip a specimen; I said ≥2 of 3.
* **P7 right.** The refusal fires on both blind shapes and is silent on `--twice`
  and on sighted-vs-sighted.
* **P8 right.** A per-arm audit is 60–92 seconds and the four-arm retake was
  242 seconds wall. Minutes, not seconds — which is why nobody paid it, and why
  the arm now says so unbidden instead of a dossier saying it three lanes later.

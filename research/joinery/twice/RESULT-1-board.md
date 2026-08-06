# Result 1 — the board is reproducible; the 7x was three different columns

Predictions in [`PREDICTION-1-board.md`](PREDICTION-1-board.md) and
[`PREDICTION-2-cache.md`](PREDICTION-2-cache.md), written before any of this ran
and unedited since. Scored at the bottom, failures included.

Everything below is taken on **pin `tenon`** (`fa7fcaee5e14`, built
2026-08-06T00:05:08Z) against **oracle `d952e2aa2c90` / tree-sitter 0.26.11**,
seat `twice`, in a private `OUTLINER_WORK`. That second half of the stamp is the
finding.

## The short answer

**The board is deterministic.** 900 numbers, five runs, nothing moved — and
nothing moved when every folio was re-pressed between runs either. The 7x spread
on scala is real and it is not a flake: **two of those three numbers are two
different columns, and the arithmetic between them is exact.**

| | reading | what it actually is |
|---|---|---|
| **9,087** | `rack`'s raw crooked | structural disagreement **plus** extras placement |
| **7,149** | scala's `soft` | where a scaladoc hangs — a choice, not a misreading |
| **1,938** | `standing.py`'s crooked | `9,087 − 7,149`, to the byte |
| **1,278** | `extent.py`, once, in June | **not reproduced.** See below |

`9,087 − 7,149 = 1,938` was the first arithmetic I tried and it landed on the
owners lane's number exactly. Two instruments, one word, two questions.

## Tier 1 — one pin, one folio set, five runs

```
5 run(s) · 30 grammar(s) × 30 column(s) = 900 number(s) compared
STABLE — every one of the 900 numbers is identical across all 5 runs.
```

`cache: kept` on all thirty each time, one generation each time. Nothing in the
parse or in `standing.py` samples a clock, a hash seed or a directory order, and
the measurement agrees.

## Tier 2 — the folio cache wiped and re-pressed before each run

Same 900 numbers, three runs, **and** compared back against the tier-1 warm
runs: **nothing moved, including across the warm/cold boundary.** A re-pressed
folio produces the same board as a kept one.

And the press itself, checked rather than believed — thirty grammars pressed
twice into two directories by the same binary seconds apart:

```
grammars 30 · byte-identical twice 30 · DIFFERENT 0 · press failed 0
```

The `lexicon.Head` / `Dfa.PatRun` padding fix holds. Nine of thirty is the kind
of number that comes back, and it has not.

## Tier 3 — the three numbers

### 9,087 and 1,938 are the same measurement, minus soft

Run today, `standing.py --audit`, scala:

```
audit: scala: 1938 crooked · 7149 soft · 131 unframed · 0 unaudited of 15957 built
```

`rack.crooked` is 9,087; `standing.audit` subtracts the runs whose bytes are
blank or whose parting rung is a declared extra, and prints 1,938. Neither is
wrong. They answer *"where do the two trees disagree"* and *"where do the two
trees disagree about **structure**"*, and both have been quoted as "scala's
crooked" in this repository. **That is the whole of the reported 7x**, and it is
a naming defect, not an instability.

### 1,278 I could not reproduce, and I am not going to explain it

It came from `extent.py`, a third instrument, and the lane that produced it
[said so and declined to claim a cause](../tenon/RESULT-4-instrument.md). Its
circumstantial evidence was three oracle libraries rebuilt mid-session. **I
tested that mechanism and it is not sufficient:**

```
seat twice   scala.dylib 72b173132661…   built 19:01
seat twice2  scala.dylib b67ef46f4c6d…   built 19:05   (same sources)
30 grammars audited under each · verdicts that moved: 0
```

Two different libraries, byte-for-byte different, same size, four minutes apart
— **every one of the thirty verdicts identical.** A plain rebuild of the oracle
does not move a number. That vindicates `attest`'s decision to digest the
oracle's *sources* rather than its library, and it means the 1,278 reading needs
a **source** change or a CLI change, of which no trace survives.

So the honest report is: the spread is **9,087 against 1,938 and it is
explained**, and **1,278 is unexplained but bounded** — one reading, one
instrument, one afternoon in a tree with no oracle attribution at all. It is not
evidence the board wanders, and it is not evidence it does not.

## What I fixed, and what each fix was worth

### 1. The board's newest column had no generation guard at all

`Held` carried three digests — folio, binary, source — and all three describe
*outliner*. `crooked` is a comparison of two parsers and **the second one was
unattributed**, so a sibling regenerating one grammar's tree-sitter sources
moved the number while every guard on the page read clean and the row printed
`graded: read`.

`Held` now carries a fourth: `attest`'s per-grammar oracle identity
(`<source-digest>/<cli version>`). A verdict whose oracle has moved prints
**`other`** rather than `stale`, because those are different news — `stale` says
the thing being judged moved, `other` says the *judge* did.

Demonstrated on real data rather than staged: the audit cache written before
this change carried no oracle, and the new board refused all thirty rows.

```
yaml  … graded: other      haskell … graded: other      verilog … graded: other
```

Cost: **283 ms** on an audited board (1.138 s vs 0.855 s warm), zero on a board
with no audit, because the identity is only computed when there is a verdict to
attribute.

### 2. The folio cache asked an mtime which binary made an artifact

`order.miss` compared `folio.st_mtime` against `BIN.st_mtime`. That answers *was
this made before the binary*, asked of a **path**. Staged with two real pins
sharing one `OUTLINER_WORK`:

| | verilog folio | verilog `nodes` |
|---|---|---|
| pin `tenon`, alone | `3ed97566244be7e3` | 22,222 |
| pin `derive-only`, alone | `811e808412d78cbc` | 22,210 |
| `derive-only` after `tenon` minted into the shared dir | `3ed975…` | **22,222** |

`cache: kept 30`. The second pin reported the first pin's row and said nothing.
Those two digests are the pair the earlier lane hit. On this pin pair the damage
is one column of one row, because the two folios agree about almost everything —
**the size of the error is a property of the pins you happen to pick, and the
silence is a property of the rule.**

A folio now carries a ticket (`<name>.folio.by`) holding the sha256 of the
binary that pressed it, published by the same atomic rename, and `miss` compares
digests. Same staging, after:

```
B's cache decisions on the shared dir: {'re-minted - another binary pressed it': 30}
B(true, private work) vs B(shared with A) rows that differ: none
```

It is strictly stronger — an mtime is structurally blind to the two-pin case —
and also strictly quieter: a rebuild landing on the same bytes, or a bare
`touch`, no longer invalidates thirty folios that are still exactly what this
binary would press. The self-test in `order.py cache` now stages *"a fresher
folio another pin minted"* and *"a folio with no record of its minter"*, and
asserts the retired rule's other half — *"an older folio this same binary
minted"* — is **kept**.

### 3. `built` stopped adding up four days ago and the board said so to nobody

Not what I came for, and it was on the page the whole time. The board's own
partition check was **red on 14 of 27 audited rows** on the first audit I ran,
before I had touched anything:

```
**BROKEN** square + crooked + soft + unaudited == built on 27 of 27 audited rows
           — BROKEN on markdown, haskell, ruby, c, bash, cpp, latex, scala,
             swift, ocaml, php, zig, julia, elixir
```

`rack` grew an `unframed` bucket ([the frame lane's
finding](../frame/RESULT-1-frame.md)) and took it out of `square`. `standing.audit`
never learned about it, so the identity was short by exactly that: 105 bytes on
c, 178 on markdown — *its entire file* — 18,354 on php, 60,067 corpus-wide.
`Held` now carries `unframed`, out of `crooked` and out of `square` as the frame
lane specified, and the check is green on 27 of 27.

### 4. A guard that is not re-derived is a guard that quietly stops checking

The way this project loses a guard is by adding a field and not adding the case
that notices it is ignored — which is precisely what happened to `unframed`. So
every run now offers each live verdict back four times with one digest replaced,
and asserts all four are refused:

```
CHECK  a verdict is refused when ANY of its four digests moves — folio, binary,
       source and ORACLE — on 27 of 27 live verdicts; the fourth is why the same
       pin could be quoted at 1,278 and 9,087
```

## The stability guarantee

Two runs are comparable when they were measured the same way, and nothing said
whether they were. Now:

```sh
eval "$(python3 tool/pin.py arm before)"     # binary + its OWN folio cache + its OWN oracle seat
python3 tool/standing.py --twice=3           # run me three times, diff every number
python3 tool/standing.py --against=was.json  # diff this tree against a saved run
```

`--twice` re-runs the board as separate processes — a loop inside one
interpreter would inherit the folio decisions, the `accepts` memo and the oracle
identity, and report a stability it never tested. Both verbs print **what moved
and what the runs differed in, separately**, so a `crooked` that moved because
the oracle moved is never read as a board that wanders.

`pin.py arm` exists because a binary is one third of a measurement. A folio is a
derived artifact of a binary, so a pin owning a binary should own the cache it
presses into; an oracle seat is the other parser in every audited column, and
without a name it is keyed on `os.getppid()` — **which shell you ran from.**

Two real arms, one command each:

```
2 run(s) · 30 grammar(s) × 31 column(s) = 930 number(s) compared
  [1] arm-tenon.json   tree fa7fcaee5e14  built 2026-08-06T00:05:08Z  one generation
  [2] this tree        tree 0177d3b91eab  built 2026-08-06T01:57:45Z  one generation
  2 binaries — what moved may be the change under test

MOVED — 20 of 930 numbers are not the same in every run, over 2 grammar(s):
  php  built 59146 → 67845 · roots 119 → 1 · damage 8699 → 0 · … · verilog nodes 22222 → 22210
```

Twenty numbers, two grammars, named. That is the report the before-arm that read
its after-arm's table could not have produced.

## The ordering question

**Yes, the default should change, and it should change to two keys.**

`crooked` is inside `built`. `damage` is `size − built`. They are **complements
over the same file** — every byte in one is outside the other by construction —
so each is blind to exactly the other, and the owners lane's "crooked is blind
to verilog" is not a quirk of verilog. Measured on this corpus:

| grammar | damage | crooked | rank by damage | rank by crooked | moved |
|---|---|---|---|---|---|
| verilog | 63,937 | 0 | **1** | **29** | 28 |
| yaml | 18,935 | 0 | 3 | 30 | 27 |
| markdown | 3,126 | 0 | 7 | 27 | 20 |
| sql | 2,423 | 0 | 8 | 28 | 20 |
| elixir | 1,559 | 17,656 | 11 | **2** | 9 |
| php | 8,699 | 24,539 | 4 | **1** | 3 |

**28 places** between the two orders on one row. Eight rows cost more wrong than
missing. Neither key is the work list.

The default is now `max(damage, crooked)`, with a **`by`** column saying which
key placed each row (`dmg` / `crk`) and a note naming the rows each key lifted.
The two numbers stay in their own columns and neither is added to the other — a
fused score is the thing this board has been fooled by four times. With no audit
live, `crooked` is zero everywhere and `max` degrades to exactly `--damage`, so
an unaudited board opens on the order it always did. `--standing` keeps the old
ratio default, which was blind to file size and is now something you ask for.

Two notes fire rather than one: `--damage` already warned it is blind to the
misbuilt bytes, and `--crooked` now warns it is blind to the unbuilt ones.

## The predictions, scored

| | claim | |
|---|---|---|
| **P1** | tier 1 flat — 900 numbers × 5 runs | **held** |
| **P2** | tier 2 flat, and 30/30 press byte-identical | **held**, both halves |
| **P3** | `1,938 = 9,087 − soft`, exactly | **held** to the byte, 7,149 |
| **P4** | the 7x is columns, not a flake | **held** for two of the three |
| **P5** | 1,278's cause is a sibling rebuilding scala's oracle | **falsified as worded** |
| **P6** | the two-pin cache lie moves the board on ≥1 row | **held** — verilog, 1 column |
| **P7** | `accepts()` reads a foreign folio fine; freshness is what's broken | **held** |
| **P8** | the sidecar closes the hazard at no measurable cost | **held** — 30/30 refused |
| **P9** | damage and crooked orders disagree by >10 places on ≥1 row | **held** — 28 |

**P5 is the one that failed and it failed usefully.** I named a *library*
rebuild as the mechanism; two seats holding two different `scala.dylib` files
returned thirty identical verdicts. The mechanism I predicted is real and is
insufficient, so the guard I built is keyed on sources — which is what `attest`
already argued and I had treated as a detail.

I also predicted, in P6, that the cache lie would be visible. It is, but it is
**one column of one row** on the pin pair I had, not the seven-witness swing the
earlier lane saw. I would have written a bolder number if I had picked different
pins, and that is exactly the point: the magnitude is a property of the pins,
the silence is a property of the rule, and only the second one is a defect.

## Two things I did not do

**I did not reproduce 1,278.** Twice now a lane has tried and neither has. It
predates oracle attribution, so the state that produced it is gone.

**I did not test the oracle guard against a genuinely different oracle**, because
there is not one on this machine to test against — `upstream/grammars/*.json`
and `.local/differential/lang/*/src/grammar.json` are byte-identical, so any
regeneration reproduces the same sources. The guard is exercised on real data
(an audit cache with no oracle recorded, refused on all thirty rows) and
re-derived every run by the digest-substitution check, and neither of those is
the same as watching it catch a live source change. It is the weakest link in
this dossier.

## Reproducing

```sh
eval "$(python3 tool/pin.py arm tenon)"
python3 tool/standing.py --twice=5      # tier 1
python3 tool/order.py cache             # every way a cached folio stops being one
python3 tool/standing.py --audit        # writes the oracle into the verdict
python3 tool/standing.py                # six CHECK lines, two-keyed order
```

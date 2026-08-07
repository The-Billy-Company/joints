# Result 10 — the record, worked: what fell, what was under-priced, what regrows

`RESULT-9-reach.md` counted 116 of 347 pages quoting our columns and never the
oracle's, and ranked them. This is the lane that worked the ranking. Predictions
in [PREDICTION-4-record.md](PREDICTION-4-record.md), scored at the foot.

**Nothing here was re-measured.** Every sighted number comes from the base board
and the twenty-one arms of `RESULT-8-sighted.md`, taken with retained pins a few
hours ago. `crooked` is under repair (`HANDOFF-crooked.md`) and is quoted nowhere
as a load-bearing number.

## What got worse, first

Four verdicts fell. All four fell in the *same direction*, which is the direction
the mechanism predicts — **a correctly-recognised extra is an `orphan` and a
misread one is `built`**, so a `damage`-only reading of a comment, docstring or
string body is biased toward calling a correct parse a regression.

| page | what it said | what fell |
|---|---|---|
| `bench.report.md` | elixir is 0 rubble, 100% standing, **0 damage** — the headline win of the rubble table | elixir is **51.8% `trued`**: it builds every byte and derives 22,210 of them under other parents. The row is off the table because it is finished on our columns, not because it is finished |
| `consort/RESULT-3-scala.md` | its title and inherited claim: scala's pair is *two overlapping regressions* | **both rows are positive**: +6,739 and +6,536 `square`, each worth nearly all the agreement scala has. Two sign flips in one page — the largest inversion on the tree. The page's *own* verdict was `unknown`, so what fell is the claim it inherited, and the refusal is what saved it |
| `changelog.d/+ocamls-comments-…` | the day's one published regression, −721 `damage` | **+448 `square`**. Already recorded by `RESULT-8`; the fragment now carries the withdrawal |
| `semi/RESULT-2-seated.md` | kotlin's −1,075 `built` is *a smaller regression inside a larger win* | kotlin finishes at **98.6% `trued`**, 247 bytes uncorroborated in total. The `built` drop is the comment bias, and the page's refusal to launder it as an artifact was right discipline reaching the wrong verdict |

Two more were **re-pointed** rather than overturned — the conclusion survives and
the number it rests on is measuring something else:

- **`verilog/RESULT-1-wall.md`** keeps its headline (the trap is real and larger
  than advertised) and gains the fact that changes everything downstream of it:
  of the 32,193 bytes verilog *does* build, **2,184 are `square` — 7.9% of what
  the oracle adjudicates**. Work that converts verilog's damage into `built` is,
  on tonight's evidence, work that converts unbuilt bytes into misderived ones.
  Its changelog fragment carries the same re-pointing. Neither could have been
  written sighted: verilog was 100% unadjudicable until this afternoon.
- **`layout/RESULT-1-scala.md`**'s *40.8% → 79.4% standing* is reach, not assent.
  Scala finishes at **33.5% `trued`** with 9,218 built bytes uncorroborated, so
  fewer than half the standing bytes are derived like tree-sitter's.

## What under-priced itself

Five pages claimed less than they achieved, every one of them by seating an extra
or a separator:

| page | priced at | sighted | × |
|---|---|---|---|
| `orphan/RESULT-1-gate.md` — php's one mend | 8,091 orphan bytes, *"twelve percent of its structural account"* | **+67,183 `square`** — the whole file's agreement | **8.3×** |
| `semi/RESULT-2-seated.md` — elixir's caesura row | +1,329 `damage` | **+23,878 `square`** | **18×** |
| `orphan/RESULT-2-wall.md` — kotlin's `_string_start` | +20,728 `built`, and the page says it is *"the number I would bet on and not the number I would report as measured"* | **+27,143 `square`**, now measured | 1.31× |
| `interior/RESULT-2-board.md` — julia's string interior | +5,634 `built` | **+8,910 `square`** | 1.6× |
| `layout/RESULT-1-scala.md` — scala's offside troupe | +7,753 `built` | **+6,739 `square`** — all of scala's agreement | — |

## What holds, explicitly

Six pages survive a sighted reading, and saying so is a result:

1. **`orphan/RESULT-2-wall.md`** — its subject is kotlin at 98.6% `trued`, so the
   orphan-versus-built argument was reasoning about a forest the oracle
   corroborates. The **mechanism it established is now the rule every other page
   on this list is judged by**, including the four that fell.
2. **`orphan/RESULT-1-gate.md`** — `orphan > 0` iff the file mended is a fact
   about one line of `gather.zig`, checkable at 30 of 30 rows; no oracle needed.
3. **`interior/RESULT-2-board.md`** — its disputed P2c defence (*`built` up with
   `describes` down is consolidation, not reading less*) is now proved rather than
   argued: julia is 89.1% `trued`.
4. **`consort/RESULT-3-scala.md`** — it refused a verdict and asked to be
   re-priced on a healthy tree. Discharged; the refusal was right.
5. **`semi/RESULT-2-seated.md`** — *exactly two grammars moved* holds on
   twenty-four columns including five of the oracle's.
6. **`verilog/RESULT-1-wall.md` Part 4** — *"`square` is the only column here not
   made out of the thing it checks"* reached without an oracle, from `stretch`.

## `damage = 0` is two facts and the board prints one column

php, html and elixir read **`damage 0` and `standing 100.0%`** — the two columns
every page in this repository quotes. php and html are finished. **Elixir derives
48% of its file under parents tree-sitter does not use.** On the base board 15
grammars read `damage 0` and 13 of them are `trued 100%`; the exceptions are
elixir (51.8%) and toml (99.2%).

A note on a page cannot fix this, because the next page copies the row and not
the note. The fix is one column in the printer — **never print `damage` in a row
with no `trued` in it, and print `trued —` rather than nothing when no oracle was
asked**, so the absence is visible in the row instead of reading as a pass. That
is [HANDOFF-damage-zero.md](HANDOFF-damage-zero.md), owned by whoever holds
`tool/standing.py`, with two smaller changes beside it (split the `whole N of 30`
tally into `reached whole` and `agreed whole`; stamp an unaudited board
`unsighted` on its face, the way it already stamps the tree it read).

Also shipped, and mine: `askance.py --grammars`, which prints
`damage`/`standing`/`trued`/`unvouched` in one row per grammar so the gap is
arithmetic rather than prose.

## The fraction, and whether 116 is a number or a rate

`sighting.py`. It imports `onlydamage.py`'s classifier rather than copying it and
adds two things it cannot see. First a **table-aware** reading: the triage's
proximity regex refuses to cross a `|`, and every correction this lane wrote puts
the column name and its number in different cells, so without that pass the sweep
scores its own work as no work — it graded this lane's own handoff page as blind.
Second the two columns **derived** from `square`: `trued` (`square / size`) and
`unvouched` (`built − square`) are claims about a second parser as surely as
`square` is, and neither is in the triage's vocabulary — so the column this lane
is asking the board to print would have left every page that printed it reading
as blind.

```text
379 pages under research/ and changelog.d/
  sighted  156   quotes the oracle, or proves two forests byte-identical
  blind    102   quotes only our own words about our own forest
  silent   121   no measurement in it
60.5% of the 258 pages that report a measurement have asked a second parser.
```

**116 is a rate, not a number.** `onlydamage.py`, unchanged, read **116 of 347**
when `RESULT-9` ran, **113 of 354** half an hour later, and **109 of 379** now.
The record grew by **thirty-two pages** during one lane. Ten of the corrections
are mine and the blind count still only fell by seven, because the population is
being refilled as fast as it is drained: **five blind pages have been written
since the base board that made sight possible was minted, three of them in the
three minutes before this paragraph** (`unjudged/RESULT-9-verilog.md` at 15:21Z
and two fragments at 15:22Z and 15:23Z). Every measured page in the population is
uncommitted, so the whole thing is two days old. This is not a historical backlog.
It is the current output rate, and no page-level correction touches it.

So the fix is upstream of any page, and it is a gate:

```text
sighting.py --gate --since <ref>   fail on a page changed since REF that is blind
sighting.py --gate --max N         fail when the population exceeds N
sighting.py --risk                 the blind pages wearing the known-bias shape
```

The `--since` form is the one that belongs in CI and it is inert tonight, because
with the record uncommitted every page is "changed since HEAD". The `--max` form
works now and only ever has to fall.

**The tail is bigger than the ranking claimed.** `RESULT-9` says that below rank
8 a sighted reading resizes a number rather than changing a verdict. `--risk`
tests that against the shape `RESULT-9` itself defined — our columns only, a
declared extra as the subject, and a seating that **cost** something, which is
ocaml's fragment exactly — and **39 of the 102 wear all three.** That does not
make them wrong; it means 39 pages, not 8, are in the class where the bias has a
known direction, and the three highest-ranked ones I opened had a sign flip, an
8.3× and a withdrawal in them. The rest are the next lane's worklist and `--risk`
orders it.

## Predictions, scored

Five right, three half, one wrong. Leading with the miss.

- **P4 — three named pages under-price their own win by more than 2×. WRONG on
  its own naming.** I named `interior/RESULT-2-board.md` as *php's* string
  interior at 7.7×; it is **julia's**, and it is 1.6×. All three named pages do
  hold and all three did get a larger number, so the shape was right and the
  identification was wrong: I read a php row off `RESULT-8` and attached it to
  a page I had not opened. The 7.7× row exists and belongs to
  `orphan/RESULT-1-gate.md`, which I had not named.
- **P1 — the overturns are elixir's, at least two pages state it. HALF.** The
  named page is right (`bench.report.md`'s table) and it is the **only** one:
  swept over all 102 blind pages, nothing else calls elixir finished.
  `cpp/RESULT-1-crooked.md` and `unjudged/RESULT-5-tripwire.md` had already found
  the trap from the other end and named elixir as the exhibit.
- **P2 — verilog holds and re-points; its fragment overturns. HALF.** The page
  holds and re-points, as predicted. The fragment does **not** overturn: its
  arithmetic is `built`, it is honestly labelled `built`, and re-pointing it is
  enough. I predicted an overturn because I expected the fragment to have claimed
  correctness, and it had not.
- **P3 — haskell is an overturn, on a page outside the top three. WRONG-ish,
  HALF.** haskell's board square really is 5 bytes, and `vacuity/RESULT-2-arms.md`
  already carries it — so the overturn had happened before I arrived and there was
  no *unsettled* page left to overturn. Predicting a casualty another lane had
  already buried is not a hit.
- **P5 — I ship the wording and the survey and hand the board change over.
  RIGHT**, and the handoff is narrower than I expected: one column, not a verdict.
- **P6 — the 116 regrows; the fix is a gate with a ceiling and an exit code.
  RIGHT**, and far faster than the week I predicted: five blind pages since the
  base board, three of them inside three minutes.
- **P7 — a page moves under me while I work. RIGHT**, and by more than a page: the
  population grew 347 → 379 during the lane, and all five of the freshest blind
  pages are other lanes' live work, which is why I cited them and did not edit
  them.
- **P8 (implicit, in the outcome table) — ~95 hold, ~14 re-price, ~4 overturn.
  HALF.** The overturn count is exactly 4. The other two buckets are unscoreable
  as stated, because I settled 10 pages by hand and 92 by class, and *"holds"* over
  a page nobody opened is a claim about the ranking, not about the page. The
  `--risk` sweep is the honest version of what I should have predicted: not how
  many hold, but how many are in the shape where holding cannot be assumed. 39.

## The instrument I trust least

**My own `sighting.py`, which was wrong twice, and both times it took a page I had
written that hour to catch it.**

First it classified this lane's own `HANDOFF-damage-zero.md` — a page whose
opening table is three grammars against `square` and `trued` — as **blind**. That
bug is exactly the bug it exists to correct: `onlydamage.py` cannot see a column
name and its number in two different *cells*, and my first pass could not see them
in two different *rows*. A markdown table states its columns in a header and its
numbers beneath it, and a reader that only pairs within a row misses the commonest
shape a number is written in on this tree.

Then, fixed, it classified one of this lane's own **changelog fragments** as blind
— the one whose whole subject is `trued`. The vocabulary it inherited lists
`square`, `crooked`, `unframed`, `soft` and five more, and does not list `trued`
or `unvouched`, which are *arithmetic on `square`*. So the sweep meant to find
pages that never asked a second parser could not recognise the column this lane
is asking the board to print. Had the handoff shipped and the board changed, every
page printing `trued` would have read as blind, and the sweep would have reported
the fix as a regression.

What makes it the least trustworthy rather than merely the buggiest is the
direction and the audit. Both failures went toward **more blind pages** — toward
a louder finding and more work for me — and both passed the instrument's check,
because the count it printed was plausible, monotone with the older sweep, and
moved the right way when I fixed a page. Nothing in the output could have told me
102 from 107. The only reason I caught either is that a page I had written that
hour appeared in a list of pages that had never asked the oracle, and I recognised
the filename. **A sweep I can only audit by recognising my own filenames is a
sweep I cannot audit at all**, and the tail of 102 contains no filenames I wrote.

The general form is the one this repository keeps re-learning, and it now has a
third instance beside `joints state`'s row and `state --census`: **an instrument
that reduces a two-part fact to one number is reporting one of two facts and not
saying which.** `onlydamage.py` reports "quotes an oracle column" and means
"quotes one within 24 characters, on one side of a pipe". Both readings are
defensible; only one is the question. `sighting.py --json` now emits `theirs`,
`theirs_tabled` and `theirs_derived` as separate fields for that reason, so the
next reader can see which third of the answer they are holding.

Runner-up: **the mtime buckets in the same script.** *"68 of the 102 were
written today"* is really *"68 have an mtime from today"*, and every page I
edited took a fresh mtime from me. The regrowth conclusion does not rest on it —
it rests on the five pages timestamped after the base board was minted, which is
a comparison between two clocks on one disk — but the histogram flatters the
finding, and I am the one who moved ten pages into today's bucket.

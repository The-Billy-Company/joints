# consort — the residual is a property of the fixture, not of the rows

`vacuity/RESULT-5-pairs.md` priced five two-row subsets and found two that are
not the sum of their parts: **kotlin at −20,288** and **scala at +5,500**. It
called both *cooperating* and read swift's zero as *a seated row that changes
nothing in any combination available to it.*

Those are three claims about **rows**, taken with an instrument that only reads
one **file** per grammar. This lane took the same pairs over fixtures of its own
choosing, and over a second tier the pair sweep never consulted.

| file | what it holds |
|---|---|
| `PREDICTION-1-mechanism.md` | ten predictions, written before a measurement |
| `RESULT-1-kotlin.md` | the mechanism, and what kotlin's seating is actually worth |
| `RESULT-2-swift.md` | the inert row: alive, exercised, and mis-motivated |
| `RESULT-3-scala.md` | the smaller pair, and the tree it was priced on |
| `RESULT-4-clearance.md` | does "fourteen rows, no collateral" survive · predictions scored |
| `PREDICTION-2-oracle.md` | eight predictions on the blindness, the retake and the specimens |
| `RESULT-5-blindness.md` | the blast radius of the empty oracle column, and the three closes |
| `RESULT-6-scala.md` | scala's pair re-taken clean, with both arms sighted |
| `RESULT-7-witnesses.md` | the three unwatched rows, their specimens, and their real worth |
| `gate.py` | price a pair over fixtures this lane chooses, not the corpus board |
| `witnessed.py` | join a board-arm zero to the specimen tier - the check nobody ran |
| `PREDICTION-3-sighted.md` | ten predictions on the re-take, written before an arm was built |
| `RESULT-8-sighted.md` | the whole family re-taken with an oracle in all twenty-one arms |
| `RESULT-9-reach.md` | which other published pages are `damage`-only, ranked and costed |
| `HANDOFF-crooked.md` | a negative `crooked`, its cause, and why this lane did not fix it |
| `blind.py` | which retained boards ever read a square, and which were merely told |
| `retake.py` | re-price a pair from a refreshed snapshot, minting each arm's oracle |
| `sighted.py` | build · mint · board every arm of the ablation family, three at a time |
| `collateral.py` | the falsifier: every column of every grammar an arm cannot seat |
| `onlydamage.py` | the 116 pages that quote our columns and never the oracle's |
| `PREDICTION-4-record.md` | eight predictions on working the ranking, before a page was edited |
| `RESULT-10-record.md` | the ranking worked: four verdicts down, five under-priced, six holding |
| `HANDOFF-damage-zero.md` | why `damage 0` is two facts, and the one column that would say which |
| `sighting.py` | how much of the record has asked a second parser, and whether that is rising |
| `RESULT-11-quotation.md` | the cross-lane quotation hole, and the half no gate reaches |
| `instrument.py` | what each instrument can be asked, read off its own record declarations |
| `RESULT-12-refusal.md` | the gate's false-refusal rate, and which half of it now blocks |
| `sighting.since` | the pin the gate ratchets from: committed, append-only, last line live |
| `sighting.adjudicated.json` | 45 sampled refusals, each read in full and judged by hand |
| `askance.py` | per grammar: what we cover against what the oracle corroborates |
| `borrow.py` | where a negative `crooked` comes from, priced per run kind |
| `witness/` | the fixtures, each isolating one of a pair's two constructs |

## The one-sentence answer

**No pair on this board is two rows cooperating.** Kotlin's two rows are mechanically
independent - each moves its own construct by the same amount whether the other
is seated or not - and their −20,288 residual is what `built` does when two
constructs sit 25 bytes apart in the head of one file. Swift's "inert" row is
**alive and already had a bound falsifier**: it flips two specimens the moment
it is un-seated, and reads zero on the board only because `Chunked.swift`
contains no `/*`. Scala's pair was priced on a tree carrying a live regression
that had already quadrupled scala's control damage.

**And none of that family was a claim about agreement with another parser.** All
nineteen arms read `square 0`, because the private work dir that makes an arm an
arm is where the oracle's verdicts live. 28 of the 33 boards retained on this
disk are blind the same way. `RESULT-5-blindness.md` traces it, `pin.py oracle`
ends it, and `standing.py --against` now exits 4 rather than print a delta
between two silences. Re-taken clean and sighted, scala's +5,500 residual is
−7,372 and both its rows are worth more than nothing
(`RESULT-6-scala.md`) — and all three of the negative-worth rows turn out to be
positive-worth once asked the only question that involves a second parser
(`RESULT-7-witnesses.md`).

**Re-taken whole, the clearance survives — and it is now the first time it has
been claimed.** All twenty-one arms of the ablation family were re-run with an
oracle minted inside each one (`RESULT-8-sighted.md`): 29 of 30 rows sighted in
every arm, **13,728 cells of twenty-four columns, zero collateral**, corroborated
by byte-exact parse trees that consult no oracle at all. What did not survive is
the *pricing*: haskell's row is worth 9,168 on `damage` and **5** on `square`,
elixir's `_newline_before_do` is worth 1,329 on `damage` and **23,878** on
`square`, ocaml's comment row **changes sign**, and no pair anywhere on the board
is two rows cooperating — every `square` residual is a ceiling, elixir's most
starkly, where each row alone costs 99.996% of the grammar's whole agreement.
`RESULT-9-reach.md` counts what else is exposed: **116 of 347 published pages
quote a column of ours and never one of the oracle's.**

## The method

`gate.py` prices a pair exactly as `attribute.py pairs` does - `worth(r) =
D({r}) − D(none)`, `residual = joint − Σ worth` - over any file, using the same
retained pins and reusing `standing.rows`/`tops`/`union` rather than re-spelling
the span reader. On the corpus file it re-derives `pairs.json` **to the byte**
for both kotlin and scala, which is what makes its answer on a different fixture
worth reading:

| fixture | worth(2) | worth(12) | joint | residual |
|---|---:|---:|---:|---|
| `Maps.kt` (the corpus file) | 20,737 | 19,229 | 19,678 | **−20,288** |
| `witness/kotlin-separator-only.kt` | **0** | 5 | 5 | **+0** |
| `witness/kotlin-gate-early.kt` | 13 | 601 | 602 | −12 |
| `witness/kotlin-gate-late.kt` | 203 | 601 | 602 | −202 |

The last two differ in one byte position - where the single string literal sits
in an otherwise identical 200-statement file - and the residual moves 17×. A
number that moves with the fixture and not with the rows is not describing the
rows.

## What this lane did not touch

`src/press/`, the mend paths and `tool/rack.py` belong to other lanes; no Zig
was changed here. Scala's regression is named and handed back, not chased. No
`.baseline`, no existing `.expect` claim and no board number was edited to make
anything agree; the two `.expect` files touched in the first pass carry
corrected **prose headers** and identical assertions, and the four added in the
second are new files asserting things that were true before they were written.

## The instrument I trust least

`RESULT-4-clearance.md` named **`gate.py`, this lane's own**, and the fact that
it reproduces `pairs.json` to the byte is exactly why. The second pass names
**`crooked`**: see the foot of `RESULT-5-blindness.md`'s sibling note in
`RESULT-6-scala.md`. It read **−335** on one arm of the retake, and the board's
own consistency check — `square + crooked + soft + unframed + unaudited ==
built` — passed on that arm, because a negative summand satisfies an identity
just as well as a real one.

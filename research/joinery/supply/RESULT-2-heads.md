# Result 2 — how many readings a repair throws away

Taken on `joints 1885792a7` · tree `4f018b60f` (pin) · oracle `d85e736fa`
(30 of 30 live, 30 attributed). No source changed to get any number here; every
figure below comes from `joints parse --scars` and `JOINTS_TRACE=quire`,
both of which the runtime already emitted.

This lane exists to answer one question the ranked work list has been carrying
for a while: **per-reading error cost.** Upstream's first comparison rung is
error cost, `Reading.beats` has no such rung, and the standing explanation is
that it would be vacuous. `arity/RESULT-3-structure.md` proved that rung
vacuous from the tables. This one asks the other half - not "would the rung
separate anything", but "how much is being thrown away where it would have
looked". The answer is not zero, and the reason the rung is vacuous turns out
to be a different fact than the one written down.

## The premise, confirmed in the source rather than assumed

Every repair this runtime performs collapses the live set to exactly one
reading, and does it by construction rather than by accident:

- `mended`, `fell` arm (`gather.zig:1182-1204`) - `bare()` clears `x.live`,
  then one perch is stood up in state zero and one `Reading{ .top = 0 }` is
  appended.
- `mended`, `keep` arm (`gather.zig:1206-1208`) - `x.live` cleared, one
  `Reading{ .top = top }` appended.
- `supply` (`gather.zig:1378-1382`) - same shape, and the comment says it
  outright: *"Every other reading died with this one; the parse stands where
  the repair left it, exactly as `mended`'s `keep` leaves it."*

The code already knew. `mended` reads its `heads` field at `gather.zig:1163`
under the comment *"Read before either branch below, because both clear
`live`"*. So the premise holds, and it holds harder than the note I inherited
claimed: the two branches do not merely agree on the count, they both leave
**one** reading, and that reading is a fresh `Reading` whose `rank` and `heft`
are the struct defaults - zero. A repair does not just fail to distinguish
readings, it erases the two numbers `beats` compares.

That gives the vacuity a sharper cause than "the mends counter is per-parse".
`x.mends` being per-parse is a symptom. The cause is that **between any two
repairs, every live reading descends from the single reading the previous
repair left standing.** They cannot have taken different repairs, because
there was only ever one of them to take a repair. No per-reading counter can
fix that, wherever you put it.

## So the rung is vacuous. Is the population?

Those are different questions and only the first one was ever answered. A
repair firing while several readings stand is a repair discarding readings
without judging them - which is exactly the site a cost rung would want to
look at, and the `Scar.heads` field has been recording the count all along.

Its doc (`quire.zig:164-177`) is worth reading before trusting it, because this
field was already wrong once in the flattering direction: its first spelling
counted roots *after* the unwind, which under `--mend=keep` read **zero on
every scar of every grammar** - a field that passes every test by being
constant. It was moved to the refusal, before either branch touches `live`.

Swept over all thirty corpus grammars:

```
CORPUS  scars=3,326  heads==1: 2,689  heads>1: 637  (19.15%)  max=39
distribution: {1:2689, 2:440, 3:95, 4:39, 5:22, 6:16, 7:4, 8:11,
               9:2, 10:1, 11:3, 16:1, 18:1, 36:1, 39:1}
```

**Just under a fifth of every repair in the corpus fires with more than one
reading standing**, and the column reads 1 through 39, so it is not constant
again. Eighteen of the thirty grammars scar not at all; the multi-head sites
live in five:

| grammar | scars | heads=1 | heads>1 | max |
|---|---:|---:|---:|---:|
| haskell | 919 | 564 | 355 | 39 |
| verilog | 2,015 | 1,749 | 266 | 4 |
| markdown | 79 | 65 | 14 | 2 |
| kotlin | 2 | 1 | 1 | 2 |
| scala | 4 | 3 | 1 | 2 |
| sql | 245 | 245 | 0 | 1 |
| ruby / ocaml / swift / julia / zig / bash | 57 | 57 | 0 | 1 |

haskell is the concentration: 38.6% of its repairs meet an open ambiguity, and
one of them meets thirty-nine readings.

## The one number that reframes the item

Split those same scars by which repair fired:

| repair | heads=1 | heads>1 | % multi |
|---|---:|---:|---:|
| delete (`fell`) | 2,609 | 636 | 19.6% |
| supply | 80 | 1 | **1.2%** |

**636 of the 637 multi-head repairs are deletions. One is a supply.** Against a
19.15% base rate, supplies are essentially absent from exactly the sites where
several readings are standing. That asymmetry is not a coincidence and it is
not a heuristic misfiring - it is written into where the rule asks its question.

`supply` asks `x.spent`, a single perch, and the docstring is explicit about
why (`gather.zig:1283-1285`): *"Not `x.live`: a fold under `x.lone` shrinks the
perch array, so a reading's recorded top can be an index that no longer
exists."* That is a real hazard and a deliberate narrowing. But the rule this
lane was built to implement did not say that. `PREDICTION-1-insert.md`, clause
3, says the candidate must be unique **"across every live reading"**. The
implementation narrowed the rule's domain from *the live set* to *one perch* -
for a sound reason, and at a cost nobody had priced.

This is the price: at 637 walls, between 1 and 38 readings were standing that
the supply rule never asked. All of them were then deleted.

And `x.spent` is not an arbitrary member of that set - it is only written when
a **rank-0** reading dies (`gather.zig:2392-2395`, `2434-2437`, both guarded by
`if (rank == 0)`; `alone`'s two sites at `2602`/`2624` are unguarded because
there is only one reading there). So the perch the repair is computed from is
by construction the *table's own* reading, and every speculation standing
beside it is unrepresented.

## Why the rung is downstream of something bigger

Put those two facts together and the ranked item changes shape.

At a wall, **every** live reading refused the token - that is what makes it a
wall. So even with a per-reading cost field wired into `beats`, all N readings
would carry the same cost, because they have taken the same repairs (there was
one reading to take them) and they are all about to take the same one (there is
one `x.spent` to compute it from). The rung would still separate nothing.

Per-reading error cost is not a rung you can add. It is downstream of
**per-reading repair**: until two coexisting readings can be repaired
differently - one supplied a `}`, its rival deleted a token, a third left alone
- there is nothing for a cost to be the cost *of*. The tables are not what makes
the rung vacuous. The repair architecture is.

That reorders the work. The cheap first rung is not `beats`. It is widening
`supply`'s question from one perch to the live set, which is the rule as it was
originally written, has a measured population of 637 sites, and does not
require a cost field to exist at all.

## The check I ran that found almost nothing, and what it cost to believe it

If `x.spent`/`x.refused` can go stale - they are reset once per parse
(`gather.zig:1011-1012`) and only rewritten when a rank-0 reading dies - then a
wall met only by speculations would report a state from an earlier token. That
is falsifiable from outside: a stale state would sometimes *admit* the very
symbol it is reported as refusing.

First run said 0 of 132 distinct (symbol, state) pairs, both grammars. It was
wrong. `joints state` refuses a folio - it exits 2 and prints nothing - and
my check read that silence as "does not admit". **The zero was the tool's
silence, not the table's answer**, which is the exact trap `TESTING.md` warns
about and the same
one `Scar.heads` itself fell into. Re-run against the `grammar.json`, with the
exit code asserted, a positive control drawn from each state's own row (66 of
66 states) and a negative control (a bogus symbol, absent everywhere):

- heads=1: **0 of 2,160** report a state that admits the refused symbol.
- heads>1: **4 of 473** - all haskell, all on `=`, states 339 and 342.

Four is not nothing, but it is not staleness either. Both states hold a *fold*
on `=` (`339: fold expression -> variable`, `342: fold expression -> name`),
and `gather.zig:2433` has a legitimate path that produces exactly this report:
a fold the table names but the stack cannot make sets `refused = state` and
marks the reading dead. A state that refused a symbol it has a fold on is that
arm, self-consistently. **The staleness hypothesis is unproven and this test
cannot prove it** - it cannot separate a stale field from a failed fold. Left
open rather than claimed.

## Why supply stands down, in its own words

`declined` traces its reason (`gather.zig:1420-1424`). Over the same two
grammars, one parse each, default policy:

| grammar | stood down | `forked` | `none` | `ground` | supplied | spurned |
|---|---:|---:|---:|---:|---:|---:|
| haskell | 552 | 209 | 343 | 0 | 46 | 20 |
| verilog | 1,971 | 1,139 | 432 | 400 | 33 | 11 |

**`forked` is the single largest reason verilog declines to supply** - 1,139 of
1,971. That is `follows` walking toward a candidate, hitting a declared
conflict, and refusing to say. It is the same shape as the verilog leaf item:
a fork the walk will not adjudicate. So supply's reach is bounded twice over -
once by asking a single perch, and once by a walk that stops at the first fork
it meets.

## What the next lane inherits

1. Widening `supply` from `x.spent` to the live set is the cheapest rung with a
   real population (637 sites). It needs the dangling-perch hazard in
   `gather.zig:1283-1285` solved first, and clause 3's uniqueness test then has
   to mean unique *across* readings, not unique *within* one - which is a
   stronger bar and may spend some of the 637 on `spurned` rather than on
   supplies. That is the right failure: `spurned` is a counted refusal, not a
   guess.
2. `forked` bounds it independently. Widening the domain does not help if the
   walk still stops at the first declared conflict in each of the new perches.
3. Per-reading error cost should not be attempted before either. It has nothing
   to measure until repairs can differ per reading.

## What I trust least

**The decline table is one parse of one file per grammar, and the offsets I
matched it against are weak.** I bucketed each `stood down` line to a scar by
exact offset, and verilog's `forked` declines matched zero multi-head walls
while its `none` declines matched 262. That is either a real split or my
matching dropping rows on the floor; the totals per grammar are sound because
they are direct counts of trace lines, but the multi/single split inside them
is not, and I have not quoted it as a finding.

**`heads` is a count, not an identity.** It says how many readings stood, never
which - so "between 1 and 38 readings the rule never asked" is arithmetic over
the count, not a demonstration that any of those readings had a repair
available. The 637 is an upper bound on what widening could pay, and it could
pay nothing: the unasked readings may all have been in configurations with no
candidate either. Nothing here measures that, and the honest form of the claim
is that the population is non-empty, not that it is valuable.

**One binary, one policy.** Everything is `--mend=fell` (the default), which is
why `delete/keep` is 0 in the split table rather than small. Under `--mend=keep`
the perch that survives is different and the whole `heads` distribution could
move. Not measured.

**The four `=` scars are attributed by reading, not by instrument.** I matched
them to `gather.zig:2433`'s fold-failure arm because the states hold folds on
`=` and that arm produces this exact report. I did not observe the arm firing.
A trace on that `orelse` would settle it in one run and I did not add one.

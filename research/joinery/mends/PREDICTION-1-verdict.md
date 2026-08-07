# Prediction 1 — what the `verdict()` repair actually moves

Written before running anything except one confirming parse of `Maps.kt`, whose
stderr I already had from the brief and from
`research/joinery/board/PREDICTION-1-order.md`:

```
joints: kotlin: blind to 8 externally scanned terminal(s)
joints: upstream/sources/Maps.kt: unexpected (?:[^\r\n]*) at 270 in state 433, 419 roots, mended 142 over 142B
joints: kotlin: lexer on (?:[^\r\n]*) in state 433 [no stand-in for _string_start]: …
```

`stamp.verdict()` takes the **last non-blank line**. On this row that is
`inquest`'s, which is prefixed with the *grammar* name and not the source path,
so `behind()` returns None and the fallback `line.split(": ", 2)[-1]` hands back
inquest's prose as if it were the stop.

The brief I was given says the field that breaks is `mends`, the victim is
`walls.py`'s `voice`, and the repair is "reportedly one line". I was told to
verify that rather than inherit it. These five are what I have **not** measured.

---

## P1 — `mends` is the smallest part of it

`verdict()` is not a `mends` reader. It is the single input to `outcome()`, and
`outcome()` derives **six** fields from the string it returns: `kind`, `reach`,
`verdict`, `roots`, plus the `at` / `wall` / `stray` properties computed off
`verdict`. Only `blind` and `unsound` are searched over the whole stderr.

Inquest's line contains `in state 433` and no `at N`, so I expect the whole
record to be wrong on a walled row, not one field of it.

**Predicted**, for every grammar whose stderr carries a third `inquest` line:

- `mends == 0` (as briefed), and `roots == 1`
- `kind == "state"` — not `"mended"`
- `reach == 0`, because `AT` finds no byte and `ask(tree=None)` never triggers
  the forest re-run that a `"mended"` kind would have asked for
- `wall is None` and `at is None`

**Falsified by:** any walled row where `kind`, `reach` or `wall` is already
correct today. If only `mends` is wrong, the brief's framing is right, my
"it is bigger than one field" claim is wrong, and I should say so first.

---

## P2 — `voice` reads 0.0 for a reason the brief does not name

The brief says `voice` "divides by" `mends` and therefore reads 0.0. `voice` is
`mends / len(distinct)`, so a zero numerator does that. But `walls.peel()` takes
`out.wall` and `out.stray` to decide where to step, and returns on round one
when both are None — which P1 says they are.

**Predicted:** on every walled grammar `walls.py` reports `crossed == 0` and
`distinct == []`, so `voice` is 0.0 via the **empty-denominator** branch, and
the mend count is not even reached. The peel — the instrument's whole middle
third, the thing its docstring calls "the bounded-tail-versus-second-project
ratio" — produces nothing at all and says so only in a `why` column.

**Falsified by:** any walled grammar reporting `crossed > 0` today.

**If it holds**, the honest statement of the defect is not "voice divides by a
zero" but "`walls.py` has not measured a wall on a walled grammar since the
inquest line was added", and fixing `mends` alone would leave `voice` reading
`something / 0 → 0.0` — still 0.0, still wrong, and now wrong invisibly.

---

## P3 — the repair is one line, but the *anti-vacuity* is not

The fix I expect to need: pick the last non-blank line that `behind()` claims,
rather than the last non-blank line. That is one expression.

`stamp.probe()` already drives `verdict()` across eight `SHAPES` and passes.
Reading them: **not one has a line below the verdict.** The nearest, `"a warning
above it"`, puts the noise on top — the only side the old reader survives.

**Predicted:** adding a shape with an `inquest` line *below* the stop reddens
`stamp.py probe` against the current code, and the eight existing shapes stay
green under the repair. That is the measurement that makes the fix a fix rather
than an assertion.

**Falsified by:** the new shape passing before the repair (my diagnosis is
wrong), or any of the eight existing shapes reddening after it (the repair is
narrower than I think and I have broken a real case).

---

## P4 — other readers of the same field exist and are wrong the same way

`sole.py` exists to enforce that `stamp` is the only reader of a verdict. I
expect it has held for the *rule* and not for the *line selection*, because
picking a line off stderr does not look like reading a verdict.

**Predicted:** at least two more instruments select a stderr line the same way
and are wrong on the same 17 rows. My candidates before looking:
`tool/specimen.py` (its own `MENDED`, line 106) and `tool/order.py:283` (a
`reversed(...)` `next()` over the combined streams).

**Falsified by:** finding zero or one. `sole.py` passing today while two readers
are wrong would itself be the twenty-third instrument.

---

## P5 — my own flattering number, named in advance

The repair makes `ask(tree=None)` see `kind == "mended"` on 17 rows, which
triggers the forest re-run at `stamp.py:709`. `reach` on those rows goes from
**0** to `furthest(tree)` — most of the file.

So every instrument that sums `reach` is about to report a very large
improvement, and **the parser will not have changed by one byte**.
`census.py`'s "bytes read" total is the specific number at risk.

**Predicted:** corpus-wide `sum(reach)` rises by more than 100,000 bytes across
the repair, with a binary whose sha256 is unchanged.

**Falsified by:** a rise under 100,000, or any change in the pinned binary's
digest across the two measurements — the second of which would mean I measured
two parsers and the number means nothing at all.

**If it holds** I must report that rise as an instrument correction in the same
sentence as the number, every time, and no report of mine may quote a
before/after `reach` delta as progress. This is the flattering number inside my
own work and it is very large.

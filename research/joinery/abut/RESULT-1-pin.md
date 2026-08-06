# Result 1 — the pin, and what it was actually refusing

Measured 2026-08-05 against `PREDICTION-1-pin.md`. Four predictions, four held,
and one of them held in a way that makes the ceiling a claim no corpus can check.

## P1 — held. The handover was wrong about the mechanism

The brief said `step`'s progress pin **refuses** a zero-width answer that moves
no memory, and that seating julia's cohort needs the pin relaxed. It does not.
The pin was a single slot holding the last `(offset, symbol, shape)`, and it
refused an exact repeat of that triple and nothing else. A memoryless hand's
**first** answer at an offset came back fine.

So there was nothing to relax. What the pin could not do is *prove* anything: one
slot cannot see a cycle longer than one, and "no hand has spun yet" is not a
termination argument. The work was replacing an argument that happened to hold
with one that has to.

## P2 — held. The hole is a two-cycle, and it is now a test

`A`, then `B`, then `A`, at one offset with the memory unmoved: the second answer
overwrote the slot that would have refused the third. Two hands taking turns
never repeat a *consecutive* pair, so the slot could not see that spin however
long it ran. Nothing in the tree reached it, because every zero-width hand seated
before now either moves a stack (python's dedents pop a column, html's implied
closes pop a tag) or is the only member that can answer at its offset. A cohort
of five memoryless markers is the first arrival for which one slot is not enough.

`outside: the ledger refuses the two-cycle the old slot let through` is that
sequence, written as the four calls that walk it.

## P3 — held, 30/30

The ledger replaced the slot as a separate step, before the abut hand existed,
and every one of the thirty grammars was tree-identical to the pin. That is the
right bar for this half: it refuses everything the pin refused plus the
two-cycle, so it may not admit anything new, and twenty-nine of thirty would have
been a defect rather than a control.

## P4 — held, and the measurement is worth more than the prediction

The stated falsifier was a grammar whose parse changes with the ceiling lowered
to 96. It does not. So the ceiling was lowered until something moved:

| `Spent.ceiling` | grammars tree-identical to 256 |
|---|---|
| 16 | 30 / 30 |
| 4 | 30 / 30 |
| 2 | 29 / 30 — python moves |
| 1 | 28 / 30 — python and scala move |

The deepest run of zero-width answers at one offset anywhere in the corpus is
**three**. The ceiling is 256, so the corpus exercises about 1% of it, and the
number that clears python's dedent run is not the number that bounds the loop —
`offside.Columns.max` is 96 and no file in the corpus closes more than three
blocks at one offset.

**That is the honest state of the ceiling: it is untestable from this corpus.**
It is a bound on a spin nothing here performs, which is exactly what a
termination argument is for, and it means the only thing exercising it is the
unit test that drives a hand answering a fresh symbol at a fresh shape 1,024
times and counts 256 admissions. If that test were deleted, the ceiling would be
dead code that every board measurement agrees with.

## The termination argument, as it now stands in the file

Three facts and the conclusion is arithmetic:

1. the offset never goes backwards — the walk resumes each token from the end of
   the last, so `at` is monotone and bounded by the file;
2. a hit with extent advances it, and `step` returns those without consulting the
   ledger at all, because the cursor moving *is* the proof;
3. a hit without extent is counted, and the count has a ceiling.

At most `ceiling * (n + 1)` zero-width answers over a file of `n` bytes. The
bound does not depend on the grammar, on which hands are seated, or on anything a
hand promises about itself — which is the property the slot could not offer.

The per-`(offset, shape)` symbol set is the second arm and it is quality rather
than termination: a ceiling alone terminates by exhaustion, emitting 256 junk
tokens first. Memory moving clears that arm, which is what lets a dedent run
through while `A B A` at one unmoved shape is refused.

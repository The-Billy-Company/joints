# Result 3 — the admission-report family

Measured 2026-08-05 against `PREDICTION-3-instruments.md`. Five predictions,
four held, **one failed, and the one that failed is about the instrument I
built to run this audit.**

## The shape of the family

An LR state row has two halves. **Shifts**, where the state consumes the token,
and **reduce-lookaheads**, where the terminal only triggers a fold. `drive.offer`
admits both, because that is tree-sitter's `valid_symbols` and `valid_symbols` is
the only thing a scanner reads. So every count taken over "what this state
admits" is one of two facts unless it says which — and the failure is always in
the same direction, because the narrow read is the shift read, the shift read
prints zeros, and zeros read as a clearance.

`lalr.Half` is now the one definition of the split. It was a private enum in
`state.zig`; it is in `lalr.zig` beside `Action`, so a census of a mechanism and
the mechanism cannot drift the way `lex`'s blind count did.

## P10 — held. `inquest` was a member

`awaited` builds its four-tier ranking out of shifts and folds, computes which
half admitted the stand-in, and then threw the answer away. `write` printed a
terminal name with no way to tell whether the state was *waiting for* that token
or merely tolerating it as a fold lookahead — and `inquest` is what `parse`'s
owner line prints, so the conflation reached every reader of a wall and every row
of the board's damage table.

It now carries `admitted: ?lalr.Half` on the finding and prints
`[no stand-in for X, admitted by shift]`.

## P11 — held. `joints.legal` was a member

It printed `it accepts:` over one flat list of every terminal with a non-error
action, truncated at twelve by symbol number. In a state with three shifts and
two hundred lookaheads that is a mixed dozen under a header naming neither half,
and a reader counting them reads a state that consumes three tokens as one that
consumes twelve. Its own doc comment already said the distinction mattered — "a
missing action is nearly always a missing *fold*" — and then printed one list.

It now prints `it reads:` and `it folds on:` as two independently counted and
independently truncated lists, both through `lalr.Half.of`.

## P12 — held, and it is not a report

`Expected.wanted` is filled by two offers with two different meanings.
`drive.offer` admits every terminal with any non-error action; `Gather.offer`
admits `shiftable(top, sym)` — the folds actually run over the standing stack, so
a shift is on the other side. Both are deliberate and `Gather`'s doc says why at
length. What was missing is that the *field* said neither. One field, two halves,
one doc comment, and a hand written against either reading is written against the
other in the other driver. The doc now names both fillers and says which half
each supplies.

This is the member that matters most for item 1: the abut hand reads `wanted`,
and `_immediate_paren` is a shift in 20 states and a lookahead in 239.

## P13 — held. `lex`'s blind count is repaired, and structurally

`blind` is now derived in the same loop that seats: a terminal is blind exactly
when its pattern is `.external` and no cast claimed its name and no provision
resolved it. There is no second derivation to disagree with the first, which was
the whole defect — the count read `claimed` and `claimed` had not heard about the
new role. `declined` is a separate field for a separate population, which is what
stopped php's 99 engine refusals being reported as 99 externals.

## P14 — held. Item 2 moves zero board cells

Two pins, one with item 1 only and one with item 1 and item 2, run through
`tool/standing.py`. Every numeric column is identical: 30 rows, `363,987 built +
56,343 orphan + 24,167 rubble + 82,301 spoil = 526,798`, `describes` 97,595, bare
leaves unchanged, all thirty trees identical.

The **only** differences in the whole board are eight diagnostic sentences
growing `, admitted by shift`, plus the stamp and cache lines that record which
binary ran. That is the result.

## P15 — FAILED, and it is the finding I would least like to report

The prediction was that writing the gate as a floor rather than a list would
catch at least one site I had not found by reading, on the argument that I am the
instrument here and the instrument built to audit is the one most likely to
flatter me.

It caught none. Sweeping every action-cell read in `src/` and every printed
sentence containing admit / accept / expect / permit across `src/` and `tool/`
returns exactly the four sites already listed and no fifth. So the sweep
confirmed my reading instead of testing it, which is the failure mode the
prediction was written to catch, arriving in the prediction itself.

What is left standing is not the sweep but three gates that can fail:

- `lalr.zig` — `Half.of` is total and disjoint over the verb enum, written as an
  exhaustive `inline for` so a fifth verb reddens rather than vanishing from a
  list; **and** a pressed grammar must contain a state where both halves are
  occupied and unequal, so "say which half" is a distinction with something
  behind it.
- `inquest.zig` — findings must set `admitted` whenever they set `unlexable`,
  **and** both `.shift` and `.fold` must occur, so the assertion cannot pass by
  examining only shift-admitted findings.
- `outside.zig` — the ledger refuses the two-cycle, **and** the longest
  legitimate run fits under the ceiling while an unconditional hand is stopped by
  it, so a ledger that admits nothing cannot pass.

## The eight-shift observation, which the corpus cannot resolve

Every one of the eight inquest findings on the board prints `admitted by shift`.
Not one prints `fold`. That is not a bug — `awaited` ranks shifts above folds, so
the fold pass only speaks when there is no blind shift in the row — but it means
**the fold branch of the newly honest report is unexercised by the entire
corpus**, and the only thing that exercises it is the unit test that builds a
fold-only row by hand. A reader who trusted the board would conclude the fold
half never happens, which is the same error one shape smaller.

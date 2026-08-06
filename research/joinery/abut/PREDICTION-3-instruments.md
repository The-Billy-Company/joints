# Prediction 3 — the admission-report family, before the sweep

Written before any instrument is read closely enough to fix. An LR state row has
two halves: **shifts**, where the state consumes the token, and
**reduce-lookaheads**, where the terminal only triggers a fold. `drive.offer`
admits both, so the permission set a hand reads is the union, and every count
taken over "what this state admits" is one of the two facts unless it says
which.

The failure is directional and that is why it is worth a lane: the narrow read
prints **zeros**, zeros read as a clearance, and a clearance licenses unsound
work. `state --census` printed `shift 0` across all 28 content pairs of a cohort
that sits together ten times in the column a hand reads.

## Members I expect to find

**P10.** `inquest` is a member. `awaited` already computes the half — its
four-tier ranking is built out of `shifts` — and then throws it away, so
`write` prints a stand-in name with no way to tell whether the state was
*waiting for* that token or merely *tolerating* it as a fold lookahead. Since
`inquest` is what `parse`'s `owner` line prints, that conflation reaches every
reader of a wall.

Falsified by: `inquest.write` already distinguishing the two.

**P11.** `joints.legal` is a member. It prints "it accepts:" over one flat list
of every terminal with a non-error action, truncated at twelve — a mixed dozen
under a header that names neither half. This is the exact shape `state --census`
was fixed away from, one file over, and its own doc comment already says the
distinction matters ("a missing action is nearly always a missing *fold*").

Falsified by: it already splitting, or the list being shift-only by
construction.

**P12.** There is a member in the *mechanism* rather than in a report:
`Expected.wanted` is filled by two different offers with two different meanings.
`drive.offer` admits every terminal with any non-error action, and
`Gather.offer` admits `shiftable(top, sym)` — the folds actually run over the
standing stack, so a shift is on the other side. One field, two halves, one doc
comment. A hand written against either reading is written against the other in
the other driver.

Falsified by: the two offers admitting the same set.

**P13.** `lex`'s blind count — the family's second known member, which called
swift blind to a terminal the parser was emitting — is already repaired, by
splitting `declined` out of `blind` and by not counting a terminal a hand
answers. It stays in the sweep as a control that a fix here holds.

Falsified by: finding it still conflating.

## What the sweep may not do

**P14.** Every item-2 change is a diagnostic string or a doc comment. The board
does not move: `built + orphan + rubble + spoil = 526,798` with the same four
addends, `describes` unchanged, bare leaves unchanged, all thirty grammars
tree-identical.

Falsified by: any board cell moving.

## The gate, and its anti-vacuity

A gate that checks "every admission report names its half" passes trivially if
it examines no reports. So the gate is two assertions:

1. every report site the gate knows about names a half;
2. the set of report sites the gate knows about is **non-empty and at least as
   large as a floor**, so deleting a site cannot turn the gate green.

**P15.** Writing the gate this way will catch at least one site I did not find
by reading. That is the point of a floor: I am the instrument here, and the
brief says the instrument I build to audit is the one most likely to flatter me.

Falsified by: the gate finding exactly the sites I already listed.

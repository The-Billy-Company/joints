# PREDICTION-5 — the fork is opened and then thrown away

`HANDOVER-wrong-limb.md` says gather takes the declaration limb at state 1762 on
`=`. It does, and the reason is not a choice: **that cell is `residual`, so it
is not in `Forks` and gather is never offered the other limb.** Admitting
residual cells to `Forks` was measured on 2026-08-06 (arm A of
`PREDICTION-4-limb.md`) and regressed two witnesses; that arm is abandoned and
the file is back to the shape its author wrote.

What the same state row *does* offer is `<=`:

```
<=   fold clockvar -> _identifier [prec 0 left]
     [declared reduce_reduce, over fold variable_lvalue -> _identifier [prec 0 left]]
```

**Declared.** So gather forks. And with `JOINTS_TRACE=quire` on
`always @* begin x <= 0; end`, the whole defect is two lines:

```
split: state 1762 on <= at 42 rank 0 - keeps fold clockvar #3382, casts fold variable_lvalue #4185
merged: rank 0 and rank 1 stand on the same states; rank 0 keeps the nodes
```

The fork opens. The two readings fold back onto the same state chain. `collapse`
merges them and keeps the lower rank — which is the limb the *press* chose at a
cell the press had no authority over — and `x <= 0;` ships as a
`clocking_drive`. **On this construct the declared conflict does no work at
all**: the fork is opened, costs a strand, and is discarded by the same coin
toss that would have decided it with no fork at all.

That is the claim under test. `collapse`'s tie-break is `@min(rank)`, justified
in its docstring as "the tie-break `first` already applied at the end of the
parse — so the collapse only decides it sooner". Those are two different
questions. `first` compares readings that are still distinguishable **by what
they will do next**; `collapse` compares readings distinguishable only **by what
they have already built**, because `twinned` has just established their futures
are identical. Rank measures departures from the table, and at a `declared` cell
the table's answer is the one the author said not to trust.

## The arm

**Arm C — at a twinned merge, keep the higher rank.** One line in
`collapse`: `if (v.rank > k.rank) k.* = v;`. Equal-rank twins (the verilog
port-list case the docstring describes, eight spellings of one derivation) are
untouched, because nothing there differs. Only twins whose ranks differ move,
and those are exactly the merges where a declared fork is being resolved.

This is not offered as obviously correct. It is a coin toss in the other
direction, and its value is that it *measures whether the press's cell choice is
systematically the wrong one*. If the board improves, the finding belongs to the
press: its reduce/reduce tie-break disagrees with upstream's. If it regresses,
`@min(rank)` is right on average and the verilog cell needs the authored rank,
which no policy in gather can reconstruct.

## Predictions

Measured with pinned binaries either side, each arm its own `JOINTS_WORK`,
folio shas checked to differ — Arm C is a quire change and mints no new folio,
so the shas should be **identical**, and a differing sha is a bug in the harness
rather than a finding.

- **P1** — `x <= 0;` seats as `nonblocking_assignment` under Arm C. This is the
  arm's whole purpose; if it does not fire, the merge is not where the reading
  dies and the trace is lying.
  *Falsifier: it stays `clocking_drive`.*

- **P2** — `x = 0;` stays `block_item_declaration`. The `=` cell is residual and
  Arm C cannot reach it. **Four of the seven wrong rows in the limb table are
  `=` rows and none of them move.**
  *Falsifier: any `=` row changes shape.*

- **P3** — `c[i] <= 0;` still walls. Its wall is `merge damaged this terminal's
  cell elsewhere`, a lex-side report about the `[`-row, and the `<=` fork is
  downstream of a reading that never got that far.
  *Falsifier: it parses.*

- **P4** — verilog's damage moves **less than 500 bytes**. `x <= 0;` and
  `c[i] <= 0;` between them are a handful of picorv32 statements, and the four
  `=` rows — the bulk of the 63,937 — are untouched by construction.
  *Falsifier: |Δ| ≥ 500.*

- **P5** — **at least one grammar other than verilog moves.** `merges` is
  non-zero on more than verilog, and a global flip of the merge tie-break cannot
  be verilog-local. This is the prediction I most expect to make the arm
  unshippable.
  *Falsifier: 29 of 30 byte-identical and only verilog moves.*

- **P6** — corpus `describes` **rises**. A higher-rank reading reached its state
  by taking more folds, so preferring it should keep more nodes, not fewer.
  *Falsifier: `describes` falls.*

- **P7** — `rack run`'s `square` column **falls** on at least one grammar. This
  is the prediction that decides shippability, because `square` is the only
  column measured against upstream's own derivation, and a merge policy that
  buys verilog by paying a grammar that already agrees with tree-sitter is not a
  trade worth making.
  *Falsifier: no grammar's `square` falls.*

- **P8** — the arm does **not** need `first` changed to match. If `collapse`
  keeps the higher rank and `first` still prefers the lowest, the two disagree
  only for readings that never merged — a real inconsistency, and the reason
  this arm would need a second half before it could ship even if the board liked
  it. I predict the inconsistency is **invisible on the corpus** because a
  parse ending with two unmerged readings of different rank is rare.
  *Falsifier: changing only `collapse` moves a grammar that changing both does
  not, or vice versa.*

## What this arm cannot do

Both defects at state 1762 have one root cause and it is not in my files.
`variable_lvalue` is authored `prec.left(37)` in `verilog.json` and polls at 0,
because `fold.zig::expand` splices `_hierarchical_variable_identifier` away and
the boundary step keeps the victim's authored 0 over the host's authored 37
(`RESULT-2-splice.md` derives this; its repair A restores the 37 and costs
3,412 bytes by deleting 8,817 forks). With 37 present, `<=` folds
`variable_lvalue` because 37 > 0 and `=` folds it for the same reason — **one
number fixes both rows, and it is a number gather cannot see**, since the splice
drops it before the step is written.

So the honest ceiling on this arm is the `<=` row and whatever else in the
corpus merges across ranks. The `=` row needs the press, and the press's own
dossier says the cheapest repair that reaches it is A+B composed — A so the cell
answers `fold`, B so the 8,817 forks A deletes come back as forks rather than
vanishing. Nobody has measured that composition. It is not mine to measure.

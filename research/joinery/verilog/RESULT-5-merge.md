# RESULT-5 — the fork is opened and then thrown away

Against `PREDICTION-5-merge.md`. Eight predictions, **two failed**, and the most
useful thing in this file is a mistake I made and caught: for about twenty
minutes I believed this lane had turned latex perfect, and it had not. Nothing
ships but an instrument, a corrected docstring, and two boards that close two
directions off.

| | prediction | outcome |
|---|---|---|
| P1 | `x <= 0;` seats as `nonblocking_assignment` under C | **held** |
| P2 | no `=` row moves | **FAILED** — `c[3] = 0;` seats correctly |
| P3 | `c[i] <= 0;` still walls | held |
| P4 | verilog damage moves < 500 bytes | held, +94 |
| P5 | a grammar other than verilog moves | held — five do |
| P6 | corpus `describes` rises | held, +816 nodes |
| P7 | some grammar's `square` falls | **held, ruinously** — elixir 23,879 → 1 |
| P8 | `first` needs no matching change | held, and it is the finding |

## The handover's premise is not gather's to answer

`HANDOVER-wrong-limb.md` says gather takes the declaration limb at state 1762
on `=`. **It does not choose it.** The row says why:

```
=    read on   [residual shift_reduce, over fold variable_lvalue -> _identifier [prec 0 left]]
<=   fold clockvar -> _identifier [prec 0 left]
              [declared reduce_reduce, over fold variable_lvalue -> _identifier [prec 0 left]]
```

`Forks.of` admits `declared` and `unwritten` cells and skips `residual` ones, so
the `=` limb is **never offered to gather at all**. Four of the seven wrong rows
below are `=` rows and no policy in quire can reach them. Admitting residual
cells to `Forks` was arm A of `PREDICTION-4-limb.md`, measured 2026-08-06, and
it regressed `c[3] <= 0;` and `a[3:0] <= 0;` from `nonblocking_assignment` to
`clocking_drive`; `forks.zig` is back to the shape its author wrote.

`<=` is a different matter. It is **declared**, gather does fork, and with
`OUTLINER_TRACE=quire` the whole defect is two lines:

```
split: state 1762 on <= at 42 rank 0 - keeps fold clockvar #3382, casts fold variable_lvalue #4185
merged: rank 0 and rank 1 stand on the same states; rank 0 keeps the nodes
```

The fork opens, the readings fold back onto one state chain, `collapse` merges
them and keeps the lower rank — the limb the press picked at a cell the author
declared arbitrary — and `x <= 0;` ships as a `clocking_drive`. **On this
construct the declared conflict does no work at all.**

## The instrument, because "it parses" was the failure mode

`.local/limb/limb.py` seats one statement in `witness.py`'s frame and reports
**what node the `seq_block` holds**, not whether the module stood. The extractor
had to be written twice: looking for the node under the innermost
`statement_item` reports the *frame*, because the defect's signature is that the
statement is not a statement at all.

| statement | want | got | |
|---|---|---|---|
| `x = 0;` | `blocking_assignment` | `block_item_declaration` | whole, wrong |
| `c[i] = 0;` | `blocking_assignment` | `block_item_declaration` | whole, wrong |
| `c[3] = 0;` | `blocking_assignment` | `block_item_declaration` | whole, wrong |
| `x <= 0;` | `nonblocking_assignment` | `clocking_drive` | whole, wrong |
| `c[i] <= 0;` | `nonblocking_assignment` | — | walls |
| `c[3] <= 0;` | `nonblocking_assignment` | `nonblocking_assignment` | ✓ |
| `mem[i] <= 0;` | `nonblocking_assignment` | — | walls |
| `{x, y} = 0;` | `blocking_assignment` | `blocking_assignment` | ✓ |
| `{x[3], y} = 0;` | `blocking_assignment` | `blocking_assignment` | ✓ |
| `x = $signed(y);` | `blocking_assignment` | `block_item_declaration` | whole, wrong |

**Seven of ten wrong, five of them standing whole**, so every one of those five
contributes its bytes to verilog's `built`. That is `RESULT-2`'s 9.24% floor
with ten rows instead of one.

## The mistake, first, because every number below depends on it

`limb-base` was pinned at 02:38 and `merge-C` at 02:46. In those eight minutes
the **lex lane landed a fix that takes latex from 72 roots to `accepted, 1
root`**. Every arm I built after 02:38 carries it, so every arm read
`latex −1,185 damage` against `limb-base` and I attributed it to the arm.

What caught it was pinning the *reverted* tree (`limb-final`) and diffing it
against `limb-base` as a control. It should have been byte-identical. It showed
latex −1,185 and elixir −583 with `collapse` textually identical either side —
a behaviour change with no code change, which is only ever a stale baseline.

The brief warned about two binaries sharing an `OUTLINER_WORK`; each arm here
had its own, and the folio shas were checked identical, which is the right check
for a quire change. **It does not cover a shared tree moving underneath the
pins.** On a tree ten lanes write to, the control has to be pinned *after* the
arm, not before, or the window belongs to whoever else landed in it.

Everything below is against `limb-final` — the reverted tree, pinned last.

## Arm C — keep the higher rank at a merge

One line: `if (v.rank > k.rank) k.* = v;`. Equal-rank twins untouched, so the
verilog port-list case the docstring describes does not move. Folio shas
identical either side.

The verilog limb table goes **7 wrong → 5**: `x <= 0;` seats as
`nonblocking_assignment` (P1) and `c[3] = 0;` seats as `blocking_assignment`
(P2 failed — after `select1` the parse reaches a state where the `=` cell *is* a
declared fork, so the merge policy gets there after all). No row regresses, and
reverting the line returns the table to 7, which is what attributes the change.

`standing.py`, corpus damage **+677**:

| grammar | built | damage | nodes |
|---|---|---|---|
| elixir | −583 | **+583** | −15 |
| verilog | −94 | **+94** | **+846** |
| cpp · kotlin · php · swift | . | . | +1 · +1 · +26 · −43 |
| **total** | **−677** | **+677** | +816 |

`rack run`, which compares the whole spine per byte against tree-sitter's own
derivation and is the only column that can arbitrate a limb:

| grammar | square | askew | racked | unframed | bracket recall |
|---|---|---|---|---|---|
| **elixir** | **23,879 → 1** | 121 → 124 | 22,089 → 21,976 | **0 → 23,386** | 97.7% → 97.5% |
| **php** | **67,845 → 67,685** | 0 | **0 → 160** | 0 | 100.0% |
| swift | 10,413 → 10,413 | 1,970 → **1,003** | 6,837 → 7,425 | 3,876 → 4,255 | 91.0% → **96.7%** |
| kotlin | 34,589 → **34,642** | 99 → 90 | 880 → **836** | 0 | 99.9% |
| cpp | 185 → 185 | 596 → 589 | 7 → **2** | 167 → 179 | 28.9% → **29.4%** |
| verilog | unjudgeable — tree-sitter's own CST and XML disagree | | | | |

Corpus `square` **142,157 → 118,172: Arm C destroys 23,985 bytes of agreement
with tree-sitter**, almost all elixir's, which goes from 23,879 square bytes to
one and moves 23,386 of them under a frame we no longer build. php stops tying
tree-sitter and loses to it by 160 bytes.

So Arm C buys two verilog witness rows and 846 verilog nodes for 677 bytes of
damage and 23,985 bytes of upstream agreement. **It is a coin toss that lands
worse**, and `@min(rank)` is right on average — which is the answer to the
question the arm was built to ask.

Verilog's `+94` is not the reason it fails. Verilog cannot be adjudicated
against upstream at all: tree-sitter's own tree of `picorv32.v` has errors in
it, so `rack` has no verdict on any of its 30,720 built bytes. What can be said
is that two of ten hand-derived rows go from wrong to right while `built` falls
94 bytes — `built` counting wrong structure, in person, for the second time in
this dossier.

## Arm D — decline the merge, and the reason `collapse` exists

If the twins really have identical futures, keeping both is free. So:
`if (v.rank != k.rank or !twinned(…)) continue;`.

**Corpus damage +57,627 over five grammars:** kotlin +24,393, julia +17,820,
elixir +7,737, swift +5,102, verilog +2,550. The extra readings fill `crowd` and
the later forks that mattered are denied — the failure mode `collapse`'s
docstring predicts, at four times the size anyone would guess. **This merge is
load-bearing, not an optimisation.**

And the verilog limb table under D is **byte-identical to the control, 7 of 10
wrong**. That is P8 in its strongest form and the finding of the lane:
`collapse` really is only deciding sooner what `first` decides at the last byte,
so `twinned`'s soundness argument stands, and **it is the tie-break and not the
merge that picks a limb.** Applying the same flip in `first` would measure the
same. There is no cheap repair hiding in `collapse`.

## What no policy in quire can do

Both defects at state 1762 have one root cause and it is not in these files.
`variable_lvalue` is authored `prec.left(37)` in `verilog.json` and polls at 0,
because `fold.zig::expand` splices `_hierarchical_variable_identifier` away and
the boundary step keeps the victim's authored 0 over the host's authored 37
(`RESULT-2-splice.md` derives it). With 37 present, `<=` folds `variable_lvalue`
because 37 > 0 and `=` folds it for the same reason: **one number seats both
rows, and the splice drops it before the step is written, so gather cannot see
it.**

`RESULT-2` measured restoring it (repair A: verilog +3,412, because 8,817
declared forks stop being contested) and measured recording the deleted reading
(repair B: verilog −1,292, all four witnesses, 17 of 17 controls, and scala
+12,733 / elixir +7,358 because gather takes the wrong limb on the new forks).
**A and B composed has never been measured** — A so the cell answers `fold`, B
so the forks A deletes come back as forks rather than vanishing. That is the
cheapest repair that reaches the four `=` rows, and it is the press's.

The half of B that is mine is real and unaddressed: B's scala regression is
`@SerialVersionUID(0) class Some[+A] …` shredding, a wrong limb on a newly
offered fork, and it is legible in the tree. Reproducing it needs B applied,
which is a table change; it is the next thing I would take, and it is not
reachable from `collapse` given what D measured.

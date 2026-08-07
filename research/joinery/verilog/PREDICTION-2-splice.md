# PREDICTION-2 — the splice, not the ladder

Written before any measurement of the change. Three verilog conflicts were
handed to this lane with authored witnesses and standing controls:

| witness (fails) | control (stands) | named wall |
|---|---|---|
| `x = {a[3], b};` | `{a, b}` and `a[3]` separately | `;` in state 701 |
| `$signed(a) < $signed(b)` | `$signed(a) < b` | `(` in state 3772 |
| `c[i] = 0;` | `c[i] <= 0;` | `=` in state 2394 |

## What I found before predicting

None of the three named states is contested. `joints state 701` holds one
item, `casting_type -> constant_primary .`, and admits exactly one terminal,
`'`. The same probe over 3772 and 2394 finds no cell the settle bench ever
had to decide. The failure states are locations three constructs downstream,
as the brief warned.

The contested cell is state **1184**, the state after an identifier in
statement position. Probing `Bench.decide` there:

```
PROBE state 1184 t=118 [ reading=true above=false below=false level=true
  continues=false grounded=false unwritten=false
  fold=clockvar prec=.{ .level = 0 } left=true right=false -> ladder=fold
   poll t=[ read variable_lvalue           dot=1 rank=.{.level=0} vs fold .{.level=0} -> eq
   poll t=[ read nonrange_variable_lvalue  dot=1 rank=.{.level=0} vs fold .{.level=0} -> eq
   poll t=[ read hierarchical_identifier_repeat154 dot=1 rank=.{.level=0} -> eq
```

`variable_lvalue` is authored `prec.left(37)` in `verilog.json`. It polls at
**0**. That is the whole defect: with the rank at 37 the survey is
`above && !below` and rung 2 returns `.read` before associativity is ever
consulted. At 0 the survey is a tie, rung 3 sees `purely(f, .left)` — because
`clockvar`'s body `hierarchical_identifier` is `prec.left(0)` — and folds.
`keep_read` goes false, `f.tied()` is false, `standing` comes to 1, and
`decide` returns at `if (standing <= 1)` without recording. No conflict, no
fork, and the `[` shift is gone from the table.

Where the 37 goes: `fold.zig::expand` splices a substituted body into its
host and gives the last inserted step the host's rank *only where it has none
of its own* (`if (last.prec == .none) last.prec = host.prec`).
`_hierarchical_variable_identifier` reaches `_identifier` through
`hierarchical_identifier`, which is `prec.left(0)`. So the last step arrives
carrying an authored `0` and the host's authored `37` is dropped on the floor.
Upstream never inlines a hidden rule, so upstream never has to choose.

## The change

In `expand`, at the boundary step only, the **host** wins where the host wrote
something; the victim keeps the interior. Silence on the host still defers to
the victim, which is the arm the Rust `_non_special_token` note is about.

## Predictions

**P1 — `c[i] = 0;` parses, and `c[i] <= 0;` still does.** Falsified by
`research/joinery/verilog/smallest.py` reporting either row red.

**P2 — `c[i] <= 0;` changes tree shape.** It currently builds
`clocking_drive (clockvar_expression …)`; with the read restored it should
build `nonblocking_assignment (variable_lvalue …)`. Falsified by the tree
printing `clocking_drive` after the change. This one matters more than P1:
the control was *standing while wrong*, which is the 9.24% floor in person.

**P3 — state 701 goes away as a wall for `x = {a[3], b};`.** The composition
failure is the same deleted read: with `a` folded to `clockvar`/`casting_type`
and no reading left to take `[`, the concat element commits to the cast
reading and dies at `'`. Falsified by the witness still failing, or by failing
at a different state for a reason that is not this one.

**P4 — `$signed(a) < $signed(b)` is NOT fixed by this.** `$signed` is not an
identifier and does not pass through state 1184; I have no evidence it shares
the splice. Falsified by it going green anyway, which would be a finding.

**P5 — the corpus board moves up, and at least one grammar pays.** A rank
that has been silently zero everywhere it was inlined is load-bearing in more
places than verilog. Falsified by `tool/standing.py` reporting `built`
unchanged (which would mean the splice is dead code) or by all 30 grammars
staying byte-identical.

**P6 — tree-identity holds at 29 or 30 of 30.** Falsified by fewer.

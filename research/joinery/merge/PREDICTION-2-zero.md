# Prediction 2 — a declared zero is still a zero, in a column the merge invented

Written before the change is made. Each claim carries the measurement that kills
it.

Predicted against the control arm outliner `beb695b5d` · tree `e973ce73c` (pin)
· oracle `d85e736fa` (30 of 30 live, 30 attributed), which is where zig's 1,375
bytes of damage and its wall at byte 4101 were read.

## The cell

Zig state 208 holds two items and refuses `[_]u8{ … }`:

```
type_expression -> primary_type_expression .          prec.right(0)
struct_initializer -> primary_type_expression . initializer_list   prec(-1)
```

`compare` reads `level(-1)` against `level(0)` numerically, returns `.lt`, the
survey sets `below`, and `Ladder.step` folds. The shift row comes out empty and
the `{` has nowhere to go.

`bench.zig:435` already declines exactly this comparison in a frayed cell - a
column the lookahead union invented - but only when the fold is **unranked**:

```zig
.lt => if (!frayed or f.prec != .none or rank != .level) {
```

Zig's fold is not unranked. It carries `prec.right(0)`, which is how a
tree-sitter grammar spells right-associativity, and the level it carries is
zero.

## The claim

In a frayed cell, a fold ranked at a **declared zero** should decline the same
way a fold at an **implied zero** already does. `Prec`'s own docstring says a
declared zero "outranks nothing but still *ties* deliberately, and the
difference decides whether associativity gets consulted at all" - a statement
about associativity, not magnitude. Zero is zero either way, and neither should
delete an authored negative in a column no real arrival puts them both in.

The change is the condition and nothing else: `.none` becomes "`.none` or
`.level` equal to zero". Positive folds keep their authority everywhere.

## What kills it

1. **Zig does not reach whole.** If `[_]u8{` still refuses, the ladder was not
   what was holding it and this whole page is wrong. Measure: `outliner parse
   upstream/grammars/zig.json upstream/sources/ascii.zig`.

2. **Any grammar loses built bytes.** The narrowing is supposed to be
   one-directional - it only ever declines to delete a read. A row whose `built`
   falls is a refutation, not a trade. Measure: the board, every row against the
   control arm.

3. **Crooked rises anywhere.** Forking a cell that used to fold means a reading
   the oracle may judge wrong. Confidently wrong costs more than visibly
   failing, so a row that converts damage into crooked has not paid. Measure:
   `audit.json`, every row.

4. **`residual` or `contested` rises.** `Defects.betterThan` ranks residual
   first for a reason; a cell that becomes residual is one `forks` refuses to
   offer, which is worse than the fold it replaced. Measure:
   `OUTLINER_TRACE=press` round lines, before and after.

5. **The press gets materially bigger.** Declining a comparison leaves both
   actions standing, which the unfolder may then try to separate. The earlier
   attempt at backward separation took bash from 7,753 states to 24,572.
   Anything of that order is a refutation. Measure: state counts, all thirty.

## What I expect

Zig reaches whole and 1,375 bytes of damage go. I do not expect the other four
rows of the merge class to move: julia, sql and swift each name a different
terminal, and verilog's is a backtick in a different shape. If any of them moves
it is a bonus this page did not predict, and it will be reported as unpredicted.

I expect a small number of grammars to change automaton size, because the same
condition governs cells in every grammar that ranks a rule negative under a
`prec.right(0)` parent. Swift's residual census is named in `bench.zig` as one
such cell - `call_expression` at `prec(-2)` against an unranked
`_if_let_binding` - but that one is already `.none` on the fold side and so is
already declining. It should not move.

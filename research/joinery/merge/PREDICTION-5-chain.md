# Prediction 5 — the verdict is unprovable because one list is not kept

Written before the change. Each claim carries the measurement that kills it.

Control arm: outliner `beb695b5d` · tree `e973ce73c` (pin) · oracle `d85e736fa`
(30 of 30 live, 30 attributed).

## The cell

`inquest.refused` can already prove a wall's attribution and name its
`lalr.Floor` bucket. It needs one input:

```zig
refused: struct { terminal: u32, state: u32, folded: ?[]const Fold = null },
```

`folded` is never anything but the default. `kernel/walk/drive.zig` - the
single-stack differential loop, test-only - keeps exactly this list: cleared per
token, appended on every reduce, handed out on `.unexpected` as
`{ tok, state, folded }`. `kernel/quire/gather.zig`, the GLR loop the CLI runs,
walks the same states and keeps only the endpoints:

```zig
.unexpected = .{ .symbol = tok.symbol, .at = tok.start, .state = x.refused },
```

and `surface/face/outliner/parse.zig:496` faithfully carries that shortfall into
the verdict:

```zig
.unexpected => |u| .{ .refused = .{ .terminal = u.symbol, .state = u.state } },
```

So `inquest.zig:610` fires - `folded == null` and the table has damage on this
terminal somewhere - and the verdict prints `press?` with *"no fold chain was
supplied to say whether this wall is downstream of it"*. Four of the five walls
in `RESULT-4-walls.md` are that sentence, and I read them as an indictment.

## The claim

Recording the chain turns those verdicts from *cannot rule the press out* into
either a proof (`press`, with the cell and its bucket) or a different owner. It
is a **diagnostics-only** change: nothing the parse decides may move.

Both absorb loops need it - the forking worklist and the `alone` fast path - and
only for `rank == 0`, which is already the condition under which `x.refused` is
recorded, because the table's own reading is the only one worth reporting from.

Ownership is the trap. `finish` stores the `Stop` in the returned `Quire`, which
outlives the `Gather`, so the chain has to be duped into the quire's allocator
and freed in its `deinit` rather than borrowed from a list the gather owns.

## What kills it

1. **Any row's `built`, `damage`, `square` or `crooked` moves.** This records
   what the loop already walks; it must not change a decision. A single byte
   anywhere is a refutation, not a trade. Measure: the board, all thirty rows
   against the control, plus `still against`.

2. **A verdict gets *worse*.** If a wall that printed `press?` now prints
   `press?` still, the chain is not reaching the verdict. If one flips to a
   proven `press` naming a cell whose bucket is `agreed`, the press was never
   the owner and the old sentence was closer to true than the new one. Measure:
   the five class rows' verdict lines, before and after.

3. **Parse time regresses materially.** One append per reduce in the GLR hot
   loop, on a product whose whole point is beating incumbents. The chain is
   cleared per token so it stays short, and `drive.zig` pays the same cost
   already - but "should be fine" is not a measurement. Measure: parse
   wall-clock on the largest corpus files, before and after. Anything over a
   few percent is a refutation.

4. **A leak or a dangling read.** The chain is duped into the quire and freed in
   `deinit`; getting that wrong is a use-after-free that a passing test suite
   might not catch. Measure: `zig build test` under the testing allocator, which
   fails a leak, plus a test that reads the chain after the gather is gone.

5. **The `amend` path breaks.** `amend.zig` also reads `.unexpected`. A new
   field with no default, or a stop built somewhere I did not look, is a compile
   error at best and a wrong re-parse at worst. Measure: `zig build check`, then
   the amend cases.

## What I expect

zig's wall becomes a proven `press` naming a frayed `open` cell - it is the one
row already traced to a cell by hand, so it is the calibration. julia and swift
each become *something*, and I am deliberately not predicting which; the point
of the change is that I stop having to guess. verilog should stop saying `press?`
at all, because there is no press defect on its path - `RESULT-4` showed state
3438 has an empty lookahead row and tree-sitter puts an `ERROR` on the same byte.
If verilog still reads as the press's fault with a chain in hand, my reading of
that wall was wrong and `RESULT-4` needs revisiting.

I expect no row on the board to move by a byte. If one does, I have not written
a diagnostic.

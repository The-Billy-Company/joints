# Prediction 2 — the forest gate

Written after the diagnosis in `RESULT-1` and **before** the change compiles.
Every row names the measurement that falsifies it. Baseline pin `stoop-before`
(tree `d00259bdd266`), folio set `1b1a9a5d`, probe `research/keystroke/probe.py`.

## What I am changing

One function. `graft.stoop` opens with

```zig
if (q.roots.len != 1) return gr.chain.items;
var ref = q.roots[0];
```

and a mended parse leaves a forest, so on 17 of 29 grammars that line returns an
empty candidate chain at every probe - 11,606 of them across seven grammars on
one keystroke each. The gate is not even load-bearing as written: with it removed
and `roots[0]` kept, the descent's own `old < n.start` break refuses everything
past the first root anyway. So the change is to **pick the root that holds the
offset** rather than assume there is one. Roots are in source order and do not
overlap - `Quire.survey` holds them to it on every parse, which is what makes the
pick a binary search instead of a scan.

## Predictions

| # | Prediction | Falsified by |
|---|---|---|
| P1 | The 12 clean grammars do not move **at all**: identical `offered`, `lifts`, `read`, and identical trees. `roots.len == 1` makes `holder()` return `roots[0]` exactly when the old loop's first `break` would not have fired. | any diff in `offered`/`lifts`/`read`/tree on c\*, cpp is mended - the clean 12 are go, java, javascript, typescript, python, rust, json, css, embedded-template, html, lua, toml |
| P2 | All 17 mended grammars go `offered = 0` → `offered > 0` at the midpoint edit. | any forest still at `offered = 0` |
| P3 | `lifts > 0` at the midpoint edit for **latex, zig, kotlin, julia** - the four forests where the prefix resume already succeeds (`stood > 0`) and almost every ask already reaches `stoop` (latex 517/527, zig 1768/1786, kotlin 2237/3188). | `lifts = 0` on any of those four |
| P4 | Per-key time drops **≥ 40%** on latex, zig, kotlin, julia. | < 40% on any of them |
| P5 | **Swift drops by less than 30% and stays the worst row on the board.** Two ceilings this change does not touch: `alight` declines every ring (`unheld=4`), so the parse still starts on the ground, and 4,283 of 6,622 asks (65%) are turned away by `turned_fork` before `stoop` is ever called. | swift dropping ≥ 30%, or any row ending worse than swift |
| P6 | Median gain over the 17 mended goes 1x → **≥ 2x**, and **at least 6 of the 17** leave the `gain < 1.5` bucket. | fewer than 6 leaving |
| P7 | `rack --square` does not move on any grammar. A lift is admitted by `liftable` shape, by `aligned`, and by the goto existing; which root the offset sits under is not part of that argument, so a candidate this change newly nominates is one the same three gates then judge. | any square delta |
| P8 | Trees **do** change on some mended grammars - they now lift where they re-derived - so `built` may move in either direction. If `built` rises while `square` falls, the change is buying wrong structure and I report it as a loss, not a win. | reported as a win with `square` down |

## What I expect to be wrong about

P4 is the weak one. A lift is only cheap if the widest candidate is wide, and
`widest/taken` on the clean grammars says the walk already leaves bytes on the
table (toml takes 1,750 of 3,001 offered). On a forest the roots are small by
construction - verilog has 3,544 of them over 94,657 bytes, 27 bytes each - so
the widest candidate under a root may be a leaf's parent and nothing more.
**Verilog and markdown are where I expect P4's logic to fail**, and I am not
predicting them.

P2 is the one I am most confident in and the least impressed by: it says a gate I
am deleting stops firing.

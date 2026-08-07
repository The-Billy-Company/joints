`Quire.survey` is the only interior check this project can afford to leave on -
ten seconds, no oracle, every grammar that parses - and until this morning its
verdict reached the outside world only as a complaint. `parse.zig` printed
`UNSOUND: N loose, ...` when it disliked the forest and printed nothing at all
when it liked one. So `tool/sound.py`, which is a hard gate, was clearing thirty
rows **on an absence**: if `parse.zig` stopped calling `survey`, or the clause
were reworded out from under `stamp.ask`, every unit test stays green and the
board reads sound.

That is the same defect `collate.py`'s `recall` and `shear.py`'s `cut_rubble`
were repaired for the same day - both reading zero for "none there were" and for
"nobody asked" - and this was the last place it lived.

**The parse now says it looked.** `Quire.Survey` carries `walked` (nodes the
roots reached) and `held` (nodes the arena holds), and `verdict` prints
`surveyed N of M nodes` on **every** parse, before the optional `UNSOUND:`
clause:

```
joints: /t/a.toml: accepted, 1 root, surveyed 731 of 731 nodes
joints: /t/b.zig: stray byte at 41, 4 roots, surveyed 31 of 31 nodes, UNSOUND: 1 loose, 0 disorder, 0 torn
```

`stamp.Outcome` gains `surveyed`/`arena` off it and strips the clause from
`verdict`, so no page's stored sentence moves. A row with no clause is **UNASKED**
and fails, naming the function that owes it.

The falsifier is the one the old evidence structurally could not have. Pointed
at pin `sound` - binary `b9bd1cc19`, built 2026-08-06T00:15Z, the very binary
that produced yesterday's `30 of 30 sound` - `sound.py` now refuses all 29 rows
as UNASKED, and `standing.py`'s three new assertions all redden. Pointed at
`pin-shapelane` (binary `4c262974e`) it reads **29 of 29 asked grammars hand
back a tree, 109,717 nodes walked**.

Two things that number is not, both of which the old one was:

- **yaml is a skip, not a pass.** The binary refuses the file outright, so there
  is no forest to survey. The earlier `30 of 30` counted that refusal as a
  clearance, which is the same bug one level up.
- **`walked` is not `held`.** The arenas hold 145,351 nodes against 109,717
  walked, and twenty rows carry slack (widest verilog, 18,240). That is arena
  the roots abandoned - speculative nodes `Gather.reduce` allocated that no root
  ended up pointing at - not forest that went unchecked. Both numbers print, so
  the claim is auditable rather than asserted.

Tests: `survey_test.zig` keeps its hand-built arenas across all four violation
classes and gains two that show `sound()` alone cannot distinguish a clean walk
from no walk, and that an unreachable node is `held` and not `walked`.
`parse.zig` gains three that assert the sentence itself, including that
`surveyed` precedes `UNSOUND` and that an empty forest still says it looked;
`main.zig` imports `parse.zig` so they are collected. `stamp.py` gains a
`--surveys` gate table whose last row is the one that matters: **no clause at
all must read UNASKED and never sound.**

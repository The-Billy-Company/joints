`built` is the union of the extents of our top-level roots that have children, so
a root reaching over a hole carries the hole with it: the bytes inside it are
counted `built`, are not counted `damage`, and were never built. Verilog's board
damage was being quoted as *bytes verilog never built* by three lanes who
optimised against it before `square` could be read on the row at all, and it is
not that. It is `size - built`, exactly, and there is a second population it
cannot see.

`rack` now counts it. **`stretch`** is built bytes under no leaf of ours,
**`airy`** is how many of those are whitespace between two tokens, **`honest`** is
`damage + stretch`, and **`text`** is `honest - airy`. `rack.py board` prints all
five in a `STRETCH` block sorted by the last, so a row that is mostly blank sorts
below a row that is mostly source.

**And the column dissolves the correction it was written to make.** The
reconciliation this was asked for expected a majority of verilog's stretch to be
source text; **90.8% of it is whitespace**, and corpus-wide it is 96.3%:

| | verilog | corpus |
|---|---|---|
| `damage` = `size - built` | **62,464** | 126,927 |
| `stretch` | 4,594 | 79,628 |
| `airy` | 4,170 | 76,719 |
| `honest` | **67,058** | 206,555 |
| `text` | **62,888** | 129,836 |

So the figure a work order should be given is **62,888** — source text inside
`built` that no token of ours stands on — which is 424 bytes more than the board
prints, not 4,594. The board's damage figure was very nearly right all along.

Verilog is not even the row the column indicts. By raw stretch the widest is
**html at 25,241**; by source-text stretch it is **toml at 1,552 of 1,972** — a
row scoring 100.0% standing with zero damage, carrying 1,552 bytes of source
under no token, which also prints an `UNSOUND` complaint no board reads.

The two figures long quoted as partitioning verilog's damage still do not, and
now by a third fault as well as the two already recorded: 49,446 is a census in
`damage`'s units and 8,175 was a delta in *honest built*'s (the same ablation is
13,385 in `damage`'s); 2,222 of the raw delta lands inside `picorv32` so they
overlap; and the delta is **not arm-invariant** — +8,175 on one arm, +9,422 on
another, +9,576 here, so the residue is 4,863 the record's way and 3,462 on this
arm. `damage`, `honest` and `text` are all functions of `built`, and `built`
moves several times a day on a tree ten lanes write to. **A verilog damage figure
quoted without its arm is not a figure.**

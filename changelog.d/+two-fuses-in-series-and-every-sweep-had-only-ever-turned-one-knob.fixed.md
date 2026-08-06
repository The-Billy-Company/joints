A fork needs a `crowd` slot and a `skeins` strand, and both were set from
sweeps that moved one of them at a time. That cannot work: whichever fuse is
lower is the only one a single-knob sweep can observe, so both read as
saturated and each certified the other's floor.

`gather.zig` recorded the conclusion in the comment on `crowd` - "re-measuring
the whole board at 8, 32 and 256 moves 13 bytes, all of them verilog's, and
saturates below 32 ... 8 stays because the cap is cheap rather than because it
is out of reach." Held one knob at a time it is even true. The four corners:

| `crowd` | `skeins` | elixir | scala | swift |
|---|---|---|---|---|
| 8 | 64 | 1 | 534 | 10,413 |
| 8 | 512 | 1 | 722 | 10,413 |
| 64 | 64 | 1 | 534 | 14,419 |
| 64 | 512 | **23,879** | **6,739** | **14,419** |

Raising either alone moves which fuse blows and nothing else. At 64/512 elixir
comes back whole.

**Swift owes none of this to a press change.** With the tables untouched it
still gains 4,006 square bytes, so the cap was costing that much on the tables
we ship today and the old sweep left it on the floor. What made the rest
visible is that sparing the side-rung cell mints more legitimate forks than
eight slots hold: elixir's `denied` counter goes from 0 to 75 - denying more
forks than it takes - and a fork that never opens cannot be recovered by
anything downstream of it. That is the whole of the "wrong limb" the board had
been pricing at 29,348 bytes: not a merge picking badly, a fork refused.

Cost is nil, which is what a fuse should cost. A slot is allocated when a fork
opens, not reserved, so raising the ceiling is free until a parse reaches for
it - and when it reaches, the alternative was losing the frame. Throughput is
flat on all seven timed grammars and elixir, the only forker on the board big
enough to time honestly, is 1.00x either side.

The instrument that hid this for so long was the sweep's own shape, and it
passed every check it had: it was reproducible, it saturated, and it was
measuring one dimension of a two-dimensional bound.

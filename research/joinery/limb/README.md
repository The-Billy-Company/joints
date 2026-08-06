# limb - what picks the reading when the author said both are fine

The lane the board priced at **29,348 square bytes**, handed over as "`gather`
takes the wrong limb at a merge". It is two findings, and the brief's own
diagnosis is the smaller of them.

| | |
|---|---|
| `PREDICTION-1-heft.md` | written before anything was built or measured |
| `RESULT-1-heft.md` | the board, the four-corner fuse table, the predictions scored |

**The short version.** The tie-break really was reading the wrong number -
`collapse` compared speculation depth, a fact about the parse loop, where the
grammar author had written `prec.dynamic` for exactly this moment and the
runtime carried it through the folio without ever reading it. Fixing that is
right, and it is worth **44 square bytes**.

The other 29,348 was never a tie-break. Sparing an associativity-decided cell
mints more legitimate forks than the runtime had slots to hold, so elixir went
from denying zero forks to denying 75 - more than it took - and a fork that
never opens cannot be recovered by anything downstream. `crowd` and `skeins`
are **in series**, so every previous sweep, which moved one knob at a time,
could only ever see the lower fuse and read it as saturated.

**Together: +6,529 square bytes** (+4,956 with verilog withheld), W5 and W6
seated, 17/17 controls standing, elixir byte-identical to control, nothing lost
anywhere, and throughput flat.

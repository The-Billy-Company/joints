`picorv32.v` was the board's top row by `damage = size - built`: **63,937
bytes** over 94,657, 32.5% standing, 2,109 mends, nobody on it.
`research/joinery/verilog/` attributes them.

**Two constructs pay.** Blanking them length-preserved, with all 3,934 bytes of
comment blanked as the negative control leaving `built` at 30,720 **to the byte**
and `mends` at **2,109**:

- a `` `ifdef `` between two port declarations **inside a module port list** -
  `+9,788` built, `+4,148` describes;
- `$signed(` in the right operand of `*` - `+1,704` built, `+1,054` describes.

Split into its eight `module`/`endmodule` blocks and parsed alone, three modules
already stand whole, and under those two ablations `picorv32_axi` goes
**54.2% -> 100.0%**, `picorv32_wb` **54.3% -> 100.0%** and
`picorv32_pcpi_fast_mul` **73.4% -> 100.0%**. Six of eight whole. Held to the
stricter test - `built` with a token of some depth actually standing on it - the
pair is worth **8,175** honest bytes rather than 11,529; 3,354 of the headline
is stretch, and the number to carry is the smaller one.

**Four more walls are named exactly and worth nothing**, which is the half of
this worth reading. Each reproduces in one line of verilog and none moves the
file:

```verilog
initial begin c[i] = 0; end   press? on = in state 2394   8 sites,  -167 bytes
x = {a[3]};                   press? on ; in state 701  112 sites,    +68 bytes
always @* begin `debug end    press? on ` in state 1108            -2,176 bytes
… && |pcpi_rs2                                                          +0 bytes
```

Their scalar / unbracketed / expression-position counterparts all parse whole,
so these are exact - and they are the `_import_dot` shape: a perfect diagnosis
worth zero. State 2394 is where the **warm** peel spends seven of the nine walls
the cold peel cannot reach, so the state that recurs most is not the state that
costs most.

**The remaining 49,446 bytes are one module and no ablation takes them down.**
`picorv32` is 92.1% procedural damage, 69.9% of it in three `always @(posedge
clk)` blocks; declarations stand at 90.3% and the 28 procedural blocks at 16.2%,
with 1,400 of 1,506 mends inside them. Deleting the module's entire parameter
port list *and* its entire port list - 2,972 bytes - moves `built` by **exactly
0** while a 1,051-byte control cut of declarations costs 1,019, so the header is
innocent; and blanking the line the stop names, 61 rounds running, moves `built`
**down** 1,508 bytes because the stop is resynchronisation and not a wall.

**Re-pointed 2026-08-06, and the pricing is the part that moves.** Every figure
above is `built`, `describes` or `standing` - ours about our own forest. Sighted
against tree-sitter, the 32,193 bytes verilog *does* build carry **2,184
`square`**: of the 27,598 the oracle adjudicates, **7.9%** are derived the way
tree-sitter derives them. So `+9,788 built` and `+8,175 honest` are honest counts
of bytes brought under structure and **not** counts of bytes brought under the
right structure, and "six of eight modules whole" is six of eight at 100%
`standing` with no per-module `square` reading ever taken. On tonight's evidence
converting verilog's damage into `built` converts unbuilt bytes into misderived
ones - which makes the two named constructs a better work order than before, not
a worse one, because now they can be priced on the column that would notice.
verilog was 100% unadjudicable until 2026-08-05, so no sighted reading of this
file existed while it was measured. `research/joinery/consort/RESULT-8-sighted.md`.

Two instruments to distrust, both mine. `modules.py` first printed
`picorv32_regs … 6790.4% standing`, because `built` unions top-level root spans
and a 343-byte module padded to 94,657 hands back one root over the padding -
caught only because one row was absurd, while the walled modules in the same
table scored a plausible 54-73%. And the whole ablation method has a blind spot
this file found: blanking a construct that *partly* parses removes the bytes it
was contributing, so a grammar gap and a productive construct both read as a
negative delta. Every arm of the statement-form sweep is uninterpretable for
that reason. What worked was building the smallest module that fails, from
nothing.

# Result 2 — the width test reads a derived fact as an authored one, and is out

2a held. 2b held on every instrument the corpus has. **2c was falsified**, and
the change is out.

## What the change was

One condition in `fold.expand`, guarding the mark that had been unconditional:

```zig
const scoped = body.steps.len == 1;
…
if (!scoped and (inserted.prec != .none or inserted.assoc != .none)) inserted.spliced = true;
```

## What it bought

Residual conflicts, all thirty grammars, `joints grammar <g>`:

| grammar | before | after |
| --- | --- | --- |
| scala | 192 | **0** |
| rust | 176 | **0** |
| verilog | 136 | **40** |
| haskell | 8 | 8 |
| php | 5 | 5 |
| the other 25 | 0 | 0 |

517 residual to 53. Rust reaches the zero `TESTING.md` claims for it, and so does
scala, which was never in the eleven. 2a holds: the rank was present the whole
time and the mark was the only thing standing between it and the ladder.

Nothing else visible moved. The corpus damage board is **byte-identical** -
411,517 bytes built, 1,979 misread, 78.12% standing, unchanged. 27 of 30 conflict
censuses are byte-identical; the three that differ are the three above.

## What falsified it

The verilog statement the record names, in a file written for it:

```verilog
module m;
  reg [7:0] c [0:3];
  integer i;
  initial begin
    c[i] <= 0;
  end
endmodule
```

Before, the inner statement reads:

```text
(nonblocking_assignment (variable_lvalue (simple_identifier) (select1 (bit_select1 …))) (expression …))
```

After, it reads:

```text
(clocking_drive (clockvar_expression (clockvar (simple_identifier)) (select1 …)) (expression …))
```

Which is the failure `Step.spliced`'s comment predicts, arrived at by the exact
route it warns about. A bit-select assignment in an `initial` block is not a
clocking drive; there is no clocking block in the file for it to drive.

## Why "one step" was not what it looked like

Expansion runs **to fixpoint**, not once. A rank authored over a region of three
steps can arrive at a later round sitting on a body that is by then one step,
because earlier rounds already collapsed the region into a single step. So
`body.steps.len == 1`, read at the moment of a fold, does not answer "did the
author write this rank around one step". It answers "is whatever is left of the
region now one step" - a fact the press derived, being read as a fact the author
asserted. Rust's `prec.right(0, repeat1(punct))` genuinely is a one-step
alternative as written; verilog's `hierarchical_identifier` rank only becomes one
after normalization eats its `seq`, and the test cannot tell the two apart.

## What the real repair is

Record the rank's **authored** width on the `Step` at import, and carry it
through folding unchanged. Then `spliced` can mean what it should - the fold
moved a rank off the region its author drew - judged against the width the author
wrote rather than the width that survives to this round. That is a front-end
provenance change, not a condition in `expand`, and it is the shape any real fix
here has to take.

## Second finding: the board cannot see this class of change

The damage board came back byte-identical while a verilog statement changed
category. The board is not lying; it measures the corpus, and the corpus's
verilog specimen is `picorv32.v` - Verilog-2005, no clocking block anywhere in
it. So the whole of the instrumented corpus is blind to `clockvar`, which is the
one shape the record singles out as the reason this mark is conservative. A
prediction that names a specific construct needs a file containing that
construct; a corpus board is a control for regressions in general, not evidence
about the case under argument.

Rust's 176 residual conflicts remain, and `TESTING.md`'s zero-for-all-eleven
claim remains wrong about rust until either the authored-width repair lands or
the claim names rust as the holdout.

## Reproducing

```sh
python3 tool/plumb.py run && python3 tool/plumb.py board   # the corpus control
joints grammar upstream/grammars/rust.json | grep RESIDUAL # 176
joints parse upstream/grammars/verilog.json <the file above>
```

The revert is byte-exact: all thirty folios re-minted after it compare identical
to the ones minted before the change.

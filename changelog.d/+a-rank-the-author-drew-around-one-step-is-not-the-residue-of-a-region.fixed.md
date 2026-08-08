Rust pressed to 176 residual shift/reduce conflicts against a `TESTING.md`
paragraph claiming all eleven grammars press to zero, and scala to 192. One of
`_non_special_token`'s alternatives is exactly `prec.right(0, repeat1(punct))`;
the fold that inlines it marked the rank `spliced`, and the ladder then refused
a rank the author did write.

The obvious repair - decline the mark when the body being inlined is one step -
was measured and [rejected](../research/press/RESULT-2-splice.md). It takes rust
and scala to zero and leaves the damage board byte-identical, and it also turns
verilog's `c[i] <= 0;` into a `clocking_drive`, because expansion runs to fixpoint
and a body that is one step *at fold time* can be the residue of a region the
author wrote around three. It reads a fact the press derived as one the author
asserted, which is the same error `spliced` exists to prevent.

So the width is now recorded where the author's intent is still visible.
`Step.region` is stamped at **import**, once, and never recounted: `spread.drawn`
walks a `PREC` node's group and records the **widest** reading of it, which is
what keeps verilog's `optional`-bearing sequence wide even though one of its
readings is a single step. `fold.expand` declines the splice mark when
`region == 1`. Rust and scala press to zero, verilog's `clockvar` is unchanged,
28 of 30 minted folios are byte-identical, and `tool/rung1.py` passes on its own
terms for the first time.

`region` is deliberately **not** part of a body's identity. Adding it to
`spread.bodyKey` and `grammar.Key` was tried and cost sql its unfolding round and
280 fresh residual conflicts, because two bodies that differ only in the width of
an enclosing rank are the same production and must share a slot. It is provenance
about a rank, not a distinguishing feature of a step, and it does not survive to
the folio - `carry_test.zig` declares that loss rather than letting it pass
silently.

The part worth more than the count: scala's 192 were not a classification
problem. It had been **right**-associating a `prec.left` operator, so `A Op B Op
D` parsed as `A Op (B Op D)` where tree-sitter reads `(A Op B) Op D`. Nothing
here could see it - `verdicts.toml` has no scala row and the damage board's
specimen never reaches those cells - so the mechanism carries a hermetic test in
`import_test.zig` that builds both shapes and asserts which one survives the
fold, rather than trusting a corpus that demonstrably cannot fail.

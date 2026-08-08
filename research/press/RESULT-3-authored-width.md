# Result 3 — the width is an authored fact, so record it where it is authored

Result 2 ended by naming the repair, before any of it was built:

> Record the rank's **authored** width on the `Step` at import, and carry it
> through folding unchanged. Then `spliced` can mean what it should - the fold
> moved a rank off the region its author drew - judged against the width the
> author wrote rather than the width that survives to this round.

That is what this is, and it holds. Rust presses to **0** residual conflicts,
scala to **0**, verilog's `c[i] <= 0;` stays a `nonblocking_assignment`, and 28
of the 30 grammars mint byte-identical folios. `tool/rung1.py` passes on its own
terms for the first time.

The unexpected part: scala's 192 were not merely misclassified. They were a
real mis-parse, and the repair fixes it.

## The change

`Step` gains one press-only field, `region` - how many steps the author drew
`prec`/`assoc` around, measured at import by `spread.drawn` and never recounted.
`fold.expand` then declines the `spliced` mark for a region of exactly one:

```zig
if (inserted.prec != .none or inserted.assoc != .none) {
    if (inserted.region != 1) inserted.spliced = true;
}
```

Unmeasured (`0`) reads as wide, so every step this never reached keeps the
conservative answer the mark had before.

### The one measurement that is not obvious

`drawn` records the **widest** reading of the group, not each reading's own
width. An `optional` or `repeat` inside the group gives it a reading with those
members absent, and verilog's `hierarchical_identifier` is exactly that shape:

```javascript
prec.left(0, seq(choice(seq('$root', '.'), blank), repeat(…), _identifier))
```

One of its readings is a bare `_identifier` - one step. Measured per reading,
that alternative claims the author ranked a single step, and the repair
reproduces Result 2's failure exactly: verilog flips to `clocking_drive` again.
Measured across the group, the author plainly drew the rank around a sequence,
and the narrow reading is a reading *of* that sequence rather than a second,
narrower statement.

This is the same mistake as Result 2 in a different disguise - a fact the press
derived being read as a fact the author asserted - and it cost one build to find
because the verilog file from Result 2 was the first thing run after `zig build`.

## What it bought

Residual conflicts, `joints grammar <g>`:

| grammar | before | after |
| --- | --- | --- |
| rust | 176 | **0** |
| scala | 192 | **0** |
| verilog | 136 | 136 |
| haskell | 8 | 8 |
| php | 5 | 5 |
| the other 25 | 0 | 0 |

Rust's three residual entries all named `_non_special_token_repeat5` folds at
`[prec 0 right]` - the rank the author wrote, refused by the ladder. They are
gone, and 176 cells stopped being contested at all (1,569 → 1,393) with the
table's shift and reduce counts unchanged: the cells always had the right
action, they were only recorded as nobody's decision.

**28 of 30 folios are byte-identical**, and the two that moved are rust and
scala. **28 of 30 conflict censuses are byte-identical**, the same two. The
corpus damage board is byte-identical - 411,517 bytes built, 1,979 misread,
78.12% standing, both sides of:

joints `05476a05f` · tree `27a0869d9` (live) · oracle `d85e736fa` seated but
**no verdict live on this arm** (0 of 30 held)

`tool/rung1.py`'s output differs from the run before it in
exactly one number, rust's residual, and the gate flips from
`rust: 176 residual conflicts survived the press` to `11 grammars · zero
residual conflicts · nothing disagreed · residue never past 2`.

## Scala was parsing infix types backwards

Scala's cells did not vanish, they became `sided` - 192 of them, on
`infix_type` - and its table moved 192 cells from shift to reduce. The corpus
board did not notice, because scala's specimen never reaches them. So the same
instrument Result 2 needed was needed again: a file containing the construct
under argument.

`type T = A Op B Op D`, before:

```text
infix_type left: (type_identifier) operator: (identifier)
           right: (infix_type left: (type_identifier) …)
```

After:

```text
infix_type left: (infix_type left: (type_identifier) …)
           operator: (identifier) right: (type_identifier)
```

The first is `A Op (B Op D)`. The second is `(A Op B) Op D`. `infix_type` is
declared `prec.left(0, …)`, so the second is what the grammar says - and
tree-sitter's own parser, run on the same file, produces the second. We were
right-associating a left-associative operator, and had been for as long as the
splice mark was unconditional.

That is a stronger result than the residual count. A residual conflict is a cell
nobody decided; this was a cell decided the wrong way, in a construct scala
programmers write, on a grammar in the pinned eleven.

## What is deliberately not in the change

`region` is the **one** field of `Step` that is not part of a production's
identity - not in `dedup`'s key, not in `spread.bodyKey`. Both say so where they
decline it. Keying on it splits an auxiliary on provenance, and the corpus was
blunt about the cost: 26 of 30 grammars moved, sql lost its unfolding round and
63 of its declared conflicts - which stop matching once the participating rule
set changes - and went from 0 residual to 280 reduce/reduce.

It is not needed. `region` is read by exactly one caller, the fold that sets
`spliced`, and `dedup` runs after that fold - so by then the only thing it
decides has been decided and recorded, and `spliced` is already in both keys.

The hazard this declines to chase, named in `bodyKey` so it is not rediscovered:
`seq(prec(1,a), prec(1,b))` and `prec(1, seq(a,b))` arrive with the same rhs and
the same ranks, regions `1,1` against `2,2`, and share one auxiliary - so
whichever is interned first decides for both. No grammar in the corpus of thirty
contains the pair. If one turns up, widen the merge to the larger region rather
than splitting on it; wide is the conservative answer everywhere `region` is
read.

## The gates could not have caught either half of this

Worth writing down, because it is the third time in this dossier:

- `research/collate/verdicts.toml` covers verilog (16 rows), php (2), swift (1)
  and go (1). It has **no rust or scala row**, so `abide.py` is structurally
  blind to both grammars this change touches. Its two DRIFT rows are verilog's,
  pre-existing, and cannot be this change's: verilog's folio is byte-identical.
- The damage board measures the corpus, and the corpus specimen for a grammar
  need not contain the construct under argument. It missed verilog's `clockvar`
  in Result 2 and scala's infix chain here.

So the mechanism now has a hermetic test of its own rather than a corpus one.
`import_test.zig`'s *"a rank drawn around one step survives a fold, and one
drawn around a region does not"* puts both shapes in one grammar - a
`prec.right(0, repeat1(…))` and a `prec.left(0, seq(choice(…, ε), …))`, both in
the `inline` list so both meet a host - and asserts the narrow one keeps its
rank while the wide one is absorbed. Removing the `optional` from the wide side
makes it pass while verilog breaks, which is why the `optional` is there.

## Reproducing

```sh
python3 tool/rung1.py                                        # passes
joints grammar upstream/grammars/rust.json  | grep RESIDUAL   # 0
joints grammar upstream/grammars/scala.json | grep RESIDUAL   # 0
joints parse upstream/grammars/verilog.json <Result 2's file> # nonblocking_assignment
joints parse upstream/grammars/scala.json   <the infix file>  # left-nested
python3 tool/plumb.py run && python3 tool/plumb.py board      # byte-identical
```

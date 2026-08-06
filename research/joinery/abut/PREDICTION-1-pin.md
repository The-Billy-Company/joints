# Prediction 1 — what the progress pin actually refuses

Written before the hand exists. Julia's `_immediate_*` cohort was handed over
with the claim that `step`'s progress pin *refuses* a zero-width answer that
moves no memory, and that admitting one needs the pin relaxed.

## The claim I am testing

Reading `outside.step`, the pin is not a categorical refusal:

```zig
if (hit.skip + hit.len > 0) return hit;
const now = carry.shape();
if (carry.pinned) |was| {
    if (was.at == at and was.sym == hit.symbol and was.shape == now) return null;
}
carry.pinned = .{ .at = at, .sym = hit.symbol, .shape = now };
return hit;
```

The **first** zero-width answer at an offset is returned whatever the memory
did. Only an exact repeat of `(at, symbol, shape)` is refused, and it is
refused against a **single slot** holding the most recent answer.

**P1.** The handover is wrong about the mechanism. A memoryless zero-width hand
is admitted by today's `step` on its first answer; nothing has to be relaxed to
seat the cohort. What the pin cannot do is *prove* termination, because one slot
cannot see a cycle longer than one.

Falsified by: a hand that answers zero-width with the memory unmoved, whose
**first** answer comes back null from `step`.

**P2.** The hole a single slot leaves is a two-cycle. `A` then `B` then `A` at
one offset with the memory unmoved is permitted today, because `B` overwrote the
slot that would have refused the second `A`. Nothing in the tree reaches it
because every zero-width hand seated so far either moves a stack (python's
dedents, html's implied closes) or is the only member that can answer at its
offset (haskell's `sever`). The abut cohort is the first with five members and
no memory.

Falsified by: a construction where `A,B,A` at one fixed offset with one shape is
refused by today's `step`.

## What I will build instead of relaxing anything

A per-offset ledger, replacing the single slot:

- keyed on `at`; a hit that moves the cursor retires it by moving `at`;
- within one `at`, a total counter with a hard ceiling;
- within one `(at, shape)`, the set of symbols already answered.

**P3.** The ledger is *strictly stronger* than the pin — it refuses everything
the pin refused and also the two-cycle — so no grammar's trees may change.
Twenty-nine of thirty byte-identical is the wrong bar here; **thirty** of thirty
is, because this half of the work admits nothing new on its own.

Falsified by: any grammar's tree changing under the ledger alone, before the
abut hand is seated.

## The ceiling has to clear a real run

A run of dedents at one offset is legitimate and unbounded by anything but the
column stack. Capacities: `offside.Columns.max = 96`, `lineage.Tags.max = 64`,
`fence.Spans.max = 16`. So a ceiling below 96 would refuse a python file that
closes 96 blocks at EOF.

**P4.** No corpus file reaches even 16 zero-width answers at one offset, so a
ceiling of 256 is untestable from the corpus and the ledger's fine-grained
`(shape, symbol)` arm is what actually fires.

Falsified by: a corpus grammar whose parse changes when the ceiling is lowered
to 96.

# Prediction 6 — A and B together, which nobody has measured

Three lanes have now arrived at the same pair of repairs from different
directions and none of them ran the pair. RESULT-2 measured A alone and B alone
and rejected both. RESULT-3 shipped a third thing instead. RESULT-5 closed by
naming the composition as the open question: *A so the cell answers `fold`, B so
the forks A deletes come back as forks rather than vanishing.*

That sentence is a hypothesis about a mechanism, and writing this file made me
doubt it before I built anything. The prediction below is mostly about why.

## What A and B are, exactly

**A — the host's rank wins the splice boundary.** `fold.zig::expand`, the two
lines at the end of the splice:

```zig
if (last.prec == .none) last.prec = host.prec;   // today: fills in only
if (host.prec != .none) last.prec = host.prec;   // A: wins outright
```

Today the victim's rank survives and the host's is discarded, so
`variable_lvalue`'s `prec.left(37)` arrives at the boundary wearing
`hierarchical_identifier`'s `left(0)`. Under A the 37 survives.

A carries one thing RESULT-2's A could not, because `Step.spliced` did not exist
when it was measured: if the host's rank wins, the surviving rank *was* written
here, so its provenance is the host's and `last.spliced = host.spliced`. A rank
that wins while still flagged as inherited would be a third repair, not A.

**B — record the cell the side rung decided.** `bench.zig::decide`. `spared`
today fires only for the rung-2 `unwritten` arm; B extends it to the one rung-3
arm that deletes a reading (`purely(f, .left) => .fold`). Purely additive: `r[t]`
is already written, the primary action does not move, the deleted read comes back
as the fork's other limb.

## The mechanism I think RESULT-5 got wrong

A deletes 8,817 forks by making **precedence** answer. Contested cells go
18,732 → 9,915, declared 18,715 → 9,900. Those cells leave rung 2 decided —
`above and !below` → read, `below and !above` → fold — and never reach rung 3.

B records cells **rung 3** decided.

So B does not cover the set A empties. They are disjoint by construction, and
the composition RESULT-5 describes cannot work the way RESULT-5 describes it.

There is a second-order channel that could rescue it, and it is the only reason
this is worth building. Under A more boundary steps carry an authored non-zero
rank, so more cells **tie at a non-zero level** and fall through rung 2 into
rung 3 — where `purely` now finds `authored = true` more often, precisely
because A's boundary steps are authored. B fires on a set A *enlarged*. Whether
that set is 8,817 cells or 30 is the whole measurement.

## Predictions

1. **A alone reproduces verilog 67,349.** If it lands anywhere else, my A is not
   RESULT-2's A, or the provenance bit interacts with it, and I say so before
   quoting anything else. This is the reproduction gate.
2. **B alone does *not* reproduce verilog 62,645 / scala 16,883 / elixir 8,917.**
   B was measured before `Step.spliced` shipped. The verilog cells B was buying
   with — state 1184's `[`, folded away by a `left` `clockvar` inherited from
   `hierarchical_identifier` — are already forks today, because `purely` declines
   an unauthored side. B alone should be **at or near baseline on verilog**, and
   cheaper than 16,883 on scala. Its cost is the residue on cells whose side
   really was written.
3. **A+B ≈ A on verilog.** Within a few hundred bytes of A's own number, not
   back down at baseline. The 8,817 forks do not come back.
4. **A+B is a worse trade than either alone.** It should carry A's verilog
   regression *and* B's scala/elixir regression, because the two costs are in
   different grammars and nothing cancels.
5. **Scala's `@SerialVersionUID(0) class Some[+A]` shreds under B and under
   A+B**, and not under A. It is B's fork that `gather` takes the wrong limb of;
   A does not offer that fork. If it shreds under A too, B is not the cause and
   RESULT-2's attribution was wrong.
6. **The controls all stand under all three arms.** B is additive, A only moves
   ranks, and 17/17 held for every arm in RESULT-2's table.

If 3 and 4 hold, the honest close is that the composition is not a repair and
the next cheapest thing is the `gather` limb defect HANDOVER-wrong-limb.md
names — because B's *witnesses* are the best anyone has got (W5–W8 all stand,
17/17 controls) and the only thing stopping B being shipped is one layer down.

## What I am not claiming

Verilog's eight `_identifier` walls are not mine to claim. 6,591 of those bytes
are a measuring artifact of the peel, 98.3% on the `macro_text` path, with one
state holding more than one fold. Nothing below counts them.

## The ground

Every arm is built and read inside one rsynced scratch tree taken at a fixed
moment, because `src/kernel/lex/outside.zig` and `src/kernel/quire/gather.zig`
are being edited by other lanes and the board flapped twice this evening. The
oracle store under `.local/differential/` is a private clone, not the shared
one — `rack.py` records scala reading 1,278 crooked in one run and 9,087 in the
next off that directory, same pin, same script. The control is pinned **after**
the arms and diffed against the baseline; if the reverted tree disagrees with
the baseline while the code under test is byte-identical, the table is void and
does not get published.

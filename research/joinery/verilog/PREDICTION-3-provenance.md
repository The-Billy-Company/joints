# PREDICTION-3 — a provenance bit on the step

Written before any measurement of the change, against
`RESULT-2-splice.md`, which named this as the honest next step and did not
start it:

> A provenance bit on `Step`, so rung 3 can decline a side it inherited rather
> than folding on a rank that was never authored for this reading. `Step` is
> `leaf.StepRecord`, an `extern struct` in the folio format, so that is a format
> change and `impose`'s ledger owns it.

## What I found before predicting

The handover's own sentence is wrong about the format, and the error is worth
naming because it is the reason the folio hazard looked unavoidable.

`leaf.StepRecord` is **not** `g.Step`. It holds two fields:

```zig
pub const StepRecord = extern struct {
    alias: u32,
    field: u32,
};
```

`prec` and `assoc` are not in it, and `bind.zig` says so out loud where it
rebuilds a step: *"Precedence and associativity are press inputs and are not in
the file; a bound step carries only what names a child."* A folio carries the
table, not the argument that produced it, so the static ranks are consumed
during the press and never written.

A provenance bit **about those ranks** therefore lives exactly where they do:
in the press, and not on disk. There is no `extern struct` to widen, no
version bump, no padding to re-zero.

That is a claim to falsify rather than to assert, so it is P1.

There is a second thing already true and worth naming: `impose`'s ledger covers
`lalr.Conflict`, `settle.Frayed` and `lalr.Tables`. **It does not cover
`g.Step`.** The exact bug it exists to stop — a press-side field the writer
silently does not carry — is unguarded for the one type this change touches. So
the guard has to be extended whichever way P1 lands.

And a third: `grammar.zig::dedup` keys a production on `lhs`, `rhs`, every
step's `prec`/`assoc`/`alias`/`field`, and `dynamic`, and it runs **after**
`fold`. Two bodies identical except for where their rank was authored are two
different statements, so provenance belongs in that key or the deduplicator
collapses them.

## The change

1. `g.Step` grows `spliced: bool = false` — "the rank on this step was absorbed
   from a rule the press folded away, not written on the production that names
   it".
2. `fold.zig::expand` sets it: every step inserted from a victim's body that
   carries a rank of its own is spliced, and the boundary step inherits the
   *host's* provenance along with the host's rank, so a second fold round cannot
   launder it clean.
3. `column.Folds` records whether any *surviving* reduction authored its own
   side; `Ladder.purely` answers no when none did.
4. `impose`'s ledger grows a `step` roster naming all five fields, with `prec`,
   `assoc` and `spliced` marked press-only; `folio_test` asserts a bound step
   comes back with them empty and with `alias`/`field` exact.

Nothing about how a rank is *chosen* at the boundary moves. Repair A was that,
and it was measured worse.

## Predictions

**P1 — no folio change is needed, and the round trip proves it rather than
assuming it.** Falsified by any consumer of a *bound* grammar reading
`Step.prec`, `Step.assoc` or `Step.spliced`; by `folio.version` needing a bump;
or by the new round-trip assertion failing.

**P2 — the ledger is blind here today, and I can demonstrate it.** Adding
`spliced` to `g.Step` and building compiles clean with the field written
nowhere, because `accounts` is never called on `Step`. Falsified by the build
failing before I extend the ledger.

**P3 — state 1184's row gains a shift on `[`.** The tie stops being answered by
`clockvar`'s inherited `left`, `Ladder.step` returns `.undecided`, `standing`
comes to 2 and the cell is recorded. Falsified by `--holding 'clockvar ->
_identifier .'` still showing no `[` in the row.

**P4 — W7 and W8 seat, with their controls standing.** These are the two the
narrowed repair C also seated, and they are the ones that live in this cell.
Falsified by `smallest.py` reporting either red, or either control failing.

**P5 — W9 (`x = {a[3], b};`) seats too, and W5/W6 (`$signed`) do not.**
`RESULT-2` showed the concatenation failure *is* this deleted fork, and that
`$signed` does not pass through an identifier state. P4 of the previous
prediction failed in the `$signed` direction under two repairs, so this is the
one I am least sure of. Falsified either way by `smallest.py`.

**P6 — this is NOT repair B narrowed, and its damage may go either way.** B was
purely additive: it recorded a cell whose primary action was already written.
Declining an inherited side leaves `keep_read` true, so the *primary action
changes* from the fold to the read in every cell it touches. Falsified by
verilog's damage landing at B's 62,645 exactly, which would mean the two changes
are the same change.

**P7 — scala and elixir regress, and by less than under B.** They regress
because the gather wrong-limb defect is one layer down in `quire` and is not
mine to fix; by less because a side authored on the folding rule itself is
untouched here and was not under B. Falsified by either coming back
byte-identical, or by either exceeding B's 12,733 / 7,358.

**P8 — every grammar presses to the same bytes twice.** The bit never reaches
disk, so no `extern struct` grew and no padding came back. Falsified by any of
the thirty differing between two pressings by the same binary.

**P9 — `rack --square` shows no grammar that buys `built` and pays `square`.**
The guard is blind on verilog and can see scala and elixir, which are exactly
the two that move. Falsified by any grammar's racked bytes rising.

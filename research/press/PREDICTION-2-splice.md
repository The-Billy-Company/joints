# Prediction 2 — does a rank on a one-step body keep its scope through a fold?

`TESTING.md` claims all eleven pinned grammars press to zero residual conflicts.
Rust presses to **176**, all shift/reduce. Bisected to `967c9ac` and older, so it
predates the public repo and the rename - the claim has been wrong for a while
rather than newly broken.

The cause is `_non_special_token`. One of its alternatives is exactly
`prec.right(0, repeat1(punct))`, and `_non_special_token` is hidden, so
`fold.expand` inlines it into `_token_pattern`. Every rank that travels through
an inline is marked `spliced`, and the ladder refuses to decide a contest on a
spliced rank - so the state stays undecided and is classed `residual`. The rank
the author wrote is present, applies to the pair in contest, and is ignored.

`Step.spliced` says as much in its own comment, and names verilog's `clockvar` as
the reason it is conservative.

## Prediction 2a — the mark is the cause, not a missing rank

> **Prediction:** rust's 176 are all states where a spliced rank would have
> decided the contest. Declining to mark this one fold takes rust to 0 with no
> other change to the press.
>
> *Falsifier:* unmarking leaves rust's residual count above zero, which would
> mean the rank is absent or does not cover the contested pair, and the
> diagnosis is wrong.

## Prediction 2b — body width is the discriminator

> **Prediction:** a rank is authored around a *region* of a body, and what a fold
> costs is the region: the steps that shared it end up spread across a host that
> never made the statement, so the rank arrives ordering pairs its author was not
> talking about. A body of **exactly one step** has no region to lose. So
> `body.steps.len == 1` separates the fold that preserves the author's statement
> from the fold that breaks it, and marking only the second is sound.
>
> *Falsifier:* any grammar in the corpus of thirty parses differently, or any
> folio outside the three that gain the resolution changes bytes.

## Prediction 2c — verilog's `clockvar` stays absorbed

> **Prediction:** `hierarchical_identifier` ranks `prec.left(0, seq(…))` over
> bodies of two and three members, so the width test keeps it spliced and the
> absorbed side keeps refusing. Verilog's `c[i] <= 0;` inside `initial begin`
> goes on reading as a `nonblocking_assignment` to a `variable_lvalue`, not as a
> `clocking_drive`.
>
> *Falsifier:* that statement reads as a `clocking_drive`. Then the width test
> has laundered exactly the rank the record says must stay absorbed, and no
> residual-count win pays for it.

2c is the one that decides the change. 2a and 2b are about whether the fix works;
2c is about whether "one step" means what it appears to mean, and the instrument
for it is a hand-written file rather than the corpus, because the corpus's
verilog specimen is `picorv32.v` - plain Verilog-2005, with no clocking block in
it to exercise.

# Prediction 2 — do the four defects share one mechanism?

Written before any measurement. The brief says four witnesses that turn out to
be one defect is worth more than four fixes, so this is the prediction the lane
is really about, and it is the one most likely to fail.

## The hypothesis

`src/press/grammar.zig` says it plainly about `prec.dynamic`:

> tree-sitter compares the **sum** over each candidate subtree, which no table
> can know because the subtrees do not exist yet.

And `src/kernel/quire/gather.zig`:

> Where several readings accept, the least speculative wins: without dynamic
> precedence there is nothing better to compare them by.

So outliner ranks a *cell* where tree-sitter ranks a *subtree*. If the
wrong-parent class is one defect, that is the defect: an ambiguity both
grammars contain, resolved by a per-production rank the press can spend at
table-build time instead of by a sum nobody can know until the subtree exists.

## P4 — go, python and elixir are the same mechanism

All three are ambiguities the vendored grammar itself declares — a
`conflicts` entry, a `prec.dynamic`, or both — over productions outliner has to
choose between with only the table in hand.

**Falsifier.** Any one of the three has **no** declared conflict and **no**
dynamic rank on either of the two competing productions. Then it is an
ordinary LALR resolution or an import defect, and the "one finding" claim is
dead for that grammar.

## P5 — but they will not all be resolved at the same place

Even if the ambiguity is declared in all three, the *place* outliner decides
will differ: at least one will be settled statically in the table (the rival
action is gone before a parse starts) and at least one will be settled at fork
time (both readings live, and the loser is picked at the end).

**Falsifier.** All three decide in the same half. Then the class really is one
fix, which is a better finding than this prediction and I will say so.

## P6 — go is the odd one out

go's `type_conversion_expression` beating `call_expression` on `fmt.Print("x")`
is not dynamic precedence. tree-sitter-go declares the conversion/call
ambiguity as a **conflict** and resolves it with GLR error-driven survival —
the conversion reading dies later, when nothing accepts it — rather than with a
rank. Outliner has no later; it commits.

**Falsifier.** go's competing productions carry a nonzero `prec.dynamic` and
the rank alone explains the choice.

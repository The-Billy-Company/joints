# Prediction 1 — is the cohort rule actually the wall?

Written before any measurement of the board. The brief I was handed says:

> Stand-ins for external scanners are governed by `outside.Provision`, which
> **requires the whole cohort**: if a grammar declares N externals, you spell
> all N or you spell none.

## Prediction

**That claim is false, and it is a misreading of the word "cohort".** I predict
the rule is per-row rather than per-grammar:

- `Provision.cohort` names *the other externals the scanner that row was
  transcribed from also emits*. It is evidence that this grammar's scanner is
  the one the row was read off, not a demand that we answer everything the
  grammar declares.
- `Troupe`/`seated` requires the full **cast** — the parts one troupe names —
  for the same reason, and again not the grammar's whole external set.
- So a grammar may have most of its externals blind while a few are seated, and
  that should already be shipping.

Falsifiable form: **if the claim were true, then every grammar with a seated
external would have all of its externals seated.** Count seated vs declared per
grammar. If any grammar ships a strict subset, the claim is dead.

Predicted counter-examples, in order of confidence:

1. **bash** — the roll seats `variable_name`, `file_descriptor`,
   `test_operator` and a heredoc troupe. If bash declares more than ~4
   externals the claim is dead on the first grammar.
2. **haskell** — the `.writ` row seats six orders plus a brace plus four
   conditions; the `.scry` row seats four extras. `outside.zig`'s own comment on
   the haskell scry row says "the other forty-four externals stay blind on
   purpose", which if true is the claim's own source file contradicting it.

## Why it matters either way

If the cohort rule is *not* the wall, then the second design question in the
brief — "can a partial cohort be made to fail closed" — is already answered by
the code, because **blindness is per-terminal**. An external nothing answers
produces no token, the parse stops there, and that is a refusal that is provable
from the byte at hand in the strongest possible sense: no hand and no slate row
even offered an answer. The fail-closed partial the brief asks me to design is
the mechanism already in the file.

If it *is* the wall, my read of `scanner.zig`'s compile loop is wrong and I have
to find where the whole-grammar quantifier lives.

## Prediction 2 — what the real wall is

If the cohort rule is not blocking, something else must be, because swift is
still at 2,306 of 28,435. I predict the real blocker is one of:

- (a) nobody has written the row/troupe yet, and it is simply undone work; or
- (b) a row exists but its cohort names a terminal swift does not declare; or
- (c) `_implicit_semi` is zero-width, so it cannot be a `Provision` at all — the
  roll is patterns over bytes and a pattern may not match empty. It needs a
  hand, i.e. a `Troupe`, and the existing `.caesura` hand is gated on
  `kin = "_template_chars"` which swift does not declare.

I predict **(a) and (c) together**: the mechanism exists (`caesura`), it is
correctly refused to swift/kotlin/scala by `kin`, and nobody has written the
per-language rows. That makes this undone work wearing a soundness argument's
clothes.

# Prediction 1 — the second move

Written **before** any arm was pinned, against `f7ba400`. The lane before this
one measured that every repair this runtime performs is a deletion, and priced
the consequence at **1,929 scars over twelve grammars tree-sitter derives
clean**. This lane gives the runtime an insertion and scores it on `square`.

## The rule I am about to measure

At a refusal, supply a terminal `m` and re-read the same token when, and only
when:

1. `m` is **anonymous** — a literal the grammar spells itself. A zero-width
   instance of a *named* terminal is a token the lexer could never have
   produced, so supplying one asserts the author omitted text nobody can name.
   An anonymous literal names exactly what is missing.
2. Shifting `m` from a live reading makes **the token the file actually holds**
   shiftable. Not "m is legal here" — the refused token must resume. This is
   the justification and the termination proof at once: the supply is always
   immediately followed by a real shift, so the offset advances.
3. **Exactly one** such `m` exists across every live reading. Two candidates is
   the parser guessing, and the brief is explicit that choosing badly is worse
   than not choosing.

No constant is introduced. The walk reuses `shiftable`'s two existing bounds.

## Predictions

**P1 — the rule fires on a minority of the 1,929.** Between 15% and 45% of
those scars become supplies. **Falsifier either way**: under 5% means the
uniqueness clause made the rule ornamental; over 80% means it is admitting
candidates it has not justified and I should disbelieve it before publishing it.

**P2 — `square` rises across the twelve and no grammar pays for it.** At least
six of the twelve gain, and no grammar anywhere loses more than 200 B of
`square`. **Falsifier**: any single grammar losing more `square` than the twelve
gain together.

**P3 — the localization lead holds.** verilog's scars cover 34% of its file
against tree-sitter's 100%. A vocabulary that recovers further will tempt the
parse to sprawl. Verilog's scar coverage stays under 50%. **Falsifier**: over
50%.

**P4 — `built` barely moves.** An inserted node covers zero bytes, so it cannot
add to `built` directly; it can only move it by letting real bytes fall under a
parent they were not under. Corpus `built` moves under 1%. **Falsifier**: over
3%, which would mean the parse is building structure over text rather than
completing structure the author began.

**P5 — the twelve are not where the value is, and I expect to be wrong-footed
here.** They are 2,169 B of *file*; verilog alone is 94,657 B and is not in the
list because tree-sitter also fails on it. I predict the twelve account for
**under 40%** of the total corpus `square` movement. **Falsifier**: over 70%.

I am recording P5 because it is the prediction whose flattering direction is the
opposite of the brief's framing, and the lane before me led with the two it got
wrong.

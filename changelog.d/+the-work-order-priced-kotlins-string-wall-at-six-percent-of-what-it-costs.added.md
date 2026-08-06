`unbound = rubble + spoil` is the column the board prints its work order by, and
it excludes `orphan` on purpose: a comment is a leaf in any parse, so charging
its bytes to "a token lying where a tree should be" would make the column track
comment density instead of grammar health. Correct about a comment. Read as a
work order it sent every lane past the largest fixable number on the board.

Kotlin scores `unbound = 1,269` and ranks eighth. Its real cost is **20,728
bytes of `built`** — 41.44% → 99.31% standing on `Maps.kt`, +3.93 points of the
526,798-byte headline — behind one blind external family,
`_string_start`/`string_content`/`_string_end`. The gap is `orphan`, and
kotlin's 19,705 orphan bytes are not a measure of how much KDoc the file has;
they are a measure of how many times the parse felled its stack. 139 of
`Maps.kt`'s 142 mends stand on that one family. Ranked by `size - built`
instead, kotlin moves eighth → third, php sixth, scala fifteenth → eighth, and
all three are the same defect: a blind string interior.

Proved by ablation rather than by a verdict, because a verdict is a location.
Blanking the 45 string literals to same-length identifiers takes `Maps.kt` from
142 mends to 3, `built` 14,841 → 35,569, `orphan` 19,705 → 208, bare leaves
237 → 5, roots 419 → 11 — and `describes` **up** 8,322 → 8,580 with `spoil`
936 → 16, so this is not the reading-less shape. Blanking every comment instead
leaves `built` at 14,841 to the byte and the mend count at 142: the comments
carry nothing. Blanking the imports removes 2 mends, zero bytes, and moves
`orphan` the wrong way.

What it costs and where it goes the wrong way. Nothing was seated. Kotlin's
fence needs a `prefix_len` on `fence.Span` (Kotlin 2.1 multi-dollar
interpolation fixes the sigil width at the opener), a greedy triple close that
`fence.read`'s first-match rule does not have, and two `Troupe` roles for
interpolation starts that are neither open, body, close nor escape — the third
of which sits in the region another lane holds. And `Maps.kt` contains **zero**
triple quotes, **zero** `$` and **zero** backslash escapes, so every number
above would be identical under a stateless `"[^"]*"` regex that is unsound the
moment a string interpolates. The board is not the test for this change and
there are no probe files yet.

Second finding, from the same pass: `orphan > 0` **iff** the file mended, on
thirty of thirty. Twelve grammars mend zero times, score zero orphan, and hand
back exactly one root, because `crown` — the only operation that adopts extras
no reduction claimed — is gated on `x.mends == 0` for the whole file. php
reaches **8,091 orphan bytes and 119 roots on a single mend over a single
byte**. Five instruments for all of this land in `research/joinery/orphan/`,
each reading through `standing.py`'s own `ranged`/`ask` so none of them can
disagree with the board about what a root is.

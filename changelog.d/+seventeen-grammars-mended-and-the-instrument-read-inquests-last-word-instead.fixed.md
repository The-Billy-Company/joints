`stamp.ask().mends` read **0 on every one of the seventeen grammars that mend**
- kotlin's 142, verilog's 2,109, php's 1 - and read correctly on the thirteen
that do not. Right on every quiet row and wrong on every interesting one, which
is why it survived four generations of the reader that produced it.

`verdict()` took the **last non-blank line** of stderr. On a walled grammar the
last line is not the stop; `inquest` prints after it, prefixed with the grammar
name rather than the source path, on all eighteen rows that hit a wall. So the
reader handed inquest's prose back as the verdict, and because `outcome()`
derives `kind`, `reach`, `roots`, `at` **and** `wall` from that one string, five
fields went with it: seventeen grammars reported `mends 0`, `kind state`,
`reach 0`, and no wall at all. `BLIND` and `UNSOUND` search the whole stderr and
stayed correct throughout, which is the shape of the thing - the two fields
nobody suspected were the two that were right.

The line is now found by asking which one the **source** names, rather than by
counting from either end: `verdict()` walks stderr in reverse for the first line
carrying the path we passed in, and falls through to the old behaviour only when
no line does (yaml lexes nothing and prints none). Corpus-wide, with both rules
run over the **same captured stderr** from one pinned binary so the parser
cannot be what moved: `mends` **0 -> 4,551**, `reach` **100,399 -> 507,850
bytes** (19.1% -> 96.4% of the 526,798-byte corpus), `roots` **30 -> 8,435**,
walls named **0 -> 15**, and the kind census goes from `{state: 15, whole: 12,
other: 3}` to `{mended: 17, whole: 12, other: 1}`. Two of the seventeen mending
rows still name no wall, so `walls_named` is 15 and not 17; that is a second
bug, not this one.

The cost, in the same breath: this is the **fourth** rule to read that line and
the third to be wrong. Generation one took the tail after the last `": "`,
which silently ate python's verdict down to `at 482 in state 880` because the
payload names the token it refused and that token is a colon. Generation two
fixed the boundary and kept the wrong line. Both are now kept in `stamp.py` as
named functions and the `--probe` gate runs all three side by side over 20
shapes, printing which of the 20 each prior rule gets wrong (rsplit 6, last-line
5) - because the gate before this one had no fixture with an inquest line under
the verdict, so it passed against the broken reader.

Downstream: `tool/walls.py`'s `voice` - mends per distinct wall - divided by
this and read **0.0 for every walled grammar**, a zero on both sides of the
divide, reporting every tail as pure depth. It now separates them: markdown
79x, verilog 53x, haskell 32x, sql and ocaml 14x are repetition; the corpus
peel names 181 distinct walls across 18 walled grammars.

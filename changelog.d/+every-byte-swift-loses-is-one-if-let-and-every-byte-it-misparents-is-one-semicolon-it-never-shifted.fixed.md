Swift's damage column was read as pointing at the implicit-semicolon path, on
the strength of 3,997 orphan bytes and hundreds of roots. It does not, and the
caesura row is not merely innocent - it is the largest thing holding swift up.

**The falsifier.** `swift-nosemi` is today's tree with swift's `caesura` row
commented out and the plumbing left in. Against `swiftlane-ctl`:

| | control | row removed |
|---|---|---|
| built | 25,279 | 12,178 |
| damage | 3,189 | 16,290 |
| orphan | 2,521 | 8,998 |
| roots | 128 | 1,332 |
| mends | 7 over 28 B | 334 over 1,224 B |

The row is worth 13,101 bytes of `built` and 1,204 roots. Nothing about swift's
board is a caesura that failed to fire.

**What the roots actually are.** `Chunked.swift`'s forest is 101 top-level
nodes, contiguous, correctly built, and it never closed a `source_file` - so 49
line comments sit at the top level as `orphan` for no reason of their own.
Rewriting **one site** - line 793, `if let limit = limit {` - takes the file
from `128 roots, mended 7 over 28B` to `accepted, 1 root` covering `[0, 28469)`.
Damage 3,189 → 0, orphan 2,521 → 0, rubble 95 → 0. Every number in swift's
damage column is that one construct.

Reduced: `if let a = b { }` refuses, and so do `= b()`, `= b.c`, `= (b)`,
`= b as? C`, and `while let`. `if a == b { }`, `if let a { }` and
`if let a = b, c { }` all parse. The `{` is being shifted as a trailing closure
- the tree reads `call_expression (simple_identifier) (call_suffix
(lambda_literal))` - so the `if` never gets its `_block`. In the grammar the
only thing separating those two readings is `PREC_DYNAMIC(-1)` on
`_fn_call_lambda_arguments`, under the single-symbol conflicts `['call_suffix']`,
`['constructor_suffix']` and `['_fn_call_lambda_arguments']`. tree-sitter forks
and settles it at the end of the parse; a deterministic table has to settle it
at generation time and settles it the other way. That is a press-lane defect and
is named here rather than fixed.

**And the crooked column is a second, separate defect.** A per-byte spine census
of the whole file against the oracle, with our missing `source_file` aligned
away: 13,140 bytes square, **7,081 bytes where both sides have `statements`,
under the same parent, with a different extent**, and ~7,800 more whose outermost
rung disagrees because they are inside the `extension ChunksOfCountCollection`
block the `if let` above destroyed. Two defects, essentially the whole
disagreement.

The 7,081 are three bytes per function body. `eat_whitespace` advances the
whitespace it crosses with tree-sitter's `skip` flag, so its zero-width
`_implicit_semi` lands *past* the newline and the indent, `statements` takes the
optional trailing `_semi` and reaches the `}`; ours stops at the last statement.
`caesura.zig`'s header called that "a span and no structure" - it is a span and
7,081 crooked bytes. Moving the hand's answer to `.{ .skip = i - at }`, which is
the C scanner's own placement, changes nothing: an explicit `;` in that exact
position **is** shifted and does square the rung, so the state admits `_semi`
before `}` and the implied one is being declined downstream of the lexer. The
inert edit was reverted and the measurement is written into the header where the
dismissal used to be.

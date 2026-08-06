Swift's `multiline_comment` is seated on its own `marrow` vein. Swift's
`eat_comment` is byte-for-byte kotlin's `scan_multiline_comment` - the same
`after_star` flag, the same three cases, the same rule that a `/` not preceded
by `*` opens a nesting level when a `*` follows it - with exactly one
difference: kotlin accepts an unterminated comment at end of input and swift
refuses, so its `/*` in a truncated file falls back to the operators rather than
swallowing the tail. One walk serves both veins with that line as a parameter,
because guessing either way would have been a wrong tree in one of the two
languages. The vein is separate rather than reused because both grammars declare
the same terminal name, and one shared vein would have put two rows under one
pinned permission - which is how `marrow/kotlin_block` once read
`{kotlin, scala}` and let either widen onto the other silently.

`/* c\n d */` used to come back as `custom_operator` `/*` over a
`simple_identifier`, then `d * /` as a multiplicative expression. `/* x /* y */
z */` came back as a `regex_literal`. Both are now one `multiline_comment` at
its right extent, and the two specimens go 2/4 -> 4/4.

**And it moves the board by zero bytes, which is the finding.** The work order
priced this at 3,997 orphan bytes, the second-largest row in the blind-comment
cohort. `upstream/sources/Chunked.swift` contains **zero `/*`** - 237 `//` line
comments and no block comment at all - so a blind `multiline_comment` could not
have been responsible for one byte of it. Measured: swift's row is unchanged to
the byte across the seating (`built 23,131 · orphan 3,997 · damage 5,337`), and
all 30 grammars are tree-identical. What actually walls swift is eleven distinct
walls, none of them a comment: the `comment` rule's own `(?:[^\r\n]*)` tail in
state 66, the identifier pattern in state 130, and `)` in three states.

The instrument that lied is the one the board is computed from. `/* c\n d */`
parsed as **one root with zero mends** - every signal this parser emits saying
"fine" - while reading a comment as a division and a multiplication, and those
twelve bytes were counted `built` the whole time. They are *still* counted
`built` after the fix, because the comment attaches as a top-level extra rather
than orphaning, so the correction is invisible in both directions. `roots`,
`mends`, `covered` and `built` cannot tell a confidently wrong tree from a right
one; only a specimen asserting a name and an extent can. The blind-comment
cohort's 37,575 bytes should be re-derived per file before anyone takes scala or
php off that ranking.

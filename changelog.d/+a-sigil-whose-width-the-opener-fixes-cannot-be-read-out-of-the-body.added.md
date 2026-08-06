Kotlin's strings are seated. `fence` gains a `kotlin` dialect and `Span` gains a
`prefix_len`, because Kotlin 2.1 fixes the interpolation sigil's width at the
opener - inside `$$"a $x b"` it takes two `$` to start one, and no amount of
looking at the body recovers that. The reader is its own function rather than
four more conditionals on the shared driver, because all three of its moves
differ from the driver's: the raw close is greedy, the sigil is a run, and a
backslash is matter inside a raw literal. Two new terminals answer the
interpolation openings, which the ordinary lexer was reaching before -
`val s = "a ${n + 1} b"` came back as a **`lambda_literal`**, a confidently
wrong node in the middle of a string.

Five of kotlin's eight blind externals now answer. Kotlin's damage falls
20,974 -> 246 bytes, `orphan` 19,705 -> 208, bare leaves 237 -> 5, standing
41.4% -> 99.3%, and the corpus headline 69.1% -> 73.0% (2026-08-05, pins
`lex-before` `dfc481e49` and `lex-after` `c7bc59177`). `describes` rises 97,595
-> 97,898 nodes, so the bytes were read rather than swallowed, and 29 of 30
grammars are tree-identical with only kotlin moving - compared as trees, not as
folio digests.

**None of those numbers are the evidence.** `Maps.kt` holds 90 `"` and **zero
`"""`, zero `$`, zero `\`**, so a stateless `"[^"]*"` regex would have moved
every one of them by the same amount. The proof is six specimens, five of them
whole and the sixth holding four of five claims, including `"${"$n"}"` - a
string inside an interpolation inside a string, which a hand with no memory
across the body structurally cannot reach.

One deliberate divergence from the pinned `scanner.c`, which is the only place
this hand disagrees with it. `"""a""""` is the string `a"`: a raw literal
terminates at the *last* `"""` in a run, so `string_content` is `[11, 13)` and
the close is the final three quotes. tree-sitter-kotlin swallows all four into
its end token and hands back `a` - a correct parse carrying a wrong value, and
its own comment says it saw "no point" in separating the two. The grammar's
raw-string rule and the language reference both say `a"`.

Written down because it cost a prediction: I predicted `describes` would rise by
more than 400 and it rose by 303, because not every literal becomes two nodes -
`_string_start` and `_string_end` are hidden, an empty `""` has no content child
at all, and I had priced the shape I was proud of rather than the shape the file
holds.

Eleven of fourteen seated rows were witnessed by a specimen and three were
corpus-only — and those three were exactly the three whose measured worth was
negative. A row only the corpus board can see, which the corpus board says does
harm, is the row most in need of something able to say no on its own terms.

Four specimens, three isolating one row each and one carrying the pair:

    scala/offside-braceless.scala        6 claims   row 0  _indent/.offside/.slashes
    scala/nested-comment.scala           3 claims   row 4  block_comment/.marrow/.kotlin_block
    scala/offside-through-comment.scala  6 claims   rows 0 and 4
    ocaml/nested-comment.ml              3 claims   row 5  comment/.marrow/.ocaml_comment

Scored against the pair arms, they flip on the right row and only the right row:

                                  both in  r0 out  r4 out  both out
    offside-braceless.scala           6/6     0/6     6/6       0/6
    nested-comment.scala              3/3     3/3     0/3       0/3
    offside-through-comment.scala     6/6     2/6     0/6       0/6
    ocaml/nested-comment.ml           3/3         0/3 (aud-r5)

The two singles are orthogonal on purpose — `offside-braceless` carries no
comment, and `nested-comment` claims nothing about roots, because un-seating the
offside row shreds that file's root count while leaving `block_comment [10, 27)`
standing. A red is attributable to one seating rather than to "scala got worse".
`witnessed.py` over the whole family now reads **14 witnessed**, from 11/3/0.

All three comment specimens are the nesting case. A reader with no depth counter
closes at the first inner terminator, byte 22 in both languages, and emits a node
of the *correct name* at the wrong extent — only `spans` separates them, so every
extent here is read off the source text and never off a parser. And neither
un-seated arm produces a short comment: scala's body comes back as one
`infix_expression [10, 27)`, ocaml's as `mult_operator` at 11, 16 and 25 with a
`value_path` between them and the first `let` losing its `value_definition`. Both
are stated as `lacks` claims, so the specimen fails on the wrong tree and not
merely on the missing one.

Then the reason all three read negative. Scala's two were subtracted from a
control carrying a press regression, and clean they are +7,763 and +2,407 on
`damage`, +6,739 and +6,536 on `square`. Ocaml's control was never poisoned —
2,182 on the retained snapshot and 2,182 on today's board, to the byte — so its
−721 is a real number about a real parse:

    row 5 in    built 14,696   damage 2,182   orphan 1,829   square 12,165
    row 5 out   built 15,417   damage 1,461   orphan     0   square 11,717

Un-seating makes `built` go **up** by 721 and `damage` go **down** by 721,
because 1,829 bytes of correctly-recognised comment are an extra and land in
`orphan`, while the same bytes misread as operators are structure and land in
`built`. On `damage` the broken parse wins by 721. On `square` the seated row is
worth +448 and tree-sitter is the one saying so.

So a row can be corpus-only, negative-worth and correct, and the two instruments
that would have told you were a specimen nobody had written and an oracle column
nobody had filled in. `specimen.py verify` still holds 6/6 with these in,
including the assertion that a hand regression reddens a green specimen.

# Result 7 — the three unwatched rows now have falsifiers, and all three were being libelled

`witnessed.py` found 11 of 14 seated rows witnessed by a specimen, 0
unwitnessed, and **3 corpus-only** — and those three were exactly the three whose
measured worth was negative. A row only the corpus board can see, which the
corpus board says does harm, is the row most in need of something that can say
no on its own terms.

Four specimens were written. Three isolate one row each; the fourth is the pair.

| specimen | claims | isolates |
|---|---|---|
| `scala/offside-braceless.scala` | 6 | row 0 `_indent/.offside/.slashes` |
| `scala/nested-comment.scala` | 3 | row 4 `block_comment/.marrow/.kotlin_block` |
| `scala/offside-through-comment.scala` | 6 | rows 0 **and** 4 |
| `ocaml/nested-comment.ml` | 3 | row 5 `comment/.marrow/.ocaml_comment` |

## They flip, and they flip on the right row

Scored against the pair arms from `retake.py` and, for ocaml, against the
retained `aud-r5`:

| specimen | both in | row 0 out | row 4 out | both out |
|---|---|---|---|---|
| `offside-braceless.scala` | 6/6 | **0/6** | 6/6 | 0/6 |
| `nested-comment.scala` | 3/3 | 3/3 | **0/3** | 0/3 |
| `offside-through-comment.scala` | 6/6 | **2/6** | **0/6** | 0/6 |

| specimen | row 5 in | row 5 out |
|---|---|---|
| `ocaml/nested-comment.ml` | 3/3 | **0/3** |

The two single-row scala specimens are **orthogonal**: each survives the other
row's removal intact, so a red is attributable to one seating and not to "scala
got worse". That is deliberate — `offside-braceless.scala` carries no comment,
and `nested-comment.scala` claims nothing about roots, because un-seating the
offside row shreds that file's root count while leaving `block_comment [10, 27)`
standing.

`witnessed.py` re-run over the whole family now reads:

```
  14 witnessed
```

0 corpus-only, 0 unwitnessed, from 11 / 3 / 0.

## What each one establishes

**A depth counter, not a regex.** All three comment specimens are the nesting
case — `/* x /* y */ z */` and `(* x (* y *) z *)`. A reader with no depth state
closes at the first inner terminator, byte 22 in both, and emits a node of the
*correct name* at the wrong extent. Only `spans` separates them, which is why
every extent here is read off the source text and never off a parser.

**A confidently wrong shape, not an absence.** Neither un-seated arm produces a
short comment. Scala's body comes back as one `infix_expression [10, 27)` over
`operator_identifier` runs; ocaml's comes back as `mult_operator` at 11, 16 and
25 with a `value_path` between them, and the first `let` loses its
`value_definition` entirely. Both are stated as `lacks` claims, so the specimen
fails on the wrong tree rather than merely on the missing one.

**Offside without braces.** `object A:` followed by two indented members has to
produce `template_body [8, 33)` with no `{` anywhere; un-seated it produces no
`object_definition` at all, just loose `identifier` and `assignment_expression`
leaves. The extent is the whole claim, because the token that closes the body is
invisible.

**And one mechanical coupling.** `offside-through-comment.scala` is 42 bytes
holding a block comment inside an indentation region, and it fails under either
row alone. This is the falsifier `RESULT-6-scala.md` needed: the corpus residual
that was read as "two rows working the same region" was priced off a poisoned
control and a 20 KB fixture whose layout the brief warns against trusting. Forty-
two bytes cannot be a layout artifact.

## All three negative worths were wrong, for two different reasons

This is the part worth carrying forward. The three rows the board said were
harmful:

| row | grammar | board worth (`damage`) | why it read negative | clean worth |
|---|---|---|---|---|
| 0 | scala | −4,970 | poisoned control (`RESULT-6`) | **+7,763** damage · **+6,739** square |
| 4 | scala | −10,326 | poisoned control (`RESULT-6`) | **+2,407** damage · **+6,536** square |
| 5 | ocaml | −721 | `damage` prefers a wrong-but-large tree | **−721** damage · **+448** square |

The two scala rows were subtracted from a control carrying a 12,733-byte press
regression; their arm damages were correct all along. The ocaml row is the
interesting one, because its control was never poisoned — 2,182 on the retained
snapshot and 2,182 on today's clean board, to the byte — so its −721 is a real
number about a real parse:

```
row 5 in    built 14,696   damage 2,182   orphan 1,829   square 12,165
row 5 out   built 15,417   damage 1,461   orphan     0   square 11,717
```

Un-seating the row makes `built` go **up** by 721 and `damage` go **down** by
721, because 1,829 bytes of correctly-recognised comment are an *extra* and land
in `orphan`, while the same bytes misread as `mult_operator`/`value_path` are
structure and land in `built`. On `damage` the broken parse wins. On `square` —
the only column that is a claim about a second parser — the seated row is worth
**+448**, and tree-sitter is the one saying so.

So a row can be corpus-only, negative-worth, and correct, and the two
instruments that would have told you were a specimen nobody had written and an
oracle column nobody had filled in. Both are now present for all three.

## What this does not establish

`corpus-only` was never a clearance and `witnessed` is not one either: a
specimen exists where somebody wrote one, so `14 witnessed` is a floor on the
tier's reach and not a statement about the other rows' quality. Four new
specimens is four constructs, chosen because the brief named the rows; the
remaining silence in this tier is still silence. `specimen.py verify` holds
6/6 with these in, including the assertion that a hand regression reddens a green
specimen, so the tier can still say no.

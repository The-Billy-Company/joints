# Result 1 — the coverage gate, and the instrument it caught being me

Eight predictions in `PREDICTION-1-coverage.md`. **Three failed**, and one of the
three is the finding this lane will be remembered for, because it was mine.

| | prediction | verdict |
|---|---|---|
| P1 | no grammar exercises all its seated externals | **failed** — ocaml does |
| P2 | fewer than half of seated externals are exercised | held, wrong mechanism |
| P3 | Swift's `multiline_comment` is blind | held |
| P4 | Julia's interiors are seated, specimens green on arrival | **failed** |
| P5 | every Kotlin string specimen is red today | held |
| P6 | the greedy specimen distinguishes a first-match reader | held |
| P7 | yaml is the worst grammar the gate reports | **failed** — markdown is |
| P8 | the gate refuses to score a zero-external grammar | held |

## The gate

```
declared 461  seated 252 (55% of declared)
of those seated, 216 are hidden and cannot be witnessed at all;
of the 36 that can be, 21 are exercised (58%)
23 scorable grammar(s), 7 n/a
```

Four populations per grammar. **declared** is a field in `grammar.json`.
**blind** is what outliner says it has no stand-in for. **seated** is the
difference — *this tree can make that token*. **exercised** is a seated
external some file here actually reaches.

## The twenty-second instrument was my own coverage count

I said in the brief's own words that the instrument I would trust least is the
one I was building. It lied on the first run, in the most alarming direction
available, and it took reading a forest to catch it.

`outliner grammar` closes with

```
note: external scanner tokens cannot be lexed here: _block_comment_rest
_immediate_paren _immediate_bracket ... +8 more
```

which reads exactly like the blind set and is not it. On julia that note names
**all sixteen** declared externals. `outliner lex` on the same grammar reports
**five**, and names them — the `_immediate_*` family — and `parse` agrees. The
note is a restatement of `externals[]` wearing a blindness sentence.

The first gate read that note and reported:

```
declared 461  seated 0
```

**Seated zero, for all twenty-three scorable grammars.** A headline saying this
tree cannot lex a single one of the 461 externals it declares, which is false by
a factor of infinity and would have been repeated by every report downstream of
it. It was caught because Julia's `command.jl` specimen passes 6/6, and a
grammar that can lex nothing cannot pass a specimen. The number lost an argument
with a tree, which is the only reason it lost at all.

A second, smaller lie in the same instrument: the row pattern reading
`parse --ranges --all` did not allow for a `field: ` prefix, so on Swift — which
labels most of a property declaration — it read a forest containing
`value: line_string_literal [18, 32)` and reported the literal **absent**. Swift
went from 0/6 specimens sound to 2/6 on that one-line fix. Both lies were in the
under-reporting direction, and both would have read as findings.

## P1 failed — ocaml exercises everything it can

ocaml declares 6, seats 1, exercises 1, hides none. It is the only grammar in
the tree whose seated set is fully reached, which makes it the counterexample to
the claim that nothing here is covered. It is also a thin victory: five of its
six externals are blind, including both quoted-string delimiters.

## P4 failed, and it is the most useful failure

The brief describes Julia as "seated today and stateless", a regression floor
rather than an unblock. Three of five Julia specimens are red, and the wall is
not the string interior at all:

```
unexpected ( at 12 in state 290 ... [no stand-in for _immediate_paren]
```

Julia's **interiors are seated and work**: `command.jl` passes whole, and
`triple-quote.jl` — `"""x "q" y"""` — parses to a single root with the literal
at exactly [4, 17). What is blind is the **immediacy family**:
`_immediate_paren`, `_immediate_bracket`, `_immediate_brace`,
`_immediate_string_start`, `_immediate_command_start`. Five zero-width markers
that say *this bracket is glued to the token before it*.

The cost is not small and it is invisible today:

- `s = "a $(n + 1) b"` — the **parenthesised** interpolation form — does not
  parse at all. 8 roots, 3 mends, no `string_literal` node anywhere.
- `s = raw"a\b"` — any prefixed literal — does not parse. No
  `prefixed_string_literal` node.
- `"$("$n")"` builds the **inner** string at [13, 17) and never the outer, which
  is the textbook stateless close written out by a hand that is not stateless —
  it simply never got to start.

And `set.jl`, the 27,360-byte Julia corpus file, contains **zero** `$(` and
**zero** `raw"`. Four bare `$ident` interpolations, which are the one form that
works. The corpus is silent about both broken constructs, exactly as the brief
predicted of Kotlin and Swift.

This belongs to the lane holding zero-width work in `outside.zig`/`step`. It is
handed over with the three specimens that prove it, not fixed here.

## P7 failed — markdown, not yaml

I reasoned from a count and got what six lanes before me got.

**yaml declares 113 externals and seats all 113** — the best-seated grammar in
the tree. 112 of them are hidden, so `exercised` sees one, but capability is
whole.

**markdown declares 47 and seats none.** Every `_list_marker_*`, every
`atx_h*_marker`, both `setext_*_underline`, `block_continuation`, the fenced
code delimiters, `_pipe_table_start` — all blind. latex (12), php (12) and sql
(3) are also at zero. Those four grammars are where a coverage question has the
most to say, and none of them is Kotlin or Swift.

## P2 held on its terms, for a reason I did not give

21 of 252 seated externals are exercised, 8%, well under half. But my argument
was corpus silence, and the dominant mechanism is **hiddenness**: 216 of the 252
are `_`-prefixed terminals that never become nodes, so observing a forest cannot
witness them however hard a file leans on them. On the population the
instrument can actually see, 21 of 36 — **58%** — are exercised, which is above
the half I predicted.

The gate now prints both, because a single ratio here is the "one number for two
facts" mistake this repo has caught twice already. Julia is the proof: 11 seated,
0 exercised, and every one of the 11 hidden. Read without the hidden column that
zero is a scandal; read with it, it is a blind spot in my instrument.

## Kotlin, which is what the lane was for

```
kotlin  declared 10  seated 2  exercised 1 of 1 visible  (1 hidden)
blind: _by_delegation_hint _import_dot _interpolation_expression_start
       _interpolation_identifier_start _primary_constructor_keyword
       _string_end _string_start string_content
```

Eight blind, and **five of the eight are the string**. Seated is
`_automatic_semicolon` and `multiline_comment`, nothing else. All six Kotlin
specimens are red, 1 claim of 29 holding.

The shape of the failure is the one the troupe contract in `outside.zig` calls
worse than an unanswered token. `val s = "a ${n + 1} b"` returns a
**`lambda_literal`** — the `${` reaches the ordinary lexer, which sees a brace
and builds a lambda over the interpolation. `lacks lambda_literal` in
`interpolation.kt.expect` is that sentence as an assertion.

This is the file the 20,728-byte fix was waiting for. It cannot be passed by a
stateless hand: `nested-interpolation.kt` requires remembering that the `"` at
byte 21 opens rather than closes, and `greedy-close.kt` requires closing
`"""a""""` at byte 16 rather than 15.

## Swift, and a clean verdict over a wrong tree

Swift seats 21 of 33 — not 0, as the wrong reporter claimed. Ordinary
interpolation works, including nested: `interpolation.swift` and
`nested-interpolation.swift` both pass whole. What is blind is
`multiline_comment`, the three `raw_str_*` parts, the custom operators and the
`_directive_*` family.

P3 held, and the mechanism is worse than orphaning. `/* c\n   d */` gives:

```
prefix_expression [10, 14)
  operation: custom_operator [10, 12)     <- the `/*`
  target: simple_identifier [13, 14)      <- the `c`
multiplicative_expression [18, 22)
  lhs: simple_identifier [18, 19)         <- the `d`
  op: "*" [20, 21)
  rhs: "/" [21, 22)                       <- the `*/`
```

**One root, zero mends, and the comment is arithmetic.** The bytes are not
orphaned — they are *claimed*, so `covered` counts them as read and every byte
measurement this repository takes calls this file perfect. The lane that handed
over 3,997 orphan bytes was measuring the part of the damage that shows.

`nested-comment.swift` goes further: Swift block comments nest, so
`/* x /* y */ z */` needs a depth counter, and a first-`*/` reader stops at byte
21 with `z */` left over. Neither specimen can be satisfied without the hand.

`swift/raw-string.swift` carries the assertion no byte count can express:
inside `#"..."#` the interpolation sigil widens to `\#(`, so the `\(n)` in the
body is six literal bytes, and `lacks raw_str_interpolation` fails a hand that
reuses the ordinary interior. Right node, wrong place, full marks on the board.

## What was proven rather than argued

`specimen.py verify` — five assertions, three of which exist to show a predicate
can still say no:

```
ok  specimens are outside the corpus (31 board file(s) checked)
ok  a claim can fail (1 held, 1 failed - want 1 and 1)
ok  spans distinguishes extent (exact True, off-by-one False - want True and False)
ok  zero-external grammars are unscorable (7 found, 0 wrongly scored)
ok  a hand regression reddens a green specimen (6 of 6 claim(s) stopped holding)
```

The last one is performed, not asserted. `_end_cmd` is renamed in a scratch copy
of julia.json, which unseats the command troupe — `seated` in `outside.zig`
requires a cast's full membership — and `command.jl` goes from 6/6 to 0/6. That
is a real hand ceasing to answer, and the tier notices.

Every one of the 17 specimens was watched failing before it was trusted. Four
are green now (`julia/command.jl`, `julia/triple-quote.jl`,
`swift/interpolation.swift`, `swift/nested-interpolation.swift`) and each was
red at some point during authoring — two of them for a defect in my row pattern
rather than in the parser, which is why they are worth having.

## Two things I got wrong that are not in the predictions

**Rename ablation is unsound as a coverage oracle**, and I spent real time
believing otherwise. Renaming one blind Kotlin external — a single character,
`_by_delegation_hint` to `_by_delegation_hinT` — took the blind count from 8 to
**10**. `provision` requires a troupe's full cast, so losing any one member
unseats every other member with it, and a rename ablation therefore reports
every part of a seated troupe as load-bearing whether it is or not. It is
recorded in `enumerate_blind`'s docstring as the thing not to do, and used in
`verify` for the one job it is honest at: deliberately breaking a hand.

**A blind external does not imply a broken construct.** The press keeps an
ordinary token for any spelling it can lex, which is why Swift's line strings
parse whole with 33 externals blind. `seated` is therefore a floor on capability
as well as a ceiling on it, and only a specimen settles a given construct. The
gate prints that caveat on every run.

## The instrument I still trust least

`exercised`, and not for the reason I expected. The hidden-terminal blind spot
is now named per row, so it cannot be read as a finding — but it means the
instrument can only ever witness 36 of 252 seated externals, 14%. For the other
216 the honest answer is that this gate does not know, and no amount of specimen
writing changes that. Witnessing a hidden terminal needs the parse to report the
tokens it consumed, and the `lex` lens advertised in `outliner`'s own usage
banner — `OUTLINER_TRACE=press,lex,joint,weave,folio` — emits nothing today; no
code under `src/kernel/lex/` writes a trace. That is the cheapest available
route to turning 14% into 100%, and it is one lens, not a rewrite.

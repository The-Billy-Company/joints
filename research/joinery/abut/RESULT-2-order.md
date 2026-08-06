# Result 2 — the abut hand, and the census that was right about the table and wrong about the file

Measured 2026-08-05 against `PREDICTION-2-order.md`. Five predictions, three
held, **two failed**, and the two that failed are the useful ones.

## P5 — FAILED. Placing the hand first did not break julia

The census said it would. By **shift**, no `_immediate_*` is ever co-admitted
with any `_content_*` or either close — 28 pairs of `shift 0`, a wall that reads
as a clearance. In the **set** column, which is the one a hand reads, every one
of them is co-admitted in state 1, the state where 103 terminals fold
`identifier -> _word_identifier`. And `_immediate_string_start` and `_end_str`
are keyed to the same byte, `"`.

So the hand was placed last, below the caesura, and then the prediction was
measured anyway by placing it *first* and running the board. Julia's standing did
not move by a byte. Nor did any probe written to provoke it.

The reason is the `wanted` test inside the hand, not the phase: the parser never
stands in state 1 at a quote in this corpus, so the marker is never in the
permission set where the collision would happen. **The census was right about the
table and told me nothing about the file.** A co-admission in the set column is a
statement that a table *permits* both, and permission is not arrival.

The hand stayed last regardless, because that is the rule this file already
applies — a hand that moves nothing outranks nothing, the same rule that ranks
the caesura last — and because a defence against a table shape that exists is
worth its two lines even when the corpus does not walk into it. The comment above
`glued` now says which of those is carrying julia today, which is neither.

## P6 — held. Julia rises with the hand seated last

See P8 for the size.

## P7 — FAILED as stated, in the direction that says the guard is unmeasured

The falsifier was "removing it and seeing any measurement move". Removed, the
board is identical on all thirty grammars. So the `at > 0` veto fires nowhere in
this corpus and is a field guard rather than a measured one — exactly what the
prediction said, which means the prediction's own falsifier could never have
fired and it was not a prediction. Recorded as a failure of the test, not of the
guard: a file whose first byte is `(` still has nothing for the paren to be glued
to, and `fresh` is vacuously true at offset 0.

The same is true of the open-span veto, and that one is already labelled in the
source as an invariant stated for the next language rather than a measured guard.
The `at > 0` line deserved the same label and now has it.

## P8 — held, by 33 points against a predicted 5

| julia | before | after |
|---|---|---|
| standing | 59.6% | **92.9%** |
| covered | 80.3% | 99.2% |
| built | 16,313 | 25,407 |
| strewn | 5,647 | 1,724 |
| rubble | 3,512 | 12 |
| spoil | 5,400 | 229 |
| unbound | 8,912 | **241** |
| roots | 1,591 | 138 |
| bare leaves | 897 | **30** |
| blind terminals | 5 | **0** |

Bare leaves fell 867 and the board's `describes` rose 2,445 nodes (95,150 ->
97,595), so this is not a policy reading less: fewer roots with *more* nodes
described is a tree getting deeper, and `covered` rose alongside `built` rather
than trading against it.

Board: 67.4% -> **69.1%** standing, unbound 115,139 -> 106,468, orphan 56,766 ->
56,343. Julia is the only grammar in the delta.

Julia's wall moved from `lexer` to `press`: it now stops at
`_delimiter_str_1 in state 136 (0 dropped, 14 misfolded)`, a merge-damaged term
rather than a token nobody can lex. 241 unbound bytes is what is left.

## P9 — held. 29 of 30 tree-identical, julia the thirtieth

Compared as trees, per the control the last lane set. `outliner parse`'s stdout
hashed per grammar; the verdict line kept out of the hash and reported beside it,
because a verdict moves for reasons a tree does not and item 2 changes one of
those on purpose.

## What the five markers are

Read off `upstream/grammars/julia.json` rather than guessed:

| terminal | rule | byte |
|---|---|---|
| `_immediate_paren` | `call_expression = _primary _immediate_paren tuple_expression` | `(` |
| `_immediate_bracket` | `index_expression = _primary _immediate_bracket _array` | `[` |
| `_immediate_brace` | `parametrized_type_expression = _primary _immediate_brace curly_expression` | `{` |
| `_immediate_string_start` | `prefixed_string_literal = identifier _immediate_string_start …` | `"` |
| `_immediate_command_start` | `prefixed_command_literal = identifier _immediate_command_start …` | `` ` `` |

Each is a zero-width marker between the previous token and a delimiter,
asserting the delimiter is glued on. `f(x)` is a call and `f (x)` is not, and
the only difference is whitespace the marker refuses to step over. The hand is
`fresh` plus one byte test, and it reads `wanted` rather than `named` because
`_immediate_paren` is a shift in 20 states and a reduce-lookahead in 239 — which
is item 2's finding arriving inside item 1.

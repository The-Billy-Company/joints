# Prediction 2 — where the abut hand has to stand, and what happens if it stands first

Written before the hand exists, from the census in `census-cross.txt`.

## What the five mean

From `upstream/grammars/julia.json`, not from a guess:

| terminal | rule | byte that must be touching |
|---|---|---|
| `_immediate_paren` | `call_expression = _primary _immediate_paren tuple_expression` | `(` |
| `_immediate_bracket` | `index_expression = _primary _immediate_bracket _array` | `[` |
| `_immediate_brace` | `parametrized_type_expression = _primary _immediate_brace curly_expression` | `{` |
| `_immediate_string_start` | `prefixed_string_literal = identifier _immediate_string_start …` | `"` |
| `_immediate_command_start` | `prefixed_command_literal = identifier _immediate_command_start …` | `` ` `` |

Each is a zero-width marker sitting *between* the previous token and a
delimiter, asserting the delimiter is glued on. `f(x)` is a call and `f (x)` is
not, and the only difference is whitespace the marker refuses to step over. So
the hand is `fresh` — outliner's `fresh` is exactly "no extra was stepped over
since the last token ended" — plus one byte test.

## The census contradiction

The obvious seating is a new phase near the front, since the answer is cheap and
consumes nothing. The census says that is unsound, and says it in the column the
last lane had to learn to read:

```
_immediate_string_start    _end_str          shift 0     set 1  (first set: state 1)
_immediate_string_start    _content_str_1    shift 0     set 1  (first set: state 1)
_immediate_paren           _content_str_1    shift 0     set 1  (first set: state 1)
```

By **shift**, no `_immediate_*` is ever co-admitted with any `_content_*` or
either close — a wall of `shift 0` that reads as a clearance. In the **set**
column, which is what a hand actually reads, every one of them is co-admitted
with every interior terminal, in state 1: the state where 103 terminals fold
`identifier -> _word_identifier`.

`_immediate_string_start` and `_end_str` are keyed to the **same byte**, `"`.

**P5.** An abut hand placed ahead of the marrow phase answers
`_immediate_string_start` over the closing quote of julia strings, and julia's
standing **falls** from the 59.6% the last lane left it at.

Falsified by: seating abut first and measuring julia standing at or above 59.6%.

**P6.** Placed last — below `caesura`, which is currently the bottom — it never
sees those offsets, because the marrow hand answers `_end_str` before the ask
reaches it.

Falsified by: julia standing failing to rise with the hand seated last.

## Three vetoes, each with a reason rather than a hedge

- **`fresh`**, or the marker means nothing: it *is* the adjacency claim.
- **`at > 0`**, because a file whose first byte is `(` has nothing for the
  paren to be glued to, and `fresh` is vacuously true at offset 0.
- **no open span**, stated rather than left to phase order, because phase order
  is a property of a file someone will edit and this is a property of the
  construct.

**P7.** The `at > 0` veto never fires on the corpus, because no corpus file
starts with one of the five bytes. It is there for the field.

Falsified by: removing it and seeing any measurement move.

## Magnitude

`set.jl` is 27,360 bytes of Julia and Julia writes calls constantly, so almost
every `f(` in the file is currently a wall. `_immediate_paren` shifts in 20
states, `_immediate_bracket` and `_immediate_brace` in 14 each — small numbers,
but the construct they gate is the commonest one in the language.

**P8.** Julia standing rises by at least 5 points from 59.6%.

Falsified by: a rise under 5 points.

**P9.** No other grammar declares an `_immediate_*` cohort, and the ledger is
strictly stronger than the pin, so **twenty-nine of thirty are tree-identical**
and the thirtieth is julia.

Falsified by: any non-julia grammar's tree changing.

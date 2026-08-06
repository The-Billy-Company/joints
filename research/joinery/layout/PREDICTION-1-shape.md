# Prediction 1 — which organ each language wants, written before building

Two languages were handed to this lane as "probably the same shape: layout
driven by a stack." Both have a stack. I predict they are **not** the same
shape, and that neither is haskell's.

The axis is the one `CLASSIFICATION.md` established and I am not re-inventing:
**what does `serialize` write**, and *who decides when the stack moves*.

## The prediction

**Scala is python's shape** — `offside`, not `writ`. Its scanner *measures* a
line's leading width and compares it against a stack it owns, and the
comparison is the token (`INDENT` / `OUTDENT`). The parser's only part is
permission (`valid_symbols[INDENT]`), which is exactly how
tree-sitter-python's scanner is gated too. So scala can ride
`offside.Columns` with a rule of its own, and does **not** want haskell's
commanded push.

**Yaml is a third shape, and no organ in this tree hosts it.** Its scanner
keeps a *paired typed* stack — an indent kind (`root`/`map`/`seq`/`str`)
beside an indent width — and the standing of a line against that stack is
**not a token at all**. It is a *prefix on every other token's name*: the same
byte `[` is `_r_flw_seq_bgn` on the same line, `_br_flw_seq_bgn` on a deeper
line, and `_b_flw_seq_bgn` on a level one. Layout here is a **dimension of the
terminal alphabet**, not a member of it.

## What would falsify each

- **Scala is `writ`, not `offside`** if `INDENT` is ever emitted with no
  measurement behind it — a push granted on the parser's say-so alone, the way
  haskell's `_cmd_layout_start_do` is. Read the push site: if the guard is
  `valid_symbols[INDENT]` *and nothing about a column*, I am wrong.
- **Yaml is `offside`** if the grammar declares an indent/dedent terminal pair,
  or if the `_r_`/`_br_`/`_b_` triple turns out to be about something other
  than the line's standing against the stack top.
- **They are the same shape** if scala's stack entries and yaml's carry the
  same information. Scala's are a width plus one flag bit; yaml's are a width
  plus a *kind* that changes which token may be emitted at all.

## Why the difference decides the work rather than decorating it

If yaml's standing is a prefix rather than a token, then a hand cannot answer
"is a dedent owed here" and hand back one symbol. It has to answer *every*
terminal in the language through a layout-indexed table — which is a new organ
with a table 113 rows wide, not a `Tongue` on an existing one. That is the
difference between a table row and a lane, and it is the thing to establish
before writing either.

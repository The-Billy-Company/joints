# Prediction 2 — how to derive the mechanism, not hand-list it

The deliverable asks for all 33 swift externals (and kotlin's 10, scala's 31)
split into **carried state** versus **context-sensitive pattern over bytes**,
*derived* rather than hand-listed. So the first thing to state is what the
derivation reads.

## The signal I predict exists

Tree-sitter grammars that route a token through the external scanner purely to
*disambiguate* it almost always still say what it is spelled as, because the tree
has to show the user a `=` and not a `_eq_custom`. The DSL's way of saying that is
`ALIAS`:

```json
{"type":"ALIAS","value":"=","named":false,
 "content":{"type":"SYMBOL","name":"_eq_custom"}}
```

**Prediction:** for a large majority of swift's `*_custom` / `*_keyword` /
`_explicit_semi` externals, the grammar itself carries the spelling in an
`ALIAS` wrapper over the `SYMBOL`. If so, the spelling is not ours to invent —
it is read out of `grammar.json`, which is the fidelity contract satisfied
exactly, and the strongest possible answer to "derived rather than hand-listed."

Concretely I predict aliases for: `_explicit_semi` → `;`, `_eq_custom` → `=`,
`_dot_custom` → `.`, `_eq_eq_custom` → `==`, `_arrow_operator_custom` → `->`,
`_conjunction_operator_custom` → `&&`, `_disjunction_operator_custom` → `||`,
`_nil_coalescing_operator_custom` → `??`, `_bang_custom` → `!`,
`_as_custom` → `as`, `_as_quest_custom` → `as?`, `_as_bang_custom` → `as!`,
`_throws_keyword` → `throws`, `_rethrows_keyword` → `rethrows`,
`_async_keyword_custom` → `async`, `_hash_symbol_custom` → `#`.

And I predict **no** alias for: `multiline_comment`, `raw_str_part`,
`raw_str_continuing_indicator`, `raw_str_end_part` (delimiter memory),
`_implicit_semi` (zero-width — there are no bytes to alias),
`_custom_operator` (an open pattern, not one spelling), and the four
`_directive_*` (they are `#if`/`#elseif`/`#else`/`#endif` and may well be
aliased, so this is the branch I am least sure of).

If the aliases are absent, the derivation has to fall back to something weaker
and I will say so rather than hand-listing.

## The three mechanism classes I expect to need

Not two. The brief's split — carried state vs context-sensitive pattern — leaves
out the class `_implicit_semi` is actually in:

1. **Spelled** — the bytes are a fixed string the grammar itself names. A
   `Provision` row can answer it, possibly with trailing context. Cost: nothing
   carried.
2. **Zero-width** — the terminal occupies no bytes, so a pattern *cannot*
   answer it (the slate must refuse an empty match; only a hand may answer
   zero-width, because only a hand can prove progress). Needs a `Troupe`.
   `_implicit_semi` and scala's `_indent`/`_outdent` are here.
3. **Carried state** — the end of the token is a function of bytes the scanner
   saw earlier. Needs a hand *with a memory*. swift's `raw_str_*` triple, and
   scala's eleven string middles/ends.

Class 1 and 2 are both "context-sensitive pattern over bytes" in the brief's
vocabulary, but they need different seams, so collapsing them would produce a
plan that cannot be built.

## Prediction 3 — the co-admission population

The haskell lane licensed its late-answering design by measuring whether its
`_cmd_*` orders were the only shiftable terminal in the states that admit them
(they were, in 51 of 56). The analogous question for `_implicit_semi` is:

**In the states that admit `_implicit_semi`, what else is shiftable?**

I predict the answer is *the opposite* of haskell's, and that this is the whole
difference between the two: an implicit semicolon lives at a statement boundary,
and a statement boundary is exactly where a great many terminals are legal —
every token that can start the next statement. So I predict `_implicit_semi`
shares its states with **many** rivals, typically tens.

If that is right, a `caesura`-style hand that answers *early* from bytes is
sound and a `writ`-style hand that answers *late, only after the slate came up
empty*, is **not available** — because the slate will nearly always produce a
token at a statement boundary (the first token of the next statement), so a late
hand would never fire. This is the reverse of haskell and it is why swift cannot
simply reuse `writ`.

Falsifiable: count shiftable terminals per state admitting `_implicit_semi`. If
the median is ~1, I am wrong and `writ`'s late protocol transplants directly.

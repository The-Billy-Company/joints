# Prediction 1 — the `text` node is one un-lexable quote and the mend behind it

Written after reading the parse and the grammar, before authoring a single
witness and before touching `src/kernel/lex/`.

## What I think is happening

`upstream/sources/Str.php` is 67,845 bytes. `outliner parse --ranges --all`
prints exactly one node spanning `[26850, 67845)`:

```
name  [26835, 26847)
"("   [26847, 26848)
"\""  [26848, 26849)
program [26850, 67845)
  text  [26850, 67845)
```

The bytes at 26835 are `preg_replace("`. So the claim is:

1. The lexer takes the opening `"` of the **first real double-quoted string in
   the file** (every earlier `"` in the file is inside a `/** … */` comment).
2. Inside that string php wants `encapsed_string_chars`, which the grammar
   declares external. Nothing in `outside.zig` answers it, so no token exists
   and the walk stops on the `/` at 26849.
3. The mend puts the stack down. What is left to reduce the remaining 40,995
   bytes is `program: seq(optional(text), optional(seq(php_tag, repeat(statement))))`,
   and `text` is
   `repeat1(choice(token(prec(-1, /</)), token(prec(1, /[^\s<][^<]*/))))` —
   a loop that between the two branches matches **any** byte sequence.
   So `text` is not a wrong guess among several; it is the one production in
   php that can absorb an arbitrary tail, and it has a child, so `standing.py`
   scores all 40,995 bytes as `built`.

That last step is why php's `damage` is 8,699 while its `crooked` is an order
of magnitude larger. The column that was the work order all day is measuring
the 8,699 bytes php *failed* to cover and is silent about the 40,995 it covered
wrongly.

## The falsifier

Three, and each can kill it on its own.

- **Locality.** Take a copy of `Str.php` and replace the one string at 26848
  (`"/(.*)\s.*/"`) with a single-quoted string of the same length. If the claim
  is right the `text` node moves to the *next* double-quoted string and shrinks
  by exactly the distance between them. If it stays at 26850, the quote is not
  the cause.
- **Miniature.** A file of well under 100 bytes containing one
  `$x = f("a");` should reproduce a `text` node. If a 40-byte file parses
  clean, something about the size or the position of the failure matters and
  the diagnosis is wrong.
- **Innocence.** The same miniature with `'a'` instead of `"a"` must parse
  clean and build no `text`. If the single-quoted control is also broken, the
  defect is not the external at all — it is `string` or the call shape — and
  I would be about to fix the wrong thing.

## What would make this only half true

`standing.py` says php's stop is `unexpected / at 26849 in state 68`, and the
brief warns that a reported state is a location and not a diagnosis. If
`outliner state php.json --holding` says state 68 holds no item spelling
`encapsed_string_chars`, the byte is right and the state is a red herring — the
diagnosis survives, the number 68 does not, and I should say so rather than
quote it.

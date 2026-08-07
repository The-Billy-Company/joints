# Prediction 2 — the seam is a `marrow` roster and not a `fence`

Written after reading `upstream/grammars/companion/php/common/scanner.h`
(pinned, sha256 `b882662c…`) and before writing any Zig.

php declares twelve externals. The four this prediction is about are

```
encapsed_string_chars
encapsed_string_chars_after_variable
execution_string_chars
execution_string_chars_after_variable
```

all four served by one C function, `scan_encapsed_part_string(scanner, lexer,
is_after_variable, is_heredoc, is_execution_string)`.

## Prediction

**With `is_heredoc` false, that function reads no scanner memory at all.** Its
only inputs are the bytes at the cursor and the two booleans, and the two
booleans are not remembered from a previous token — they are *implied by which
terminal the parse state asked for*. That is the definition `marrow.zig`'s
header gives for a family: "the close is still not carried - it is just read
off the terminal rather than off the bytes".

So the seating should be one `Troupe` row of `kind = .marrow` with a four-part
`roster` and a new `marrow.Family`, in the shape elixir's twenty and julia's
eight already have. Not a `fence`: a fence exists because an opener captured
something a later token has to spend, and there is nothing here to spend.

**The two heredoc arms are a different animal and I will not seat them.** They
read `scanner->heredocs`, a stack of tags pushed by `heredoc_start` and popped
by `heredoc_end`. That is `fence`'s shape plus the deferral to a line boundary
that `lex/README.md` already names as "the next honest thing to grow", and
mixing it into this change would make the diff unjudgeable.

## The falsifier

Mechanical, on the pinned bytes:

- If any statement reachable from `scan_encapsed_part_string` with
  `is_heredoc == false` touches `scanner->heredocs`, `scanner->has_leading_whitespace`,
  or any other field of `Scanner`, the run is stateful and marrow is the wrong
  seam. I read the function as: the whole `scanner` use sits inside
  `if (is_heredoc && scanner->heredocs.size > 0)`. If that reading is wrong the
  prediction is dead.
- If seating these four requires a field on `marrow.Mark` that means something
  about a *previous token* rather than about this run's close, it is carried
  state wearing a table's clothes. I expect to need exactly one new field —
  `after`, whether this run resumes immediately behind a `variable_name`, which
  is what makes `[` and `->` ends rather than content — and it is a property of
  the terminal the state named, not of history.

## A second prediction, cheaper to check and more likely to be wrong

php's `scan()` asks `AFTER_VARIABLE` **before** the plain member, for both the
encapsed and the execution pair. `spelt` in `outside.zig` takes "the first the
state admits, in the specification's own table order", so that order is
load-bearing only if some LR state admits both members at once.

**I predict at least one state does**, because `encapsed_string_chars_after_variable`
follows a `variable_name` inside the same `_interpolated_string_body` repeat
that `encapsed_string_chars` sits in, and LALR merging has every reason to fold
those. Falsifiable directly:

```
joints state upstream/grammars/php.json --census \
  encapsed_string_chars encapsed_string_chars_after_variable
```

If no state admits both, the roster order is decorative here and I should say
so rather than let a reader think it was load-bearing.

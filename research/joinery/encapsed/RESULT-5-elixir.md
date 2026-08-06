# Result 5 — elixir is a break, not a span. Prediction 5 held.

Written after PREDICTION-5, which was written before I opened elixir's
scanner. The claim under test was the interrupting lane's: that if
`_newline_before_binary_operator` and `encapsed_string_chars` share a
mechanism, "that pair alone is 66,700 bytes and by far the biggest single thing
available."

**They do not, and the pair does not exist.**

## The derivation

Re-derived rather than taken from the gap list, per that lane's own warning.
Asking the pinned binary directly:

```
elixir: lexer? on alias in state 100 [no stand-in for
_newline_before_binary_operator]: a terminal the scanner cannot produce is a
DECLARED EXTRA, so it is in no action row at all
```

A declared extra, and the wall is `alias` — a different terminal from the one
that is missing, which is the fourth-of-eighteen case that lane flagged, and it
reproduces here.

The scanner settles it. `scan_newline` advances over the newline and the
whitespace behind it, calls `lexer->mark_end` there, and *then* looks at what
follows:

```c
  lexer->mark_end(lexer);
  if (lexer->lookahead == '#') { … NEWLINE_BEFORE_COMMENT … }
  if (lexer->lookahead == 'd' && valid_symbols[NEWLINE_BEFORE_DO]) { … }
  if (valid_symbols[NEWLINE_BEFORE_BINARY_OPERATOR]) { … }
```

The extent is fixed **before** the decision, and every branch after it is
lookahead. There is no delimiter, no close, and nothing computed from the
bytes ahead except a yes/no. php's walk is the opposite object: the whole
answer *is* a distance forward from the cursor.

So elixir's is a **`caesura`** — "a break the line demands and the file never
spells", decided on the parser's expected set — which is a seam this tree
already has, with three rows in it (ecma, swift, kotlin).

## Both anticipated counter-arguments, judged

PREDICTION-5 named two ways it could be wrong and both are worth reporting:

1. *"If it's a caesura the fix may be a row rather than a mechanism — which
   makes it cheap, not shared."* This is what happened. elixir's remaining
   blind terminals are `_newline_before_do`, `_newline_before_binary_operator`,
   `_newline_before_comment`, `_before_unary_op`, `_not_in` and
   `_quoted_atom_start` — six, of which the first three are one `scan_newline`
   and look like one caesura row. Cheap and shared are different findings and I
   am not reporting the first as the second.
2. *"If elixir's newline rule is walled by a `_quoted_content_*` member — which
   IS marrow and IS already seated — the two are connected after all."* They
   are not: elixir's twenty `_quoted_content_*` externals are already seated on
   `marrow/elixir_quoted`, which is why only six of its twenty-six are blind.
   This was the outcome I said I would most like to be wrong into, and it did
   not happen.

## What this costs the headline

The interrupting lane's 66,700-byte figure is a real sum of two lanes and
would be a fabrication as a claim about one change. php's 40,996 is php's;
elixir's 25,704 is a caesura row somebody should take, and it is still the
corpus's largest racked source. Two good pieces of work, not one.

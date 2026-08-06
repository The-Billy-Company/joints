# Prediction 5 — is elixir's 25,704 bytes the same fix as php's?

Written the moment the adjudication lane's result arrived and **before reading
one line of elixir's scanner or grammar**, because that is the only order in
which this prediction is worth anything. The lane's message:

> elixir `_newline_before_binary_operator` — 25,704 (two rows, **one fix**) …
> if `_newline_before_binary_operator` and php's `encapsed_string_chars` share
> a mechanism, that pair alone is 66,700 bytes and by far the biggest single
> thing available. Check it early.

## Prediction: they do not share a mechanism, and it is not close

**php's is a span and elixir's is a break.** From the names and from what this
tree already models:

- `encapsed_string_chars` is *content* — a run of bytes with width, bounded on
  both sides by marks the grammar spells for itself. That is `marrow`'s
  definition, and the whole of php's non-heredoc scanner is a walk forward from
  the cursor.
- `_newline_before_binary_operator` is a **zero-width decision about a line
  boundary**: "is the newline you are standing on a separator, or is it swallowed
  because the next line begins with an operator?" Nothing about it has an extent,
  a delimiter, or a close. `caesura.zig` is the file in this tree that already
  models exactly that shape — "a break the line demands and the file never
  spells" — and it decides on the parser's expected set, which is what an
  operator-continuation rule needs.

So my prediction is: **elixir's is a `caesura` and php's is a `marrow`, they
share the seam `outside.zig` and nothing below it, and the honest report is two
fixes and not one.** The 66,700-byte figure is real as a *sum of two lanes* and
would be a fabrication as a claim about one change.

## Why I might be wrong, stated in advance

The two arguments against me, both worth more than my prediction if they hold:

1. **`caesura` already exists, so if elixir's is a caesura the fix may be a row
   rather than a mechanism** — which would make it cheap, not shared. Cheap and
   shared are different findings and I must not report the first as the second.
2. The adjudication lane says each of these six is refused *because an external
   upstream was never produced*. If elixir's newline rule is walled by
   `_quoted_content_*` — which **is** marrow, and **is** already seated — then
   the two are connected after all, through elixir's string family rather than
   through its newline rule. That would be a genuine shared mechanism and it is
   the outcome I would most like to be wrong into.

## The falsifier

Mechanical and cheap:

- Read elixir's pinned scanner for `_newline_before_binary_operator`. If the
  answer has a **width greater than zero** and a **close computed from the
  bytes**, I am wrong and it is marrow.
- Ask `outliner state elixir.json --holding` for the wall elixir actually stops
  at, and re-derive the refused terminal rather than trusting the name in the
  table — the same lane says four of eighteen witnesses refuse a terminal the
  gap list does not name.
- If elixir's wall re-derives to a `_quoted_content_*` member, prediction 5 is
  dead and the shared-mechanism claim is live.

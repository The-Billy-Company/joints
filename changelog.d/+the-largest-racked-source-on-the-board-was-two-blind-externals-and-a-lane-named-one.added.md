elixir's `router.ex` was 44,530 built bytes with **one** of them square. The
whole `defmodule` frame was missing, 26,756 bytes agreed rung for rung under a
frame we never built, and the parse ended in 255 roots.

Two externals were blind, not one. `scan_newline` is a `caesura` — three
terminals from one function, chosen by a single peek after the mark, and the
opposite claim from an automatic semicolon: ecma's seam says a statement ended,
elixir's says it did **not** and the next line resumes it with a comment, a `do`,
or a binary operator. So the row has no `body` and carries three `seams`
instead; a break followed by none of the three is not a token here at all and
the extras eat it. It is also not zero-extent, which the handover had wrong —
`mark_end` comes after the newline *and* after the inline-whitespace loop, which
on this file is routinely 7 bytes.

Seating it moved the wall from 17,006 to 22,229 and left `square` at one byte.
Byte 22,229 is the `:` of `:"__match_route_#{verb}__"` — `_quoted_atom_start`,
which is not a hand at all: the C advances one byte, marks the end, and only
*looks* at the next, so it is a spelling plus trailing context and eleven lines
in `roll` beside ruby's `hash_key_symbol`. `router.ex` holds exactly two.

With both: **1 → 23,228 square, 26,756 → 0 unframed, 255 → 1 root, damage 1,559
→ 0, 96.6% → 100% standing** (frozen `seat3` oracle, 2026-08-06).

Where it goes the wrong way: racked went **up**, 17,654 → 22,724. Those bytes
are right leaves under a wrong parent — `defp f(x) do` hangs its `do_block`
inside `arguments` — and they rose because the file now builds a whole tree over
bytes that previously had no parent to be wrong about. Half of `router.ex` is
still shaped wrong and that defect is untouched; the specimen measuring it
(`do-block-on-inner-call.ex`) was 4/5 before and is 4/5 after.

The instrument that would have caught the second blind external before I
predicted a number is `specimen.py coverage`, which reports `declared` against
`seated` per grammar and now says elixir went `seated 20` to `seated 24`. I ran
it afterwards. Naming one blind external correctly is not knowing it is the only
one, and the prediction that elixir would clear 30,000 square died on exactly
that gap plus the racked class I under-priced.

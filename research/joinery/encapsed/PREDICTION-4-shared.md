# Prediction 4 — does one change move four grammars?

The brief asks the question the right way round: *"If one change moves four
grammars, that is the finding and it leads your report."* Six grammars were
named as having the same shape — a delimited span leaking into the token
stream — C, OCaml, Bash, LaTeX, PHP, Scala. Two are fixed (scala, ocaml), php
is mine, and C, Bash and LaTeX are open.

## Prediction: it moves one, and the shape is shared with exactly one of the
## three

**I predict the honest answer is "no", and that saying yes would be the
flattering number in my own work.** Written before I look at the other three,
from what the two files I have already read say:

- **C.** `src/kernel/lex/README.md` records that "c declares no external at
  all, so nothing lexical is missing" and files C's stop at byte 841 as *a table
  fact* — the LR collapse of a conflict tree-sitter keeps alive with GLR.
  A grammar with zero externals cannot have a leaking external. Prediction: C
  shares **nothing** with php's mechanism, and the change moves it zero bytes.
- **Bash.** The same README files bash's stop as `\n` declared as an *anonymous
  external* that the press drops, and separately names heredocs — a tag carried
  from an opener to a body on the next line — as unfinished. Both are carried
  state. Prediction: bash shares the *category* (a delimited span) and **not the
  mechanism**; it wants the heredoc half of php's scanner, which is precisely
  the half I am not seating.
- **LaTeX.** `marrow.zig`'s own `Family` header says latex "is the one still
  outstanding, spelling eleven `_trivia_raw_env_<name>` terminals whose close is
  `\end{<name>}`". One content terminal per delimiter, close read off the
  terminal the state named. Prediction: latex shares the **mechanism exactly** —
  it is a `Family` roster — and my change makes it a table entry rather than a
  new seam, but it is still a second change and not the same one.

So: **one change, one grammar moved, one grammar made cheaper.** If I write
"this change moves four grammars" at the end of the day, somebody should check
whether I widened a definition to get there.

## The falsifier

- If C's byte-841 stop turns out to be a `"` inside `printf(…)` whose content
  terminal is external after all, the README is wrong and so am I. Cheap to
  check: `joints parse` C and read the grammar's `externals`.
- If bash's remaining damage is dominated by something other than the heredoc
  stack, the "carried state" claim is wrong.
- If latex's eleven terminals need any memory — and `\end{name}` has to match
  the `\begin{name}` that opened it, which *sounds* carried — then latex is a
  fence and not a family, and marrow.zig's header has been wrong since it was
  written. That is the most likely of the three to fail, and it is the one I
  most want to be wrong about, because a wrong header is worth more than a
  right prediction.

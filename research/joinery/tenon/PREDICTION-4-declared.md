# Prediction 4 — a declared conflict is a fork, and this press cannot fork

Written after the elixir and go cells were found and **before** the corpus-wide
correlation below was run. Pin `tenon` (`4d7074db7346`, tree `fa7fcaee5e14`,
commit `f7ba40004+103`). Scored in `RESULT-2-declared.md`, unedited after that.

## What changed my mind mid-lane

PREDICTION-2 guessed the shared mechanism was `prec.dynamic` — a per-production
rank spent at table-build time where tree-sitter sums over subtrees. Reading
the tables says something narrower and much easier to falsify.

`src/surface/face/outliner/joints.zig` already writes the thesis down, as an
argument for *not* worrying:

> Contested and residual are different numbers and only the second is a defect:
> a cell the author declared ambiguous is a fork a GLR parser is **for**, and
> reporting the total as "unresolved" reads as a broken press on a grammar
> whose press is fine. Go is the case in point — 23 contested cells, every one
> declared, none residual.

Read the other way round, that is the defect. A `conflicts:` entry in a
tree-sitter grammar is not a hint about how to resolve an ambiguity; it is the
author telling the parser **not to resolve it** — to carry both readings and
let the input decide. Outliner is LALR. It cannot carry two. So every declared
cell is a fork collapsed to one action at press time, chosen by a fixed ladder
that never sees the input.

Under that reading `residual = 0` is not health. It is the press reporting that
it successfully answered every question it was asked not to answer.

## P10 — the guilty cell in each of go, python and elixir is `declared`

Not `residual`. The press will name each one as an ambiguity the grammar author
declared, and outliner's `joints` line will report zero or near-zero residual
conflicts for exactly the grammars that are misreading.

**Falsifier.** Any of the three guilty cells is residual (a conflict the author
never declared), or arises in a state whose row shows no contest at all.

## P11 — toml's 29 bytes are not a press decision, because toml has no decision

`outliner grammar upstream/grammars/toml.json` reports **0 declared conflicts**,
and `outliner joints` reports **0 contested cells over all 175 states**. If the
whole table is uncontested there was never a second derivation for the press to
prefer, so whatever `rack` is charging cannot be a wrong choice between two
readings. It is either a shape difference that follows deterministically from
the grammar (both parsers doing exactly what toml.json says, differently
because one hides a rule the other does not), or `rack` is wrong.

**Falsifier.** A contested cell exists in toml's table on the path this witness
takes; or the two trees differ in a way that required a choice.

## P12 — the grammars with no contested cell have no hard racked bytes

css, embedded-template, html, json, latex, lua and toml all report `0 contested
(0 declared, 0 residual)`. html is already known clean at 72,288 bytes and
13,971/13,971 brackets. If the class is what P10 says it is, none of these can
carry hard racked bytes beyond extras placement.

**Falsifier.** Any zero-contest grammar shows hard (non-soft) racked bytes in
`rack`'s own accounting.

## P13 — the count of declared conflicts does **not** rank the damage

The temptation, having found the mechanism, is to rank grammars by declared
count and call it a prediction of harm. It will not be one. verilog declares
181 and kotlin 50 and swift 40; elixir declares **6** and is the largest racked
source in the corpus. A declared conflict costs nothing until the corpus
contains the construct that reaches it, and the corpus is the weakest
instrument here.

**Falsifier.** `racked` bytes rank in the same order as declared-conflict
counts, or as contested-cell counts, across the adjudicable grammars.

## P14 — the four are not four defects, but they are not one defect either

I expect go, python and elixir to be **one** mechanism (a collapsed declared
fork) and toml to be a different thing entirely — an instrument or a grammar
shape, not a press choice. So the honest answer to "do the four share a
mechanism" is *three do*.

**Falsifier.** toml turns out to be a collapsed fork too, or one of the other
three turns out not to be.

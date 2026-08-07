# Prediction 1 — Tier A, how much of tree-sitter's field we can press

Written before a single grammar outside `upstream/grammars/` was pressed. What
I had read first: `README.md`, `tool/README.md`, `grammars.toml`'s header,
`tool/standing.py`'s docstring, `tool/rack.py`'s docstring, and the output shape
of `joints grammar` on five corpus grammars (json · scala · kotlin · swift ·
markdown · haskell) to fix the outcome vocabulary. Nothing off-corpus has been
fetched or pressed.

The roster is pinned before it is read:
`nvim-treesitter/nvim-treesitter@3d3321b560a63ff92a8692401f303a5123336b86`,
`lua/nvim-treesitter/parsers.lua`, sha256 `4a8f2aac6a74…a92403`, 73,900 bytes,
**323 parser entries**. That file is a third party's list, authored for a
different purpose, and I did not choose which languages are on it.

## The vocabulary, fixed before the sweep

`joints grammar <grammar.json>` is the press. Its report carries the four
facts an outcome is made of, and I am naming them now so no bucket can be
invented after the fact to make a number read better:

    RESIDUAL n         conflicts the resolver could not settle
    frayed  (n REFUSE) cells contested only by state merging, refusing a token
    terminals L literal, R regex, E external
    BARREN             referenced nonterminals that derive nothing

    clean      exit 0 · 0 RESIDUAL · 0 REFUSE
    refusing   exit 0 · 0 RESIDUAL · N REFUSE > 0
    residual   exit 0 · N RESIDUAL > 0
    barren     exit 0 · a BARREN line (reported alongside, not instead)
    unlexable  exit 0 · L + R == 0 — pressed, and cannot lex one byte
    refused    exit != 0, with the binary's own first line as the reason
    timeout    exceeded 120 s
    absent     no committed grammar.json at the pinned revision — counted
               separately, and never folded into a percentage of the field

`unlexable` is a separate bucket because yaml already proves the trap: it
presses to **0 RESIDUAL** with 113 external terminals, 0 literal, 0 regex, and
`joints parse` exits 2 with "no lexable terminal at all". A taxonomy that
called that `clean` would report the project's single hardest stop as a success.

## P1.1 — we press ≥ 85% of the grammars we can obtain, `clean` or better

Every corpus grammar presses. Thirty is in-sample, but the press is a general
LALR construction over a declarative table, not thirty special cases, and the
corpus already contains the field's worst shapes (cpp at 458 KB, scala with 192
RESIDUAL, markdown with a BARREN nonterminal).

Counting `clean + refusing + residual + barren` over the obtainable denominator.

**Falsifier:** below 85%. That would mean `refused` and `timeout` together
exceed one in seven, and the "any `grammar.json`" claim fails at the front door
rather than at the scanner — which is the *opposite* of the brief's thesis and
the more interesting result.

## P1.2 — `refused` is under 5% and `timeout` is under 3%

The press is a table construction; the pathological cost is state-count blowup
on a large ambiguous grammar. I expect a handful of enormous grammars (C#,
Julia-scale, generated SQL dialects) to be the whole of both buckets.

**Falsifier:** either bucket in double-digit percent.

## P1.3 — at least 25 are `unlexable`, and every one of them external-only

The corpus has exactly one (yaml). The field's markup and layout-sensitive
languages — the ones whose whole lexical structure lives in a C scanner — are
over-represented outside a corpus assembled from mainstream code.

**Falsifier:** fewer than 25 unlexable, or any unlexable grammar that declares a
literal or regex terminal (which would mean my rule is not measuring what I
think it measures).

## P1.4 — external seating, not table construction, is where the field stops

Concretely: across the obtainable field, the **median share of terminals that
are external is above 5%**, and the count of grammars with ≥ 1 external exceeds
the count of grammars with ≥ 1 RESIDUAL by more than 3×.

**Falsifier:** RESIDUAL grammars outnumber external-declaring grammars, or the
median external share is zero. Then the press, not the scanner, is the binding
constraint, and this project's entire work order is aimed at the wrong wall.

## P1.5 — between 15% and 40% of the roster ships no committed `grammar.json`

`grammar.json` is a build artifact many repos `.gitignore`; tree-sitter's own
newer template does not commit `src/`. I cannot press what I cannot obtain, and
a denominator I cannot see is worse than a small one, so this is counted and
named rather than dropped.

**Falsifier:** outside that band in either direction. Under 15% would mean the
ecosystem commits generated output far more uniformly than I expect; over 40%
would mean the "we take any `grammar.json`" claim is answering a question about
a minority of the field, and the honest headline needs the tree-sitter CLI in
the loop.

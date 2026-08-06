# Prediction 3 — what yaml's decline actually rests on

Yaml has been declined twice as "unrunnable externals". The brief tells me
that blanket is false — `provisionFor` requires a *row's own* cohort, never a
grammar's whole external list, and eight grammars already run partially
seated. So the decline has to be re-argued or overturned on yaml's own
evidence.

## The fact the previous declines did not have

```
outliner grammar upstream/grammars/yaml.json
  terminals      0 literal, 0 regex, 113 external
```

**Every terminal in the language is external.** Not a majority — all 113.
Bash's partial seating works because bash has a slate of ordinary tokens under
it and the three seated rows sit on top; yaml has no floor at all. This is
what `standing.py`'s docstring already records as `yaml lexes no terminal at
all, builds no tree, and scores 0`, and it is a *different* fact from
"unrunnable externals".

## Prediction 3a — partial seating has no floor to stand on here

I predict that the minimum cohort for even the **first three lines** of
`upstream/sources/ci.yml`

```yaml
---
name: CI
on:
```

is at least **8 distinct external terminals across at least 5 mechanisms**,
and that one of them is schema-classified — a terminal whose *name* depends on
a regex over the bytes it matched, not on where it sits.

**Falsifier and how it is measured:** walk the automaton with
`outliner state upstream/grammars/yaml.json <n>`, starting at 0, taking the
shift the next construct needs. If fewer than 8 distinct externals are
consumed before line 3 ends, the cohort is small and the decline is
overturnable cheaply, and I should just seat it.

## Prediction 3b — the plain scalar's name is not a fact about position

`_r_sgl_pln_nul_blk` · `_bol_` · `_int_` · `_flt_` · `_tms_` · `_str_` are six
terminals over **one** scan. The scanner picks among them with `SGL_PLN_SYM`,
a ladder over `scanner->rlt_sch` — a resolution the schema file computes from
the matched text. So `CI` is `_r_sgl_pln_str_blk` and `true` is
`_r_sgl_pln_bol_blk`, and no amount of parse-state permission separates them.

I predict this is the one mechanism in yaml that is genuinely *new* for this
lexer: everywhere else a terminal's identity comes from the grammar and the
state, and here it comes from a **classifier over the match**.

**Falsifier:** if the six variants are never co-admitted in one state — if the
grammar's own expected set already separates null from int — then the
classifier is redundant and the parse state does the work. Measure with
`outliner state`: find a state admitting `_r_sgl_pln_str_blk` by shift and
count how many of its five siblings it admits beside it. More than one and
the classifier is load-bearing.

## Prediction 3c — 113 is not 113 pieces of work

The `_r_` / `_br_` / `_b_` prefix is one function computed once per scan:

```c
bool has_nwl = scanner->cur_row > scanner->row;
bool is_r  = !has_nwl;                                 // same line
bool is_br = has_nwl && leading_spaces > cur_ind;      // deeper than the frame
bool is_b  = has_nwl && leading_spaces == cur_ind;     // level with it
```

so the 113 terminals are a small set of spellings crossed with a 3-valued
standing and a 6-valued schema. I predict the **distinct spellings number
under 32**, and that the honest price of yaml is "one new organ plus a table",
not "113 hand-written scanners".

**Falsifier:** count them off the scanner's own dispatch. If the distinct
spellings exceed 40, the cross-product story is wrong and 113 really is 113.

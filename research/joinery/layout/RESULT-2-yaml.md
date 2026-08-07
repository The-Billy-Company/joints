# Result 2 — yaml declined a third time, on its own scanner's evidence

The inherited reason was **"unrunnable externals"**, and the brief is right
that this is not a reason any more: `provisionFor` needs a row's own cohort,
never a grammar's whole declaration list, and eight grammars already run
partially seated. I did not accept that verdict. I re-derived one, and it comes
out the same way for three different reasons, none of which is the old one.

## Fact 1 — there is no floor for a partial seating to stand on

```
$ joints grammar upstream/grammars/yaml.json
  terminals      0 literal, 0 regex, 113 external
```

Every terminal in the language is external. Not a majority — all 113.

Bash's 3-of-4 works because bash's other terminals lex: the seated rows sit on
a slate that answers everywhere else. Yaml has no slate. And this is not an
argument about averages, because the entry state settles it:

```
$ joints state upstream/grammars/yaml.json 0
  shift 44, lookahead 0 — 44 terminal(s) accepted of 113
```

**44 shiftable terminals at state 0 and every one of them is external.** A
partial seating of yaml is not "most of a parse"; before the first byte there
is no subset of the 113 that lets the automaton leave state 0 for a general
document. Prediction 3a guessed "at least 8 across at least 5 mechanisms" for
the first three lines of `ci.yml` and named the walk that would check it. The
walk did not need three lines.

This is a different claim from "we cannot run C" and it is the one that
actually holds. It also predicts yaml's board row exactly: `standing.py`
already records that yaml lexes no terminal at all, builds no tree, and scores
zero.

## Fact 2 — a terminal's *name* is a classifier over the bytes it matched

Prediction 3b, confirmed, and this is the decisive one.

`_r_sgl_pln_nul_blk` · `_bol_` · `_int_` · `_flt_` · `_tms_` · `_str_` are six
terminals over **one** scan. The scanner picks among them through `SGL_PLN_SYM`,
a ladder over `scanner->rlt_sch`, which the schema resolver computes from the
matched text. So `CI` is `_r_sgl_pln_str_blk` and `true` is
`_r_sgl_pln_bol_blk`, and nothing in the grammar separates them.

The falsifier I named was: if the parse state already separates the variants,
the classifier is redundant and the table does the work. Measured:

```
$ joints state upstream/grammars/yaml.json --census \
    _r_sgl_pln_str_blk _r_sgl_pln_int_blk _r_sgl_pln_bol_blk _r_sgl_pln_nul_blk

_r_sgl_pln_str_blk
  shift in 19 state(s), lookahead in 33
  company where it shifts: min 9, median 37, max 43 — sole shift in 0 state(s)

co-admitted by shift:
  _r_sgl_pln_str_blk   _r_sgl_pln_int_blk   19  (first: state 0)
  _r_sgl_pln_str_blk   _r_sgl_pln_bol_blk   19  (first: state 0)
  …every pair, all 19 states
```

**All four are co-admitted by shift in all 19 of their states, state 0
included.** Not one state prefers one over another. So a hand for a plain
scalar must decide the terminal's identity from the matched text, in every
state where any scalar is legal, with 37 rivals beside it.

Nothing in this lexer does that. A `Provision` names a spelling; a troupe
answers for a family from bytes plus memory; neither *renames its own answer*
by running a second grammar over the match. That is a new role, and it is the
kind of role the brief warns has a census somewhere that will not hear about
it.

## Fact 3 — layout here is a dimension of the alphabet, not a member of it

Prediction 1's yaml half, confirmed. `serialize` writes `row`, `col`,
`blk_imp_row`, `blk_imp_col`, `blk_imp_tab`, and **two parallel stacks** —
`ind_typ_stk` (an indent *kind*) beside `ind_len_stk` (a width). Scala's stack
is a width and a flag bit; yaml's is a width and a kind that changes which
token may be emitted at all.

And the standing of a line against that stack is not a token. It is a prefix on
every other terminal's name, computed once per scan:

```c
bool has_nwl = scanner->cur_row > scanner->row;
is_r  = !has_nwl;                            // same line
is_br = has_nwl && leading_spaces > cur_ind; // deeper than the frame
is_b  = has_nwl && leading_spaces == cur_ind;// level with it
```

The same byte `[` is `_r_flw_seq_bgn`, `_br_flw_seq_bgn` or `_b_flw_seq_bgn`
depending on where the line sits. `offside` emits indent/dedent/newline as
three symbols; yaml has no such symbols to emit. A hand cannot answer "a dedent
is owed" and hand back one terminal — it has to answer *every* terminal through
a layout-indexed table.

## Prediction 3c falsified — 113 does not compress as far as I claimed

I predicted the distinct spellings behind the 113 would number **under 32**,
and named the falsifier: over 40 and the cross-product story is wrong.
Stripping the standing prefix and the schema slot leaves **46**. Falsified.

The cross-product is real where it is real — `_sgl_pln_*_blk` is 18 terminals
(3 standings × 6 schemas) and `_sgl_pln_*_flw` is 12 — but the long tail does
not fold, so the honest price is 46 rows and three new organs, not "one organ
plus a table". I would have under-quoted this by a third.

## The verdict

Declined, and the price is now named rather than gestured at. Yaml needs:

1. a **paired typed** indentation stack (kind beside width) — new, not `Columns`;
2. a **layout-indexed alphabet**, where standing selects among three spellings
   of every terminal rather than emitting one of its own — new;
3. a **schema classifier** that renames its own answer from the matched text —
   new, and load-bearing in all 19 states by measurement;
4. a 46-row table under all three;

and, because there is no slate beneath any of it, **no subset of that work
produces a parse.** Every other grammar seated this session bought partial
credit for partial work. Yaml is all-or-nothing, and that — not "unrunnable
externals" — is the reason.

The ~18,900 bytes stay on the board. Blindness is fail-closed, so they stay as
a located wall rather than a plausible tree, which is the correct place for
them until someone builds all three organs at once.

# Result 2 — go and python: a declared conflict is a fork, and this press cannot fork

Scores `PREDICTION-2-mechanism.md` (P4–P6) and `PREDICTION-4-declared.md`
(P10–P14). Pin `tenon` (`4d7074db7`, tree `fa7fcaee5`, repo `f7ba40004+106`).

## The two witnesses

**go** — `fmt.Print("x")`, seated as `specimen/go/selector-field.go`:

```
  outliner                          tree-sitter
  type_conversion_expression        call_expression
    qualified_type                    selector_expression
      package_identifier "fmt"          operand: identifier "fmt"
      type_identifier    "Print"        field:   field_identifier "Print"
    interpreted_string_literal        argument_list
                                        interpreted_string_literal
```

Same bytes, opposite meaning: convert `"x"` to the type `fmt.Print`, or call
`Print` with `"x"`.

**python** — `print(x)`, seated as `specimen/python/print-as-statement.py`:

```
  outliner                          tree-sitter
  print_statement [0, 8)            call [0, 8)
    "print"                           function: identifier "print"
    parenthesized_expression          arguments: argument_list
```

Under `print_statement`, `print` is not a reference and `x` is not an argument.

## Six controls, five green and one that came back guilty

| Control | Verdict |
|---|---|
| go `var x fmt.Stringer` | green — a real qualified type reads as one |
| go `int(x)` | green — a real conversion reads as `call_expression`, on both sides |
| go `fmt.Print()` | green — zero arity, call survives |
| go `fmt.Print("x", "y")` | green — two arity, call survives |
| python `y = print(x)` | green — expression position, call survives |
| python `log(x)` | green — a different name in the same position |
| python `print(x, y)` | **RED** — see below |

The go arity pair is the proof that a fork exists. A conversion takes exactly
one operand; give it none or two and that limb dies, and the call limb — which
was carried the whole time — is the one left standing. Both readings are alive
in the table, the input kills one, and outliner reports the survivor. On one
argument neither dies and the tie has to be broken by something else.

`int(x)` is the control I did not expect: outliner reads the one input that
really *is* a conversion as a `call_expression`, agreeing with the oracle,
because tree-sitter-go deliberately does not distinguish `f(x)` from a
conversion without a selector. So outliner is not reaching greedily for
`type_conversion_expression`. It reaches for it only where the `.` puts a
second derivation on the table.

## P4 — all three are ambiguities the vendored grammar declares. **HOLDS.**

```
go       conflicts include  ['qualified_type', '_expression']
python   conflicts include  ['print_statement', 'primary_expression']
elixir   conflicts include  ['_expression', '_local_call_without_parentheses']
```

And each carries a rank on the losing side:

```
go       PREC_DYNAMIC  type_conversion_expression -1,  _simple_type -1 / 3, generic_type 1
python   print_statement prec 1;  keyword_identifier for `print` prec -3
elixir   PREC_DYNAMIC  _call_arguments_without_parentheses -1
```

## P5 — they are not all resolved at the same place. **HOLDS.**

go and python decide at **fork time**: the cell is contested, the press records
it, both limbs run, and the loser is picked by `gather.zig`'s "least
speculative wins" when several readings accept. The go arity controls measure
this directly — the survivor changes with the input.

elixir decides at **table-build time**, and worse than P5 imagined: the rival
action is not merely outranked, it is absent (`RESULT-1-elixir.md`). Same class
of construct, three different places in the pipeline.

## P6 — go's choice is not dynamic precedence. **FAILS.**

> **Falsifier.** go's competing productions carry a nonzero `prec.dynamic` and
> the rank alone explains the choice.

`type_conversion_expression` carries `prec.dynamic(-1)`. tree-sitter sums that
rank over the finished subtrees and the call wins by exactly one point. My "go
resolves by GLR error-driven survival rather than by a rank" was half right —
survival is what the arity controls show, and it is *also* ranked, and the rank
is what settles the one-argument case. Outliner spends the same −1 per cell at
table-build time, which is not the same arithmetic and does not reach the same
answer.

## P10 — the guilty cell is `declared`, not `residual`. **HOLDS for two of three.**

```
go     state 1   .     read on   [declared shift_reduce, over fold  _expression -> identifier]
python state 6   (     read on   [declared shift_reduce, over fold  primary_expression -> print   [prec -3 none]]
elixir state 272 do    read on
```

`declared` on both, exactly as predicted, and `residual` on neither. So
`joints`' `residual = 0` really is the press reporting that it answered every
question the grammar author asked it not to answer. Elixir has no verdict of
any class, which P10 did not allow for.

## P11 — toml has no decision to get wrong. **HOLDS.** See `RESULT-3-toml.md`.

## P12 — zero-contest grammars carry no hard racked bytes. **FAILS.**

Six of seven hold: css, embedded-template, html, json, lua and toml all show 0
disputed bytes. **latex shows 42.** Small, but the prediction said none, and 42
is not none. latex's 1,077 crooked bytes are 1,035 span (a `section` whose right
edge moves) and 42 shape — a real disagreement in a grammar with nothing
contested anywhere in its table, which means the class has at least one more
member than "collapsed fork".

## P13 — declared count does not rank the damage. **HOLDS.**

elixir declares **6** conflicts and tops the disputed board at 15,791 bytes. go
declares **8** and carries 17. verilog declares 181 and cannot be judged at all.
The count predicts nothing; the corpus containing the construct is what
predicts.

## P14 — three share a mechanism, toml is different. **FAILS.**

The honest count is **two, one and one**:

- **go and python** are collapsed declared forks, decided by a per-cell ladder
  where tree-sitter uses a per-subtree sum.
- **elixir** is a fold that does not exist in the table. Nothing was collapsed;
  the second reading was never there to collapse.
- **toml** is not a press decision at all.

And go and python are not the same *fix* even though they are the same
mechanism, which the specimen that was meant to be a control proved:

```
print(x, y)   ->  print_statement with `argument: tuple`
```

Python 2's print statement takes a tuple, so it accepts every arity a call
accepts. **No input starves the wrong reading.** go's fork resolves itself on
most real Go — anything not exactly one argument — which is why go's corpus row
is 17 bytes. python's never resolves, so every bare `print(...)` in every
Python 3 file is misread, and python's row is only 27 bytes because the corpus
file happens to contain one.

That is the corpus warning in the brief arriving on my own data: go's 17 bytes
and python's 27 bytes are the same size and mean completely different things.

## The finding, in one line

Three of the four are the same *question* — an ambiguity the grammar author
declared so that a GLR parser would carry both readings and let the input
decide — and outliner answers it in three different places, none of which is
where the input is. Two get answered by a ladder that ranks a cell; one gets
answered by LALR merging deleting the alternative before any ladder runs.

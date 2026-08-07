# tenon — four grammars the board calls perfect, and what they actually read

A diagnosis lane. It produces witnesses and ownership verdicts and edits
nothing in `src/press/`. Pin `tenon` (`4d7074db7`, tree `fa7fcaee5`, repo
`f7ba40004+106`).

The four defects are all places joints **succeeds** — `accepted, 1 root`, no
wall, no stop, and on three of the four the board reads `whole` at 100.0%
standing. Nothing in this repository reddens on any of them, which is why the
only instrument that can show one is a pair of trees side by side. That is
`pair.py`, and it is the first thing to run on anything here.

## The finding

Not one mechanism. **Two, one and one** — and the split matters more than the
count, because it says where each fix lives.

| Defect | Mechanism | Where it is decided |
|---|---|---|
| **go** `fmt.Print("x")` → conversion | a declared fork, collapsed | fork time, by the ladder |
| **python** `print(x)` → Python 2 statement | a declared fork, collapsed | fork time, by the ladder |
| **elixir** `defp f(x) do x end` | a fold that is not in the table | table-build time, by LALR merging |
| **toml** `v = "1"  # c` | a parent's right edge, not a parse | not a decision at all |

A `conflicts:` entry in a tree-sitter grammar is not a hint about how to
resolve an ambiguity. It is the author telling the parser **not to** resolve it
— to carry both readings and let the input decide. Joints is LALR and cannot
carry two, so every declared cell is a fork collapsed at press time by a fixed
ladder that never sees the input. Read that way, `survey`' `residual = 0` is not
health; it is the press reporting that it answered every question it was asked
not to answer.

go and python are that. **elixir is worse**, and it is the largest racked source
in the corpus: at the guilty cell there is no rival action of any class, because
LALR merging dropped `do` from the competing reduction's lookahead. Nothing was
collapsed — the second reading was never there. No re-ranking in the ladder can
reach it.

toml is neither. Both parsers derive the identical tree; joints's `pair`
simply ends before a `comment` it has already adopted as a child. `standing.py`
has been printing `UNSOUND — child outside its parent` on that grammar the whole
time, on a row the board scores 100.0%.

## The dossier

| File | What |
|---|---|
| `PREDICTION-1-elixir.md` → `RESULT-1-elixir.md` | P1–P3. P2 fails, and its failure is the elixir finding. |
| `PREDICTION-2-mechanism.md` + `PREDICTION-4-declared.md` → `RESULT-2-declared.md` | P4–P6, P10–P14. P6, P12 and P14 fail. |
| `PREDICTION-3-toml.md` → `RESULT-3-toml.md` | P7–P9. P7 fails; the reason it fails is the finding. |
| `RESULT-4-instrument.md` | `rack`, three demonstrations, including one in my own code. |

Nine predictions logged before measurement, **four failed**, and three of the
four carry the findings they were wrong about.

## The tools

| Tool | What it answers |
|---|---|
| `pair.py <grammar> <file>` | both trees side by side plus `rack`'s verdict. Exit 1 if they are identical, because a witness that witnesses nothing is a failure. |
| `reach.py` | GAP or CONFLICT by reachability closure, adapted from `verilog/reach.py` for a population with no wall: it asks whether the oracle's parent-child edge is **seated** by a single production rather than whether a symbol is derivable at all. |
| `cell.py` | finds the candidate parser states for a wrong-parent defect — states that shift a terminal while a same-rule item is complete. `dump` for one state, `find` to search. |
| `extent.py` | re-sorts `rack`'s crooked into `span` (right parent, wrong right edge) and `shape` (parent in dispute). Changes no total; the `crooked` column must equal `rack`'s row for row. |

## The witnesses, all seated as specimens

Seven controls green, five witnesses red, under `tool/specimen.py run`:

```
ok   elixir/do-block-as-keyword-argument.ex     6/6
ok   elixir/do-block-without-inner-call.ex      5/5
FAIL elixir/do-block-on-inner-call.ex           4/5
ok   go/qualified-type-in-var.go                6/6
ok   go/conversion-without-a-selector.go        6/6
ok   go/call-with-two-arguments.go              8/8
FAIL go/selector-field.go                       2/8
ok   python/call-that-is-not-print.py           6/6
ok   python/print-in-expression-position.py     6/6
FAIL python/print-as-statement.py               2/7
FAIL python/print-with-two-arguments.py         2/8
ok   toml/pair-without-comment.toml             4/4
FAIL toml/comment-after-pair.toml               5/6
```

The controls are the argument. `defp f do x end` is green, so joints attaches
a do-block to a definition correctly when it is the only candidate. `y =
print(x)` is green, so joints does not think `print` is a keyword — it thinks
so exactly where the grammar offers it a choice. `int(x)` is green, so joints
is not reaching greedily for `type_conversion_expression`; it reaches for it
only where a `.` puts a rival derivation on the table.

`python/print-with-two-arguments.py` was authored as a control and came back
guilty, which is the reason go and python are not one fix: go's wrong reading
starves on any arity but one, and python's — a print statement over a tuple —
accepts every arity a call accepts and can never be starved.

## The three guilty cells, verbatim

```
go     state 1   .     read on   [declared shift_reduce, over fold  _expression -> identifier]
python state 6   (     read on   [declared shift_reduce, over fold  primary_expression -> print   [prec -3 none]]
elixir state 272 do    read on
```

go and python print what they beat. Elixir beats nothing.

## Numbers, with denominators

`built` is 384,715 of 526,798 corpus bytes; 34,687 of those have **no oracle
verdict at all** because tree-sitter itself ERRORs over verilog and sql, leaving
349,928 adjudicable. `rack` charges 83,169 crooked and defends 60,138 after
subtracting extras placement. Re-sorting that charge, **7,699 of the defended
60,138 are a right parent whose right edge moved**, so the figure this lane
defends is **52,439 bytes — 13.63% of `built`, 15.0% of adjudicable, 10.0% of
corpus.**

elixir alone is 15,791 disputed bytes, the largest of any grammar with a working
oracle except php, and every one of them is one shift on one terminal in one
state. go is 17 and python is 27 — the same size and completely different
things, because the corpus file happens to contain one bare `print(` and Go code
mostly calls with an arity that starves the wrong reading. As the brief says and
this lane's own data confirms: the corpus is the weakest instrument here.

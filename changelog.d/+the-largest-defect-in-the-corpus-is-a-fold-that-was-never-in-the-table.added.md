Diagnosed the four wrong-parent defects on grammars the board calls perfect —
elixir, go, python and toml — as `research/joinery/tenon/`, with a minimal
authored witness and a passing control for each, seated in the specimen tier.
Seven controls green, five witnesses red.

They are not one mechanism. go's `fmt.Print("x")` reading as a
`type_conversion_expression` and python's `print(x)` reading as a Python 2
`print_statement` are the same thing: an ambiguity the grammar author *declared*
so that a GLR parser would carry both readings and let the input decide, which
an LALR press has to collapse to one action at table-build time. Both cells say
so in their own words — `[declared shift_reduce, over fold …]`.

elixir is worse and is the largest racked source in the corpus at 17,734 bytes.
On `defp f(x) do x end` the guilty cell, state 272 on `do`, prints one action
and no rival of any class. The fold that would hand `do` to the outer call is
not in the row at all: LALR merging dropped `do` from that reduction's lookahead,
so no fork exists and nothing in the four-rung ladder in `settle.zig` can reach
it. That is a strictly worse defect than a mis-resolution and it needs a
different fix. Every one of elixir's nine widest racked runs is the same
construct, `arguments` where the oracle says `do_block`.

toml is neither a gap nor a conflict. Its grammar declares zero conflicts and
`survey` reports zero contested cells over all 175 states, so there was never a
second derivation to prefer. Both parsers put the `comment` under the same
`pair`; joints's `pair` merely ends before it. `standing.py` has been printing
`UNSOUND — child outside its parent` for that grammar all along, on a row the
board scores 100.0% standing and `whole`.

The control that mattered most was the one authored as a control that came back
guilty. `fmt.Print("x", "y")` is read correctly, because a conversion takes one
operand and a second argument starves the wrong limb — proof the press really
does fork and that go's is a resolved contest. `print(x, y)` is still wrong,
because Python 2's print statement takes a tuple and therefore accepts every
arity a call accepts. go's fork resolves itself on most real Go; python's can
never be starved by any input. Same mechanism, different fixes, and the corpus
rows — 17 bytes and 27 bytes — hide the whole difference.

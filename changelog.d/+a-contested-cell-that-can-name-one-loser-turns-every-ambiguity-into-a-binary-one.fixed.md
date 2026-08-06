A contested cell recorded exactly one dropped reading, so a grammar that
declares an ambiguity three ways got a two-way fork. `settle.Conflict.other`'s
own docstring said so — *"One of the readings that lost. There may have been
more."* — and nothing downstream could ask for the rest, because there was
nowhere to put them.

C++ is where that costs the most. At the cell that decides a bare `identifier`,
three readings complete at once — `_declarator`, `type_specifier`, `expression`
— and the two the fork carried were both *declarations*. So every unqualified
call was read as a declaration of a variable whose type is the callee, and no
amount of ranking could have fixed it: dynamic precedence orders the readings on
the table, and the reading tree-sitter takes was never on it. C++ declares the
most dynamic precedences on the corpus and the lane that taught the runtime to
read them moved C++ zero bytes. This is why.

A cell now carries all of them. `column.Folds` keeps tied reductions past
`rival` instead of dropping them, `settle.Conflict` grows a `rest` beside
`other`, the folio grows a `rival` section that a `ConflictRecord` names its own
slice of, and `forks.at` returns every reading a cell dropped rather than the
first. The runtime's split loop became a loop.

`void g() { f(y); }` — nineteen bytes that parsed whole, one root, zero damage,
every leaf at the oracle's offset and every parent wrong — now builds
`expression_statement (call_expression (argument_list))`, which is the oracle's
tree exactly. On one frozen oracle, against a control pinned one change away:

    cpp    185 → 1408 square (+1223), 1039 → 1408 built, damage 369 → 0
    c      767 → 1444 square  (+677),  893 → 1444 built, damage 551 → 0
    corpus 311540 → 313440 square (+1900), 27 of 30 rows bit-identical

No row loses a square byte. Haskell trades 272 bytes of `built` for 272 of
`damage` at flat square and 36 fewer crooked, which is a shape it used to build
wrongly and now declines to build — the only row that pays anything.

The bound on how wide a cell can be is real and now cannot be silent.
`column.spares_max` sits at 8 where the widest cell on the corpus drops 6
(verilog, 89 of them), and `research/joinery/arity/arity.py` **fails** if the
corpus ever reaches the bound, because a ceiling measured by the thing it caps
reports its own value and calls it a count. Raising the bound from 6 to 8 moved
no number, which is the positive control that it was never truncating.

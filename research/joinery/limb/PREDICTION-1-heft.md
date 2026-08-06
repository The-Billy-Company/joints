# Prediction 1 - the tie-break at a merge is dynamic precedence, not speculation depth

Written before anything was built or measured. Oracle frozen as `limb`
(`attest.py freeze limb`, 30 grammars, tree-sitter 0.26.11) so neither arm can
be handed a different oracle.

## The premise

`gather.collapse` merges two readings standing on the same states and keeps the
one with the lower `rank`. `first` and `close` apply the same key. `rank` is
**how many declared conflicts this reading took the losing side of** - a fact
about the parse loop's own bookkeeping, not a fact about the grammar. At a cell
whose author declared the two sides equally valid, "the table picked first" is
what `rank 0` means, so keeping the lower rank is keeping the press's coin toss.

Three places in this tree already name the missing input, none of them mine:

- `grammar.zig`, on `Production.dynamic`: *"A dynamic one resolves nothing: the
  cell keeps both actions, the parse forks, and this is the tie-break between
  readings that are all still alive at the end ... tree-sitter compares the
  **sum** over each candidate subtree."*
- `gather.zig`, on `close`: *"the least speculative wins: **without dynamic
  precedence there is nothing better to compare them by**."*
- `research/joinery/TESTING.md`, on c's `long total;`: *"a declared fork whose
  winner is chosen by **dynamic precedence**, and the `-1` sits on exactly the
  branch that swallows the identifier ... the ranking that consumes
  `Production.dynamic` is the press lane's."*

So the runtime carries `prec.dynamic` through the folio (`leaf.zig`,
`impose.zig`, `bind.zig` all round-trip it) and then never reads it.

## What the oracle actually does

tree-sitter 0.26.11, read rather than remembered:

| site | file:line | rule |
|---|---|---|
| a subtree's rank | `subtree.c:353,407` + `parser.c:1030` | `dyn(parent) = sum(dyn(child)) + action.reduce.dynamic_precedence` |
| a stack version's rank | `stack.c:164,171` | `dyn(node) = dyn(prev) + sum(dyn(pushed subtrees))` |
| choosing between versions | `parser.c:284` | error cost first, then **higher `dynamic_precedence` wins** |
| choosing between trees at a merge | `parser.c:856-866` | **higher `ts_subtree_dynamic_precedence` wins**, then structural compare |

The two accumulations compose to something a parse loop can carry in one
integer. A reduce pops N subtrees whose ranks are already in the stack total and
pushes one parent worth `sum(children) + declared`, so the **net delta on the
stack total is exactly the production's declared `prec.dynamic`**, and a shift
contributes zero. `ts_stack_dynamic_precedence` is therefore reproducible as
`heft += gr.productions[p].dynamic` on every fold - one `i32` add per reduce, on
the forking path only.

## The change

`Reading.heft` / `Turn.heft`, an `i32` accumulated at the `.reduce` arm of
`absorb` and of `close`, inherited unchanged by a reading born at a split (up to
the split they are the same derivation, so their totals are equal there and only
the suffix differs - which is exactly the difference the comparison wants).

The key at all three comparison sites becomes **higher `heft`, then lower
`rank`**. Rank stays as the last word, so nothing that ties on the grammar's own
declaration changes its answer.

It is structural in the sense the brief demands: the only input is
`prec.dynamic`, written by the grammar's author in the grammar's own file. No
grammar name is read, no per-language table exists, and a grammar that declares
no dynamic precedence cannot reach the new comparison at all.

## Predictions, with the number that kills each

**P1a - the twelve grammars with no `PREC_DYNAMIC` are byte-identical.**
`gist -c -F PREC_DYNAMIC upstream/grammars/*.json` says verilog, yaml, sql,
html, css, toml, embedded-template, latex, ruby, r, and the rest declare zero.
`heft` is 0 on every reading in those, so both keys tie and `rank` decides
exactly as today. **Killed by any movement at all in a zero-dynamic row** - that
is an implementation bug, not a result.

**P1b - the tie-break alone is a small positive, concentrated in c and cpp.**
c's `long total;` is the case TESTING.md already attributes, and the `-1` is on
the branch that swallows the identifier, so preferring the higher total should
stop swallowing it. cpp declares 29, the most on the board. **I predict `square`
up on c, and `square` not down by more than 500 anywhere.** Killed if any
grammar loses more than 500 square bytes.

**P1c - and it will be small.** These cells only exist where a fork *already*
stood and *already* merged. Elixir merges 10 times on `router.ex` against 296
splits today. **I predict the corpus-wide `square` delta of the tie-break alone
is under +3,000**, most of it c and cpp, and I would not be surprised by zero.

**P2 - B plus the tie-break does NOT recover the 29,348, and elixir does not
come back.** This is the prediction I expect to be graded down for and it is
written first on purpose. Two reasons:

- **verilog declares zero `PREC_DYNAMIC`.** The `<=` cell at state 1762 is the
  named wrong-limb defect and dynamic precedence is structurally incapable of
  answering it: both limbs carry heft 0. Whatever picks verilog's limb, it is
  not this.
- **elixir declares six**, against a fork population B multiplies. 23,879 square
  bytes down to **one** is not a tie-break landing on the wrong side of a coin;
  a tie-break can only ever cost you the readings that reached a merge. My
  reading of `collapse`'s own docstring is that the mechanism is `crowd`
  exhaustion - B opens forks at every `purely(f, .left)` cell, eight readings
  stand, and the later fork that mattered is `denied`. **The falsifier is the
  denial counter**: if elixir's `denied` goes from 0 to a large number under B,
  the wrong-limb story does not explain elixir and the tie-break cannot fix it.

**P2 is killed - happily - if B + heft returns elixir to within 1,000 square
bytes of control.** That is the outcome the lane was priced for and I do not
expect it.

## What clears what

`heft` cannot move a pressed table, so **folio identity says nothing about it**
(fifth house rule). Its control is an isolation arm: today's tree with the
`heft` rows deleted and every seam left standing, checked by
`still against <arm> <alone> --mine src/kernel/quire/gather.zig`.

B *is* a press change, so folio identity is a real positive control for that
half and a vacuous one for the runtime half. Both are needed and neither
substitutes.

**Not judged on verilog.** It is 100% `unjudged` while its oracle's CST and XML
disagree, so its only live column is `damage`, and `damage` is outliner's own
words about its own forest. Verilog rows are reported and not scored.

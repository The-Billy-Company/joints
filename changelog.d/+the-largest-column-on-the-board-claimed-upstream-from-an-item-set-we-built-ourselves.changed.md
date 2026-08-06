The owners board's `gap` verdict printed *"no LR parser over this grammar takes
it here"* and carried 73.7% of the priced corpus. A lane checked eighteen of
those rows against tree-sitter 0.26.11 and fifteen parsed, worth 99.94% of
their bytes. Sixty bytes survived, all verilog.

The sentence was false in one specific place, and it is worth naming precisely
because the *test* is fine. `viable()` computes FIRST and FOLLOW over
`grammar.json`, which is shared; the **items come from our own LR(0)
collection**, which is not. A reading our table construction lost is
indistinguishable, from inside, from a reading the grammar never had - and the
`src/press/` lane has since proved the splice erases authored precedence with
no conflict recorded and no fork, so a deleted reading leaves nothing in the
row to see. The verdict was reporting the automaton and labelling it the
grammar.

`gap` is retired for **`unowned`**, which is what the test establishes: the
parse shifted into this state, nothing folded, and the automaton we built holds
no reading for this terminal. Four things produce that and three are ours - our
table lost a reading, our lexer produced a terminal the program does not
contain, an external was never seated, or the grammar genuinely has nothing.
The verdict now names the four instead of picking the one that takes the work
off us. `--gaps` becomes `--unowned` and writes an adjudication worklist rather
than a claim; `GAPS.md` keeps its bytes and gains a retraction header.

`stranded` is unchanged and the pair now reads as a pair: `stranded` is the
wrong place to ask, `unowned` is the right place with four answers. Neither
says upstream. Nothing in this change moves a byte between buckets on its own -
the relabelled board is byte-identical to the old one outside the two walls the
sibling fixes moved - which is the point. The number was never wrong. The
sentence bolted to it was, and it had been read as a work order.

The README's status section described a tree that stopped existing one wave ago.
It listed grain, vellum and the M5 quotient under "what is *not* built" - all
three had landed - and the monoid table said the same thing twice more, with M3
promising that "the succinct 2n+o(n) settling (vellum) is not" built and M5 flatly
"not built".

The worse half was the sentence about the size claim, which read "M5 - which is
where the size claim lives, so the size claim is still a target." Both clauses
turned out to be wrong, and in opposite directions. **The size claim is met**:
rung 4 measures the folio against tree-sitter's compiled parser at 0.139x-0.987x
bits per production over eleven grammars, no grammar losing. **And it is not M5's
win.** The bisimulation merges 0 to 19 states out of thousands, the column
alphabet narrows 1.00x-1.09x, and the DAFSA loses to a sorted array by
2.85x-4.33x, so the folio still writes the array. Leaving the old sentence up
would have let a reader credit the number to the mechanism that did not earn it,
which is a worse fault than being out of date.

So each row now carries what was measured rather than whether the file exists,
including the parts that read badly: vellum is **30-100x slower on `parent`**,
grain's line index is **0.08x-0.43x on jumbled access** and only repays a forward
sweep, and rung 4's `ours` column includes a per-grammar lexicon section that
tree-sitter emits as machine code inside the `.so` and does not pay for in the
same currency.

The section also gained the two numbers a reader wants first and could not get
from this page at all - **78.12% of a 527 KB, thirty-grammar corpus gets a tree
and 0.48% of that is read as something else, eighteen of thirty grammars at
100%** - each named with the instrument that prints it and the tree it was taken
on, because four boards published here in one morning once disagreed by ~1,900
bytes with all four correct about different trees. Every figure quoted on this
page and on that one came off `7eb9bb9`: `python3 tool/plumb.py board` for the
corpus percentages, `zig build census` for the wall roster, and `python3
tool/rung4.py run` for the bits-per-production ratios.

What is left is now three items rather than five, ordered by what it costs a
reader: the query engine, an edit door on the C ABI (`jnt_parse` is the only way
in, so the weave is reachable from the CLI alone, and the tree walks downward
only), and M4 as a semiring parameter rather than one policy family. The layout
block moved grain and vellum into what exists, and corrected the plan's one wrong
guess about vellum's own shape: it landed above `quire`, not inside it, because
it reads both the quire it settles and the spine it hangs the word on.

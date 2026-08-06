# abut — a token of no width, and the family of reports that could not describe it

Two items that turned out to be one. Julia's five `_immediate_*` markers are
zero-width externals that move no memory, and the hand for them has to read the
parse state's permission set — which is the union of the row's two halves, and
which nearly every instrument in this repo was reporting as one of the two
without saying which.

| File | What it holds |
|---|---|
| `PREDICTION-1-pin.md` / `RESULT-1-pin.md` | What `step`'s progress pin was actually refusing, and the ledger that replaced it. 4 predictions, 4 held. |
| `PREDICTION-2-order.md` / `RESULT-2-order.md` | Where the hand stands and what julia does. 5 predictions, **2 failed** — the census said the placement mattered and the measurement said it did not. |
| `PREDICTION-3-instruments.md` / `RESULT-3-instruments.md` | The admission-report sweep. 5 predictions, **1 failed**, and the one that failed is about the sweep itself. |

## The three sentences worth carrying out of here

**The pin was not refusing what the handover said it was.** It refused an exact
repeat of `(offset, symbol, shape)` against a single slot, so a memoryless hand's
first answer was always legal and nothing needed relaxing. What one slot cannot
do is see a two-cycle: `A B A` at one offset with the memory unmoved walked
straight through, because `B` overwrote the slot that would have caught the
second `A`. The replacement is a per-offset ledger with an arithmetic termination
bound, and the argument is in `outside.Spent`'s header rather than here.

**The ceiling that makes the bound work is exercised by nothing.** Lowered from
256 to 4, every grammar in the corpus is byte-identical; the deepest run of
zero-width answers at one offset anywhere in the thirty is three. One unit test
stands between that constant and dead code.

**A census can be right about the table and silent about the file.** Julia's
markers are co-admitted with its string interiors in state 1 and share a byte
with `_end_str`, which said the hand had to stand below the marrow phase. Placed
above it instead, julia's board does not move — the parser never stands in state
1 at a quote. The placement stayed on the rule the file already applies, and the
comment now credits the rule rather than the census.

## The measurement, in one row

| | julia before | julia after | board before | board after |
|---|---:|---:|---:|---:|
| standing | 59.6% | **92.9%** | 67.4% | **69.1%** |
| covered | 80.3% | 99.2% | 83.4% | 84.4% |
| unbound | 8,912 | 241 | 115,139 | 106,468 |
| roots | 1,591 | 138 | — | — |
| bare leaves | 897 | 30 | — | — |
| blind terminals | 5 | 0 | — | — |
| describes | — | — | 95,150 | **97,595** |

Twenty-nine of thirty grammars tree-identical, compared as trees rather than
folio bytes. `describes` rose while roots fell, so the lifted `built` is a
deepening tree and not a policy reading less.

Item 2 moves **zero** board cells: same thirty rows, same four addends summing to
526,798, same `describes`, all thirty trees identical, and the entire diff is
eight diagnostic sentences growing `, admitted by shift`.

# rung: quotient

`zig build bench-quotient`

Three Myhill–Nerode questions asked of each pinned grammar, and the arm each
answer has to beat:

| Section | Question | Beaten against |
|---|---|---|
| `states` | which LR states does no parse tell apart? | the un-quotiented state count |
| `cols` | which terminal columns does no state route differently? | the raw column count |
| `names` / `pats` | is the grammar's string payload smaller as one automaton? | a sorted array with an offset pair per key |

Two of the three are expected to come back unimpressive, and printing them
anyway is the point.

* **`merged` is near zero, on purpose.** `folio/forme.zig` interns identical
  action rows before anything gets here, and `press.zig`'s unfolding loop exists
  to *split* the states LALR merged wrongly. A third pass finding a handful is
  the correct answer; the row is printed every run so that "the relation is
  empty" keeps having to be true as the press changes.
* **The DAFSA ratio can exceed 1.00x**, and then the folio is right to keep the
  sorted array. `spelling` is the mean key length that decides it — long
  unshared stems are where an automaton pays a target word per edge and earns
  nothing back.

The bits-per-production comparison against the tree-sitter `.so` is **not**
here: it needs a tree-sitter toolchain and a compiled parser per grammar, so it
lives in `tool/rung4.py` beside `tool/bench.py`, with its own tracked baseline
at `tool/rung4.baseline.json`.

Grammars come from `upstream/grammars/`. A grammar that is not underfoot is a
skipped row — run `python3 tool/grammars.py fetch` first.

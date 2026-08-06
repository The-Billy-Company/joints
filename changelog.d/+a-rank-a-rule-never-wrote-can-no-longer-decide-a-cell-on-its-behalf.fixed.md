`g.Step` grows a `spliced` bit, and rung 3 of the precedence ladder declines a
side that carries it.

When `fold.zig::expand` inlines a rule, a spliced boundary step takes the host's
rank only where the victim wrote none. So verilog's `variable_lvalue`, authored
`prec.left(37)`, reaches `_identifier` through `hierarchical_identifier`, which
wrote `prec.left(0)` — and the 37 is dropped on the floor. Rung 2 then saw a tie
instead of `above`, rung 3 folded on a `left` that the competing reduction had
*also* inherited from the same intermediate rule, `standing` came to 1, and
`Bench.decide` returned before recording anything. No conflict, no fork, no
shift on `[` in state 1184's row, and verilog could not read `a[3]` inside a
concatenation. Nothing in the press could tell a rank a rule wrote from a rank
it absorbed on the way through a fold, and four earlier repairs were all
attempts to guess that distinction from outside.

Now `expand` marks every step it splices in that carries a rank of its own, and
the boundary step inherits the host's provenance along with the host's rank so a
second fold round cannot launder it clean. `column.Folds` records whether any
surviving reduction authored its own side; `Ladder.purely` answers no when none
did, and the cell stays undecided instead of being settled by an inherited one.
The bit is press-only — a folio carries the table, not the argument that
produced it — so no `extern struct` grew and no padding came back: all thirty
grammars press twice to identical bytes.

Measured 2026-08-05, pinned binaries either side plus a paired control differing
by one line. Board totals unchanged at 142,083 damage; `rack --square` flat on
every grammar and every column; 27 of 30 folios byte-identical, 29 of 30 trees
identical. The earlier repair that seated the same witnesses cost scala 12,733
bytes and elixir 7,358; this costs them nothing, and elixir's folio does not
change at all. W7 and W8 seat with all seventeen controls standing.

What it costs, in the same paragraph as the win: **verilog is not fixed.** With
the rank no longer erased, state 1762 now honestly offers a fork on `=` between
`variable_lvalue` and `variable_decl_assignment`, and `gather` takes the
declaration limb — so `c[i] = 0;` seats as a `block_item_declaration` rather
than a `blocking_assignment`, four statements in `picorv32.v` do the same, and
`ident[ident] <= …` regresses from a wrongly-shaped parse to a hard wall. All of
that prices at exactly zero on the board, which counts spans; the only number
that moves anywhere is verilog's node count, 22,222 → 22,210. The remaining
defect is the wrong-limb choice in `src/kernel/quire/`, and it now has a
three-line reproducer instead of two whole-file regressions in other grammars.
See `research/joinery/verilog/RESULT-3-provenance.md`.

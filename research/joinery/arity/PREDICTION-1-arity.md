# Predictions — a contested cell that can only name one loser

Written before any board was read on this lane. The arm is `pin-arity-control`
(tree `2695f7f68590`, commit `f7ba40004`+136, oracle 30 of 30 live). The brief is
two jobs folded into one: widen a contested cell to carry every dropped reading,
then fix swift's `if let limit = limit {`.

## What I think is true

**P1 — swift's `if let` does not need the widening.** The cell I have already
located is state 1401 on `{`, one read against one fold (`_if_let_binding`), and
the trace I want is a *class* change, not an arity change. Widening carries more
losers out of a cell; swift's cell drops exactly one. So the two halves of this
brief are two different defects that happen to live in the same file, and the
honest answer to "did swift need the widening" will be **no**.

**P2 — swift's cell is `residual` and that is the whole bug.** `forks.zig` offers
a fork for `declared` and `unwritten` and refuses one for `residual`. The cell is
recorded (so both actions survived the ladder) and then thrown away by the
classifier. The repair is on the classifying side, not the ordering side: nobody
wrote the comparison that silenced the survey, so `unwritten` is the true class.

**P3 — the widening changes no cell's `chosen` anywhere.** I am confining it to
what a cell *carries out*, and touching nothing the ladder reads. If any row's
folio digest moves, I have made a mistake rather than a discovery.

**P4 — the number of contested cells that drop more than one reading is in the
low hundreds corpus-wide, and it is dominated by two or three grammars.**
Verilog's 76 groups of ≥3 make it the most likely leader, and I expect
verilog + cpp + typescript to hold over half of it.

**P5 — the third reading in cpp's state 2572 is a *tied* fold and is being
dropped by `Folds`' two-slot bound**, not erased at rung 1 by precedence. If it
lost on precedence, widening the record cannot recover it and the dossier's
recommended repair is the wrong one. This is the prediction most worth being
wrong about.

**P6 — the widening moves cpp's `square` and moves swift's not at all.** cpp's
recoverable band is 883–1,197 against 185. swift's `if let` is a class bug; a
third strand in a cell that only ever had two readings buys nothing.

**P7 — `crowd`/`skeins` do not bind on the corpus after the widening.** The
dossier flags fan-out as a thing to price. I expect the extra strands to be
refuted within a token or two (a third reading of a bare identifier dies fast),
so the denial counters stay at zero on every row that is whole today.

## What I expect to be unable to settle

**P8 — the three-byte `statements` extent gap is not mine and is not a press
defect.** A trailing separator's extent is a tree-shaping decision, so I expect
to find it in the node builder rather than in any table, and I expect it to be
corpus-wide rather than swift-only.

**P9 — the implied statement break being declined downstream of the lexer is a
`quire`/`lex` boundary question**, and the state that "admits the separator
before `}`" admits it under a *different* terminal than the one the lexer emits.
I expect to be able to name which of the two symbols the state reads and not to
be able to fix it inside my lane.

# Prediction 4 — the wrong limb, and who is actually choosing it

Written against [HANDOVER-wrong-limb.md](HANDOVER-wrong-limb.md) before any
binary but the baseline was built. `.local/pin/limb-before`, tree `fec880d745da`,
commit `f7ba40004+118` — the press lane's provenance bit is in the working tree,
so state numbers here are the after-fix numbers and match the handover's.

Everything below is reproduced first, so the predictions are about a change and
not about the tree as it stands. What I have already confirmed by reading and by
`outliner state`, and am therefore not predicting:

- The witness reproduces. `instr_mul = 0;` in an `always @* begin` reads
  `block_item_declaration (data_declaration …)`.
- State 1762 on `=` is `read on [residual shift_reduce, over fold
  variable_lvalue -> _identifier]`, as printed.
- Two situations the handover does not list. `c[i] += 0;` walls in state 2603
  exactly as `c[i] <= 0;` does, so the hard regression is every compound
  assignment through an identifier index and not only `<=`. And `x <= 0;`
  *accepts*, as `clocking_drive (clockvar_expression (clockvar …))` — a
  nonblocking assignment read as a clocking drive, which is a fifth wrong limb
  and a pre-existing one.

## The claim the handover makes, and why I think it is wrong

> State 1762 used to have one action on `=`; now it is a real `shift_reduce` and
> gather takes the declaration limb.

`gather` does not take it. `gather` is never asked.

`settle.Forks.of` builds the index `absorb` consults on every token, and its
first line is

```zig
if ((k.class != .declared and k.class != .unwritten) or k.other.none()) continue;
```

A `residual` cell is excluded on the stated argument that *"nobody sanctioned
that ambiguity, and exploring it would be guessing on the author's behalf a
second time, in the other direction."* So at state 1762 on `=` there is no entry
in `Forks`, `absorb` takes `x.t.at(state, sym)` unconditionally, and the limb is
whichever one the **press** wrote into the cell when it fell back from a residual
it could not settle. The press's fallback is shift. Yacc's default.

That relocates the defect without making it someone else's: the cell is the
press's, the *policy that a residual is not worth exploring* is a claim about
what a parse loop should do, and the parse loop is mine.

**P1 — no fork stands at 1762 on `=`.** Falsified by any trace showing a split
there, or by `x.rifts`/`x.denied` rising when a file hits that cell.

**P2 — the four situations in the handover's table are three separate defects,
not one.** `=` is the press's residual fallback (P1). `ident[ident] <= …` walls
in state 2603, whose only item is `associative_dimension -> [ data_type ] .`, so
the commitment to a declaration was made *inside the brackets* — a later cell,
where `i` folded to `data_type` rather than toward `expression`. `x <= 0;` is a
**declared** `reduce_reduce` at 1762 (`clockvar` over `variable_lvalue`) where
`gather` really does fork and really does answer wrong. Falsified if the same
cell explains two of the three.

## The two arms

Neither arm re-ranks anything and neither resurrects a spliced rank; repair A
was that and measured worse.

**Arm A — a residual cell forks, in the order it already answers.** Admit
`.residual` to `Forks`. The reading in hand keeps the table's action at rank 0,
the residual reading is spawned at rank 1. `collapse` keeps the lower rank and
`first` picks the lower rank, so the table's answer wins every tie it wins today.

The argument the exclusion actually rebuts is *choosing* a residual reading.
Forking does not choose. A fork keeps both and lets the bytes refute one, which
is the opposite of guessing, and the direction the fuse points is already
right: `crowd`'s doc says *"the reading that is not forked is the most
speculative one, so the table's own answer is never the thing that gets
dropped."* Yacc prefers shift because it cannot fork; inheriting that tie-break
in a parser that can is the part with no argument behind it.

1,115 residual cells over 30 grammars, 1,102 of them shift/reduce, in 14
grammars: cpp 472, scala 192, rust 183, verilog 136, c 66, julia 21, bash 14,
ruby 9, haskell 8, php 5, python 4, go 2, zig 2, swift 1. Against verilog's
18,710 declared cells this is a 0.7% wider index.

**P3 — Arm A changes no accepted tree, on any grammar.** Rank order is
preserved, so wherever the table's limb survives today it still wins. The only
thing Arm A can do is keep a parse alive that walls today. Falsified by any
grammar whose `built` *falls*, or whose node count moves on a file that has no
wall either side.

**P4 — Arm A changes nothing at all on the 16 grammars with no residual cell.**
`standing.py` rows byte-identical. Falsified by one of them moving. This is the
control, and it is a weak one: it can only catch a change so broad it isn't
about residuals.

**P5 — Arm A leaves `instr_mul = 0;` a declaration.** Both limbs parse the file
whole, so nothing refutes the shift, and rank hands it the tie. I would rather
be wrong; being wrong would mean the shift limb dies somewhere I cannot see.

**P6 — Arm A does not fix `ident[ident] <= …`.** By P2 that wall is downstream
of a cell inside the brackets, and if that cell is `declared` it already forks
and Arm A does not touch it. Falsified if it seats — which would be the good
kind of wrong and would mean the bracket cell is residual too.

**P7 — Arm A moves verilog's damage by less than 1,000 bytes.** `RESULT-1`
priced all 8 of picorv32's wall-D sites at 167 bytes by ablation, and the two
`ident[ident] <=` sites sit behind `` `ifdef `` blocks the parse already walls
on. Falsified by a move over 1,000 either way. A large *fall* would be the good
kind of wrong; a rise means readings are surviving that should not.

**Arm B — at a residual shift/reduce, the completed reading is the less
speculative one.** Arm A plus: the reading in hand takes the fold and the shift
is spawned at rank 1. Only `shift_reduce`, only `residual` — 1,102 cells.

The argument: a fold is a production that is *complete*, and a shift is a bet
that more input will complete a longer one. Where nobody ranked the two, the
completed reading is the one with evidence behind it, and taking it costs
nothing now that the bet is still standing beside it at rank 1. It is also what
this cell did before the press fix, and the fourteen sibling rows of 1762 —
`+=`, `-=`, `*=`, `++`, `--`, and nine more — all fold and are all right. `=` is
the outlier only because a declaration is the one other thing an identifier can
begin there.

The risk it runs is the dangling-else shape, where shift is wanted. I expect
that to be small *because* these cells are residual: in a tree-sitter grammar
the constructs an author cares about carry ranks, and a rank that settles the
cell keeps it out of this class entirely. Residual cells are the accidental
ones. That is an argument, not a measurement, and P9 is where it gets tested.

**P8 — Arm B seats the witness.** `instr_mul = 0;` reads
`blocking_assignment (operator_assignment (variable_lvalue …))`, and verilog's
node count returns to the baseline 22,222 from the provenance bit's 22,210.
Falsified by the tree still reading `block_item_declaration`, or by the count
landing anywhere but 22,222 — a different number means I fixed a different
thing.

**P9 — Arm B regresses at least one of cpp, scala or rust.** They carry 472,
192 and 183 inverted cells and nobody has ever taken the fold at any of them.
Falsified by all three staying byte-identical, which would mean the corpus never
reaches those cells and Arm B is cheaper than it looks.

**P10 — `crowd` does not bind harder.** verilog's 136 new fork cells are 0.7% of
its index and `collapse` already stopped the twin storm that made the fuse
matter, so `denied` stays near its 46. Falsified by `denied` rising materially,
which would mean Arm A can change a tree by starving a *later* declared fork —
the one way P3 can be wrong without a residual limb winning anything.

## How this gets judged, given the instruments here lie

`smallest.py` scored W7 seated because it asked whether a snippet parses whole,
and `c[i] = 0;` parses whole and is wrong. So no arm below is judged on an exit
code. Every witness is judged by **diffing the printed tree**, and the four
`picorv32.v` statements at line 2348 are the visible difference — worth twelve
nodes and zero bytes, so `built`, `covered`, `spoil` and `damage` cannot see the
fix either way. `rack --square` prints `THE GUARD CANNOT RUN HERE` for verilog.

Each arm gets its **own `OUTLINER_WORK`**, and the folio shas get printed and
compared, because `tool/order.py::miss` keys on a path and an mtime and two
pinned binaries are both older than a folio either of them minted. I expect the
shas to be *identical* across arms — `Forks` is built by the consumer and never
written to the folio, and no arm touches a conflict's class — and that
expectation is exactly why the check is worth running: if a folio moves, my
model of where this change lives is wrong.

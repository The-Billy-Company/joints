The widening that took cpp from 185 to 1,408 square left verilog bit-identical,
and verilog holds 93% of the multi-drop cells it was built for. Three filters
stand between a wide cell and a byte, and verilog fails all three.

**Reach.** 4,350 of its 5,241 wide cells (83%) sit in 167 states `picorv32.v`
never stands in. Only 891 are ever entered. cpp is the same shape and its
numbers were too small to notice: 3 of 27.

**The balance sheet.** The 891 that are entered opened **+1,808** forks over the
control, and every one died — **+1,674 merged, +134 refuted, net standing
exactly +0**. The record was filled, the fork was taken, and the reading was
merged away one step later. Forty-two more forks hit the `crowd` budget the
control never reached, in three states that hold no wide cell at all, so the
widening's only measurable effect on verilog was to crowd out forks elsewhere.

**Why they die.** Verilog declares **no `prec.dynamic` anywhere**, so
`Reading.heft` is identically zero and `Reading.beats` degenerates to
speculation depth — which a rival loses by construction, being born later than
the reading it split from. All **2,708** of verilog's merges read `heft 0 and
heft 0`; so do all 536 of haskell's. Seven of cpp's seventeen are decided by an
unequal nonzero heft, and that column is the whole 1,223 bytes. The two keyless
grammars hold **95%** of the corpus's wide cells. On a keyless grammar a widened
record can only ever *substitute* a rival for a reading that died, never let one
be preferred - and haskell, where 66 did survive by substitution, **lost 272
bytes** doing it.

**And the damage is elsewhere anyway.** All four of verilog's defect wall
states - 1108, 701, 3772, 2394, carrying 41,916 bytes - hold **no contested
cell at all**, reproducing RESULT-2-splice from the other direction and
extending it to the fourth. 72.5% of verilog's damage is `spoil`, bytes the
parse never reached.

Two corrections to RESULT-1. cpp opens the **same 45 forks on both arms**, so
its gain is three strands not being refuted at an existing fork site, not 27
cells paying out; and the arity headline counts a population four fifths of
which no single file can enter.

What lands: `research/joinery/arity/reach.py`, which asks all three questions
off the folio's own enum ordinals and one `quire` trace, and fails loudly when
handed a binary that prints no fork lines rather than reporting a reach of
zero - which reads exactly like a grammar nobody splits in. Plus
`RESULT-2-reach.md`. No tables moved.

Three directions out of the merge, none taken. Two were already closed by
measurement (keeping the higher rank costs 23,985 bytes of agreement;
declining the merge costs 57,627 and returns the same trees). The third -
gating the widening off on keyless grammars - needs no build to price, because
the control arm *is* the gated arm on those two rows: **+272 bytes**, in
exchange for disabling the mechanism over 95% of the cells it was built for.
Declined. The rung that would actually pay is a **structural** tie-break in
`Reading.beats`, the one tree-sitter's `ts_parser__condense_stack` has and we do
not; that is a handoff to `src/kernel/quire/`, not a patch, while two lanes are
live in it.

# quarrel - what a state does when it could do two things

A cell where the automaton could both read on and fold up is a quarrel, and the
generator has to settle every one of them or refuse the grammar. This directory
holds the machine that settles them and the five instruments that explain the
settlement.

**These six files are one module and cannot be cut.** They are mutually
recursive: `settle.zig` imports all five of the others and every one of them
imports `settle.zig` back. That is not an accident to be tidied - a verdict and
the reasons for a verdict are the same computation - and it is why this is a
directory rather than a layer boundary drawn through the middle of it. Any split
here would be a shallow one, and it would be a cycle across directories on top of
being shallow.

`settle.zig`'s doc comment lays out a ladder of four rungs, consulted in the order
the author's declarations were meant to be. That ladder is also the file seam: one
rung per file, so a reader who has the ladder has the folder.

| File | Rung |
|---|---|
| `settle.zig` | The record and the entry point. `Action`, `Conflict`, `Frayed`, `Tally`, the `Case` that goes in and the `Verdict` that comes out - which is what the rest of the press, the folio, and `impose`'s comptime ledger see. |
| `column.zig` | **Rung 1** - reduction against reduction, inside one column of one state. `Folds` is the column; `keener` orders a tie the author ranked. |
| `ladder.zig` | **Rungs 2 and 3** - read against fold, by precedence and then by associativity. `Survey` is what the state's readings said; `Ladder.step` is the verdict, including the exception on rung 2 that looks like a bug and is not. |
| `attribution.zig` | **Rung 4** - whose ambiguity is left, once precedence and associativity have both declined to say. Traces a synthesized reading back to the rules that were expecting it. |
| `workbench.zig` | The fixture the rungs are walked on: one state's row at a time, and the scratch that makes doing it thirty thousand times affordable. |
| `forks.zig` | Not settling at all - the index a parse loop reads off a finished verdict to know which cells it may split at. |

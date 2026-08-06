# Prediction 1 — what the peel's provenance is worth, before I measure it

Written before running anything but a 22-second timing probe on swift. Nothing
below is measured yet; the numbers are what I expect to be wrong about.

The inheritance: `../strand/RESULT-1-attribution.md` says 21,350 of the 22,179
`stranded` bytes (96.3%) are the cold peel's own scissors, established by asking
whether `tool/walls.py warm` — a peel that never restarts — ever reaches the
same wall. `Wall.real` is `not shadow and state != 0`, which catches the state-0
row and misses the two with a statement in front of them.

## What I think the mechanism actually is

**P1 — `cut.py`'s warm/cold diff is a state-number join, and the state number is
the thing the finding says is meaningless.** A wall's identity in both peels is
the phrase `<terminal> in state <n>`. Cold round *i* reads a fragment, so its
state numbers are that fragment's; warm always reads the whole file, so its state
numbers are the file's. Two different automaton walks cannot produce the same
state number for the same refusal except where the two peels read the same text —
which is **round 1 and only round 1**. So I predict the warm/cold set difference
is, to within a couple of coincidences, exactly `turn > 1`, and the 96.3% is
mostly the join key rather than the warm peel.

Falsifier, and it is cheap: swift's warm run already reports 54 distinct walls of
which **53 are not in the cold set**. If the join were sound, a warm peel that
reads the whole file 400 times would share far more than one wall with a cold
peel over the same file. I predict the shared wall on swift is `) in state 141`
and that it is the round-1 wall. If instead I find several shared walls at
`turn > 1`, P1 is wrong and the join is doing real work.

**P2 — the honest join is (terminal, absolute offset), and it will move the
number.** Warm blanks rather than deletes precisely so offsets stay stable, and
the cold peel knows every wall's absolute offset (`marks`). Joining on *where and
what* instead of *what and which state* is a join both peels can actually satisfy.
I predict this raises the surviving population well above 611 B — my guess is
between 2,000 B and 15,000 B corpus-wide — because cold walls at real byte
positions that warm also complains about will start matching. I expect to be
wrong in the low direction more likely than the high.

**P3 — the absence has a frontier, and a third of the `torn` verdicts will turn
out to be `untested` rather than artifacts.** The lane named this as its own
weakest instrument: an absence from a bounded run looks stronger the weaker the
run is. It is fixable, not just confessable. Warm records how far it ever read;
a cold wall lying beyond that frontier was never in warm's view, so its absence
is uninformative and it belongs in neither bucket. I predict at least 5 of the 30
grammars have warm frontiers short of their file, and that the `untested` bucket
is ≥10% of the population that the two-valued test called artifact.

**P4 — verilog's 63,937 B damage figure does not move at all, and the 6,591 B
subtraction another lane is about to make would be wrong.** `standing.py` defines
`damage = size - built` off a single whole-file parse; `walls.py` prices `behind`
off the peel and says in `Depth.behind`'s own docstring that it is **not**
damage. The two numbers are different instruments over different runs, and 6,591
peel bytes were never inside 63,937 damage bytes. I predict the honest answer to
"what does this do to verilog" is *nothing to the baseline and everything to the
worklist*, and that I will find at least one place in the tree where the two are
already being mixed.

**P5 — `Wall.real` cannot be fixed with any predicate computable from the wall
alone.** State number, terminal shape, `FIRST(start)`, bracket-ness: all of them
are properties of the wall, and the artifact is a property of *the text the round
was handed*. So the fix is provenance carried forward by the instrument that
knows it, not a cleverer rule downstream. I predict the state-0 rule and
`owners.py`'s own independent copy of it (`w.endswith(" in state 0")`, line 486)
both go, and that the second copy is itself a `sole.py`-shaped defect nobody
filed.

**P6 — `walls.py warm` on all thirty will cost under an hour and at least three
grammars will not finish 400 rounds.** Swift took 21.7 s. I predict the corpus
run lands between 15 and 60 minutes and that verilog, haskell and kotlin are the
ones that stall or saturate early, i.e. exactly the rows where the frontier
correction matters most.

## What I am deliberately not predicting

Whether the re-priced board changes which lane should work next. That is the
output, and guessing it first is how a re-price becomes a number written to
match an expectation.

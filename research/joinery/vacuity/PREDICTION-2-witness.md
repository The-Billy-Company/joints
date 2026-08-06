# Prediction 2 - a board that knows which tree it read, and a pair no single arm can see

Written before any of it was measured. Two independent halves; scored in
`RESULT-4-witness.md` and `RESULT-5-pairs.md`.

## The setting

The previous lane named `standing.py`'s board as the instrument it trusted
least, on evidence its own check cannot produce: two controls four minutes
apart were each perfectly reproducible under `--twice` and disagreed by 63
standing points on scala. `--twice` asks *is this binary's board reproducible*.
It does not ask *is this board's tree the tree I think it is*, and on a tree ten
lanes edit those two questions have different answers.

The raw material for the second question already exists. `pin.py build` writes a
per-file manifest (`world.json`) beside every pin's record, and that manifest is
what let the previous lane name the two files separating its two controls. The
board does not carry it.

## Half one - the witness

**P1 - cost.** Recording a witness on every board costs under 5% of a board
run's wall time, and under 10 KB in the saved JSON. The manifest is ~90 files;
digesting them is milliseconds, and for a *pinned* binary it is a single
`world.json` read and costs nothing at all. If this is wrong - if it is
perceptibly expensive - the design is wrong, because a check people skip is a
check that does not exist.

**P2 - the historical pins.** The brief says historical pins cannot be
retrofitted and not to try. I predict a **partial** contradiction: `world.json`
predates today's board work, so pins minted since it landed *can* be judged
against each other by reconstructing a witness from the pin at read time. What
genuinely cannot be retrofitted is a witness for a *saved board*, because the
tree the board read is not recoverable from the numbers. So I expect
`aud-live`, `aud-live2` and `aud-now` - the three controls that disagreed - to
be judgeable today, and I expect the gate to name the files separating them.

**P3 - the strict/loose crux.** The distinction the brief calls the crux - "my
own edit" versus "a sibling landed something" - cannot be drawn by *who* wrote
a file, which nothing records. It can be drawn by two facts that are on disk:
whether the lane **claimed** the file (`--mine`), and whether the file can
change the product binary at all (`stamp.builds`, which already excludes
`*_test.zig` for exactly this reason). I predict the honest rule is:

- unclaimed **and** build-bearing -> refuse; this is the latex case verbatim
- unclaimed and not build-bearing -> warn; a sibling's test edit cannot have
  moved a number on this board
- claimed -> declared, whatever it is

and that `--mine` has to accept a **prefix or a glob**, not just a path,
because a real lane's change is `src/press/` and not one file. Spelling
fourteen paths to run one comparison is the loose direction arriving by the
back door - nobody will do it, so nobody will claim anything, so everything
will refuse and the flag will come off.

**P4 - no lane breaks the day this lands.** Every board saved before today
carries no witness, so every `--against` against an existing file must degrade
to a warning rather than a refusal. The gate should switch itself on as new
boards are saved, with no flag and no flag day. If this needs a flag, I got the
default wrong.

## Half two - the pair

The known case: scala's 79.4% is two seatings cooperating, and with either
ablated scala reads identically on both trees to the byte - both of its own
isolation arms report a 12,733-byte regression as zero.

**P5 - the powerset does not need running.** Fourteen rows is 16,369 subsets of
size >= 2, and nearly all of them are incoherent: a row can only change a
grammar it could seat, and `seated()` requires every terminal the row names to
resolve in that grammar. So candidacy is decidable from the roster and the
grammars' `externals` alone, with no build. I predict the fourteen rows
partition into candidate sets small enough that **fewer than ten** multi-row
subsets are worth testing, and that the falsifier - every grammar a row was
*measured* to move must be a grammar it is a candidate for - holds for all
fourteen.

**P6 - the union arm has already answered it.** If each grammar's candidate set
is exactly the rows that reach it, then the union arm (all fourteen removed,
already pinned as `aud-iso`) restricted to grammar g *is* g's own full-subset
arm, because removing rows that cannot reach g cannot move g. If that holds,
every pair is already on disk and the answer costs one board run. I predict it
holds, and I predict I will not believe it until a genuine two-row arm is built
for at least one grammar and matches the union to the byte.

**P7 - scala is not the only one.** Five grammars carry two rows apiece on my
reading of arms.json (scala, kotlin, julia, elixir, swift). I predict **at
least two** show a materially non-additive pair - the joint ablation differing
from the sum of the two singles by more than 1,000 bytes - and I specifically
expect **swift** to be one, because `multiline_comment/.marrow/.swift_block`
moved *nothing at all* on its own arm, which is the exact signature of a row
whose contribution is only visible beside another. I predict **julia** is
additive, because its two rows are a quoted-content family and a glued-marker
cast that answer different bytes.

**P8 - the shape to report.** "Cooperating" needs a definition that is not a
vibe. Mine, fixed before the numbers: with `worth(r) = D({r}) - D(none)` and
`joint(S) = D(S) - D(none)`, the residual `joint(S) - sum worth(r)` is what
single-row ablation cannot see. A grammar is **cooperating** when that residual
exceeds 1,000 bytes, and **invisible** - the bad case, the one with no
attributable owner - when every member's `worth` is zero and the joint is not.
I predict at least one invisible pair and I predict it is swift.

## What would falsify each

| # | Falsified by |
|---|---|
| P1 | a board run measurably slower, or a JSON that grew by more than 10 KB |
| P2 | `still against` unable to judge the three retained controls |
| P3 | a rule that refuses a comparison nobody would call broken, or clears the latex case |
| P4 | any existing saved board that now exits non-zero on `--against` |
| P5 | a row measured to move a grammar it is not a candidate for |
| P6 | a built two-row arm disagreeing with the union arm on its own grammar |
| P7 | all five pairs additive, or the non-additive one not being swift |
| P8 | no invisible pair anywhere, making the class hypothetical |

# Prediction 3 — the family re-taken with an oracle in every arm

Written before a single arm of this sweep was built. `RESULT-5-blindness.md`
established that all nineteen arms of the `vacuity` family read `square 0`, so
the "fourteen rows, no collateral" clearance was taken on `damage` alone. This
lane re-takes the same population — base, fourteen singles, five pairs, the
union arm — with `standing.py --audit` paid inside each arm's own work dir.

Sign convention used throughout, because the two published tables use opposite
ones and the confusion is load-bearing: **positive worth means the seating is
doing good.** On `damage` that is `damage(arm) − damage(base)`; on `square` it
is `square(base) − square(arm)`.

## What I expect

**P1 — the clearance survives, and for a structural reason rather than luck.**
No arm moves a *second* grammar's `square` by a single byte. `seated()` refuses
a whole cast unless the grammar declares every terminal the row names, and
`ablate.py guests` shows all fourteen candidate sets are a single grammar; a
grammar outside the set cannot lex differently, so its forest is identical and
`square` is a function of the forest. **Falsifier:** any non-owner grammar whose
`square` differs between an arm and the base.

**P2 — and the one way P1 dies that is not collateral.** If a non-owner grammar
does move, I expect it to move in *more than one arm at once*, which is the tell
that a sibling landed a press or tree-sitter change mid-sweep rather than that a
row reached sideways. I will check that shape before reading any single move as
collateral.

**P3 — every row's `square` worth is ≥ 0, and exactly one is exactly 0.** The
zero is swift's row 3 (`multiline_comment/.marrow/.swift_block`), because
`Chunked.swift` contains no `/*` — the board cannot see that row at all, on any
column, and `consort/RESULT-2-swift.md` already established the row is alive on
the specimen tier.

**P4 — `square` is silent where `damage` is loud, on at least two rows.**
|square worth| < 100 while |damage worth| > 1,000. Named: **row 1, haskell**,
whose whole file carries **5** square bytes on the base board — there is nothing
there for the row to move, while its `damage` worth is ~9,192. A "no collateral"
family that scored haskell on `damage` was scoring the one grammar whose
agreement with tree-sitter is already annihilated.

**P5 — at least two rows show `square` worth more than 2× their `damage`
worth**, and they are comment/extra rows. `damage` counts a misread comment as
structure and a correct one as an orphan, so every `marrow` row should be
under-priced by `damage` in a known direction. ocaml's row 5 is the proven case
(−721 `damage`, +448 `square`); I expect scala's row 4 (+2,407 vs +6,536,
already 2.7×) to hold and one of latex row 10 / elixir row 6 / julia row 7 to
join them.

**P6 — kotlin's pair is a ceiling, not a coupling, exactly like scala's.** Each
kotlin row alone costs **more than 85%** of kotlin's 35,324 square, so the two
solos sum past the ceiling and the `square` residual is strongly positive
(> +10,000) where the `damage` residual is −20,288. Two rows that each destroy
nearly all of a quantity cannot also sum.

**P7 — at least one pair that reads `additive` on `damage` does not on
`square`.** julia `{7,8}` (+163) and elixir `{6,13}` (−177) are additive on
`damage`; julia's two rows both cost most of julia's 24,382 square, so I expect
julia's `square` residual to exceed 1,000. If both stay additive, the ceiling
story is scala's and kotlin's alone and P6 is weaker than it reads.

**P8 — the union arm loses between 150,000 and 230,000 of the base board's
311,540 square, and no tenth grammar moves.** php alone carries 67,845 square
against a base `damage` of 0, so the nine owners dominate the total.

**P9 — `crooked −335` reproduces on the row-4 arm**, and negative buckets appear
on **one to three** arms in the whole sweep, all of them with `roots > 500`. The
mechanism named in `RESULT-6-scala.md` is a soft attribution that runs out of
room on a shredded parse, so it should track shredding and nothing else.

**P10 — the blindness reaches at least eight other published conclusions**, and
at least three of them are about a comment, docstring or other declared extra —
the class where `damage`'s bias has a known direction and could flip a sign
rather than merely resize it.

## What would make me wrong in the expensive way

The reading I am most likely to get wrong is P1, and not by finding collateral —
by finding a *spurious* move and reporting it as collateral. Twenty-one arms
each running a four-minute oracle sweep is roughly half an hour of wall clock on
a tree ten lanes are editing, and the oracle's own identity (`bench()`, the
tree-sitter sources) is a property of the repo rather than of the arm. P2 is the
check that separates those two stories, and it is the only reason I am willing
to read a single-arm move as a fact about a row.

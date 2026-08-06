# Prediction 4 — working the 116, written before a page was edited

`RESULT-9-reach.md` counted the population and ranked it. This lane's job is to
work the ranking: decide **holds** / **needs re-pricing** / **overturned** for
each page, correct in place, and lead with what got worse rather than with the
pages that under-priced their own wins.

Everything below was written after reading `TESTING.md`, `RESULT-8-sighted.md`
and `RESULT-9-reach.md`, and **before opening any page below rank 3**. Scored at
the foot of `RESULT-10-record.md`.

## The population, as I expect to find it

`onlydamage.py` reads **113 of 354** tonight where `RESULT-9` read 116 of 347.
So seven pages landed and the blind count fell by three in the ~30 minutes
between the two runs, which is already the answer to the stability question and
I want it on the record before I confirm it.

| outcome | pages | why |
|---|---:|---|
| **holds** | ~95 | below rank 8 a page makes 0–2 comparisons; a sighted number resizes it and leaves the verdict standing |
| **needs re-pricing** | ~14 | the top ten plus the changelog fragments that carry one arm's worth |
| **overturned** | ~4 | a verdict a sighted reading contradicts outright |

## P1 — the overturns are elixir's, and there are at least two

Elixir is the only grammar on the board that reads `damage 0` while deriving 48%
of its file under different parents. Any page that reads elixir as finished
because it stands at 100% is not mis-sized, it is **wrong**. I predict at least
two pages state that, and that `bench.report.md`'s `standing` table is one.

## P2 — verilog holds and re-points; its changelog fragment overturns

`verilog/RESULT-1-wall.md` keeps its headline (the trap is real, and larger than
advertised) and gains a re-pointing: the 32,193 bytes verilog does build are
**7.9% square**. The fragment that prices two constructs at a fifth of the
board's largest `damage` is the one that cannot survive, because "worth 11,529
bytes of `built`" on a grammar at 7.9% square is a claim about volume presented
as a claim about correctness.

## P3 — haskell is an overturn and not a re-pricing

haskell's whole board `square` is **5 bytes**. A page pricing a haskell seating
at +9,168 is not 1,834× optimistic about a real win; it is measuring a grammar
with no agreement left to move. I predict at least one page's verdict falls on
that alone, and that it is *not* one of the top three (which are verilog, elixir
and kotlin).

## P4 — three pages under-price their own win by more than 2×

Named before I look: `interior/RESULT-2-board.md` (php's string interior, 7.7×),
`orphan/RESULT-2-wall.md` (kotlin's `_string_start`, priced at 20,728 `built`
against +27,143 `square`) and `semi/RESULT-2-seated.md` (already known, 18× on
elixir's row). I predict all three **hold** and all three get a larger number.

## P5 — the `damage = 0` fix cannot be finished by me

The right fix is a column or a verdict the board itself prints, and the board is
`tool/rack.py` + `tool/standing.py`, both held tonight. I predict I ship the
wording fix — one **name** for the state, used identically everywhere it appears
— plus a read-only survey of my own, and hand the board change to the rack lane
with the exact shape it should take. A note on a page is weaker than a board that
cannot say it, and I expect to be able to prove that and not to fix it.

## P6 — the 116 regrows, and the upstream fix is a gate not a sweep

`onlydamage.py` is a *sweep*: it says which pages are blind after they are
written. Nothing refuses a new one. I predict the count is back above 116 within
a week of tonight unless a gate lands, and that the gate is cheap because the
classifier already exists — it is `onlydamage.py` with a ceiling and an exit
code, which is the same shape `walls.py gate` already has on this tree.

## P7 — one page will have been corrected under me while I worked

Ten lanes share this tree. I predict at least one page I open has moved since
`onlydamage.py` classified it, and that I find it by re-running the sweep at the
end rather than by remembering.

## What I am not going to be able to say

Anything resting on `crooked`. It borrows from `unframed`, six rows are
understated and three arms go negative (`HANDOFF-crooked.md`). Every page whose
conclusion rests on it gets marked **pending that repair** rather than corrected
twice — which means verilog's 13,128 and elixir's 22,089 are quoted here as
*context for a `square` reading*, never as the load-bearing number.

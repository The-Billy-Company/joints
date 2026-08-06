`residue.py`'s `none` was the largest bucket in the residue - **1,288 of the
twelve grammars' refusals under `--mend=fell`** - and it was not a measurement.
It was the residual: whatever was left when four positive tests failed. The
claim it printed is universal, *no literal terminal exists that could stand for
this refused external*, and nothing in the runtime ever asserted it.

The runtime could not have. `Gather.follows` returned a bool, and it returns
false for five different reasons: the table has an `err` cell, the walk hit the
end column, the walk crossed a cell the author declared ambiguous, the `climb`
overlay filled, or `chase` ran out. Two of those are the table answering and
three are the walk giving up, and by the time `supply` had looped over every
literal the difference was gone. Its own closure check read `0` on all 24 rows
and could not have read anything else - it summed the counter it had just
filled, so a bucket that was wrong and a bucket that was right closed
identically.

`follows` now returns `Ahead.Says`, and `Ahead` records which wall a walk hit
in a `Hazy` field beside the `unsure` that carries it. Every arm behaves exactly
as before - each non-`yes` is still a no, no repair moved, and the corpus proves
it: the `+3,124` this lane's sibling measured comes back byte-identical, all
three components (sql `3,437 -> 3,718`, swift `11,172 -> 12,346`, verilog
`8,087 -> 9,756`). `none` is now reported only when **every** literal reached a
table verdict, and `forked` / `climbed` / `chased` name the wall when one did
not. One untellable candidate out of two hundred disqualifies the claim, because
the claim is about all of them.

The split, twelve grammars, `--mend=fell`, tree `f7ba40004+144`:

**959 of the 1,288 (74.5%) are honest misses. 329 (25.5%) are the walk
declining** - and all 329 are `forked`, not a budget. `climbed` and `chased` are
**0 on all thirty grammars in both arms**. haskell owns 1,263 of the 1,288 and
splits 936 / 327 the same way.

So the brief's hypothesis is refuted in a useful direction. Nobody needs to
raise `climb` or `chase`; the numbers there are real zeros, proved by building
the same tree at `climb=1, chase=2`, where the two columns light up at **45**
and **968**. What the 329 want is a walk that can carry two readings across a
declared fork, which is `absorb`'s machinery and a different brief from the 959.

Three more things fell out of looking:

`supplied` has the same weakness pointing the other way, and the runtime now
says so on a second `unsure (...)` line: a supply made while some *other*
candidate was untellable is the one literal that said yes, not provably the only
one that would have. **1,468 refusals under `fell` had at least one untellable
candidate.** `spurned` returns mid-loop and has no count - a real hole, left
visible rather than papered.

`adrift` was the same disease in the column that was supposed to catch it. It
was `cut + gave - sum(seen.values())`, which is identically zero whenever the
counter is complete, and the counter is always complete because the same
function fills it. It also hardcoded the reason list it summed, so the day the
runtime grew three words it lost 50 of bash's 90 deletions into a check whose
own output column could not show it. It is now derived from the other side -
scars minus the reasons this file knows by name - so it is signed, it can go
either way, and `--selftest` shows it reading `+40` where the old form read
`+0`.

`stray`, `ground`, `unseated`, `fuse` and `spurned` audited clean. `stray` was
this same bug and a sibling already fixed it: `blame` asks a second time with
the state filter off, so a byte that lexes fine but that no live state wants is
no longer filed as a byte no lexer could read.

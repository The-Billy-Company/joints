The survey's `stranded` verdict - the wall cannot be owned from the wall's own
state - held 22,179 bytes across 22 items, and by fold body the top three carry
88%. They were read as roughly three grammar problems worth a lane. **21,350 of
those bytes, 96.3%, are text that is not a program**, and the mechanism is the
measuring instrument rather than any grammar:

| population | bytes | share |
|---|---:|---:|
| the cold peel's own cut | 21,350 | 96.3% |
| survives a peel that keeps its prefix | 611 | 2.8% |
| in grammars nobody warm-peeled | 218 | 1.0% |

`tool/walls.py` says it plainly - resuming "means parsing the remaining bytes
from a clean start, so each round begins in state 0". `Chunked.swift` reads
1,492 bytes, walls at `)` in state 141 with three braces still open, and the
tail handed to the parser next opens with four orphan closers. Each `}` is
refused at whatever file-level state that fragment's own prefix reached, so
**the state number is only a count of how many statements came first**. Three
hand-built witnesses reproduce all three states: a bare `}` walls in state 0,
one statement then `}` walls in 681, two statements then `}` walls in 1166, and
three saturates. `Wall.real` is `not shadow and state != 0`, which catches the
first and misses the next two - the same artifact with a statement in front of
it, priced as construct damage at 9,160 and 3,896 bytes.

`stranded` was the right label and was doing its job. It says the state cannot
own this, and for 96.3% of the bytes the reason is that there is no construct to
own.

**The discriminator is deliberately not a state number.** A rule about state 0,
or about closers, would be the existing exclusion restated in a way that cannot
fail. `research/joinery/owners/cut.py` asks a different peel: `walls.py warm`
never restarts, so it always holds the real accumulated prefix, and a wall it
never reaches in 400 rounds needs the state-0 restart to exist. It says no often
enough to be worth believing - swift's `) in state 141` and verilog's `; in
state 701` and `: in state 701` all survive - and prints an anti-vacuity column,
because a grammar whose warm set shares no wall with its cold set is a broken
reader and not a finding.

What survives is small and honest. Swift's real wall is `) in state 141`, 95
bytes, genuinely `stranded`: state 141 admits four terminals of 224 and arrives
on `user_type` from 196 states, and the single reduce lookahead that looks like
merge damage is not - `FOLLOW(_navigable_type_expression)` really is
`{_dot_custom}`. The table is right; the mistake is folding to `user_type`
several constructs earlier, which is what `stranded` means. Verilog's eight
`_identifier` walls are 6,591 bytes and **not one reduce-reduce family**: 6,477
of them, 98.3%, are the `macro_text` path, and only one of the eight states
holds more than one fold.

**Nothing about this moved the board, and that is on purpose.** These bytes were
never in the workable 14.1%; the change is that they stop being an open
question, and no lane should be sized against them. The unowned population -
73.7% of damage - has never been given this test, uses the same too-narrow
`Wall.real` predicate, and `cut.py` answers it per grammar for the price of one
warm peel. Two of thirty grammars are done. Re-pricing another lane's instrument
on this lane's verdict is the failure the dossier is about.

**Two predictions failed and one passed for a reason it should not have.** The
swift row was predicted `scanner` on an unseated `_semi` external; swift does
declare `_implicit_semi` and `_explicit_semi` with no rule body and our lexer
does emit them, all of it true and none of it the mechanism. The bar "≥60% of
bytes get a named owner" passed at 96.3% on a verdict, `peel`, that was not among
the categories the bar was written against. And the fold body - the axis the
whole population had been organised by - turned out to be the one part of each
row carrying no information at all.

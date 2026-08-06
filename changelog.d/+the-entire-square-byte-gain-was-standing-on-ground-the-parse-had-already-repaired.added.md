`rack.py` scores every built byte into one bucket and says nothing about the
ground it stood on. A byte it calls `square` where the parse read straight
through is a claim about the grammar; the same byte downstream of a deletion is
a claim about the grammar *and* the repair that got the parse there. Every
`square` figure anybody has quoted is a blend of the two in a ratio nobody could
state. `RESULT-2-untested.md` bounded it at **19.9-23.0%** off `built` alone and
said so.

`research/joinery/scars/ground.py` closes the join. It is **not a sixth price**
and it does not touch `rack.py`, which is a lane's live file and refuses across
a rule change at exit 4. It calls `rack.survey` verbatim, three times, over the
same `plumb.Read` with only the *judged byte range* narrowed - `rack.twice`'s
trick pointed at a different axis. Same forest, same oracle tree, same frames,
same renames, one classification, partitioned rather than re-decided.

Which is what makes it checkable, and the check is the point. A window is
`(judge_from, judge_to, root_start, root_end)`; the clip narrows the first pair
and never the second, because `unframed` walks the set of root extents to find
the seams between adjacent roots and dropping one invents a seam that is not
there. So a window outside the slice is kept with an *empty* judged range. The
two halves must then add back up to the whole row on all 19 byte columns, by
three walks that never see each other's answers - and they do, on all thirty
rows. `--selftest` builds the wrong clip on purpose and shows the check catching
it, because a join that cannot fail is not evidence about a join.

The board, thirty rows, binary-default mend, tree `f7ba40004+144`:

**67,231 of 313,469 square bytes (21.4%) stand at or past the first repair in
their file.** That lands inside the published interval rather than above it -
but the board figure is the wrong denominator and that is the finding. Seventeen
grammars never repair at all and contribute 200,221 clean square bytes. **Among
the twelve rows that repair, the share is 59.4%**, and it is 100% on haskell and
ruby, 99.5% on kotlin, 93.2% on ocaml, 85.3% on verilog.

Then the number the interval was really about. Splitting *both arms* of the
supply experiment at one common cut - same binary, one `--no-supply` apart -
locates the `+3,124` itself:

| | ctl `square` | arm `square` | Δ | Δ clean | Δ scarred |
|---|---:|---:|---:|---:|---:|
| sql | 3,437 | 3,718 | +281 | +9 | +272 |
| swift | 11,172 | 12,346 | +1,174 | +0 | +1,174 |
| verilog | 8,087 | 9,756 | +1,669 | +0 | +1,669 |
| | 22,696 | 25,820 | **+3,124** | **+9** | **+3,115** |

**+3,115 of the +3,124 (99.7%) landed at or past the first repair.** The
authoring lane guessed the share leaned larger than its 23% bound. It does, by a
great deal more than it expected.

Half of that is structural and this file says so rather than banking it: the two
arms are byte-identical up to the first refusal, and the first refusal is where
the first repair lands in both - `ctl 1st` and `arm 1st` come back 2,907/2,907,
24,582/24,582, 3,712/3,710 - so the movement *cannot* be upstream of the cut
except through an extent change, which is exactly what sql's `+9` is.

The part that is not structural is the enrichment, and it is where the result
lives. Compare each gain against how much of that grammar's `built` is
downstream at all: verilog is 97.1% downstream and gains 100% there, a ratio of
1.03 and no information. **swift is 6.0% downstream and gains 100.0% there - a
16.7x concentration**, 1,174 square bytes landing in a repaired tail that is one
sixteenth of the file. sql is 1.8x. So the honest reading of the +3,124 is that
verilog's 1,669 is a whole-file effect the cut cannot resolve, and swift's 1,174
is a genuinely local one standing on repaired ground.

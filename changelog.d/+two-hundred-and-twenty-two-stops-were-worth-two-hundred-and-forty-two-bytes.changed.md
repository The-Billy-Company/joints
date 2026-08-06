`walls.py`'s peel counted how often it met each wall and the board read that as
cost. They are not the same number and one of them is the one anybody cares
about. On SQL the wall a recurrence ordering leads with takes **222 stops and is
worth 242 bytes**; the wall actually worth ranking carries **2,839 bytes on 10
stops** - 11.7x the file on 4.5% of the recurrence. The verilog lane had already
measured the same decoupling twice on `picorv32.v` and handed it over as the
obvious next lane: one state leads with nine statements stopped, a different state
leads with one statement and 16,289 bytes, and state 2394 takes seven of nine
warm-only walls while costing **-167 bytes** and landing twelfth of thirteen.

So the peel now prices itself. Each wall owns the file between where it stands and
where the next wall takes over, and `board` ranks by that. Recurrence stays a
column, because warm behaviour is real information - it just stops being the
ranking. The disagreement prints on every run rather than waiting to be
rediscovered: **bytes and recurrence name a different worst wall in 3 of 17
walled grammars** (sql, haskell, verilog), each with both orderings side by side.

The price is a **partition**, which is the part that could have been faked and is
the reason it can be believed: `prefix + every wall's bytes + unpeeled == size`,
printed per grammar every run, and a grammar where it fails prints `UNBALANCED`
instead of printing a price. It holds to the byte on **30 of 30**. Overlapping the
segments, or handing one wall the whole remainder, would have made every wall look
expensive and the ordering would still have looked decisive.

Three of 17 is well under what was predicted (six of eighteen), and the reason
belongs here rather than in a footnote: the corpus specimens are `ledger.*` and
C's is **1,444 bytes**, where every wall is cheap and two orderings have no room
to diverge. The verilog disagreement was found on a real 40 KB file. So the low
rate is a fact about the specimens, not evidence that recurrence was an adequate
proxy.

Pricing the families also found a crash in the `board` verb's residue line.
`family()` deliberately returns None on a shape no row claims - that is what makes
the classifier falsifiable instead of total - and the residue line indexed the
lane table with it, so `board` died on **exactly the surprise the classifier
exists to be able to report**. The residue is now the `unassigned` lane plus the
unplaced, printed apart: 38 walls / 32,641 B unassigned, of which **4 walls /
105 B** no row claims at all.

One thing the partition surfaced on its own: the cold peel resumes in **state 0**,
so some walls are the peel's own resume artifact rather than a construct the
grammar cannot express. Those get a `state0` column, **printed rather than netted
out** - the peel's reach is what is in question there, and a column a reader can
subtract is honest where a corrected total nobody can check is not. 24 of the
corpus's 42 grammar gaps turn out to be state-0 walls, and the gap list marks
them so.

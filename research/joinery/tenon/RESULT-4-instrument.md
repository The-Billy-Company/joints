# Result 4 — the instrument I trust least, and three demonstrations

`tool/rack.py`. Not because it is bad — it found 39,110 bytes in a class the
previous instrument structurally could not see, and it prices its own softness
in a way nothing else here does. Because it is the one whose number I could not
reproduce, and because two of the three failures below are ones it cannot see
from inside itself.

## Demonstration 1 — it charges 8,334 bytes where nobody disputes a parent

`rack`'s spine rung is `(name, named, start, end)`, and two rungs differing in
any of the four part the spines. Three of those four are derivation. **The
fourth is not.** A parent that adopts the right child and records an extent
stopping short of it is the same derivation with a bad number on one node, and
every byte under that node is charged as though the parent were wrong.

`research/joinery/tenon/extent.py` re-sorts `rack`'s own charge — same windows,
same `unjudged` rule, same rename excuse, `rack`'s functions called by name so
the two cannot drift — into `span` (every rung agrees on name, order and left
edge; some rung's right edge moved) and `shape` (a parent genuinely in
dispute). It changes no total; the `crooked` column must equal `rack`'s row for
row, and it does on all 27 adjudicable grammars.

```
grammar   crooked  span  soft   shape   soft  DISPUTED
toml           29    18     2      11     11         0
latex        1077  1035    16      42      0        42
zig            10     8     0       2      0         2
swift        8807  3626   423    5181    340      4841
scala        9087  1499   194    7588   6955       633
ruby          145   139    15       6      0         6
elixir      17734  1873     4   15861     70     15791
TOTAL       83169  8334   654   74835  22396      52439
```

toml is 62% span. latex is 96% span. zig is 80%. Those three rows are not
reports of misread structure at all.

The correction to the headline: `rack` defends **60,138 bytes**, having
subtracted extras placement. Applying its own soft test at its own granularity
to the two halves, **7,699 of those 60,138 (12.8%) are a right parent whose
right edge moved**. The number I would defend is **52,439 bytes, 13.63% of
`built`** — of 384,715 built, 349,928 adjudicable (34,687 over verilog and sql
have no oracle verdict at all), and 526,798 corpus, so 15.0% of adjudicable and
10.0% of corpus.

This is not a small correction and `rack soft` cannot reach it. Its own
docstring says why: the bytes are not the extra's, they are the siblings'.

## Demonstration 2 — it stamps one of the two trees it compares

`rack run scala --json`, stamp block, verbatim keys:

```
binary build built commit dirty drift live moved moved_at newest source stale told tree when
```

Fourteen fields, all fourteen about outliner: which binary, which tree hash,
which commit, how dirty, whether it drifted, whether it was told. Every number
`rack` prints is a comparison of two trees, and **the second tree is
unattributed** — no tree-sitter version, no grammar revision, no dylib hash, no
seat.

That is not academic here. The oracle libraries are built into
`.local/differential/seat/$OUTLINER_LANE/lib/`, and `.local/differential/lang/`
underneath is shared by every lane on this machine. During this session:

```
.local/differential/lib/python.dylib   Aug 5 16:58
.local/differential/lib/go.dylib       Aug 5 16:59
.local/differential/seat/tenon/lib/scala.dylib   Aug 5 17:35
```

Three oracle halves rebuilt mid-session, by lanes that are not me, while I was
measuring. The pin caught the binary; nothing caught these.

**And I hit it.** `extent.py` read scala's crooked bytes at **1,278** in one run
and **9,087** in the next, from the same pinned binary, the same corpus file,
and the same unedited script — a 7.1× swing, 7,809 bytes, with `rack`'s stamp
byte-identical across both. I could not reproduce the low reading afterwards and
I am not going to claim I proved the cause; the dylib mtime above is
circumstantial and that is all it is. What is *not* circumstantial is that
nothing in either instrument's output would have told me the two runs used
different oracles, and both numbers would have been quotable.

The falsifiable test for whoever picks this up: record the sha256 of each
`lib/*.dylib` and the `tree-sitter --version` into the stamp, then re-run scala
under two seats built from different `lang/` states. If the numbers move with
the hash, the stamp is the fix.

## Demonstration 3 — the flattering number I found inside my own instrument

`extent.py`'s first cut reported `TOTAL … 38636 DISPUTED` and closed with *"that
is the number this lane would defend"*. It was wrong, and wrong in the
flattering direction — it made the corrected figure look 27% smaller than it is.

`rack soft` asks its question **per run**: it merges adjacent cuts sharing a
parting rung and asks whether the whole run is blank or whether the run's
parting rung is a declared extra. My first cut asked **per cut**. Inside a
single 1,815-byte racked run of elixir, every space and newline between two
tokens is its own cut, so the same words counted every interior space as soft:

```
                       rack soft   extent.py, first cut
  elixir soft bytes           74                  4,879
```

66× too soft, on the largest row on the board, with no assertion anywhere
capable of noticing — the two files agreed exactly on `crooked` the whole time,
which is the check I had built and passed.

The fix is in `resort()`: runs are now accumulated on `survey`'s own key with
the span/shape class appended, so a run never straddles a class, and the soft
test is asked once per run. `extent.py`'s soft total is now 23,050 against
`rack soft`'s 23,031 — 19 bytes apart, the difference being runs the class
field splits in two — so the columns are addable to `rack`'s on purpose rather
than by coincidence.

I state this one first when quoting any figure above, because it is exactly the
failure I was sent to look for in someone else's instrument and I reproduced it
in mine within an hour.

## What I would not change about it

`rack --square`, and `rack soft`. The first is the only guard in this tree that
catches a change buying `built` and paying structure, and it prints `THE GUARD
CANNOT RUN HERE` rather than reading silence as agreement. The second is an
instrument volunteering the part of its own headline it will not defend, which
is rarer here than it should be. Both of those are why it is worth correcting
rather than replacing.

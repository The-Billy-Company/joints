`settle.zig` was 1,139 lines against a rule that says 500, and it got there
honestly: it was 1,022 at HEAD and the composite-literal fix added 117, of which
93 are the argument for why an unranked fold may order an authored reading and
not erase it. That prose is the most valuable thing in the file, so the split had
to carry it rather than route around it.

There is no escape hatch here. Billy's monorepo has a marker-plus-registry route
for a file that genuinely shouldn't divide; this package's CONTRIBUTING just says
files stay under 500 lines, and `tool/sole.py` - the only shape gate in CI - reads
`tool/*.py` and says so out loud, so nothing was going to catch this but a reader.
So it splits, and the seam was already written down. The file's own doc comment
lays out a ladder of four rungs consulted in the order the author's declarations
were meant to be, and that list is the folder:

  `column.zig`       rung 1, reduction against reduction inside one column
  `ladder.zig`       rungs 2 and 3, read against fold by precedence then side
  `attribution.zig`  rung 4, whose ambiguity is left when both declined
  `bench.zig`        the fixture the rungs are walked on, one state's row at a time
  `forks.zig`        not settling at all - the index a parse loop reads off a verdict
  `settle.zig`       the record and the entry point

249, 107, 211, 177, 185 and 392 lines. Nothing was rewritten and no name was
prefixed with the file it came from: rung 1 is a *column* of a state and rung 4
is *attribution*, which is what they were already called in the prose.

One thing genuinely moved rather than relocating. `Bench` carried rung 4's whole
apparatus as six of its own fields - a second closure, a reverse index, and four
lists - and splitting on the ladder would have left `bench.zig` holding a rung
that isn't its own. `Attribution` is now a type with those six fields and a
five-call surface (`open`, `note`, `of`, `named`, plus init and deinit), and
`Bench` holds one field where it held six. The traced-back attribution logic is
byte-identical; what changed is that it is behind an interface instead of
in scope.

`Conflict` and `Frayed` stayed in `settle.zig` on purpose. `impose`'s comptime
ledger reaches them as `settle.Conflict.Class` and `settle.Frayed`, and a folio's
on-disk format is those enums' ordinals, so moving them one import further away
would have made the guard's own address a thing that drifts.

**What proves it.** A folio's sha256 does not, and finding that out was worth the
detour. Minting cpp twice with the *same* binary gives 726,344 bytes one run and
726,328 the next, because the `lexicon` section - irregex's compiled program - is
not reproducible; every other section is, and all 346 differing byte runs sit at
or past the lexicon's start offset plus the two header fields describing it. A
lane that had trusted the hash would have read 11 of 30 folios as moved by a
relocation that moves nothing, which is the same genre of lie as the one that
nearly killed the composite-literal fix, pointing the other way.

So the comparison is the folio truncated at the lexicon, from past the header: the
action table, the interned rows and groups, `complete`, and the three sections a
settle change moves - `conflict`, `party`, `frayed`. Byte-exact over conflict
*contents*, which a section-count diff cannot see. **All 30 grammars identical,
every section count identical.** The oracle has teeth: flipping one comparison in
the moved `keener` - `a.value < b.value` to `>` - moves 17 grammars, every one of
them differing from byte 0.

The board agrees. Both arms re-measured with the same binary pair against the same
tree, 30 grammars x 18 columns including `verdict`, `nodes` and `leaves` because a
metric can improve by describing less: **540 cells, 0 moved**, `unbound 120,534 of
526,798`, standing 66.30%, whole 12, describes 97,280 nodes, buckets exact.
Pressing all 30 costs 8,613 ms against 8,618 ms; three paired runs came out
-1.6%, +0.2% and -0.1%, so the honest reading is that it is free and the spread is
the machine. scala, the slowest row at 1.33 s, is flat in all three.

The methodology hazard, since it cost an hour and would have been reported as a
finding: the payload comparison writes its two mints into fixed scratch
directories, and one of the runs proving the oracle has teeth left the *sabotaged*
binary's folios in one of them. A later stand-in comparison over those leftovers
read four grammars as moved, including c flipping from `press? on ,` to
`accepted, 1 root`, and the first plausible story for that was "the lexicon's
nondeterminism changes parse verdicts" - which would have been a much bigger claim
than this change. It was a stale directory. Minting each grammar six times with
each binary and comparing the *distributions* is what settled it: control and
treatment agree 6 of 6 on all four, and lexicon size varies 83,630 to 83,696 on
swift across eight mints with the verdict never moving. A scratch path reused
across a negative control is a trap worth naming.

Both load-bearing properties are proven rather than asserted.
`Conflict.Class.unwritten` is last, and reordering it ahead of `residual` still
fails the build at `impose.zig:103` naming both members - so the guard is watching
the moved enum, not a memory of it. And `spared` is still read before the second
`poll`, which deliberately cannot see it, and still recorded before the
`standing <= 1` return, which is the line that used to swallow these cells.

The instrument to distrust here is `zig build test`'s shard verdict. A shard went
red under 32-way contention and passed standalone 11-of-11; the pre-change capture
had two of those in the same run. And a `-Dtest-filter` that matches none of a
shard's tests exits 1, so a narrow filter reddens 31 of 32 shards and none of it
means anything.

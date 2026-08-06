`built` is the union of the spans of the top-level roots that have a child, and
`tops()` discards every indented row before it is computed. **Neither `standing`
nor `damage` has ever read a byte below the root frontier.** On a file one root
covers whole they read 100% and 0 regardless of the tree underneath: a child
outside its parent contributes its bytes exactly like a well-placed one, and so
do a child out of source order, a node reached twice, and a whole subtree hung
under the wrong parent.

That is not a bug in either column - it is what a frontier measurement is, and
coverage is worth measuring. It is a lie only when it is read as correctness,
and `17 of 30 grammars parse whole` reads as correctness.

**So the board carries the third axis rather than an asterisk.** A `shape`
column beside `stand` and `trued`, one word per row off `Quire.survey`: `tree`
when the walk liked the forest, `loose`/`disorde`/`torn` naming the worst class
when it did not, `void` when nothing was built, `unasked` when the binary handed
back no survey at all. The old ` · UNSOUND` row suffix is gone - it said the
same thing worse, and only when the answer was bad.

The headline is four tallies, and no fused number. Read on `pin-shapelane`
2026-08-06, binary `4c262974e`, oracle `d85e736fa` (30 attributed):

```
30 grammars · 17 reached whole (one root over every byte, no gap by construction)
              29 surveyed sound (every node reached once, inside its parent, in source order)
              16 agreed whole (`trued` 100% - the oracle defends every byte), over the 29 row(s) it judged
              16 whole on ALL THREE - coverage, shape and agreement are different questions and this is
                the only count that means what `17 parse whole` sounds like
```

**The hole is one row wide, and it is elixir.** 46,089 bytes, one root over all
of them, a forest that surveys sound, and a derivation the oracle rejects over
**22,089 bytes - 48% of the file**, against a `damage` of zero. Every other row
that reached whole survives both interior questions. So in magnitude the finding
is a documentation fix and I will say so plainly; in kind it is not, because
elixir is the row that proves nothing on the page could have told you. It is
also already the widest `crooked` row on the board, so the new count does not
discover it - it stops the headline from counting it as perfect.

Three assertions keep the axis from going quiet, all corpus-shaped, all three
red against the pre-contract binary (pin `sound`, `b9bd1cc19`):

- **the wiring** - every forest-building row carries a `surveyed` clause, or it
  is named as having cleared itself on an absence.
- **the corroboration** - the survey's node count off stderr equals the printer's
  line count off stdout, 109,717 either way, two independent readings of one
  parse. A walk that stopped early and a printer that dropped a subtree each
  break this and nothing else on the page notices either. It reads **VACUOUS**,
  not green, when no row answered.
- **the non-vacuity** - 109,717 nodes across 29 sound forests were actually put
  under the walk, so a fault had somewhere to be found.

`tool/README.md` gains the `sound.py` section it was owed and a `Three axes`
subsection under `standing.py`. The `-x` trap the toml dossier recorded - reading
the oracle through `tree-sitter parse -x` instead of `--cst`, where the XML
writes anonymous nodes without ranges and a `string` with two quote children
reads as childless - was checked across `tool/`: three files read `-x`, and all
three already answer for it. `differential.py` and `plumb.py` pair it with
`--cst` through `reconciled`, and `collate.py` repairs it from the grammar
instead, because `reconciled` refuses the CST on exactly the files in recovery
that verb exists for. `standing.py`'s own audit reaches the oracle through
`plumb`. Nothing to fix, which is worth writing down once so the next lane does
not check again.

# scars — making repairs visible, and finding out what that costs

A node in this parser's output does not say whether it was read as the author
wrote it or repaired into place. `research/joinery/reprice/` hit that wall,
named the missing capability, and left **18,146 B `untested`** rather than
resolve it in the direction that would have flattered its own re-price.

This lane built the capability — `outliner parse --scars`, one line per repair —
handed it to the peel, checked who else was reasoning from "a node covers this
byte", and put our repair surface beside tree-sitter's.

Read in this order:

| file | what it is |
|---|---|
| `PREDICTION-1-surface.md` | four predictions about the API shape and its cost, written after reading the runtime and before building anything |
| `PREDICTION-2-untested.md` | seven more about where the untested bytes fall, who else is blind, and tree-sitter |
| `RESULT-1-surface.md` | the surface, P1–P4 scored, and the field of mine that was a constant |
| `RESULT-2-untested.md` | the resolution, the board and rack, tree-sitter, P5–P11 scored, and the instrument I trust least |

## The headline

- **The untested category closed: 88,975 B → 0 B.** Of the peel's 97,742 B,
  **86,531 B (88.5%) is an instrument** and **11,211 B (11.5%) stands**. That is
  the direction that flatters the re-price, so it is published with both bounds:
  dispute the cascade call and the floor is 59,335 B; ask the question of a
  felling parse instead and it is 70,330 B.
- **The re-price's own 18,146 B could not be resolved.** Its labelling has
  swift refusing at byte 1492; today's binary reads to 24,582. The seat's
  self-check refuses rather than mapping across a tree that moved.
- **19.7% of the bytes under a node were deleted by a repair anyway** under
  `--mend=keep` — the hole `Cold.canopy` could not see, measured.
- **The board does not paper, because it parses `--mend=fell`.** Switch the
  policy and `built` gains 62,990 B, 81% of it over repaired-away bytes.
  27.9% of `built` (61.9% among mending grammars) is downstream of a repair;
  19.9–23.0% of `square` is.
- **Against tree-sitter: level on enumeration, ahead on attribution and
  localization, behind on insertion.** On verilog its `ERROR` nodes cover 100%
  of the file and ours cover 34%. It inserts 70 `MISSING` nodes corpus-wide and
  we cannot insert at all.
- **Twelve grammars we repair where tree-sitter derives clean** — 1,929 scars
  over 2,169 B that are our gap, not the file's, and were invisible before.

## The surface

```
scar 24582..24594 12B kept unexpected identifier in state 398, 122 heads, +3501 tokens
```

A side channel: `Quire.scars`, a sorted disjoint list parallel to the node array.
Not a node (a mend deletes; a node there would invent a parent for refused text
and move `built`), not an annotation (a scar sits *between* two subtrees), and
deliberately not spelled `[start, end)` so a reader matching node lines cannot
match it by accident. `--scars` replaces the tree on stdout.

## The files here

| file | what it does |
|---|---|
| `seat.py` | hands the peel the capability: reclassifies every wall from the repair sites, self-checks against the walls the board already knew, and prices its own judgement call from both sides. `--warm` compares one parse against a 400-round warm seat |
| `blind.py` | who else reasons from node coverage: `built` downstream of a repair, `built` papered over one, and the bound on `square` |
| `against.py` | our repair surface against tree-sitter's `ERROR` and `MISSING`, over the same thirty files |

Give each its own `OUTLINER_WORK`: two pinned binaries sharing one folio cache
both read whichever folio was written last, and that error is always flattering.

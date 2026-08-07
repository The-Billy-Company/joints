# Prediction 1 — the board that routes the other boards

Written before measuring anything beyond the baseline board I already hold
(`.local/lane-board/base.json`, pinned binary `.local/pin/kdocA`, `generation:
uniform`, `cache: kept 30`, totals `354,893 built + 56,766 orphan + 27,667
rubble + 87,472 spoil = 526,798`, `standing 67.3679%`, `unbound 115,139` — the
same numbers `research/joinery/orphan/` was taken against).

## What is not a prediction, and why saying so matters

The corrected ranking is **arithmetic on a board I have already taken**.
`size − built` is two columns the board already prints, subtracted. Writing it
down as a prediction and then "confirming" it would be theatre, and this lane
exists because an instrument flattered. So: the ranking is a computation, it is
reported as one, and the four things below are the things I have **not**
computed and could be wrong about.

The orphan mechanism is likewise not re-derived. `research/joinery/orphan/`
measured it; I am encoding it, not re-proving it.

---

## P1 — the mend count the board would have reached for is broken

I want `mends` on the board, because "one mend can cost 8,091 bytes" is one of
the three facts I was sent to make legible. The cheap way to get it is
`stamp.ask(tree=True)`, which already returns an `Outcome` carrying `mends` —
no second parse, no fifth reader.

Spot-checking eight grammars, it returns **0**.

`stamp.verdict()` takes *the last non-blank line* of stderr. On a grammar that
hits a wall the binary prints three lines, and the last is `inquest`'s owner
line, not the stop line:

```
joints: kotlin: blind to 8 externally scanned terminal(s)
joints: …/Maps.kt: unexpected (?:[^\r\n]*) at 270 in state 433, 419 roots, mended 142 over 142B
joints: kotlin: lexer on … [no stand-in for _string_start]: …
```

`MENDED` and `ROOTS` are searched over the verdict; `BLIND` and `UNSOUND` are
searched over the whole stderr. So the two that ride the *stop* line are lost
on exactly the rows that mended.

**Predicted:** over all thirty, `stamp.ask(tree=True).mends == 0` and
`.roots == 1` for **every** grammar the board scores at `roots > 1` — 18 of
them — while `.blind` and `.unsound` stay correct.

**Falsified by:** any walled grammar where `ask` returns the mend count
`research/joinery/orphan/gate.py` reads (kotlin 142, verilog 2,109, haskell
1,806, php 1 …).

**If it holds**, `tool/walls.py`'s `voice` — mends per distinct wall, the
number its own docstring calls "the bounded-tail-versus-second-project ratio" —
reads **0.0 for every walled grammar**, which is the reading that says every
tail is all depth and no repetition. That is the exact inversion of the truth
and it is the 22nd instrument. I do not own `tool/stamp.py`; I will name the
line and route it.

**And it decides my design.** If it holds I will not put `mends` on the board
at all — not because I cannot get it, but because every other column on the
board is a property of the *tree the board scored* and `mends` is a property of
a stderr line. `research/joinery/orphan/RESULT-2-wall.md` already flagged that
seam as the thing it trusted least in its own work. The gate gets expressed in
`roots` and `leaves` instead, which are measured off the same tree as `built`.

---

## P2 — bytes and share are different work orders and the board must print both

`damage = size − built` ranks by **where the most bytes are**. The board's
existing default sort — `standing` ascending — ranks by **which grammar is most
broken**. Both are legitimate and I expect them to disagree hard.

**Predicted:** the top five by `damage` and the top five by `1 − standing`
share **at most two** members.

**Falsified by:** four or more shared members — in which case `damage` is
mostly re-sorting what `standing` already said and is a smaller contribution
than I am claiming.

---

## P3 — the corrected ranking is a property of the tree, not of the pin

Every number above came from `.local/pin/kdocA`. The live `zig-out/bin/joints`
is a later build by an unrelated lane. My deliverable is a dispatch list, so it
had better not be a fact about one frozen binary.

**Predicted:** re-measured against the live binary, the top eight by `damage`
are the same eight grammars in the same order.

**Falsified by:** any membership change or any swap inside the top eight. A
swap would mean the dispatch list has to name its binary, which is a materially
weaker deliverable and worth knowing.

---

## P4 — the gate can be stated in the board's own columns, exactly and non-vacuously

`research/joinery/orphan/` states the clean case as *zero mends → zero orphan →
one root*, measured off stderr. I want it off the tree.

**Predicted, three parts:**

- **exact** — `leaves == 0` ⟺ `roots ≤ 1`, over all thirty. No row hands back
  one root with something loose, and none hands back many roots with nothing
  loose.
- **non-vacuous** — both sides are inhabited (≥1 row at `roots ≤ 1`, ≥1 row at
  `roots > 1`), so the biconditional is being asked of a real partition rather
  than passing over an empty set.
- **graded** — among rows with `roots > 1`, `damage / roots` spans at least
  **10×** between its widest and its narrowest. This is the third orphan fact
  turned into a guard that can still say *no*: if the count ever started
  pricing the bytes, the spread would collapse toward 1× and this reddens.

**Falsified by:** any row breaking the biconditional; an empty side; or a
spread under 10×.

The `roots ≤ 1` rather than `== 1` is deliberate. yaml builds no tree and hands
back **zero** roots, so `mends == 0` has two meanings — parsed whole, and
parsed nothing — and the stderr framing cannot tell them apart. The board's
`basis` column already can (`whole` versus `void`). If the biconditional holds
at `≤ 1` and fails at `== 1`, that is the finding.

---

## P5 — my own column is gameable, and I expect to measure that it is

Six lanes have found a flattering number inside their own fix. `damage` is
`size − built`, so it inherits every watermark `built` has, and the board's own
docstring names the worst one: on `picorv32.v`, `--mend=keep` scores 59.3%
standing against `fell`'s 32.5% while printing 10,256 nodes against 17,997 —
**three columns improved by describing 43% less.**

**Predicted:** re-measuring verilog under `--mend=keep`, `damage` falls by at
least 25,000 bytes while `describes` falls by at least 5,000 nodes.

**Falsified by:** `damage` not falling, or falling while `describes` holds or
rises — either of which would mean `damage` is *less* gameable than `built`,
which I would not believe without looking twice.

**If it holds**, `damage` is exactly as corruptible as the headline it is the
complement of, and the board has to print `describes` and `leaves` beside it
rather than in a footer a reader skips. A work order that can be improved by
reading less is the twenty-second flattering instrument wearing my name, and
the only defence is that the counter-column is adjacent and load-bearing.

---

## What I have decided in advance not to build, so the decision is on the record

The brief asks whether the board should say **what kind** of damage each
grammar has, and names the pattern it missed: three blind string-interior
externals worth 31,842 orphan bytes across kotlin, php and scala.

I will not write a classifier over the stand-in terminal name. The brief itself
says `inquest`'s stand-in name is a guess and has been wrong twice, and
`tool/walls.py` already refuses to widen a predicate to swallow a shape. A
family computed from a guessed name would manufacture families, and it would be
this lane's own flattering number — a grouping that looks like a finding and is
a string match.

What I will do instead is print the three rows **adjacent, sorted by damage,
under their owner word**, with the bracketed stand-in shown and marked as a
guess. If the pattern is real it prints itself as three neighbouring lines; the
board shows it and does not claim it. If that turns out to be too weak to have
caught what a lane found by hand, that is a failure of this design and I will
say so rather than reach for the keyword match.

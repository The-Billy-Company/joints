# Prediction 2 — what the corrected labels do to the board

Written **before** the one-line externals fix was applied, before `owners.py` was
re-run, and before the re-measured peel finished. What I had read: both
dossiers in full (`owners/`, `adjudicate/`), `closure.py`, `owners.py`,
`walls.py`, `standing.py`, and the published externals dump in
[`RESULT-2-settled.md`](../adjudicate/RESULT-2-settled.md). What I had not run:
anything.

Binary: pin `relabel` (tree `289a2b3c4988`, commit `f7ba40004`+110 dirty). The
previous lane's board was pin `owners`; the adjudicating lane's was
`adjudicate2`. **Three pins, three LR(0) collections, and state numbers do not
survive between them** — so every claim below is keyed on a grammar and a
terminal, never on a state number.

## What I already know, so a reader can discount it

The dropped-literal census is published, and it is the whole reach of the fix:

```
bash 6 · scala 6 · python 4 · ruby 1 · ocaml 1 · javascript 1 · typescript 1 · html 1
```

Of those eight grammars, exactly **four are walled** on the previous board —
bash, scala, ruby, ocaml — and ruby's six walls are withheld by the 95% control
floor whatever this fix does. So I know the fix's blast radius is small before I
run it, and the interesting question is not *how much* it moves but **which
direction, and whether the published claim about the direction is true.**

---

## P1 — the fix moves bytes out of more than `gap`

The withheld note says the re-run "can only move bytes **out** of `gap`."
`verdict()` tests `kin & g.blind` **first**, ahead of the `conflict` branch. So a
widened `blind` captures a wall the closure had proven viable in its own state
— a `conflict`, the one verdict that accuses us — and relabels it `scanner`.

**I predict ≥ 1 wall moves from a verdict other than `gap` into `scanner`.**
Falsified if every wall that changes owner was `gap` before.

Named candidate: **ocaml**. Its one dropped literal is `"`, it carries a
14,686 B `conflict`, and a wall on a quote is the commonest shape on this board.
If that is the row, the fix moves 14,686 B from *provably ours* to *seat an
external* — the opposite of the direction the note promised, and a direction
that takes work off a lane rather than giving it any.

## P2 — the reach, priced in advance

**≤ 5 walls change owner and the bytes that move are in [495, 20,000].**
Falsified at ≥ 8 walls, or > 25,000 B.

495 is bash's `]` alone, which is already demonstrated and is therefore the
floor rather than a prediction. The ceiling is bash + a whole ocaml conflict and
nothing else, because scala's six literals are keywords (`else`, `catch`,
`finally`, `extends`, `derives`, `with`) and none of scala's four walls is a
keyword.

## P3 — the ordering hides a press defect, and that is a second bug

`scanner` is tested before `conflict`, so a terminal that is **both** a declared
external **and** inside its state's viability set reads `scanner`. The grammar
demonstrably derives it there; the closure proved it; the board files it as
somebody else's C code.

**I predict ≥ 1 wall in the corpus is both blind-hit and viable.** Falsified at
zero. If it holds, the fix I was handed makes the taxonomy *worse* in one place
while making it better in another, and the repair is to report both facts rather
than let the first branch win.

## P4 — the 24 state-0 walls really are artifacts, and the warm peel is how you know

27,560 B sit in `gap` marked *resume artifact* and unadjudicated. The owners
lane's P6 promised this check and did not deliver it. The warm peel **never
restarts** — it parses the whole file from byte 0 every round — so a wall it
reports is not an artifact of resuming.

**I predict ≤ 3 of the 24 state-0 walls are reported verbatim by the warm peel
on their own grammar.** Falsified if ≥ 8 are.

If it holds, the exclusion was right and 27,560 B leave the board. If it fails,
the previous two lanes both under-counted real work, and the second-largest
unresolved population on the board is real.

## P5 — terminals survive a rebuild; state numbers do not

**≥ 90% of (grammar, terminal) wall pairs are identical between the previous
lane's survey and mine, while ≥ 1 grammar renumbers a state under the same
terminal.** Falsified below 75% terminal agreement.

This is the instrument-trust prediction. If terminals are not stable either,
then `GAPS.md`, this board, and everything keyed on a wall name is a report
about one binary's afternoon.

## P6 — my ranking disagrees with both of `standing.py`'s

The board's default sort became `--crooked` today because `crooked` exceeds
`damage` on eight rows. My prices are neither: a peel price is **the file lying
past a wall**, where `damage` is `size - built` and `crooked` is built-but-wrong.

**I predict ranking walled grammars by peel bytes gives a top-5 that differs as
a set from `--crooked`'s and from `--damage`'s.** Falsified if either matches.

Three metrics that disagree about who is worst is not a scandal; three metrics
that disagree while everyone quotes whichever they ran is.

## P7 — the stranded population is nameable, and `--holding` is how

22,179 B in states holding a completed item, unownable from the wall.

**I predict that for ≥ 2 of the 5 dearest stranded walls, `outliner state
--holding <the completed item>` names exactly one state** — so the fold that
could have left the parse there is unique and the defect has an address.
Falsified at 0 of 5.

If it fails, the stranded column needs an input the wall cannot supply and the
honest report is that it stays unowned until someone runs the parse rather than
the table.

---

## What would make me retract the relabelling

If the re-measured peel does not reproduce the previous lane's wall set on the
grammars that carry the money — php, kotlin, elixir, swift — then I am
relabelling a board that no longer exists, and the corrected split is a
statement about my binary rather than about the corpus. In that case I publish
the disagreement and **not** a corrected split, exactly as the owners lane
refused to reconcile 170 against 181.

## The word replacing `gap`

`gap` says *nobody in this tree*. The test establishes *the parse shifted into
this state and, in the automaton we built from this grammar, no item's
continuation and no fold's follow-set covers this terminal.* Four things produce
that, three of them ours.

The verdict becomes **`unowned`**, and the sentence becomes the four suspects in
the order worth checking. It is deliberately not a synonym for `stranded`:
`stranded` says *the wrong place to ask*, `unowned` says *the right place, and
the test cannot choose between four answers*. Neither says upstream.

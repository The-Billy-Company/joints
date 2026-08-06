# Prediction 4 — the fifth case says my gate is aimed at the wrong thing

Written after being handed a fifth instance and **before** re-aiming anything.
Prediction 3 stands unedited above; this is not a revision of it, it is the
record of what that prediction got wrong and what I am replacing it with.

## What the fifth case does to Prediction 3

The fifth: a lane pinned a baseline, worked for eight minutes, pinned its arm,
and read `latex −1,185`. The lex lane had landed a latex fix inside those eight
minutes. Each arm had its own `OUTLINER_WORK`; the folio shas matched and were
checked. The lane credited itself with somebody else's fix.

Prediction 3's gate **does not catch this, and cannot**, and the reason is not
an implementation gap I can close. Its whole population is writes: `hand`
interposes the write primitives, `seal` diffs a manifest across a window it
opened. Case five has:

- no write into the compared artifact,
- no write by the instrument at all,
- both arms internally consistent, each a correct measurement of its own tree,
- and the two windows **never overlap** — the tree moved in the gap *between*
  two runs, so there is no window either run could have opened that contains
  the event.

That last one is the fatal one. A within-run detector is structurally blind to a
between-run fact. So P8 is not merely unproven, its target is wrong: I aimed at
the mechanism the first four shared, and the mechanism is the accident. Four of
them wrote; the shape does not require a write.

**Scored honestly: P3's framing dies here.** Not the seal itself — the seal
still catches what it claimed, and I will still build and measure it — but the
claim that a write-detector *gates the shape* was over-claimed by exactly one
case, and it is the case that costs a lane twenty minutes rather than an
afternoon of disk archaeology, because it leaves no disk evidence at all.

## The re-aim: the failure, not the mechanism

All five share the *outcome* and only the outcome:

> **Two arms were not taken against the same world**, the verdict was clean, and
> the error ran toward agreement.

So the gate's question is not *who wrote* but **what world was this arm taken
against**, recorded per arm, compared across arms, refused when the two differ
anywhere outside the variable the comparison declared it was varying.

That is a manifest digest taken twice, which the brief already named as the
cheap real version of this, and it is a strictly larger net than the seal:

| # | Instance | What differs between the two arms' worlds |
|---|---|---|
| 1 | `order.miss` folio cache | the folio one arm read was pressed by the **other arm's binary** — a derived artifact that must covary with the declared variable and didn't |
| 2 | `specimen` default stop | the binary the run attributed to is not the binary that answered |
| 3 | `fetch_scanners` | the oracle identity for a grammar differs across arms |
| 4 | `oracle_build` unlocked | same, and within one arm between rows |
| 5 | latex, this one | the **repo source tree digest** differs between the two pins |

Five for five, and each one is a field in a record rather than a rule about
behaviour. Which is the tell that this is the right level: the detector stops
needing to know what kind of mistake it is looking for.

## P11 — the witness catches all five, including the one no window contains

**Predicted:** a `Witness` — binary digest, the pin's own recorded tree digest,
the live repo source digest at arm time, the oracle identity of every grammar
read, the digest of every artifact `stamp.fed` recorded, and the three
`OUTLINER_*` variables — recorded per arm and compared pairwise, refuses all
five, and refuses case five *on the repo tree digest field alone*.

**Kills it:** any of the five passing a pairwise witness comparison, or the
comparison refusing two arms that genuinely differ only in their binary. The
second is the one to watch: on a tree ten lanes write to, the repo digest moves
constantly, and a gate that refuses every honest before/after is a gate that
gets switched off within a day. I predict I will have to distinguish **the
sources the binary was built from** (must match, or the arms are different
programs) from **the repo working tree** (moves under everyone; a warning, and
an error only when the moved files are ones the comparison's own subject
depends on). If I cannot draw that line mechanically I will say so and ship the
warning rather than a refusal nobody can live with.

## P12 — the seal survives as the earlier, narrower detector

I am not deleting it. Two detectors answering two questions:

- **witness** — *were these two arms the same world?* Between arms. Catches all
  five. Cannot fire until there are two arms, so it cannot fire before a single
  run's verdict.
- **seal** — *did this run write into its own evidence?* Within one arm, fires
  at the instant of the read that depends on the write, which is strictly
  before any verdict derived from it. Catches 3 and 4 at their mechanism, with
  the call site attached, without needing a second arm to exist.

**Predicted:** the seal catches 3 and 4 and neither 1, 2 nor 5; the witness
catches all five but only in a two-arm comparison. Neither subsumes the other
and I expect to be able to state exactly which one bit in the proof rather than
printing a merged verdict.

**Kills it:** the seal turning out to catch 5 (it cannot — no window contains
the event), or the witness turning out to catch a single-arm run's write-into-
evidence before the verdict (it cannot — nothing to compare against yet).

## P13 — the null arm makes the fifth lane's falsifier automatic

The lane that found case five found it by pinning the **reverted** tree last and
diffing it against its own baseline: a comparison whose subject is byte-identical
on both sides, which must therefore report zero difference. It reported a
behaviour change, which is the apparatus indicting itself.

That is a general falsifier and it is currently heroic — somebody has to think
of it. It is a mode: build the same subject twice, at two times, and require
that the board come back inert.

**Predicted:** a null arm over this tree, right now, **does not come back
inert**, because ten lanes are writing and the second pin is minutes younger
than the first. I predict the null arm's residual is not noise but nameable —
that the witness diff will say which field moved and the board diff will say
which grammars, and the two lists will overlap.

**Kills it:** a null arm that comes back perfectly inert, which would mean this
tree is quieter than the fifth case says it is and the whole hazard is smaller
than the lane reported.

## P14 — the attest fix is a precondition for the witness, not a neighbour of it

Prediction 1 took generated files out of `attest.survey`'s digest. That was
scored on its own terms. But the witness carries **an oracle identity per
grammar as a field that must match across arms**, and before Prediction 1 that
field differed between any two arms where one had built a `parser.c` and the
other had not — which is to say between almost any two arms.

**Predicted:** with the pre-fix rule, a witness comparison of two honest arms
refuses on the oracle field for 2 of the 77 grammars on this machine today
(measured: `css` and `toml`, both splitting on the presence of `parser.c`), and
the gate is unusable. With the fix, that field is silent unless someone actually
edited a grammar.

**Kills it:** the field still moving across two honest arms after the fix,
which would mean the identity is still carrying something generated.

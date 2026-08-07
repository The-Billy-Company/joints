# Result 3 — the gate, and the prediction that had to die first

`tool/still.py`. Two detectors, `still.py verify` drives fourteen rows, all hold.

## The prediction that died, and why it is the useful one

Prediction 3 designed a **write detector**: interpose the write primitives, seal
a window, refuse when an instrument writes into the artifact set it is about to
compare. It is a good detector and it is aimed at the wrong thing.

The four instances I had all wrote. A fifth arrived mid-lane and did not:

> A lane pinned its baseline, worked eight minutes, pinned its arm, read
> `latex −1,185`. The lex lane had landed a latex fix inside those eight minutes.
> Each arm had its own `JOINTS_WORK`; the folio shas were checked and matched.

Nothing wrote to anything being compared. Both arms were internally honest
measurements of their own trees. **And the event is between two runs**, so there
is no window either run could have opened that contains it — this is not an
implementation gap in a write detector, it is outside the class of things a
within-run detector can observe.

So P3's framing is falsified by exactly one case, and it is the cheap one to
suffer: it costs twenty minutes of believing a false result rather than an
afternoon of disk archaeology, because it leaves no disk evidence at all to go
archaeologising in. **Four of five share the mechanism; five of five share the
failure**, and the failure is the thing to gate:

> two arms taken against different worlds, each internally consistent, reported
> as one comparison.

## What is there now

**`witness`** — what world one arm was taken against, as a record: the binary's
bytes; a **per-file manifest** of the tree it was built from; the oracle identity
of every grammar read; the digest of every artifact `stamp.fed` recorded; and
`JOINTS_BIN`/`WORK`/`LANE`. `pin.py build` writes the manifest beside its own
record, because a pin is a frozen build and the tree it came from is knowable
only while it is still the live tree.

**`seal`** — the write half, kept. Interposes the write primitives, brackets
child processes over the directory they were handed, hooks `stamp.fed`, and
raises at the instant of the read that depends on the write. That instant is
strictly before any verdict derived from it, without a caller remembering to ask.

Neither subsumes the other, which is P12 and it held. The witness needs two arms
to exist; the seal cannot see between two runs.

## P11 — the witness catches all five. **Held.**

```
the five, restored                                        refuses on   seal
1 · order.miss — two arms, one folio cache                work         blind
2 · specimen — declared a variable that did not move      binary       blind
3 · fetch_scanners — the two arms' oracles differ         oracle       BITES
4 · oracle_build — one grammar read as two                artifact     BITES
5 · latex — the tree moved between the two pins           subject      blind
```

Row 5 refuses on the subject manifest, which is P11's specific claim. The
refusal is not *these two differ* — two arms of a before/after are supposed to
differ — it is *these differ in files you did not claim*:

```
still: REFUSE - subject: the two arms were built from trees differing in
                2 file(s), 1 of which you have not claimed
    src/kernel/lex/latex.zig      NOT YOURS
    src/kernel/table/press.zig    yours
```

The line I predicted I would have to draw, I drew: the **subject** (the tree a
binary was built from, per file, against what the lane claims) refuses, and the
**live** repo digest only warns. A refusal on the live tree would fire on every
honest before/after within a day, and a gate switched off inside a day would be
the sixth instance of this shape.

The three rows that must pass, pass: an honest before/after with one claimed
file and its own cache and seat; a null arm; and a folio pressed into an arm's
own `JOINTS_WORK`.

## P12 — two detectors, and the seal is honestly blind on three. **Held.**

The `seal` column above is printed by the gate itself, in its own output, rather
than kept in this document. A detector that took credit for the other one's
population would be the same over-claim in a new place.

## P8 (from Prediction 3) — the seal bites, and does not bite the repairs. **Held.**

Not constructed. The defects are written into a module of their own in a scratch
tree and imported, then performed:

```
3 restored · rewrite the scanner, unlink the parser beside it   flaw.py:10 in unconditional
3 repaired · write only a scanner that actually changed         read back, no complaint
4 restored · overwrite a shared grammar.json holding no lock    flaw.py:24 in unlocked
4 repaired · the same write, under the lock oracle_build takes  read back, no complaint
4 · a CHILD process writing it, which no interposition can see  flaw.py:29 in child
private · press a folio into this arm's own JOINTS_WORK       read back, no complaint
```

The separate module is load-bearing, not tidiness. `_site` skips its own frames,
so a proof whose writer is the detector's own file reports every finding as `?` —
which is what the first run did, and the attribution column is most of the seal's
value. *Something moved* is what the generation ledger already says; *your line
moved it* is the new sentence.

The two `repaired` rows are the ones I care about. A gate that fires on the
repair the last lane made is a gate nobody leaves on.

## P10 — no name list. **Held.**

Nothing in `still.py` names an instrument or a call site. The seal's population
is whatever the process writes. The witness's is whatever the arm reads. The
private set is derived from the environment `pin.py arm` exports, so an
**unarmed** run has an empty private set and every shared write it reads back is
a fault — failing closed there is the point, since that run never had a claim to
comparability. The lock exemption is asked of `differential`'s own re-entrant
register rather than re-derived, because two answers to *who holds this* is the
same defect one layer up.

`CHECKS` in the sweep is the closest thing to a list and it is the opposite of
an allowlist: a module absent from it is reported **unexercised**, not clean.

## P13 — the null arm over this tree is not inert. **Falsified.**

I predicted the tree would move under a null arm and that the residual would be
nameable. Measured, twice, over the whole Zig source manifest:

```
null arm over 4.8 minutes on a ten-lane tree
  early fold 53c18489dc21  (87 files)
  late  fold 53c18489dc21  (87 files)
  source files that moved under me, having changed none: 0
```

Zero. Byte-identical, over a window comparable to the fifth lane's eight minutes,
on the same tree with the same lanes running. A pin was built by somebody in that
window — the pin count went 71 → 72 — and no source file moved.

**The correction is worth more than the prediction was.** I assumed a shared tree
is *continuously* in motion, so a lane would feel the hazard and learn to check.
It is not: it is quiet most of the time and moves in bursts when a lane lands. A
check that passes almost every time is one people stop running, and a hazard you
cannot feel is exactly the kind that needs a recorded manifest rather than
vigilance. My prediction was the optimistic one — I predicted a hazard loud
enough to teach you about itself.

## P14 — the attest fix is a precondition. **Held.**

The witness carries an oracle identity per grammar that must match across arms.
Under the retired survey rule, measured over every oracle tree on this machine:

```
[was] 77 grammars, 206 trees — 2 with more than one identity (css, toml)
[now] 77 grammars, 206 trees — 0
```

Both splits are `parser.c` present in one arm and absent in the other, visible in
the file listing beside each. Two of 77 rather than the 28 of 29 the original
report quoted, because a scanner refresh has since run over this machine and
healed most of them — the mechanism is identical and the population has moved.
With the old rule that field refuses two honest arms whenever one of them has
built a parser and the other has not, which is most pairs, and the gate is
unusable. Prediction 1 is what makes this field carry a signal.

## The sixth case — a third detector, because the first two are aimed elsewhere

A sixth arrived after the above was written, and it is the only one where nothing
is wrong with the arms. A lane offered 30 byte-identical folios as proof its
`Troupe` seating broke no other grammar. The arms were comparable, the digests
real, the tickets correct, nothing written. **The check is sound and it is about
the wrong object** — a folio is a pressed table and a seat cannot move one, so
latex's folio is identical between the arm scoring 108 and the arm scoring 5,246.

Neither existing detector can see it, and neither *should*: the witness asks
whether two arms were taken against the same world, and the honest answer here is
yes. The seal asks whether anything wrote into evidence, and nothing did. This is
a third question — *is this evidence about the change at all* — and it needed its
own rule.

The general form is not checkable. A machine cannot know which artifact a change
should move. The narrower one is, and is sufficient:

> An instrument that did not respond to the treatment cannot clear it.

So `vacuous()` pools each arm's artifacts by kind and refuses any kind that is
byte-identical throughout while the two binaries differ. Either it is the wrong
instrument or the change did nothing; a negative result from it is not evidence
of absence either way. This is the binary rule reflected — that one refuses arms
equal by construction, this refuses evidence that is.

Two things fell out of building it. **Oracles must not be pooled**: an oracle is
a controlled variable, case 3 refuses precisely *because* two arms' oracles
diverged, and demanding one move would invert the rule holding it still. Vacuity
is a question about outcomes only. And restored against the other five it fires
unbidden on three — row 1 because a shared cache makes both arms read one folio,
rows 3 and 5 because a scanner refresh and a lex fix cannot move a pressed table
either. Those were the same theatre, standing in the record for weeks, visible
only from this side. Row 6 carries `folio!` and nothing else, which is why two
lanes read it as clearance.

The escape hatch is `--inert`, and it is not a suppression: it changes the claim
from *nothing else broke* to *this moves nothing*, which is a refactor's real
result and is falsifiable on its own terms.

The rule of thumb is now the fifth house rule rather than folklore, and the
isolation arm is its control. What makes that more than advice is that it is
already checkable — the isolation arm is *defined* as the arm differing from
today by only your rows, and `--mine` is exactly that predicate, so a botched
isolation that took a shared seam out on the way past fails at the file, by name,
before printing a number.

## What it costs

`still.py verify` is 0.15 s. A witness over this tree is one manifest — 87 source
files — plus whatever `stamp.FED` already holds, so it is well under the second
Prediction 9 budgeted, and the seal's per-child bracket is bounded by the
`WATCHABLE` ceiling below.

## The hole I am leaving open

The child bracket watches the directory a child was **pointed at**. A child that
writes outside its own cwd is invisible to it, and `_BLIND` is the admission
rather than the defence: a bracket that cannot be made sound declines and prints
that it declined, whether or not anything else fired.

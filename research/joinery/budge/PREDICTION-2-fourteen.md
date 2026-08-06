# Predictions — the thirteen columns `budge` convicted

Written before the repairs, scored at the bottom of `RESULT-2-fourteen.md`.
The board this is written against: 108 records, 790 declared fields, 2577
documents, 255 MB, **13 red**. (The brief says fourteen; `rack.Seen.renamed`
has since gone `unseen/thin` on its own — see the hand-off.)

Disclosure of what was already measured before these were written: the
`walls.Priced` attribution mechanism (P1) was traced first, so P1 is a
prediction about the *fix*, not about the diagnosis. Everything else below is
written blind to its own measurement.

## P1 — `walls.Priced.roofed` is `budge`'s own defect, not `walls.py`'s

Attribution admits an object to a record when `record.required <= object.keys`,
and breaks ties by `max(len(required))`. Nothing charges a record for the keys
it *cannot* explain. `walls.Priced` requires four keys — `cost hits kind who` —
and those four sit on the stale `owners.Wall` boards under `.local/strand/` and
`.local/reprice/`, written before `Wall` grew `roofed`. `Priced` is the only
declared record that fits them, so it wins by default and explains 4 of 14 keys.

**Predict:** a coverage floor — a record must explain a majority of an object's
keys to be charged it — turns all seven `walls.Priced` rows `unseen`, removes
the one red row, and reddens nothing. **Predict** the collateral is small:
**≤ 3 other records** change verdict class. (Confidence 0.7 on the ≤ 3; the
number is the part I am least sure of and it is the part that decides whether
this fix is shippable.)

**Predict the second half, which matters more:** `walls.Priced`'s other six
fields currently read **`budged`** — green — and every value they hold was
harvested off `owners.Wall`. So the fix should turn **six green rows into
`unseen`**, not zero. A fix that only removes the red row has removed the
symptom. Green rows resting on another record's values are precisely the
vacuous evidence this instrument exists to name, and `budge` is committing it.

## P2 — `field.Press.reason` is innocent, and its innocence is a second `budge` defect

The brief calls this the most interesting: constructed by four writers, `""` on
all 640 rows, therefore "a serialization or plumbing defect". I predict it is
neither. `reason` is written non-empty only where a press *fails*.

**Predict:** `field.Press.outcome` is itself **flat** across those same 640
rows — every row on disk is the same successful outcome. If so, `reason` did
not fail to arrive; it was never constructed, and the population contains no
failure for it to describe.

**Predict** the sibling that earned `Press` its `open` label is `name` (one row
per grammar). That exposes the general defect: `open` reads *any* sibling
moving as proof the record responded, so a column whose variance is
**conditional on a sibling that did not move** is convicted for the stillness
of that sibling. Correct verdict is `thin` — a corpus finding, `absent.py`'s.

**Predict** this same shape explains most of the remaining rows, and that if I
fix it correctly the red count falls to **3 or fewer** without a single field
being filled or deleted. (Confidence 0.55. This is the prediction most likely
to be self-serving, so it gets the falsifier with teeth: after the fix,
restoring the *original* `oracles` bug must still turn `still.Witness.oracles`
red, and `budge verify` must still hold. A discriminator that excuses the bug
budge was built for is not a discriminator.)

## P3 — `stamp.Ledger.moved` / `republished` are dormant, and the plumbing is real

`[]` on all 58. **Predict** the detector works when driven — feeding the same
path twice with different bytes produces a `Moved`. **Predict** the reason no
run has ever produced one is that `order.py` feeds the **binary** and never
feeds a folio, and the folio is the only artifact in this system that is
re-minted mid-run. So: a real gap, in a file I own, and the repair is to feed
the artifact the ledger was built to watch — not to fill the column.

**Predict** `stamp.Ledger.artifacts` (`31` on all 58) is the same corpus shape
as P2: 30 grammars + 1 binary on every run, `thin` not `open`.

## P4 — the population rows

`attest.Oracle.cli` (`tree-sitter 0.26.11` ×390), `attest.Oracle.asked`
(`true` ×300), `bench.Row.axis` (`press`) / `.unit` (`ms`), `shear.Cut.cut_rubble`
(`0` ×114), `repair.Reuse.beats` (`60` ×3), `still.Witness.asked` / `.lowered`.

**Predict** all seven are corpus findings — one tree-sitter installed, one axis
benched, no rubble cut in the sampled set — and none is a defect. **Predict**
`still.Witness.asked`/`lowered` reproduce the brief's claim: driven directly
against a real oracle consultation the pair fills immediately, so the repair is
to make the population exist, and it lives in `still.py`, which I do not own.

**Predict** exactly one of these seven turns out not to be a population
finding. (Named guess: `shear.Cut.cut_rubble`, because `0` from a *counter* is
the same shape as the `oracles` bug — a lookup that always misses reads zero
just as honestly as an empty set does.)

## P5 — the two hand-offs

**Predict** `scars-arm` is a **stale pin, not corruption**: the bytes at the
pinned path are a valid later build, and someone re-armed into the same prefix
without re-pinning.

**Predict** `rack.Seen.renamed` is no longer red because rack's board aged out
of the scopes, not because anything was fixed.

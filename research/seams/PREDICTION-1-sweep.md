# Prediction 1 — the sweep, and whether the repair generalizes

Written before the measurements that decide it.

[`../press/RESULT-1-scope.md`](../press/RESULT-1-scope.md) closed on two record
types whose bytes no field owns being written straight to disk — `lexicon.Head`
(sixty bytes of fields in a type `@sizeOf` rounds to sixty-four) and irregex's
`Dfa.PatRun` (`struct { hi: u32, mask: u64 }`, twelve rounded to sixteen). Both
were found by chasing one symptom: fourteen of thirty grammars pressing to
different bytes twice in a row. Nobody has asked whether there are others.

This dossier is that sweep, over this repository and the sibling engine, plus
the question the repair leaves open: `flat` fixes the two sites it is called
from, and a rule that lives in one function is a rule the next writer will not
find.

## Prediction 1a — the sweep finds nothing else that reaches disk here

> **Prediction:** every remaining `asBytes` / `sliceAsBytes` / `bytesAsSlice` in
> `src/` views a type whose fields tile it — mostly `u32`, `[]const u32`, and
> `packed struct(u64)` — so the two already found are the whole disk-facing set.
>
> *Falsifier:* a third persisted type with unowned bytes. That would mean `flat`
> was applied where the symptom pointed rather than where the class lives, and
> the press job in CI has been passing on a corpus that happens not to exercise
> it.

## Prediction 1b — the hash sites are the exposure, and one is live

> **Prediction:** the interesting remainder is not on the disk path but on the
> **hash** path, and the mechanism there is different: no memory escapes, but a
> byte-wise `hash` paired with a value-wise `eql` disagree about which values
> are the same one, so a map stores two rows for one key. Every LR(0), LALR and
> quire interner in this repo keys on `sliceAsBytes` of something.
>
> *Falsifier:* every hashed element type is seamless. Then the hash paths are
> sound by luck of their element types rather than by discipline, which is worth
> saying out loud but is not a defect.

## Prediction 1c — the gate has to be a compile error over a derived roster

> **Prediction:** the check that would have caught the original bug *before*
> anyone pressed twice is a comptime assertion that every persisted record type
> tiles itself, and it has to derive its roster from the format rather than
> list it. `leaf.Kind` already enumerates every section and `Record(k)` already
> maps a kind to its record, so `for (std.enums.values(Kind)) |k|` is a roster
> that a section added tomorrow joins without anyone remembering this exists.
>
> *Falsifier:* the assertion cannot be stated without a hand-written list of
> types. A roster somebody has to extend is the same bug wearing a checklist.

## Prediction 1d — `flat`'s own guard has a hole in it

> **Prediction:** `flat` refuses a field that "is not an integer", and that
> phrasing is not the property it needs. The property is *does this field own
> all of its bytes*, and an integer can fail it: `@sizeOf(u21)` is four while a
> store writes twenty-one bits. So `flat` as written would accept a `u21` field
> and copy eleven bits of the source's slack into the zeroed cell — the bug it
> exists to prevent, one level down, admitted by the guard.
>
> *Falsifier:* `std.meta.hasUniqueRepresentation(u21)` is true, or no such
> integer can reach a record here. Then the guard is merely worded oddly.

## Prediction 1e — this lane moves zero board cells

> **Prediction:** every change this lane makes is a `comptime` block, a `test`
> block, or a comment. None of them is a runtime expression, so the parse is
> untouched and **all** board cells hold.
>
> *Falsifier:* any cell moving between a binary built with these edits and one
> built without them, from a single tree snapshot, at a single path.

## Prediction 1f — the binaries will be byte-identical

> **Prediction:** because 1e's changes emit no code, building the two arms at
> the same path from one snapshot yields two binaries with the same `sha256`,
> and that comparison is cheaper and stricter than boarding both.
>
> *Falsifier:* differing digests. Which would leave the board diff as the only
> instrument, and would say that a binary digest cannot answer this question.

## What would make this dossier worth nothing

A gate that passes because it examined an empty set, or because its predicate
says yes to everything. Both read exactly like a clean bill of health, and a
`for` loop over a roster is the easy way to write the first one by accident.
Every assertion landed here has to be paired with a check that the set was
non-empty and that the predicate can still say no.

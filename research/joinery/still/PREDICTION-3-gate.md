# Prediction 3 — a gate that fires before the verdict, not months after

The brief for this one is exact: *an instrument which writes into the artifact
it is about to compare must fail **before** it prints a verdict.* Everything
below is written before the gate exists.

## Why the machinery already here does not do it

`stamp.reconcile` re-reads every artifact a run was `fed` and names the rows
whose artifact moved. It is the closest thing in the tree and it cannot catch
this shape, for three separate reasons, and it is worth being precise about them
because "we already have a generation ledger" is the argument that would stop
this lane before it starts.

1. **It watches reads, not writes.** Its population is `stamp.FED` — what an
   instrument declared it was handed. `oracle_build`'s `parser.c` and
   `fetch_scanners`' `scanner.c` were never fed, so they were never watched.
2. **The write is in setup, so there is only one generation to see.** All four
   defects mutate *before* the first read. `reconcile` then finds one digest per
   artifact and prints `one generation each — every row was measured against
   what this tree holds now`, which is **true** and is exactly the wrong
   reassurance. This is why every one of the four came back clean twice.
3. **It reports, and it reports at the end.** By the time the ledger speaks, the
   verdict is printed.

So the gate is not a better change-detector. `reconcile` asks *did the artifact
move*; the gate has to ask *who moved it*, and answer before the number is
printed. Different question, and it composes with the ledger rather than
restating it — a second copy of the reconcile rule is the defect `sole.py`
exists to catch.

## The design: prepare, then seal, then compare

The discipline the gate enforces is one sentence: **an instrument declares the
moment its inputs are final, and any write to the compared artifact set after
that moment is a defect.** Not "no writes" — `oracle_build` must build the
oracle. Writes belong before the seal. This is a real and followable rule rather
than a ban, and an instrument that cannot say when its inputs are final has
found something out about itself.

```python
with still.sealed("rack: spine audit", grammars):
    ...                       # the comparison
                              # the seal is judged on the way out, before the caller prints
```

Two detectors inside the window, for the same reason the sweep has two:

- **`hand`** — the in-process write primitives are interposed for the duration
  of the window. A write inside the seal raises **at the instant it happens**,
  carrying the call site. This is the half that makes it a gate: it does not say
  *something moved*, it says *your line moved it*.
- **`seal`** — a manifest over the artifact set, taken on entry and re-taken
  before the verdict. This is the half that survives a child process, and
  `tree-sitter generate` and `joints mint` are the two that matter.

The two must be told apart in the output and not merged into one verdict. A
`hand` finding is always the instrument's own bug. A `seal` finding with no
`hand` finding may be a sibling lane landing mid-window on a tree ten people
share, which is a different sentence and a different fix.

## P8 — it catches the ones we know about, restored

**Predicted:** in a scratch tree with `differential.refresh`'s conditional
reverted to the unconditional `write_bytes` + `unlink` it replaced, a sealed
`scanners` run fails on the **hand** detector, names `write_bytes`, and names
the file. With the fix in place the same run passes. And with `alone()` stood
down inside `oracle_build`, a sealed run fails on the **seal** detector — that
one is a child process and `hand` structurally cannot see it, which is the
measurement that says why there are two detectors and not one.

**Kills it:** either defect passing the gate, or the fixed version failing it.
A gate that fires on the repaired instrument is a gate nobody will leave on, and
it would be the fifth instance of this lane's own shape.

## P9 — the price is payable, and I will pay it in the open

**Predicted:** the digest-mode seal over the corpus artifact set costs **under
one second**, against a board that takes tens of seconds, so it can be on by
default. `attest.survey` is quoted at 0.15 s for scala's 28 MB `parser.c`, and
taking generated files out of the digest (Prediction 1) should take most of that
away — the seal and the narrowing are the same economy twice.

I predict the stat-mode seal is at least 10x cheaper and **strictly weaker**,
and I predict I will keep the digest as the default anyway, because an mtime
standing in for an identity is the second half of the shape this whole lane is
about and shipping it as the default would be funny in the wrong way.

**Kills it:** a digest seal over a board's artifact set costing a second or
more, in which case default-on is not honest and the flag has to be the other
way round.

## P10 — the gate is adoptable without a name list

The brief forbids an allowlist of known-bad functions, and the reason is the
whole point: it would catch the four we found. So the sealed set has to be
**derived** rather than declared — the artifacts a comparison is *about*, taken
from where the instruments already get them (`differential.WORK / "lang"`, the
folio cache, the binary, the seat's `lib/`), never from a list of paths that
grows by hand.

**Predicted:** the gate needs no per-instrument configuration beyond the line
that opens the window, and adding a thirty-first grammar or a sixteenth
instrument requires no edit to it.

**Kills it:** finding myself writing a name in the gate to make a real
instrument pass. If that happens the honest report is that the shape is not
mechanically separable from legitimate work, and that is a result too — a worse
one, and it must not be hidden behind a list.

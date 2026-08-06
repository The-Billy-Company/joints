`onlydamage.py` says which pages never asked a second parser. `sighting.py` says
how much of the record has, and whether the number is a backlog or a flow — the
second being the only one that decides whether the fix belongs on a page.

```text
379 pages under research/ and changelog.d/
  sighted  156   quotes the oracle, or proves two forests byte-identical
  blind    102   quotes only our own words about our own forest
  silent   121   no measurement in it
60.5% of the 258 pages that report a measurement have asked a second parser.
```

**116 is a rate.** Unchanged, `onlydamage.py` read 116 of 347 when
`RESULT-9-reach.md` ran, 113 of 354 half an hour later and 109 of 379 now: the
record grew by **thirty-two pages** during one lane. Ten of the corrections are
this lane's and the blind count still fell by only seven, because the population
refills as fast as it drains — **five blind pages have been written since the base
board that made sight possible was minted, three of them in the three minutes
before this fragment.** Every measured page in the population is uncommitted, so
this is not a historical backlog; it is the current output rate, and no page-level
correction touches it.

So the fix is a gate, and it is cheap because the classifier already exists:

```text
sighting.py --gate --since <ref>   fail on a page changed since REF that is blind
sighting.py --gate --max N         fail when the population exceeds N
sighting.py --risk                 the blind pages wearing the known-bias shape
```

The `--since` form belongs in CI and is inert tonight, because with the record
uncommitted every page is "changed since HEAD". The `--max` form works now and only
ever has to fall.

It imports `onlydamage.py`'s classifier rather than copying it, and adds the two
things that classifier cannot see. A **table-aware** reading, because the triage's
proximity regex refuses to cross a `|`, so a page reporting
`| ...of those, **square** | **2,184** |` reads as blind while being the most
sighted paragraph on the tree — and every correction written tonight is in that
shape. And the columns **derived** from `square`: `trued` (`square / size`) and
`unvouched` (`built − square`) are claims about a second parser, are not in the
triage's vocabulary, and are exactly what this lane is asking the board to print.
Both gaps were caught the same way: the sweep graded a page this lane had written
that hour as never having asked the oracle.

**The tail is bigger than the ranking claimed.** `RESULT-9` says that below rank
8 a sighted reading resizes a number rather than changing a verdict. `--risk` tests
that against the shape `RESULT-9` itself defined — our columns only, a declared
extra as the subject, and a seating that **cost** something, which is ocaml's
fragment exactly — and **39 of the 102 wear all three**. The three highest-ranked
of those that got opened held a sign flip, an 8.3× and a withdrawal. The rest are
a worklist and `--risk` orders it. `consort/RESULT-10-record.md`.

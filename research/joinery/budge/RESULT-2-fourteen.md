# The thirteen columns, worked through

Measured 2026-08-06 on this tree. Board before: 108 records, 790 declared
fields, **13 red**. Board after: 794 fields, **10 red** - four of the thirteen
resolved, one new arrival from a sibling lane (`rack.Price.rule`, not mine).

Three of the four were repaired in the instrument rather than in the fields it
convicted, which is the finding of this lane: **the sweep's own `open` label
convicted three columns on evidence that was not theirs, and cleared six on the
same mistake.** Predictions are in `PREDICTION-2-fourteen.md`, scored below.

## What each of the thirteen turned out to be

| column | verdict was | is | what it is |
|---|---|---|---|
| `walls.Priced.roofed` | `silent/open` | `unseen/adrift` | budge defect - a record never written to disk, charged 3,507 foreign objects |
| `field.Press.reason` | `void/open` | `void/unreached` | innocent - three writers, none ever executed, and the sweep can name which observation would prove it |
| `bench.Row.axis` | `flat/open` | `flat/unreached` | innocent - one of eight axes has ever been benched |
| `bench.Row.unit` | `flat/open` | `flat/unreached` | innocent - cross-witnessed by `axis` |
| `stamp.Ledger.moved` | `void/open` | `void/open` | **real** - the folio was never fed. Plumbing repaired; stays red until a re-mint lands mid-board |
| `stamp.Ledger.republished` | `void/open` | `void/open` | same defect, same repair |
| `stamp.Ledger.artifacts` | `flat/open` | `flat/open` | the same defect said as a number - `31` is thirty grammars and a binary, and no folio |
| `shear.Cut.cut_rubble` | `flat/open` | `flat/open` | constant by construction - reported, not mine |
| `attest.Oracle.cli` | `flat/open` | `flat/open` | corpus - one tree-sitter installed. Read-only lane |
| `attest.Oracle.asked` | `flat/open` | `flat/open` | corpus. Read-only lane |
| `still.Witness.asked` | `flat/open` | `flat/open` | corpus, judgement confirmed - see below. Read-only lane |
| `still.Witness.lowered` | `void/open` | `void/open` | same pair. Read-only lane |
| `repair.Reuse.beats` | `flat/open` | `flat/open` | three observations - reported, not mine |

## The three repairs

Each is argued in its own `changelog.d/` fragment and each is falsified by
restoring the defect and watching exactly the right row go red.

**`unseen/adrift`.** Attribution admitted an object when the record's
*required* columns were a subset of its keys, with no charge for keys the
record cannot explain. `walls.Priced` requires four of its seven and took every
stale `owners.Wall` board in `.local/`, explaining four keys of fourteen. It
was the **only record in the tree with zero complete objects** - every other
record with partials has thousands of whole ones beside them - so counting
whole observations per record costs exactly the one record it was written for
and keeps the tolerance that lets a board written before a column existed still
be read. Six columns of `Priced` that read `budged`, green, cleared, were green
on another record's values.

**`unreached`.** `field.Press.reason`'s three real-string writers each pin
`outcome` to a literal - `absent`, `refused`, `timeout` - that no row on disk
has ever held. The population's four outcomes are `clean`, `residual`,
`refusing`, `unlexable`; the near-miss between `refusing` (a successful press
over a table with refusing cells) and `refused` (a press that would not run) is
78 rows against zero. The verdict fires only when every site that could hand
over something other than the observed value is so marked, only on string
literals, and only against a sibling the population has actually shown - so it
lapses the moment a `refused` row lands. That lapse is the falsifier.

**The folio.** `stamp.Ledger.moved` is not a dead column and not a corpus
finding. `ask` feeds the grammar and the binary, `order.press` feeds the
binary, and nothing fed the folio - the one artifact here that is re-minted
while boards run, and the exact event `reconcile`'s docstring is written about.
`--hazards` showed the detector firing for months because it plants the
sighting itself. `order.folio_for` now feeds what it hands over, on both
branches, and the new `stamp.py --plumbed` asks the question `--hazards`
cannot.

## Predictions, scored

Six held, two half, one clean miss.

- **P1, the adrift fix costs ≤ 3 records** - **held**, and under. Exactly one
  record changed class, and the second half held too: six false-`budged` rows
  retired with the red one, which was the part that mattered.
- **P2, `Press.reason` is innocent** - **half**. The conclusion held and the
  evidence I predicted for it was false. I predicted `outcome` would be flat
  across the 640 rows. It took four values. What actually acquits `reason` is
  narrower than "the population never moved": the population moved a lot, and
  moved only among outcomes for which `reason == ""` is the contract. I would
  have been wrong to stop at the prediction, and the brief was right that the
  interesting thing was in this column.
- **P2's corollary, red falls to ≤ 3** - **wrong, and it was the load-bearing
  one.** It fell to 9. I assumed the `unreached` shape would explain most of
  the board; it explains three columns. Six of the nine survivors are corpus or
  other-lane findings that no rule change should touch, and assuming otherwise
  is exactly how a discriminator gets widened until it excuses everything.
- **P3, the ledger's plumbing gap is that folios are never fed** - **held**,
  precisely, including that `order.py` was the file.
- **P3b, `Ledger.artifacts` is a corpus shape** - **half**. `31` is thirty
  grammars plus a binary as predicted, but calling it corpus was wrong: it is
  the same plumbing defect stated as a count, and it should start moving now.
- **P4, seven population rows** - **held**, and the named guess held. I said
  exactly one would not be a population finding and named
  `shear.Cut.cut_rubble`. It is not one - but not for the reason I gave. I
  guessed a lookup that always misses. It is `best.rubble if best else 0`,
  where `best` is only ever assigned an outcome with `standing >= 1.0`, and a
  fully-standing prefix has no rubble. Both arms of the ternary are zero. Right
  answer, wrong mechanism.
- **P5, `scars-arm` is a stale pin** - **held**, and provable.
- **P5b, `rack.Seen.renamed` aged out** - **held**.

## `still.Witness.asked` / `lowered` - the judgement confirmed

The sweep judged this an honest corpus finding rather than a defect and it
holds. `asked` is `any(r.asked for r in rows)` and `lowered` is a comprehension
over `r.lower`, both minted at one site in `still.py:222` whose every argument
is computed. There is no literal to read there, so `unreached` cannot and does
not reach it - which is the right outcome: nothing in the source proves the
branch was never taken, only that no witness on disk was taken by a run that
consulted the oracle. The remedy is to make the population exist, and it is in
`still.py`, which this lane is read-only on. Handed over rather than raced for.

## Reported, not touched

- **`shear.Cut.cut_rubble`** (`tool/shear.py:66`) - constant by construction, as
  above. It wants a `# budge:` excuse on the declaration, which is what this
  tree spells a deliberate constant with, and then it stops being a row. One
  line, and it is not my file.
- **`repair.Reuse.beats`** (`tool/repair.py:92`) - `len(puts)` where the count
  comes from `--beats`, default 60, and all three rows on disk were taken at
  the default. That is the `unasked` shape, and `unasked` deliberately matches
  string defaults only, so a distinctive numeric default slips through. Worth
  fixing in `budge` eventually; not on three observations in three documents,
  which is the thinnest population on the board.
- **`attest.Oracle.cli` / `asked`** - one tree-sitter version installed, and
  `asked` true wherever an oracle was consulted. Read-only lane.

## Hand-offs

**`pin.py verify` exits 1 on `scars-arm`: a stale pin, not corruption, and I
can show it.** The pin records binary `67892dc687d4`, built 22:08:53 local; the
bytes at `.local/pin/scars-arm/bin/outliner` digest `c7ad0942e6a1` and the file
is dated **22:49:47**, the same second as `fz-skeins`, in the middle of a run
of ten sibling arms all built between 22:37 and 23:14. So someone re-armed into
the same prefix 41 minutes after pinning it and never re-pinned. Nothing is
corrupt.

The consequence is worse than the exit code, and it is on the boards rather
than the binary: `.local/scars/arm.json` and `arm-audit.json` both record
`build=67892dc687d4`, and **`arm-audit2.json` records `build=c7ad0942e6a1`**.
One pin name now stands for two binaries, so those boards are not comparable to
each other even though they share an arm. Each board is individually honest -
it wrote down which build it read, which is exactly what that machinery is for
- but a comparison across them is a cross-binary comparison wearing one name.
Worth a second look while you are in there: `control-audit.json` records
`tree=4b10e8617560` where every other scars board records `0eecbc118fd3`.

**`rack.Seen.renamed` reads `0` sixty times, and it has a twin.** It went
`unseen/thin` partway through this session - the boards carrying it had aged
out of the swept scopes - and came back on a fresh board the lane wrote while
this was being written. What the sweep can say cheaply:

- `renamed` is `0` on all 60 rows over 2 documents, and so is **`shelter`**,
  which was not in the original report. Every other column of `rack.Seen` -
  22 of them - budged over those same rows, so the real classifier path
  (`rack.py:810`, `tally[...]`) is what wrote them. The all-zero fallback
  `Seen` at `rack.py:842` is not what these rows came from.
- The classifier has a live `renamed` branch: `rack.py:649` returns
  `"unframed" if missing else "renamed"`, and `rack.py:770` treats `renamed`
  alongside `square` and `unwindowed`. So the value is reachable in the
  source and has not been reached by the corpus.
- Neither column is excused by the new `unreached` rule, and that is
  deliberate rather than an oversight: `rack.py:842`'s writer is a literal `0`
  which *is* the observed value, and `rack.py:810`'s is computed with no
  literal sibling to read. Both stay honestly red. Whether that is "no grammar
  here has ALIAS pairs that survive to a byte" or a branch that cannot fire is
  the lane's to answer; the sweep can only say it never has.

`rack.Price.rule` also arrived red in the same window (`flat/open`,
`a59f94cff34fee84…` on 3 rows in 3 documents) - a hash constant across every
row anyone has taken, which on three observations is a population too thin to
convict on and worth a look from inside the lane.

## The instrument I trust least

**`budge`, and specifically `open`.** Not because of the two defects fixed here
- those are fixed and falsified - but because of what fixing them showed about
the label.

`open` convicts, and it convicts on the weakest possible proxy: *some* sibling
column of this record took two values, therefore this column's stillness is
about this column. Of the thirteen it convicted, **three were convicted for a
sibling's variance that had nothing to do with them** - `Press.reason` for
`name` moving one row per grammar, `bench.Row.axis` and `unit` for `case`
moving - and **one was convicted for a record that had never been written at
all**. Four of thirteen. The two new rules cover the shapes I could
mechanically prove; they do not make `open` sound, they carve two provable
cases out of it. `attest.Oracle.cli` is still red today for the sibling `name`
moving across grammars, which says nothing whatsoever about how many
tree-sitters are installed.

And passing its own check does not clear it, for the reason the sweep already
said about itself out loud: pointed at itself it reported nineteen of nineteen
fields `unseen`, perfectly green, because it had never written a record to
disk. `budge verify` is ten falsifiers over populations `budge` plants itself,
three witnesses and four press rows at a time. Every one of them holds. Not one
of them would have caught either defect repaired today, because both needed a
population `budge` did not author - 3,507 stale boards from a lane that renamed
a column, and 640 press rows whose four outcomes happen to exclude three
literals. A gate whose corpus is its own fixtures is testing the rule it
already wrote down.

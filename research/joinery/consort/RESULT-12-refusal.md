# Result 12 — what the gate is wrong about, and which half of it now blocks

`RESULT-10-record.md` built the gate and left one number unmeasured: how often
it refuses a page that was already fine. It shipped advisory with 206 refusals,
and 206 is a floor on the problem rather than a measurement of it — a gate whose
false-refusal rate is unknown cannot honestly be argued into blocking, because
the argument has no denominator.

This measures it, and the answer splits the gate in half.

**Verdict: the stamp axis blocks, the blind axis reports.** Adjudicating 45
sampled refusals by hand puts the stamp axis at **6.9% false [1.9%, 22.0%]** and
the blind axis at **60.0% false [35.7%, 80.2%]** where it refuses alone. The
enforced gate is the first of those. The second prints `note:` and returns 0,
with `--strict` for anyone measuring whether it is ready to be promoted, and a
promotion criterion that is a number rather than a mood.

outliner `a525dc9b8` · tree `3d0d2e481` (live) · **no oracle** — outliner's own
words. Every count below is off that tree; the record grows several pages an
hour while ten lanes work, so a re-run will not reproduce the populations and
`--rate` re-derives them live rather than quoting these.

## The method, and why it is stratified

```sh
python3 research/joinery/consort/sighting.py --sample 15 --seed 11   # the worklist
python3 research/joinery/consort/sighting.py --rate                  # the reading
```

A refusal belongs to exactly one of three axes — `blind only`, `stamp only`, or
`both` — and the three are 30 / 108 / 80 pages of the refused population. A
proportional sample of 45 would put four pages in `blind only` and report its
rate to about ±40 points, which is not a measurement of the half the authoring
lane said it was least sure of. So the draw is **stratified**: fifteen from each
axis, seeded, so somebody else can redraw the same worklist and disagree with
the adjudications rather than with the sample.

Each of the 45 was read in full. A refusal is **false** when the page already
carries what the axis demanded:

- for the **blind** axis — its figures came from a second parser it does name,
  or from an instrument with only one parser in the question, or the thing the
  detector read as a figure is not one;
- for the **stamp** axis — it names a tree or a binary identity, or it carries
  no figure at all.

The adjudications are committed at `sighting.adjudicated.json`, one row per
page with a verdict and a note. Rates are Wilson score intervals, not the normal
approximation: at 0 of 14 the normal form gives ±0, and 0 of 14 is not
certainty.

| axis | refused | judged | false | rate (95% Wilson) |
|---|---:|---:|---:|---|
| blind only | 30 | 15 | 9 | **60.0%** [35.7%, 80.2%] |
| both | 80 | 15 | 2 | 13.3% [3.7%, 37.9%] |
| stamp only | 108 | 14 | 0 | 0.0% [0.0%, 21.5%] |
| **record** | 218 | 45 | 11 | **13.1%** [6.3%, 35.6%] stratum-weighted |
| **stamp axis** | 188 | 29 | 2 | **6.9%** [1.9%, 22.0%] the half that blocks |

The record row weights each axis rate by how much of the refused population it
is, because the strata were drawn equally and the population is not.

The last row is the only one that describes the enforced gate. `both` counts
into it because a page failing both axes is still refused by the stamp axis
alone, and the two false ones there are false on the stamp axis too — neither
carries a figure at all.

Every axis in that table is re-derived from the tree as it is now and joined to
the adjudications by path, so a page somebody stamped this morning leaves the
stratum it was judged in and stops counting. That is the right arithmetic and it
is also how a measurement decays quietly into a smaller sample while still
printing a number, so `--rate` closes by saying how many adjudicated pages it
has lost. One has, so far.

## Why the blind axis is wrong three times in five

Nine of the fifteen `blind only` refusals are pages that **did** ask a second
parser and said so in a word the vocabulary has no entry for: *the oracle
defends 611*, *median 2.9x tree-sitter's time*, *4,300 unjudged where the oracle
had nothing to say*. The classifier reads `square|crooked|graded|unframed|soft|
regrouped|relabelled|interstice|askew|tree-identical|trued|unvouched`, and a
page can be scrupulously attributed in English without using one of them.

A closed word list cannot be completed by trying harder at it. That is the same
finding `STAMP`'s own comment already records about anchoring a digest to a
keyword — the keyword-anchored form refused 203 of 263 measuring pages against
184 for the shape-only form, and the 19 extra were pages carrying a digest in a
spelling the list had not met yet.

The remaining false ones are the detector reading a **name** as a figure. Both
changelog fragments the gate refused within the hour of being written are this:
they say ``Same shape as the `damage 0` fix landing beside it``, and the
proximity pass pairs the column name `damage` with the digit `0`. Neither page
is quoting a measurement. Both now pass the enforced gate — they carry stamps —
and both still carry a blind `note:`, which is the correct amount of noise for
a signal that is wrong three times in five.

## The self-comparison spelling

The authoring lane named the shape and declined to widen someone else's
classifier for it: `shear.py` presses the same bytes with the same grammar
twice, so *which oracle* has no answer for it, and `onlydamage.FOREST` has an
oracle-free exemption with no spelling for an instrument that compares a thing
to itself.

`instrument.py` is that spelling, and it is read off the instruments rather
than off a list of their names. For a module a page cites, it parses the record
declarations with `budge.declared` — the same reader the field sweep uses — and
asks four questions:

| question | how it is answered |
|---|---|
| what does it report? | every `_` segment of every field its records declare, so `cut_rubble` and `whole_rubble` both report `rubble` |
| can it be asked an oracle? | does any field it declares carry the oracle's vocabulary |
| does it reach one? | does it import `differential`, the one module in this tree that spawns tree-sitter |
| does it have two arms? | do its fields come in qualified pairs over a shared stem — `whole_roots`/`cut_roots`, `one_first`/`many_first`, `cold_read`/`mean_read` |

An instrument with paired arms, no oracle column, and no reach to the driver is
**self-comparing**, and a figure in one of its columns is exempt from the blind
axis. Nothing here is a name: an instrument written next month is classified by
the shape of its own record. On this tree that reads five self-comparing
instruments — `amend`, `order`, `probe`, `repair`, `shear` — against 39 that can
be asked an oracle, and it puts the module that spawns the oracle on the right
side of the line, which is the check most worth watching fail.

Adjudication is **per column**, not per page, because a page cites several
instruments and quotes several columns. A page is exempt when every column it
quoted with a number beside it is reported *only* by self-comparing
instruments. A column that `standing` also reports is not exempt no matter what
else the page names, and a column nothing on the page reports at all earns
nothing.

**It exempts one page today, and that is the finding rather than a shortfall.**
Of the 111 blind pages: 19 name no instrument, 60 cite code that reports none of
their columns, 31 quote a column an oracle-capable instrument also reports, and
1 is self-comparing. Self-comparison was a real gap, it is now closed, and it
was never the thing making the blind axis wrong — the closed vocabulary is.
Measuring that is why the axis reports instead of blocking.

## What is enforced, how, and what it costs

The `record` job in `.github/workflows/ci.yml`, a fourth kind of news beside the
pins, the press and the topology. Bare checkout, no toolchain, no sibling, and
the only job in the file that takes `fetch-depth: 0` — a forward ratchet needs a
diff, and a depth-1 clone has none.

```yaml
- run: python3 research/joinery/consort/sighting.py --check   # and the gate still bites
- run: python3 research/joinery/consort/sighting.py --gate
```

`--check` is 28 assertions, each built and watched to fail: that the stamp axis
blocks and the blind axis does not, that `--strict` reverses that, that a
seven-digit number is not read as a digest, that the module spawning the oracle
is never exempt, that a column nothing reports earns nothing, that a contents
row asks nothing while a data row does, and that a `--since` asking about fewer
pages is refused while the pin spelled another way is not mistaken for a move.

Cost on the real enforcement path, measured as whole processes with real git,
median of seven:

| pages in the diff | wall (quiet) | wall (nine sibling lanes compiling) |
|---:|---:|---:|
| 1 | 91 ms | 115 ms |
| 10 | 180 ms | 229 ms |
| 25 | 276 ms | 319 ms |
| 50 | 330 ms | 344 ms |

Both columns are on this laptop, hours apart, and the second is the honest one to
plan against: a gate runs while the rest of the branch is working. The live run
at the pin `459c097` is **270 ms** over the twelve pages the diff names, which is
the number that matters — the table above is the shape, this is the gate.

The one number over the ceiling is a diff naming the whole record: **1.2 s** over
409 pages, which was this working tree for the hour between turning the gate on
and the record landing in a commit, so every page was "changed since the pin".
That hour is also the ledger's first real entry: the pin moved from `f7ba400` to
`459c097` and the line says it cleared 219 refused pages, which is the ceremony
working rather than an exception to it. A diff that wide is
either that, or the sweep the ratchet exists to make unnecessary. The gate now
prints its own cost when it crosses a second rather than being quietly slow — a
gate that costs more than it admits is the one that gets switched off.

## Asking about the bytes, not about the file

One edit found the granularity bug. Adding five rows to this dossier's table of
contents made this lane answerable for 23 figures further down the page that
somebody else wrote months ago. "Refuses a page the diff names and never a page
already written" is only true if *written* means the bytes.

So a page is asked when the lines it **gained** carry a measured figure. A
contents row, a link, a fixed typo and a paragraph of prose ask nothing. An
added *data* row does, and getting that right is the only subtlety: the hunk
holds `| 311,540 |` and the word `square` is three hundred lines up in a header
that did not move, so every table's header is re-seated over the diff hunk
before the count is taken. Headers that name no column are skipped, which is
exact rather than approximate — a header with no column name cannot pair with
anything, whatever row is put under it. An untracked page has no diff and is
asked whole, which is right: every byte of it is new.

On this tree that spares six pages a run today. It will spare more as the
record gets committed and edits stop being whole-file.

One duplicated pass came out on the way. `onlydamage.read` already computed
which of our columns carried a number and threw the words away, and the caller
that needed them recomputed the same pass — a quarter of the read's cost, and a
second chance to disagree with the count standing next to it. It now carries
them. Verdicts before and after are identical over all 407 pages.

## Making the ref movable only in public

A forward ratchet is honest exactly as long as nobody can nudge the ref past an
inconvenient page. The pin lives at `sighting.since`, it is committed, and it is
append-only; the live pin is the last line. Four things stand behind it:

1. **Every run prints it, pass or fail** — the ref and its age, before any
   verdict, so it is never off-screen in the log of the run it silenced.
2. **A working-tree copy that differs from the committed one refuses the run**
   at exit 2. Moving the pin costs a reviewed commit and can never be a local
   convenience.
3. **`--since` may only reach further back than the pin.** Asking about more
   pages is how a lane checks its own work harder than CI will; asking about
   fewer is the pin moved by a flag, and it exits 2. Both refs are resolved
   before they are compared, so `--since HEAD` on the day the pin *is* HEAD is
   recognised as the same ref rather than refused as a move.
4. **`--pin` says what the move buys before it writes it.** It prints exactly
   which currently-refused pages would stop being asked, then appends a row
   carrying that count and a mandatory `--because`. A move that clears pages has
   to be typed next to the number of pages it clears.

## Adoption

The refusal message hands over the command that clears it, with the page's own
column in it — `standing.py --cite` when nothing summable was quoted, and
`--cite=<the board this number came from> --quote=<column>` when something was,
because that form renders the figure and the world it was taken in from the same
board and so cannot drift the way a hand-pasted pair can. `--cite` is 188 ms and
one markdown line; the stamp on this page came from it.

## What this does not claim

The stamp check is **presence, not binding**. A digest anywhere on the page
satisfies it, so a fresh `--cite` pasted beside a stale number passes cleanly.
`RESULT-11-quotation.md` establishes that binding the two is unreachable — the
binary may be a pruned arm, the tree may never have been committed, and a press
costs ~30 s against a 1 s ceiling — and the gate now says so in its own output
rather than letting the pass read as a guarantee.

## Promotion criterion for the blind axis

One number: `--rate` reading under 10% false for `blind only` on a fresh seed.

The way there is not a longer word list. It is a reading of "asked a second
parser" that is not a vocabulary at all — the oracle's identity is already on
the board as `still.Witness.asked`, so a page carrying a `--cite` line that says
how many oracles were in the room needs no words for it. That makes the blind
axis a consequence of adoption rather than a competitor to it, which is the
right order: the stamp axis blocking is what drives `--cite` onto pages, and
`--cite` on pages is what makes the blind axis measurable.

# Result 1 — every field this tree reports, and whether it has ever moved

Measured 2026-08-06 on this machine, against
[`PREDICTION-1-sweep.md`](PREDICTION-1-sweep.md), which was written before
`tool/budge.py` existed.

## What the sweep is

`still against` refuses a comparison whose evidence is byte-identical either
side of the treatment, as `vacuous`: an instrument that did not respond to your
change cannot clear it. That argument was never about boards. It is about
values, and a board is the coarsest unit it can be applied to. `budge` applies
it to the smallest one — a single field of a single record — and the finding it
was built for is the shape of `0 oracle(s)`: a column that read the same thing
on every run for the whole life of the field while everything printed beside it
moved constantly.

Two halves, for the reason `still sweep` has two:

- **static** — every record in `tool/` and `research/`, every field it declares,
  and every place in the source that can decide that field's value. **107
  records, 784 fields.** Complete over the tree and blind to values.
- **dynamic** — every value each of those fields has actually held, harvested
  out of the JSON this tree has already written. **2,516 documents, 250 MB,
  13,687 objects attributed** to a record; 2.4 M objects matched none, 8 fit two
  records equally and were charged to neither.

An object belongs to a record when it carries all of that record's
non-defaulted fields, and the tighter fit wins a contest. A **missing** key is
not a value — it is recorded as `silent` — because "the board predates this
field" and "the field holds nothing" are different sentences and the first one
is not a finding.

| verdict | what was observed |
|---|---|
| `budged` | two or more distinct values. Alive |
| `flat` | exactly one, and not an empty one. A constant |
| `void` | every observation empty — `{}`, `[]`, `""`, null. It has never held anything |
| `silent` | the record reached disk N times and this key was never on it |
| `unseen` | no document carried the record at all. A hole in the sweep, printed as one |

| why | what the source and the population say |
|---|---|
| `unwritten` | nothing in the tree sets it |
| `sealed` | one writer and it is a literal. Constant by construction |
| `unasked` | its one value is a default its own CLI declares. Nobody passed the flag |
| `open` | the record moved — siblings took several values — and this did not |
| `thin` | the record never moved either. A corpus finding, not a field finding |

`0` and `false` are values. A boolean that is always false is `flat`, never
`void`, because it may be exactly right.

## The falsifier, first

`budge verify` writes three witnesses into a scratch scope twice over, differing
in one thing: which rule fills `Witness.oracles`. The shipped bug is still in
the tree under its own name — `still.stems`, kept so the fix has something to be
a fix *of* — so restoring it needs no edit to a file nine other lanes are
working in.

It also **plants its own three-grammar corpus** in the temp tree it deletes on
the way out, rather than reading the thirty a sibling lowered into `.local`. The
first version read the real corpus and that was wrong twice: a gate needing a
corpus somebody else happened to lower is red on a fresh clone for a reason that
is not its own, and a falsifier reading nine other agents' scratch cannot say
whether it held because the detector works or because of what was lying around.
The planted homes only have to be distinct and shaped `lang/<name>/src/
grammar.json`, because what is under test is which of two rules recovers
`<name>` from that path — and the file is still called `grammar.json`, so the
retired rule still asks for a language called `grammar` and still misses. Run
with `tree-sitter` off `PATH` entirely, all five rows hold.

```text
held    the shipped rule (stem of grammar.json, so always 'grammar')
        Witness.oracles reads void/open - {} ×3; wanted void
held    the current rule (the grammar its path names)
        Witness.oracles reads budged/- - 3 value(s), least 1/3; wanted budged
held    restoring the bug moved 1 of 18 field(s) of the same record: oracles
held    a scope with no documents reports 18 of 18 field(s) unseen, and no field budged
held    and it fails nothing: 0 red
```

**One of eighteen.** Breaking one field turns one row red and leaves the other
seventeen exactly where they were. The last two rows are the other direction: an
empty population must report that it has no opinion, and must not fail anything
for it — a sweep that reddens on absence of evidence is noise, and noise gets a
flag from the second person who meets it.

## What fell out — 14 findings over 784 fields

| verdict × why | unwritten | sealed | unasked | open | thin | — |
|---|---|---|---|---|---|---|
| `budged` | 0 | 0 | 0 | 0 | 0 | **360** |
| `flat` | 0 | 0 | 1 | **10** | 17 | 0 |
| `void` | 0 | 1 | 0 | **4** | 2 | 0 |
| `silent` | 0 | 0 | 0 | **1** | 0 | 0 |
| `unseen` | 0 | 5 | 0 | 0 | 383 | 0 |

**Fifteen** fields read `open`; one of them carries a declared excuse and is
printed under it, leaving the fourteen below. Four are in files this lane owns;
the rest are reported and not touched.

| field | reads | note |
|---|---|---|
| `field.Press.reason` | `""` ×640 | five writers, four of which produce a real string. Not one of the 640 rows on disk holds any of them |
| `stamp.Ledger.moved` | `[]` ×55 | the ledger's whole point is naming an artifact that moved under a run; it has never named one |
| `stamp.Ledger.republished` | `[]` ×55 | same record, same shape |
| `still.Witness.lowered` | `{}` ×19 | **mine** — see below |
| `walls.Priced.roofed` | key absent ×501 | declared, and no `Priced` on disk carries it |
| `attest.Oracle.cli` | `tree-sitter 0.26.11` ×390 | **mine** — one CLI has ever been installed here |
| `attest.Oracle.asked` | `true` ×300 | **mine** — every stored oracle row came from a consulting run |
| `rack.Seen.renamed` | `0` ×300 | another lane's; reported, not touched |
| `shear.Cut.cut_rubble` | `0` ×95 | |
| `stamp.Ledger.artifacts` | `31` ×55 | fifty-five ledgers, each naming thirty-one artifacts |
| `bench.Row.axis` | `press` ×33 | six axes declared, one measured on disk |
| `bench.Row.unit` | `ms` ×33 | |
| `still.Witness.asked` | `false` ×19 | **mine** — see below |
| `repair.Reuse.beats` | `60` ×3 | |

### The two on the witness are the same finding, and it is not a defect

`still.Witness.asked` is `false` on all nineteen witnesses that record it, and
`still.Witness.lowered` is `{}` on all nineteen. Those are one fact: **no
witness on this disk was taken by a run that actually consulted the oracle.**
Every one of them attributed a court rather than asking it.

Driven directly — consult one grammar through `attest.consult`, then take a
witness — both fill immediately:

```text
asked: True | lowered: {'json': '2fa6cfe6'} | oracles: 1
```

So the fields are right, the writers are right, and the corpus of witnesses is
the thing that is narrow. This is `absent.py`'s finding wearing a witness's
clothes, and the remedy is a witness taken by the next `rack` or `absent` run,
not a line of code. The sweep still reports it red, and should: nineteen
consecutive witnesses asserting the same thing about a parser they never opened
is worth one line in a report.

### `attest.Oracle.cli` is the honest limit of the `open`/`thin` split

`cli` reads `tree-sitter 0.26.11` on all 390 rows because one tree-sitter has
ever been installed on this machine. That is a **corpus** finding, and the sweep
calls it `open` because the siblings beside it — `tree`, `newest`, `lib`, `seat`
— move on every row. Sibling variation is the right generalisation of `vacuous`
and it cannot tell "this column is wrong" from "this column can only move if you
install a second tree-sitter".

One rung of that gap closed mechanically and is worth having. `amend.Row.grammar`
read `json` ×168 with every sibling column moving, which is the identical shape;
`amend.py --grammar` **defaults** to `json` and no run has ever passed the flag.
So the sweep now reads each module's own `add_argument(default=…)` strings and
reports a field whose single value is one of them as `unasked` — a fact about
how the instrument has been invoked, remedied by an invocation. Strings only:
`0`, `False` and `""` are the defaults of half the flags in this tree and
matching on them would turn real findings amber by coincidence.

The residue after that is ten `flat/open` rows, which is a number a person can
read. The report says so in its own footer: a red row is a field to **look at**,
not a field proven broken.

### Two things the static half found on its own

**Zero fields are `unwritten`.** Every declared field of every record has at
least one writer somewhere in the tree, which is P6 and it held — but only after
the reader was fixed twice, and both bugs were the same bug this whole lane is
about. Twelve modules declare a record called `Row`; resolving a bare `Row(...)`
by name alone charged every writer to one arbitrary `Row` and reported the other
eleven's fields as unwritten. And `walls.py`'s `Priced(k, w, *rest, bool(…))`
puts a splat in the middle, so positional index 4 is not field 4 — the reader
now stops mapping at the splat and charges the remainder to an unknown writer,
because guessing would have put the last argument on the wrong field. A tool for
finding fields that report the wrong thing, reporting the wrong thing.

**Six fields are `sealed`** — one writer, and it is a literal. Five are
`unseen`, one is `rung1.Result.faults` at `[]` ×22.

## Scoring the predictions

Two readings were taken during orientation, before the prediction file was
written, and it says so: the 33 witnesses counted by `len(oracles)`, and `asked`
coming back `False` on the four that recorded it. Neither is scored.

| | prediction | outcome |
|---|---|---|
| **P1** | the restored bug lands in `void`, not `stuck` | **held.** `void/open`. An empty dict is no value, not one value |
| **P2** | `oracles` is not the only dead field on the witness, and it is a real finding rather than a thin population | **half.** Two more — `lowered` and `asked` — but both are thin populations. The second clause is wrong |
| **P3** | `narrow` + `unseen` outnumber `stuck` by more than 2:1 | **held**, and by far more: 402 `thin` and 388 `unseen` against 10 `flat/open` |
| **P4** | the sweep finds at least one stuck field in **itself** on the first run, and it will be a column added for completeness | **half.** Pointed at itself it found nothing, because it had never written a record to disk — nineteen of nineteen `unseen`, exempt from its own rule by leaving no trace. Given `--keep`, `budge.Verdict.excuse` came back `void`: exactly the column-added-for-completeness the prediction named, and `void` rather than `flat` |
| **P5** | the three-function digest misses ≥2 names those functions read, ≥1 outside `attest` | **held exactly.** `split` (609 bytes, in `attest`) and `differential.INCLUDE` (in another module) |
| **P6** | every declared field has ≥1 writer | **held** — 0 `unwritten` of 784 |
| **P7** | under 300 ms for the disk-only tier | **wrong.** 2.9 s over the full 250 MB, 0.66 s for the static half alone. The miss is the whole gating argument below |

Four held, two half, one wrong.

## Cost, and whether this should gate

Measured on this machine, three runs each, wall clock:

| rung | cost | what it claims |
|---|---|---|
| `budge verify` | **2.12 s** | the detector still detects. Hermetic — no corpus, no other lane's scratch |
| static half alone | **0.66 s** | every declared field has a writer. No observations, no verdicts |
| `budge --budget 16` | **1.17 s** | 1,409 of 2,518 documents, and **the wrong answer** |
| `budge --budget 0` | **2.9 s** | all of it |
| `budge against <kept board>` | +0 s | newly-red rows only, over a board already taken |

**A budgeted sweep is not a subset of a full one, and that is the measurement
that decides the recommendation.** Against the full board, an 8 MB sweep
disagrees on **sixteen** rows: eleven read red that read green over all 250 MB —
every one of `walls.Warm`'s six among them — and five read green that read red,
including `field.Press.reason`, the largest finding on the board, which reads
green as `thin`, the verdict meaning *the corpus is too narrow to say*. The
budget changes the verdict in both directions, because whether a record "moved"
is a claim about the population and a partial population is a different claim.
So the cheap tier cannot gate — it would fail pushes over fields that are fine
and pass ones that are not.

The recommendation, then:

1. **`budge verify` joins the gate, and has** — one step in CI's `grammars` job,
   the deliberately toolchain-free one, beside `sole.py --probe`, which is the
   same shape of assertion (*and the gate still bites*). 2.12 s, no build, no
   network, no dependence on what any lane left in `.local`, and it is the row
   that fails when somebody weakens the detector.
2. **`budge --budget 0 --keep` does not go in a hook.** Three seconds is over
   this project's standing bar, and worse, it reads 250 MB of nine other lanes'
   scratch — so two agents running it a minute apart legitimately get different
   answers. It belongs where a board refresh belongs: run it after changing a
   record, and file the board.
3. **`budge against` is the part that is cheap enough to gate**, and it is what
   makes "a sweep that must be remembered" unnecessary. It differences a fresh
   board against the last kept one and fails only on **newly** red rows, so the
   fourteen findings above do not have to be fixed before the gate is useful —
   which is the ratchet shape every baseline in this tree already uses. It
   refuses two boards taken under different budgets or scopes at exit 4, in the
   same words and for the same reason `still against` refuses two arms from
   different trees — the population alone moves sixteen rows — and it names the
   invocation that would have been comparable rather than only refusing.

The honest cost of (3) is that it still has to take the board — the three
seconds is in the `against` run too. What it buys is that the three seconds only
has to be paid where somebody is already waiting on a full sweep, and the answer
is a delta rather than a wall of pre-existing rows.

## Instance three, closed

`attest.rule()` hashed the source text of three functions and called the result
"the rule". It is not the rule; it is three quarters of the rule and a claim
about the rest. `sources` calls **`split`**, which lives in `attest.py` and was
not one of the three, and matches against **`differential.INCLUDE`**, which does
not live in `attest.py` at all — so the entire include-closure half of an
oracle's identity could have been rewritten from another module with the digest
holding still. That is the failure the digest exists to catch, one level up.

It now digests the transitive closure of what the seeds actually read: walk the
syntax, resolve every global name and every `module.attr`, fold the source of
anything defined in this tree and the *value* of anything constant, recurse.
Seven names, and `attest.py rule` prints them:

```text
rule 8910687a2 - the closure of survey, sources, lowered

covered                       kind       bytes
LOWERED                       data          30
LOWERED_DIR                   data          13
d.INCLUDE                     data          34
lowered                       code         564
sources                       code        3003
split                         code         609
survey                        code        2057
```

**And it prints what it cannot cover, in the tool rather than in a dossier**,
because the number is read in the tool: `still against` refuses two arms whose
rules differ and `attest list` calls a pin retired, and both quote nine
characters of it. The boundary rows are the seven stdlib and module names the
closure stops at, each with the reason it stops there, under the sentence that
states the claim exactly: *the seven names above have not changed.* It is not a
claim that two oracle digests are comparable — the stdlib, the tree-sitter CLI
and the bytes on disk are the other three, and `Oracle.cli`, `tree` and `lower`
carry those. A live object the renderer cannot reproduce would be listed
`opaque` and would exit 1, because that is a hole rather than a bound; there are
none today.

Eight rows in `attest verify` hold it to that, and the load-bearing four are
**paired against the rule it replaced**, kept as `narrow()` for the reason `was`
and `stamp.py --verdicts` are kept:

```text
MOVES when `differential.INCLUDE` changes                8910687a2 → 29005f628   yes
...where the rule this replaced holds, having never read it   08fe2ec8b = 08fe2ec8b   yes
MOVES when `split` changes                               8910687a2 → 537c98600   yes
...where the rule this replaced holds for that too       08fe2ec8b = 08fe2ec8b   yes
MOVES when `LOWERED` changes                             8910687a2 → 0deba12bb   yes
HOLDS when `PINS` changes — something the rule does not read  8910687a2113        yes
```

Both directions, because only the pair is evidence. Moving when its closure
moves proves the new rule is self-consistent, and every rule is that. Holding
when `PINS` moves is the half that makes the digest usable at all: a rule that
moved on any edit to `attest.py` would retire every pin on the machine every
time somebody fixed a docstring three functions away.

**What this costs.** The rule digest moved from `08fe2ec8b` to `8910687a2`, so
every pin taken before today reads `retired` in `attest list`. Nothing false is
printed: `minted()` re-derives a pin's rule by re-digesting three of its own
rows rather than trusting the stamp, and two of the five pins still read
`current` on that measurement. The three that read `retired` read retired
before this change too, for the older `survey` reason.

## The instrument I trust least

**`budge`'s own `open`/`thin` split**, and the reason is not that it is new.

Everything else here degrades safely. `unwritten` is a syntactic claim and
observation is allowed to overrule it, and does — the footer counts the
contradictions rather than reddening a field that demonstrably works. `unseen`
says the sweep has no opinion. `thin` hands the row to `absent.py`. `sealed` and
`unasked` are read off the source, so they are checkable by reading it.

`open` is the one that convicts, and it convicts on a **proxy**: some other
column of the same record took two values, therefore the population moved,
therefore this column's stillness is about the column. `attest.Oracle.cli` is
the counterexample sitting in the report — it can only move if you install a
second tree-sitter, and no amount of sibling variation is evidence about that.
Ten of the fourteen findings rest on that inference and I can name at least
three where it is the wrong reading.

Passing its own check did not clear it, and this is the specific way. Pointed at
itself on the first run, `budge` reported nineteen of nineteen of its own fields
`unseen` — perfectly green, and green because it had never written a record to
disk. An instrument that leaves no trace is exempt from every rule that reads
traces, which is the same exemption `attest.rule()` had when its verify row
proved the digest reads a field rather than that the field is the rule. `--keep`
removes the exemption: the board is written **after** the read, so no run scores
its own homework, and the next run finds `budge.Verdict` in its own population.
It immediately found a dead column of its own — `excuse`, `void` over 783 rows,
because nothing in the tree had ever claimed an excuse. One real annotation on
`attest.Oracle.lowers` later, all eleven of its columns budge.

That is the sweep catching itself once. It is not evidence that it would catch
itself twice.

`still against` refuses a comparison whose evidence is byte-identical either
side of the treatment, as `vacuous`: an instrument that did not respond to your
change cannot clear it. That argument was never about boards. It is about
values, and a board is the coarsest unit anyone had applied it to. A single
column reading the same thing on every run for the whole life of the field is
vacuous by the identical reasoning, and the twenty-five green rows around
`0 oracle(s)` are what it costs to have no instrument for it.

`tool/budge.py` runs it one level down. Static half: every record in `tool/` and
`research/`, every field it declares, and every source expression that can
decide that field's value - **107 records, 784 fields**, complete over the tree
and blind to values. Dynamic half: every value each field has held in the JSON
this tree has already written - **2,516 documents, 250 MB, 13,687 objects
attributed** to a record, 8 that fit two equally and were charged to neither.

A field with one value is four findings and they are not interchangeable.
`budged` two or more. `flat` exactly one, non-empty. `void` every observation
empty - and `0` and `false` are values, so a boolean that is always false is
`flat` and may be right. `silent` the record reached disk and the key never did.
`unseen` no document carried the record, which is a hole in the sweep and is
printed as one. Then *why* it did not move: `unwritten` nothing sets it,
`sealed` one writer and it is a literal, `unasked` its one value is a default
its own CLI declares, `open` the record moved and this did not, `thin` the
record never moved either. Only `open` and `unwritten` convict; `thin` belongs
to `absent.py` and is answered by widening the corpus.

**14 findings over 784 fields**, measured 2026-08-06. `field.Press.reason` is
`""` on all 640 rows on disk against five writers, four of which make a real
string. `stamp.Ledger.moved` and `republished` are `[]` on all 55 - a ledger
whose whole point is naming an artifact that moved under a run has never named
one. `walls.Priced.roofed` is declared and absent from all 501 `Priced` on disk.
`still.Witness.asked` is `false` and `lowered` is `{}` on all 19 that record
them, which is one fact: no witness here was taken by a run that consulted the
oracle rather than attributing one. Driven directly it fills
(`asked: True | lowered: {'json': '2fa6cfe6'}`), so that pair is a narrow
corpus and not a defect - and is still worth the line.

`verify` restores the shipped bug through `still.stems`, which is in the tree
precisely so the fix has something to be a fix of, and requires **one of
eighteen** fields of the same record to redden. It also requires an empty
population to report eighteen `unseen` and fail nothing, because a sweep that
reddens on absence of evidence gets a flag from the second person who meets it.
It plants its own three-grammar corpus in the temp tree rather than reading the
thirty a sibling lowered into `.local` - a falsifier reading nine other agents'
scratch cannot say whether it held because the detector works or because of what
was lying around - so it holds with `tree-sitter` off `PATH` and on a fresh
clone. That is what earns it a seat in CI's toolchain-free `grammars` job, beside
`sole.py --probe`, which is the same assertion about a different gate.

Two static bugs found on the way, both the class the sweep exists for. Twelve
modules declare a `Row`, so resolving a bare `Row(...)` by name charged every
writer to one arbitrary record and reported the other eleven `unwritten`. And
`walls.py`'s `Priced(k, w, *rest, bool(...))` puts a splat mid-call, so
positional index 4 is not field 4 - the reader stops mapping at the splat and
charges the remainder to an unknown writer rather than guessing.

Cost, three runs each: `verify` 2.12 s hermetic, static half alone 0.66 s, the
full sweep **2.9 s** over all 250 MB. It is not gateable at that price and a
budget does not rescue it, it changes the answer: under the default budget six
of `walls.Warm`'s columns read red that read green over the whole population,
and `field.Press.reason` - **the largest finding on the board, 640 rows** - reads
green, and green as `thin`, which is the verdict meaning *the corpus is too
narrow to say*. A partial population is a different verdict, not a cheaper one,
which is why the board records the budget it was taken under. `against` is the
rung that gates - it differences a fresh board against a kept one and fails only
on **newly** red rows, so the fourteen do not have to be fixed before it is
useful. Two boards taken under different budgets or scopes it refuses at exit 4,
in the same words `still against` refuses two arms from different trees, and it
names the invocation that would have been comparable rather than only refusing.

`research/joinery/budge/` carries the predictions (four held, two half, one
wrong - the wrong one is the cost) and the full board.

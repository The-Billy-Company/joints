# Prediction 1 — what a per-field variation sweep will find

Written before `tool/budge.py` exists and before any sweep has been run.

## What was measured before this file was written, and is therefore not predicted

Honesty first, because the lane before me declared the same thing. Two readings
were taken during orientation, before a word of this file:

1. The 33 witnesses under `.local/still/witness/` were counted by
   `len(oracles)`: **29 read 0, three read 30, one reads 0**. That is the shipped
   `0 oracle(s)` bug on one side of its fix and the fix on the other.
2. In the same four lines, `asked` came back `False` on the four witnesses that
   record it at all and absent on the other 29.

Neither is scored below. Everything else here was written first.

## The design being predicted against

A field is a path into what an instrument reports. The sweep has two halves,
deliberately, on the same argument `still.sweep` makes for its own two:

- **static** — every field an instrument *declares* it reports, read out of the
  source. The denominator, complete over the population, and blind to values.
- **dynamic** — every value each of those fields has actually taken, harvested
  from the JSON already on this disk. The numerator, and honest about its reach.

Five verdicts, ordered by strength of claim:

| verdict | one value, and… |
|---|---|
| `budged` | no — two or more. Alive |
| `void` | every observation is empty: `{}`, `[]`, `""`, absent. It has never held anything |
| `stuck` | one non-empty value over a population whose other fields moved |
| `narrow` | one value over a population that never varied. A corpus finding, not a field finding |
| `unseen` | declared and never observed. A hole in the sweep, printed as one |

## The predictions

**P1 — the restored `0 oracle(s)` bug lands in `void`, not in `stuck`.** An empty
dict is not one value; it is no value, and the two deserve different words. If it
lands in `stuck` the partition is wrong.

**P2 — `oracles` is not the only dead field on the witness.** At least one more
field of `still.Witness` comes back `void` or `stuck` across the witnesses on
disk, and it is a real finding rather than a thin population.

**P3 — `narrow` plus `unseen` outnumber `stuck` by more than two to one.** Most
constancy in this tree is a corpus that never presented the second value, which
is `absent.py`'s finding wearing a different hat, not a broken field.

**P4 — the sweep finds at least one stuck field in itself on the first run.** It
is a field-reporting instrument and it is the first thing it should be pointed
at. I expect the guilty one to be a column I added for completeness and populated
from a single code path.

**P5 — `attest.rule()`'s three-function digest misses at least two names its own
three functions read**, and at least one is not in `attest` at all. `sources`
calls `split` and reads `differential.INCLUDE`; neither is in the digest.

**P6 — every declared field of every record has at least one writer in the
source.** If any has zero, the field is dead in the strongest sense and the
static half alone catches it without a single observation.

**P7 — cost under 300 ms** for the disk-only tier, on the standing rule that
local tooling must not tax the machine. If it needs a run of `standing.py` to say
anything it will not be run, and a sweep nobody runs is not a sweep.

## The falsifier, named before it is built

Restoring the shipped bug must turn the `oracles` row red and leave every other
row where it was. A sweep that goes red everywhere when one field breaks is a
sweep that will be passed with a flag by the second person who meets it.

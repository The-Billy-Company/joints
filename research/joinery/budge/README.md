# budge — a field that has only ever held one thing

Three fields shipped in one day that read something real, faithfully, which was
not the thing they were named after. The worst of them returned the same value
for every input on every run for its whole life, and twenty-five green rows did
not notice, because every one of them handed the comparison a record somebody
had typed by hand — proving the predicate, never the filling.

This lane is the generalisation of the check that catches the class.
[`../vacuity/`](../vacuity/README.md) is `still against` refusing evidence that
is byte-identical between two arms: an instrument that did not respond to the
treatment cannot clear it. `budge` runs that argument one level down, on a
single field of a single record, over every value that field has held in every
JSON this tree has written.

| file | what it is |
|---|---|
| [`PREDICTION-1-sweep.md`](PREDICTION-1-sweep.md) | written before `tool/budge.py` existed, declaring the two readings taken before it |
| [`RESULT-1-sweep.md`](RESULT-1-sweep.md) | 784 fields, 14 findings, the falsifier, the cost, and instance three closed |

```text
python3 tool/budge.py                        the sweep
python3 tool/budge.py show still.Witness     one field: writers, values, documents
python3 tool/budge.py --keep                 file the board, so the next run sweeps this one
python3 tool/budge.py against                newly-red rows against the last kept board
python3 tool/budge.py verify                 restore the shipped bug; watch one row of eighteen go red
```

Read [`../still/RESULT-5-oracle.md`](../still/RESULT-5-oracle.md) first for
where the class was named, and the sixth house rule in
[`../TESTING.md`](../TESTING.md) for why a measurement that agrees with itself
by construction is the failure mode this repository keeps paying for.

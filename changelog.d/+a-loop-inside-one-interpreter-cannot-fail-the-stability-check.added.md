Four lanes are running before/after measurements and each was being told by hand
to give every arm its own `OUTLINER_WORK`. The recipe now lives where a lane
trips over it — `tool/README.md` under `pin.py`, and as the third house rule at
the top of `research/joinery/TESTING.md`, beside the two about pricing both
halves and naming your instrument:

```sh
eval "$(python3 tool/pin.py arm before)"          # BIN + WORK + LANE, all under the pin
python3 tool/standing.py --json > before.json
eval "$(python3 tool/pin.py arm after)"
python3 tool/standing.py --against=before.json    # every cell, plus what differed
python3 tool/standing.py --twice=3                # is this row stable at all?
```

**A binary is one third of a measurement.** The other two thirds are each their
own way to read one arm twice. `OUTLINER_WORK` belongs under the pin because a
folio is a derived artifact of a binary; the ticket in `order.py` now refuses to
serve one pin's folio to another, but a shared cache still costs both arms a
full re-press on every alternation. `OUTLINER_LANE` belongs under the pin
because without one the oracle seat is keyed on `os.getppid()` — *which shell
you ran from* — and the oracle is the other parser in every audited column.

**`--twice=N` re-runs the board as N separate processes, and that is the whole
point of it.** A loop inside one interpreter inherits the folio decisions, the
`accepts` memo and the oracle identity from the first pass, so it re-prints the
first answer N times and reports the agreement as stability. It cannot fail.
Only a fresh process re-asks every question, which is why `--twice` shells
`sys.executable` rather than calling `table()` in a loop — and it is the part
people get wrong, because the cheap version looks like it is testing the same
thing.

`--against` prints movement and provenance **separately**, so a `crooked` that
moved because the oracle moved is never read as a board that wanders.

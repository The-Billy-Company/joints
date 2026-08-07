Two runs are comparable when they were measured the same way, and nothing on the
board said whether they were. Three additions, none of which pins a number.

**`standing.py --twice[=N]`** re-runs the board as *N separate processes* and
diffs every cell. Separate processes on purpose: a loop inside one interpreter
inherits the folio decisions, the `accepts` memo and the oracle identity, and
would report a stability it never tested. Tier 1 over five runs on one pin:
`900 number(s) compared · STABLE`. Tier 2, wiping the folio cache between runs,
the same 900 including across the warm/cold boundary.

**`standing.py --against=FILE`** diffs this tree against a saved `--json` run and
reports **what moved and what the runs differed in, separately**, so a `crooked`
that moved because the oracle moved is never read as a board that wanders:

```
2 run(s) · 30 grammar(s) × 31 column(s) = 930 number(s) compared
  [1] arm-tenon.json  tree fa7fcaee5e14  built 2026-08-06T00:05:08Z  one generation
  [2] this tree       tree 0177d3b91eab  built 2026-08-06T01:57:45Z  one generation
  2 binaries — what moved may be the change under test
MOVED — 20 of 930 numbers, over 2 grammar(s):
  php  built 59146 → 67845 · roots 119 → 1 · damage 8699 → 0 · … · verilog nodes 22222 → 22210
```

**`pin.py arm <name>`** prints the three exports a measurement actually needs,
because a binary is one third of one:

```sh
eval "$(python3 tool/pin.py arm before)"
```

`JOINTS_BIN` is the pin. `JOINTS_WORK` is a folio cache **under that pin** —
a folio is a derived artifact of a binary, so a pin owning a binary should own
what it presses into, and the alternative is the cache hazard fixed alongside
this. `JOINTS_LANE` is an oracle seat named after the pin, because without one
the seat is keyed on `os.getppid()` — *which shell you ran from* — and the
oracle is the other parser in every audited column.

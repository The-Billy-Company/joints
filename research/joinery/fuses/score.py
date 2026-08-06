#!/usr/bin/env python3
"""Per-grammar `square` across a set of `rack.py run --json` boards.

`square` is the only column here that is agreement with a second parser, so it
is the one a capacity arm is judged on. Two things this prints that a diff of
the two summary lines cannot: which grammar moved, and the total **without
verilog**, whose oracle row was repaired hours before these arms were taken - a
freshly-repaired reference agreeing with a change looks the same whether the
change is right or the reference drifted toward it.

    ./score.py .local/fuses/fz-control.json .local/fuses/fz-crowd.json ...

The first board is the control and every later one is scored against it.
"""

import json
import pathlib
import sys

WITHHELD = ("verilog",)


def board(p: str) -> dict[str, int]:
    d = json.loads(pathlib.Path(p).read_text())
    rows = d["row"]
    if isinstance(rows, dict):
        rows = list(rows.values())
    out = {}
    for r in rows:
        name = r.get("grammar") or r.get("name")
        if name is not None and "square" in r:
            out[name] = r["square"]
    return out


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    names = [pathlib.Path(p).stem for p in argv]
    b = [board(p) for p in argv]
    every = sorted(set().union(*(set(x) for x in b)))

    w = max(len(n) for n in names) + 2
    print(f"{'grammar':<20}" + "".join(f"{n:>{w}}" for n in names) + "   moved")
    for g in every:
        cells = [x.get(g, 0) for x in b]
        moved = "" if all(c == cells[0] for c in cells) else "  <-"
        mark = " *" if g in WITHHELD else ""
        print(f"{g + mark:<20}" + "".join(f"{c:>{w}}" for c in cells) + moved)

    for label, keep in (("TOTAL", lambda g: True),
                        ("TOTAL without verilog", lambda g: g not in WITHHELD)):
        tot = [sum(v for g, v in x.items() if keep(g)) for x in b]
        print(f"\n{label:<20}" + "".join(f"{t:>{w}}" for t in tot))
        print(f"{'delta vs control':<20}" + "".join(f"{t - tot[0]:>+{w}}" for t in tot))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Did any arm move a grammar its rows cannot seat? Every column, every arm.

`sighted.py score` prints the three columns a reader wants to see. This asks
the falsifier instead, and asks it as widely as the board can be asked: for
each arm, take **every numeric column of every grammar the arm's rows do not
own** and require it to be byte-identical to the base arm. One differing cell
anywhere is collateral and the whole clearance is gone.

The point of doing it here rather than in `score` is that a clearance quoted
off three columns is a clearance quoted off three columns. `RESULT-2-arms.md`
cleared this same family on "thirty-one columns" - and every one of those
columns was outliner's own words about its own forest, because `square` read
0 on all of them. This run has `square`, `crooked`, `soft`, `unframed` and
`trued` live on 29 of 30 rows, so the same width of check is now half oracle.

    python3 collateral.py            every arm against base
    python3 collateral.py --loud     also print the columns that were compared
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from sighted import BOARDS, OWNER, PLAN, tag_of  # noqa: E402

# `graded` is a verdict's own liveness and `held` is its digest bundle: both are
# about the audit rather than the parse, and a row can change either without a
# byte of the forest moving. Everything else on the row is fair game.
ABOUT_THE_AUDIT = {"name", "graded", "held", "verdict", "basis", "set_"}


def numeric(row: dict) -> dict[str, int | float]:
    return {k: v for k, v in row.items()
            if k not in ABOUT_THE_AUDIT and isinstance(v, (int, float))}


def main(argv: list[str]) -> int:
    base = json.loads((BOARDS / "base.json").read_text())
    was = {r["name"]: numeric(r) for r in base["row"]}
    cols = sorted(next(iter(was.values())))
    if "--loud" in argv:
        print(f"\n  {len(cols)} columns compared: {', '.join(cols)}")
    print(f"\n  {'arm':<9}{'seats':<26}{'checked':>9}{'cells':>8}   collateral")
    hits, arms = 0, 0
    for rows in PLAN[1:]:
        tag = tag_of(rows)
        at = BOARDS / f"{tag}.json"
        if not at.exists():
            continue
        arms += 1
        now = {r["name"]: numeric(r) for r in json.loads(at.read_text())["row"]}
        mine = {OWNER[r] for r in rows if r in OWNER}
        others = [g for g in was if g not in mine]
        moved = {g: {k: (was[g][k], now[g].get(k)) for k in was[g]
                     if was[g][k] != now.get(g, {}).get(k)} for g in others}
        moved = {g: d for g, d in moved.items() if d}
        hits += len(moved)
        print(f"  {tag:<9}{','.join(sorted(mine)):<26}{len(others):>9}"
              f"{len(others) * len(cols):>8}   "
              + (", ".join(f"{g} {d}" for g, d in moved.items()) if moved else "none"))
    print(f"\n  {arms} arm(s) · 0 collateral is the claim · {hits} grammar(s) moved\n")
    return 1 if hits else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

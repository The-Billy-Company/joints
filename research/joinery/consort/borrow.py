#!/usr/bin/env python3
"""Where a negative `crooked` comes from: `soft` draws from a kind it cannot spend.

One arm on this disk printed `crooked = -335` and another printed
**`crooked = -8,669`**, and the board's own consistency check passed both times,
because the four buckets still total `built` - a bucket that overdraws from its
neighbour leaves the sum alone.

The arithmetic is one line of `standing.audit()`:

    soft = sum(w.width for w in seen.worst if <blank or extra-named>)
    Held(square, seen.crooked - soft, soft, ...)

`seen.crooked` is `askew + racked` and **nothing else** - `rack.Seen.crooked`
says so in its own docstring, deliberately, so that no quoted figure quietly
grows. But `seen.worst` is `rack.widest()`, which returns the widest runs **of
each kind**, and `unframed` is one of those kinds. So the sample is drawn from
`askew + racked + unframed` and subtracted from `askew + racked`. Any grammar
whose missing frames are blank or extra-named pays the difference, and once
that difference exceeds the real crooked bytes the column goes below zero.

This script does not fix it - `tool/rack.py` is another lane's this hour, and
the sample is `tool/standing.py`'s. It prints the two numbers that identify
which of the two is wrong: the qualifying width **per run kind**, and what
`crooked` would read if the sample were restricted to the kinds `crooked`
counts.

    OUTLINER_BIN=<binary> python3 borrow.py [grammar...]
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tool"))

import plumb  # noqa: E402
import rack  # noqa: E402
import standing  # noqa: E402


def qualify(saw, run, was) -> bool:
    """`standing.audit()`'s soft rule, restated with nothing added."""
    return (not saw.blob[run.start:run.end].strip()
            or run.ours in was or run.theirs in was)


def look(name: str) -> dict | None:
    case = next((c for c in plumb.slate() if c.name == name), None)
    if case is None:
        return None
    saw = plumb.read(case)
    if saw is None or saw.why or not saw.built:
        return None
    seen = rack.survey(name, saw, top=1 << 20)
    was = standing.extras(name)
    kinds: dict[str, int] = {}
    for run in seen.worst:
        if qualify(saw, run, was):
            kinds[run.kind] = kinds.get(run.kind, 0) + run.width
    soft = sum(kinds.values())
    # The kinds `crooked` is made of. Everything else in `kinds` is an overdraw.
    own = sum(w for k, w in kinds.items() if k in ("askew", "racked"))
    return {"name": name, "built": saw.built, "raw": seen.crooked,
            "soft": soft, "kinds": kinds, "own": own,
            "charged": seen.crooked - soft, "restricted": seen.crooked - own,
            "unframed": seen.unframed}


def main(argv: list[str]) -> int:
    want = [a for a in argv if not a.startswith("-")]
    names = want or [c.name for c in plumb.slate()]
    print(f"\n  {'grammar':<11}{'built':>8}{'askew+racked':>14}{'soft':>8}"
          f"{'charged':>9}{'restricted':>12}   soft drawn from")
    bad = 0
    for name in names:
        got = look(name)
        if got is None:
            continue
        over = {k: v for k, v in got["kinds"].items() if k not in ("askew", "racked")}
        flag = "  <-- NEGATIVE" if got["charged"] < 0 else ""
        if got["charged"] < 0:
            bad += 1
        print(f"  {name:<11}{got['built']:>8}{got['raw']:>14}{got['soft']:>8}"
              f"{got['charged']:>9}{got['restricted']:>12}   "
              f"{', '.join(f'{k} {v}' for k, v in sorted(got['kinds'].items())) or '-'}"
              f"{flag}")
        if over and got["charged"] < 0:
            print(f"  {'':<11}overdraw {sum(over.values())} bytes from a kind "
                  f"`crooked` does not contain: {sorted(over)}")
    print(f"\n  {bad} row(s) below zero\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

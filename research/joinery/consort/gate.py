#!/usr/bin/env python3
"""Is a pair's residual a property of the two rows, or of the file they were priced on?

`vacuity/attribute.py pairs` prices a pair over the corpus board: one fixture
per grammar, `damage = size - built`, `residual = joint - sum of the solos`. It
found kotlin at -20,288 and called the pair *cooperating*. That word is a claim
about the two rows.

But `built` is **byte reach**, and a walk reaches bytes in file order. Two rows
whose constructs both appear near the head of the same file are serial gates on
one walk: clearing one leaves the walk stopped at the other, so each solo arm
reads back nearly the whole file and the two solos sum to nearly twice it. That
is super-additive by construction and says nothing about whether the rows touch.

The two readings differ in exactly one place - **what happens on a fixture that
holds only one of the two constructs.** If the rows are coupled, the residual
follows the rows and survives the change of fixture. If it is the corpus file's
layout, the residual collapses to zero on a single-construct fixture and comes
back on one that holds both.

So this prices the same pair the same way, over fixtures this lane chooses. It
reuses `standing.rows`/`tops`/`union` rather than re-spelling the span reader:
the fourth instrument to parse that render would be the shape `sole.py` exists
to catch.

  python3 research/joinery/consort/gate.py kotlin 2 12 witness/kotlin-*.kt

Arms are the retained pins under `.local/aud-iso/`: `aud-base` is neither row
removed, `aud-rN` is row N removed, `aud-rA-rB` both. Nothing is rebuilt.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))

import standing  # noqa: E402  (needs ROOT/tool on the path first)

PINS = ROOT / ".local/aud-iso/outliner/.local/pin"
GRAMMARS = ROOT / "upstream/grammars"


def built(arm: str, grammar: Path, src: Path) -> tuple[int, int, str]:
    """`built`, root count and verdict for one arm on one file.

    `built` is the union of top-level spans carrying at least one child, which
    is `standing.ask`'s definition read off the same `--ranges --all` render.
    """
    binary = PINS / arm / "bin/outliner"
    got = subprocess.run(
        [binary, "parse", grammar, src, "--ranges", "--all"],
        capture_output=True, text=True, timeout=120,
    )
    text = got.stdout + got.stderr
    top = standing.tops(standing.rows(text))
    verdict = next(
        (ln.split("outliner:", 1)[1].strip() for ln in reversed(text.splitlines())
         if "outliner:" in ln), "")
    return standing.union([(a, b) for _, a, b, kid in top if kid]), len(top), verdict


def price(grammar: str, a: int, b: int, fixtures: list[Path]) -> int:
    """One row per fixture: the four arms, the two solos, the joint, the residual."""
    gram = GRAMMARS / f"{grammar}.json"
    arms = {"none": "aud-base", "a": f"aud-r{a}", "b": f"aud-r{b}", "both": f"aud-r{a}-{b}"}
    missing = [n for n in arms.values() if not (PINS / n / "bin/outliner").exists()]
    if missing:
        print(f"gate: no retained pin for {', '.join(missing)}", file=sys.stderr)
        return 2

    print(f"{'fixture':<26}{'size':>7}{'both in':>9}{f'-{a}':>9}{f'-{b}':>9}"
          f"{'both out':>10}{f'worth {a}':>10}{f'worth {b}':>10}{'joint':>8}{'residual':>10}")
    for src in fixtures:
        size = src.stat().st_size
        got = {k: built(v, gram, src) for k, v in arms.items()}
        # `worth(r) = D({r}) - D(none)`, and `D = size - built`, so the size
        # cancels and the worth is a difference of two `built`s. Taken that way
        # so a fixture of a different length is still comparable.
        worth_a = got["none"][0] - got["a"][0]
        worth_b = got["none"][0] - got["b"][0]
        joint = got["none"][0] - got["both"][0]
        print(f"{src.name:<26}{size:>7}{got['none'][0]:>9}{got['a'][0]:>9}{got['b'][0]:>9}"
              f"{got['both'][0]:>10}{worth_a:>10}{worth_b:>10}{joint:>8}"
              f"{joint - worth_a - worth_b:>+10}")
        for k in ("none", "a", "b", "both"):
            print(f"    {arms[k]:<22}{got[k][1]:>4} roots  {got[k][2][:72]}")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) < 4:
        print(__doc__)
        return 2
    grammar, a, b, *rest = argv
    here = Path(__file__).resolve().parent
    fixtures = [p if (p := Path(f)).exists() else here / f for f in rest]
    if bad := [f for f in fixtures if not f.exists()]:
        print(f"gate: no such fixture: {bad[0]}", file=sys.stderr)
        return 2
    return price(grammar, int(a), int(b), fixtures)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

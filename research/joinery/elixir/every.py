#!/usr/bin/env python3
"""The same-name split, taken over EVERY run instead of the widest ones.

`rack.py show` prints `widest(runs, top)` - the `top` widest runs of each kind.
A lane read the same-name share off that list and split the corpus in two:
swift/ruby/kotlin at 100% same-name (a boundary slip), elixir/verilog/ocaml/
sql/julia at 0% (a genuinely different parent). The instrument's own caution
is that the population it cannot see - narrow runs - is exactly the population
a boundary-slip claim is about, and a three-byte extent gap is a small run by
construction.

So this asks `survey` for all of them. `top` is a slice width and nothing else
in `rack` depends on it, so `measure(case, top=1<<30)` is the same classifier
over the same parse with the ranking turned off. Nothing here re-implements
`bucket`; the comparison would be worthless if it did.

    python3 research/joinery/elixir/every.py            every grammar with runs
    python3 research/joinery/elixir/every.py elixir     one, with the tail printed
    python3 research/joinery/elixir/every.py --json
    python3 research/joinery/elixir/every.py --oracle=<tag>   a FROZEN oracle

Exit 0 measured, 2 could not run.
"""

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

TOOL = Path(__file__).resolve().parents[3] / "tool"
sys.path.insert(0, str(TOOL))

import attest  # noqa: E402
import plumb  # noqa: E402
import rack  # noqa: E402
import stamp  # noqa: E402

ALL = 1 << 30
# What `rack.py show` prints, and what the split was read off.
SHOWN = 20


def peel(name: str) -> str:
    """A label without its quotes, so `"do"` and `do` compare as one name."""
    return name[1:-1] if len(name) > 1 and name.startswith('"') else name


def split(runs) -> dict:
    """Bytes and run counts, same-name against different-name, for one kind."""
    same = [r for r in runs if peel(r.ours) == peel(r.theirs)]
    diff = [r for r in runs if peel(r.ours) != peel(r.theirs)]
    return {
        "runs": len(runs), "bytes": sum(r.width for r in runs),
        "same_runs": len(same), "same_bytes": sum(r.width for r in same),
        "diff_runs": len(diff), "diff_bytes": sum(r.width for r in diff),
        "edge_runs": sum(1 for r in runs if r.edge),
        "edge_bytes": sum(r.width for r in runs if r.edge),
    }


def one(case: plumb.Case) -> dict | None:
    seen = rack.measure(case, top=ALL)
    if seen is None or seen.why:
        return None
    runs = [r for r in seen.worst if r.kind in ("racked", "askew")]
    if not runs:
        return None
    # The widest of each kind, exactly as `widest` picks them, so the two
    # columns differ in the sample and in nothing else.
    shown = list(rack.widest(runs, SHOWN))
    pairs = Counter((r.kind, peel(r.ours), peel(r.theirs)) for r in runs)
    weight: Counter = Counter()
    edges: Counter = Counter()
    for r in runs:
        weight[(r.kind, peel(r.ours), peel(r.theirs))] += r.width
        edges[(r.kind, peel(r.ours), peel(r.theirs))] += r.edge
    return {
        "name": case.name, "built": seen.built, "crooked": seen.crooked,
        "all": split(runs), "racked": split([r for r in runs if r.kind == "racked"]),
        "askew": split([r for r in runs if r.kind == "askew"]),
        "shown": split(shown),
        "shown_racked": split([r for r in shown if r.kind == "racked"]),
        "pairs": [{"kind": k, "ours": a, "theirs": b, "runs": n,
                   "bytes": weight[(k, a, b)], "edge": edges[(k, a, b)]}
                  for (k, a, b), n in pairs.most_common()],
    }


def table(rows: list[dict]) -> None:
    print(f"\n{'grammar':<14}{'crooked':>9}{'runs':>7}{'wide runs':>11}"
          f"{'same% ALL':>11}{'same% WIDE':>12}{'same% ALL b':>13}{'same% WIDE b':>14}")
    print("-" * 91)
    for r in sorted(rows, key=lambda r: -r["racked"]["bytes"]):
        a, w = r["racked"], r["shown_racked"]
        if not a["runs"]:
            continue
        pa = a["same_runs"] / a["runs"] * 100
        pw = w["same_runs"] / w["runs"] * 100 if w["runs"] else 0.0
        ba = a["same_bytes"] / a["bytes"] * 100 if a["bytes"] else 0.0
        bw = w["same_bytes"] / w["bytes"] * 100 if w["bytes"] else 0.0
        print(f"{r['name']:<14}{r['crooked']:>9}{a['runs']:>7}{w['runs']:>11}"
              f"{pa:>10.1f}%{pw:>11.1f}%{ba:>12.1f}%{bw:>13.1f}%")
    print("\n`racked` runs only - the class the split was a claim about."
          "\n`same%` is the share of runs (then of bytes) whose two labels are"
          " the SAME NAME:\n  an extent slip rather than a different parent."
          "  `ALL` is every run; `WIDE` is the"
          f"\n  {SHOWN} widest of each kind, which is what `rack.py show` prints.")


def tail(row: dict) -> None:
    print(f"\n# {row['name']} — every (kind, ours, theirs) pair, widest bytes first\n")
    print(f"  {'kind':<9}{'ours':<26}{'theirs':<26}{'runs':>6}{'bytes':>8}{'edge':>6}  same")
    for p in sorted(row["pairs"], key=lambda p: -p["bytes"]):
        print(f"  {p['kind']:<9}{p['ours']:<26}{p['theirs']:<26}{p['runs']:>6}"
              f"{p['bytes']:>8}{p['edge']:>6}  {'yes' if p['ours'] == p['theirs'] else ''}")


def main(argv: list[str]) -> int:
    as_json = "--json" in argv
    pin = next((a.split("=", 1)[1] for a in argv if a.startswith("--oracle=")), "")
    want = [a for a in argv if not a.startswith("-")]
    slate = plumb.slate()
    picked = [c for c in slate if not want or c.name in want]
    if want and not picked:
        print(f"every: no grammar named {', '.join(want)}", file=sys.stderr)
        return 2
    try:
        picked = attest.consult(picked, pin)
    except ValueError as bad:
        print(f"every: {bad}", file=sys.stderr)
        return 2
    rack.warm(picked)
    rows = [r for c in picked if (r := one(c)) is not None]
    if not rows:
        print("every: nothing with a run to judge", file=sys.stderr)
        return 2
    if as_json:
        print(json.dumps({"row": rows}, indent=2))
        return 0
    table(rows)
    if len(rows) == 1:
        tail(rows[0])
    print(rack.told())
    print(rack.priced().line())
    print(stamp.take(plumb.BIN).line())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

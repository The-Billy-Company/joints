#!/usr/bin/env python3
"""Arm against control, one flag apart, across every row and every mend policy.

`../supply/RESULT-1-insert.md` reports the supply's result split by mend policy:
a pure reclassification under `keep`, and under `fell` - the default - `+688
crooked` corpus-wide with verilog carrying all of it. This file re-derives that
split on today's tree and asks the question the dossier leaves open: **the same
rule cannot have two behaviours, so which policy is the number a property of.**

Both arms are ONE executable a single flag apart (`--no-supply`), so the tree
drift the house rules guard against is structurally unavailable: there is no
second pin to have been built at a different commit. The oracle is the arm's own
frozen seat, and `pin.py arm` says whether it is sighted before any of this is a
measurement rather than thirty rows of `square=0`.

    eval "$(python3 tool/pin.py arm <name>)"
    python3 research/joinery/felled/board.py                  every policy, every row
    python3 research/joinery/felled/board.py --mend fell      one policy
    python3 research/joinery/felled/board.py --json           for a diff

Exit 0 measured, 2 could not run.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))

import plumb  # noqa: E402
import rack  # noqa: E402

POLICIES = ("none", "keep", "fell", "relent")

# The columns a verdict is made of. `built` is here because a policy that buys
# `square` and pays `built` is the trap `rack.py guard` exists to catch, and the
# whole question this file asks is which of the two the supply moved.
COLUMNS = ("built", "square", "crooked", "unframed", "renamed")


def tree() -> str:
    """The digest of the tree these numbers were read on.

    A lane nearly published a nonexistent regression this week because a
    sibling's change landed mid-sweep. Every row below is stamped.
    """
    try:
        out = subprocess.run(["git", "status", "--porcelain=v1", "-z"],
                             cwd=ROOT, capture_output=True, text=True, check=True)
        head = subprocess.run(["git", "rev-parse", "--short", "HEAD"],
                              cwd=ROOT, capture_output=True, text=True, check=True)
    except (OSError, subprocess.CalledProcessError):
        return "unknown"
    import hashlib
    dirt = hashlib.blake2b(out.stdout.encode(), digest_size=6).hexdigest()
    return f"{head.stdout.strip()}+{dirt}"


def sighted() -> str:
    """Whether the arm on this shell has an oracle, or `square` is vacuous."""
    work, binary = os.environ.get("OUTLINER_WORK"), os.environ.get("OUTLINER_BIN")
    if not binary:
        return "zig-out (no pin — `pin.py arm <name>` first)"
    name = Path(binary).resolve().parents[1].name
    seen = subprocess.run([sys.executable, str(ROOT / "tool" / "pin.py"), "arm", name],
                          cwd=ROOT, capture_output=True, text=True)
    for line in (seen.stdout + seen.stderr).splitlines():
        if "oracle:" in line:
            return f"{name} — {line.split('oracle:', 1)[1].strip()}"
    return f"{name} — UNSIGHTED (`pin.py oracle {name}`), `square` is not a measurement"


def sweep(cases: list[plumb.Case], how: str) -> dict[str, dict[str, dict[str, int]]]:
    """Both arms of one policy, row by row."""
    out: dict[str, dict[str, dict[str, int]]] = {}
    for case in cases:
        row: dict[str, dict[str, int]] = {}
        for arm, extra in (("control", (f"--mend={how}", "--no-supply")),
                           ("arm", (f"--mend={how}",))):
            seen = rack.measure(case, top=0, extra=extra)
            if seen is None or seen.why:
                row[arm] = {c: 0 for c in COLUMNS} | {"why": seen.why if seen else "no read"}
                continue
            row[arm] = {c: getattr(seen, c) for c in COLUMNS} | {"size": seen.size}
        out[case.name] = row
    return out


def delta(row: dict[str, dict[str, int]]) -> dict[str, int]:
    return {c: row["arm"].get(c, 0) - row["control"].get(c, 0) for c in COLUMNS}


def render(all_of: dict[str, dict], stamp: str, arm: str) -> None:
    print(f"\n  tree {stamp}   arm {arm}\n")
    for how, rows in all_of.items():
        moved = {n: delta(r) for n, r in rows.items()}
        live = {n: d for n, d in moved.items() if any(d.values())}
        tot = {c: sum(d[c] for d in moved.values()) for c in COLUMNS}
        print(f"  --mend={how}   {len(live)} of {len(moved)} rows move")
        print(f"    {'grammar':<22}" + "".join(f"{c:>11}" for c in COLUMNS))
        for name in sorted(live, key=lambda n: -abs(moved[n]["crooked"])):
            d = moved[name]
            print(f"    {name:<22}" + "".join(f"{d[c]:>+11}" for c in COLUMNS))
        print(f"    {'CORPUS':<22}" + "".join(f"{tot[c]:>+11}" for c in COLUMNS) + "\n")


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mend", action="append", choices=POLICIES,
                    help="repeatable; default is every policy")
    ap.add_argument("--grammar", action="append", help="repeatable; default is every row")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--out", type=Path, help="write the raw sweep here as well")
    args = ap.parse_args(argv)

    cases = plumb.slate()
    if args.grammar:
        want = set(args.grammar)
        cases = [c for c in cases if c.name in want]
        if missing := want - {c.name for c in cases}:
            print(f"no such grammar: {', '.join(sorted(missing))}", file=sys.stderr)
            return 2

    stamp, arm = tree(), sighted()
    rack.warm(cases)
    out = {how: sweep(cases, how) for how in (args.mend or POLICIES)}
    body = {"tree": stamp, "arm": arm, "policies": out}

    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(body, indent=1))
    if args.json:
        print(json.dumps(body, indent=1))
    else:
        render(out, stamp, arm)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

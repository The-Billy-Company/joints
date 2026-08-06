#!/usr/bin/env python3
"""Where is `damage` blind? One row per grammar, both columns beside each other.

`damage` is outliner's own words about its own forest; `square` is the only
column that is a claim about a second parser. A row can be quiet on the first
and ruinous on the second exactly when a wrong reduction is still a reduction -
so this joins the two and sorts by the gap between them.

The press census beside it (`outliner grammar`) is the third column, because a
grammar whose author declared many conflicts is a grammar tree-sitter forks the
stack in and we do not.

Read-only: it re-reads a board `rack.py run --json` already wrote and shells
`outliner grammar`, which builds a table in memory and prints its shape.

    python3 research/joinery/cpp/blind.py .local/cpplane/rack-board.json
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BIN = Path(os.environ.get("OUTLINER_BIN", ROOT / "zig-out" / "bin" / "outliner"))
GRAMMARS = ROOT / "upstream" / "grammars"

CONTEST = re.compile(r"contested\s+(\d+) cells")
PARTS = re.compile(r"(\d+) repetition, (\d+) declared, (\d+) RESIDUAL")
DECL = re.compile(r"conflicts\s+(\d+) declared")


def press(name: str) -> tuple[int, int, int, int]:
    """(declared conflicts, contested cells, of-those-declared, residual)."""
    path = GRAMMARS / f"{name}.json"
    if not path.exists():
        return (0, 0, 0, 0)
    try:
        out = subprocess.run([str(BIN), "grammar", str(path)], capture_output=True,
                             text=True, timeout=180).stdout
    except (OSError, subprocess.SubprocessError):
        return (0, 0, 0, 0)
    cells = int(m.group(1)) if (m := CONTEST.search(out)) else 0
    decl = int(m.group(1)) if (m := DECL.search(out)) else 0
    if m := PARTS.search(out):
        return (decl, cells, int(m.group(2)), int(m.group(3)))
    return (decl, cells, 0, 0)


def main(argv: list[str]) -> int:
    board = json.loads(Path(argv[0]).read_text())
    rows = [r for r in board["row"] if not r["why"]]
    print(f"# oracle {board.get('oracle', '?')}\n")
    head = (f"{'grammar':<14}{'size':>6}{'built':>7}{'damage':>8}{'dmg%':>7}"
            f"{'square':>8}{'crook%':>8}{'recall':>8}   {'declared':>8}{'contested':>10}"
            f"{'ofthose':>9}{'resid':>7}")
    print(head)
    print("-" * len(head))
    seen = []
    for r in sorted(rows, key=lambda r: (-r["share"], r["recall"])):
        dmg = r["damage"] / r["size"] * 100 if r["size"] else 0
        decl, cells, ofd, res = press(r["name"])
        seen.append((r, dmg, decl, cells, ofd, res))
        print(f"{r['name']:<14}{r['size']:>6}{r['built']:>7}{r['damage']:>8}{dmg:>6.1f}%"
              f"{r['square']:>8}{r['share'] * 100:>7.1f}%{r['recall'] * 100:>7.1f}%"
              f"   {decl:>8}{cells:>10}{ofd:>9}{res:>7}")

    print("\n## the signature: quiet on damage, ruinous on square")
    print("   (damage under a third of the file, and either crooked>25% or recall<90%)\n")
    for r, dmg, *_ in seen:
        if dmg < 33 and (r["share"] > 0.25 or r["recall"] < 0.90):
            print(f"   {r['name']:<12} damage {dmg:>5.1f}%  crooked {r['share'] * 100:>5.1f}%"
                  f"  recall {r['recall'] * 100:>5.1f}%  square {r['square']}/{r['built']}"
                  f" = {r['square'] / r['built'] * 100:.0f}% of built")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

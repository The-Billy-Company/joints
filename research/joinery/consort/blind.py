#!/usr/bin/env python3
"""Which boards on this disk made a claim about agreement, and which only think they did.

`square` is the one column that is a claim about a second parser. It comes off a
per-work-dir `audit.json` that `--audit` writes, and the third house rule gives
every arm a work dir of its own - so the discipline that makes a comparison
trustworthy is exactly the thing that empties its oracle columns. Nothing warned:
the columns read zero, and zero is what a clean agreement looks like too.

This walks every saved board and every folio cache under `.local/` and sorts them
into four states, because they are four different pieces of news:

  sighted   at least one row carries a live verdict AND some square. This board
            asked tree-sitter something and got an answer.
  told      an audit ran, and the board printed `stale`/`other` over it. No claim
            about agreement, but the board SAID so on the row.
  blind     `graded: —` on every row: no audit exists for this work dir at all.
            Every oracle column reads 0 and nothing on the page distinguishes
            that from thirty grammars agreeing perfectly.
  void      no rows / not a board.

Usage:  blind.py                 sort every board and cache under .local
        blind.py --json          the same, machine-readable
        blind.py <dir>           somewhere else
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "tool"))

# A row's `graded` when the board could read a verdict of its own tree.
LIVE = ("read", "part")


def boards(where: Path) -> list[tuple[Path, dict]]:
    """Every saved `standing.py --json` under `where`, cheapest test first."""
    out = []
    for p in sorted(where.rglob("*.json")):
        if p.name in ("audit.json", "pin.json", "world.json"):
            continue
        try:
            if "\"graded\"" not in p.read_text()[:400_000]:
                continue
            got = json.loads(p.read_text())
        except (OSError, ValueError, UnicodeDecodeError):
            continue
        if isinstance(got, dict) and isinstance(got.get("row"), list):
            out.append((p, got))
    return out


def state(got: dict) -> tuple[str, dict]:
    """Sort one board, and carry the counts the sort was made on."""
    rows = got.get("row", ())
    tally: dict[str, int] = {}
    for r in rows:
        tally[r.get("graded", "?")] = tally.get(r.get("graded", "?"), 0) + 1
    square = sum(r.get("square", 0) for r in rows)
    if not rows:
        return "void", {"rows": 0, "square": 0, "graded": tally}
    seen = {"rows": len(rows), "square": square, "graded": tally}
    if any(r.get("graded") in LIVE for r in rows) and square:
        return "sighted", seen
    if any(r.get("graded") in ("stale", "other", "none") for r in rows):
        return "told", seen
    return "blind", seen


def caches(where: Path) -> list[tuple[Path, int, int]]:
    """Every `audit.json`: where it is, how many verdicts, how many attributable.

    A verdict with an empty `oracle` field predates the fourth digest and is
    refused by `Held.matches` on sight, so it is counted apart - a cache can be
    full and still mint nothing.
    """
    out = []
    for p in sorted(where.rglob("audit.json")):
        try:
            got = json.loads(p.read_text())
        except (OSError, ValueError):
            continue
        named = sum(1 for v in got.values() if isinstance(v, dict) and v.get("oracle"))
        out.append((p, len(got), named))
    return out


def main(argv: list[str]) -> int:
    where = Path(argv[0]) if argv and not argv[0].startswith("--") else ROOT / ".local"
    if not where.is_dir():
        print(f"blind.py: no directory at {where}", file=sys.stderr)
        return 2
    found = [(p, *state(g), g) for p, g in boards(where)]
    kept = caches(where)
    if "--json" in argv:
        print(json.dumps({
            "board": [{"path": str(p.relative_to(ROOT)), "state": s, **seen,
                       "lane": (g.get("witness") or {}).get("lane", ""),
                       "work": (g.get("witness") or {}).get("work", ""),
                       "binary": (g.get("witness") or {}).get("binary", "")[:12]}
                      for p, s, seen, g in found],
            "cache": [{"path": str(p.relative_to(ROOT)), "verdicts": n,
                       "attributable": named} for p, n, named in kept]}, indent=1))
        return 0
    print(f"\n  {len(found)} board(s) and {len(kept)} folio cache(s) under"
          f" {where.relative_to(ROOT) if where.is_relative_to(ROOT) else where}\n")
    print(f"  {'state':<9}{'board':<52}{'rows':>5}{'square':>10}  graded")
    print("  " + "-" * 100)
    for p, s, seen, _ in sorted(found, key=lambda r: (r[1], str(r[0]))):
        spelled = " ".join(f"{k}:{v}" for k, v in sorted(seen["graded"].items()))
        print(f"  {s:<9}{str(p.relative_to(ROOT))[-50:]:<52}{seen['rows']:>5}"
              f"{seen['square']:>10}  {spelled}")
    tally: dict[str, int] = {}
    for _, s, _, _ in found:
        tally[s] = tally.get(s, 0) + 1
    print(f"\n  {'  ·  '.join(f'{k} {v}' for k, v in sorted(tally.items()))}")
    print(f"\n  {len(kept)} folio cache(s) carry an audit at all:")
    for p, n, named in kept:
        print(f"    {str(p.relative_to(ROOT)):<58}{n:>4} verdict(s), {named} attributable")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

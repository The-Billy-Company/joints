#!/usr/bin/env python3
"""The five predictions in `PREDICTION-1-order.md`, measured.

Reads the board through `standing.py`'s own helpers, so nothing here can
disagree with the board about what a root is or which file a grammar was
scored over.

  python3 research/joinery/board/probe.py .local/lane-board/base.json
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))

import standing  # noqa: E402
import stamp  # noqa: E402
from order import folio_for  # noqa: E402

board = {r["name"]: r for r in json.load(open(sys.argv[1]))["row"]}
src = standing.sources()
dmg = lambda r: r["size"] - r["built"]  # noqa: E731


def rank(key) -> list[str]:
    return [r["name"] for r in sorted(board.values(), key=key)]


print("=" * 78)
print("P1 — does stamp.ask() lose the mend count on the rows that mended?")
print("=" * 78)
print(f"{'grammar':<14}{'board roots':>12}{'ask.mends':>11}{'ask.roots':>11}{'ask.blind':>11}  verdict head")
lost = []
for n, r in sorted(board.items(), key=lambda kv: -dmg(kv[1])):
    o = stamp.ask(standing.BIN, folio_for(n, standing.WORK), src[n], tree=True)
    if r["roots"] > 1 and (o.mends == 0 or o.roots == 1):
        lost.append(n)
    print(f"{n:<14}{r['roots']:>12}{o.mends:>11}{o.roots:>11}{o.blind:>11}"
          f"  {o.verdict.split(':')[0][:40]}")
walled = [n for n, r in board.items() if r["roots"] > 1]
print(f"\nrows the board scores at roots>1: {len(walled)}")
print(f"rows where ask() reports mends==0 or roots==1 anyway: {len(lost)}")
print(f"P1 {'HELD' if len(lost) == len(walled) else 'FAILED'}: {sorted(lost)}")

print()
print("=" * 78)
print("P2 — do a bytes ranking and a share ranking disagree at the top?")
print("=" * 78)
bytes5 = rank(lambda r: -dmg(r))[:5]
share5 = rank(lambda r: r["standing"])[:5]
both = [n for n in bytes5 if n in share5]
print(f"top 5 by damage : {', '.join(bytes5)}")
print(f"top 5 by 1-stand: {', '.join(share5)}")
print(f"shared: {len(both)} ({', '.join(both) or 'none'})")
print(f"P2 {'HELD' if len(both) <= 2 else 'FAILED'} (predicted at most 2)")

print()
print("=" * 78)
print("P4 — the gate, stated in the board's own columns")
print("=" * 78)
bad = [r["name"] for r in board.values() if (r["leaves"] == 0) != (r["roots"] <= 1)]
one = [r["name"] for r in board.values() if r["roots"] <= 1]
many = [r["name"] for r in board.values() if r["roots"] > 1]
strict = [r["name"] for r in board.values() if (r["leaves"] == 0) != (r["roots"] == 1)]
per = {r["name"]: dmg(r) / r["roots"] for r in board.values() if r["roots"] > 1}
lo, hi = min(per.items(), key=lambda kv: kv[1]), max(per.items(), key=lambda kv: kv[1])
spread = hi[1] / lo[1]
print(f"exact      leaves==0 <=> roots<=1 : {'HOLDS' if not bad else 'BREAKS on ' + str(bad)}")
print(f"           leaves==0 <=> roots==1 : {'holds' if not strict else 'breaks on ' + str(strict)}")
print(f"non-vacuous  roots<=1: {len(one)} rows   roots>1: {len(many)} rows")
print(f"graded     damage/roots  {hi[0]} {hi[1]:.1f}  vs  {lo[0]} {lo[1]:.1f}  = {spread:.1f}x")
print(f"P4 {'HELD' if not bad and one and many and spread >= 10 else 'FAILED'}")

print()
print("=" * 78)
print("the corrected ranking (arithmetic, not a prediction)")
print("=" * 78)
by_d, by_u = rank(lambda r: -dmg(r)), rank(lambda r: -r["unbound"])
print(f"{'#':>3}  {'by unbound':<14}{'':>9}  {'by damage':<14}{'':>9}{'moved':>7}{'flattered':>11}")
for i, n in enumerate(by_d):
    r, u = board[n], board[by_u[i]]
    move = by_u.index(n) - i
    ratio = dmg(r) / r["unbound"] if r["unbound"] else float("inf")
    tag = f"{ratio:>10.1f}x" if r["unbound"] else f"{'—':>11}"
    print(f"{i + 1:>3}  {u['name']:<14}{u['unbound']:>9,}  {n:<14}{dmg(r):>9,}"
          f"{move:>+7}{tag}")
    if i >= 19:
        break

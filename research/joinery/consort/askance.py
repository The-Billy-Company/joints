#!/usr/bin/env python3
"""Which pages name a grammar whose `standing` and `trued` disagree.

`onlydamage.py` asks *did this page ever quote the oracle*. That is a question
about vocabulary and it is deliberately over-inclusive. This is the sharper
question, and it needs the board rather than a regex: **does this page talk
about a grammar the oracle disagrees with, using a column that cannot see the
disagreement?**

The discriminator is one subtraction the board already prints:

    standing = under / size        bytes we put under some construct
    trued    = square / size       bytes we put under THE SAME construct
                                   tree-sitter puts them under

`built − square` is how many bytes of a grammar's coverage are unvouched for -
built by us and not corroborated by a second parser. It is the whole of the
`damage = 0` trap in one number:

    php     damage 0   standing 100.0%   trued 100.0%   unvouched      0
    html    damage 0   standing 100.0%   trued 100.0%   unvouched      0
    elixir  damage 0   standing 100.0%   trued  51.8%   unvouched 22,210

All three rows read `damage 0`. Two of them are finished grammars, and no
`damage`-only page can tell you which one it is holding.

A page is **askance** when it names a grammar carrying at least `--floor`
unvouched bytes (default 2,000) and quotes a column of ours without ever quoting
one of the oracle's. The rank is those bytes times how many comparisons the page
draws, because a comparison can have its sign changed and a description can only
be incomplete.

**Ranking on bytes rather than on percentage points is not cosmetic.** The first
draft of this file ranked on `standing − trued` and put cpp at the head of the
board on a 57.7-point gap - over 812 bytes, because `ledger.cpp` is 1,408 bytes
long. Every page that says the word "cpp" outranked `verilog/RESULT-1-wall.md`,
whose grammar carries 30,009. A percentage is a ratio and the thing at risk here
is a byte count.

Read-only. It parses no board of its own: it reads a **retained sighted board**
(`.local/sighted/boards/base.json` by default, the audited base arm of
`RESULT-8-sighted.md`) so that nothing here re-measures what has already been
measured sighted.

Usage:  askance.py                    the worklist, worst first
        askance.py --json             machine-readable
        askance.py --floor=500        widen the net
        askance.py --board=<path>     a different retained board
        askance.py --grammars         just the board, sorted by unvouched bytes
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))

import onlydamage  # noqa: E402 - the classifier, reused rather than re-spelled

BOARD = ROOT / ".local/sighted/boards/base.json"
# Below this many unvouched bytes a page quoting `standing` is imprecise rather
# than wrong, and this sweep is for the ones that are wrong.
FLOOR = 2000


def board(at: Path) -> dict[str, dict]:
    """Every graded row of a retained board, keyed by grammar."""
    got = json.loads(at.read_text())
    return {r["name"]: r for r in got["row"] if r.get("graded") == "read"}


def unvouched(rows: dict[str, dict]) -> dict[str, int]:
    """Bytes each grammar built that the oracle does not corroborate.

    `soft` is left in deliberately. It is a disagreement about where an extra
    hangs rather than a misreading, but it is still a byte no `damage`-only page
    can claim was placed correctly, and this sweep's job is to size what a page
    cannot say.
    """
    return {n: r["built"] - r["square"] for n, r in rows.items()}


def named(text: str, grammar: str) -> int:
    """How many times a page names a grammar, as a word rather than a substring.

    `sql` must not match `mysqld` and `c` must not match every English word, so
    the boundary is required on both sides and one-letter names are matched only
    where they are already set off - a table cell, a list bullet, or backticks.
    """
    if len(grammar) <= 2:
        return len(re.findall(rf"(?:^|[|`(\s])`?{re.escape(grammar)}`?(?=[|`)\s,.]|$)",
                              text, re.M))
    return len(re.findall(rf"\b{re.escape(grammar)}\b", text, re.I))


def read(at: Path, apart: dict[str, int]) -> dict:
    got = onlydamage.read(at)
    text = at.read_text(errors="replace")
    leans = {g: named(text, g) for g in apart if named(text, g)}
    got["grammars"] = sorted(leans, key=lambda g: -apart[g])
    got["worst"] = max((apart[g] for g in leans), default=0)
    got["worst_of"] = got["grammars"][0] if got["grammars"] else ""
    return got


def rank(got: dict) -> float:
    return got["worst"] * (1 + min(got["compares"], 6)) * (1 if got["claims"] else 0.3)


def main(argv: list[str]) -> int:
    where = next((a.split("=", 1)[1] for a in argv if a.startswith("--board=")), BOARD)
    floor = int(next((a.split("=", 1)[1] for a in argv if a.startswith("--floor=")), FLOOR))
    rows = board(Path(where))
    apart = unvouched(rows)

    if "--grammars" in argv:
        print(f"\n  {Path(where).relative_to(ROOT)}\n")
        print(f"  {'grammar':<20}{'size':>8}{'built':>8}{'damage':>8}{'square':>8}"
              f"{'stand':>8}{'trued':>8}{'unvouched':>11}")
        for n, g in sorted(apart.items(), key=lambda kv: -kv[1]):
            r = rows[n]
            print(f"  {n:<20}{r['size']:>8}{r['built']:>8}{r['damage']:>8}{r['square']:>8}"
                  f"{r['standing'] * 100:>7.1f}%{r['trued'] * 100:>7.1f}%{g:>11}")
        return 0

    got = [read(p, apart) for p in onlydamage.pages()]
    blind = [g for g in got if g["ours"] and not g["theirs"] and g["worst"] >= floor]
    for g in blind:
        g["rank"] = round(rank(g), 1)
    want = sorted(blind, key=lambda g: -g["rank"])
    if "--json" in argv:
        print(json.dumps(want, indent=1))
        return 0
    print(f"\n  {len(got)} page(s) · {len(blind)} lean on a grammar carrying ≥{floor:,}"
          f" unvouched bytes and never quote the oracle\n")
    print(f"  {'rank':>9}{'unvouched':>11}  {'grammar':<12}{'cmp':>4}  page")
    for g in want[:40]:
        print(f"  {g['rank']:>9,.0f}{g['worst']:>11,}  {g['worst_of']:<12}"
              f"{g['compares']:>4}  {g['path']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

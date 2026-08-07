#!/usr/bin/env python3
"""Does the second move cost us the localization lead, and where do repairs sit?

Two questions off one pass of the scar channel, both of which this lane is
obliged to answer and neither of which any board answers today.

## 1. The lead

`../scars/` measured the one place we are ahead of tree-sitter: on verilog its
266 `ERROR` nodes cover **100%** of the file and our scars cover **34%**, so a
consumer asking "which bytes should I not trust" gets an answer from us and a
shrug from them. A richer repair vocabulary is exactly the thing that loses
that: a parse that can also *insert* recovers further, reads on through more of
the file, and can end up marking more of it. So it is measured rather than
assumed - control and arm, same binary, one flag apart.

The number to watch is `spanned`, the **union** of the deleted byte ranges. A
supply spans nothing (it is zero-width), so it cannot inflate this directly;
what it can do is let the parse reach walls it never used to reach.

## 2. The scar-aware view rack does not have

`../scars/` also bounded the blind spot: **27.9% of `built` sits downstream of
a repair** and `square`'s exposure is **19.9-23.0%**, with no column anywhere
distinguishing agreement that stands on repaired ground from agreement that
does not. That matters here because this lane moves `square`, and part of the
movement is inside the region nothing watches.

`tool/rack.py` belongs to another lane, so this hands over the **join key**
rather than editing the board: `--spans` writes, per grammar, every repair site
of the run - deletions with their byte range, supplies with their anchor and
the terminal written in. Joining a per-leaf square attribution against these
spans is a column rack can add without re-deriving anything.

  python3 research/joinery/supply/reach.py --mend keep
  python3 research/joinery/supply/reach.py --mend keep --spans .local/supply/spans.json

Exit 0 measured, 2 an error.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import NamedTuple

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))

import order  # noqa: E402
import plumb  # noqa: E402
from residue import run  # noqa: E402

CUT = re.compile(r"^scar (\d+)\.\.(\d+) (\d+)B (fell|kept) (.*), (\d+) heads, \+(\d+) tokens$")
GAVE = re.compile(r"^scar (\d+) gave (\S+) (.*), (\d+) heads, \+(\d+) tokens$")


def union(spans: list[tuple[int, int]]) -> int:
    total, end = 0, -1
    for a, b in sorted(spans):
        a = max(a, end)
        if b > a:
            total += b - a
            end = b
    return total


class Look(NamedTuple):
    cuts: int
    spanned: int
    gave: int
    sites: list[dict]


def read(out: str) -> Look:
    cuts: list[tuple[int, int]] = []
    sites: list[dict] = []
    gave = 0
    for line in out.splitlines():
        line = line.strip()
        if m := CUT.match(line):
            cuts.append((int(m[1]), int(m[2])))
            sites.append({"at": int(m[1]), "over": int(m[2]), "gave": None,
                          "felled": m[4] == "fell", "why": m[5]})
        elif m := GAVE.match(line):
            gave += 1
            sites.append({"at": int(m[1]), "over": int(m[1]), "gave": m[2],
                          "felled": False, "why": m[3]})
    return Look(len(cuts), union(cuts), gave, sites)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mend", default="keep", choices=("keep", "fell", "relent"))
    ap.add_argument("--spans", type=Path, help="hand rack the join key")
    args = ap.parse_args(argv)

    work = Path(os.environ.get("JOINTS_WORK", ROOT / ".local" / "work"))
    print(f"--mend={args.mend}\n\n{'grammar':<12}{'size':>9}"
          f"{'cuts ctl':>10}{'reach ctl':>11}{'%':>6}"
          f"{'cuts arm':>10}{'reach arm':>11}{'%':>6}{'gave':>7}   lead")
    dump: dict[str, list[dict]] = {}
    wide = [0, 0, 0, 0, 0]
    for case in plumb.slate():
        art = order.folio_for(case.name, work) or (order.GRAMMARS / f"{case.name}.json")
        if not Path(art).exists() or not case.source.exists():
            continue
        size = case.source.stat().st_size
        was = read(run(order.BIN, Path(art), case.source, args.mend, False, False)[0])
        now = read(run(order.BIN, Path(art), case.source, args.mend, True, False)[0])
        if not was.cuts and not now.cuts and not now.gave:
            continue
        dump[case.name] = now.sites
        pc, pa = 100.0 * was.spanned / size, 100.0 * now.spanned / size
        # Tighter is better: fewer bytes handed back as "do not trust this"
        # for the same file is a sharper answer, and a wider one is the sprawl
        # a richer repair vocabulary was warned about.
        lead = "held" if pa <= pc + 0.05 else "SPRAWL"
        print(f"{case.name:<12}{size:>9,}{was.cuts:>10,}{was.spanned:>11,}{pc:>5.0f}%"
              f"{now.cuts:>10,}{now.spanned:>11,}{pa:>5.0f}%{now.gave:>7,}   {lead}")
        wide = [wide[0] + size, wide[1] + was.cuts, wide[2] + was.spanned,
                wide[3] + now.spanned, wide[4] + now.gave]
    if not wide[0]:
        print("reach: nothing repaired anywhere", file=sys.stderr)
        return 2
    print(f"\nOver the grammars that repair at all: {wide[2]:,} B deleted without the "
          f"second move ({100.0 * wide[2] / wide[0]:.1f}% of their bytes), "
          f"{wide[3]:,} B with it ({100.0 * wide[3] / wide[0]:.1f}%), plus {wide[4]:,} "
          f"zero-width supplies that span nothing. A repair surface is better when it "
          f"is *tighter*, so the arm keeps the lead only if its percentage does not "
          f"rise.")
    if args.spans:
        args.spans.parent.mkdir(parents=True, exist_ok=True)
        args.spans.write_text(json.dumps({"mend": args.mend, "grammar": dump}, indent=1))
        print(f"\nwrote {sum(len(v) for v in dump.values()):,} repair site(s) to "
              f"{args.spans} - the join key for a scar-aware `square` column. Every "
              f"site carries `at`/`over` (a deletion's bytes, or a supply's anchor "
              f"twice) and `gave` (the terminal written in, or null for a deletion).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

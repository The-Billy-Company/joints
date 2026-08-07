#!/usr/bin/env python3
"""Where in the file is a gap wall, and what construct is standing there?

`GAPS.md` names each wall as `<terminal> in state <n>` and prices it, but the
price is all the peel keeps: `Depth` carries `priced`, and `priced` has thrown
the byte offsets away by the time anything downstream sees it. So a reader
handed "php `/` in state 68 costs 40,996 B" cannot get from that row to the
line of PHP it stands in front of, which is the only thing an adjudication can
be about.

This re-runs the same cold peel `walls.py` runs and keeps the half it drops:
`peel()` already returns `marks` beside `seen`, so the offsets exist and are
simply not plumbed anywhere. Every wall comes back with its absolute byte, the
line it lands on, and the bytes either side of it.

**A state number is not a key here.** Two binaries differing by one line
renumber the whole LR(0) collection, so a row keyed on `state 68` may name a
different state on your build. The stable key is the (terminal, offset) pair
and the source text at it - which is what a witness is authored from.

    python3 research/joinery/adjudicate/locate.py php kotlin
    python3 research/joinery/adjudicate/locate.py --json php

Exit 0 located, 2 could not run.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))

from order import BIN, folio_for  # noqa: E402
from walls import DEPTH, roster  # noqa: E402
from walls import peel as cold_peel  # noqa: E402


def context(text: bytes, at: int, span: int) -> tuple[int, str, str]:
    """The line number at `at`, and the bytes either side of it."""
    line = text.count(b"\n", 0, at) + 1
    before = text[max(at - span, 0):at].decode("utf-8", "replace")
    after = text[at:at + span].decode("utf-8", "replace")
    return line, before, after


def locate(name: str, src: Path, work: Path, depth: int) -> list[dict] | None:
    folio = folio_for(name, work)
    if folio is None or not src.exists():
        return None
    text = src.read_bytes()
    seen, marks, _, why = cold_peel(folio, text, work, src.suffix.lstrip(".") or "txt", depth)
    out = []
    for (kind, who), at in zip(seen, marks, strict=True):
        line, before, after = context(text, at, 90)
        out.append({"grammar": name, "kind": kind, "wall": who, "at": at,
                    "line": line, "before": before, "after": after, "why": why})
    return out


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("grammar", nargs="*", help="which grammars to locate (default: all)")
    ap.add_argument("--depth", type=int, default=DEPTH)
    ap.add_argument("--wall", help="only walls whose name contains this")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)

    if not BIN.exists():
        print(f"locate: no binary at {BIN}; set JOINTS_BIN", file=sys.stderr)
        return 2
    work = ROOT / ".local" / "adjudicate"
    work.mkdir(parents=True, exist_ok=True)

    todo = [(n, p) for n, p in roster() if not args.grammar or n in args.grammar]
    rows: list[dict] = []
    for name, src in todo:
        got = locate(name, src, work, args.depth)
        if got is None:
            print(f"locate: {name}: no grammar or no source", file=sys.stderr)
            continue
        rows += got
        print(f"locate: {name}: {len(got)} wall(s)", file=sys.stderr)
    if args.wall:
        rows = [r for r in rows if args.wall in r["wall"]]
    if args.json:
        print(json.dumps(rows, indent=2))
        return 0
    for r in rows:
        print(f"\n{r['grammar']:<10}{r['wall']}")
        print(f"  at byte {r['at']:,}  line {r['line']}")
        print(f"  before | {r['before']!r}")
        print(f"  after  | {r['after']!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

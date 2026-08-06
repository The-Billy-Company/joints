#!/usr/bin/env python3
"""Where are the bytes no root ever got over?

`spoil` is a *count* - the complement of the union of the top-level root spans -
and every instrument in this tree reports it as one number. A number cannot say
whether 45,102 bytes are one hole or four thousand, and those are different
projects: one hole is a wall, four thousand is a policy.

So this prints the complement as **spans**, largest first, with the line each
one opens on and the byte the source holds there. No new reading of the tree:
the spans come from `standing.ranged`, which is the board's own reader, so a row
here cannot disagree with the board about what a root is.

    python3 research/joinery/verilog/unreached.py [--grammar verilog] [--top 20]
    python3 research/joinery/verilog/unreached.py --source path/to/other.v
    python3 research/joinery/verilog/unreached.py --json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))

import standing  # noqa: E402
import stamp  # noqa: E402


def holes(spans: list[tuple[str, int, int, bool]], size: int) -> list[tuple[int, int]]:
    """The complement of the union of `spans` over `[0, size)`.

    Exactly `standing.union`'s complement, computed the same way it computes its
    total, so `sum(b - a for a, b in holes(...)) == row.spoil` by construction
    rather than by agreement.
    """
    merged: list[list[int]] = []
    for _, a, b, _ in sorted(spans, key=lambda s: (s[1], s[2])):
        if merged and a <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], b)
        else:
            merged.append([a, b])
    out, at = [], 0
    for a, b in merged:
        if a > at:
            out.append((at, a))
        at = max(at, b)
    if at < size:
        out.append((at, size))
    return out


def line_of(text: bytes) -> list[int]:
    """Start offset of every line, so a byte can name a line without a scan."""
    at, out = 0, [0]
    while (i := text.find(b"\n", at)) >= 0:
        out.append(i + 1)
        at = i + 1
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--grammar", default="verilog")
    ap.add_argument("--source", type=Path, default=None)
    ap.add_argument("--top", type=int, default=20)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    src = args.source or dict(standing.roster()).get(args.grammar)
    if src is None or not Path(src).exists():
        print(f"unreached: no source for {args.grammar}", file=sys.stderr)
        return 2
    src = Path(src)

    folio = standing.folio_for(args.grammar, standing.WORK)
    if folio is None:
        print(f"unreached: no folio for {args.grammar}", file=sys.stderr)
        return 2
    got = stamp.ask(standing.BIN, folio, src, tree=True, patience=standing.PATIENCE)
    if got.kind == "timeout":
        print("unreached: timed out", file=sys.stderr)
        return 2

    text = src.read_bytes()
    top = standing.tops(standing.rows(got.tree))
    gaps = holes(top, len(text))
    starts = line_of(text)

    def line(at: int) -> int:
        lo, hi = 0, len(starts) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            lo, hi = (mid, hi) if starts[mid] <= at else (lo, mid - 1)
        return lo + 1

    total = sum(b - a for a, b in gaps)
    ranked = sorted(gaps, key=lambda g: -(g[1] - g[0]))

    # What a hole is MADE of decides whose it is. A gap holding nothing but
    # whitespace is the *seam between two adjacent roots* and no parse of any
    # quality closes it while the forest is a forest - it is an artifact of the
    # metric's own definition, not a byte the parse failed to reach. A gap
    # holding source text is the thing `spoil` was named for.
    def kind(a: int, b: int) -> str:
        body = text[a:b]
        if not body.strip():
            return "blank"
        stripped = body.strip()
        if stripped.startswith(b"//") or stripped.startswith(b"/*"):
            return "comment"
        return "code"

    made: dict[str, tuple[int, int]] = {}
    for a, b in gaps:
        k = kind(a, b)
        n, wide = made.get(k, (0, 0))
        made[k] = (n + 1, wide + b - a)

    if args.json:
        print(json.dumps({
            "grammar": args.grammar, "source": str(src), "size": len(text),
            "verdict": got.verdict, "spoil": total, "holes": len(gaps),
            "made": {k: {"holes": n, "bytes": w} for k, (n, w) in sorted(made.items())},
            "spans": [{"start": a, "end": b, "bytes": b - a, "line": line(a),
                       "opens": text[a:a + 60].decode("utf-8", "replace")}
                      for a, b in ranked],
        }))
        return 0

    print(stamp.take(standing.BIN).line())
    print(f"{args.grammar}  {src}  {len(text)} B")
    print(f"  {got.verdict}")
    print(f"\n  {len(gaps)} unreached span(s), {total} B "
          f"({total / len(text) * 100:.1f}% of the file)")
    wide = [g for g in ranked if g[1] - g[0] >= 64]
    print(f"  {len(wide)} of them are 64 B or wider, and hold "
          f"{sum(b - a for a, b in wide)} B "
          f"({sum(b - a for a, b in wide) / max(total, 1) * 100:.1f}% of the spoil)")
    print("\n  what the holes are made of — a hole holding only whitespace is the seam")
    print("  between two adjacent roots, which no forest closes:")
    for k, (n, w) in sorted(made.items(), key=lambda it: -it[1][1]):
        print(f"    {k:<8} {n:>6} hole(s)  {w:>7} B  "
              f"{w / max(total, 1) * 100:>5.1f}% of the spoil")
    print()
    print(f"  {'bytes':>8} {'start':>7} {'line':>6}  opens on")
    for a, b in ranked[:args.top]:
        head = text[a:a + 58].decode("utf-8", "replace").replace("\n", "\\n").replace("\t", " ")
        print(f"  {b - a:>8} {a:>7} {line(a):>6}  {head}")
    if len(ranked) > args.top:
        rest = sum(y - x for x, y in ranked[args.top:])
        print(f"  {'...':>8} {len(ranked) - args.top} more span(s), {rest} B")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

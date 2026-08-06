#!/usr/bin/env python3
"""Every mend site the parse made, grouped by the wall that caused it.

`--scars` prints one line per repair - the byte range walked past, the terminal
the state refused, and the state it refused it in. That is the only instrument in
this tree that answers *where the unreached bytes went* rather than how many
there are, and nothing had aggregated it.

Ranked by **bytes**, never by count, for the reason `witness.py` already carries:
on this file the two orderings disagree, and the wall that recurs most is very
nearly the wall that costs least.

    python3 research/joinery/verilog/stops.py [--grammar verilog] [--top 20]
    python3 research/joinery/verilog/stops.py --source path/to/other.v
    python3 research/joinery/verilog/stops.py --json
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))

import standing  # noqa: E402
import stamp  # noqa: E402

# `scar A..B NB fell|kept unexpected T in state S, H heads, +N tokens`
# `scar A gave T unexpected T2 in state S, H heads, +N tokens`
FELL = re.compile(
    r"^scar (\d+)\.\.(\d+) (\d+)B (fell|kept) (.*?), (\d+) heads, \+(\d+) tokens$")
GAVE = re.compile(r"^scar (\d+) gave (\S+) (.*?), (\d+) heads, \+(\d+) tokens$")
WALL = re.compile(r"^unexpected (.*) in state (\d+)$")


class Scar:
    __slots__ = ("at", "over", "wide", "felled", "gave", "terminal", "state", "shifted")

    def __init__(self, at, over, wide, felled, gave, terminal, state, shifted):
        self.at, self.over, self.wide = at, over, wide
        self.felled, self.gave = felled, gave
        self.terminal, self.state, self.shifted = terminal, state, shifted


def read(line: str) -> Scar | None:
    if (m := FELL.match(line)) is not None:
        w = WALL.match(m.group(5))
        return Scar(int(m.group(1)), int(m.group(2)), int(m.group(3)),
                    m.group(4) == "fell", None,
                    w.group(1) if w else m.group(5), int(w.group(2)) if w else -1,
                    int(m.group(7)))
    if (m := GAVE.match(line)) is not None:
        w = WALL.match(m.group(3))
        return Scar(int(m.group(1)), int(m.group(1)), 0, False, m.group(2),
                    w.group(1) if w else m.group(3), int(w.group(2)) if w else -1,
                    int(m.group(5)))
    return None


def scars(binary: Path, folio: Path, src: Path) -> tuple[list[Scar], str]:
    got = subprocess.run([str(binary), "parse", str(folio), str(src), "--scars"],
                         capture_output=True, text=True, timeout=300)
    out = [s for line in got.stdout.splitlines() if (s := read(line.strip())) is not None]
    # The verdict is the first stderr line; the second, when there is one, is
    # inquest's attribution of the same wall and belongs to `inquest`, not here.
    said = [ln for ln in got.stderr.splitlines() if ln.startswith("outliner:")]
    return out, (said[0].split(": ", 2)[-1] if said else "")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--grammar", default="verilog")
    ap.add_argument("--source", type=Path, default=None)
    ap.add_argument("--top", type=int, default=20)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    src = args.source or dict(standing.roster()).get(args.grammar)
    if src is None or not Path(src).exists():
        print(f"stops: no source for {args.grammar}", file=sys.stderr)
        return 2
    src = Path(src)
    folio = standing.folio_for(args.grammar, standing.WORK)
    if folio is None:
        print(f"stops: no folio for {args.grammar}", file=sys.stderr)
        return 2

    seen, verdict = scars(standing.BIN, folio, src)
    text = src.read_bytes()

    # Grouped by the pair that names a wall, because a state is not a wall and a
    # terminal is not either: the same terminal refused in two states is two
    # different sentences about the grammar.
    #
    # `+0 tokens` is the previous refusal re-reported against the next token
    # rather than a second wall, so it is counted apart instead of inflating a
    # row - the double-count `research/joinery/reprice/` found the warm peel
    # making across a whole corpus.
    rank: dict[tuple[str, int], dict] = {}
    for s in seen:
        k = (s.terminal, s.state)
        row = rank.setdefault(k, {"terminal": s.terminal, "state": s.state, "bytes": 0,
                                  "scars": 0, "echoes": 0, "fell": 0, "kept": 0,
                                  "gave": 0, "first": s.at, "opens": ""})
        row["bytes"] += s.wide
        row["scars"] += 1
        row["echoes"] += 1 if s.shifted == 0 else 0
        row["first"] = min(row["first"], s.at)
        if s.gave is not None:
            row["gave"] += 1
        elif s.felled:
            row["fell"] += 1
        else:
            row["kept"] += 1
    for row in rank.values():
        row["opens"] = text[row["first"]:row["first"] + 52].decode("utf-8", "replace")

    ranked = sorted(rank.values(), key=lambda r: -r["bytes"])
    walked = sum(s.wide for s in seen)

    if args.json:
        print(json.dumps({"grammar": args.grammar, "source": str(src),
                          "size": len(text), "verdict": verdict,
                          "scars": len(seen), "walked": walked, "walls": ranked}))
        return 0

    print(stamp.take(standing.BIN).line())
    print(f"{args.grammar}  {src}  {len(text)} B")
    print(f"  {verdict}\n")
    print(f"  {len(seen)} scar(s) over {len(rank)} distinct (terminal, state) wall(s), "
          f"{walked} B walked past")
    by_count = sorted(rank.values(), key=lambda r: -r["scars"])[0]
    print(f"  ranked by bytes the leader is {ranked[0]['terminal']} in "
          f"{ranked[0]['state']}; by scar count it would be "
          f"{by_count['terminal']} in {by_count['state']}\n")
    print(f"  {'bytes':>7} {'scars':>6} {'echo':>5} {'fell':>5} {'kept':>5} {'gave':>5} "
          f"{'state':>6}  terminal")
    for r in ranked[:args.top]:
        print(f"  {r['bytes']:>7} {r['scars']:>6} {r['echoes']:>5} {r['fell']:>5} "
              f"{r['kept']:>5} {r['gave']:>5} {r['state']:>6}  {r['terminal'][:44]}")
    if len(ranked) > args.top:
        rest = sum(r["bytes"] for r in ranked[args.top:])
        print(f"  {'...':>7} {len(ranked) - args.top} more wall(s), {rest} B")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

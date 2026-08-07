#!/usr/bin/env python3
"""Per-row A/B for the bracket seat, over every grammar with a real source.

Two arms, one tree: the control deletes the two-row `.brackets` data field from
haskell's troupe, which makes the whole seat inert - nothing resolves, both
loops in `tested` and `ordered` run over an empty list, and nothing ever pushes
a marker frame, so `bracketed` cannot fire and `standing`'s `>= marker` collapses
to the `== sealed` it replaced. The treatment restores the two rows. Everything
else in the tree is held identical, which is what lets a difference be read as
the seat's.

Every row is printed, not a corpus total. The keyword lane measured a seat that
repaired verilog and took php from 67,697 square bytes to 662 and scala from
6,739 to 201; a total would have shown a win. So php, scala and elixir are
carried permanently beside haskell, and a row that does not move is evidence
too - it is the claim that the seat is confined to the grammar that declares it.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BIN = ROOT / "zig-out/bin/joints"
GRAMMARS = ROOT / "upstream/grammars"
SOURCES = ROOT / "upstream/sources"

# `accepted, 1 root` and `2003 roots, …` are the same line wearing two faces, and
# a refusal prints *after* it - so anchoring on the last line reports a different
# fact for a row that refused than for one that did not.
VERDICT = re.compile(
    r"(?:accepted, (?P<one>\d+) root|(?P<many>\d+) roots)"
    r"(?:.*?mended (?P<mended>\d+) over (?P<bytes>\d+)B)?"
    r"(?:.*?supplied (?P<supplied>\d+))?"
    r"(?:.*?surveyed (?P<seen>\d+) of (?P<nodes>\d+))?"
)


def rows() -> list[tuple[str, Path]]:
    """Each grammar paired with the corpus source it is measured on."""
    sys.path.insert(0, str(ROOT / "tool"))
    import breadth  # noqa: PLC0415 - the manifest is the tool's, not ours

    out = []
    for name, spec in sorted(breadth.SOURCES.items()):
        grammar = GRAMMARS / f"{name}.json"
        source = SOURCES / spec[1]
        if grammar.exists() and source.exists():
            out.append((name, grammar, source))
    return out


def read(grammar: Path, source: Path) -> dict[str, int]:
    got = subprocess.run(
        [str(BIN), "parse", str(grammar), str(source)],
        capture_output=True,
        text=True,
        timeout=300,
    )
    hit = VERDICT.search(got.stdout + got.stderr)
    if hit is None:
        # A row that produced no verdict at all is not a zero; it is an arm that
        # did not answer, and reporting it as 0 roots would read as a perfect
        # parse. The two are opposite and must not share a cell.
        return {}
    g = hit.groupdict()
    return {
        "roots": int(g["one"] or g["many"]),
        "mended": int(g["mended"] or 0),
        "mendB": int(g["bytes"] or 0),
        "supplied": int(g["supplied"] or 0),
        "seen": int(g["seen"] or 0),
        "nodes": int(g["nodes"] or 0),
    }


def main() -> int:
    arm = sys.argv[1] if len(sys.argv) > 1 else "arm"
    print(f"# {arm}")
    for name, grammar, source in rows():
        got = read(grammar, source)
        if not got:
            print(f"{name}\tNO-VERDICT")
            continue
        print(name + "\t" + "\t".join(f"{k}={v}" for k, v in got.items()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

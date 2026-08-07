#!/usr/bin/env python3
"""How wide is a contested cell, really.

A contested cell used to name one loser. It now names all of them, and this
counts what that bought: per grammar, how many cells drop more than one
reading, and how many readings a binary fork could never have carried.

It reads the folio directly rather than asking the binary, for one reason: the
number wanted here is a property of the *table*, and every instrument that
reports a table's shape reports it after a parse has spent it. `mint` already
prints the `rival` section's size, which is the readings; only the folio itself
says how those readings distribute over cells, and a cell holding three losers
and three cells holding one are the same number there and different facts.

    python3 research/joinery/arity/arity.py [FOLIO|GRAMMAR.json]...

With no argument it mints every grammar under `upstream/grammars/` into a
temporary folio and reads that. Read-only; writes nothing but its own temps.
"""

from __future__ import annotations

import struct
import subprocess
import sys
import tempfile
from pathlib import Path

MAGIC = b"OTLFOLIO"
HEADER_LEN = 96
ENTRY_LEN = 16
# Section ordinals are the file format. `conflict` and `rival` are read by name
# off the directory rather than by a number written here, so appending a section
# upstream cannot silently shift what this script thinks it is reading.
ROOT = Path(__file__).resolve().parents[3]


def sections(blob: bytes) -> dict[int, tuple[int, int, int]]:
    if blob[:8] != MAGIC:
        raise SystemExit("not a folio")
    count = struct.unpack_from("<H", blob, 10)[0]
    out = {}
    for i in range(count):
        kind, stride, n, off = struct.unpack_from("<HHIQ", blob, HEADER_LEN + i * ENTRY_LEN)
        out[kind] = (stride, n, off)
    return out


def kinds() -> list[str]:
    """The `Kind` enum in declaration order, read from its own source."""
    src = (ROOT / "src/folio/leaf.zig").read_text()
    body = src.split("pub const Kind = enum(u16) {", 1)[1].split("\n};", 1)[0]
    out = []
    for line in body.splitlines():
        line = line.strip()
        if not line or line.startswith("//"):
            continue
        if line.endswith(","):
            out.append(line[:-1].strip())
    return out


def survey(path: Path, roll: list[str]) -> tuple[int, int, int, dict[int, int]]:
    blob = path.read_bytes()
    dirs = sections(blob)
    where = {name: i for i, name in enumerate(roll)}
    if "rival" not in where:
        raise SystemExit("this folio has no `rival` section — arm a widened build")
    c_stride, cells, c_off = dirs[where["conflict"]]
    _, rivals, _ = dirs[where["rival"]]
    # A ConflictRecord is a run of u32s; `rival_len` is the last of them.
    wide = c_stride // 4
    spread: dict[int, int] = {}
    for i in range(cells):
        row = struct.unpack_from("<%dI" % wide, blob, c_off + i * c_stride)
        spread[row[-1]] = spread.get(row[-1], 0) + 1
    return cells, rivals, wide, spread


def folio_for(arg: Path, tmp: Path) -> Path:
    if arg.suffix == ".folio":
        return arg
    out = tmp / (arg.stem + ".folio")
    subprocess.run(
        [str(ROOT / "zig-out/bin/joints"), "mint", str(arg), "-o", str(out)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return out


def main() -> int:
    args = [Path(a) for a in sys.argv[1:]]
    if not args:
        args = sorted((ROOT / "upstream/grammars").glob("*.json"))
    roll = kinds()
    print(f"{'grammar':<20}{'cells':>8}{'wide':>8}{'rivals':>8}{'widest':>8}  spread")
    tot_cells = tot_wide = tot_rivals = 0
    worst = 0
    with tempfile.TemporaryDirectory() as td:
        for arg in args:
            try:
                f = folio_for(arg, Path(td))
                cells, rivals, _, spread = survey(f, roll)
            except Exception as e:  # a grammar the press refuses is not a count
                print(f"{arg.stem:<20}{'—':>8}{'—':>8}{'—':>8}{'—':>8}  {e}")
                continue
            deep = sum(n for k, n in spread.items() if k > 0)
            top = max(spread) if spread else 0
            tot_cells += cells
            tot_wide += deep
            tot_rivals += rivals
            worst = max(worst, top)
            shape = " ".join(f"{k}:{n}" for k, n in sorted(spread.items()) if k > 0) or "—"
            print(f"{arg.stem:<20}{cells:>8}{deep:>8}{rivals:>8}{top:>8}  {shape}")
    share = 100.0 * tot_wide / tot_cells if tot_cells else 0.0
    print(
        f"\n{tot_wide} of {tot_cells} contested cells ({share:.2f}%) drop more than one "
        f"reading, and carry {tot_rivals} reading(s) a binary fork could not."
    )
    print(f"widest cell on the corpus drops {worst} reading(s).")

    # The bound has to stay above the corpus, not on it. A column that keeps
    # `spares_max` spares can report at most `spares_max + 1` dropped readings,
    # so a corpus that reaches that number is a corpus this survey can no longer
    # measure: every wider cell would come back wearing the ceiling's value, and
    # the count above would be a floor printed as a total.
    cap = spares_max()
    if worst >= cap + 1:
        print(
            f"\nCHECK FAILED  the widest cell drops {worst} reading(s) and a column keeps"
            f" {cap} spare(s), so a cell can carry at most {cap + 1}. This number is now a"
            f" floor, not a count. Raise `column.spares_max` and re-measure."
        )
        return 1
    print(
        f"CHECK         a column keeps {cap} spare(s), so it can carry {cap + 1} dropped"
        f" reading(s); the widest cell needs {worst}. The bound is above the corpus."
    )
    return 0


def spares_max() -> int:
    """The press's own bound, read from its source rather than restated here."""
    src = (ROOT / "src/press/column.zig").read_text()
    tail = src.split("pub const spares_max", 1)[1]
    return int(tail.split("=", 1)[1].split(";", 1)[0].strip())


if __name__ == "__main__":
    raise SystemExit(main())

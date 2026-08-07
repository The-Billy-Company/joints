#!/usr/bin/env python3
"""How much of every board column is downstream of a repair nobody was counting.

`Cold.canopy` is the known case: an instrument decides a byte was read as the
author wrote it because a node covers it, and in a mended forest that does not
follow. The question this file asks is who else does it, and how much of each
board it is worth.

**`built` is the same shape.** `tool/standing.py` prices `built` as bytes under a
top-level root that has at least one child, and a root built *after* the parse
put its stack down and stood back up in state zero is counted exactly like one
built in context. The board never claimed otherwise - `built` is joints's own
word about its own forest and `damage` is `size - built` - but until
`joints parse --scars` there was no way to *ask* it, so nobody could say
whether the distinction was worth a column or worth a footnote.

**`square` is a different shape and a smaller exposure.** It is agreement with
tree-sitter's derivation, so a stretched root cannot buy it, and `tool/rack.py`
says so in its own docstring. But a leaf built after a repair can still land
under the right oracle parent, and rack has no column that separates those. This
file cannot split `square` itself - rack owns that walk and this lane is not
racing it - so it prices the **exposure**: the share of built bytes downstream
of the first repair, which bounds any per-byte column measured over them.

## This reader has to agree with the board before it may say anything

`built` here is re-derived from the `--ranges --all` render rather than taken
from `standing.py --json`, because the split needs the spans and the board
publishes the totals. So the totals are checked against the board's, per
grammar, on every run, and a row that disagrees is printed as a fault rather
than folded into a headline. Two readers of one render disagreeing is the exact
defect `tool/stamp.py` exists to prevent, and re-deriving is how it comes back.

  python3 research/joinery/scars/blind.py
  python3 research/joinery/scars/blind.py --json .local/scars/blind.json

Exit 0 measured, 1 this reader disagrees with the board, 2 an error.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))

import order  # noqa: E402
import stamp  # noqa: E402
import walls  # noqa: E402
from seat import RANGE, SCAR, Site  # noqa: E402

# `  name [start, end)` - the leading spaces are the depth, two per level, which
# is what tells a top-level root from its children.
LINE = re.compile(r"^( *)(.*) \[(\d+), (\d+)\)$")


class Row(NamedTuple):
    name: str
    size: int
    built: int
    # Bytes under a construct root that a repair deleted anyway: the parse both
    # built over them and walked past them.
    papered: int
    # Bytes under a construct root at or past the first repair in the file. The
    # bound on any per-byte column measured over `built`.
    downstream: int
    mends: int
    first: int
    # The same two, read off a `--mend=keep` parse. The board runs `fell`; this
    # arm is what `built` would become under the other policy, and how much of
    # the difference is over bytes a repair deleted.
    keeps: int
    kept_papered: int

    @property
    def share(self) -> float:
        return self.downstream / self.built if self.built else 0.0


def roots(tree: str) -> list[tuple[int, int, bool]]:
    """Every top-level root: its span, and whether it has a child.

    `standing.py`'s split, re-derived. A root with a child is a construct and
    its bytes are `built`; a root without one is a leaf and its bytes are
    `strewn`.
    """
    out: list[list] = []
    for line in tree.splitlines():
        if not (m := LINE.match(line)):
            continue
        if len(m[1]) == 0:
            out.append([int(m[3]), int(m[4]), False])
        elif out:
            out[-1][2] = True
    return [(a, b, kid) for a, b, kid in out]


def under(name: str, src: Path, art: Path, binary: Path,
          mend: str) -> tuple[bytearray, list[Site]] | None:
    """The construct-root bitmap of one parse, and the repairs it performed."""
    extra = () if mend == "fell" else (f"--mend={mend}",)
    end = stamp.ask(binary, art, src, tree=True, extra=extra)
    if not end.tree:
        return None
    size = src.stat().st_size
    bits = bytearray(size)
    for a, b, kid in roots(end.tree):
        if kid:
            lo, hi = min(a, size), min(b, size)
            bits[lo:hi] = b"\1" * (hi - lo)
    got = subprocess.run([str(binary), "parse", str(art), str(src), "--scars", *extra],
                         capture_output=True, text=True, timeout=stamp.PATIENCE, cwd=ROOT)
    return bits, [Site(int(m[1]), int(m[2]), m[4] == "fell", m[5], int(m[6]), int(m[7]))
                  for line in got.stdout.splitlines() if (m := SCAR.match(line.strip()))]


def holes(bits: bytearray, sites: list[Site]) -> int:
    """Set bytes a repair deleted anyway: built over, and walked past."""
    was = sum(bits)
    for s in sites:
        bits[s.at:s.over] = bytes(max(0, min(s.over, len(bits)) - min(s.at, len(bits))))
    return was - sum(bits)


def row(name: str, src: Path, work: Path, binary: Path) -> Row | None:
    art = order.folio_for(name, work) or (order.GRAMMARS / f"{name}.json")
    if not Path(art).exists() or not src.exists():
        return None
    if (got := under(name, src, Path(art), binary, "fell")) is None:
        return None
    bits, sites = got
    size, built = src.stat().st_size, sum(bits)
    first = sites[0].at if sites else size
    downstream = sum(bits[first:])
    # The keeping policy, as the falsifier on the felling one's zero. A `papered`
    # of 0 that no policy could ever raise would be a silence dressed as a
    # measurement, which is the whole shape this file exists to catch.
    kept = under(name, src, Path(art), binary, "keep")
    keeps = sum(kept[0]) if kept else built
    return Row(name, size, built, holes(bits, sites), downstream, len(sites), first,
               keeps, holes(kept[0], kept[1]) if kept else 0)


def board() -> dict[str, dict]:
    """The board's own rows, so this reader can be checked against them."""
    got = subprocess.run([sys.executable, str(ROOT / "tool" / "standing.py"), "--json"],
                         capture_output=True, text=True, cwd=ROOT)
    try:
        return {r["name"]: r for r in json.loads(got.stdout).get("row", [])}
    except (json.JSONDecodeError, KeyError, TypeError):
        return {}


def held(work: Path, said: dict[str, dict]) -> dict[str, int]:
    """`square` per grammar, from the audit cache, for rows it still describes.

    A bare `standing.py --json` prints `square: 0` on every row, because
    `square` is `0` unless a verdict is live for *this* tree - so reading that
    field without an audit reads thirty zeroes as thirty measurements. This
    reader takes `square` from the same cache `--audit` writes and applies the
    board's own staleness rule (`Held.built != built` is a verdict of another
    tree), so a grammar with no live verdict is **absent** here rather than
    zero, and the caller has to say it withheld it.
    """
    try:
        got = json.loads((work / "audit.json").read_text())
    except (OSError, ValueError):
        return {}
    return {k: int(v["square"]) for k, v in got.items()
            if k in said and int(v.get("built", -1)) == int(said[k]["built"])}


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--json", type=Path)
    args = ap.parse_args(argv)

    work = Path(order.os.environ.get("JOINTS_WORK", ROOT / ".local" / "work"))
    rows = [r for name, src in walls.roster() if (r := row(name, src, work, order.BIN))]
    if not rows:
        print("blind: nothing measurable", file=sys.stderr)
        return 2

    said = board()
    # An empty comparison is a failed check, not a passed one. The first
    # spelling of this gate keyed on the wrong field, matched no row, found no
    # disagreement and printed "agrees on 0 of them" as if that cleared it -
    # which is the flattering-instrument shape twice over, in the very file
    # written to catch it.
    seen = [r for r in rows if r.name in said]
    if len(seen) < len(rows):
        print(f"blind: the board has no row for "
              f"{sorted({r.name for r in rows} - set(said))}", file=sys.stderr)
        return 1
    if bad := [r for r in seen if int(said[r.name]["built"]) != r.built]:
        print("blind: this reader and the board disagree about `built`:", file=sys.stderr)
        for r in bad:
            print(f"  {r.name}: board {said[r.name]['built']:,} · here {r.built:,}",
                  file=sys.stderr)
        return 1
    print(f"blind: {len(rows)} grammar(s) · `built` agrees with the board on every one")

    print(f"\n{'grammar':<12}{'size':>9}{'built':>9}{'mends':>8}{'papered':>9}"
          f"{'downstream':>12}{'share':>8}  first repair")
    for r in sorted(rows, key=lambda r: -r.downstream):
        print(f"{r.name:<12}{r.size:>9,}{r.built:>9,}{r.mends:>8,}{r.papered:>9,}"
              f"{r.downstream:>12,}{100.0 * r.share:>7.1f}%"
              f"  {r.first if r.mends else '-':>9}")
    size = sum(r.size for r in rows)
    built = sum(r.built for r in rows)
    down = sum(r.downstream for r in rows)
    paper = sum(r.papered for r in rows)
    mending = [r for r in rows if r.mends]
    print(f"{'all':<12}{size:>9,}{built:>9,}{sum(r.mends for r in rows):>8,}"
          f"{paper:>9,}{down:>12,}{100.0 * down / built:>7.1f}%")

    print(f"\n**{down:,} B of the {built:,} B this corpus calls `built` "
          f"({100.0 * down / built:.1f}%) is at or past the first repair in its file**, "
          f"and {paper:,} B ({100.0 * paper / built:.1f}%) is under a construct root that "
          f"a repair deleted anyway. {len(mending)} of {len(rows)} grammars mend at all; "
          f"across those {len(mending)}, "
          f"{100.0 * sum(r.downstream for r in mending) / max(sum(r.built for r in mending), 1):.1f}% "
          f"of built bytes are downstream.")
    print("Neither number is a defect in `built`, which never claimed context. Both are "
          "the size of a question no instrument here could ask before `--scars`.")

    # Why `papered` is 0 above, and why that is a measurement rather than a
    # silence: it is a property of the policy the board runs, and the other
    # policy makes it enormous.
    gain = sum(r.keeps for r in rows) - built
    kept = sum(r.kept_papered for r in rows)
    worst = max(rows, key=lambda r: r.keeps - r.built)
    print(f"\n**`papered` is 0 because the board parses `--mend=fell`, and that is a "
          f"result about the policy rather than about repair.** Felling puts the stack "
          f"down at a break, so no construct root can reach across one. Re-read under "
          f"`--mend=keep`, the same corpus builds {gain:+,} B more - and {kept:,} B "
          f"({100.0 * kept / max(gain, 1):.0f}% of the gain) is over bytes a repair "
          f"deleted anyway. {worst.name} alone accounts for "
          f"{worst.keeps - worst.built:+,} B of it. Any lane tempted to switch the "
          f"default because `built` reads higher under `keep` is reading that.")

    # `square` is rack's, and rack cannot split it. Where a grammar's every built
    # byte is downstream of its first repair the split needs no per-byte walk at
    # all: all of its `square` is, by arithmetic.
    sq = held(work, said)
    if not sq:
        print(f"\n`square` withheld: no live oracle verdict under {work}. "
              f"Run `python3 tool/standing.py --audit` on this arm first.")
    else:
        live = [r for r in seen if r.name in sq]
        whole = [r for r in live if r.built and r.downstream == r.built]
        sure = sum(sq[r.name] for r in whole)
        all_sq = sum(sq.values())
        exposed = sum(sq[r.name] for r in live if r.mends)
        # A bound, not an estimate. `square` is a subset of `built`, and this
        # file knows which `built` bytes are downstream, so per grammar the
        # downstream share of `square` is at least `square - upstream` (it
        # cannot all hide upstream if upstream is too small) and at most
        # `min(square, downstream)`. Summing the two ends is the honest answer
        # to "how much of `square` is exposed" without the walk rack owns.
        low = sum(max(0, sq[r.name] - (r.built - r.downstream)) for r in live)
        high = sum(min(sq[r.name], r.downstream) for r in live)
        dark = sorted({r.name for r in seen} - set(sq))
        print(f"\n**`square` is {all_sq:,} B over the {len(live)} grammar(s) with a live "
              f"verdict. {sure:,} B of it is provably out of context** - it belongs to "
              f"{len(whole)} grammar(s) ({', '.join(r.name for r in whole)}) whose every "
              f"built byte is at or past the first repair, so no per-byte walk is needed "
              f"to say so. Another {exposed - sure:,} B sits in a mending grammar where "
              f"the split needs a walk `tool/rack.py` owns and does not have; the "
              f"remaining {all_sq - exposed:,} B is in a grammar that never mends and is "
              f"not exposed at all. rack's docstring already argues `square` is the one "
              f"column a stretched root cannot buy, and that is still true - a repair is "
              f"not a stretched root, and this is the other question.")
        print(f"Bounded rather than guessed: since `square` is a subset of `built` and "
              f"this file knows which `built` bytes are downstream, between {low:,} B "
              f"({100.0 * low / all_sq:.1f}%) and {high:,} B ({100.0 * high / all_sq:.1f}%) "
              f"of `square` is downstream of a repair. The walk that would close that "
              f"interval to a number is rack's.")
        if dark:
            print(f"Withheld for want of a live verdict: {', '.join(dark)}.")

    if args.json:
        args.json.write_text(json.dumps([r._asdict() for r in rows], indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

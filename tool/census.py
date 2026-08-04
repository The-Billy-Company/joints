#!/usr/bin/env python3
"""Thirty grammars, one table: how far does each one get, and what stopped it?

The eleven corpus grammars have had a reach table since the beginning. The
nineteen held-out ones have never had one, because until the oracle reader
learned to read a multi-line token there was nothing to put in it. There is now.

The column that matters is not `reach` but `wall`, and it is derived from the
verdict rather than assigned by hand:

  whole      accepted; one root over every byte
  unclosed   `truncated` - every byte lexed, no root ever closed
  lexical    `stray byte at N` - nothing could produce a terminal at N, which is
             what a grammar's external scanner looks like from outside
  state      `unexpected T at N in state S` - the token lexed and the state
             refused it, which is a table or a fork question and never lexical

Blindness to externals is reported alongside, since it is the single strongest
predictor of the lexical class and the two are constantly confused.

  python3 tool/census.py            the table
  python3 tool/census.py --json     machine output
  python3 tool/census.py --set=corpus | --set=breadth
"""

import json
import os
import sys
from pathlib import Path
from typing import NamedTuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
import breadth as B  # noqa: E402
from grammars import load  # noqa: E402
from rung1 import pairs  # noqa: E402
from stamp import ask as ask_one  # noqa: E402
from stamp import take  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
GRAMMARS = ROOT / "upstream" / "grammars"
CORPUS = ROOT / "research" / "joinery" / "corpus"
BIN = Path(os.environ.get("OUTLINER_BIN", ROOT / "zig-out" / "bin" / "outliner"))
PATIENCE = 240

# The same eleven files, one program in eleven languages; see corpus/README.md.



class Row(NamedTuple):
    name: str
    set_: str
    size: int
    reach: int
    wall: str
    blind: int
    verdict: str

    @property
    def share(self) -> float:
        return self.reach / self.size if self.size else 0.0

    def as_dict(self) -> dict:
        return {**self._asdict(), "share": round(self.share, 4)}


def ask(name: str, src: Path, set_: str) -> Row:
    size = src.stat().st_size if src.exists() else 0
    if not size:
        return Row(name, set_, 0, 0, "no source", 0, "no source fetched")
    end = ask_one(BIN, GRAMMARS / f"{name}.json", src, size=size, patience=PATIENCE)
    return Row(name, set_, size, end.reach, end.kind, end.blind, end.verdict)


def census(want: str) -> list[Row]:
    rows = []
    if want in ("all", "corpus"):
        rows += [ask(n, CORPUS / leaf, "corpus") for n, leaf in sorted(pairs())]
    if want in ("all", "breadth"):
        rows += [ask(p.name, B.source_of(p.name), "held-out")
                 for p in sorted(load("breadth"), key=lambda p: p.name)]
    return rows


def table(rows: list[Row]) -> None:
    print(f"\n{'grammar':<19}{'set':<10}{'bytes':>8}{'reach':>8}{'':>3}"
          f"{'share':>7}  {'wall':<9}{'blind':>6}  where it stops")
    print("-" * 118)
    for r in rows:
        where = r.verdict if r.wall != "whole" else "-"
        print(f"{r.name:<19}{r.set_:<10}{r.size:>8}{r.reach:>8}{'':>3}"
              f"{r.share * 100:>6.1f}%  {r.wall:<9}{r.blind or '':>6}  {where[:44]}")

    by = {}
    for r in rows:
        by[r.wall] = by.get(r.wall, 0) + 1
    whole, unclosed, mended = (by.get(k, 0) for k in ("whole", "unclosed", "mended"))
    stopped = [r for r in rows if r.wall in ("lexical", "state")]
    bytes_in = sum(r.size for r in rows)
    got = sum(r.reach for r in rows)
    print(f"\n{len(rows)} grammars · {whole} parse whole · {mended} hit a wall and read on"
          f" · {unclosed} read every byte and closed nothing · {len(stopped)} stop dead")
    print("walls: " + " · ".join(f"{n} {k}" for k, n in sorted(by.items(), key=lambda kv: -kv[1])))
    print(f"bytes: {got} of {bytes_in} covered, {got / bytes_in * 100:.1f}%"
          # A mended row's reach is how far the forest extends, not a claim that
          # what it holds is right. The differential is what says that, and the
          # two questions have to stay apart or a recovered parse reads as a
          # correct one.
          + (f" (of which {sum(r.reach for r in rows if r.wall == 'mended')}"
             " is forest over mended input, covered but not vouched for)" if mended else ""))
    ext = sum(1 for r in stopped if r.wall == "lexical" and r.blind)
    print(f"of the {len(stopped)} stopped dead, {ext} stop lexically in a grammar that "
          "declares externals we cannot run")


def main(argv: list[str]) -> int:
    if "--help" in argv or "-h" in argv:
        print(__doc__)
        return 0
    want = next((a.split("=", 1)[1] for a in argv if a.startswith("--set=")), "all")
    if want not in ("all", "corpus", "breadth"):
        print(f"census.py: --set must be all, corpus or breadth, not {want!r}", file=sys.stderr)
        return 2
    if not BIN.exists():
        print(f"census.py: no binary at {BIN}", file=sys.stderr)
        return 2
    mark = take(BIN)
    rows = census(want)
    if "--json" in argv:
        print(json.dumps({"stamp": mark.as_dict(),
                          "row": [r.as_dict() for r in rows]}, indent=2))
        return 0
    table(rows)
    print(mark.line())
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

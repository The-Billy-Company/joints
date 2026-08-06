#!/usr/bin/env python3
"""Cut a file immediately before its wall. Does the forest become a tree?

This is the falsifier for `standing`, and it is the reason `rubble` replaced it
as the headline.

`standing` counts bytes under a root that has children, against `covered`, which
counts bytes under any root at all. The gap between them was read as structure
the parser failed to build - "a token lying where a tree should be". That reading
requires the childless roots to be *damage*. They are mostly not.

**The mechanism.** One token the tables refuse, anywhere in the file, prevents
the top-level reduce. So the parse cannot hand back one root over everything; it
hands back a forest of the highest constructs it did complete. Every declared
extra sitting *between* those constructs - every comment, every docstring - was
going to be a child of the node that never closed, and becomes a childless root
instead. It is a leaf in a healthy parse too. It has no subtree to be missing.

So `covered - standing` is not lost structure. It is **comment density times
has-a-wall**, and a grammar can be punished by it for having comments.

**The proof, and it is about as clean as this project gets.** Cut the file
immediately before the byte its wall names, hand the *same grammar* the
truncated bytes, and the parse closes: `accepted, 1 root`, 100% standing, on a
prefix of the identical file. Nothing about the parser changed. The bytes that
were "strewn" are now inside the tree, because the wall that demoted them is no
longer in the file.

  python3 tool/shear.py              every grammar that hits a wall
  python3 tool/shear.py --set=corpus the five the argument was made on
  python3 tool/shear.py --json       machine output

A grammar that does **not** flip is the interesting row, not a failure of the
proof: it means something past the first wall is also refused, so the first wall
is not the whole of its forest. Those are reported as `still N roots` with the
second wall named, because that is a real finding about that grammar rather than
noise in this one.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import NamedTuple

sys.path.insert(0, str(Path(__file__).resolve().parent))

import standing  # noqa: E402
from stamp import AT, take  # noqa: E402

WORK = standing.ROOT / ".local" / "shear"


class Cut(NamedTuple):
    """One grammar's file, whole and cut.

    The four `cut_*` columns and `wall` are `None` rather than `0` when there
    was nothing to measure, and that is not tidiness. A grammar that never
    completes one top-level construct has **no prefix** - there is no shorter
    file to hand back, so `kept`, `cut_roots`, `cut_standing` and `cut_rubble`
    are questions nobody could ask. Written as zeroes they read as *measured*
    zeroes: `cut_rubble 0` beside a `whole_rubble` of 13,811 says the cut
    removed every unstructured byte, which is the opposite of what happened.
    `budge.py` has been reporting `shear.Cut.cut_rubble` as `flat/open - 0
    ×152` for exactly as long as this instrument has existed - one value, every
    observation, and the writer it names is `best.rubble if best else 0`.

    `wall` has the same shape one level worse. `wall_of(verdict) or 0` turned a
    verdict that names no byte into **a wall at byte 0**, which is a real
    position and a plausible one - the offset half this corpus's blind-external
    grammars genuinely stop at.
    """

    grammar: str
    set_: str
    bytes: int
    wall: int | None  # the byte the verdict named, or None if it named none
    whole_roots: int
    whole_standing: float
    whole_rubble: int
    kept: int | None  # bytes in the prefix; None when no prefix stands alone
    cut_roots: int | None
    cut_standing: float | None
    cut_rubble: int | None
    cut_verdict: str
    first: int  # the boundary the same grammar stops accepting at

    @property
    def flipped(self) -> bool:
        """One root over every byte of the prefix, and nothing left unstructured."""
        return self.kept is not None and self.cut_roots == 1 and self.cut_standing >= 1.0

    def as_dict(self) -> dict:
        return {**self._asdict(), "flipped": self.flipped,
                "whole_standing": round(self.whole_standing, 4),
                "cut_standing": (None if self.cut_standing is None
                                 else round(self.cut_standing, 4))}


def wall_of(verdict: str) -> int | None:
    hit = AT.search(verdict)
    return int(hit[1]) if hit else None


def seams(name: str, src: Path) -> list[int]:
    """The parse's own top-level construct boundaries, ascending.

    Cutting anywhere else is a different experiment and says so loudly: cut at
    the wall byte itself and the prefix lands mid-construct, comes back
    `truncated`, and proves only that half a function is half a function. The
    claim under test is about the **top-level reduce**, so every candidate prefix
    has to be a whole number of top-level constructs.
    """
    read = standing.ranged(name, src)
    return sorted({b for _, a, b, kid in read[0] if kid}) if read else []


def shear(was: standing.Row, src: Path) -> Cut | None:
    """Walk the boundaries up until the same grammar stops accepting the prefix.

    The verdict names only the **last** token refused, so cutting before it
    leaves every earlier refusal in the file - which is why c, cpp, go and bash
    still come back as forests when you cut there. Scanning up from the front
    instead locates the *first* refusal, and the prefix below it is the claim:
    one root, 100% standing, zero rubble, identical bytes, identical grammar.
    """
    if was.roots <= 1:
        return None  # nothing to explain: it already parses whole
    WORK.mkdir(parents=True, exist_ok=True)
    text = src.read_bytes()
    cut = WORK / f"{was.name}.cut{src.suffix or '.txt'}"
    best, first = None, was.size
    for end in seams(was.name, src):
        if end <= 0 or end >= was.size:
            continue
        cut.write_bytes(text[:end])
        now = standing.ask(was.name, cut, was.set_)
        if now is None or now.roots != 1 or now.standing < 1.0:
            first = end
            break
        best = now
    # A grammar with no standing prefix at all is the interesting row, not a row
    # to drop: it means the file never completes a single top-level construct, so
    # its forest is not one wall's doing and its `rubble` is the real thing.
    return Cut(grammar=was.name, set_=was.set_, bytes=was.size,
               wall=wall_of(was.verdict), whole_roots=was.roots,
               whole_standing=was.standing, whole_rubble=was.rubble,
               kept=best.size if best else None,
               cut_roots=best.roots if best else None,
               cut_standing=best.standing if best else None,
               cut_rubble=best.rubble if best else None,
               cut_verdict=best.verdict if best else "no prefix stands alone",
               first=first)


def survey(want: str) -> list[Cut]:
    """Which grammars are in `want` is `standing`'s question, asked once."""
    where = dict(standing.roster())
    rows = (shear(was, where[was.name]) for was in standing.survey(want)
            if was.name in where)
    return [r for r in rows if r is not None]


def table(rows: list[Cut]) -> None:
    print("\nshear: the same grammar and the same bytes, cut at the first refusal\n")
    print(f"  {'grammar':<12}{'set':<10}{'bytes':>8}{'roots':>7}{'standing':>10}"
          f"{'rubble':>8}   ->{'kept':>8}{'roots':>7}{'standing':>10}{'rubble':>8}"
          f"  {'':<3}what the prefix says")
    print("  " + "-" * 132)
    for r in sorted(rows, key=lambda r: (not r.flipped, r.set_, r.grammar)):
        mark = "OK " if r.flipped else "-- "
        # A row with no prefix has no cut to report, so the four cut columns
        # read `—` rather than four zeroes somebody could quote as the result
        # of an experiment that never ran. `cut_verdict` says which it is.
        cut = ((f"{r.kept:>8}{r.cut_roots:>7}{r.cut_standing * 100:>9.1f}%{r.cut_rubble:>8}")
               if r.kept is not None else f"{'—':>8}{'—':>7}{'—':>10}{'—':>8}")
        print(f"  {r.grammar:<12}{r.set_:<10}{r.bytes:>8}{r.whole_roots:>7}"
              f"{r.whole_standing * 100:>9.1f}%{r.whole_rubble:>8}   ->" + cut
              + f"  {mark}{r.cut_verdict[:30]}")
    flew = [r for r in rows if r.flipped]
    print(f"\n  {len(flew)} of {len(rows)} hand back one root over every byte of the prefix"
          " at 100% standing and zero rubble,")
    print("  on identical bytes and an identical grammar. Nothing about the parser"
          " changed between the two columns.")
    if flew:
        freed = sum(r.whole_roots - 1 for r in flew)
        print(f"  {freed} childless roots across those {len(flew)} sit downstream of a"
              " refusal rather than marking code the tables could not shape.")
    stuck = [r for r in rows if not r.flipped]
    if stuck:
        print(f"\n  {len(stuck)} never complete one top-level construct, so no prefix of"
              " them stands alone. These are not")
        print("  wall artefacts, and they are where the rubble is:")
        for r in sorted(stuck, key=lambda r: -r.whole_rubble):
            # `first == bytes` means the scan never had a boundary to cut at: not
            # one construct closes anywhere in the file, so the wall is whatever
            # the verdict named and there is nothing downstream of it to blame.
            # `wall` is None when the verdict named no byte at all, which is a
            # different row from one walled at offset zero — and `or 0` used to
            # print them the same way.
            wall = f"byte {r.wall}" if r.wall is not None else "a byte the verdict does not name"
            where = (f"first refusal at byte {r.first} of {r.bytes}" if r.first < r.bytes
                     else f"no construct closes anywhere; wall at {wall} of {r.bytes}")
            print(f"    {r.grammar:<12}{r.whole_rubble:>7} rubble  {where}")
    print("\n  so `covered - standing` prices comment density times has-a-wall,"
          " and a grammar can be punished by it")
    print("  for having comments. `rubble` is the column that survives the test:"
          " code left unstructured.")


def main(argv: list[str]) -> int:
    if "--help" in argv or "-h" in argv:
        print(__doc__)
        return 0
    want = next((a.split("=", 1)[1] for a in argv if a.startswith("--set=")), "all")
    if want not in ("all", "corpus", "breadth"):
        print(f"shear.py: --set must be all, corpus or breadth, not {want!r}", file=sys.stderr)
        return 2
    if not standing.BIN.exists():
        print(f"shear.py: no binary at {standing.BIN}", file=sys.stderr)
        return 2
    mark = take(standing.BIN)
    rows = survey(want)
    if not rows:
        print("shear.py: no grammar hit a wall to cut at", file=sys.stderr)
        return 1
    if "--json" in argv:
        print(json.dumps({"what": "shear", "stamp": mark.as_dict(),
                          "row": [r.as_dict() for r in rows]}, indent=2))
        return 0
    table(rows)
    print(mark.line())
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

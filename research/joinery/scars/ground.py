#!/usr/bin/env python3
"""How much of the board's `square` was read cleanly, and how much stands on a repair?

`rack.py` scores every built byte into one bucket and says nothing about the
ground it was standing on. A byte it calls `square` in a region the parse read
straight through is a claim about the grammar. The same byte downstream of a
deletion is a claim about the grammar *and* about the repair that got the parse
there - and the board cannot tell them apart, so every `square` figure anybody
has quoted is a blend of the two in an unstated ratio.

`RESULT-2-untested.md` bounded that ratio at **19.9-23.0%** and could not
narrow it, because `blind.py` re-derives `built` from `--ranges --all` and has
no access to the classification: it can say which bytes are downstream of a
repair, not which of *those* were scored square. This file closes the join.

## It is not a sixth price

`rack.py` prices a byte under a frame we never built, and a lane is re-pricing
that now; `rack.py against` refuses across a rule change at exit 4. Nothing
here is a new rule. `survey` is called verbatim, three times, over the same
`plumb.Read` with only the *judged byte range* narrowed - the frames, the
spines, the renames and the oracle tree are the ones rack already had. So this
is `rack.twice`'s trick pointed at a different axis: one parse, one
classification, partitioned rather than re-decided.

Which is also what makes it checkable. The two halves must add back up to the
whole row, column by column, and they are computed by three independent walks
that never see each other's answers. If a clip changed a verdict instead of
merely splitting where it was counted, the sum breaks and the run exits 1. A
join that cannot fail is not evidence about a join.

## What counts as repaired ground

`blind.py`'s definition, kept verbatim so the number is comparable to the
interval it narrows: **at or past the first repair in the file.** A parse that
deleted a token at byte 900 is a different parse from byte 900 on, whatever it
does afterwards, and every node it builds downstream stands on that choice.

Two readings are printed, and the difference between them is the finding
`blind.py` could not have:

  cuts    deletions only, which is the site set `seat.SCAR` matches and the
          set the 19.9-23.0% interval was computed over
  all     deletions **and** supplies. A supply is a repair too, and it can land
          earlier in the file than any deletion, which moves the cut left and
          makes the repaired share larger

  python3 research/joinery/scars/ground.py
  python3 research/joinery/scars/ground.py --json .local/scars/ground.json
  python3 research/joinery/scars/ground.py --selftest    # can the check fail?

Exit 0 measured, 1 a split did not add back up, 2 an error.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))

import order  # noqa: E402
import plumb  # noqa: E402
import rack  # noqa: E402
import stamp  # noqa: E402

# Every `Seen` column that is a count of BYTES inside the judged range, and so
# must survive being cut in two. Named rather than derived by subtracting the
# ones that don't, because a list built by exclusion admits a new column
# silently and this is the whole check.
#
# `size` is the file and is the same on both halves. `ours_nodes`,
# `their_nodes`, `shared`, `frames` and `framed` count *nodes per window*, and
# both halves see every window, so they double rather than split - they are
# left out of the sum and reported off the whole row only.
BYTES = ("built", "square", "renamed", "askew", "racked", "unframed", "engulf",
         "unjudged", "unwindowed", "shade", "shelter", "mute", "stretch",
         "airy", "warp", "slack", "veiled", "padding", "gap")


class Site(NamedTuple):
    at: int
    felled: bool


class Split(NamedTuple):
    name: str
    whole: rack.Seen
    clean: rack.Seen
    scarred: rack.Seen
    at: int          # the cut, or -1 for a file with no repair
    sites: int
    shut: tuple[str, ...]   # columns whose halves did not add up


def sites(case: plumb.Case, extra: tuple[str, ...] = ()) -> list[Site] | None:
    """Every repair site, off the same parse `plumb.read` scores.

    `--scars` suppresses the tree, so this is a second invocation rather than a
    second parse: same binary, same folio, same source, same flags. The board's
    own run is `stamp.ask(..., tree=True)`, which adds `--ranges --all`; those
    change what is *printed*, not what is read.
    """
    folio = plumb.folio_for(case.grammar.stem, plumb.WORK)
    if folio is None or not case.source.exists():
        return None
    argv = [str(plumb.BIN), "parse", str(folio), str(case.source), "--scars", *extra]
    got = subprocess.run(argv, capture_output=True, text=True,
                         timeout=stamp.PATIENCE, cwd=ROOT, check=False)
    out: list[Site] = []
    for line in got.stdout.splitlines():
        line = line.strip()
        if m := seat_cut(line):
            out.append(Site(m, True))
        elif m := seat_gave(line):
            out.append(Site(m, False))
    return out


def seat_cut(line: str) -> int | None:
    """`scar A..B nB fell|kept ...` - the offset, or None if this is not one."""
    if not line.startswith("scar "):
        return None
    head = line[5:].split(maxsplit=1)[0]
    a, sep, _ = head.partition("..")
    return int(a) if sep and a.isdigit() else None


def seat_gave(line: str) -> int | None:
    """`scar N gave SYM ...` - a supply, which has no width."""
    bits = line.split()
    if len(bits) >= 3 and bits[0] == "scar" and bits[1].isdigit() and bits[2] == "gave":
        return int(bits[1])
    return None


def clip(saw: plumb.Read, lo: int, hi: int) -> plumb.Read:
    """The same read, judged only over `[lo, hi)`.

    Two things are narrowed and one thing is deliberately not.

    **`scope` is clipped**, because it is what `built` is counted over and what
    the `stretch`/`airy`/`warp`/`slack`/`padding` walk visits. `built` is
    recomputed from the clipped spans so the arithmetic those columns do
    against it still holds.

    **A window's judged range is clipped**, and its *frame* is not. A window is
    `(judge_from, judge_to, root_start, root_end)`; `survey` derives its cut
    points from the first pair and `within`/`unframed` read the second. Clip
    the frame and the classification moves - `unframed` walks the set of root
    extents to find the seams between adjacent roots, so dropping a root
    invents a seam that is not there. So a window outside the slice is kept,
    with an empty judged range: `cuts` collapses to a single point, no byte is
    visited, and the frame it contributes to `unframed` is untouched.

    That asymmetry is the entire reason the halves are addable, and it is why
    the check downstream is worth running rather than assumed.
    """
    scope = [(max(a, lo), min(b, hi)) for a, b in saw.scope]
    scope = [(a, b) for a, b in scope if b > a]
    windows = [(max(jf, lo), min(jt, hi), ra, rb) if min(jt, hi) > max(jf, lo)
               else (jf, jf, ra, rb)
               for jf, jt, ra, rb in saw.windows]
    return saw._replace(scope=scope, windows=windows,
                        built=sum(b - a for a, b in scope))


def split(case: plumb.Case, saw: plumb.Read, at: int, count: int) -> Split:
    """One row, surveyed whole and then as two halves that must add back up."""
    whole = rack.survey(case.name, saw)
    size = len(saw.blob)
    # A file with no repair is entirely clean ground, and saying so through the
    # same two calls rather than by special-casing keeps the check live on it:
    # an empty scarred half must still sum correctly.
    edge = size if at < 0 else at
    clean = rack.survey(case.name, clip(saw, 0, edge))
    scarred = rack.survey(case.name, clip(saw, edge, size))
    loose = tuple(k for k in BYTES
                  if getattr(clean, k) + getattr(scarred, k) != getattr(whole, k))
    return Split(case.name, whole, clean, scarred, at, count, loose)


def measure(case: plumb.Case, extra: tuple[str, ...] = (),
            felled_only: bool = False, at: int | None = None) -> Split | None:
    """One row. `at` overrides the cut, for a delta priced over one byte range.

    `felled_only` drops supplies from the site set, which is `seat.SCAR`'s
    population and the one the 19.9-23.0% interval was computed over. A supply
    is a repair and can land earlier in the file than any deletion, so leaving
    them in moves the cut left and makes the repaired share *larger* - the
    difference between the two readings is the honest size of that choice.
    """
    saw = plumb.read(case, extra)
    if saw is None or saw.why:
        return None
    found = sites(case, extra)
    if found is None:
        return None
    keep = [s for s in found if s.felled or not felled_only]
    return split(case, saw, min((s.at for s in keep), default=-1)
                 if at is None else at, len(keep))


def delta(case: plumb.Case, extra: tuple[str, ...]) -> tuple[Split, Split] | None:
    """The arm beside its `--no-supply` control, split at ONE cut.

    The scoreboard's own control: same binary, one flag apart. Their repair
    sites differ - that is what the flag does - so pricing each half against
    its own parse's first repair would compare two different byte ranges and
    call the difference a delta. The cut is the earlier of the two, so both
    arms are cut at the same offset and `arm.clean - ctl.clean` is a statement
    about the same bytes on both sides.
    """
    was, now = sites(case, (*extra, "--no-supply")), sites(case, extra)
    if was is None or now is None:
        return None
    at = min((s.at for s in [*was, *now]), default=-1)
    ctl = measure(case, (*extra, "--no-supply"), at=at)
    arm = measure(case, extra, at=at)
    return None if ctl is None or arm is None else (ctl, arm)


def selftest() -> int:
    """Prove the additivity check can fail, on a read this file builds by hand.

    Three windows over a fabricated forest, no binary and no oracle. The first
    case splits at a byte and must close. The second clips the *frame* as well
    as the judged range - the mistake this file's `clip` exists to not make -
    and must be caught. A check that has only ever passed has not been tested.
    """
    blob = b"x" * 60
    mine = [plumb.Node("root", True, 0, 30, 0, False),
            plumb.Node("leaf", True, 0, 30, 1, True),
            plumb.Node("root", True, 30, 60, 0, False),
            plumb.Node("leaf", True, 30, 60, 1, True)]
    saw = plumb.Read(blob, mine, list(mine), [(0, 60)],
                     [(0, 30, 0, 30), (30, 60, 30, 60)], set(), 60, "")

    whole = rack.survey("probe", saw)
    good = (rack.survey("probe", clip(saw, 0, 25)),
            rack.survey("probe", clip(saw, 25, 60)))
    # The bug, spelled out: drop the windows that fall outside the slice
    # instead of emptying them. `unframed` then sees one root where there are
    # two, and the seam between them stops existing.
    def maim(s: plumb.Read, lo: int, hi: int) -> plumb.Read:
        keep = [w for w in s.windows if min(w[1], hi) > max(w[0], lo)]
        span = [(max(a, lo), min(b, hi)) for a, b in s.scope]
        span = [(a, b) for a, b in span if b > a]
        return s._replace(scope=span, windows=keep, built=sum(b - a for a, b in span))
    bad = (rack.survey("probe", maim(saw, 0, 25)),
           rack.survey("probe", maim(saw, 25, 60)))

    ok = all(getattr(good[0], k) + getattr(good[1], k) == getattr(whole, k)
             for k in BYTES)
    caught = [k for k in BYTES
              if getattr(bad[0], k) + getattr(bad[1], k) != getattr(whole, k)]
    print(f"{'ok ' if ok else 'BAD'} a clipped judged range adds back up "
          f"({whole.built} built, {good[0].built} + {good[1].built})")
    print(f"{'ok ' if caught else 'BAD'} a clipped FRAME is caught"
          + (f" - {', '.join(caught)} disagree" if caught
             else " - NOTHING disagreed, so the check proves nothing"))
    if not (ok and caught):
        print("ground: self-test failed", file=sys.stderr)
    return 0 if (ok and caught) else 1


def deltas(picked: list[plumb.Case], extra: tuple[str, ...]) -> int:
    """Where a supply's `square` gain actually landed: clean ground, or repaired.

    The question `RESULT-1-insert.md` could not answer. It moved corpus
    `square` by +3,124 and knew that some share of it sat inside the region
    `../scars/` bounded at 19.9-23.0%, with no instrument able to say which.
    Splitting both arms at one cut says it directly, per grammar and in total.
    """
    got = [(c.name, d) for c in picked if (d := delta(c, extra))]
    if not got:
        print("ground: no arm/control pair", file=sys.stderr)
        return 2
    print(f"{'grammar':<12}{'cut':>9}{'ctl sq':>10}{'arm sq':>10}{'Dsq':>8}"
          f"{'D clean':>9}{'D scar':>8}{'scar share':>12}")
    tot = [0, 0, 0, 0]
    for name, (ctl, arm) in got:
        d_all = arm.whole.square - ctl.whole.square
        d_cl = arm.clean.square - ctl.clean.square
        d_sc = arm.scarred.square - ctl.scarred.square
        tot = [tot[0] + ctl.whole.square, tot[1] + arm.whole.square,
               tot[2] + d_cl, tot[3] + d_sc]
        print(f"{name:<12}{ctl.at if ctl.at >= 0 else '-':>9}"
              f"{ctl.whole.square:>10,}{arm.whole.square:>10,}{d_all:>+8,}"
              f"{d_cl:>+9,}{d_sc:>+8,}"
              f"{(100.0 * d_sc / d_all if d_all else 0.0):>11.1f}%")
    move = tot[1] - tot[0]
    print(f"{'':<12}{'':>9}{tot[0]:>10,}{tot[1]:>10,}{move:>+8,}"
          f"{tot[2]:>+9,}{tot[3]:>+8,}"
          f"{(100.0 * tot[3] / move if move else 0.0):>11.1f}%")
    if move:
        print(f"\n**{tot[3]:+,} of the {move:+,} square-byte movement "
              f"({100.0 * tot[3] / move:.1f}%) landed at or past the first repair "
              f"in its file**; {tot[2]:+,} ({100.0 * tot[2] / move:.1f}%) landed on "
              f"ground the parse read straight through.")
    loose = [n for n, (c, a) in got if c.shut or a.shut]
    for n in loose:
        print(f"ground: {n} does not split", file=sys.stderr)
    return 1 if loose else 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--json", type=Path)
    ap.add_argument("--only", nargs="*", help="grammars, default every board row")
    ap.add_argument("--mend", choices=("keep", "fell", "relent"),
                    help="default is the binary's, which is what the board reads")
    ap.add_argument("--cuts", action="store_true",
                    help="deletions only - `blind.py`'s site set, ignoring supplies")
    ap.add_argument("--delta", action="store_true",
                    help="the arm beside its --no-supply control, split at one cut")
    ap.add_argument("--selftest", action="store_true",
                    help="prove the additivity check can fail, without a binary")
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()

    extra = (f"--mend={args.mend}",) if args.mend else ()
    picked = [c for c in plumb.slate() if not args.only or c.name in args.only]
    rack.warm(picked)
    if args.delta:
        return deltas(picked, extra)
    rows = [r for c in picked if (r := measure(c, extra, args.cuts))]
    if not rows:
        print("ground: nothing to read", file=sys.stderr)
        return 2

    mark = stamp.take(order.BIN) if hasattr(stamp, "take") else None
    print(f"{'grammar':<12}{'sites':>7}{'first':>9}{'built':>10}{'square':>10}"
          f"{'sq clean':>10}{'sq scar':>9}{'scar%':>7}{'crooked':>9}{'ck scar':>9}")
    for r in sorted(rows, key=lambda r: -r.scarred.square):
        sq = r.whole.square
        print(f"{r.name:<12}{r.sites:>7,}{r.at if r.at >= 0 else '-':>9}"
              f"{r.whole.built:>10,}{sq:>10,}{r.clean.square:>10,}"
              f"{r.scarred.square:>9,}"
              f"{(100.0 * r.scarred.square / sq if sq else 0.0):>6.1f}%"
              f"{r.whole.crooked:>9,}{r.scarred.crooked:>9,}")

    sq = sum(r.whole.square for r in rows)
    on = sum(r.scarred.square for r in rows)
    ck = sum(r.whole.crooked for r in rows)
    ckon = sum(r.scarred.crooked for r in rows)
    bl = sum(r.whole.built for r in rows)
    blon = sum(r.scarred.built for r in rows)
    print(f"{'':<12}{sum(r.sites for r in rows):>7,}{'':>9}{bl:>10,}{sq:>10,}"
          f"{sq - on:>10,}{on:>9,}{100.0 * on / sq:>6.1f}%{ck:>9,}{ckon:>9,}")

    print(f"\n**{on:,} of {sq:,} square bytes ({100.0 * on / sq:.1f}%) stand at or "
          f"past the first repair in their file**, and {sq - on:,} "
          f"({100.0 * (sq - on) / sq:.1f}%) were read straight through. "
          f"`RESULT-2-untested.md` bounded this at 19.9-23.0% off `built` alone "
          f"and could not narrow it.")
    print(f"\nThe same cut over the whole board: {blon:,} of {bl:,} built bytes "
          f"({100.0 * blon / bl:.1f}%) and {ckon:,} of {ck:,} crooked "
          f"({100.0 * ckon / ck if ck else 0.0:.1f}%) are downstream of a repair.")
    if mark:
        print(f"\n{mark}")

    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps([{
            "name": r.name, "at": r.at, "sites": r.sites, "loose": list(r.shut),
            "whole": r.whole._asdict() | {"worst": []},
            "clean": r.clean._asdict() | {"worst": []},
            "scarred": r.scarred._asdict() | {"worst": []},
        } for r in rows], indent=1, default=str))

    loose = [r for r in rows if r.shut]
    for r in loose:
        print(f"ground: {r.name} does not split - {', '.join(r.shut)} disagree "
              f"between the whole row and its two halves", file=sys.stderr)
    return 1 if loose else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

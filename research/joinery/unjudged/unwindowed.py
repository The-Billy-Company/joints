#!/usr/bin/env python3
"""`unwindowed` is not `unjudged`, and most of it is `unframed` under another name.

`Seen.blind` is `unjudged + unwindowed` and the board printed the pair under
`unjudged`'s sentence - *"carry no oracle verdict"*, reason *"plumb rule, byte by
byte"*. Both halves of that line were wrong for haskell, whose `unjudged` is
exactly **0**: no plumb rule fires on any of its 1,013 bytes.

`unwindowed` is the `not t_sp[k]` branch of `rack.survey` - *the oracle has
nothing strictly inside this window here and outliner does*. Its docstring is
right that the oracle's silence inside a window is not a verdict. What the column
cannot say is **why** the oracle has nothing inside, and this walks the same
windows `survey` walks to find out: for each such byte it keeps outliner's
deepest node, the oracle's node, the narrowest oracle bracket that *spans* the
window from outside, and whether that byte sits under a frame `rack.unframed`
already charges us for.

The answer is the flattering-the-parser hazard stated as a number: **building
more structure under a frame you are missing moves bytes out of `unframed`, which
is a charge, and into `unwindowed`, which reads as silence.** Same bytes, same
missing frame; the column depends only on whether we put something of our own
underneath.

    python3 research/joinery/unjudged/unwindowed.py            the corpus table
    python3 research/joinery/unjudged/unwindowed.py haskell    one row, in full
"""
from __future__ import annotations

import argparse
import bisect
import collections
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))
import plumb  # noqa: E402
import rack  # noqa: E402


def walk(case: plumb.Case) -> dict | None:
    """Every `unwindowed` byte of one row, as maximal runs with their provenance."""
    saw = plumb.read(case)
    if saw is None or saw.why:
        return None
    size = len(saw.blob)
    t_who, t_bad = plumb.paint(saw.theirs, size), plumb.hurt(saw.theirs, size)
    o_pile, t_pile = rack.inorder(saw.mine), rack.inorder(saw.theirs)
    o_from, t_from = [r.start for r in o_pile], [r.start for r in t_pile]
    edge = sorted({v for r in (*o_pile, *t_pile) for v in (r.start, r.end)})
    # The frames `rack` already charges as `unframed`, as a byte mask, so a run
    # can say whether it is that population wearing a different column.
    missing = bytearray(size)
    for lo, hi, _ in rack.unframed(saw, o_pile):
        missing[lo:hi] = b"\1" * (hi - lo)

    runs: list[list] = []
    tally: collections.Counter[str] = collections.Counter()
    for lo, hi, ra, rb in saw.windows:
        mine = rack.within(o_pile, o_from, ra, rb)
        yours = rack.within(t_pile, t_from, ra, rb)
        cuts = sorted({lo, hi, *edge[bisect.bisect_right(edge, lo):
                                     bisect.bisect_left(edge, hi)]})
        o_sp, t_sp = rack.cover(mine, cuts[:-1]), rack.cover(yours, cuts[:-1])
        for k, p in enumerate(cuts[:-1]):
            wide = cuts[k + 1] - p
            them = saw.theirs[t_who[p]] if t_who[p] >= 0 else None
            if (them is None or (not them.leaf and t_bad[p])
                    or (t_bad[p] and them.name.startswith(plumb.HURT))):
                tally["unjudged"] += wide
                continue
            if o_sp[k] == t_sp[k] or t_sp[k] or rack.excused(o_sp[k], t_sp[k], saw.renames):
                continue
            tally["unwindowed"] += wide
            # The frame is the narrowest oracle bracket that opens at or before
            # the window and closes at or after it - the thing that "framed the
            # window from outside" and left nothing inside.
            key = (them.name, o_sp[k][-1].name if o_sp[k] else "—",
                   next((r.name for r in t_pile[:bisect.bisect_right(t_from, ra)]
                         if r.end >= rb), "—"),
                   len(o_sp[k]), bool(missing[p]))
            if runs and runs[-1][1] == p and runs[-1][2] == key:
                runs[-1][1] = p + wide
            else:
                runs.append([p, p + wide, key])
    return {"row": case.name, "size": size, "built": saw.built,
            "windows": len(saw.windows), "runs": runs, **tally}


def one(got: dict) -> None:
    runs = got["runs"]
    print(json.dumps({
        **{k: v for k, v in got.items() if k != "runs"},
        "runs_n": len(runs),
        "widest": sorted((r[1] - r[0] for r in runs), reverse=True)[:12],
        "under_a_frame_we_never_built": sum(r[1] - r[0] for r in runs if r[2][4]),
        "our_deepest": collections.Counter(r[2][1] for r in runs).most_common(8),
        "their_frame": collections.Counter(r[2][2] for r in runs).most_common(8),
        "our_depth_below_the_frame":
            collections.Counter(r[2][3] for r in runs).most_common(6),
    }, indent=1))


def corpus() -> None:
    print(f"{'row':<14}{'built':>9}{'unjudged':>10}{'unwindowed':>12}"
          f"{'of those, under a frame we never built':>40}")
    tot = under = 0
    for case in plumb.slate():
        got = walk(case)
        if got is None or not got.get("unwindowed"):
            continue
        hit = sum(r[1] - r[0] for r in got["runs"] if r[2][4])
        tot, under = tot + got["unwindowed"], under + hit
        print(f"{got['row']:<14}{got['built']:>9,}{got.get('unjudged', 0):>10,}"
              f"{got['unwindowed']:>12,}{hit:>32,}"
              f"{hit / got['unwindowed']:>8.1%}")
    print(f"{'corpus':<14}{'':>9}{'':>10}{tot:>12,}{under:>32,}"
          f"{under / tot if tot else 0:>8.1%}")
    print("\n`unwindowed` reads as the oracle having no verdict. Where the frame is one"
          "\nwe never built, it is `unframed`'s population - and building MORE under a"
          "\nmissing frame is what moves a byte from the charge into the silence.")


if __name__ == "__main__":
    ask = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ask.add_argument("row", nargs="?", help="one grammar in full; default the corpus table")
    want = ask.parse_args().row
    if want is None:
        corpus()
    elif (case := next((c for c in plumb.slate() if c.name == want), None)) is None:
        raise SystemExit(f"{want}: not on the slate")
    elif (got := walk(case)) is None:
        raise SystemExit(f"{want}: refused whole, so it has no windows to walk")
    else:
        one(got)

#!/usr/bin/env python3
"""How much of `rack`'s crooked is a WRONG PARENT, and how much a wrong SPAN.

`rack`'s spine rung is `(name, named, start, end)`, and two rungs that differ in
any of the four part the spines. Three of those four are derivation. The fourth
is not: a parent that adopts the right child and records an extent that stops
short of it is the **same derivation** with a bad number on one node, and every
byte under that node is charged as if the parent were wrong.

toml is the case that makes it visible, and `rack` already knew - it quotes
`standing.py`'s `UNSOUND - child outside its parent` in `cover`'s docstring as
the reason it filters by extent instead of popping a stack, then charges the
bytes anyway. On `v = "1"  #:x` both parsers put `comment` **inside** `pair`;
outliner's `pair` merely ends at the string and tree-sitter's ends after the
comment. Nobody chose a different tree. `rack soft` cannot catch it either,
because the bytes it charges are not the extra's - they are the siblings'.

So this re-runs `rack`'s own survey and re-sorts `askew + racked` into:

    span    every rung agrees on (name, named, start) in order; some rung's
            `end` differs. A right parent measured wrong.
    shape   anything else - a different name, a different nesting, a rung one
            side does not have. A parent genuinely in dispute.

Nothing here changes a `rack` number; it partitions one. Run it beside
`rack show <grammar>` and the two must add up.

The `soft` columns are `rack soft`'s test, not a re-implementation of it, and
that distinction cost this file a wrong number once. `soft` merges adjacent
cuts into RUNS and asks whether a whole run is blank; the first cut of this
file asked per cut, so every space inside a 1,815-byte racked run counted soft
and elixir read 4,879 soft where `rack soft` reads 74. Both numbers used the
same words. So the runs are built here the way `survey` builds them - same key,
plus the span/shape class so a run never straddles one - and the two totals are
addable on purpose.

    python3 research/joinery/tenon/extent.py [grammar...]

Exit 0 measured, 2 could not.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))

import differential as d  # noqa: E402
import plumb  # noqa: E402
import rack  # noqa: E402


def spanwise(ours: tuple[rack.Rung, ...], theirs: tuple[rack.Rung, ...]) -> bool:
    """Same spine, one or more rungs measured differently.

    Deliberately strict about `start` as well as name and order: a parent that
    begins somewhere else has been re-seated, not mis-measured, and only the
    right edge can move by adopting a trailing extra. Requiring the lengths to
    match is what keeps a genuinely missing rung out of this bucket.
    """
    if len(ours) != len(theirs) or ours == theirs:
        return False
    moved = False
    for a, b in zip(ours, theirs):
        if (a.name, a.named, a.start) != (b.name, b.named, b.start):
            return False
        moved = moved or a.end != b.end
    return moved


def resort(saw: plumb.Read, xs: set[str]) -> tuple[dict[str, int], list[tuple[int, int, str, str]]]:
    """The four-way split over the same windows `rack.survey` walks.

    Both questions on one pass, because they are not the same question and
    quoting either alone overstates it. `rack soft` asks whether the bytes are
    an extra's or whitespace; this asks whether the spines name the same
    parents. A byte can be both - toml's `pair` ends early *because* of a
    comment - so the honest report is the intersection, not two totals that
    look like they add up and do not.

    A transcription of `survey`'s loop with one extra question asked at the one
    line that files a byte crooked. Everything above that line - the unjudged
    rule, the window arithmetic, the rename excuse - is `rack`'s, called by
    name, so the two cannot drift apart on anything but the question being
    added. Runs are accumulated on `survey`'s own key with the span/shape class
    appended, because `soft` is a question about a run and not about a byte,
    and asking it per cut is how this file first read elixir 66x too soft.
    """
    import bisect

    size = len(saw.blob)
    t_who, t_bad = plumb.paint(saw.theirs, size), plumb.hurt(saw.theirs, size)
    o_pile, t_pile = rack.inorder(saw.mine), rack.inorder(saw.theirs)
    o_from = [r.start for r in o_pile]
    t_from = [r.start for r in t_pile]
    edge = sorted({v for r in (*o_pile, *t_pile) for v in (r.start, r.end)})

    runs: list[list] = []  # [start, end, key, class, widest-rung note]
    for lo, hi, ra, rb in saw.windows:
        mine = rack.within(o_pile, o_from, ra, rb)
        yours = rack.within(t_pile, t_from, ra, rb)
        cuts = sorted({lo, hi, *edge[bisect.bisect_right(edge, lo):
                                     bisect.bisect_left(edge, hi)]})
        o_sp = rack.cover(mine, cuts[:-1])
        t_sp = rack.cover(yours, cuts[:-1])
        for k, p in enumerate(cuts[:-1]):
            wide = cuts[k + 1] - p
            them = saw.theirs[t_who[p]] if t_who[p] >= 0 else None
            # `rack.survey`'s rule verbatim, and it is one test now: `hurt`
            # is asked of the node covering the byte, so the leaf clause this
            # used to carry was the ancestry rule's and nothing else.
            if them is None or t_bad[p]:
                continue
            if o_sp[k] == t_sp[k] or not t_sp[k]:
                continue
            if rack.excused(o_sp[k], t_sp[k], saw.renames):
                continue
            deep = o_sp[k][-1] if o_sp[k] else None
            at = rack.parts(o_sp[k], t_sp[k])
            a = o_sp[k][at] if at < len(o_sp[k]) else None
            b = t_sp[k][at] if at < len(t_sp[k]) else None
            how = "span" if spanwise(o_sp[k], t_sp[k]) else "shape"
            key = ("racked" if deep == t_sp[k][-1] else "askew", at,
                   a.label() if a else "—", b.label() if b else "—", how)
            note = (f"{a.label()} [{a.start}, {a.end}) vs [{b.start}, {b.end})"
                    if how == "span" and a and b else "")
            if runs and runs[-1][1] == p and runs[-1][2] == key:
                runs[-1][1] = p + wide
            else:
                runs.append([p, p + wide, key, how, note])

    got = dict.fromkeys(("crooked", "span", "shape", "span_soft", "shape_soft"), 0)
    worst: list[tuple[int, int, str, str]] = []
    for start, end, key, how, note in runs:
        wide = end - start
        # `soft`'s two tests, at `soft`'s granularity: the whole run is
        # whitespace, or the run's parting rung is a declared extra.
        text = saw.blob[start:end]
        mild = not text.strip() or (text.strip() and (key[2] in xs or key[3] in xs))
        got["crooked"] += wide
        got[how] += wide
        got[f"{how}_soft"] += wide if mild else 0
        if how == "span" and note:
            worst.append((wide, start, note, ""))
    worst.sort(reverse=True)
    return got, worst[:4]


def main(argv: list[str]) -> int:
    if not d.oracle_ready():
        print(f"extent.py: no tree-sitter CLI at {d.TS}", file=sys.stderr)
        return 2
    want = set(argv)
    picked = [c for c in plumb.slate() if not want or c.name in want]
    if not picked:
        print(f"extent.py: no such grammar on the slate: {' '.join(argv)}", file=sys.stderr)
        return 2
    d.lay_out()
    for case in picked:
        try:
            with d.alone(d.named(case.lang)):
                d.oracle_build(case.lang, case.grammar)
        except (OSError, ValueError):
            pass  # `plumb.read` reports it properly; this only pre-compiles
    print("Of every byte `rack` files crooked, how many are a parent in dispute and\n"
          "how many are the same parent with a different right edge. `soft` is `rack\n"
          "soft`'s test at `rack soft`'s granularity - per run, not per byte - so the\n"
          "two columns can be read beside its own totals.\n")
    print(f"{'grammar':<12}{'crooked':>9}{'span':>8}{'soft':>7}{'shape':>8}{'soft':>7}"
          f"{'DISPUTED':>10}   the widest span run")
    print("-" * 116)
    tot = dict.fromkeys(("crooked", "span", "shape", "span_soft", "shape_soft"), 0)
    for case in picked:
        saw = plumb.read(case, ())
        if saw is None or saw.why:
            print(f"{case.name:<12}{'—':>9}{'—':>8}{'—':>7}{'—':>8}{'—':>7}{'—':>10}   "
                  f"{(saw.why if saw else 'no read')}")
            continue
        try:
            xs = {e["name"] for e in json.loads(case.grammar.read_text()).get("extras", ())
                  if e.get("type") == "SYMBOL"}
        except (OSError, ValueError):
            xs = set()
        seen = rack.survey(case.name, saw)
        got, worst = resort(saw, xs)
        note = ""
        if worst:
            wide, at, who, _ = worst[0]
            note = f"{wide:>4}b at {at} under {who}"
        hard = got["shape"] - got["shape_soft"]
        print(f"{case.name:<12}{seen.crooked:>9}{got['span']:>8}{got['span_soft']:>7}"
              f"{got['shape']:>8}{got['shape_soft']:>7}{hard:>10}   {note}")
        if got["crooked"] != seen.crooked:
            print(f"{'':<12}  DISAGREES WITH rack: {got['crooked']} != {seen.crooked}")
        for k in tot:
            tot[k] += got[k]
    print("-" * 116)
    hard = tot["shape"] - tot["shape_soft"]
    print(f"{'TOTAL':<12}{tot['crooked']:>9}{tot['span']:>8}{tot['span_soft']:>7}"
          f"{tot['shape']:>8}{tot['shape_soft']:>7}{hard:>10}")
    if tot["crooked"]:
        print(f"\n  {tot['span']} of {tot['crooked']} crooked bytes"
              f" ({tot['span'] / tot['crooked']:.1%}) name the same parents in the same\n"
              "  order and differ only in where one of them ends. Those are the ones this\n"
              "  file was built to find, and they are a re-sort of `rack`'s own charge:\n"
              f"  the crooked column above must equal `rack`'s, row for row. {hard} bytes\n"
              f"  ({hard / tot['crooked']:.1%}) are a parent genuinely in dispute on a run that\n"
              "  is neither whitespace nor an extra's - the same test `rack soft` applies,\n"
              "  so subtract this file's soft columns from its own halves and nothing else.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

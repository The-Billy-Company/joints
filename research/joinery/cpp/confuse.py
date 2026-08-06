#!/usr/bin/env python3
"""What is C++ building where tree-sitter builds something else?

Read-only. It touches no parser source and writes nothing outside stdout; it
drives `plumb.read`, which is the same pair of trees `rack.py` judges, so the
population here and the population on the board are one population by
construction rather than by agreement.

Four questions, one walk:

    pairs    every crooked byte grouped by (our label, their label) at the rung
             the two spines first differ - the confusion matrix `rack.py show`
             prints one row of
    roots    our top-level forest beside the oracle's brackets, so a missing
             frame is visible as a frame rather than as a byte count
    recall   labeled-bracket recall recomputed here from the two node sets,
             as a second route to the board's own `recall` column
    where    the same numbers cut at a byte, so "before the wall" and "after
             the wall" are separable

    python3 research/joinery/cpp/confuse.py [grammar ...] [--verb pairs|roots|recall|where]
"""

from __future__ import annotations

import sys
from collections import Counter
from pathlib import Path

TOOL = Path(__file__).resolve().parents[3] / "tool"
sys.path.insert(0, str(TOOL))

import plumb  # noqa: E402
import rack  # noqa: E402


def spines(saw: plumb.Read):
    """Every judged cut as (byte, width, kind, our rung, their rung).

    `rack.survey`'s walk with the tallies removed, so a regrouping here cannot
    drift from the board's classification: `rack.bucket` decides, exactly as it
    does there, and `rack.within` / `rack.cover` / `rack.unframed` supply the
    spines it decides over.
    """
    import bisect

    size = len(saw.blob)
    t_who, t_bad = plumb.paint(saw.theirs, size), plumb.hurt(saw.theirs, size)
    o_pile, t_pile = rack.inorder(saw.mine), rack.inorder(saw.theirs)
    missing = bytearray(size)
    holes = sorted(rack.unframed(saw, o_pile), key=lambda s: s[1] - s[0])
    for lo, hi, _ in holes:
        missing[lo:hi] = b"\1" * (hi - lo)

    def frame(p: int) -> str:
        return next((n for lo, hi, n in holes if lo <= p < hi), "—")

    o_from = [r.start for r in o_pile]
    t_from = [r.start for r in t_pile]
    edge = sorted({v for r in (*o_pile, *t_pile) for v in (r.start, r.end)})
    out = []
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
            # `rack.survey`'s rule verbatim — one test since `hurt` began
            # asking the node covering the byte rather than its ancestry.
            blind = them is None or t_bad[p]
            hole = bool(missing[p])
            kind = rack.bucket(o_sp[k], t_sp[k], saw.renames, blind, hole)
            at = rack.parts(o_sp[k], t_sp[k])
            a = o_sp[k][at].label() if at != -1 and at < len(o_sp[k]) else "—"
            b = t_sp[k][at].label() if at != -1 and at < len(t_sp[k]) else "—"
            if kind == "unframed":
                a, b = "—", frame(p)
            out.append((p, wide, kind, at, a, b))
    return out, holes


def at(blob: bytes, off: int) -> str:
    return f"L{blob[:off].count(chr(10).encode()) + 1}"


def pairs(name: str, saw: plumb.Read) -> None:
    cuts, _ = spines(saw)
    tally: Counter[tuple[str, str, str]] = Counter()
    runs: Counter[tuple[str, str, str]] = Counter()
    for _, wide, kind, _, a, b in cuts:
        if kind in ("square", "renamed", "unjudged", "unwindowed"):
            continue
        tally[kind, a, b] += wide
        runs[kind, a, b] += 1
    charged = sum(tally.values())
    print(f"\n{name}: {charged} charged byte(s) over {len(tally)} distinct confusion(s)")
    print(f"  {'bytes':>6} {'%':>6} {'cuts':>5}  kind      we build -> they build")
    for (kind, a, b), n in tally.most_common(24):
        print(f"  {n:6} {100 * n / charged:5.1f}% {runs[kind, a, b]:5}  {kind:9} {a} -> {b}")


def roots(name: str, saw: plumb.Read) -> None:
    print(f"\n{name}: our top-level forest ({len(saw.windows)} built window(s))")
    for lo, hi, ra, rb in saw.windows:
        who = next((r.name for r in saw.mine if (r.start, r.end) == (ra, rb)), "?")
        print(f"  [{ra:5},{rb:5}) {at(saw.blob, ra):>5}  {who}")
    _, holes = spines(saw)
    print(f"\n{name}: oracle frames we never built ({len(holes)})")
    for lo, hi, who in sorted(holes, key=lambda h: h[0] - h[1]):
        print(f"  [{lo:5},{hi:5}) {at(saw.blob, lo):>5}  {hi - lo:5}B  {who}")


def recall(name: str, saw: plumb.Read) -> None:
    """Two denominators, because the board's and the whole file's differ."""
    ours = {(r.name, r.named, r.start, r.end) for r in saw.mine}
    theirs = {(r.name, r.named, r.start, r.end) for r in saw.theirs}
    both = ours & theirs
    print(f"\n{name}: labeled brackets, WHOLE FILE (no windowing)")
    print(f"  ours {len(ours)} · theirs {len(theirs)} · shared {len(both)}"
          f" · recall {len(both) / max(len(theirs), 1):.4f}"
          f" · precision {len(both) / max(len(ours), 1):.4f}")
    named_o = {r for r in ours if r[1]}
    named_t = {r for r in theirs if r[1]}
    print(f"  named only: ours {len(named_o)} · theirs {len(named_t)}"
          f" · shared {len(named_o & named_t)}"
          f" · recall {len(named_o & named_t) / max(len(named_t), 1):.4f}")
    missed = Counter(r[0] for r in named_t - named_o)
    print("  the oracle's named brackets we do not reproduce, by kind:")
    for who, n in missed.most_common(15):
        print(f"    {n:4}  {who}")


def where(name: str, saw: plumb.Read, cut: int) -> None:
    cuts, _ = spines(saw)
    side = {False: Counter(), True: Counter()}
    for p, wide, kind, _, _, _ in cuts:
        side[p >= cut][kind] += wide
    for after, tag in ((False, f"before {cut}"), (True, f"from {cut}")):
        tot = sum(side[after].values())
        bad = tot - side[after]["square"] - side[after]["renamed"]
        print(f"\n{name}: {tag} — {tot} judged, {bad} charged ({100 * bad / max(tot, 1):.1f}%)")
        for k, n in side[after].most_common():
            print(f"    {k:11} {n:6}")


def price(name: str, saw: plumb.Read) -> None:
    """What the declaration/expression fork is worth, counted on the oracle.

    The fork is offered exactly once per `call_expression` whose callee is a
    bare `identifier` - a `field_expression` or `qualified_identifier` callee
    cannot begin a declarator, so no fork is offered and those calls are right
    today. Counting on **their** tree rather than ours is deliberate: ours does
    not contain the nodes in question, which is the whole complaint.
    """
    kids: dict[tuple[int, int], list[plumb.Node]] = {}
    for i, r in enumerate(saw.theirs):
        for s in saw.theirs[i + 1:]:
            if s.start >= r.end or s.depth <= r.depth:
                break
            if s.depth == r.depth + 1:
                kids.setdefault((r.start, r.end), []).append(s)
    calls = [r for r in saw.theirs if r.name == "call_expression"]
    bare = [r for r in calls
            if (k := kids.get((r.start, r.end))) and k[0].name == "identifier"]
    first = min((r.start for r in bare), default=-1)
    size = len(saw.blob)
    print(f"\n{name}: {len(calls)} call_expression(s), {len(bare)} with a bare-identifier"
          f" callee — the only shape that offers the fork")
    for r in bare:
        print(f"  [{r.start:5},{r.end:5}) {at(saw.blob, r.start):>5}"
              f"  {saw.blob[r.start:r.end][:56].decode('utf8', 'replace')!r}")
    if first >= 0:
        print(f"\n  first fork offered at byte {first} ({at(saw.blob, first)});"
              f" {size - first} of {size} bytes ({100 * (size - first) / size:.0f}%)"
              f" of the file lie at or after it")


def main(argv: list[str]) -> int:
    verb = "pairs"
    if "--verb" in argv:
        i = argv.index("--verb")
        verb = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    cut = 690
    if "--cut" in argv:
        i = argv.index("--cut")
        cut = int(argv[i + 1])
        argv = argv[:i] + argv[i + 2:]
    want = set(argv) or {"cpp"}
    for case in plumb.slate():
        if case.name not in want:
            continue
        saw = plumb.read(case)
        if saw is None or not saw.ok:
            print(f"{case.name}: {saw.why if saw else 'no folio'}")
            continue
        {"pairs": pairs, "roots": roots, "recall": recall, "price": price}.get(
            verb, lambda n, s: where(n, s, cut))(case.name, saw)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

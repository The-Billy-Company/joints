#!/usr/bin/env python3
"""Does the `fell` regression concentrate on supplies with an untellable rival?

The residue-closure lane found clause 3's predicate weaker than the clause: a
supply is the one literal that *said yes*, not provably the only one, whenever
some other candidate's walk gave up rather than answering. It repaired `follows`
to say so, and the runtime now emits an `unsure` line per refusal counting how
many of how many literals were untellable.

That is a rival explanation for the split this lane is adjudicating, and a good
one, so it is tested rather than argued with. This file joins three streams off
ONE traced run per grammar:

  * `unsure (word): N of M literals at ...` - the untellable count at a refusal
  * `supplied: SYM at ANCHOR so state S can read TOK` - the supply that followed
  * the tree's zero-width nodes - whether that supply's ghost ended up INSIDE a
    parent (a fold took it, the omission was real) or as a top-level ROOT (no
    fold ever took it, and `fell`'s unwind published it anyway)

If clause 3's weakness explains the `fell` regression, the unconfirmed supplies
- the ones that become parentless zero-width roots - concentrate on refusals
where a rival was untellable. If the two rates are the same, the untellable
population is orthogonal to the damage and something else is doing the work.

The join is by ORDER, not by position: `unsure` and `supplied` are emitted from
the same `supply` call in that order, so an `unsure` still open when a
`supplied` arrives belongs to it. Position would be wrong - `unsure` carries the
refused token's offset and `supplied` carries the anchor, and they differ.

    eval "$(python3 tool/pin.py arm <name>)"
    python3 research/joinery/felled/untellable.py --mend fell

Exit 0 measured, 2 could not run.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))
sys.path.insert(0, str(ROOT / "research" / "joinery" / "supply"))

import order  # noqa: E402
import plumb  # noqa: E402
from residue import run  # noqa: E402

UNSURE = re.compile(r"^unsure \((\w+)\): (\d+) of (\d+) literals at (\d+) in state (\d+)$")
SUPPLIED = re.compile(r"^supplied: (\S+) at (\d+) so state (\d+) can read (\S+)$")
SPURNED = re.compile(r"^spurned: (\S+) and (\S+) both resume (\S+) at (\d+) in state (\d+)$")
RIVALS = re.compile(r"^rivals: (\d+) of (\d+) literals resume (\S+) at (\d+) in state (\d+)$")


def supplies(case: plumb.Case, how: str) -> tuple[list[dict], int, int]:
    """Every supply of one traced run, each with the untellable count beside it.

    Also the `spurned` total and how many of THOSE carried an `unsure`, which is
    the second question: clause 3 declines when two candidates both say yes, and
    a third that was untellable makes even the decline a claim about a set the
    walk did not establish.
    """
    work = Path(os.environ.get("JOINTS_WORK", ROOT / ".local" / "work"))
    art = order.folio_for(case.name, work) or (order.GRAMMARS / f"{case.name}.json")
    if not Path(art).exists() or not case.source.exists():
        return [], 0, 0
    # The join is the IMMEDIATELY preceding line, and that is exact rather than
    # a heuristic: `unsure` is emitted from `supply` after the candidate loop and
    # `supplied` from the same call a few lines later, with no trace between
    # them. A stale flag carried across other refusals would attribute one
    # refusal's untellable rival to another's supply - and verilog emits 1,139
    # `unsure` lines against 33 supplies, so nearly all of them belong to
    # refusals that supplied nothing.
    out, spurned, prev = [], [], None
    for line in "".join(run(order.BIN, Path(art), case.source, how, True, True)).splitlines():
        haze = UNSURE.match(prev) if prev else None
        if m := SUPPLIED.match(line):
            out.append({"sym": m[1], "at": int(m[2]), "state": int(m[3]),
                        "haze": {"hazes": int(haze[2]), "of": int(haze[3])}
                        if haze and haze[5] == m[3] else None})
        elif m := SPURNED.match(line):
            spurned.append({"at": int(m[4]), "state": int(m[5]), "rivals": 2,
                            "haze": bool(haze) and haze[4] == m[4]})
        elif (m := RIVALS.match(line)) and spurned:
            spurned[-1]["rivals"] = int(m[1])
        prev = line
    return out, spurned


def ghosts(case: plumb.Case, how: str) -> set[int]:
    """Where a supply's ghost ended up: inside a parent, or nowhere.

    Only the parented set is read back. A supply whose anchor is not in it is
    unproven whichever binary answered - on the arm that publishes them it is a
    parentless zero-width root, and on the arm that withholds them it is absent
    from the tree entirely - so one classification reads both.
    """
    saw = plumb.read(case, (f"--mend={how}",))
    if saw is None or saw.why:
        return set()
    return {n.start for n in saw.mine if n.start == n.end and n.depth > 0}


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mend", default="fell", choices=("none", "keep", "fell", "relent"))
    ap.add_argument("--grammar", action="append")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)

    cases = plumb.slate()
    if args.grammar:
        cases = [c for c in cases if c.name in set(args.grammar)]

    print(f"\n  --mend={args.mend}   does the damage sit on the untellable supplies?\n")
    print(f"  {'grammar':<12}{'supplies':>9}{'hazy':>6}    "
          f"{'confirmed':>10}{'hazy':>6}{'rate':>7}    "
          f"{'UNPROVEN':>9}{'hazy':>6}{'rate':>7}    {'spurned':>8}{'hazy':>6}{'>2':>5}")
    body, wide = {}, {"n": 0, "h": 0, "ck": 0, "ch": 0, "uk": 0, "uh": 0, "s": 0, "sh": 0}
    for case in cases:
        got, spurned = supplies(case, args.mend)
        if not got and not spurned:
            continue
        inside = ghosts(case, args.mend)
        ok = [g for g in got if g["at"] in inside]
        bad = [g for g in got if g["at"] not in inside]
        hz = lambda rows: sum(1 for r in rows if r["haze"])  # noqa: E731
        sp_hazy, deep = hz(spurned), sum(1 for s in spurned if s["rivals"] > 2)
        body[case.name] = {"supplies": len(got), "confirmed": len(ok),
                           "unproven": len(bad), "spurned": len(spurned),
                           "hazy": hz(got), "confirmed_hazy": hz(ok),
                           "unproven_hazy": hz(bad), "spurned_hazy": sp_hazy,
                           "spurned_over_two": deep}
        for key, add in (("n", len(got)), ("h", hz(got)), ("ck", len(ok)),
                         ("ch", hz(ok)), ("uk", len(bad)), ("uh", hz(bad)),
                         ("s", len(spurned)), ("sh", sp_hazy), ("s3", deep)):
            wide[key] = wide.get(key, 0) + add
        pc = lambda a, b: f"{100 * a / b:.0f}%" if b else "  -"  # noqa: E731
        print(f"  {case.name:<12}{len(got):>9}{hz(got):>6}    "
              f"{len(ok):>10}{hz(ok):>6}{pc(hz(ok), len(ok)):>7}    "
              f"{len(bad):>9}{hz(bad):>6}{pc(hz(bad), len(bad)):>7}    "
              f"{len(spurned):>8}{sp_hazy:>6}{deep:>5}")
    pc = lambda a, b: f"{100 * a / b:.0f}%" if b else "  -"  # noqa: E731
    print(f"  {'CORPUS':<12}{wide['n']:>9}{wide['h']:>6}    "
          f"{wide['ck']:>10}{wide['ch']:>6}{pc(wide['ch'], wide['ck']):>7}    "
          f"{wide['uk']:>9}{wide['uh']:>6}{pc(wide['uh'], wide['uk']):>7}    "
          f"{wide['s']:>8}{wide['sh']:>6}{wide.get('s3',0):>5}")
    print(f"\n  A supply is UNPROVEN when its ghost is a parentless zero-width root:"
          f"\n  nothing ever folded over it, and `fell`'s unwind published it anyway."
          f"\n  If clause 3's weakness were the mechanism, the two `hazy` rates would part.")
    if args.json:
        print(json.dumps(body, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

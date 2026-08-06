#!/usr/bin/env python3
"""Was the stack a supply stood on founded by the author, or by the last mend?

`../supply/RESULT-1-insert.md` reports the same rule as a pure reclassification
under `--mend=keep` and as +713 crooked under `--mend=fell`. One rule cannot have
two behaviours, so the difference is in the configurations each policy *asks* it
in, and this file measures the one property that separates them.

The supply's third guard is `ground`: it declines at stack depth zero, on the
reasoning that

    a supply repairs an OMISSION, and an omission is only a thing relative to
    something the author began.

That is exactly right and the test does not implement it. Depth is a proxy for
authorship, and it is a sound one under `keep`, where the standing stack is the
derivation the file itself built. Under `fell` it is not: a mend bares the stack
and stands one perch back up in state zero, so the parse is at depth 1 again
after a single shift - and that perch was begun by *the previous mend*, not by
the author. The guard cannot tell the two apart, because depth cannot.

`+N tokens` on a scar line is `s.shifted - shifted`: the real tokens the parse
shifted between the previous scar and this one. So the tokens standing under a
supply since the last recovery event is already in the stream, and this file
reads it rather than instrumenting anything.

    eval "$(python3 tool/pin.py arm <name>)"
    python3 research/joinery/felled/founded.py                  every mending row
    python3 research/joinery/felled/founded.py --mend keep      the other policy
    python3 research/joinery/felled/founded.py --grammar verilog

Exit 0 measured, 2 could not run.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))
sys.path.insert(0, str(ROOT / "research" / "joinery" / "supply"))

import order  # noqa: E402
import plumb  # noqa: E402
from residue import run  # noqa: E402

CUT = re.compile(r"^scar (\d+)\.\.(\d+) (\d+)B (fell|kept) (.*), (\d+) heads, \+(\d+) tokens$")
GAVE = re.compile(r"^scar (\d+) gave (\S+) (.*), (\d+) heads, \+(\d+) tokens$")


def read(case: plumb.Case, how: str, supply: bool = True) -> list[dict] | None:
    """Every scar of one run, in order, each carrying its tokens-since-the-last.

    The compiled folio, not the grammar JSON - `reach.py`'s resolution, so both
    files read the same artefact and a difference between them is a difference
    in the question rather than in what was parsed.
    """
    work = Path(os.environ.get("OUTLINER_WORK", ROOT / ".local" / "work"))
    art = order.folio_for(case.name, work) or (order.GRAMMARS / f"{case.name}.json")
    if not Path(art).exists() or not case.source.exists():
        return None
    out: list[dict] = []
    for line in "".join(run(order.BIN, Path(art), case.source, how, supply, False)).splitlines():
        if m := GAVE.match(line):
            out.append({"kind": "gave", "at": int(m[1]), "sym": m[2],
                        "why": m[3], "since": int(m[5])})
        elif m := CUT.match(line):
            out.append({"kind": m[4], "at": int(m[1]), "over": int(m[2]),
                        "why": m[5], "since": int(m[7])})
    return out


REFUSED = re.compile(r"^unexpected (\S+) in state (\d+)$")


def founding(scars: list[dict]) -> list[dict]:
    """Each supply, with what it stood on and what happened immediately after.

    `stood` is the tokens shifted since the last FELL. A `kept` scar does not
    bare the stack, so it does not re-found it; only a `fell` does. Tokens
    accumulate across intervening supplies and `kept` scars because none of
    those put the stack down.

    `undone` is the second reading and the sharper one: the supply wrote in
    terminal `m`, and the very next scar is a deletion of a refused `m`. The
    file was not missing an `m` - it had one, a token later - so the parse
    did not gain a terminal, it swapped the author's for a ghost one position
    earlier and threw the author's away. `after` is how many real tokens the
    parse shifted in between, so `undone and after == 1` is the tight case.
    """
    out, since, ever = [], None, 0
    for k, s in enumerate(scars):
        ever += s["since"]
        if s["kind"] == "fell":
            since = ever
            continue
        if s["kind"] != "gave":
            continue
        nxt = scars[k + 1] if k + 1 < len(scars) else None
        hit = REFUSED.match(nxt["why"]) if nxt and nxt["kind"] != "gave" else None
        out.append(s | {"stood": ever if since is None else ever - since,
                        "undone": bool(hit) and hit[1] == s["sym"],
                        "after": nxt["since"] if nxt else -1})
    return out


def render(rows: dict[str, list[dict]], how: str, stamp: str) -> None:
    print(f"\n  tree {stamp}   --mend={how}\n")
    print(f"  {'grammar':<14}{'supplies':>9}{'ground':>7}{'<=2 tok':>8}{'<=8 tok':>8}"
          f"{'median':>7}    {'undone':>7}{'next tok':>9}")
    wide = Counter()
    for name, got in sorted(rows.items()):
        if not got:
            continue
        stood = sorted(g["stood"] for g in got)
        near = [sum(1 for s in stood if s <= n) for n in (0, 2, 8)]
        gone = [g for g in got if g["undone"]]
        tight = sum(1 for g in gone if g["after"] <= 1)
        for key, add in (("n", len(stood)), ("g", near[0]), ("2", near[1]),
                         ("8", near[2]), ("u", len(gone)), ("t", tight)):
            wide[key] += add
        print(f"  {name:<14}{len(stood):>9}{near[0]:>7}{near[1]:>8}{near[2]:>8}"
              f"{stood[len(stood) // 2]:>7}    {len(gone):>7}{tight:>9}")
    if not wide["n"]:
        return
    print(f"  {'CORPUS':<14}{wide['n']:>9}{wide['g']:>7}{wide['2']:>8}{wide['8']:>8}"
          f"{'':>7}    {wide['u']:>7}{wide['t']:>9}")
    print(f"\n  {wide['8']} of {wide['n']} supplies "
          f"({100 * wide['8'] / wide['n']:.0f}%) stand on eight tokens or fewer "
          f"since the last fell — the stack was founded by a mend, not by the author."
          f"\n  {wide['u']} of {wide['n']} ({100 * wide['u'] / wide['n']:.0f}%) are "
          f"UNDONE: the terminal written in is the terminal the next deletion refuses."
          f"\n  {wide['t']} of those cost the parse the author's own copy one token later.")


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mend", default="fell", choices=("none", "keep", "fell", "relent"))
    ap.add_argument("--grammar", action="append")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)

    cases = plumb.slate()
    if args.grammar:
        want = set(args.grammar)
        cases = [c for c in cases if c.name in want]
        if not cases:
            print("no such grammar", file=sys.stderr)
            return 2

    head = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                          capture_output=True, text=True).stdout.strip()
    rows = {c.name: founding(read(c, args.mend) or []) for c in cases}
    if args.json:
        print(json.dumps({"tree": head, "mend": args.mend, "rows": rows}, indent=1))
    else:
        render(rows, args.mend, head)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

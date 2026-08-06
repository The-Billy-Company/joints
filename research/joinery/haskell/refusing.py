#!/usr/bin/env python3
"""Which *external* is standing in the way of each `none` refusal?

`../supply/residue.py` split the 1,289 unsupplied refusals into 960 honest
misses (`none`) and 329 spent walks (`forked`), and named the mechanism behind
the first: the refused terminal is an external-scanner terminal with no
anonymous literal that could stand for it. It does not say **which** external,
and it cannot, because the trace prints the refused token and the refused token
is usually an innocent bystander. On haskell's first wall the trace reads
`unexpected . at 681 in state 7` — but `.` is not the problem, `_cond_qual_dot`
is: state 7 shifts two externals and both are blind, so the byte `.` is a token
this press cannot make in a state that wanted one.

This file joins the three channels that together name the obstruction:

  the trace     `stood down (none): TERM at N in state S` — where, and why
  the scars     `scar A..B nB fell …`                     — how many bytes
  the table     `outliner state <g> S`                    — what S would accept

and reports, per blind external, how many refusals stood in a state that
admits it. That is an *attribution*, not a proof of causation, so it is
reported in four buckets rather than one number:

  sole    the state shifts exactly one blind external. Unambiguous: nothing
          else in that row is unlexable, so that terminal is the wall
  shared  the state shifts two or more. The wall is the *set*; per-external
          counts below are `implicated`, and they double-count on purpose
  ahead   no blind external is shiftable, but one is in the lookahead set. A
          weaker claim: the state would only have folded on it
  clear   the state admits no blind external at all — by shift or lookahead

**`clear` is the falsifier and it is why this file exists.** If the inherited
story is right, a `none` refusal is an external with no literal, and `clear`
should be small. A large `clear` means the residue is not what the last lane
said it was, and this instrument would rather report that than confirm a brief.
The lane that produced this one did not trust its own zeros; this one does not
trust its own totals, so the bucket that can contradict it is printed first.

  python3 research/joinery/haskell/refusing.py                # haskell
  python3 research/joinery/haskell/refusing.py --all --brief   # the twelve
  python3 research/joinery/haskell/refusing.py --json out.json
  python3 research/joinery/haskell/refusing.py --selftest      # can it say `clear`?

Exit 0 measured, 2 an error.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import NamedTuple

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))

import order  # noqa: E402
import plumb  # noqa: E402
import specimen  # noqa: E402
import stamp  # noqa: E402

STOOD = re.compile(r"^stood down \((\w+)\): (\S+) at (\d+) in state (\d+)$")
SCAR = re.compile(r"^scar (\d+)\.\.(\d+) (\d+)B \w+ (.*)$")
HEAD = re.compile(r"^row — (shifts|lookahead):")
# A terminal row under a `row —` header. Anonymous terminals print quoted or as
# a bare regex; externals are always named, so the name form is all we read.
TERM = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s{2,}")
TALLY = re.compile(r"^shift \d+, lookahead \d+")
TWELVE = ("c", "cpp", "ruby", "bash", "haskell", "julia", "kotlin",
          "markdown", "ocaml", "scala", "swift", "zig")


class Wall(NamedTuple):
    """One refusal, with the bytes it cost and the row it stood in."""

    why: str
    term: str        # the terminal the trace named — often a bystander
    at: int
    state: int
    bytes: int       # from the scar at the same offset, 0 when none matched


class Row(NamedTuple):
    grammar: str
    declared: int
    blind: list[str]
    walls: list[Wall]
    admits: dict[int, tuple[frozenset[str], frozenset[str]]]  # state -> shift, ahead

    def bucket(self, w: Wall) -> tuple[str, frozenset[str]]:
        """Which of the four this refusal falls in, and the externals named."""
        gone = set(self.blind)
        shift, ahead = self.admits.get(w.state, (frozenset(), frozenset()))
        hit = frozenset(shift & gone)
        if len(hit) == 1:
            return "sole", hit
        if len(hit) > 1:
            return "shared", hit
        late = frozenset(ahead & gone)
        return ("ahead", late) if late else ("clear", frozenset())


# ------------------------------------------------------------------ channels


def parse(binary: Path, art: Path, src: Path, mend: str) -> tuple[str, str]:
    env = dict(os.environ) | {"OUTLINER_TRACE": "quire"}
    got = subprocess.run(
        [str(binary), "parse", str(art), str(src), "--scars", f"--mend={mend}"],
        capture_output=True, text=True, timeout=stamp.PATIENCE, cwd=ROOT, env=env)
    return got.stdout, got.stderr


def walls(out: str, err: str) -> list[Wall]:
    """Every refusal, joined to the scar that cut for it.

    Keyed on the offset, which is the only key the two channels share. A scar
    the trace never explained keeps its bytes out of the total rather than
    being attributed to the nearest wall — an attribution nobody measured.
    """
    cost: dict[int, int] = {}
    for line in out.splitlines():
        if m := SCAR.match(line.strip()):
            cost[int(m[1])] = cost.get(int(m[1]), 0) + int(m[3])
    seen = []
    for line in err.splitlines():
        if m := STOOD.match(line.strip()):
            at = int(m[3])
            seen.append(Wall(m[1], m[2], at, int(m[4]), cost.get(at, 0)))
    return seen


def admitted(binary: Path, art: Path, state: int) -> tuple[frozenset[str], frozenset[str]]:
    """The named terminals one state shifts, and the ones it only folds on.

    Reads the grammar **JSON**, not the folio the parse ran on: `outliner
    state` imports a grammar and refuses a compiled folio with
    `MalformedGrammar`. The first draft of this file passed the folio, got
    nothing back on every state, and reported all 936 refusals `clear` — a
    perfectly-shaped falsification of its own brief, produced entirely by a
    silent exit 2. Hence the tally line: `outliner state` closes with
    `shift N, lookahead M`, and a run that never printed one did not answer.
    """
    got = subprocess.run([str(binary), "state", str(art), str(state)],
                         capture_output=True, text=True, timeout=stamp.PATIENCE,
                         cwd=ROOT)
    half, shift, ahead, told = "", set(), set(), False
    for line in got.stdout.splitlines():
        line = line.strip()
        if m := HEAD.match(line):
            half = m[1]
        elif TALLY.match(line):
            half, told = "", True
        elif half and (m := TERM.match(line)):
            (shift if half == "shifts" else ahead).add(m[1])
    if not told:
        raise SystemExit(f"refusing: `state {art} {state}` did not answer "
                         f"(exit {got.returncode}): {got.stderr.strip()[:200]}")
    return frozenset(shift), frozenset(ahead)


def row(case: plumb.Case, work: Path, binary: Path, mend: str) -> Row | None:
    art = order.folio_for(case.name, work) or (order.GRAMMARS / f"{case.name}.json")
    if not Path(art).exists() or not case.source.exists():
        return None
    reach = specimen.reach(case.name, with_specimens=False)
    if not reach.declared:
        return None
    out, err = parse(binary, Path(art), case.source, mend)
    seen = walls(out, err)
    # The table is read off the grammar, the parse off the folio built from it.
    admits = {s: admitted(binary, case.grammar, s) for s in {w.state for w in seen}}
    return Row(case.name, len(reach.declared), reach.blind, seen, admits)


# ------------------------------------------------------------------- reports


def census(r: Row, why: str) -> tuple[Counter, dict[str, Counter]]:
    """The four buckets, and per-external sole / implicated / bytes."""
    pot = Counter()
    per: dict[str, Counter] = defaultdict(Counter)
    for w in r.walls:
        if w.why != why:
            continue
        kind, named = r.bucket(w)
        pot[kind] += 1
        pot[f"{kind}B"] += w.bytes
        for n in named:
            per[n]["implicated"] += 1
            per[n]["bytes"] += w.bytes
            if kind == "sole":
                per[n]["sole"] += 1
            elif kind == "ahead":
                per[n]["ahead"] += 1
            per[n][f"state:{w.state}"] += 1
    return pot, per


def render(r: Row, why: str, brief: bool) -> None:
    pot, per = census(r, why)
    n = sum(pot[k] for k in ("sole", "shared", "ahead", "clear"))
    if not n:
        print(f"{r.grammar:<10} no `{why}` refusals")
        return
    print(f"\n{r.grammar} — {n:,} `{why}` refusal(s), "
          f"{len(r.blind)} of {r.declared} externals blind\n")
    print(f"  {'bucket':<10}{'refusals':>10}{'bytes':>10}   what it means")
    for k, sense in (
            ("clear", "no blind external admitted — NOT an external wall"),
            ("sole", "exactly one blind external shiftable here"),
            ("shared", "two or more shiftable; the wall is the set"),
            ("ahead", "blind only in the lookahead set — weaker claim")):
        print(f"  {k:<10}{pot[k]:>10,}{pot[k + 'B']:>10,}   {sense}")
    if brief:
        return
    print(f"\n  {'external':<28}{'sole':>7}{'impl':>7}{'ahead':>7}{'bytes':>8}"
          f"{'states':>8}")
    order_ = sorted(per.items(), key=lambda kv: (-kv[1]["sole"], -kv[1]["implicated"]))
    for name, c in order_:
        states = sum(1 for k in c if k.startswith("state:"))
        print(f"  {name:<28}{c['sole']:>7,}{c['implicated']:>7,}"
              f"{c['ahead']:>7,}{c['bytes']:>8,}{states:>8,}")
    never = [b for b in r.blind if b not in per]
    if never:
        print(f"\n  {len(never)} blind external(s) implicated in no refusal at all: "
              f"{' '.join(sorted(never))}")


def selftest() -> int:
    """Prove `clear` can fire, without a binary or a corpus.

    A bucket that only ever reports the answer the brief predicted is not a
    measurement. Three fabricated rows: one state that shifts a blind external
    (sole), one that shifts two (shared), one that admits none (clear). If the
    third does not read `clear`, this file cannot contradict its own brief and
    every number above it is decoration.
    """
    r = Row("fake", 3, ["_a", "_b"], [
        Wall("none", ".", 0, 1, 1),
        Wall("none", ".", 1, 2, 1),
        Wall("none", ".", 2, 3, 1),
        Wall("none", ".", 3, 4, 1),
    ], {
        1: (frozenset({"_a", "x"}), frozenset()),
        2: (frozenset({"_a", "_b"}), frozenset()),
        3: (frozenset({"x"}), frozenset({"_b"})),
        4: (frozenset({"x"}), frozenset({"y"})),
    })
    want = {"sole": 1, "shared": 1, "ahead": 1, "clear": 1}
    pot, per = census(r, "none")
    bad = [k for k, v in want.items() if pot[k] != v]
    for k, v in want.items():
        print(f"{'ok ' if pot[k] == v else 'BAD'} {k}: {pot[k]}, want {v}")
    # And the per-external join has to double-count `shared` rather than
    # picking a winner, or the column silently invents a cause.
    ok = per["_a"]["implicated"] == 2 and per["_a"]["sole"] == 1
    print(f"{'ok ' if ok else 'BAD'} shared is implicated for both, sole for neither")
    bad += [] if ok else ["join"]
    if bad:
        print(f"refusing: {len(bad)} self-test(s) failed", file=sys.stderr)
    return 1 if bad else 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mend", default="fell", choices=("keep", "fell", "relent"))
    ap.add_argument("--why", default="none", help="which trace reason to census")
    ap.add_argument("--all", action="store_true", help="the twelve, not just haskell")
    ap.add_argument("--brief", action="store_true", help="buckets only")
    ap.add_argument("--json", type=Path)
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()

    work = Path(os.environ.get("OUTLINER_WORK", ROOT / ".local" / "work"))
    pick = TWELVE if args.all else ("haskell",)
    rows = [r for c in plumb.slate() if c.name in pick
            if (r := row(c, work, order.BIN, args.mend))]
    if not rows:
        print("refusing: nothing to read", file=sys.stderr)
        return 2
    print(f"--mend={args.mend}  --why={args.why}")
    for r in rows:
        render(r, args.why, args.brief)
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps({r.grammar: {
            "declared": r.declared, "blind": r.blind,
            "buckets": dict(census(r, args.why)[0]),
            "per": {k: dict(v) for k, v in census(r, args.why)[1].items()},
        } for r in rows}, indent=1))
    print()
    print(stamp.line() if hasattr(stamp, "line") else "", end="")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

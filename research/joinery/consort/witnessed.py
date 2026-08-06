#!/usr/bin/env python3
"""A board arm that reads zero has not said the row does nothing. Ask a second tier.

`vacuity`'s fourteen single-row arms and five pair arms all read the **corpus
board**: one fixture per grammar, scored on `damage`. A row whose construct is
not in that grammar's fixture reads zero in every arm of that family - single,
pair, or the union of all fourteen - and there is no arm in the family that can
tell that apart from a row which does nothing. `multiline_comment/.marrow/
.swift_block` is the standing proof: `Chunked.swift` contains no `/*` at all, so
the row was priced at 0, 0 and 0 and then written up as *"a seated row that
changes nothing in any combination available to it"*.

The specimen tier is a combination available to it. It was green the whole time.

So this is the join nobody ran: for each seated row, take the specimen tier
against the row's own isolation arm and against the control, and report which
specimens **flip**. A specimen that passes with the row in and fails with it out
is a falsifier the row is answering, and it does not care whether the corpus
mentions the construct.

  python3 research/joinery/consort/witnessed.py            all fourteen
  python3 research/joinery/consort/witnessed.py 3 11       just these rows

Three outcomes per row:

  witnessed    a specimen flips - the row is doing something a falsifier can see
  corpus-only  no specimen flips, but the board arm moved - the corpus is the
               only witness, so nothing here covers the constructs it lacks
  unwitnessed  neither moves. THIS is the shape that earns a deletion argument,
               and it is not the shape swift's row was in.

Reads the retained pins under `.local/aud-iso/`; builds nothing.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PINS = ROOT / ".local/aud-iso/outliner/.local/pin"
WORK = ROOT / ".local/consort-work"
VACUITY = ROOT / "research/joinery/vacuity"

VERDICT = re.compile(r"^(ok|FAIL)\s+(\S+)", re.M)


def seated() -> list[tuple[int, str, str]]:
    """The fourteen rows as (index, seat, grammar), from the ablation tool itself.

    Parsed off `ablate.py guests` rather than re-derived, so a row this lane
    numbers differently from the lane that priced it cannot happen.
    """
    got = subprocess.run([sys.executable, VACUITY / "ablate.py", "guests"],
                         capture_output=True, text=True, cwd=ROOT)
    out = []
    for line in got.stdout.splitlines():
        m = re.match(r"\s*(\d+)\s+(\S+)\s+\d+ terminal\(s\)\s+(\w+)", line)
        if m:
            out.append((int(m[1]), m[2], m[3]))
    return out


def sound(arm: str, grammar: str) -> dict[str, bool]:
    """Which of a grammar's specimens are sound under one arm."""
    binary = PINS / arm / "bin/outliner"
    if not binary.exists():
        return {}
    env = os.environ | {"OUTLINER_BIN": str(binary), "OUTLINER_WORK": str(WORK / arm)}
    got = subprocess.run([sys.executable, "tool/specimen.py", "run", "--grammar", grammar],
                         capture_output=True, text=True, cwd=ROOT, env=env, timeout=600)
    return {name: verdict == "ok" for verdict, name in VERDICT.findall(got.stdout)}


def moved(row: int, grammar: str) -> int | None:
    """What the single-row board arm said this row was worth, from the retained ledger.

    `arms.json` carries `moved[grammar]["damage"] = [arm, all in]`, and the
    worth is the arm's damage less the control's - the same subtraction
    `RESULT-2-arms.md` prints, read rather than recomputed.
    """
    path = VACUITY / "arms.json"
    if not path.exists():
        return None
    for arm in json.loads(path.read_text()):
        if arm.get("row") == row:
            got = (arm.get("moved") or {}).get(grammar, {}).get("damage")
            return got[0] - got[1] if got and len(got) == 2 else None
    return None


def main(argv: list[str]) -> int:
    rows = seated()
    if not rows:
        print("witnessed: ablate.py guests said nothing", file=sys.stderr)
        return 2
    want = {int(a) for a in argv} if argv else {i for i, *_ in rows}
    control: dict[str, dict[str, bool]] = {}

    print(f"{'row':>3}  {'seat':<46}{'grammar':<9}{'board':>8}  specimens that flip")
    tally = {"witnessed": 0, "corpus-only": 0, "unwitnessed": 0, "no arm": 0}
    for i, seat, grammar in rows:
        if i not in want:
            continue
        if not (PINS / f"aud-r{i}" / "bin/outliner").exists():
            print(f"{i:>3}  {seat[:45]:<46}{grammar:<9}{'—':>8}  no retained pin")
            tally["no arm"] += 1
            continue
        base = control.setdefault(grammar, sound("aud-base", grammar))
        arm = sound(f"aud-r{i}", grammar)
        flipped = sorted(n for n, ok in base.items() if ok and not arm.get(n, True))
        board = moved(i, grammar)
        verdict = ("witnessed" if flipped else
                   "corpus-only" if board else "unwitnessed")
        tally[verdict] += 1
        note = ", ".join(Path(n).name for n in flipped) if flipped else f"none — {verdict}"
        print(f"{i:>3}  {seat[:45]:<46}{grammar:<9}"
              f"{(board if board is not None else '—'):>8}  {note}")

    print("\n  " + " · ".join(f"{v} {k}" for k, v in tally.items() if v))
    print("  `corpus-only` is not a clearance and `unwitnessed` is not a deletion:\n"
          "  a specimen only exists where somebody wrote one, so both are floors.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

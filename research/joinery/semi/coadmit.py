#!/usr/bin/env python3
"""What else is legal where a semicolon is - the co-admission census.

**Superseded by `population.py`; kept only as the record of a wrong answer.**
This counts *shiftable* rivals, which is the narrower of the two populations an
`outliner state` row holds - the row also lists reduce lookaheads, and it is the
union of the two that a scanner reads as `valid_symbols`. So its 20 states for
`_implicit_semi` answer a question a stand-in does not face; the number that
governs is 1712. `RESULT-2-seated.md` cites this file for that error. Run
`population.py`, which reports both and labels them.

The haskell lane licensed its late-answering layout protocol by measuring that
`_cmd_*` was the only shiftable terminal in 51 of 56 states admitting one. A
hand that answers only after the slate came up empty is sound exactly when the
slate would have come up empty anyway; if a rival terminal shares the state, a
late hand never fires and an early one has to be right about which reading asked.

So the same question has to be asked before designing anything for
`_implicit_semi`. This walks every LR state, reads its row out of
`outliner state`, and for each state that admits a named terminal reports how
many *other* terminals are shiftable there - split by whether the rival is one
this lexer can actually see (a spelled terminal) or another blind external.

That split is the load-bearing one. A state whose only rivals are themselves
blind is a state where the slate produces nothing, so a hand answering there
competes with silence.

  python3 coadmit.py <grammar.json> <terminal> [terminal...]
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BIN = ROOT / "zig-out" / "bin" / "outliner"

# `read on`/`read off` is a shift, `fold` is a reduction, `halt` is accept. Only
# a shift competes for bytes, so only a shift is a rival.
ROW = re.compile(r"^\s{4}(\S+(?:\s\S+)*?)\s{2,}(read|fold|halt|refuse)\b")
COUNT = re.compile(r"lr\(0\) states\s+(\d+)")


def states(grammar: Path) -> int:
    out = subprocess.run(
        [BIN, "grammar", str(grammar)], capture_output=True, text=True
    ).stdout
    m = COUNT.search(out)
    if not m:
        sys.exit("coadmit: could not read the state count")
    return int(m.group(1))


def blind(grammar: Path) -> set[str]:
    """Terminals no slate row and no hand answers, read from the binary rather
    than from the grammar's `externals` - the two differ by every provision."""
    out = subprocess.run(
        [BIN, "grammar", str(grammar)], capture_output=True, text=True
    ).stdout
    names: set[str] = set()
    for line in out.splitlines():
        if "cannot be lexed here:" in line:
            names |= set(line.split("cannot be lexed here:")[1].split())
    names.discard("more")
    return {n for n in names if not n.startswith("+")}


def row(grammar: Path, n: int) -> tuple[list[str], list[str]]:
    """(shiftable, folding) terminal names for one state."""
    out = subprocess.run(
        [BIN, "state", str(grammar), str(n)], capture_output=True, text=True
    ).stdout
    shift: list[str] = []
    fold: list[str] = []
    inrow = False
    for line in out.splitlines():
        if line.strip() == "row:":
            inrow = True
            continue
        if inrow:
            m = ROW.match(line)
            if not m:
                if line.strip() and not line.startswith("    "):
                    break
                continue
            name, kind = m.group(1).strip(), m.group(2)
            (shift if kind == "read" else fold).append(name)
    return shift, fold


def main() -> int:
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    grammar = Path(sys.argv[1])
    wanted = sys.argv[2:]
    dark = blind(grammar)
    total = states(grammar)
    tally = {w: Counter() for w in wanted}
    seen = {w: 0 for w in wanted}
    alone_sighted = {w: 0 for w in wanted}
    examples: dict[str, list] = {w: [] for w in wanted}

    for n in range(total):
        shift, fold = row(grammar, n)
        if not shift:
            continue
        s = set(shift)
        for w in wanted:
            if w not in s:
                continue
            seen[w] += 1
            rivals = s - {w}
            sighted = {r for r in rivals if r not in dark}
            tally[w][len(rivals)] += 1
            if not sighted:
                alone_sighted[w] += 1
            if len(examples[w]) < 6:
                examples[w].append((n, sorted(rivals), sorted(sighted), fold))

    out = {"grammar": grammar.stem, "states": total, "blind": sorted(dark), "term": {}}
    for w in wanted:
        print(f"=== {w}: admitted in {seen[w]} of {total} states")
        if not seen[w]:
            continue
        print(f"    rivals (any):       {dict(sorted(tally[w].items()))}")
        print(
            f"    no SIGHTED rival:   {alone_sighted[w]} of {seen[w]} "
            f"({alone_sighted[w] / seen[w]:.1%}) - the slate produces nothing here"
        )
        for n, rivals, sighted, fold in examples[w]:
            print(f"      state {n}: rivals={rivals} sighted={sighted} folds={len(fold)}")
        out["term"][w] = {
            "states": seen[w],
            "rivals": {str(k): v for k, v in sorted(tally[w].items())},
            "alone_sighted": alone_sighted[w],
        }
    Path(sys.argv[0]).with_suffix(".json").write_text(json.dumps(out, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

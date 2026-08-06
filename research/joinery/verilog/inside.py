#!/usr/bin/env python3
"""Inside the procedural half: which statement form is the grammar missing?

`procedural.py` split `picorv32` by construct class and the two halves could
hardly disagree more:

    declarations only     14,836B    90.3% standing      24 mends      46 leaves
    procedural blocks     54,368B    15.5% standing   1,400 mends   1,544 leaves

79% of the module is procedural, and that is where 1,400 of its 1,506 mends and
all but 46 of its bare leaves live. So the module's 49,446 bytes of damage are
not a wall at a place, they are a class of statement the grammar does not have.

This narrows inside that class. Each arm blanks one statement form out of the
procedural-only body, length-preserved, and the two negative controls blank
things that appear at the same density but are not statements. An arm that
moves `built` by thousands names the missing rule; an arm that moves it by tens
is another `_import_dot` - a terminal the verdict points at that is worth
nothing.

`describes` and bare `leaves` ride every row. On this file they have to: a
`built` that rises while `describes` falls is `--mend=keep`'s 25,457-byte
describing-less trap, and `covered` will happily call a byte read when the only
thing standing over it is a bare token.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))
import standing  # noqa: E402
from modules import blocks  # noqa: E402
from named import WALLS  # noqa: E402
from order import folio_for  # noqa: E402
from procedural import hollow, procedurals, score  # noqa: E402
from stamp import take  # noqa: E402

BIN = Path(os.environ["OUTLINER_BIN"])
SRC = ROOT / "upstream" / "sources" / "picorv32.v"


def blank(m: re.Match) -> str:
    return "".join(" " if c != "\n" else "\n" for c in m.group(0))


def comment(m: re.Match) -> str:
    return "//" + " " * (len(m.group(0)) - 2)


def ident(m: re.Match) -> str:
    return "Z" + "z" * (len(m.group(0)) - 1)


ARMS: dict[str, object] = {
    "base (procedural only)": lambda s: s,
    "- case/casez arms": lambda s: re.sub(
        r"(?ms)^([ \t]*)(case|casez|casex)\b.*?^\1end(case)\b", blank, s),
    "- nonblocking `<=`": lambda s: re.sub(r"(?m)^.*<=.*$", comment, s),
    "- macro uses (`word)": lambda s: re.sub(r"`\w+", ident, s),
    "- system tasks ($x(..))": lambda s: re.sub(r"\$\w+", ident, s),
    "- if/else headers": lambda s: re.sub(r"(?m)^[ \t]*(if|else)\b.*$", comment, s),
    "control: comments": lambda s: re.sub(r"(?m)//[^\n]*", blank, s),
    "control: rename idents": lambda s: re.sub(
        r"\b(mem_|cpu|reg_|instr_|decoded_)\w+", ident, s),
}

if __name__ == "__main__":
    text = WALLS["A+B+C"](SRC.read_text())
    lo, hi = next((a, b) for n, a, b in blocks(text) if n == "picorv32")
    alone = hollow(hollow(text, hi, len(text)), 0, lo)
    proc = procedurals(alone, lo, hi)
    keep = [(lo, proc[0][0])] + [(proc[i][1], proc[i + 1][0])
                                 for i in range(len(proc) - 1)] + [(proc[-1][1], hi)]
    only = alone
    for a, b in reversed(keep):
        only = hollow(only, a, b)
    live = sum(b - a for a, b in proc)

    print(f"procedural blocks of picorv32: {live:,} bytes in {len(proc)} blocks\n")
    print(f"{'arm':<28}{'built':>9}{'d built':>10}{'stands':>8}{'describes':>11}"
          f"{'d desc':>9}{'leaves':>8}{'mends':>7}  wall")
    first = None
    for tag, fn in ARMS.items():
        arm = fn(only)
        assert len(arm) == len(only), f"{tag}: {len(arm)} != {len(only)}"
        built, nodes, leaves, end = score(arm, (lo, hi))
        first = first or (built, nodes)
        print(f"{tag:<28}{built:>9,}{built - first[0]:>+10,}"
              f"{100.0 * built / live:>7.1f}%{nodes:>11,}{nodes - first[1]:>+9,}"
              f"{leaves:>8}{end.mends:>7}  {end.verdict[:32]}")
    print(take(BIN).line())

#!/usr/bin/env python3
"""Is `picorv32`'s wall a line in its body, or its own header?

`core.py` walked the main module for 61 rounds and `built` went **down** every
single one: -1,508 bytes, and rounds 4-47 marched one line at a time through a
run of forty-four `wire [31:0] dbg_reg_xN = cpuregs[N];` declarations, each
round losing exactly that line's bytes. A stop that moves to the next line when
you delete the line it named, and costs you the deleted bytes, is not a wall -
it is the parser resynchronising at the next statement boundary. Every one of
those 61 names is `joints parse`'s failure *location*, and none is its
diagnosis.

Which puts the defect upstream of all of them. The module's body is being
recovered into, statement by statement, rather than entered. The two things
between byte 0 of the module and its first statement are its **parameter port
list** - 27 `parameter [31:0] NAME = value` rows inside `#( … )` - and its
**port list**, 100-odd `input`/`output reg [n:0] name` rows inside `( … );`.

Each is blanked here on its own, length-preserved, with the module's `#`/parens
kept so the header still closes. The negative control blanks the same number of
bytes from the *body* instead: if removing 1,038 bytes of parameter list moves
`built` and removing 1,038 bytes of declarations does not, the header is the
wall and the byte count is not doing the work.
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
from stamp import outcome, take  # noqa: E402

BIN = Path(os.environ["JOINTS_BIN"])
NAME = "verilog"
SRC = ROOT / "upstream" / "sources" / "picorv32.v"


def hollow(s: str, a: int, b: int) -> str:
    """Blank [a,b) to spaces, keeping newlines so line numbers still line up."""
    return s[:a] + "".join(" " if c != "\n" else "\n" for c in s[a:b]) + s[b:]


def spans(text: str, lo: int) -> tuple[tuple[int, int], tuple[int, int]]:
    """The insides of `#( … )` and of the `( … );` that follows it."""
    h = text.index("#(", lo) + 2
    d, i = 1, h
    while d:
        d += (text[i] == "(") - (text[i] == ")")
        i += 1
    p = text.index("(", i) + 1
    d, j = 1, p
    while d:
        d += (text[j] == "(") - (text[j] == ")")
        j += 1
    return (h, i - 1), (p, j - 1)


def score(body: str, span: tuple[int, int]):
    lo, hi = span
    src = Path(tempfile.mkdtemp(prefix="v-head-")) / SRC.name
    src.write_text(body)
    got = subprocess.run([str(BIN), "parse", str(folio_for(NAME, standing.WORK)),
                          str(src), "--ranges", "--all"],
                         capture_output=True, text=True, timeout=900)
    end = outcome(got.stderr, src, len(body), got.stdout)
    seen = standing.rows(got.stdout)
    top = standing.tops(seen)
    kept = [(max(a, hi and lo), min(b, hi)) for _, a, b, kid in top if kid]
    inside = [r for r in top if r[1] < hi and r[2] > lo]
    return (standing.union([(a, b) for a, b in kept if a < b]), len(seen),
            sum(1 for *_, kid in inside if not kid), end)


if __name__ == "__main__":
    text = WALLS["A+B+C"](SRC.read_text())
    lo, hi = next((a, b) for n, a, b in blocks(text) if n == "picorv32")
    body = hollow(hollow(text, hi, len(text)), 0, lo)   # this module alone
    (pa, pb), (qa, qb) = spans(body, lo)
    par, port = pb - pa, qb - qa

    # The control blanks `par` bytes of ordinary declarations from the body,
    # taken from the same run of lines the climb walked.
    run = [m.span() for m in re.finditer(r"(?m)^\t(wire|reg) .*$", body[lo:hi])]
    got, cut = 0, body
    for a, b in run:
        if got >= par:
            break
        cut, got = hollow(cut, lo + a, lo + b), got + (b - a)

    arms = {
        "module alone (base)": body,
        f"- parameter list ({par:,}B)": hollow(body, pa, pb),
        f"- port list ({port:,}B)": hollow(body, qa, qb),
        "- both": hollow(hollow(body, pa, pb), qa, qb),
        f"control: -{got:,}B of decls": cut,
    }
    print(f"picorv32: {hi - lo:,} bytes · parameter list {par:,}B"
          f" · port list {port:,}B · A+B+C applied\n")
    print(f"{'arm':<30}{'built':>9}{'d built':>10}{'describes':>11}{'d desc':>9}"
          f"{'leaves':>8}{'stands':>8}{'mends':>7}  wall")
    first = None
    for tag, arm in arms.items():
        assert len(arm) == len(text)
        built, nodes, leaves, end = score(arm, (lo, hi))
        first = first or (built, nodes)
        print(f"{tag:<30}{built:>9,}{built - first[0]:>+10,}{nodes:>11,}"
              f"{nodes - first[1]:>+9,}{leaves:>8}"
              f"{100.0 * built / (hi - lo):>7.1f}%{end.mends:>7}  {end.verdict[:34]}")
    print(take(BIN).line())

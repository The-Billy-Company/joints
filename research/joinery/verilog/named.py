#!/usr/bin/env python3
"""The three walls `modules.py` found, priced one at a time and together.

`modules.py` split picorv32.v into its eight `module`/`endmodule` blocks and
parsed each alone. Three stand whole; five wall, on **three distinct
constructs** between them:

  A  a `` `ifdef `` between two port declarations, inside a module port list.
     `unexpected ` in state 3438` - picorv32, picorv32_axi, picorv32_wb.
  B  the second `$signed(` in `a <= $signed(x) * $signed(y);`.
     `unexpected ( in state 3761` - picorv32_pcpi_fast_mul.
  C  `&&` in front of a unary reduction operator: `… && |pcpi_rs2)`.
     `unexpected && in state 701` - picorv32_pcpi_div.

Each ablation below neutralises exactly one of them, length-preserved, and the
row is scored per module so a byte credited here is a byte inside the module
that actually changed. The last block re-runs the isolated-module split under
each ablation, which is where the impossibility argument lives: a 6,223-byte
module that walls at 54.2% and reads **whole** once one construct is blanked is
not a module with a long tail of problems.

The negative control from `ablate.py` rides along: blanking all 3,934 bytes of
comment leaves `built` at 30,720 to the byte.
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
from order import folio_for  # noqa: E402
from stamp import outcome, take  # noqa: E402

BIN = Path(os.environ["OUTLINER_BIN"])
NAME = "verilog"
SRC = ROOT / "upstream" / "sources" / "picorv32.v"


def comment_out(m: re.Match) -> str:
    return "//" + " " * (len(m.group(0)) - 2)


def blank(m: re.Match) -> str:
    return " " * len(m.group(0))


def unsign(m: re.Match) -> str:
    """`$signed(` -> a same-length ordinary parenthesised group."""
    return " " * (len(m.group(0)) - 1) + "("


def unreduce(m: re.Match) -> str:
    """`&& |x` -> `&&  x`: the reduction operator gone, the operand kept."""
    return m.group(0).replace("|", " ", 1)


WALLS: dict[str, object] = {
    "baseline": lambda s: s,
    "A `ifdef in port list": lambda s: re.sub(
        r"(?m)^[ \t]*`(ifdef|ifndef|else|elsif|endif)\b.*$", comment_out, s),
    "B $signed( )": lambda s: re.sub(r"\$signed\(", unsign, s),
    "C && before |unary": lambda s: re.sub(r"&&\s*\|", unreduce, s),
    "A+B+C": lambda s: re.sub(
        r"&&\s*\|", unreduce, re.sub(r"\$signed\(", unsign, re.sub(
            r"(?m)^[ \t]*`(ifdef|ifndef|else|elsif|endif)\b.*$", comment_out, s))),
    "control: comments": lambda s: re.sub(
        r"/\*.*?\*/", blank, re.sub(r"(?m)//[^\n]*", blank, s), flags=re.S),
}


def read(text: str, span: tuple[int, int]) -> tuple[int, int, int, object]:
    lo, hi = span
    src = Path(tempfile.mkdtemp(prefix="v-named-")) / SRC.name
    src.write_text(text)
    got = subprocess.run([str(BIN), "parse", str(folio_for(NAME, standing.WORK)),
                          str(src), "--ranges", "--all"],
                         capture_output=True, text=True, timeout=900)
    end = outcome(got.stderr, src, len(text), got.stdout)
    seen = standing.rows(got.stdout)
    top = standing.tops(seen)
    kept = [(max(a, lo), min(b, hi)) for _, a, b, kid in top if kid]
    return standing.union([(a, b) for a, b in kept if a < b]), len(seen), len(top), end


if __name__ == "__main__":
    text = SRC.read_text()
    found = blocks(text)
    size = len(text)
    print(f"{SRC.name}: {size:,} bytes\n")
    print(f"{'ablation':<24}{'built':>9}{'damage':>9}{'d built':>10}"
          f"{'describes':>11}{'d desc':>9}{'stands':>9}  residual wall")
    base = None
    for tag, fn in WALLS.items():
        body = fn(text)
        assert len(body) == size, f"{tag}: {len(body)} != {size}"
        built, nodes, _, end = read(body, (0, size))
        base = base or (built, nodes)
        print(f"{tag:<24}{built:>9,}{size - built:>9,}{built - base[0]:>+10,}"
              f"{nodes:>11,}{nodes - base[1]:>+9,}{100.0 * built / size:>8.1f}%"
              f"  {end.verdict[:34]}")

    print(f"\nPer module, isolated, under each ablation — `stands` is `built` "
          f"clipped to the module's own bytes.\n")
    print(f"{'module':<24}{'bytes':>7}" + "".join(f"{t.split()[0]:>9}" for t in WALLS))
    for name, a, b in found:
        cells = []
        for _, fn in WALLS.items():
            body = fn(text)
            only = " " * a + body[a:b] + " " * (size - b)
            built, _, _, end = read(only, (a, b))
            cells.append(f"{100.0 * built / (b - a):>8.1f}%")
        print(f"{name:<24}{b - a:>7,}" + "".join(cells))
    print(take(BIN).line())

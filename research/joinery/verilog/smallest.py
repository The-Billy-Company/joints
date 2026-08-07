#!/usr/bin/env python3
"""The smallest module that fails, authored rather than shrunk.

`witness.py` lifts real statements out of `picorv32` and clusters them by the
wall they name. It answers *how many* distinct defects there are. It cannot
answer *what each one is*, because its members are 300-byte statements and its
automatic shrink is not trustworthy at the last few tokens: deleting one
identifier turned `alu_lts <= $signed(a) < $signed(b);` into
`alu_lts <= $signed < $signed(b);`, which still named state 3761 and is a
different defect wearing the same number.

So the last mile is authored. Each row below is a construct written from
nothing, paired with the **control** - the nearest spelling that differs by one
thing and parses. A row is only evidence when both halves land: the witness
fails and the control stands. A witness that fails next to a control that also
fails is measuring the frame, and a witness that fails next to nothing is a
verdict, which is the thing this whole lane exists to stop reporting.

`reach.py` then says which owner each belongs to - a **gap** the grammar cannot
derive at all, or a **conflict** it can derive and the press could not resolve.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / "tool"))

import standing  # noqa: E402
from order import folio_for  # noqa: E402
from stamp import outcome  # noqa: E402

BIN = Path(os.environ.get("JOINTS_BIN", ROOT / "zig-out" / "bin" / "joints"))

DECLS = "reg [31:0] a, b, x, y, c [0:3];\ninteger i;\nreg eq, lt;\n"
IN_PROC = "module m;\n" + DECLS + "always @* begin\n%s\nend\nendmodule\n"
IN_MOD = "module m;\n" + DECLS + "%s\nendmodule\n"

# (id, what it is, frame, witness, control, owner)
CASES: tuple[tuple[str, str, str, str, str, str], ...] = (
    ("W1", "macro invoked as a statement", IN_PROC,
     "`assert(a);", "x = `WIDTH;", "gap"),
    ("W2", "`ifdef between two statements", IN_PROC,
     "`ifdef T\nx = 1;\n`endif\ny = 2;", "x = 1;\ny = 2;", "gap"),
    ("W3", "`ifdef between two port declarations", "module m (\n%s\n);\nendmodule\n",
     "input a,\n`ifdef T\noutput b,\n`endif\ninput c", "input a,\noutput b,\ninput c", "gap"),
    ("W4", "`ifdef between two module items", IN_MOD,
     "`ifdef T\nwire w;\n`endif", "wire w;", "gap"),
    ("W5", "$signed on both sides of a binary operator", IN_PROC,
     "lt = $signed(a) < $signed(b);", "lt = $signed(a) < b;", "conflict"),
    ("W6", "$signed on both sides of *", IN_PROC,
     "x = $signed(a) * $signed(b);", "x = $signed(a) * b;", "conflict"),
    ("W7", "indexed lvalue under a blocking assignment", IN_PROC,
     "c[i] = 0;", "x = 0;", "conflict"),
    ("W8", "indexed lvalue in a for body", IN_PROC,
     "for (i = 0; i < 4; i = i+1) c[i] = 0;", "for (i = 0; i < 4; i = i+1) x = 0;", "conflict"),
    ("W9", "a select inside a concatenation", IN_PROC,
     "x = {a[3], b};", "x = a[3];", "conflict"),
    ("W10", "an attribute instance before case", IN_PROC,
     "(* full_case *) case (1'b1)\neq: x = 1;\ndefault: x = 0;\nendcase",
     "case (1'b1)\neq: x = 1;\ndefault: x = 0;\nendcase", "conflict"),
    ("W11", "a reduction operator as the right operand of &&", IN_PROC,
     "x = eq && |b;", "x = eq && b;", "conflict"),
    ("W12", "unary minus as a ternary arm", IN_PROC,
     "x = eq ? -a : a;", "x = eq ? a : a;", "conflict"),
    ("W13", "a string literal as a ternary arm", IN_PROC,
     'x = eq ? "Y" : "N";', "x = eq ? a : b;", "conflict"),
    ("W14", "$display with a format string", IN_PROC,
     '$display("D: 0x%08x %-0s", a, b);', "$display(a);", "conflict"),
    ("W15", "a sized binary literal compared to a select", IN_PROC,
     "eq = a[6:0] == 7'b0110111;", "eq = a[6:0] == b;", "conflict"),
    ("W16", "a concatenation of a sized zero and a select", IN_PROC,
     "x = {16'b0, a[15:0]};", "x = {b, a};", "conflict"),
    ("W17", "a shift by a literal", IN_PROC,
     "x = 1 << 31;", "x = a << b;", "conflict"),
)

WALL = re.compile(r"unexpected (.+?) at \d+ in state (\d+)")


def run(text: str, folio: str) -> tuple[bool, str]:
    tmp = ROOT / ".local" / "witness" / f"s-{os.getpid()}.v"
    tmp.parent.mkdir(parents=True, exist_ok=True)
    tmp.write_text(text)
    g = subprocess.run([str(BIN), "parse", folio, str(tmp), "--quiet"],
                       capture_output=True, text=True, timeout=120)
    out = outcome(g.stderr, tmp, len(text.encode()))
    if out.kind == "whole":
        return True, "stands"
    m = WALL.search(out.verdict)
    return False, f"{m[1]} in {m[2]}" if m else out.verdict[:30]


def main() -> int:
    folio = str(folio_for("verilog", standing.WORK))
    print(f"{'':<5}{'construct':<44}{'witness':<24}{'control':<12}{'reads'}")
    print("-" * 104)
    real, mute, broken = [], [], []
    for cid, what, frame, witness, control, owner in CASES:
        w_ok, w_says = run(frame % witness, folio)
        c_ok, c_says = run(frame % control, folio)
        if not w_ok and c_ok:
            verdict, bucket = owner.upper(), real
        elif w_ok and c_ok:
            verdict, bucket = "-  both stand", mute
        else:
            verdict, bucket = "!  CONTROL FAILS TOO", broken
        bucket.append(cid)
        print(f"{cid:<5}{what:<44}{w_says:<24}{c_says:<12}{verdict}")
    print()
    print(f"{len(real)} constructs fail beside a control that stands: {', '.join(real)}")
    print(f"{len(mute)} parse fine - the sweep is not calling everything a defect: "
          f"{', '.join(mute) or '(none)'}")
    if broken:
        print(f"{len(broken)} have a control that also fails and prove NOTHING: "
              f"{', '.join(broken)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

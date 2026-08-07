#!/usr/bin/env python3
"""The wall, in one line of verilog, and what it costs picorv32.v.

`inside.py` could not find a statement form whose removal *helped* - every arm
went down or nowhere, because ablating a construct that partly parses removes
the bytes it was contributing. So the last step went the other way: build the
smallest module that fails, from nothing.

    module m; initial begin x    = 0; end endmodule     accepted, 1 root
    module m; initial begin c[i] = 0; end endmodule     press? on = in state 2394
    module m; initial begin c[i] <= 0; end endmodule    accepted, 1 root

That is the whole wall. A **blocking** assignment whose left-hand side is
indexed. Scalar blocking is fine; indexed nonblocking is fine; indexed blocking
is not. The same stop appears under `if`, `while`, `repeat`, `for` and `always`
and under none of them without the indexed lvalue - so the `for (i = 0; …)` the
verdict pointed at for two hours is a location, not a diagnosis, exactly as the
house warns. `inquest` reads the cell as merge-damaged: *"a merge damaged this
terminal's cell elsewhere"*, on the same state 2394 the board's biggest file
stops in.

This prices it. `=` -> `<=` on an indexed lvalue is one byte moved and none
added, so the ablation is length-preserving to the byte and every other token
in the file is untouched; the negative control does the same rewrite on
**scalar** lvalues, which the grammar already accepts, and must therefore move
nothing. `describes` and bare `leaves` are on every row: this is the file where
`--mend=keep` buys 25,457 bytes while printing 9,550 fewer nodes, and a `built`
that rises alone is not a win.
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
from order import folio_for  # noqa: E402
from stamp import outcome, take  # noqa: E402

BIN = Path(os.environ["JOINTS_BIN"])
NAME = "verilog"
SRC = ROOT / "upstream" / "sources" / "picorv32.v"

# `name[…] = ` at statement position: an indexed lvalue, blocking. The `[^=<>!+]`
# in front keeps `==`, `<=`, `!=`, `+=` out, and the `(?m)^[ \t]*` keeps it to
# statements rather than the inside of an expression.
INDEXED = re.compile(r"(?m)^([ \t]*\w+(?:\.\w+)*\s*\[[^\];]*\])(\s*)= ")
SCALAR = re.compile(r"(?m)^([ \t]*\w+(?:\.\w+)*)(\s*)= ")


def to_nb(m: re.Match) -> str:
    """`lhs = ` -> `lhs<= `: one byte moved left, total length unchanged."""
    return f"{m[1]}{m[2][:-1] if m[2] else ''}<= "


ARMS: dict[str, object] = {
    "baseline": lambda s: s,
    "indexed lvalue = -> <=": lambda s: INDEXED.sub(to_nb, s),
    "control: scalar = -> <=": lambda s: SCALAR.sub(to_nb, s),
}


def score(body: str):
    src = Path(tempfile.mkdtemp(prefix="v-lval-")) / SRC.name
    src.write_text(body)
    got = subprocess.run([str(BIN), "parse", str(folio_for(NAME, standing.WORK)),
                          str(src), "--ranges", "--all"],
                         capture_output=True, text=True, timeout=900)
    end = outcome(got.stderr, src, len(body), got.stdout)
    seen = standing.rows(got.stdout)
    top = standing.tops(seen)
    stands = [(a, b) for _, a, b, kid in top if kid]
    built = standing.union(stands)
    under = standing.union([(a, b) for _, a, b, _ in top])
    return (built, under - built, len(seen),
            sum(1 for *_, kid in top if not kid), end)


if __name__ == "__main__":
    text = SRC.read_text()
    size = len(text)
    n_i, n_s = len(INDEXED.findall(text)), len(SCALAR.findall(text))
    print(f"{SRC.name}: {size:,} bytes · {n_i} indexed blocking assignments"
          f" · {n_s} scalar ones\n")
    print(f"{'arm':<26}{'built':>9}{'damage':>9}{'d built':>10}{'rubble':>8}"
          f"{'describes':>11}{'d desc':>9}{'leaves':>8}{'mends':>7}  wall")
    first = None
    for tag, fn in ARMS.items():
        arm = fn(text)
        assert len(arm) == size, f"{tag}: {len(arm)} != {size}"
        built, rub, nodes, leaves, end = score(arm)
        first = first or (built, nodes)
        print(f"{tag:<26}{built:>9,}{size - built:>9,}{built - first[0]:>+10,}"
              f"{rub:>8,}{nodes:>11,}{nodes - first[1]:>+9,}{leaves:>8}"
              f"{end.mends:>7}  {end.verdict[:30]}")
    print(take(BIN).line())

#!/usr/bin/env python3
"""Parse each of picorv32.v's modules on its own, and see which ones stand.

The warm climb (`climb.py`) says the file has no single blocking wall: 120
rounds of blanking the line the wall names moves `built` by **-1,253 bytes**,
and a new line is named every round with no sign of saturation. That rules out
"one loud defect" but it does not say what the alternative is, because a warm
climb cannot distinguish *every construct walls* from *one early wall poisons
every construct after it*.

Splitting the file does. `picorv32.v` is eight top-level `module`/`endmodule`
blocks; each is legal verilog on its own, and each starts a fresh parse in state
0 with no accumulated damage. If the small modules stand and only the big one
falls, the damage is contextual and bounded. If every module falls at the same
rate, the damage is per-construct and the file size is incidental.

Each module is written out **length-preserved in place** - everything outside it
blanked to spaces - so a byte offset means the same thing here as on the board
and the residual wall can be compared to the whole-file one directly.
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

BIN = Path(os.environ["OUTLINER_BIN"])
NAME = "verilog"
SRC = ROOT / "upstream" / "sources" / "picorv32.v"
HEAD = re.compile(r"(?m)^module\s+(\w+)")
TAIL = re.compile(r"(?m)^endmodule")


def blocks(text: str) -> list[tuple[str, int, int]]:
    out = []
    for m in HEAD.finditer(text):
        end = TAIL.search(text, m.end())
        if end:
            out.append((m[1], m.start(), end.end()))
    return out


def score(text: str, tag: str, span: tuple[int, int]) -> None:
    """One module's row. `built` is **clipped to the module's own bytes**.

    Not clipping it printed `picorv32_regs 6790.4% standing`, because a whole
    parse of a 343-byte module padded to 94,657 hands back one root spanning
    the padding too and `union` counts every blank byte as built. The absurd
    percentage is the only reason the bug was visible in the first place - the
    three modules that mend scored 54-73% and looked perfectly reportable.
    """
    lo, hi = span
    src = Path(tempfile.mkdtemp(prefix="v-mod-")) / SRC.name
    src.write_text(text)
    got = subprocess.run([str(BIN), "parse", str(folio_for(NAME, standing.WORK)),
                          str(src), "--ranges", "--all"],
                         capture_output=True, text=True, timeout=900)
    end = outcome(got.stderr, src, len(text), got.stdout)
    seen = standing.rows(got.stdout)
    top = standing.tops(seen)
    stands = [(max(a, lo), min(b, hi)) for _, a, b, kid in top if kid]
    built = standing.union([(a, b) for a, b in stands if a < b])
    inside = [r for r in top if r[1] < hi and r[2] > lo]
    print(f"{tag:<26}{hi - lo:>8,}{built:>9,}{100.0 * built / (hi - lo):>8.1f}%"
          f"{end.mends:>7}{len(seen):>9,}{len(inside):>7}"
          f"{sum(1 for *_, kid in inside if not kid):>8}  {end.verdict[:40]}")


if __name__ == "__main__":
    text = SRC.read_text()
    found = blocks(text)
    print(f"{SRC.name}: {len(text):,} bytes, {len(found)} module(s)\n")
    print(f"{'module':<26}{'bytes':>8}{'built':>9}{'stands':>9}{'mends':>7}"
          f"{'describes':>9}{'roots':>7}{'leaves':>8}  first wall")
    score(text, "(whole file)", (0, len(text)))
    for name, a, b in found:
        only = " " * a + text[a:b] + " " * (len(text) - b)
        assert len(only) == len(text)
        score(only, name, (a, b))
    print("\nSame eight modules read out of the WHOLE-file parse, for the"
          " context each one loses when it is read alone:")
    for name, a, b in found:
        score(text, f"  in situ: {name}", (a, b))
    print(take(BIN).line())

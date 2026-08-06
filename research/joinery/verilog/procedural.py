#!/usr/bin/env python3
"""`picorv32` is not walled at a line. Is it walled at a *kind* of line?

Two readings are already dead. `core.py` killed "one bad line": 61 rounds of
blanking the line the stop named moved `built` **down** 1,508 bytes and never
once up. `header.py` killed "the module header": deleting the entire 1,045-byte
parameter port list *and* the entire 1,927-byte port list moves `built` by
**exactly 0** and leaves the stop on the identical byte - while a control that
blanks 1,051 bytes of ordinary declarations costs 1,019 built. So `built` is
sensitive to body bytes and blind to header bytes, and the header is innocent.

What is left is the third reading: the module is not walled at a place at all,
it is walled at a *construct class* that recurs everywhere. 1,506 mends over
69,204 bytes is one mend every 46 bytes - roughly every line and a half of a
2,000-line module - which is what a missing rule looks like from the outside,
and nothing like what one wall looks like.

`picorv32` is, structurally, declarations plus a dozen large procedural blocks
(`always @(posedge clk) begin … end`, `initial begin … end`, `task … endtask`).
Each arm below blanks one of those classes whole, length-preserved. If the
declarations-only module reads near 100% while the procedural-only module reads
near 0%, the wall is named: **procedural statements**, and the cost of removing
it is a grammar rule, not a patch. If both read badly, it is neither and the
damage is genuinely diffuse.
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

BIN = Path(os.environ["OUTLINER_BIN"])
NAME = "verilog"
SRC = ROOT / "upstream" / "sources" / "picorv32.v"

WORD = re.compile(r"\b\w+\b")
OPEN = {"begin", "case", "casez", "casex", "function", "task", "fork", "generate"}
SHUT = {"end", "endcase", "endcase", "endfunction", "endtask", "join", "endgenerate"}
SHUTS = {"begin": "end", "case": "endcase", "casez": "endcase", "casex": "endcase",
         "function": "endfunction", "task": "endtask", "fork": "join",
         "generate": "endgenerate"}
# `[ \t]*`, never `\s*`: with `re.M` a `\s*` lets `^` match at an earlier blank
# line and eat the newlines, so `m.start()` lands on the *previous* line and
# every block's reported first line prints empty. The spans were right and the
# labels were blank, which is the quieter half of the same bug.
HEAD = re.compile(r"(?m)^[ \t]*(always|always_ff|always_comb|initial|task|function)\b")


def hollow(s: str, a: int, b: int) -> str:
    return s[:a] + "".join(" " if c != "\n" else "\n" for c in s[a:b]) + s[b:]


def procedurals(text: str, lo: int, hi: int) -> list[tuple[int, int]]:
    """Each top-level `always`/`initial`/`task`/`function` block, whole."""
    out: list[tuple[int, int]] = []
    for m in HEAD.finditer(text, lo, hi):
        if out and m.start() < out[-1][1]:
            continue
        stack: list[str] = []
        i = m.end()
        while i < hi:
            w = WORD.search(text, i, hi)
            if not w:
                break
            t, i = w.group(0), w.end()
            if t in OPEN:
                stack.append(SHUTS[t])
            elif stack and t == stack[-1]:
                stack.pop()
                if not stack:
                    break
            elif not stack and t == ";":
                break
        else:
            continue
        # `always @(…) x <= y;` with no `begin` ends at the first `;`.
        end = i if stack or "begin" in text[m.end():i] else text.index(";", m.end()) + 1
        out.append((m.start(), min(end, hi)))
    return out


def score(body: str, span: tuple[int, int]):
    lo, hi = span
    src = Path(tempfile.mkdtemp(prefix="v-proc-")) / SRC.name
    src.write_text(body)
    got = subprocess.run([str(BIN), "parse", str(folio_for(NAME, standing.WORK)),
                          str(src), "--ranges", "--all"],
                         capture_output=True, text=True, timeout=900)
    end = outcome(got.stderr, src, len(body), got.stdout)
    seen = standing.rows(got.stdout)
    top = standing.tops(seen)
    kept = [(max(a, lo), min(b, hi)) for _, a, b, kid in top if kid]
    inside = [r for r in top if r[1] < hi and r[2] > lo]
    return (standing.union([(a, b) for a, b in kept if a < b]), len(seen),
            sum(1 for *_, kid in inside if not kid), end)


if __name__ == "__main__":
    text = WALLS["A+B+C"](SRC.read_text())
    lo, hi = next((a, b) for n, a, b in blocks(text) if n == "picorv32")
    alone = hollow(hollow(text, hi, len(text)), 0, lo)
    proc = procedurals(alone, lo, hi)
    pbytes = sum(b - a for a, b in proc)

    no_proc = alone
    for a, b in reversed(proc):
        no_proc = hollow(no_proc, a, b)
    only_proc = alone
    keep = [(lo, proc[0][0])] + [(proc[i][1], proc[i + 1][0])
                                 for i in range(len(proc) - 1)] + [(proc[-1][1], hi)]
    for a, b in reversed(keep):
        only_proc = hollow(only_proc, a, b)

    print(f"picorv32: {hi - lo:,} bytes · {len(proc)} procedural blocks totalling"
          f" {pbytes:,}B ({100.0 * pbytes / (hi - lo):.0f}%) · A+B+C applied\n")
    print(f"{'arm':<32}{'its bytes':>10}{'built':>9}{'stands':>8}{'describes':>11}"
          f"{'leaves':>8}{'mends':>7}  wall")
    for tag, arm, own in (("whole module", alone, hi - lo),
                          ("- procedural blocks", no_proc, hi - lo - pbytes),
                          ("procedural blocks only", only_proc, pbytes)):
        built, nodes, leaves, end = score(arm, (lo, hi))
        print(f"{tag:<32}{own:>10,}{built:>9,}{100.0 * built / own:>7.1f}%"
              f"{nodes:>11,}{leaves:>8}{end.mends:>7}  {end.verdict[:34]}")
    print(take(BIN).line())

#!/usr/bin/env python3
"""What stands between `picorv32` - the module, not the file - and a whole parse.

`named.py` retires the file's cheap damage: two constructs (a `` `ifdef `` inside
a port list, and `$signed(` in the right operand of `*`) take three modules from
walled to **100.0%** and buy the whole file +11,529 bytes with +5,192 describes.
What they do **not** touch is the main module, which moves 28.6% -> 29.2% and
carries 49,446 of the file's 63,937 bytes of damage - 77% of it.

So the file's remaining question is one module's. This walks it: apply A+B, then
blank the line the wall names, remeasure, repeat. Each round is one construct
the parser cannot pass. The reading is in the *shape* of the curve, not its
end - a handful of rounds that then saturate means a short list of named walls;
a hundred rounds each naming a fresh line means the grammar is missing a rule
the module leans on everywhere, and blanking is chasing a moving stop.

`describes` rides every row, because a rising `built` with a falling `describes`
is the trap this file is famous for: `--mend=keep` buys 25,457 bytes here while
printing 9,550 fewer nodes.
"""
from __future__ import annotations

import json
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

KINDS: tuple[tuple[str, str], ...] = (
    ("conditional compilation", r"^\s*`(ifdef|ifndef|else|elsif|endif)\b"),
    ("macro directive", r"^\s*`\w+"),
    ("macro use", r"`\w+"),
    ("attribute", r"\(\*"),
    ("port declaration", r"^\s*(input|output|inout)\b"),
    ("declaration", r"^\s*(reg|wire|integer|localparam|parameter|genvar|real)\b"),
    ("always/initial", r"^\s*(always|initial)\b"),
    ("task/function", r"^\s*(task|function|endtask|endfunction)\b"),
    ("generate", r"^\s*(generate|endgenerate)\b"),
    ("case arm", r"^\s*(case|casez|casex|endcase)\b|^\s*[^:;]+:\s*(begin)?\s*$"),
    ("for/if header", r"^\s*(for|if|else|while|repeat)\b"),
    ("nonblocking assign", r"<="),
    ("blocking assign", r"[^=<>!]=[^=]"),
    ("block keyword", r"^\s*(begin|end|endmodule|module)\b"),
)


def classify(line: str) -> str:
    return next((k for k, pat in KINDS if re.search(pat, line)), "other")


def line_at(text: str, byte: int) -> tuple[int, int]:
    a = text.rfind("\n", 0, byte) + 1
    b = text.find("\n", byte)
    return a, len(text) if b < 0 else b


def score(body: str, span: tuple[int, int]):
    lo, hi = span
    src = Path(tempfile.mkdtemp(prefix="v-core-")) / SRC.name
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


def main(argv: list[str]) -> int:
    rounds = int(argv[0]) if argv else 60
    text = SRC.read_text()
    lo, hi = next((a, b) for n, a, b in blocks(text) if n == "picorv32")
    body = list(WALLS["A+B+C"](text))
    for i in range(len(text)):          # everything but this module, blanked
        if not lo <= i < hi:
            body[i] = " " if body[i] != "\n" else "\n"

    print(f"picorv32 alone: bytes {lo:,}..{hi:,} = {hi - lo:,}, A+B+C applied\n")
    print(f"{'#':>3}{'built':>9}{'d':>8}{'describes':>11}{'leaves':>8}"
          f"{'stands':>8}{'mends':>7}  {'line':>6}  construct / wall")
    log, seen_lines, first = [], set(), None
    for turn in range(rounds + 1):
        text_now = "".join(body)
        built, nodes, leaves, end = score(text_now, (lo, hi))
        first = first if first is not None else built
        row = (f"{turn:>3}{built:>9,}{built - first:>+8,}{nodes:>11,}{leaves:>8}"
               f"{100.0 * built / (hi - lo):>7.1f}%{end.mends:>7}")
        if end.kind != "mended" and end.at is None:
            print(f"{row}         -  WHOLE: {end.verdict[:40]}")
            break
        at = end.at or 0
        a, b = line_at(text_now, at)
        line = text_now[a:b]
        what = classify(line)
        n = text_now.count("\n", 0, a) + 1
        print(f"{row}  {n:>6}  {what:<24} {line.strip()[:44]}")
        log.append({"turn": turn, "built": built, "describes": nodes,
                    "leaves": leaves, "mends": end.mends, "line": n,
                    "kind": what, "verdict": end.verdict})
        if (a, b) in seen_lines or not lo <= a < hi:
            print("     stuck: the wall names a line already blanked (or outside"
                  " the module) - the stop cannot be walked past by blanking.")
            break
        seen_lines.add((a, b))
        body[a:b] = list("//" + " " * (b - a - 2)) if b - a >= 2 else list(" " * (b - a))

    by: dict[str, int] = {}
    for r in log:
        by[r["kind"]] = by.get(r["kind"], 0) + 1
    print(f"\n{len(log)} rounds · {len(by)} distinct construct classes · "
          f"built {first:,} -> {log[-1]['built'] if log else first:,}")
    for k, v in sorted(by.items(), key=lambda kv: -kv[1]):
        print(f"    {v:>4}  {k}")
    Path(__file__).with_name("core.json").write_text(json.dumps(log, indent=1))
    print(take(BIN).line())
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

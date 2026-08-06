#!/usr/bin/env python3
"""Where the main module's 49,446 bytes actually sit - measured, not ablated.

`lvalue.py` ended a two-hour chase with a **near-miss**: the wall it isolated is
real and reproduces in one line (`c[i] = 0;` inside a procedural block fails
where `x = 0;` and `c[i] <= 0;` both parse), and `picorv32.v` contains **eight**
of them. Neutralising all eight moves `built` by **-167 bytes**. A perfect
diagnosis worth nothing, which is the `_import_dot` shape the house warns about
and the reason a verdict is not a work order.

Every ablation in `inside.py` had the same failure mode in reverse: blanking a
construct that *partly* parses removes the bytes it was contributing, so a
grammar gap and a productive construct both read as a negative delta and the
instrument cannot tell them apart.

So this stops ablating. One parse of the real file, unmodified, and `built`
clipped to each top-level procedural block's own span. No filler, no rewrite,
no control needed - the number is a partition of the file's own bytes and the
columns sum to the board's own row. Blocks are sorted by damage, because
`damage = size - built` is the only ranking that counts `orphan`, and a lane
that ranked by `unbound` put Kotlin 8th while it carried the 3rd-largest.
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))
import standing  # noqa: E402
from modules import blocks as modules_of  # noqa: E402
from order import folio_for  # noqa: E402
from procedural import procedurals  # noqa: E402
from stamp import outcome, take  # noqa: E402

BIN = Path(os.environ["OUTLINER_BIN"])
NAME = "verilog"
SRC = ROOT / "upstream" / "sources" / "picorv32.v"


def clip(spans: list[tuple[int, int]], lo: int, hi: int) -> int:
    return standing.union([(max(a, lo), min(b, hi)) for a, b in spans
                           if max(a, lo) < min(b, hi)])


if __name__ == "__main__":
    text = SRC.read_text()
    lo, hi = next((a, b) for n, a, b in modules_of(text) if n == "picorv32")
    got = subprocess.run([str(BIN), "parse", str(folio_for(NAME, standing.WORK)),
                          str(SRC), "--ranges", "--all"],
                         capture_output=True, text=True, timeout=900)
    end = outcome(got.stderr, SRC, len(text), got.stdout)
    seen = standing.rows(got.stdout)
    top = standing.tops(seen)
    stands = [(a, b) for _, a, b, kid in top if kid]
    leaf = [(a, b) for _, a, b, kid in top if not kid]

    proc = procedurals(text, lo, hi)
    print(f"picorv32 in situ: bytes {lo:,}..{hi:,} = {hi - lo:,}, "
          f"built {clip(stands, lo, hi):,}, damage {hi - lo - clip(stands, lo, hi):,}")
    print(f"{len(proc)} top-level procedural blocks · file verdict: {end.verdict[:40]}\n")
    print(f"{'block (first line)':<46}{'bytes':>8}{'built':>8}{'damage':>8}"
          f"{'stands':>8}{'leafB':>7}  kind")
    rows = []
    for a, b in proc:
        head = text[a:text.find("\n", a)].strip()[:44]
        n, built = b - a, clip(stands, a, b)
        rows.append((n - built, head, n, built, clip(leaf, a, b)))
    covered = 0
    for dmg, head, n, built, bare in sorted(rows, reverse=True):
        covered += dmg
        print(f"{head:<46}{n:>8,}{built:>8,}{dmg:>8,}"
              f"{100.0 * built / n:>7.1f}%{bare:>7,}")
    body = sum(n for _, _, n, _, _ in rows)
    rest = (hi - lo) - body
    rest_built = clip(stands, lo, hi) - sum(b for *_, b, _ in rows)
    print(f"\n{'procedural blocks (28)':<46}{body:>8,}"
          f"{sum(b for *_, b, _ in rows):>8,}{covered:>8,}"
          f"{100.0 * sum(b for *_, b, _ in rows) / body:>7.1f}%")
    print(f"{'everything else in the module':<46}{rest:>8,}{rest_built:>8,}"
          f"{rest - rest_built:>8,}{100.0 * rest_built / rest:>7.1f}%")
    print(f"\nthe module's damage is {100.0 * covered / (hi - lo - clip(stands, lo, hi)):.1f}%"
          f" procedural; the top three blocks are"
          f" {100.0 * sum(r[0] for r in sorted(rows, reverse=True)[:3]) / covered:.1f}% of that")
    print(take(BIN).line())

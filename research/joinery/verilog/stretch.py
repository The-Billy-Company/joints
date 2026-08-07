#!/usr/bin/env python3
"""Is a large `built` a tree, or one root stretched over a hole?

`built` is bytes under a top-level root that has **at least one child**. It says
nothing about whether anything stands under the *rest* of that root's span, so a
policy that hands back one enormous root with one child scores the whole file.
The board's own docstring names `--mend=keep` on `picorv32.v` as the largest
instance of this on the corpus, and the sharper rule a later lane earned - a
falling node count is only reading-less when `covered` falls or `spoil` rises -
**does not fire on it**: under `keep`, covered rises 11.9 points and spoil falls
11,240 bytes while `describes` drops 9,550 nodes.

So ask the question the byte columns cannot. A **token** is a node with no
children; it is the only thing that ever actually stands over a byte. Everything
else is an interval asserted about tokens.

  token bytes   the union of every leaf node's span, at any depth
  stretch       built - (token bytes inside built)

`stretch` is the bytes a construct claims and no token in the tree stands on.
Zero means every byte `built` claims has something under it. A policy that lifts
`built` by lifting `stretch` is describing less, whatever `covered` says.
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))
import standing  # noqa: E402
from order import folio_for  # noqa: E402
from stamp import take  # noqa: E402

BIN = Path(os.environ["JOINTS_BIN"])
NAME = "verilog"
SRC = ROOT / "upstream" / "sources" / "picorv32.v"


def leaves(seen: list[tuple[int, str, int, int]]) -> list[tuple[int, int]]:
    """Every node with no child, by span. A node's children are the rows below
    it at a deeper indent, up to the next row at its own indent or shallower -
    the same containment rule `standing.tops` reads column zero with."""
    out = []
    for i, (depth, _, a, b) in enumerate(seen):
        nxt = seen[i + 1][0] if i + 1 < len(seen) else depth
        if nxt <= depth:
            out.append((a, b))
    return out


def clip(spans: list[tuple[int, int]], keep: list[tuple[int, int]]) -> int:
    """Bytes of `spans` that fall inside `keep`, counted once."""
    mask = bytearray(SIZE)
    for a, b in keep:
        mask[a:b] = b"\1" * (b - a)
    hit = bytearray(SIZE)
    for a, b in spans:
        hit[a:b] = b"\1" * (b - a)
    return sum(1 for i in range(SIZE) if mask[i] and hit[i])


SIZE = SRC.stat().st_size

print(f"{SRC.name}: {SIZE:,} bytes\n")
print(f"{'policy':<10}{'built':>9}{'describes':>10}{'tokens':>8}{'token B':>10}"
      f"{'in built':>10}{'stretch':>9}{'stretched':>11}")
for mode in ("fell", "keep", "none"):
    got = subprocess.run([str(BIN), "parse", str(folio_for(NAME, standing.WORK)),
                          str(SRC), "--ranges", "--all", f"--mend={mode}"],
                         capture_output=True, text=True, timeout=900)
    seen = standing.rows(got.stdout)
    top = standing.tops(seen)
    stands = [(a, b) for _, a, b, kid in top if kid]
    built = standing.union(stands)
    tok = leaves(seen)
    inside = clip(tok, stands)
    print(f"{mode:<10}{built:>9,}{len(seen):>10,}{len(tok):>8,}"
          f"{standing.union(tok):>10,}{inside:>10,}{built - inside:>9,}"
          f"{100.0 * (built - inside) / built if built else 0:>10.1f}%")
print("\n`stretch` is bytes a top-level construct claims with no token of any"
      " depth standing on them.")
print(take(BIN).line())

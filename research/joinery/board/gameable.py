#!/usr/bin/env python3
"""P5 — is `damage` as corruptible as the `built` it is the complement of?

Scores one grammar under a recovery policy, through `standing.py`'s own
`rows`/`tops`/`union`/`extras`, so the columns here are the board's columns and
not a second reading of them. The only thing that changes between runs is the
flag handed to the binary.

  python3 research/joinery/board/gameable.py verilog fell keep none
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))

import standing  # noqa: E402
import stamp  # noqa: E402
from order import folio_for  # noqa: E402

name = sys.argv[1] if len(sys.argv) > 1 else "verilog"
policies = sys.argv[2:] or ["fell", "keep"]
src = standing.sources()[name]
folio = folio_for(name, standing.WORK)
size = src.stat().st_size
was = standing.extras(name)

print(f"{name} · {src.name} · {size:,} bytes\n")
print(f"{'policy':<8}{'built':>9}{'damage':>9}{'orphan':>8}{'rubble':>8}{'spoil':>8}"
      f"{'stand':>8}{'describes':>11}{'roots':>7}{'leaves':>7}")
first = None
for policy in policies:
    out = stamp.ask(standing.BIN, folio, src, tree=True, extra=(f"--mend={policy}",),
                    patience=standing.PATIENCE)
    seen = standing.rows(out.tree)
    top = standing.tops(seen)
    stands = [(a, b) for _, a, b, kid in top if kid]
    built = standing.union(stands)
    under = standing.union([(a, b) for _, a, b, _ in top])
    orphan = standing.union(
        stands + [(a, b) for n, a, b, kid in top if not kid and n in was]) - built
    leaves = sum(1 for *_, kid in top if not kid)
    got = (built, size - built, orphan, under - built - orphan, size - under,
           built / size, len(seen), len(top), leaves)
    first = first or got
    print(f"{policy:<8}{got[0]:>9,}{got[1]:>9,}{got[2]:>8,}{got[3]:>8,}{got[4]:>8,}"
          f"{got[5]:>7.1%}{got[6]:>11,}{got[7]:>7,}{got[8]:>7,}")
    if got is not first:
        print(f"{'':8}{'':>9}{got[1] - first[1]:>+9,}{'':>24}{got[5] - first[5]:>+7.1%}"
              f"{got[6] - first[6]:>+11,}  <- damage moved, describes moved")

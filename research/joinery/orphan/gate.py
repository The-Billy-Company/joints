#!/usr/bin/env python3
"""Is `orphan` a measurement, or a one-bit gate wearing a byte count?

For all thirty: the mend count the binary reports on stderr, the orphan bytes
`standing.py` scores, and how many top-level extra leaves the tree actually has.
Sources and folios resolve through standing's own helpers so this instrument
cannot disagree with the board about which file each grammar was read over.
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))
import standing  # noqa: E402
from order import folio_for  # noqa: E402

BIN = Path(os.environ["OUTLINER_BIN"])
MENDS = re.compile(r"mended (\d+) over (\d+)B")

board = {r["name"]: r for r in json.load(open(sys.argv[1]))["row"]}
src = standing.sources()

print(f"{'grammar':<20}{'mends':>7}{'skipB':>8}{'orphan':>9}{'roots':>7}"
      f"{'leaves':>8}{'extras':>8}  basis")
bad = []
for name, row in sorted(board.items()):
    folio = folio_for(name, standing.WORK)
    p = subprocess.run([BIN, "parse", str(folio), str(src[name])],
                       capture_output=True, text=True)
    m = MENDS.search(p.stderr)
    mends = int(m.group(1)) if m else 0
    skip = int(m.group(2)) if m else 0
    orphan, basis = row["orphan"], row["basis"]
    flag = ""
    if mends == 0 and orphan > 0:
        flag = "  <== FALSIFIES P1a (no mend, still orphaned)"
    if mends > 0 and orphan == 0 and basis == "read":
        flag = "  <== check: mended and scored zero orphan"
    if flag:
        bad.append(name)
    print(f"{name:<20}{mends:>7}{skip:>8}{orphan:>9}{row['roots']:>7}"
          f"{row['leaves']:>8}{row['declared']:>8}  {basis}{flag}")

mended = [n for n, r in board.items()
          if r["orphan"] > 0]
print(f"\nrows with orphan > 0: {len(mended)}")
print(f"suspects: {bad or 'none'}")

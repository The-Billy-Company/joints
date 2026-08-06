#!/usr/bin/env python3
"""Every row with orphan bytes, and the wall its parse actually stopped on.

`orphan` is downstream of a mend and a mend is downstream of a wall, so the
column that tells a lane what to fix is not `orphan` and not `unbound` - it is
this one.

**The last column is trustworthy by its owner word and not by its name.**
`inquest`'s stand-in name is a guess and has been wrong twice; `lexer` versus
`press` versus `weave` is not. So read `BLIND <name>` as "a scanner this
package cannot run stands here" and prove the name some other way before
building on it - `ablate.py` is how kotlin's was proved.
"""
import json, os, re, subprocess, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))
import standing  # noqa: E402
from order import folio_for  # noqa: E402

BIN = Path(os.environ["OUTLINER_BIN"])
MENDS = re.compile(r"mended (\d+) over (\d+)B")
STANDIN = re.compile(r"no stand-in for (\S+?)\]")
board = {r["name"]: r for r in json.load(open(sys.argv[1]))["row"]}
src = standing.sources()

print(f"{'grammar':<12}{'orphan':>8}{'notbuilt':>9}{'unbound':>8}{'mends':>7}"
      f"{'stand':>8}  owner / blind terminal")
rows = sorted((r for r in board.values() if r["orphan"] > 0),
              key=lambda r: -(r["size"] - r["built"]))
for r in rows:
    n = r["name"]
    p = subprocess.run([BIN, "parse", str(folio_for(n, standing.WORK)), str(src[n]),
                        "--quiet"], capture_output=True, text=True)
    m = MENDS.search(p.stderr)
    mends = int(m.group(1)) if m else 0
    last = p.stderr.strip().splitlines()[-1]
    who = last.split(": ", 1)[-1]
    s = STANDIN.search(last)
    who = ("BLIND " + s.group(1)) if s else who[:52]
    print(f"{n:<12}{r['orphan']:>8}{r['size']-r['built']:>9}"
          f"{r['rubble']+r['spoil']:>8}{mends:>7}{r['standing']:>8.1%}  {who}")

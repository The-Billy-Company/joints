#!/usr/bin/env python3
"""The top-level roots of one parse, so a big `built` can be checked for being
one dishonest root over a hole rather than a tree."""
import re, sys, tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))
import standing  # noqa: E402

name, path = sys.argv[1], Path(sys.argv[2])
text = path.read_text()
if "strings" in sys.argv:
    text = re.sub(r'"[^"\n]*"', lambda m: "Z" + "z" * (len(m.group(0)) - 1), text)
src = Path(tempfile.mkdtemp(prefix="shape-")) / path.name
src.write_bytes(text.encode())
top, verdict = standing.ranged(name, src)
was = standing.extras(name)
b = text.encode()
print(f"{verdict}\n{len(top)} roots over {len(b)} bytes")
for n, a, x, kid in top:
    tag = "CONSTRUCT" if kid else ("extra" if n in was else "CODE-LEAF")
    print(f"  {tag:<10}{n:<28}[{a:>6},{x:>6})  {x-a:>6}B  "
          f"{b[a:min(x,a+46)].decode('utf8','replace')!r}")

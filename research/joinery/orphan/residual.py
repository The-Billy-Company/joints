#!/usr/bin/env python3
"""What is still walling an ablated file: the gaps no root covers, in context."""
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

BIN = Path(os.environ["JOINTS_BIN"])
SRC = ROOT / "upstream" / "sources" / "Maps.kt"
text = SRC.read_text()
if "strings" in sys.argv:
    text = re.sub(r'"[^"\n]*"', lambda m: "Z" + "z" * (len(m.group(0)) - 1), text)
if "imports" in sys.argv:
    text = re.sub(r"(?m)^import .*$", lambda m: "//" + " " * (len(m.group(0)) - 2), text)

d = Path(tempfile.mkdtemp(prefix="resid-"))
src = d / SRC.name
src.write_bytes(text.encode())
folio = folio_for("kotlin", standing.WORK)
for mode in ("fell", "none"):
    p = subprocess.run([BIN, "parse", str(folio), str(src), f"--mend={mode}", "--quiet"],
                       capture_output=True, text=True)
    print(f"--mend={mode}: {p.stderr.strip()}")

top, _ = standing.ranged("kotlin", src)
b = text.encode()
end, holes = 0, []
for _, a, x, _ in top:
    if a > end:
        holes.append((end, a))
    end = max(end, x)
if end < len(b):
    holes.append((end, len(b)))
hot = [(a, x) for a, x in holes if b[a:x].strip()]
print(f"\n{len(holes)} gaps, {len(hot)} with a non-space byte, "
      f"{sum(x - a for a, x in hot)} such bytes")
for a, x in hot:
    left = b[max(0, a - 46):a].decode("utf8", "replace").replace("\n", "\\n")
    body = b[a:x].decode("utf8", "replace").replace("\n", "\\n")
    right = b[x:x + 34].decode("utf8", "replace").replace("\n", "\\n")
    print(f"  [{a},{x}) …{left}»»{body}««{right}…")
print("\nleaf roots that are not extras:")
was = standing.extras("kotlin")
for name, a, x, kid in top:
    if not kid and name not in was:
        print(f"  {name:<26}[{a},{x}) {b[a:x][:50]!r}")

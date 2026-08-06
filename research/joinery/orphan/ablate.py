#!/usr/bin/env python3
"""Length-preserving ablations of one source file, scored on standing's own row.

The control `standing.py`'s docstring already uses - blank a construct to
something inert, keep every byte offset - applied one construct class at a
time. What survives the ablation is the set of walls that class was not
responsible for, and the point is the mend count, not the bytes.

`standing.ask` is reused rather than reimplemented so an ablated file is
scored by exactly the columns the board prints.
"""
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

BIN = Path(os.environ["OUTLINER_BIN"])
MENDS = re.compile(r"mended (\d+) over (\d+)B")
NAME = "kotlin"
SRC = ROOT / "upstream" / "sources" / "Maps.kt"


def fill(m: re.Match, ch: str = "z") -> str:
    """A same-length identifier where a literal stood."""
    return "Z" + ch * (len(m.group(0)) - 1)


ABLATIONS = {
    "baseline": lambda s: s,
    "strings": lambda s: re.sub(r'"[^"\n]*"', fill, s),
    "imports": lambda s: re.sub(r"(?m)^import .*$",
                                lambda m: "//" + " " * (len(m.group(0)) - 2), s),
    "strings+imports": lambda s: re.sub(
        r"(?m)^import .*$", lambda m: "//" + " " * (len(m.group(0)) - 2),
        re.sub(r'"[^"\n]*"', fill, s)),
    "comments": lambda s: re.sub(r"/\*.*?\*/", lambda m: " " * len(m.group(0)), s,
                                 flags=re.S),
}


def run(text: str, tag: str):
    src = Path(tempfile.mkdtemp(prefix="ablate-")) / SRC.name
    src.write_bytes(text.encode())
    folio = folio_for(NAME, standing.WORK)
    p = subprocess.run([BIN, "parse", str(folio), str(src)],
                       capture_output=True, text=True)
    m = MENDS.search(p.stderr)
    mends, skip = (int(m.group(1)), int(m.group(2))) if m else (0, 0)
    wall = p.stderr.strip().splitlines()[0].split(": ", 2)[-1] if p.stderr.strip() else ""
    row = standing.ask(NAME, src, "breadth")
    print(f"{tag:<18}{mends:>6}{skip:>7}{row.built:>9}{row.orphan:>9}{row.rubble:>9}"
          f"{row.spoil:>8}{row.nodes:>9}{row.leaves:>8}{row.roots:>7}  {wall[:44]}")
    return row


text = SRC.read_text()
print(f"{'ablation':<18}{'mends':>6}{'skip':>7}{'built':>9}{'orphan':>9}{'rubble':>9}"
      f"{'spoil':>8}{'nodes':>9}{'leaves':>8}{'roots':>7}  wall")
for tag, f in ABLATIONS.items():
    run(f(text), tag)

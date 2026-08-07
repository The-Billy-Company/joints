"""Capture every grammar's parse tree, so a change can be judged as trees.

A folio's sha256 is not an oracle and neither is a binary's: two presses can
agree on bytes and disagree on what they build, and two can disagree on bytes
and build exactly the same thing. The only control that means anything is the
tree itself, so this writes one file per grammar and nothing else.

    python3 research/joinery/verilog/trees.py <outdir>            capture
    python3 research/joinery/verilog/trees.py <a> --against <b>   compare

Compare prints one line per grammar and a tally, and exits 1 if fewer than 29
of 30 are identical.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))

from standing import roster  # noqa: E402


def capture(out: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    binary = os.environ.get("JOINTS_BIN", str(ROOT / "zig-out/bin/joints"))
    for name, src in roster():
        grammar = ROOT / "upstream/grammars" / f"{name}.json"
        r = subprocess.run(
            [binary, "parse", str(grammar), str(src)],
            capture_output=True, text=True, cwd=ROOT,
        )
        (out / f"{name}.tree").write_text(r.stdout)
        (out / f"{name}.err").write_text(r.stderr)
        print(f"  {name:22} {len(r.stdout):>9} bytes of tree")


def compare(a: Path, b: Path) -> int:
    same, moved = 0, []
    names = sorted(p.stem for p in a.glob("*.tree"))
    for name in names:
        x, y = (a / f"{name}.tree").read_text(), (b / f"{name}.tree").read_text()
        if x == y:
            same += 1
        else:
            moved.append((name, len(x.splitlines()), len(y.splitlines())))
    for name, n, m in moved:
        print(f"  MOVED {name:20} {n} -> {m} lines")
    print(f"tree-identical {same} of {len(names)}")
    return 0 if same >= len(names) - 1 else 1


def main() -> int:
    if len(sys.argv) == 2:
        capture(Path(sys.argv[1]))
        return 0
    if len(sys.argv) == 4 and sys.argv[2] == "--against":
        return compare(Path(sys.argv[1]), Path(sys.argv[3]))
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())

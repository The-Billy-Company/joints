#!/usr/bin/env python3
"""What the generation ledger costs, with the process included.

The flattery this guards against was committed in this exact repo one lane ago:
`order.accepts` documented `55 us for json` and `~13 ms` overall for a check
that really costs 2.7 ms and 136 ms, because it timed the binary's internal work
and left the `fork`/`exec` out. So every number below is a **whole board
process**, wall clock, measured from outside it - never an in-process timer
around the hashing loop, which is precisely the number that lied.

"Before" is not a guess and not a subtraction. It is the old rule **restored
explicitly**, the way the previous lane restored its old reach rule rather than
breaking the new one and calling it equivalent: `tool/` is copied to a scratch
directory and `OLD` below is appended to the copy's `stamp.py`, which rebinds
`fed` to the stat it used to be and `reconcile` to a ledger of nothing. The
shared tree is never touched, and the patch is printed with the results so the
reader can see exactly what "before" means.

Both arms run over the **same warm private cache**, alternately, because ten
agents build this tree continuously and a block of five befores followed by a
block of five afters would measure the machine's afternoon.

  python3 research/generation/cost.py          five each, alternating
  python3 research/generation/cost.py 9        nine each
"""

from __future__ import annotations

import os
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "tool"
BIN = ROOT / "zig-out" / "bin" / "outliner"

# The rule as it stood before this lane: an artifact was recorded by the time it
# was written, and nothing ever looked at it again. Appended rather than edited
# in, so the diff is one contiguous block a reader can check against the real
# `fed` above it instead of a scatter of deletions.
OLD = '''

# ---- restored by research/generation/cost.py: the pre-ledger rule ----------
_MTIME: dict[str, float] = {}


def fed(artifact: Path | str, row: str = "") -> None:  # noqa: F811
    """What it was: a stat, discarded at exit. No digest, no read-time identity."""
    p = Path(artifact)
    try:
        _MTIME[str(p)] = p.stat().st_mtime
    except OSError:
        _MTIME[str(p)] = 0.0


def reconcile(again: bool = False) -> Ledger:  # noqa: F811
    """What it was: nothing. There was no closing pass to be idempotent about."""
    return Ledger(0, 0, (), time.time())
'''


def arm(tmp: Path, name: str, revert: bool) -> Path:
    """A scratch `tool/`, optionally with the old rule restored.

    It has to sit under something that looks like the repo, because every tool
    here reads `ROOT` off its own path - so the parent is a farm of symlinks to
    the real repo's entries with one real directory in it. Symlinks rather than
    a copy: `upstream/` and `.local/` are hundreds of megabytes, and copying
    them would price this measurement at the copy.

    **Both** arms get a farm, including the unmodified one, so whatever the farm
    costs cancels instead of landing on the arm being judged. `real` below is
    the check on that: the same board out of the true repo, in the same series.
    """
    fake = tmp / name
    fake.mkdir()
    for entry in ROOT.iterdir():
        if entry.name != "tool":
            (fake / entry.name).symlink_to(entry)
    out = fake / "tool"
    shutil.copytree(TOOL, out, ignore=shutil.ignore_patterns("__pycache__"))
    if revert:
        (out / "stamp.py").write_text((out / "stamp.py").read_text() + OLD)
    return out


def once(tool: Path, cache: Path) -> float:
    """One whole board process, timed from outside it - fork, exec and all."""
    env = {**os.environ, "OUTLINER_WORK": str(cache), "PYTHONDONTWRITEBYTECODE": "1"}
    start = time.perf_counter()
    got = subprocess.run([sys.executable, str(tool / "standing.py")],
                         capture_output=True, text=True, cwd=ROOT, env=env)
    spent = time.perf_counter() - start
    if got.returncode not in (0, 3):
        raise SystemExit(f"cost: board exited {got.returncode}\n{got.stderr[-2000:]}")
    return spent


def floor() -> float:
    """What an empty interpreter costs, so the reader can price the rest."""
    start = time.perf_counter()
    subprocess.run([sys.executable, "-c", "pass"], capture_output=True)
    return time.perf_counter() - start


def gauge(name: str, runs: list[float]) -> str:
    return (f"  {name:<28} median {statistics.median(runs) * 1000:7.0f} ms"
            f"   min {min(runs) * 1000:7.0f}   max {max(runs) * 1000:7.0f}")


def main(argv: list[str]) -> int:
    if "--help" in argv or "-h" in argv:
        print(__doc__)
        return 0
    reps = int(next((a for a in argv if a.isdigit()), 5))
    print(__doc__.splitlines()[0])
    print("\nthe patch that makes 'before' before:")
    print("".join(f"  {ln}\n" for ln in OLD.strip().splitlines()))

    with tempfile.TemporaryDirectory(prefix="cost-") as tmp:
        tmp = Path(tmp)
        cache = tmp / "cache"
        cache.mkdir()
        for f in sorted((ROOT / ".local" / "standing").glob("*.folio")):
            shutil.copy(f, cache / f.name)
        old, new = arm(tmp, "before", True), arm(tmp, "after", False)
        bytes_ = sum(f.stat().st_size for f in cache.glob("*.folio"))
        print(f"over a warm cache of {len(list(cache.glob('*.folio')))} folios"
              f" ({bytes_ / 1e6:.1f} MB) and a {BIN.stat().st_size / 1e6:.2f} MB binary,"
              f" {reps} runs each, alternating\n")

        for one in (old, new, TOOL):  # warm the page cache for every arm
            once(one, cache)
        was, now, real = [], [], []
        for _ in range(reps):
            was.append(once(old, cache))
            now.append(once(new, cache))
            real.append(once(TOOL, cache))

    empty = statistics.median([floor() for _ in range(5)])
    print(gauge("before - stat, no ledger", was))
    print(gauge("after  - digest + reconcile", now))
    print(gauge("after, out of the real tree", real))
    print(gauge("an empty interpreter", [empty]))
    a, b = statistics.median(was), statistics.median(now)
    print(f"\n  the ledger costs {(b - a) * 1000:+.0f} ms of whole process,"
          f" {(b - a) / a * 100:+.1f}% of a board"
          f"\n  the farm itself costs {(statistics.median(real) - b) * 1000:+.0f} ms,"
          f" and both arms pay it, so it cancels out of the line above - it is here"
          f" so the absolute numbers can be read as a real board's")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

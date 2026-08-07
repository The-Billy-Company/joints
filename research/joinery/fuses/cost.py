#!/usr/bin/env python3
"""What a capacity costs: wall-clock and peak memory, per pin, over the corpus.

A cap exists to bound work, so an arm that buys bytes is only half an answer.
This runs every corpus row through each pin's own binary and reports the best of
N runs per row - best rather than mean, because a shared laptop's noise is all
in one direction and the floor is the number that reproduces.

**It parses from a folio, and that is the whole reason this file exists.**
`joints parse <grammar.json>` presses the grammar first, and the press is two
orders of magnitude the parse: scala is 1,336 ms from json and 24 ms from a
folio. A timing harness that reads json is measuring the press, and it will
report a runtime capacity as free no matter what the capacity does - the first
run of this measurement did exactly that, and called an arm that costs half the
board's `square` a 1.5% difference. A folio is a derived artifact of a binary,
so each pin mints its own.

    ./cost.py --runs 7 fz-control fz-crowd fz-walk
"""

import argparse
import json
import os
import pathlib
import resource
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[3]
CORPUS = ROOT / ".local/orchestrate/census.txt"


def rows() -> list[tuple[str, str, str]]:
    out = []
    for line in CORPUS.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        gr, _, src = line.partition("|")
        gr, src = gr.strip(), src.strip()
        if gr and src:
            out.append((pathlib.Path(gr).stem, gr, src))
    return out


def once(binary: str, gr: str, src: str) -> float:
    """Seconds for one parse, output discarded."""
    t = time.perf_counter()
    with open(os.devnull, "wb") as null:
        subprocess.run([binary, "parse", gr, src], cwd=ROOT, stdout=null, stderr=null)
    return time.perf_counter() - t


def rss(binary: str, gr: str, src: str) -> int:
    """The child's own peak resident set, in bytes.

    `getrusage(RUSAGE_CHILDREN)` is a high-water mark over every child this
    process ever reaped, so it cannot separate one row from the loudest row
    before it. `/usr/bin/time -l` reports the one process it ran.
    """
    r = subprocess.run(
        ["/usr/bin/time", "-l", binary, "parse", gr, src],
        cwd=ROOT, capture_output=True, text=True,
    )
    for line in r.stderr.splitlines():
        if "maximum resident set size" in line:
            return int(line.split()[0])
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("pins", nargs="+")
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--rss", action="store_true", help="peak resident set, not time")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    corpus = rows()
    unit, scale = ("KiB", 1 / 1024) if a.rss else ("ms", 1000)
    out: dict[str, dict[str, float]] = {}
    for pin in a.pins:
        binary = str(ROOT / ".local/pin" / pin / "bin/joints")
        shelf = ROOT / ".local/fuses/folio" / pin
        shelf.mkdir(parents=True, exist_ok=True)
        out[pin] = {}
        for name, gr, src in corpus:
            f = shelf / f"{name}.folio"
            if not f.exists():
                subprocess.run([binary, "mint", gr, "-o", str(f)],
                               cwd=ROOT, capture_output=True)
            if not f.exists():
                continue
            out[pin][name] = (rss(binary, str(f), src) if a.rss
                              else min(once(binary, str(f), src) for _ in range(a.runs)))

    if a.json:
        print(json.dumps(out, indent=1))
        return 0

    w = max(len(p) for p in a.pins) + 3
    base = a.pins[0]
    print(f"{'grammar':<20}" + "".join(f"{p:>{w}}" for p in a.pins) + "   worst ratio")
    for name, _, _ in corpus:
        if any(name not in out[p] for p in a.pins):
            continue
        cells = [out[p][name] for p in a.pins]
        ratio = max(c / cells[0] for c in cells) if cells[0] else 1.0
        print(f"{name:<20}" + "".join(f"{c * scale:>{w}.1f}" for c in cells)
              + f"{ratio:>10.2f}x" + ("  <-" if ratio > 1.05 else ""))
    tot = [sum(out[p].values()) for p in a.pins]
    print(f"\n{'TOTAL ' + unit:<20}" + "".join(f"{t * scale:>{w}.1f}" for t in tot))
    print(f"{'vs ' + base:<20}" + "".join(f"{t / tot[0]:>{w}.3f}" for t in tot))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

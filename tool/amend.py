#!/usr/bin/env python3
"""What does one keystroke cost, and does it depend on where in the file it is?

`bench.py` asks what a whole parse costs against tree-sitter's. This asks the
question an editor actually poses: the file is already open, one byte changed,
what now. The axis that matters is **cut position**, not file size, and that is
the whole reason this exists as its own instrument.

The size axis alone is flattering. Scale a file 64x and the median keystroke
still re-mints one leaf, the height grows like log n, and every number on the
page says the algebra is logarithmic - which is true, and which a user never
experiences. What a user experiences is the wall clock, and the wall clock is
paid by the half of the work the algebra does not describe: the bytes the
scanner re-reads and the tokens the parser re-shifts on the way to the edit. An
edit at 2% of the file leaves that work undone; an edit at 98% pays for all of
it. One number per file cannot tell those apart, and the mean of the two
describes neither.

So every row here is one cut position, and three of them are the report:

  2%    an edit near the top - almost nothing before it, almost all of the
        file after it
  50%   the middle
  98%   the bottom, which is where an author writing a file actually types

against `cold`, a from-scratch parse of the same bytes. The claim incremental
parsing makes is that every one of those is far under `cold`. The claim it is
easy to accidentally make instead is that the *median* is - which stays true
while the 98% row quietly crosses over and the feature stops being a feature
exactly where it is used most.

Two costs are reported per row because they are paid in different currencies
and only one of them is the algebra's:

  minted   leaves the spine re-derived. The algebra's own cost, and the number
           the `weave` tests hold to a handful.
  read     tokens the scanner and parser had to move over. The other half, and
           the one a position axis exists to expose.
  us       wall clock for that one amend, median over the beats at that
           position. What a person feels.

Every measurement carries `stamp.py`'s tree state, because four lanes edit this
repo at once and a number without a tree state is a claim about nothing.

Exit 0 ran, 1 a clean negative answer (`verify` found a regression), 2 an error.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import statistics
import subprocess
import sys
from pathlib import Path
from typing import Any, NamedTuple

import stamp

ROOT = Path(__file__).resolve().parent.parent
CORPUS = ROOT / "research" / "joinery" / "corpus"
GRAMMARS = ROOT / "upstream" / "grammars"
WORK = ROOT / ".local" / "amend"
BIN = Path(os.environ.get("OUTLINER_BIN", ROOT / "zig-out" / "bin" / "outliner"))
BASELINE = Path(__file__).resolve().parent / "amend.baseline.json"

# The deciles worth printing. 2 and 98 are the poles the finding lives at; the
# ones between are there so a curve can be seen to be a curve rather than two
# points and a line drawn through them.
CUTS = (2, 10, 25, 50, 75, 90, 98)
# Insert-then-delete, so every beat at a position lands on the same file and
# the position means what it says. Odd, so the median is a measurement.
BEATS = 9

# `outliner: PATH: 61..61 +1: accepted, 2/273 leaves reminted at 20, height 10,
#  4 lifts over 637 bytes, 29 tokens read, 55 us`
# The `outliner: <path>: ` prefix is stripped by `stamp.behind` with the path
# we passed in, so this starts where the payload does.
ROW = re.compile(
    r"^(?P<what>opened|\d+\.\.\d+ \+\d+): (?P<verdict>[^,]+)"
    r"(?:, (?P<minted>\d+)/(?P<leaves>\d+) leaves reminted at (?P<at>\d+),"
    r" height (?P<height>\d+))?"
    r", (?P<lifts>\d+) lifts over (?P<skipped>\d+) bytes,"
    r" (?P<read>\d+) tokens read, (?P<us>\d+) us$"
)


class Beat(NamedTuple):
    """One reported amend, parsed back off the verb's own stderr."""

    verdict: str
    minted: int
    leaves: int
    lifts: int
    read: int
    us: int


class Row(NamedTuple):
    grammar: str
    scale: int
    bytes: int
    cut: int  # percent of the file the edit lands at
    minted: int
    leaves: int
    lifts: int
    read: int
    us: int
    cold_us: int
    cold_read: int

    @property
    def share(self) -> float:
        """Wall clock as a share of a from-scratch parse. Over 1.0 means the
        incremental path lost to not being incremental at all."""
        return self.us / max(self.cold_us, 1)

    def as_dict(self) -> dict:
        return {**self._asdict(), "share": round(self.share, 3)}


def read(path: Path) -> bytes:
    try:
        return path.read_bytes()
    except OSError as e:
        die(f"cannot read {path}: {e}")


def die(why: str) -> Any:
    print(f"amend: {why}", file=sys.stderr)
    raise SystemExit(2)


def grown(seed: bytes, copies: int) -> bytes:
    """The same file `copies` times inside one array: a bigger file of the same
    shape. A different corpus at each size would confound the size axis with
    the grammar, which is the mistake this is written to avoid."""
    if copies == 1:
        return seed
    return b"[" + b",".join([seed] * copies) + b"]"


def drive(grammar: Path, path: Path, edits: list[str], cold: bool) -> list[Beat]:
    """One `outliner amend` process, and the cost line it printed per edit."""
    argv = [str(BIN), "amend", str(grammar), str(path), "--quiet"]
    if cold:
        argv.append("--cold")
    argv += edits
    got = subprocess.run(argv, capture_output=True, text=True, cwd=ROOT)
    if got.returncode == 2:
        die(f"{path.name}: {got.stderr.strip().splitlines()[-1] if got.stderr else 'failed'}")
    out = []
    for line in got.stderr.splitlines():
        rest = stamp.behind(line, path)
        if rest is None or not (m := ROW.match(rest)):
            continue
        out.append(Beat(
            verdict=m["verdict"],
            minted=int(m["minted"] or 0),
            leaves=int(m["leaves"] or 0),
            lifts=int(m["lifts"]),
            read=int(m["read"]),
            us=int(m["us"]),
        ))
    if not out:
        die(f"{path.name}: nothing measurable came back\n{got.stderr.strip()}")
    return out


def beats(wide: int, at: int) -> list[str]:
    """A space typed at `at` and taken straight back out, BEATS times. The
    delete restores the file, so every insert in the run is the same edit on the
    same bytes and their median is a measurement rather than a drift."""
    del wide
    script = []
    for _ in range(BEATS):
        script += [f"{at}..{at}= ", f"{at}..{at + 1}="]
    return script


def sweep(grammar: Path, name: str, seed: bytes, scale: int) -> list[Row]:
    WORK.mkdir(parents=True, exist_ok=True)
    text = grown(seed, scale)
    path = WORK / f"{name}.{scale}x{Path(seed_name(name)).suffix}"
    path.write_bytes(text)
    wide = len(text)

    # The cold parse of the same bytes, which every row is judged against. Taken
    # from the `opened:` line of a run that reuses nothing, so it is the same
    # binary doing the same job with the incremental path switched off.
    opens = [drive(grammar, path, [], cold=True)[0] for _ in range(3)]
    cold_us = int(statistics.median(o.us for o in opens))
    cold_read = opens[0].read

    rows = []
    for cut in CUTS:
        at = max(1, min(wide - 1, wide * cut // 100))
        got = drive(grammar, path, beats(wide, at), cold=False)
        # Row 0 is the open; the inserts are the odd indices after it.
        puts = [b for b in got[1::2]]
        if not puts:
            die(f"{path.name}: no insert beats at {cut}%")
        rows.append(Row(
            grammar=name, scale=scale, bytes=wide, cut=cut,
            minted=int(statistics.median(b.minted for b in puts)),
            leaves=puts[0].leaves,
            lifts=int(statistics.median(b.lifts for b in puts)),
            read=int(statistics.median(b.read for b in puts)),
            us=int(statistics.median(b.us for b in puts)),
            cold_us=cold_us, cold_read=cold_read,
        ))
    return rows


SEEDS = {"json": "ledger.json"}


def seed_name(grammar: str) -> str:
    return SEEDS[grammar]


def grammar_path(name: str) -> Path:
    """The pinned grammar, or the committed json fixture, which is the only one
    a clean clone has without a fetch."""
    live = GRAMMARS / f"{name}.json"
    if live.is_file():
        return live
    if name == "json":
        return ROOT / "test" / "grammar" / "json.json"
    die(f"no grammar for {name}; run `python3 tool/grammars.py fetch`")


def run(args: argparse.Namespace) -> int:
    if not BIN.is_file():
        die(f"no binary at {BIN}; `zig build -Dcli-optimize=ReleaseFast` first")
    scales = [int(s) for s in args.scale.split(",")]
    rows: list[Row] = []
    for name in args.grammar.split(","):
        if name not in SEEDS:
            die(f"no corpus seed for {name}; scaling one needs a grammar-shaped wrapper")
        seed = read(CORPUS / SEEDS[name])
        for scale in scales:
            rows += sweep(grammar_path(name), name, seed, scale)

    mark = stamp.take(BIN)
    if args.json:
        print(json.dumps({
            "stamp": mark.as_dict(),
            "rows": [r.as_dict() for r in rows],
        }, indent=2))
        return 0
    show(rows)
    print(mark.line(), file=sys.stderr)
    return 0


def show(rows: list[Row]) -> None:
    print("\namend: one keystroke, by where in the file it lands\n")
    print(f"  {'grammar':<8} {'scale':>5} {'bytes':>8} {'cut':>4}  "
          f"{'minted':>6} {'lifts':>5} {'read':>7}  {'us':>7} {'cold':>7}  {'x cold':>6}")
    last = None
    for r in rows:
        if last is not None and (r.grammar, r.scale) != last:
            print()
        last = (r.grammar, r.scale)
        flag = "  <- lost to cold" if r.share > 1.0 else ""
        print(f"  {r.grammar:<8} {r.scale:>4}x {r.bytes:>8} {r.cut:>3}%  "
              f"{r.minted:>6} {r.lifts:>5} {r.read:>7}  {r.us:>7} {r.cold_us:>7}  "
              f"{r.share:>6.2f}{flag}")
    print("\n  minted = leaves the spine re-derived · read = tokens moved over"
          " · us = median of the beats at that cut")


def verify(args: argparse.Namespace) -> int:
    """The regression gate: no cut position may lose to a cold parse, and none
    may cost materially more than the baseline recorded for it."""
    if not BASELINE.is_file():
        die(f"no baseline at {BASELINE}; `run --json > {BASELINE.name}` to make one")
    was = {(r["grammar"], r["scale"], r["cut"]): r
           for r in json.loads(read(BASELINE))["rows"]}
    scales = sorted({r["scale"] for r in was.values()})
    names = sorted({r["grammar"] for r in was.values()})
    rows: list[Row] = []
    for name in names:
        seed = read(CORPUS / SEEDS[name])
        for scale in scales:
            rows += sweep(grammar_path(name), name, seed, scale)

    bad = []
    for r in rows:
        if r.share > 1.0:
            bad.append(f"{r.grammar} {r.scale}x at {r.cut}%: "
                       f"{r.us} us against {r.cold_us} us cold - incremental lost")
        old = was.get((r.grammar, r.scale, r.cut))
        if old and r.minted > max(old["minted"] * 2, old["minted"] + 4):
            bad.append(f"{r.grammar} {r.scale}x at {r.cut}%: "
                       f"re-mints {r.minted} leaves, was {old['minted']}")
    show(rows)
    for line in bad:
        print(f"amend: {line}", file=sys.stderr)
    print(stamp.take(BIN).line(), file=sys.stderr)
    return 1 if bad else 0


def main() -> int:
    ap = argparse.ArgumentParser(prog="amend.py", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="verb", required=True)
    one = sub.add_parser("run", help="sweep cut positions and print the curve")
    one.add_argument("--grammar", default="json")
    one.add_argument("--scale", default="1,4,16,64")
    one.add_argument("--json", action="store_true")
    one.set_defaults(fn=run)
    two = sub.add_parser("verify", help="hold the curve to the recorded baseline")
    two.set_defaults(fn=verify)
    args = ap.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)

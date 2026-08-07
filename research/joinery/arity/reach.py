#!/usr/bin/env python3
"""A wide cell only pays if a parse can stand in it, and then only if it can win.

`arity.py` counts how many readings a contested cell drops. That count is the
size of what a binary fork could not carry, and it says nothing at all about
whether anything could ever have carried it. Three separate things have to hold
before a widened record buys a byte, and this asks all three:

1. **Class.** `forks.zig` builds a split only for `declared` or `unwritten`, so
   a `repetition` or `residual` cell of arity five offers a parse exactly
   nothing. Widening the record cannot reach a cell the index declines to enter.
2. **Reach.** A cell in a state the parse never stands in is a table entry, not
   an ambiguity anybody had. `--source` crosses the wide cells against the
   states a real parse actually splits in, off the `quire` trace.
3. **A key.** `Reading.beats` consults `heft` - the running sum of
   `prec.dynamic` - and falls back to speculation depth. A grammar declaring no
   nonzero `prec.dynamic` anywhere holds `heft` at zero for every reading, so
   `beats` *is* depth; and a rival is born later than the reading it split from,
   so it carries the higher depth and loses by construction. On such a
   **keyless** grammar a widened record can only ever substitute a rival for a
   reading that died. It can never let one be preferred.

    python3 research/joinery/arity/reach.py [FOLIO|GRAMMAR.json]...
    python3 research/joinery/arity/reach.py --source FILE GRAMMAR.json

Without `--source` the run reports class and keys only, and says the reach
column is unasked rather than printing a zero that reads like a finding.
"""

from __future__ import annotations

import os
import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

MAGIC = b"OTLFOLIO"
HEADER_LEN = 96
ENTRY_LEN = 16
ROOT = Path(__file__).resolve().parents[3]


def binary() -> Path:
    told = os.environ.get("JOINTS_BIN")
    return Path(told) if told else ROOT / "zig-out/bin/joints"


def sections(blob: bytes) -> dict[int, tuple[int, int, int]]:
    if blob[:8] != MAGIC:
        raise SystemExit("not a folio")
    count = struct.unpack_from("<H", blob, 10)[0]
    out = {}
    for i in range(count):
        kind, stride, n, off = struct.unpack_from("<HHIQ", blob, HEADER_LEN + i * ENTRY_LEN)
        out[kind] = (stride, n, off)
    return out


def enum_of(source: str, name: str) -> list[str]:
    """An enum's members in declaration order, read from the source that owns it.

    Both `leaf.Kind` and `leaf.ConflictClass` are written to disk **by ordinal**,
    so a copy of either list here would be a second spelling of the file format.
    """
    src = (ROOT / source).read_text()
    head = src.split(f"pub const {name} = enum", 1)[1]
    body = head.split("{", 1)[1].split("};", 1)[0]
    out = []
    for line in body.split("\n"):
        line = line.strip()
        if not line or line.startswith("//"):
            continue
        for part in line.split(","):
            part = part.strip()
            if part and not part.startswith("//"):
                out.append(part)
    return out


class Cell:
    __slots__ = ("state", "terminal", "kind", "cls", "rivals", "mute")

    def __init__(self, state: int, terminal: int, kind: int, cls: int, rivals: int):
        self.state, self.terminal = state, terminal
        self.kind, self.cls, self.rivals = kind, cls, rivals
        self.mute = True


def ranks(blob: bytes, dirs, where) -> list[int]:
    """`ProductionRecord.rank` for every production - what `prec.dynamic` declared.

    The one number `Reading.beats` consults before it falls back to speculation
    depth. It is read at the *grammar* level and not the cell's, because `heft`
    is a running sum over everything a reading has folded: two readings whose
    ranks tie in the cell they split at can still be parted by a fold either of
    them takes afterwards. Only a grammar that declares no nonzero rank anywhere
    holds `heft` at zero for the whole parse.
    """
    stride, count, off = dirs[where["production"]]
    return [struct.unpack_from("<i", blob, off + i * stride + 12)[0] for i in range(count)]


REDUCE = 2


def keys(path: Path, roll: list[str]) -> int:
    """How many productions carry a nonzero `prec.dynamic`."""
    blob = path.read_bytes()
    dirs = sections(blob)
    where = {name: i for i, name in enumerate(roll)}
    return sum(1 for r in ranks(blob, dirs, where) if r)


def cells(path: Path, roll: list[str]) -> list[Cell]:
    blob = path.read_bytes()
    dirs = sections(blob)
    where = {name: i for i, name in enumerate(roll)}
    if "rival" not in where:
        raise SystemExit("this folio has no `rival` section - arm a widened build")
    rank = ranks(blob, dirs, where)
    _, _, r_off = dirs[where["rival"]]
    stride, count, off = dirs[where["conflict"]]
    wide = stride // 4
    out = []
    for i in range(count):
        row = struct.unpack_from("<%dI" % wide, blob, off + i * stride)
        k = Cell(row[0], row[1], row[2], row[3], row[-1])
        reads = [row[4], row[5]] + list(
            struct.unpack_from("<%dI" % k.rivals, blob, r_off + row[-2] * 4)
        ) if k.rivals else [row[4], row[5]]
        seen = {rank[a >> 2] for a in reads if a & 3 == REDUCE}
        k.mute = len(seen) < 2
        out.append(k)
    return out


def folio_for(arg: Path, tmp: Path) -> Path:
    if arg.suffix == ".folio":
        return arg
    out = tmp / (arg.stem + ".folio")
    subprocess.run(
        [str(binary()), "mint", str(arg), "-o", str(out)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return out


SPLIT = re.compile(rb"^split: state (\d+)", re.M)
DENIED = re.compile(rb"^denied: state (\d+)", re.M)
MERGED = re.compile(rb"^merged:", re.M)
REFUTED = re.compile(rb"^refuted:", re.M)


def trace(grammar: Path, src: Path) -> bytes:
    """The `quire` trace of one real parse - one line per fork, merge and refusal."""
    r = subprocess.run(
        [str(binary()), "parse", str(grammar), str(src)],
        capture_output=True,
        env=dict(os.environ, JOINTS_TRACE="quire"),
    )
    if not SPLIT.search(r.stderr) and not REFUTED.search(r.stderr):
        raise SystemExit(
            f"no `quire` trace from {binary()} - it printed {len(r.stderr)} bytes of"
            " stderr and none of it is a fork line. A silent binary would report a"
            " reach of zero, which reads exactly like a grammar nobody splits in."
        )
    return r.stderr


def crossed(grammar: Path, src: Path, rows: list[Cell]) -> None:
    """Which wide cells a real parse actually stands in, and what became of them.

    The three counts at the bottom are one balance sheet: a strand that was born
    either merged back, was refuted, or is still standing. When births equal
    deaths the widening moved no reading into the tree, whatever it cost to get
    there - and that is a claim about the run, not about the table.
    """
    blob = trace(grammar, src)
    fired = [int(m.group(1)) for m in SPLIT.finditer(blob)]
    denied = [int(m.group(1)) for m in DENIED.finditer(blob)]
    wide = {}
    for k in rows:
        if k.rivals:
            wide.setdefault(k.state, []).append(k.rivals)
    stood = set(fired) & set(wide)
    cell_in = sum(len(wide[s]) for s in stood)
    read_in = sum(sum(wide[s]) for s in stood)
    cell_all = sum(len(v) for v in wide.values())
    read_all = sum(sum(v) for v in wide.values())
    if not cell_all:
        raise SystemExit(f"{grammar.stem} has no wide cell - arm a widened build")
    print(f"\n--- {grammar.stem} x {src.name} ---")
    print(f"  wide cells      {cell_all:6} over {len(wide):4} states, {read_all} rival readings")
    print(f"  in a state the parse SPLITS in")
    print(f"                  {cell_in:6} over {len(stood):4} states, {read_in} rival readings"
          f"   ({100.0 * cell_in / cell_all:.1f}% of cells)")
    print(f"  never entered   {cell_all - cell_in:6} over {len(wide) - len(stood):4} states"
          f"   ({100.0 * (cell_all - cell_in) / cell_all:.1f}% of cells)")
    print(f"  the parse split {len(fired)} times over {len(set(fired))} distinct states,"
          f" {sum(1 for s in fired if s in wide)} of them in a wide cell's state")
    print(f"  merged {len(MERGED.findall(blob))} · refuted {len(REFUTED.findall(blob))}"
          f" · denied {len(denied)} in states {sorted(set(denied)) or '-'}"
          + (f" (none of which holds a wide cell)"
             if denied and not (set(denied) & set(wide)) else ""))


FORKABLE = ("declared", "unwritten")


def main() -> int:
    argv = sys.argv[1:]
    source = None
    if "--source" in argv:
        i = argv.index("--source")
        source = Path(argv[i + 1])
        del argv[i : i + 2]
    args = [Path(a) for a in argv if not a.startswith("--")]
    if not args:
        args = sorted((ROOT / "upstream/grammars").glob("*.json"))
    if source and len(args) != 1:
        raise SystemExit("--source crosses ONE grammar against ONE file")
    roll = enum_of("src/folio/leaf.zig", "Kind")
    classes = enum_of("src/folio/leaf.zig", "ConflictClass")

    print(f"{'grammar':<16}{'cells':>8}{'wide':>7}{'keys':>7}  "
          + "".join(f"{c[:4]:>10}" for c in classes))
    print(f"{'':<16}{'':>8}{'':>7}{'':>7}  " + "".join(f"{'(wide)':>10}" for _ in classes))
    totals = {c: [0, 0] for c in classes}
    keyless: list[tuple[str, int]] = []
    with tempfile.TemporaryDirectory() as td:
        for arg in args:
            try:
                fol = folio_for(arg, Path(td))
                rows = cells(fol, roll)
            except Exception as e:
                print(f"{arg.stem:<16}{'-':>8}{'-':>7}  {e}")
                continue
            per = {c: [0, 0] for c in classes}
            keyed = keys(fol, roll)
            for k in rows:
                name = classes[k.cls]
                per[name][0] += 1
                if k.rivals:
                    per[name][1] += 1
            wide = sum(v[1] for v in per.values())
            if not wide:
                continue
            for c in classes:
                totals[c][0] += per[c][0]
                totals[c][1] += per[c][1]
            body = "".join(f"{per[c][0]:>5}/{per[c][1]:<4}" for c in classes)
            print(f"{arg.stem:<16}{len(rows):>8}{wide:>7}{keyed:>7}  {body}")
            if not keyed:
                keyless.append((arg.stem, wide))
            if source:
                crossed(arg, source, rows)

    print()
    body = "".join(f"{totals[c][0]:>5}/{totals[c][1]:<4}" for c in classes)
    every = sum(v[1] for v in totals.values())
    if not every:
        # A run that minted nothing and a corpus with no multi-drop cell print the
        # same zero. Refuse rather than report the second when it was the first.
        raise SystemExit(
            f"no wide cell anywhere in {len(args)} grammar(s) - either {binary()} is"
            " not a widened build (a folio with no `rival` section says so above), or"
            " the arity finding has been repaired out from under this script. Both are"
            " news; neither is a percentage."
        )
    print(f"{'ALL':<16}{sum(v[0] for v in totals.values()):>8}{every:>7}{'':>7}  {body}")
    forkable = sum(totals[c][1] for c in FORKABLE)
    declined = every - forkable
    print(
        f"\nOf {every} wide cells, {forkable} are a class `forks.zig` enters and"
        f" {declined} are a class it declines. A declined cell carries its extra"
        f" readings to disk and offers a parse none of them."
    )
    dumb = sum(n for _, n in keyless)
    print(
        f"\n{dumb} of {every} wide cells ({100.0 * dumb / every:.1f}%) are in a"
        f" **keyless** grammar - one declaring no nonzero `prec.dynamic` anywhere, so"
        f" `Reading.heft` is identically zero and `Reading.beats` is always speculation"
        f" depth. A rival is born later than the reading it split from, so it always"
        f" carries the higher depth and always loses - to `collapse` where the two fold"
        f" back onto one state stack, and to `first` where they do not. On a keyless"
        f" grammar the widening can only ever *substitute* a rival for a reading that"
        f" died; it can never let one be preferred."
    )
    for name, n in keyless:
        print(f"    keyless: {name} ({n} wide cell(s))")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Rung 4 - bits per production, against the tree-sitter `.so` for the same grammar.

`bench.py`'s `artifact` axis already weighs the two files against each other.
This asks the question the size claim is actually made in: **how many bits does
one production of this grammar cost?** Megabytes are a fact about the grammar -
cpp is thirty times ruby and neither number says anything about the format.
Bits per production divides that out, so eleven grammars become eleven
comparable numbers and the honest floor is visible rather than averaged away.

Both sides are divided by the *same* production count, which is joints' own:
the grammar is the same grammar, and tree-sitter's generator does not publish a
production census to disagree with. So the ratio equals the byte ratio exactly -
that is the point. The normalization is what makes the per-grammar numbers
comparable, not what makes the comparison fair; the comparison was already fair.

Two lane numbers ride along, because rung 4 is where the quotient's size claim
is either true or it is not:

  * `merged` - how many states the action-bisimulation says are copies of
    another, read out of the folio's own `quotient` section rather than
    recomputed here. Read the tag rather than the directory, and cross-check the
    state count against what `mint` reported, so a section that moved is a skip
    and never a wrong number.
  * `quotient` - what recording the relation costs, in bits per production, so
    the price of the claim is on the same page as the claim.

Exit 0 ran, 1 a clean negative answer (`verify` found a regression), 2 an error -
`bench.py`'s family and `differential.py`'s.
"""

from __future__ import annotations

import argparse
import json
import re
import struct
import subprocess
import sys
from pathlib import Path
from typing import Any, NamedTuple

import bench
from bench import BASELINE as BENCH_BASELINE, GRAMMARS, ROOT, folio_for, forge, sharpen
from grammars import load

BASELINE = Path(__file__).resolve().parent / "rung4.baseline.json"
TAG = b"QTNT"
# How much a number may worsen before `verify` calls it a regression. Bytes are
# deterministic, so this is tight and absolute - the same guard `bench.py` puts
# on its own `artifact` axis, for the same reason.
SLACK = 0.02

USAGE = """\
rung4.py - bits per production, ours against tree-sitter's

usage:
  rung4.py run       measure every pinned grammar (offline; skips if no oracle)
  rung4.py verify    measure, and hold the numbers to tool/rung4.baseline.json
  rung4.py record    write that baseline from a fresh run

flags:
  --grammar=NAME  one grammar
  --json          machine output
"""

SHAPE = re.compile(r"^\s{2}(productions|states)\s+(\d+)\s*$", re.M)


class Row(NamedTuple):
    name: str
    productions: int
    states: int
    merged: int
    ours: float  # bits per production, folio
    theirs: float  # bits per production, tree-sitter .so
    quotient: float  # bits per production, the class map alone
    why: str

    @property
    def ratio(self) -> float:
        return round(self.ours / self.theirs, 4) if self.theirs else 0.0

    def as_dict(self) -> dict[str, Any]:
        return {
            "productions": self.productions,
            "states": self.states,
            "merged": self.merged,
            "ours": round(self.ours, 2),
            "theirs": round(self.theirs, 2),
            "ratio": self.ratio,
            "quotient": round(self.quotient, 3),
            "unit": "bits/production",
        }


def shape_of(name: str) -> tuple[int, int, str]:
    """`productions` and `states`, from the press itself rather than from a
    second reading of the grammar. Nothing else here knows how a rule becomes a
    production, and a rung that guessed would be measuring its own guess."""
    grammar = GRAMMARS / f"{name}.json"
    if not grammar.exists():
        return 0, 0, "grammar not resolved; run `python3 tool/grammars.py fetch`"
    folio_for(name).parent.mkdir(parents=True, exist_ok=True)
    got = subprocess.run([str(bench.BIN), "mint", str(grammar), "-o", str(folio_for(name))],
                         cwd=ROOT, capture_output=True, text=True)
    if got.returncode != 0:
        return 0, 0, f"joints mint: {(got.stderr or got.stdout).strip().splitlines()[-1:]}"
    found = dict((k, int(v)) for k, v in SHAPE.findall(got.stdout))
    if "productions" not in found or "states" not in found:
        return 0, 0, "mint reported no shape"
    return found["productions"], found["states"], ""


def merged_in(folio: Path, states: int) -> int:
    """How many states the class map in this folio merged.

    By the tag, checked against the automaton: the section is byte-opaque and
    its interior belongs to `src/press/quotient.zig`, so reading it through the
    directory here would be a second reader of a format that has one. The state
    word has to agree with what `mint` said or this is not the map - which makes
    a false positive on the four tag bytes a skip rather than a number."""
    if not folio.exists():
        return 0
    raw = folio.read_bytes()
    at = raw.find(TAG)
    while at != -1:
        blocks, said = struct.unpack_from("<II", raw, at + 4)
        if said == states and 0 < blocks <= states:
            return states - blocks
        at = raw.find(TAG, at + 1)
    return 0


def measure(names: list[str], reps: int) -> list[Row]:
    rows = []
    for name in names:
        productions, states, why = shape_of(name)
        if why:
            rows.append(Row(name, 0, 0, 0, 0.0, 0.0, 0.0, why))
            continue
        got = forge(name, reps)
        if got.why:
            rows.append(Row(name, productions, states, 0, 0.0, 0.0, 0.0, got.why))
            continue
        per = 8.0 / productions
        rows.append(Row(
            name, productions, states, merged_in(folio_for(name), states),
            got.folio * per, got.dylib * per, got.sections.get("quotient", 0) * per, "",
        ))
    return rows


def show(rows: list[Row]) -> None:
    print(f"{'grammar':<12}{'prods':>7}{'states':>8}{'merged':>8}"
          f"{'ours':>10}{'theirs':>10}{'ratio':>8}{'quotient':>10}")
    ran = [r for r in rows if not r.why]
    for r in rows:
        if r.why:
            print(f"{r.name:<12}{'-':>7}{'-':>8}{'-':>8}{'':>10}{'':>10}{'':>8}{'':>10}  {r.why}")
            continue
        print(f"{r.name:<12}{r.productions:>7}{r.states:>8}{r.merged:>8}"
              f"{r.ours:>10.1f}{r.theirs:>10.1f}{r.ratio:>8.3f}{r.quotient:>10.3f}")
    if not ran:
        print("\nnothing measured")
        return
    worst = max(ran, key=lambda r: r.ratio)
    print(f"\n{len(ran)} measured, {len(rows) - len(ran)} skipped · "
          f"bits/production, under 1.000 is smaller than tree-sitter")
    print(f"the floor is {worst.name} at {worst.ratio:.3f}"
          + (" - and it LOSES" if worst.ratio >= 1.0 else ""))


def verify(rows: list[Row]) -> int:
    if not BASELINE.exists():
        print(f"no baseline at {BASELINE}; run `rung4.py record`", file=sys.stderr)
        return 2
    base = json.loads(BASELINE.read_text())["grammar"]
    bad = 0
    for r in rows:
        if r.why or r.name not in base:
            continue
        was = base[r.name]["ours"]
        if r.ours > was * (1 + SLACK):
            print(f"{r.name}: {r.ours:.2f} bits/production, was {was:.2f} "
                  f"(+{(r.ours / was - 1) * 100:.1f}%, slack {SLACK * 100:.0f}%)")
            bad += 1
    print("regression" if bad else "no regression against the baseline")
    return 1 if bad else 0


def record(rows: list[Row]) -> int:
    stamp = json.loads(BENCH_BASELINE.read_text())["recorded"] if BENCH_BASELINE.exists() else {}
    BASELINE.write_text(json.dumps({
        "recorded": stamp,
        "grammar": {r.name: r.as_dict() for r in rows if not r.why},
    }, indent=1) + "\n")
    print(f"wrote {BASELINE}")
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(add_help=False, usage=USAGE)
    ap.add_argument("verb", nargs="?", default="run", choices=("run", "verify", "record"))
    ap.add_argument("--grammar")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("-h", "--help", action="store_true")
    args = ap.parse_args(argv)
    if args.help:
        print(USAGE)
        return 0

    how = sharpen()
    if not how:
        print("no joints binary to measure; `zig build` first", file=sys.stderr)
        return 2
    print(f"binary: {how}\n")

    names = [p.name for p in load()] if not args.grammar else [args.grammar]
    rows = measure(names, 1)
    if args.json:
        print(json.dumps({r.name: (r.as_dict() if not r.why else {"why": r.why}) for r in rows},
                         indent=1))
    else:
        show(rows)
    return {"run": lambda: 0, "verify": lambda: verify(rows), "record": lambda: record(rows)}[
        args.verb]()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

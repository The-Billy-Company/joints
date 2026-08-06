#!/usr/bin/env python3
"""Find the table cell that decides a wrong parent, and read what the press saw.

A wrong-parent defect is one cell. Nothing in `outliner parse` will name it -
the parse **succeeds**, so there is no wall, no stop, no state number in any
diagnostic, and `inquest` (which reports on walls) has nothing to say. The cell
has to be found from the table.

Two verbs, because dumping 975 states costs 40 seconds and asking questions of
them costs nothing:

    python3 research/joinery/tenon/cell.py dump <grammar>
    python3 research/joinery/tenon/cell.py find <grammar> --shifts do --rule call
    python3 research/joinery/tenon/cell.py find <grammar> --complete qualified_type \\
                                                          --complete selector_expression

`find` prints one row per state whose items match, and marks the ones carrying
the **tail fingerprint**: a completed production and an in-progress one that are
the same rule with the same prefix consumed. That is `Bench.resumes` - the
`continues` flag whose `Ladder.step` shortcut returns `read` before
associativity is consulted - written as a search instead of a predicate.

Confirm a candidate with the press's own instrument rather than this file's
inference:

    OTL_DECIDE=<state> outliner parse <grammar> <any file>

`src/press/bench.zig` prints the whole `Survey` and the ladder's verdict for
that state. What a report quotes should be that line, not this one.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BIN = os.environ.get("OUTLINER_BIN", str(ROOT / "zig-out" / "bin" / "outliner"))
HOME = ROOT / ".local" / "tenon"
ITEM = re.compile(r"^ {4}(\S+) -> (.*)$")
CELL = re.compile(r"^ {4}(\S+)\s{2,}(read on|fold\b.*)$")


class State:
    __slots__ = ("n", "items", "shift", "fold")

    def __init__(self, n: int) -> None:
        self.n, self.items, self.shift, self.fold = n, [], set(), set()

    @property
    def complete(self) -> dict[str, str]:
        return {lhs: rhs.rstrip(" .") for lhs, rhs in self.items if rhs.rstrip().endswith(".")}

    def tails(self) -> list[tuple[str, str, str]]:
        """`(rule, consumed, remaining)` for every in-progress item that is a
        completed item's own production carrying on. The `continues` shape."""
        done = self.complete
        out = []
        for lhs, rhs in self.items:
            if rhs.rstrip().endswith("."):
                continue
            head, _, tail = rhs.partition(".")
            if lhs in done and done[lhs] == head.strip():
                out.append((lhs, head.strip(), tail.strip()))
        return out


def grammar_of(name: str) -> Path:
    return ROOT / "upstream" / "grammars" / f"{name}.json"


def total(name: str) -> int:
    got = subprocess.run([BIN, "state", str(grammar_of(name)), "--census", "("],
                         capture_output=True, text=True, cwd=ROOT)
    m = re.search(r"(\d+) states", got.stdout)
    if not m:
        raise SystemExit(f"cell.py: cannot read a state count for {name}: {got.stderr.strip()}")
    return int(m[1])


def dump(name: str) -> int:
    HOME.mkdir(parents=True, exist_ok=True)
    out = HOME / f"{name}.states"
    n = total(name)
    with out.open("w", encoding="utf-8") as fh:
        for q in range(n):
            got = subprocess.run([BIN, "state", str(grammar_of(name)), str(q)],
                                 capture_output=True, text=True, cwd=ROOT)
            fh.write(got.stdout)
    print(f"{name}: {n} states -> {out.relative_to(ROOT)}")
    return 0


def read(name: str) -> list[State]:
    where = HOME / f"{name}.states"
    if not where.exists():
        raise SystemExit(f"cell.py: no dump at {where}; run `cell.py dump {name}` first")
    out: list[State] = []
    at = None
    for line in where.read_text(encoding="utf-8").splitlines():
        if m := re.match(r"^state (\d+) of", line):
            out.append(State(int(m[1])))
            at = None
            continue
        if not out:
            continue
        if line.strip().startswith("row —"):
            at = "shift" if "shifts" in line else "fold"
            continue
        if at is None:
            if m := ITEM.match(line):
                out[-1].items.append((m[1], m[2]))
        elif m := CELL.match(line):
            (out[-1].shift if at == "shift" else out[-1].fold).add(m[1])
    return out


def find(name: str, shifts: list[str], complete: list[str], rule: str) -> int:
    rows = read(name)
    print(f"{name}: {len(rows)} states"
          + (f" · shifts {' '.join(shifts)}" if shifts else "")
          + (f" · completes {' '.join(complete)}" if complete else "")
          + (f" · rule ~ {rule}" if rule else ""))
    print(f"\n{'state':>7} {'items':>5} {'tail?':<6} what is standing there")
    hit = 0
    for s in rows:
        if shifts and not all(t in s.shift for t in shifts):
            continue
        done = s.complete
        if complete and not all(c in done for c in complete):
            continue
        tails = [t for t in s.tails() if not rule or rule in t[0] or rule in t[2]]
        if rule and not tails and not complete:
            continue
        hit += 1
        note = "; ".join(f"{a} -> {b} . {c}" for a, b, c in tails[:2]) or \
               "; ".join(f"{k} -> {v} ." for k, v in list(done.items())[:2])
        print(f"{s.n:>7} {len(s.items):>5} {'CONT' if tails else '—':<6} {note}")
    print(f"\n{hit} candidate cell(s). Confirm with"
          f" `OTL_DECIDE=<state> outliner parse upstream/grammars/{name}.json <file>`.")
    return 0 if hit else 1


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    verb, name = argv[0], argv[1]
    if verb == "dump":
        return dump(name)
    if verb != "find":
        print(f"cell.py: no verb {verb!r}; try dump or find", file=sys.stderr)
        return 2
    pull = lambda flag: [argv[i + 1] for i, a in enumerate(argv) if a == flag]  # noqa: E731
    return find(name, pull("--shifts"), pull("--complete"),
                (pull("--rule") or [""])[0])


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

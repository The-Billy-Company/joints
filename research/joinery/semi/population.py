#!/usr/bin/env python3
"""What company does a zero-width separator keep in an LR row?

The haskell lane licensed its late-answering layout hand with a measurement
rather than a guess: `_cmd_*` turned out to be the *only* shiftable terminal in
51 of 56 states admitting one, so answering it late could not be ambiguous.
Implicit-semicolon insertion has the same hazard and deserves the same
measurement, because a `Provision` answers from bytes and cannot ask which
reading is asking.

Two questions, one walk over every LR state:

  1. **Company.** In the states that admit `_implicit_semi`, what else is
     shiftable? A separator alone in its row is unambiguous whatever order the
     slate tries. A separator sharing its row with a rival needs the rival's
     own guard to be right.
  2. **Reachable suppression.** tree-sitter-swift conditions `_bang_custom` on
     `FAKE_TRY_BANG` not being wanted - a parse-table question a `Provision`
     cannot ask. Seating `!` would be sound anyway if no state admits both,
     because then the state-directed slate never presents the choice. If some
     state admits both, the condition is live and the decline stands.

  python3 population.py <grammar.json> <states> <terminal>...
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

BIN = Path(__file__).resolve().parents[3] / "zig-out" / "bin" / "outliner"

# The row prints one line per terminal it can act on: four spaces of indent, the
# terminal (spelled, for a literal or regex; named otherwise), then the verb -
# `read on` for a shift, `fold X -> Y` for a reduce on that lookahead.
#
# **The two verbs answer different questions and conflating them inflates by
# 85x.** What gates a stand-in is the *expected set* the parser hands the lexer,
# which is every terminal with any action - a reduce lookahead is still a
# terminal the lexer is asked to try. What the haskell lane measured was
# narrower: terminals that could be *shifted*. Both are reported, separately.
TERM = re.compile(r"^ {4}(.+?) {2,}(read on|fold )", re.M)


def admits(grammar: str, n: int) -> tuple[set[str], set[str]]:
    """(expected set, shiftable subset) for one state."""
    got = subprocess.run([str(BIN), "state", grammar, str(n)],
                         capture_output=True, text=True)
    body = got.stdout.partition("row:")[2]
    every, shift = set(), set()
    for name, verb in TERM.findall(body):
        every.add(name)
        if verb == "read on":
            shift.add(name)
    return every, shift


def main(argv: list[str]) -> int:
    grammar, states, names = argv[1], int(argv[2]), argv[3:]
    with ThreadPoolExecutor(max_workers=12) as pool:
        pairs = list(pool.map(lambda n: admits(grammar, n), range(states)))
    every = [p[0] for p in pairs]
    shift = [p[1] for p in pairs]

    out: dict[str, object] = {"states": states, "terminal": {}}
    seen: dict[str, dict[str, set[int]]] = {}

    for name in names:
        seen[name] = {
            "expected": {n for n, r in enumerate(every) if name in r},
            "shift": {n for n, r in enumerate(shift) if name in r},
        }
        e, s = seen[name]["expected"], seen[name]["shift"]
        # "Alone" is a property of one row, so it is counted per state rather
        # than pooled.
        alone_e = sum(1 for n in e if len(every[n]) == 1)
        alone_s = sum(1 for n in s if len(shift[n]) == 1)
        company = Counter()
        for n in s:
            company.update(shift[n] - {name})
        out["terminal"][name] = {
            "in_expected_set_of": len(e), "alone_there": alone_e,
            "shiftable_in": len(s), "only_shift_in": alone_s,
            "top_shift_company": company.most_common(8),
        }
        print(f"  {name:<26} expected in {len(e):>5} (alone {alone_e:>4})"
              f"   shiftable in {len(s):>4} (only one {alone_s:>4})")

    print("\n  co-admission (expected set / shiftable):")
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            be = seen[a]["expected"] & seen[b]["expected"]
            bs = seen[a]["shift"] & seen[b]["shift"]
            out.setdefault("pairs", {})[f"{a}+{b}"] = {
                "expected": sorted(be), "shift": sorted(bs)}
            tail = f" shift-states {sorted(bs)[:8]}" if bs else \
                   "  never shiftable together - the condition is unreachable"
            print(f"    {a} + {b}: {len(be)} / {len(bs)}{tail}")

    Path(__file__).with_name("population.json").write_text(json.dumps(out, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

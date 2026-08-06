#!/usr/bin/env python3
"""Build the union isolation arm: today's `troupes` roster with the rows seated
today deleted and every seam, walk, dialect and vein left in.

The fifth house rule's control is *your rows removed from today's tree*. For the
whole day's seatings at once that is mechanical: `outside.zig`'s roster is a data
table of one row per grammar mechanism, and the rows seated today are exactly the
rows present in the working tree and absent from `HEAD`. Deleting a row un-seats
its terminals - the grammar goes back to declaring externals nothing answers -
while `caesura.zig`, `marrow.zig`, `fence.zig` and `offside.zig` keep every line
of today's code. That is the plumbing.

Row identity is the tuple a `seated` decision actually turns on, not the row's
bytes: two rows that differ only in a comment are the same seating, and a HEAD
row edited today is *not* a new seating and stays in.

Usage:  ablate.py plan                 name every row this would delete
        ablate.py write <dest> [i…]   write the ablated file; with `i` (a row,
                                      or `0,4` for a set), remove only those
                                      rows and leave the rest standing
        ablate.py guests              which grammars each row could possibly
                                      reach, from the roster and the grammars'
                                      own externals — the narrowing that makes
                                      the subset question finite
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GRAMMARS = ROOT / "upstream" / "grammars"
# `$ABLATE_SRC` reads the roster from a pinned snapshot rather than from the live
# file. Ten lanes edit this tree, and a row index taken from a file that moved
# between two arms names two different seatings under one number.
SRC = Path(os.environ.get("ABLATE_SRC") or ROOT / "src/kernel/lex/outside.zig")
HEAD = "pub const troupes = [_]Troupe{"

# The fields a seating is identified by. `anchor` plus `kind` is not enough -
# python and scala share `_indent`/`offside` and are different seatings - so the
# discriminators every kind uses to tell two rows apart come in too.
KEYS = ("anchor", "kind", "dialect", "vein", "family", "tongue", "note")


def array(text: str) -> tuple[int, int]:
    i = text.index(HEAD) + len(HEAD)
    j = text.index("\n};", i)
    return i, j


def rows(text: str) -> list[tuple[int, int]]:
    """Top-level `.{ … }` spans inside the roster, by brace depth.

    Literals are stepped over rather than counted, because python's row spells a
    closing bracket as the string `"}"` and elixir's marks spell one as `'}'` -
    a depth counter that reads those ends the row 300 lines early and then calls
    the remaining rows one row.
    """
    i, j = array(text)
    out, at = [], i
    while True:
        start = text.find("\n    .{", at, j)
        if start < 0:
            return out
        depth, k = 0, start + 5
        while k < j:
            c = text[k]
            if c in "\"'":
                k += 1
                while k < j and text[k] != c:
                    k += 2 if text[k] == "\\" else 1
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    break
            k += 1
        end = text.find("\n", k)
        out.append((start + 1, end + 1))
        at = end


def key(row: str) -> tuple[str, ...]:
    out = []
    for f in KEYS:
        m = re.search(rf"\.{f} = (\.?[\w\"]+)", row)
        out.append(m.group(1).strip('"') if m else "")
    # A fence's opener list distinguishes two rows sharing a dialect.
    m = re.search(r"\.(?:opens|writs|glued|shuts) = &\.\{\s*\"?([\w\.]+)", row)
    out.append(m.group(1) if m else "")
    return tuple(out)


# Every field of a `Troupe` that names a terminal, in the three shapes the
# roster spells them: a bare string, a list of strings, and a list of structs
# with a `.name`. Taken from the struct's own declaration rather than from the
# rows, so a field added tomorrow is a field this reads - and an unknown field
# only ever *widens* a candidate set, which is the safe direction.
NAMED = ("anchor", "newline", "indent", "dedent", "body", "spelled", "close",
         "escape", "kin", "stray", "implied", "shut", "brace", "sever", "seal",
         "unbrace")
LISTED = ("opens", "sigils", "writs")
BORNE = ("roster", "shuts", "glued")


def needs(row: str) -> set[str]:
    """Every terminal this row's seating requires the grammar to declare.

    `seated()` is the specification: a part that is spelled and does not resolve
    refuses the whole cast. So a row can only ever change a grammar whose
    externals are a superset of this - which is what makes the subset question
    finite without building anything.

    Refinements are deliberately out. `hushed` entries are ordinary terminals a
    grammar may or may not spell and `seated` never asks about them, and `gate`
    is looked up across the whole terminal set rather than the externals; either
    one folded in here would *narrow* a candidate set on evidence the seating
    rule does not use, and narrowing is the unsound direction.
    """
    out: set[str] = set()
    for f in NAMED:
        if (m := re.search(rf"\.{f} = \"([^\"]*)\"", row)) and m.group(1):
            out.add(m.group(1))
    for f in LISTED:
        if m := re.search(rf"\.{f} = &\.\{{(.*?)\}},\n", row, re.S):
            out |= {x for x in re.findall(r'"([^"]+)"', m.group(1)) if x}
    for f in BORNE:
        if m := re.search(rf"\.{f} = &\.\{{(.*?)\n    \}},\n", row, re.S):
            out |= set(re.findall(r'\.name = "([^"]+)"', m.group(1)))
    for m in re.finditer(r"\.seams = \.\{(.*?)\},\n", row, re.S):
        out |= {x for x in re.findall(r'"([^"]+)"', m.group(1)) if x}
    for m in re.finditer(r"\.seams\[[^\]]+\] = \"([^\"]+)\"", row):
        out.add(m.group(1))
    return out


def externals() -> dict[str, set[str]]:
    """What each grammar in the corpus declares somebody else has to lex."""
    out = {}
    for at in sorted(GRAMMARS.glob("*.json")):
        try:
            got = json.loads(at.read_text())
        except (OSError, ValueError):
            continue
        out[at.stem] = {e.get("name") for e in got.get("externals", ())
                        if isinstance(e, dict) and e.get("name")}
    return out


def guests(text: str, cut: list[tuple[int, int]]) -> list[tuple[str, set[str], set[str]]]:
    """Per row: its seat, the terminals it needs, and the grammars that have them.

    An over-approximation on purpose - it answers *could this row reach that
    grammar* and not *does it* - because the population it feeds is a list of
    subsets to test, and a candidate too many costs one build where a candidate
    too few is a pair nobody looks at. The falsifier is in `attribute.py`: every
    grammar a row was **measured** to move must appear here.
    """
    ext = externals()
    out = []
    for a, b in cut:
        want = needs(text[a:b])
        out.append(("/".join(x for x in key(text[a:b]) if x), want,
                    {g for g, have in ext.items() if want <= have}))
    return out


def lead(text: str, start: int) -> str:
    """The last line of the comment above a row - the grammar's own name for it."""
    before = text[:start].rstrip().splitlines()
    said = []
    for ln in reversed(before):
        if not ln.lstrip().startswith("//"):
            break
        said.append(ln.strip(" /"))
    return (said[-1] if said else "?")[:64]


def main(argv: list[str]) -> int:
    live = SRC.read_text()
    was = subprocess.run(["git", "show", f"HEAD:src/kernel/lex/outside.zig"],
                         cwd=ROOT, capture_output=True, text=True, check=True).stdout
    seated = {key(was[a:b]) for a, b in rows(was)}
    cut = [(a, b) for a, b in rows(live) if key(live[a:b]) not in seated]

    if not argv or argv[0] == "plan":
        print(f"{len(rows(live))} row(s) live · {len(seated)} at HEAD · "
              f"{len(cut)} seated today\n")
        for n, (a, b) in enumerate(cut):
            print(f"  {n:<3}{'/'.join(x for x in key(live[a:b]) if x):<44}"
                  f"{live[a:b].count(chr(10)):>4} lines   {lead(live, a)}")
        return 0

    if argv[0] == "guests":
        seats = guests(live, cut)
        by: dict[str, list[int]] = {}
        for n, (_, _, who) in enumerate(seats):
            for g in who:
                by.setdefault(g, []).append(n)
        for n, (seat, want, who) in enumerate(seats):
            print(f"  {n:<3}{seat:<44}{len(want):>3} terminal(s)   "
                  f"{', '.join(sorted(who)) or 'nothing in the corpus'}")
        many = {g: r for g, r in sorted(by.items()) if len(r) > 1}
        print(f"\n{len(by)} grammar(s) reachable · {len(many)} of them by more than"
              f" one row, which is where a single-row arm can be blind:")
        for g, r in many.items():
            print(f"  {g:<14}rows {r}")
        return 0

    if argv[0] == "write":
        # A set and not a row, because a pair is the whole point: `0,4` removes
        # both of scala's seatings at once, which is the arm no single-row family
        # contains and the only one that can price two rows that cooperate.
        take = cut if len(argv) < 3 else [cut[int(i)] for i in argv[2].split(",")]
        out = live
        for a, b in sorted(take, reverse=True):
            out = out[:a] + out[b:]
        Path(argv[1]).write_text(out)
        print(f"{len(take)} row(s) removed → {argv[1]}")
        return 0

    print(__doc__)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

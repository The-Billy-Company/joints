#!/usr/bin/env python3
"""The two walls that are actually worth bytes on picorv32.v, priced.

Isolating the big `always` blocks *wrapped in a bare module* - rather than
floating in blanks, which had them all stop on `always` itself at +8 bytes,
state 164, a pure artefact of my own scaffolding - named two constructs, and
both reduce to one line:

  D  a bracketed selection **inside a concatenation**.
        x = a[3];        accepted        x = {b, c, d};    accepted
        x = (a[3] + b);  accepted        x = {f(1), b};    accepted
        x = {a[3]};      press? on ; in state 701
     Selections are fine. Concatenations are fine. `[` *inside* `{ }` is not -
     which is a conflict between the select and whatever else can follow an
     operand there (replication `{n{…}}` is the obvious candidate), and state
     701 is also where `picorv32_pcpi_div` stops.

  E  a user macro invoked as a **statement**.
        x = `WIDTH;                    accepted
        module m; `debug(x) endmodule  accepted
        always @* begin `debug end     press? on ` in state 1108
     Macros parse as expressions and at module level; in statement position
     inside a procedural block they do not.

Both ablations below are length-preserving to the byte: D mangles the brackets
of a selection into identifier characters (so the token count changes but the
byte count cannot), E comments the statement line out with `//` and spaces.

Each carries a negative control that does the *same rewrite to the construct
the grammar already accepts* - selections outside braces for D, `$display`
statements for E. A control that moves `built` says the rewrite itself is doing
the work and the positive arm proves nothing. That is not hypothetical here:
`lvalue.py`'s `= -> <=` control cost 4,557 built on its own, which is what
retired that arm.
"""
from __future__ import annotations

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
from stamp import outcome, take  # noqa: E402

BIN = Path(os.environ["OUTLINER_BIN"])
NAME = "verilog"
SRC = ROOT / "upstream" / "sources" / "picorv32.v"
SEL = re.compile(r"\[[^\[\]\n]*\]")
MACRO = re.compile(r"(?m)^([ \t]*)`(\w+)")
KEEP = {"ifdef", "ifndef", "else", "elsif", "endif", "define", "include",
        "undef", "timescale", "default_nettype", "resetall"}


def bare(m: re.Match) -> str:
    """`[3:1]` -> `zzzzz`: an identifier tail, same bytes, no brackets."""
    return "z" * len(m.group(0))


def spans(text: str) -> list[tuple[int, int]]:
    """Every `{ … }`, outermost only."""
    out, depth, start = [], 0, 0
    for i, c in enumerate(text):
        if c == "{":
            if not depth:
                start = i
            depth += 1
        elif c == "}" and depth:
            depth -= 1
            if not depth:
                out.append((start, i + 1))
    return out


def inside(text: str, flip: bool) -> str:
    """Mangle selections inside braces (`flip=False`) or outside them."""
    braces, out, at = spans(text), [], 0
    for a, b in braces:
        out.append(SEL.sub(bare, text[at:a]) if flip else text[at:a])
        out.append(text[a:b] if flip else SEL.sub(bare, text[a:b]))
        at = b
    out.append(SEL.sub(bare, text[at:]) if flip else text[at:])
    return "".join(out)


def hush(m: re.Match) -> str:
    return m.group(0) if m[2] in KEEP else f"{m[1][:-2] if len(m[1]) >= 2 else ''}//" \
        + " " * (len(m[1]) - len(m[1][:-2] if len(m[1]) >= 2 else '') - 2 + len(m[2]) + 1)


def macro_lines(s: str) -> str:
    return re.sub(r"(?m)^([ \t]*)`(\w+)[^\n]*$",
                  lambda m: m.group(0) if m[2] in KEEP
                  else "//" + " " * (len(m.group(0)) - 2), s)


def display_lines(s: str) -> str:
    return re.sub(r"(?m)^[ \t]*\$\w+[^\n]*$",
                  lambda m: "//" + " " * (len(m.group(0)) - 2), s)


ARMS: dict[str, object] = {
    "baseline": lambda s: s,
    "D  [..] inside { }": lambda s: inside(s, flip=False),
    "   control: [..] outside": lambda s: inside(s, flip=True),
    "E  macro statements": macro_lines,
    "   control: $task stmts": display_lines,
    "D+E": lambda s: macro_lines(inside(s, flip=False)),
}


def score(body: str):
    src = Path(tempfile.mkdtemp(prefix="v-brace-")) / SRC.name
    src.write_text(body)
    got = subprocess.run([str(BIN), "parse", str(folio_for(NAME, standing.WORK)),
                          str(src), "--ranges", "--all"],
                         capture_output=True, text=True, timeout=900)
    end = outcome(got.stderr, src, len(body), got.stdout)
    seen = standing.rows(got.stdout)
    top = standing.tops(seen)
    stands = [(a, b) for _, a, b, kid in top if kid]
    built = standing.union(stands)
    under = standing.union([(a, b) for _, a, b, _ in top])
    bare_b = standing.union([(a, b) for _, a, b, kid in top if not kid])
    return built, under - built, bare_b, len(seen), end


if __name__ == "__main__":
    text = SRC.read_text()
    size = len(text)
    braced = sum(len(SEL.findall(text[a:b])) for a, b in spans(text))
    print(f"{SRC.name}: {size:,} bytes · {len(spans(text))} concatenations holding"
          f" {braced} bracketed selections · {len(SEL.findall(text)) - braced} outside\n")
    print(f"{'arm':<28}{'built':>9}{'damage':>9}{'d built':>10}{'rubble':>8}"
          f"{'describes':>11}{'d desc':>9}{'leafB':>8}{'mends':>7}  wall")
    first = None
    for tag, fn in ARMS.items():
        arm = fn(text)
        assert len(arm) == size, f"{tag}: {len(arm)} != {size}"
        built, rub, bare_b, nodes, end = score(arm)
        first = first or (built, nodes)
        print(f"{tag:<28}{built:>9,}{size - built:>9,}{built - first[0]:>+10,}"
              f"{rub:>8,}{nodes:>11,}{nodes - first[1]:>+9,}{bare_b:>8,}"
              f"{end.mends:>7}  {end.verdict[:28]}")
    print(take(BIN).line())

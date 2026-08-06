#!/usr/bin/env python3
"""Length-preserving ablations of `picorv32.v`, scored on the board's own row.

The method `research/joinery/orphan/ablate.py` earned on kotlin, pointed at the
grammar with the largest damage on the board. Blank one construct class to
same-length filler, keep every byte offset, and read what `built` does. What
survives an ablation is the set of walls that class was **not** responsible for.

Two things this prints that the kotlin version does not, both because the trap
on this file is describing-less rather than reading-less:

  `describes` and `leaves`, on every row. `built` is bytes under a top-level
  root that has at least one child, so one dishonest root stretched over a hole
  scores the whole hole. A row whose `built` rises while `describes` falls is
  reading less and saying so; a row where both rise is real.

  A **negative control** in the same table. Blanking every comment is expected
  to move nothing at all, and a positive result is worth what the negative one
  is worth: if the control moves too, the ablation is measuring the act of
  editing the file rather than the construct.

Each row is one parse of one temporary file against the folio the board uses,
so nothing here can disagree with `standing.py` about what a root is.
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


def blank(m: re.Match) -> str:
    """Spaces, exactly as wide as what stood here."""
    return " " * len(m.group(0))


def ident(m: re.Match) -> str:
    """A same-length identifier, for a place a token is still required."""
    return "Z" + "z" * (len(m.group(0)) - 1)


def comment_out(m: re.Match) -> str:
    """A same-length verilog line comment, for a whole line that must vanish
    without changing where the next line starts."""
    return "//" + " " * (len(m.group(0)) - 2)


ABLATIONS: dict[str, object] = {
    "baseline": lambda s: s,
    # The positive: every line that opens with a preprocessor directive.
    "directive lines": lambda s: re.sub(r"(?m)^[ \t]*`\w+.*$", comment_out, s),
    # The same family, narrower: the directive *token* only, leaving its
    # argument in place. Separates "the backtick is unlexable" from "the
    # construct it introduces is unparseable".
    "directive tokens": lambda s: re.sub(r"`\w+", ident, s),
    # The conditional-compilation subset alone - the one at byte 3712.
    "ifdef family": lambda s: re.sub(
        r"(?m)^[ \t]*`(ifdef|ifndef|else|elsif|endif)\b.*$", comment_out, s),
    # NEGATIVE CONTROLS. Neither should move `built` by a byte.
    "comments (control)": lambda s: re.sub(
        r"/\*.*?\*/", blank, re.sub(r"(?m)//[^\n]*", blank, s), flags=re.S),
    "strings (control)": lambda s: re.sub(r'"[^"\n]*"', ident, s),
    "attributes (control)": lambda s: re.sub(r"\(\*.*?\*\)", blank, s, flags=re.S),
}


def run(text: str, tag: str) -> tuple[str, object]:
    src = Path(tempfile.mkdtemp(prefix="v-ablate-")) / SRC.name
    src.write_bytes(text.encode())
    folio = folio_for(NAME, standing.WORK)
    got = subprocess.run([str(BIN), "parse", str(folio), str(src), "--quiet"],
                         capture_output=True, text=True, timeout=900)
    end = outcome(got.stderr, src, len(text))
    row = standing.ask(NAME, src, "breadth")
    print(f"{tag:<22}{end.mends:>7}{row.built:>9}{row.orphan:>8}{row.rubble:>8}"
          f"{row.spoil:>8}{row.nodes:>9}{row.leaves:>7}{row.roots:>7}"
          f"{row.covered:>8.1%}  {end.verdict[:38]}", flush=True)
    return tag, row


if __name__ == "__main__":
    text = SRC.read_text()
    print(f"{SRC.name}: {len(text):,} bytes\n")
    print(f"{'ablation':<22}{'mends':>7}{'built':>9}{'orphan':>8}{'rubble':>8}"
          f"{'spoil':>8}{'describes':>9}{'leaves':>7}{'roots':>7}{'covered':>8}  wall")
    seen = {}
    for tag, fn in ABLATIONS.items():
        body = fn(text)
        assert len(body) == len(text), f"{tag} changed the length: {len(body)} vs {len(text)}"
        seen[tag] = run(body, tag)[1]
    base = seen["baseline"]
    print(f"\n{'ablation':<22}{'d built':>10}{'d describes':>12}{'d covered':>11}"
          f"{'d spoil':>10}  reading")
    for tag, row in seen.items():
        if tag == "baseline":
            continue
        db, dn = row.built - base.built, row.nodes - base.nodes
        print(f"{tag:<22}{db:>+10,}{dn:>+12,}{row.covered - base.covered:>+10.1%}"
              f"{row.spoil - base.spoil:>+10,}  "
              + ("more - built and describes both rise" if db > 0 and dn > 0 else
                 "LESS - built rises while describes falls" if db > 0 else
                 "nothing moved" if db == 0 and dn == 0 else "worse"))
    print(take(BIN).line())

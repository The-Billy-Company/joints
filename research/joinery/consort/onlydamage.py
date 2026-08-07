#!/usr/bin/env python3
"""Which published conclusions on this tree were taken on `damage` alone.

`RESULT-5-blindness.md` labelled the ablation family: 28 of the 33 boards on
this disk never read a square byte, so every conclusion drawn off them is a
statement about joints's own forest and not about agreement with a second
parser. The family is not the only thing measured here, and this is the sweep
that says how far the blindness reaches into what is already written down.

The triage is deliberately crude and deliberately *over*-inclusive, because the
expensive error is missing a page rather than reading one too many:

  a page is **damage-only** when it quotes a number beside `damage`/`built`/
  `standing`/`worth` and never quotes one beside `square`/`crooked`/`graded`.

Two flags ride along, and they are what the ranking is actually made of:

  `compares`  the page draws a conclusion from two arms - `worth`, `residual`,
              `before`/`after`, a clearance, a byte-identical claim. A single
              board's description of one tree is a much smaller thing to be
              wrong about than a difference between two.
  `extras`    the page's subject is a comment, docstring, trivia or other
              declared extra. That is the class where `damage`'s bias has a
              **known direction**: a correctly-recognised extra leaves the tree
              as an `orphan` and a misread one is counted as `built`, so
              `damage` actively rewards misreading one. ocaml's row is the
              proven case - un-seating it *lowers* `damage` by 721 while
              *lowering* `square` by 448.

Nothing here is a verdict. It is a worklist, ordered so the pages a `square`
reading could actually overturn come first, and every one of the top rows was
read by hand before it was ranked.

Usage:  onlydamage.py               the worklist, worst first
        onlydamage.py --json        the same, machine-readable
        onlydamage.py --all         include the pages that did read a square
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WHERE = ("research", "changelog.d")

# A column name with a number attached, in either order: `damage 4,150`,
# `4,150 bytes of damage`, `| damage | 4,150 |`. A bare mention of the word in
# prose is not a measurement and must not count as one.
def beside(text: str, words: str) -> list[str]:
    """Which of `words` this page put a number beside, one entry per pairing.

    `near` is this counted. They are one function because a caller that wants to
    ask *which column* - and `instrument.py` does, to find out whether anything
    named on the page can even report it - must be reading the same pairings the
    count was made of, or it is answering about a different page.
    """
    return [m.group(1) for m in
            re.finditer(rf"\b({words})\b[^\n|]{{0,24}}?[-+−]?\d", text, re.I)] + \
           [m.group(1) for m in
            re.finditer(rf"[-+−]?[\d,]+\s*(?:bytes?\s+of\s+)?\b({words})\b", text, re.I)]


def near(text: str, words: str) -> int:
    return len(beside(text, words))


OURS = "damage|built|standing|worth|unbuilt|rubble"
# Every vocabulary on this tree in which a number is about a SECOND parser, not
# just the board's own column. `rack`/`plumb` cut the same comparison into
# `regrouped`/`relabelled`/`interstice`, and a page that reports those has asked
# tree-sitter even though it never says `square` - `plumb/RESULT-1-askew.md` is
# 33,634 bytes of oracle disagreement and reads as blind to a `square` grep.
THEIRS = ("square|crooked|graded|unframed|soft|regrouped|relabelled|interstice"
          "|askew|tree-identical")
COMPARES = ("worth", "residual", "isolation arm", "control", "before/after",
            "byte-identical", "clearance", "collateral", "no other grammar",
            "ablat", "un-seat", "unseat", "removed", "regression")
EXTRAS = ("comment", "docstring", "extra", "orphan", "trivia", "verbatim",
          "heredoc", "whitespace", "blank")
# A clearance that compared the parse **trees** of two arms is square-safe
# whatever column it quoted: if two arms' forests are byte-identical for a
# grammar, every measure derived from them is too, `square` included. That is a
# different and much cheaper proof than an oracle sweep, and the pages that have
# it are not the pages this worklist is for. `verilog/trees.py` is the
# instrument, and it is general - it reads `standing.roster()`.
FOREST = ("tree-identical", "trees.py", "differential.py", "breadth.py",
          "byte-identical to real tree-sitter")


def pages() -> list[Path]:
    out = []
    for where in WHERE:
        out += [p for p in (ROOT / where).rglob("*.md") if p.is_file()]
    return sorted(out)


def read(at: Path) -> dict:
    text = at.read_text(errors="replace")
    ours, theirs = beside(text, OURS), beside(text, THEIRS)
    low = text.lower()
    return {
        "path": str(at.relative_to(ROOT)),
        "ours": len(ours),
        "theirs": len(theirs),
        # The words behind `ours`, carried rather than recomputed. A caller that
        # asks *which* column was quoted was re-running this same pass, which is
        # both a quarter of the read's cost and a second chance to disagree with
        # the count it is standing next to.
        "quoted": sorted({w.lower() for w in ours}),
        "compares": sum(w in low for w in COMPARES),
        "extras": sum(low.count(w) for w in EXTRAS),
        "forest": sum(low.count(w) for w in FOREST),
        # A prediction is a hypothesis and not a conclusion, so it cannot be
        # overturned by anything. Kept in the population and ranked last,
        # because a prediction whose result page is missing is worth seeing.
        "claims": not at.name.startswith("PREDICTION"),
        "lines": text.count("\n") + 1,
    }


def rank(got: dict) -> float:
    """How much a `square` reading could move this page's conclusion.

    Weighted by what the blindness actually costs: a comparison can have its
    *sign* changed and a single description can only be incomplete, an extras
    subject is the one place the bias has a known direction rather than an
    unknown one, and a page that compared forests has already answered the
    question a `square` reading would answer.
    """
    return got["ours"] * (1 + 0.6 * min(got["compares"], 6)) \
        * (1 + 0.25 * min(got["extras"], 8)) \
        / (1 + min(got["forest"], 4)) * (1 if got["claims"] else 0.3)


def main(argv: list[str]) -> int:
    got = [read(p) for p in pages()]
    blind = [g for g in got if g["ours"] and not g["theirs"]]
    for g in got:
        g["rank"] = round(rank(g), 1)
    want = sorted(got if "--all" in argv else blind,
                  key=lambda g: -g["rank"])
    if "--json" in argv:
        print(json.dumps(want, indent=1))
        return 0
    print(f"\n  {len(got)} page(s) · {len(blind)} quote a number of ours and never"
          f" one of the oracle's\n")
    print(f"  {'rank':>7}  {'ours':>4}{'theirs':>7}{'cmp':>5}{'extra':>6}{'forest':>7}  page")
    for g in want[:40]:
        print(f"  {g['rank']:>7.1f}  {g['ours']:>4}{g['theirs']:>7}"
              f"{g['compares']:>5}{g['extras']:>6}{g['forest']:>7}  {g['path']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

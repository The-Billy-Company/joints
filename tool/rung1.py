#!/usr/bin/env python3
"""Run rung 1 over the whole corpus and hold it to what the dossier claims.

`research/joinery/TESTING.md` says three things a run can be checked against,
and they are the ones that would kill the design rather than merely disappoint
it:

  * every one of the eleven grammars presses to **zero residual conflicts**;
  * **nothing disagrees** - the product of the segment effects is the effect of
    the whole file, at every segmentation;
  * the **residue never gets past two** - the running product of unrefuted
    pairings stays bounded, and bounded independently of how finely the file is
    cut.

Refusals are not gated. Thirty of them are documented, owned, and blamed on the
lexer and the fork rather than the monoid, so a gate on their count would fail
the four people fixing them. json is gated on reading to the end, because it is
the one grammar that does today and losing that is news.

`outliner joints` exits 1 whenever anything refused, which is nine grammars out
of eleven right now - so a gate cannot just read its exit code, it has to read
what it said. Exit 0 all three held, 1 one of them did not, 2 could not run.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
from stamp import take  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
GRAMMARS = ROOT / "upstream" / "grammars"
CORPUS = ROOT / "research" / "joinery" / "corpus"
BIN = Path(os.environ.get("OUTLINER_BIN", ROOT / "zig-out" / "bin" / "outliner"))

HEAD = re.compile(r"^(\S+)\s+(\d+) states.*?\((\d+) declared, (\d+) residual\)")
TAIL = re.compile(r"^worst p99 rank (\d+) · widest residue (\d+) · (.*)$")
HELD = re.compile(r"(\d+)/(\d+) chains held")
REFUSED = re.compile(r"(\d+) refused at a ceiling")
RESIDUE_MAX = 2


class Result(NamedTuple):
    name: str
    file: str
    states: int
    residual: int
    rank: int
    residue: int
    held: str
    refused: int
    disagreed: bool
    accepted: bool
    faults: list[str]


def pairs() -> list[tuple[str, str]]:
    """Which corpus file belongs to which grammar, read out of the corpus's own
    README table rather than restated here. That table is what a contributor
    edits when they add a language, so scraping it means the gate cannot fall
    out of step with the corpus by one file - and a row naming a file or a
    grammar that does not exist is a fault worth failing on, not a row to skip.
    """
    rows = []
    for line in (CORPUS / "README.md").read_text(encoding="utf-8").splitlines():
        cells = [c.strip().strip("`") for c in line.split("|")[1:-1]]
        if len(cells) < 2 or cells[0] in ("file", "") or set(cells[0]) <= set("-: "):
            continue
        rows.append((cells[1], cells[0]))
    return rows


def measure(name: str, filename: str) -> Result:
    grammar, source = GRAMMARS / f"{name}.json", CORPUS / filename
    for p in (grammar, source):
        if not p.exists():
            raise FileNotFoundError(p)
    out = subprocess.run(
        [str(BIN), "joints", str(grammar), str(source)],
        capture_output=True,
        text=True,
        cwd=ROOT,
    ).stdout
    lines = [ln for ln in out.splitlines() if ln.strip()]
    head = next((m for ln in lines if (m := HEAD.match(ln))), None)
    tail = next((m for ln in reversed(lines) for m in [TAIL.match(ln)] if m), None)
    if not head or not tail:
        raise ValueError(f"{name}: cannot read the run's own report:\n{out}")
    rank, residue, verdict = int(tail[1]), int(tail[2]), tail[3]
    held = HELD.search(verdict)
    r = Result(
        name=name,
        file=filename,
        states=int(head[2]),
        residual=int(head[4]),
        rank=rank,
        residue=residue,
        held=f"{held[1]}/{held[2]}" if held else "0/0",
        refused=int(m[1]) if (m := REFUSED.search(verdict)) else 0,
        disagreed="DISAGREED" in verdict,
        # sole: the `joints` verb's own report, not a parse verdict. The two
        # verbs share the word and nothing else - `stamp.outcome` reads what
        # `parse` writes on stderr, and this is what `joints` writes on stdout.
        accepted=any("accepted" in ln for ln in lines),
        faults=[],
    )
    if r.disagreed:
        r.faults.append("a chain disagreed - the product is not the whole-file effect")
    if r.residue > RESIDUE_MAX:
        r.faults.append(f"residue {r.residue} is past {RESIDUE_MAX}")
    if r.residual:
        r.faults.append(f"{r.residual} residual conflicts survived the press")
    if name == "json" and not (r.accepted and r.held == "8/8"):
        r.faults.append(f"json no longer reads to the end at every cut: {r.held}, accepted={r.accepted}")
    return r


def main(argv: list[str]) -> int:
    as_json = "--json" in argv
    want = [a for a in argv if not a.startswith("-")]
    if not BIN.exists():
        print(f"rung1.py: no binary at {BIN}; run `zig build` first", file=sys.stderr)
        return 2
    # Taken before the sweep rather than after, so a lane landing mid-run shows
    # up as the stamp disagreeing with the numbers underneath it. Three of
    # tonight's runs were caught that way.
    mark = take(BIN)
    try:
        todo = [(g, f) for g, f in pairs() if not want or g in want]
        if not todo:
            raise ValueError(f"no corpus row matches {want}")
        results = [measure(g, f) for g, f in todo]
    except (OSError, ValueError) as e:
        print(f"rung1.py: {e}", file=sys.stderr)
        return 2

    if as_json:
        print(json.dumps({"stamp": mark.as_dict(),
                          "grammar": [r._asdict() for r in results]}, indent=2))
    else:
        print(f"{'grammar':<11} {'states':>6} {'residual':>8} {'p99 rank':>8} {'residue':>7} {'chains':>7}  stops")
        for r in results:
            stop = (
                "read to the end"
                if r.accepted
                else f"{r.refused} refused at a ceiling"
                if r.refused
                else "nothing measured"
                if r.held == "0/0"
                else "stopped early, held every chain it could run"
            )
            print(
                f"{r.name:<11} {r.states:>6} {r.residual:>8} {r.rank:>8} "
                f"{r.residue:>7} {r.held:>7}  {stop}"
            )
    faults = [(r.name, f) for r in results if r.faults for f in r.faults]
    if not as_json:
        print(mark.line())
    sys.stdout.flush()
    for name, fault in faults:
        print(f"rung1: {name}: {fault}", file=sys.stderr)
    if faults:
        print(f"rung1: {len(faults)} claim(s) in research/joinery/TESTING.md no longer hold", file=sys.stderr)
        return 1
    print(
        f"rung1: {len(results)} grammars · zero residual conflicts · nothing disagreed · "
        f"residue never past {max(r.residue for r in results)}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Our repair surface against tree-sitter's, over the same thirty files.

tree-sitter has published a repair surface since before this project existed,
and it has two members. An **`ERROR`** is a real node in the tree, with a span,
covering the region the parser could not derive; a **`MISSING`** is a
zero-width node the parser *invented* to make a derivation close, and the CLI
prints it as `MISSING: "kind"` in the CST render. Between them a consumer can
ask both of the questions a repair raises: which bytes did nobody derive, and
which tokens are here only because the parser said so.

`joints parse --scars` is the third answer, and this file is where it has to
say whether it is one. It reads both surfaces over the corpus roster and prints
them beside each other:

  ours    scars, the bytes they span, and how many shifted nothing (a cascade)
  theirs  ERROR nodes, the bytes they span, and MISSING insertions

## What the comparison is actually for

Not a score. The two surfaces are not the same object and a row where one is
larger is not a row where one is better - tree-sitter recovers differently, so
its ERROR spans and our scar spans are answers to different questions about the
same defect. What is comparable, and what this file reports, is **who saw a
defect at all**:

  both      the file is bad and both surfaces say so
  ours      we repaired where tree-sitter derived cleanly - our gap, in bytes,
            and it is not a claim about the file
  theirs    tree-sitter reports an ERROR and we mended nowhere

The `ours` column is the honest one to lead with, because a repair surface that
only ever reports the input's faults is a surface that cannot find its owner's.

  python3 research/joinery/scars/against.py
  python3 research/joinery/scars/against.py --json .local/scars/against.json

Exit 0 measured, 1 nothing comparable, 2 an error.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))

import differential as diff  # noqa: E402
import order  # noqa: E402
import plumb  # noqa: E402
import stamp  # noqa: E402
from seat import SCAR, Site  # noqa: E402


def union(spans: list[tuple[int, int]]) -> int:
    total, end = 0, -1
    for a, b in sorted(spans):
        a = max(a, end)
        if b > a:
            total += b - a
            end = b
    return total


class Row(NamedTuple):
    name: str
    size: int
    # ours
    scars: int
    cascades: int
    spanned: int
    # theirs
    errors: int
    hurt: int      # bytes under an ERROR node
    missing: int   # zero-width nodes tree-sitter inserted
    why: str       # why the oracle could not be read, if it could not

    @property
    def verdict(self) -> str:
        if self.why:
            return "unjudged"
        mine, yours = self.scars > 0, self.errors > 0 or self.missing > 0
        return ("both" if mine and yours else
                "ours" if mine else "theirs" if yours else "clean")


def theirs(lang: Path, src: Path) -> tuple[int, int, int, str]:
    """Every `ERROR` and `MISSING` in tree-sitter's own CST render."""
    try:
        text, _ = diff.oracle_full(lang, src, "--cst")
        root, _ = diff.cst_tree(text, diff.Lines(src.read_bytes()))
    except (ValueError, OSError, subprocess.SubprocessError) as e:
        return 0, 0, 0, str(e).splitlines()[0][:60] or "oracle refused"
    bad: list[tuple[int, int]] = []
    gone = 0
    stack = [root]
    while stack:
        node = stack.pop()
        if node.name == "ERROR":
            bad.append((node.start, node.end))
        elif node.name.startswith("MISSING "):
            gone += 1
        stack += node.kids
    return len(bad), union(bad), gone, ""


def ours(art: Path, src: Path, binary: Path) -> tuple[int, int, int]:
    got = subprocess.run([str(binary), "parse", str(art), str(src), "--scars"],
                         capture_output=True, text=True, timeout=stamp.PATIENCE, cwd=ROOT)
    sites = [Site(int(m[1]), int(m[2]), m[4] == "fell", m[5], int(m[6]), int(m[7]))
             for line in got.stdout.splitlines() if (m := SCAR.match(line.strip()))]
    cascade = sum(1 for i, s in enumerate(sites) if i and not s.since)
    return len(sites), cascade, union([(s.at, s.over) for s in sites])


def row(case: plumb.Case, work: Path, binary: Path) -> Row | None:
    art = order.folio_for(case.name, work) or (order.GRAMMARS / f"{case.name}.json")
    if not Path(art).exists() or not case.source.exists():
        return None
    scars, cascades, spanned = ours(Path(art), case.source, binary)
    errors, hurt, missing, why = theirs(case.lang, case.source)
    return Row(case.name, case.source.stat().st_size, scars, cascades, spanned,
               errors, hurt, missing, why)


def warm(picked: list[plumb.Case]) -> None:
    """Generate and compile every oracle first, exactly as `rack.sweep` does.

    Without it the CLI answers `No language found` for any grammar this seat has
    not built yet, and ten of thirty rows read as an oracle refusal when they are
    an unbuilt library. An instrument whose skipped rows are its own setup is an
    instrument that reports its corpus as its finding.
    """
    diff.lay_out()
    for case in picked:
        try:
            with diff.alone(diff.named(case.lang)):
                diff.oracle_build(case.lang, case.grammar)
                diff.cli([str(diff.TS), "parse", "-p", str(case.lang), "-q",
                          str(case.source)], diff.WORK)
        except (OSError, ValueError):
            pass  # `theirs` reports it properly; this only pre-compiles


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--json", type=Path)
    args = ap.parse_args(argv)

    work = Path(order.os.environ.get("JOINTS_WORK", ROOT / ".local" / "work"))
    picked = plumb.slate()
    warm(picked)
    rows = [r for case in picked if (r := row(case, work, order.BIN))]
    if not rows:
        print("against: nothing comparable", file=sys.stderr)
        return 1

    print(f"{'grammar':<12}{'size':>9}{'scars':>8}{'casc':>7}{'spanned':>9}"
          f"{'ERROR':>7}{'hurt':>8}{'MISS':>6}  saw it")
    for r in sorted(rows, key=lambda r: (r.verdict, -r.scars)):
        print(f"{r.name:<12}{r.size:>9,}{r.scars:>8,}{r.cascades:>7,}{r.spanned:>9,}"
              f"{r.errors:>7,}{r.hurt:>8,}{r.missing:>6,}  {r.why or r.verdict}")

    judged = [r for r in rows if not r.why]
    tally = {v: [r for r in judged if r.verdict == v] for v in ("both", "ours", "theirs", "clean")}
    print(f"\n{len(judged)} of {len(rows)} grammars have a readable oracle. "
          + " · ".join(f"{k} {len(v)}" for k, v in tally.items()))
    mine = tally["ours"]
    if mine:
        print(f"\n**{len(mine)} grammar(s) we repaired and tree-sitter derived clean** "
              f"({', '.join(r.name for r in mine)}): {sum(r.scars for r in mine):,} scars "
              f"over {sum(r.spanned for r in mine):,} B of a file the oracle had no "
              f"ERROR in. That is our gap and not the file's, and before `--scars` the "
              f"only sign of it on any board here was a `mended N` count in a verdict "
              f"line with no location attached.")
    if tally["theirs"]:
        print(f"\n{len(tally['theirs'])} grammar(s) tree-sitter reports an ERROR or a "
              f"MISSING in and we mend nowhere "
              f"({', '.join(r.name for r in tally['theirs'])}). A parse that never "
              f"refused is not the same as a parse that was right - `standing.py` is "
              f"where that is priced - but nothing was repaired, so nothing here is "
              f"papered over by a repair.")
    for r in tally["both"]:
        # The one row-level comparison that means something: both surfaces
        # located the same defect, so how much of the file does each hand back
        # as "here"? An `ERROR` that reaches the root is a legal answer under
        # tree-sitter's own contract and a useless one to a consumer.
        print(f"\n{r.name}: both surfaces saw it. tree-sitter marks {r.errors} ERROR "
              f"node(s) over {r.hurt:,} B ({100.0 * r.hurt / r.size:.0f}% of the file) "
              f"and inserts {r.missing} MISSING; we cut {r.scars - r.cascades:,} scar(s) "
              f"that shifted ground (plus {r.cascades:,} restating them) over "
              f"{r.spanned:,} B ({100.0 * r.spanned / r.size:.0f}%).")
    ins = sum(r.missing for r in judged)
    print(f"\ntree-sitter inserted {ins:,} MISSING node(s) across the corpus. **We have "
          f"no equivalent**: every mend this parser performs is a deletion (drop the "
          f"token, or put the stack down and stand it back up), so a `scar` never "
          f"reports an insertion because the runtime never makes one. That is the one "
          f"place this surface is behind, and it is behind the *runtime*, not the "
          f"reporting.")
    if args.json:
        args.json.write_text(json.dumps([r._asdict() for r in rows], indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

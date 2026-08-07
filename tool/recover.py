#!/usr/bin/env python3
"""What do the two parsers do with a file that is broken?

Every file in the corpus is valid. Every held-out file is valid. This is an
incremental parser, whose whole reason to exist is a buffer being edited - and a
buffer under edit is syntactically broken most of the time. Between `if (` and
`if (x)` every intermediate state is invalid; in an editor that is the common
case, not the exception. Nothing here had ever asked what happens then.

tree-sitter answers by recovering: it inserts a zero-width MISSING node, wraps
what it cannot place in ERROR, and returns one root spanning the whole file, so
an editor always has a tree to highlight. This asks what we return beside it.

  python3 tool/recover.py            the table
  python3 tool/recover.py --json     the same, machine-readable
  python3 tool/recover.py --show=NAME    both trees for one fixture

Fixtures live in `research/joinery/broken/`, one deliberate break per file in the
four grammars that are byte-exact on valid input, so a difference here is
recovery and never a parser that could not read the language anyway.
"""

import json
import os
import re
import sys
from pathlib import Path
from typing import NamedTuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
import differential as D  # noqa: E402
from stamp import ask as ask_one  # noqa: E402
from stamp import furthest, take  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
BROKEN = ROOT / "research" / "joinery" / "broken"
VALID = ROOT / "research" / "joinery" / "valid"
BIN = Path(os.environ.get("JOINTS_BIN", ROOT / "zig-out" / "bin" / "joints"))

USAGE = """\
recover.py - what each parser does with a file that is broken

usage:
  recover.py              the table, one row per fixture
  recover.py --valid      the inverse: valid input we refuse
  recover.py --show=NAME  both parsers' answers for one fixture
  recover.py --json       machine output
  recover.py --list       the fixtures
"""

# `(program [0, 0] - [5, 0]` on their first tree line; the root's span is the
# question, since a root that stops short is a parser that gave up.
SPAN = re.compile(r"^\((\w+) \[(\d+), (\d+)\] - \[(\d+), (\d+)\]")
# Their summary line carries the repairs: `(MISSING ")" [1, 12] - [1, 12])`.
MISSING = re.compile(r"\(MISSING ")
# A recovered parse still names its first stop, because that is where reading
# got hard; the count is the only thing that says reading went on. Reading the
# stop and not the count is what made this tool call twenty of twenty-five
# fixtures stopped-at-the-break while the forest plainly continued past it.


class Row(NamedTuple):
    name: str
    size: int
    their_root: str
    their_covered: int      # bytes the root spans
    their_errors: int
    their_missing: int
    our_furthest: int       # last byte any root in our forest covers
    our_reached: int
    our_roots: int
    our_kind: str
    our_verdict: str
    our_mends: int

    def as_dict(self) -> dict:
        return self._asdict()


def theirs(lang: Path, src: Path) -> tuple[str, int, int, int, str]:
    """Their tree, and how much of the file it accounts for."""
    body, aside = D.oracle_full(lang, src)
    at = D.Lines(src.read_bytes())
    root, covered = "none", 0
    if m := SPAN.search(body):
        root = m[1]
        covered = at.off(int(m[4]), int(m[5])) - at.off(int(m[2]), int(m[3]))
    # ERROR is a node in the tree; MISSING is announced on the summary line only.
    errors = len(re.findall(r"\(ERROR ", body))
    missing = len(MISSING.findall(body)) + len(MISSING.findall(aside))
    return root, covered, errors, missing, body


def spans(mark) -> int:
    """The fourth reader of tree-sitter's output, driven where the other three are.

    `differential.py spans` gates `xml_tree`, `cst_tree` and `graft_fields`
    against every multi-row shape their printers care about, because two of the
    three broke at a newline. `theirs` above reads a *third* printer - the
    default s-expression one - and nobody had ever pointed the fixtures at it.
    Its claim is that a node spanning rows is still one line of that printer's
    output, so a span cannot change the root's extent or invent an ERROR; this
    is that claim being tested rather than assumed.

    Every fixture is valid javascript, so the expected answer is known without
    running anything: one `program` root covering the file, no ERROR, no MISSING.
    """
    lang = D.oracle_home("javascript")
    D.oracle_build(lang, D.GRAMMARS / "javascript.json")
    rows, bad = [], 0
    for src in sorted(D.SPANS.glob("*.js")):
        size = src.stat().st_size
        try:
            root, covered, errors, missing, _ = theirs(lang, src)
            ok = root == "program" and covered == size and not errors and not missing
            said = (f"{root} {covered}/{size}"
                    + (f" · {errors} ERR" if errors else "")
                    + (f" · {missing} MISS" if missing else ""))
        except (OSError, ValueError) as e:
            ok, said = False, f"BROKE: {e}"
        bad += not ok
        rows.append((src.stem, said, "ok" if ok else "WRONG"))
    print(f"\n{'fixture':<34}{'their root':<30}reads")
    print("-" * 74)
    for name, said, how in rows:
        print(f"{name:<34}{said:<30}{how}")
    print(f"\n{len(rows) - bad}/{len(rows)} span shapes read correctly by the "
          "s-expression reader")
    print(mark.line(), file=sys.stderr)
    return 1 if bad else 0


def ours(grammar: Path, src: Path) -> tuple[int, int, str, str, str, int]:
    """Ours, and where it stopped.

    Four verdicts now, and the difference between them is the finding rather
    than noise. `accepted` read to the end and closed. **`truncated` read every
    byte and never closed** - the lexer got all the way through and no root
    covered the file, which is a different failure from running into a byte it
    could not read, and flattening the two would libel the parser. **`mended`
    hit a wall, put the stack down and kept reading**; it names its first stop
    because that is where the trouble began, so `stray byte at N, mended 3` has
    to be read as recovered and not as stopped. Only a bare `stray byte at N`
    with no count stops at N and never looks at byte N+1.
    """
    # This file's own reading of a verdict was the first to learn that `mended`
    # is not `stopped`; the whole exchange now lives in `stamp`, so the census
    # and the breadth sweep cannot go on getting it wrong separately.
    end = ask_one(BIN, grammar, src, tree=True)
    return end.reach, end.roots, end.verdict, end.tree, end.kind, end.mends


def fixtures(only: str = "", where: Path = BROKEN) -> list[tuple[str, Path, Path, Path]]:
    out = []
    for src in sorted(where.rglob("*")):
        if src.is_dir() or src.name == "README.md":
            continue
        lang = src.parent.name
        name = f"{lang}/{src.stem}"
        if only and only not in name:
            continue
        out.append((name, D.GRAMMARS / f"{lang}.json", D.oracle_home(lang), src))
    return out


def measure(name: str, grammar: Path, lang: Path, src: Path) -> Row:
    D.oracle_build(lang, grammar)
    root, covered, errors, missing, body = theirs(lang, src)
    reached, roots, verdict, tree, kind, mends = ours(grammar, src)
    size = src.stat().st_size
    # The question an editor actually asks is not "did it fail" - it is "is the
    # code *after* my caret still highlighted". So: the furthest byte any root in
    # our forest covers, which on a `truncated` parse is not the same as where
    # the parse stopped being one tree.
    end = furthest(tree)
    return Row(name, size, root, covered, errors, missing, end,
               end if reached < 0 else reached, roots, kind, verdict, mends)


def valid(mark) -> int:
    """The other half of the question, and the one nobody asked.

    `broken/` measures recovery. This measures the opposite failure: input a
    person would write on purpose, which tree-sitter accepts with no ERROR and
    no MISSING, and which we refuse. A row here is an ordinary differential
    finding the corpus never thought to ask - not a recovery gap, and not
    excusable by one.
    """
    picked = fixtures(where=VALID)
    D.warm([D.Case(n, g, la, s, "valid") for n, g, la, s in picked])
    rows = [measure(*f) for f in picked]
    print(f"{'fixture':<32}{'bytes':>6}   {'tree-sitter':<26}joints")
    print("-" * 92)
    for r in rows:
        clean = r.their_errors == 0 and r.their_missing == 0 and r.their_covered >= r.size - 1
        their = "accepts, clean" if clean else f"{r.their_errors} ERR · {r.their_missing} MISS"
        print(f"{r.name:<32}{r.size:>6}   {their:<26}{r.our_kind} · {r.their_root} "
              f"· {r.our_verdict}")
    theirs_ok = [r for r in rows if r.their_errors == 0 and r.their_missing == 0]
    ours_ok = [r for r in theirs_ok if r.our_kind == "whole"]
    print(f"\n{len(rows)} fixtures of valid input · tree-sitter accepts {len(theirs_ok)} "
          f"cleanly · we accept {len(ours_ok)}")
    if len(ours_ok) < len(theirs_ok):
        print(f"{len(theirs_ok) - len(ours_ok)} differential finding(s) on input that was "
              "never broken; see research/joinery/valid/README.md for the cause")
    print(mark.line())
    return 1 if len(ours_ok) < len(theirs_ok) else 0


def show(name: str) -> int:
    got = fixtures(name)
    if not got:
        got = fixtures(name, VALID)
    if not got:
        print(f"recover.py: no fixture matches {name!r}", file=sys.stderr)
        return 2
    for nm, grammar, lang, src in got:
        D.oracle_build(lang, grammar)
        print(f"# {nm}  ({src.stat().st_size} bytes)\n")
        print(src.read_text().rstrip() + "\n")
        _, _, _, _, body = theirs(lang, src)
        print("## tree-sitter\n")
        print(body.rstrip())
        _, _, verdict, tree, _ = ours(grammar, src)
        print(f"\n## joints - {verdict}\n")
        print(tree.rstrip() or "(nothing)")
    return 0


def main(argv: list[str]) -> int:
    as_json = "--json" in argv
    only = next((a.split("=", 1)[1] for a in argv if a.startswith("--show=")), "")
    if "--help" in argv or "-h" in argv:
        print(USAGE)
        return 0
    if not BROKEN.is_dir():
        print(f"recover.py: no fixtures at {BROKEN}", file=sys.stderr)
        return 2
    if not D.oracle_ready():
        print(f"recover.py: no tree-sitter CLI at {D.TS}; "
              "`differential.py install` puts one there", file=sys.stderr)
        return 2
    if only:
        return show(only)
    if "--list" in argv:
        for name, _, _, src in fixtures():
            print(f"{name:<32} {src.stat().st_size:>5} B  {D.here(src)}")
        return 0

    mark = take(BIN)
    if "--spans" in argv:
        return spans(mark)
    if "--valid" in argv:
        return valid(mark)
    picked = fixtures()
    D.warm([D.Case(n, g, la, s, "broken") for n, g, la, s in picked])
    rows = [measure(*f) for f in picked]
    if as_json:
        print(json.dumps({"stamp": mark.as_dict(),
                          "fixture": [r.as_dict() for r in rows]}, indent=2))
        return 0

    print(f"{'fixture':<30}{'bytes':>6}   {'tree-sitter':<38}joints")
    print(f"{'':<30}{'':>6}   {'root · covered · ERROR · MISSING':<38}"
          "verdict · forest covers · roots")
    print("-" * 112)
    for r in rows:
        their = (f"{r.their_root} · {r.their_covered}/{r.size}"
                 f" · {r.their_errors} ERR · {r.their_missing} MISS")
        mended = f" · mended {r.our_mends}" if r.our_mends else ""
        ours_ = f"{r.our_kind} · {r.our_furthest}/{r.size} · {r.our_roots} roots{mended}"
        print(f"{r.name:<30}{r.size:>6}   {their:<38}{ours_}")

    whole = sum(1 for r in rows if r.their_covered >= r.size - 1)
    one = sum(1 for r in rows if r.our_roots == 1 and r.our_kind == "whole")
    # The question an editor asks is whether the code past the caret is still
    # highlighted, so the measure is the furthest byte the forest covers and not
    # which verdict the parse ended on. `size - 2` allows the trailing newline
    # no leaf claims.
    tail = sum(1 for r in rows if r.our_furthest >= r.size - 2)
    dark = [r for r in rows if r.our_furthest < r.size - 2]
    print(f"\n{len(rows)} broken fixtures · tree-sitter returns one root spanning the "
          f"whole file on {whole}, joints on {one}")
    print(f"tree-sitter repairs with {sum(r.their_missing for r in rows)} MISSING and "
          f"{sum(r.their_errors for r in rows)} ERROR nodes; joints emits neither and "
          f"hands back a forest of {min(r.our_roots for r in rows)}-"
          f"{max(r.our_roots for r in rows)} partial roots")
    print(f"the forest covers the code *after* the break on {tail} of {len(rows)} "
          f"· {sum(1 for r in rows if r.our_mends)} of them by mending "
          f"({sum(r.our_mends for r in rows)} mends in all)")
    if dark:
        print(f"on {len(dark)} the forest still stops short, so an editor sees nothing "
              f"past the caret: {', '.join(r.name for r in dark)}")
    print(mark.line())
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

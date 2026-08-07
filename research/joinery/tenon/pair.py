#!/usr/bin/env python3
"""Both trees for one authored witness, side by side, plus `rack`'s verdict.

This lane's defects are places both parsers **succeed** and disagree about
shape, so nothing stops, no wall is named, and `joints parse` reports
`accepted` on every one of them. The only thing that can show the defect is the
pair of trees, so the pair is what this prints - never one of them alone.

The witness files are ordinary paths rather than corpus rows, because a witness
is *built* to contain the construct and the corpus merely happens to. Swift's
`multiline_comment` fix moved the board zero bytes and a 33-byte specimen 12,
which is the whole argument for authoring these.

    python3 research/joinery/tenon/pair.py <grammar> <file>...

Exit 0 both trees came back, 1 they are identical (which for a witness is a
failure to witness anything), 2 could not run.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))

import differential as d  # noqa: E402
import plumb  # noqa: E402
import rack  # noqa: E402


def look(name: str, src: Path) -> int:
    grammar = d.GRAMMARS / f"{name}.json"
    lang = d.oracle_home(name)
    if not grammar.exists():
        print(f"pair.py: no grammar at {grammar}", file=sys.stderr)
        return 2
    with d.alone(name):
        d.oracle_build(lang, grammar)
        d.cli([str(d.TS), "parse", "-p", str(lang), "-q", str(src)], d.WORK)
    blob = src.read_bytes()
    at = d.Lines(blob)
    theirs = d.xml_tree(d.oracle_run(lang, src, "-x"), at)
    ours, stop = d.ours_run(d.Case(name, grammar, lang, src, "witness"))

    print(f"# {name}  {src.relative_to(ROOT)}  {len(blob)} bytes")
    print(f"  {blob.decode('utf-8', 'replace')!r}")
    print(f"\n  -- joints ({stop.verdict})")
    for root in ours:
        print("\n".join("    " + ln for ln in root.render()))
    print("\n  -- tree-sitter")
    print("\n".join("    " + ln for ln in theirs.named_only().render()))

    # `rack`'s own reading of the same file, so a claim about the number and a
    # claim about the tree are never taken from two different runs.
    case = plumb.Case(name, grammar, lang, src)
    seen = rack.measure(case, top=8)
    if seen is None or seen.why:
        print(f"\n  rack: no verdict{f' — {seen.why}' if seen else ''}")
    else:
        print(f"\n  rack: {seen.built} built · {seen.square} square · {seen.askew} askew"
              f" · {seen.racked} racked · {seen.blind} unjudged"
              f" · brackets {seen.shared}/{seen.their_nodes}")
        for w in seen.worst:
            text = blob[w.start:min(w.end, w.start + 24)].decode("utf-8", "replace")
            print(f"    [{w.start}, {w.end}) {w.width:>3}b {w.kind:<7} at {w.depth}"
                  f"  ours {w.ours:<28} theirs {w.theirs:<28} {text!r}")
    # Named-only on BOTH sides. The oracle's XML carries no anonymous nodes, so
    # comparing our full tree against its named one reports `differ` on every
    # witness that has a bracket in it - which is every witness here. The first
    # four controls this file was pointed at all read `differ` beside a rack row
    # of `0 racked · 0 askew`, and the rack row was the honest one.
    same = len(ours) == 1 and d.same(ours[0].named_only(), theirs.named_only())
    print(f"\n  trees {'IDENTICAL — this witness witnesses nothing' if same else 'differ'}\n")
    return 1 if same else 0


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    if not d.oracle_ready():
        print(f"pair.py: no tree-sitter CLI at {d.TS}", file=sys.stderr)
        return 2
    bad = 0
    for leaf in argv[1:]:
        bad |= look(argv[0], Path(leaf).resolve())
    return bad


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Minimal pairs for C++'s call-versus-declaration reading. Read-only.

`ledger.cpp` answers "what is wrong" and cannot answer "what is the *smallest*
input that is wrong", because one file confounds every construct in it. Each
row below differs from the one above it in about one token, so a verdict that
moves names the token that moved it.

Both trees come from `plumb.read`, which is the pair `rack.py` judges, so
"our roots" here and "our roots" on the board are one definition rather than
two that agree today. The fixtures are written under `.local/` and never under
`upstream/sources/` or the ledger corpus, so no board number moves because this
file exists - the rule `specimen.py verify` asserts for the specimen tier.

    python3 research/joinery/cpp/vexing.py            every probe, one line each
    python3 research/joinery/cpp/vexing.py --tree N   probe N's forest, and theirs
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))

import plumb  # noqa: E402

HOME = ROOT / ".local" / "cpplane" / "probe"

# (label, source). Each differs from its neighbour in roughly one token.
PROBE: tuple[tuple[str, str], ...] = (
    ("call, identifier arg", "void g() { f(y); }\n"),
    ("call, string arg", 'void g() { f("x"); }\n'),
    ("call, integer arg", "void g() { f(1); }\n"),
    ("call, two identifier args", "void g() { f(y, z); }\n"),
    ("call, ident + string", 'void g() { f(y, "x"); }\n'),
    ("method call, string arg", 'void g(A a) { a.f("x"); }\n'),
    ("qualified call, string arg", 'void g() { std::f("x"); }\n'),
    ("a declaration, really", "void g() { int f(y); }\n"),
    ("class, no call", "class A {\n public:\n  A() {}\n  int p(int v) { return v; }\n"
                       " private:\n  int r_;\n};\n"),
    ("class, call with ident arg", "class A {\n public:\n  A() { p(1); }\n"
                                   "  int p(int v) { return v; }\n private:\n  int r_;\n};\n"),
    ("class, call with string arg", 'class A {\n public:\n  A() { p("s"); }\n'
                                    "  int p(int v) { return v; }\n private:\n  int r_;\n};\n"),
    ("main alone", "int main() { return 0; }\n"),
    ("class then main", "class A { public:\n  int p(int v) { return v; }\n};\n"
                        "int main() { return 0; }\n"),
    ("class with string call, then main",
     'class A { public:\n  A() { p("s"); }\n  int p(int v) { return v; }\n};\n'
     "int main() { return 0; }\n"),
)


def cpp() -> plumb.Case:
    for case in plumb.slate():
        if case.name == "cpp":
            return case
    raise SystemExit("no cpp row on the slate")


def sketch(nodes: list[plumb.Node], depth: int) -> list[str]:
    return [n.name for n in nodes if n.depth == depth]


def one(i: int, label: str, text: str, base: plumb.Case, show: bool) -> None:
    HOME.mkdir(parents=True, exist_ok=True)
    path = HOME / f"probe{i:02d}.cpp"
    path.write_text(text)
    saw = plumb.read(base._replace(source=path))
    print(f"\n[{i:2}] {label}\n     {text.strip()!r}")
    if saw is None:
        print("     no folio for cpp in JOINTS_WORK")
        return
    if not saw.ok:
        print(f"     refused: {saw.why}")
        return
    ours, theirs = sketch(saw.mine, 0), sketch(saw.theirs, 0)
    kids = sketch(saw.theirs, 1)
    print(f"     ours  ({len(ours):2}): {', '.join(ours)}")
    print(f"     their ({len(theirs):2}): {', '.join(theirs)}"
          + (f"  -> {', '.join(kids)}" if len(theirs) == 1 else ""))
    print(f"     built : {saw.built}/{len(saw.blob)}"
          + ("   MATCH" if ours == theirs else "   FORK"))
    if show:
        for who, nodes in (("ours", saw.mine), ("theirs", saw.theirs)):
            print(f"\n     {who}:")
            for n in nodes:
                print(f"       {'  ' * n.depth}{n.name} [{n.start}:{n.end}]")


def main(argv: list[str]) -> int:
    show = int(argv[argv.index("--tree") + 1]) if "--tree" in argv else -1
    base = cpp()
    for i, (label, text) in enumerate(PROBE):
        if show < 0 or i == show:
            one(i, label, text, base, show >= 0)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

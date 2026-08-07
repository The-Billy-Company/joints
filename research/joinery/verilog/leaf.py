#!/usr/bin/env python3
"""The leaf gap: bytes a real SystemVerilog lexer names and we stand nothing on.

`judge.py --coverage` prints the headline — joints leafs ~59% of the bytes
Verible calls tokens, tree-sitter 98.8%, and our leaf set is a strict subset of
theirs. That is a deficit with no shape. This gives it one.

Verible's raw token stream is a ground truth for *there is a token here* that
needs no parse tree and no agreement about shape: every token carries a tag and
a byte range, and it lexes the text as written (no preprocessor), which is
exactly what both trees do. So the deficit partitions two ways with no
judgement calls in it:

    by TAG     which lexical category we fail to stand on
    by REGION  contiguous runs of deficit, widest first, with their text

    python3 research/joinery/verilog/leaf.py            # both partitions
    python3 research/joinery/verilog/leaf.py --tag=SymbolIdentifier
    python3 research/joinery/verilog/leaf.py --json
    python3 research/joinery/verilog/leaf.py --grammar=verilog --source=FILE

`--source` is the whole point of the caveat: verilog on this board is one 94 KB
file, and a repair tuned to it is not a repair to verilog. Point this at a
second real source and the two answers are the report.
"""
from __future__ import annotations

import argparse
import collections
import json
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))
sys.path.insert(0, str(ROOT / "research" / "joinery" / "judge"))

import judge  # noqa: E402
import plumb  # noqa: E402
import stamp  # noqa: E402


def tokens(src: Path, size: int) -> list[tuple[str, int, int]] | None:
    """Verible's raw stream as (tag, start, end), blanks dropped."""
    exe = next(judge.JUDGE.glob("verible-*/bin/verible-verilog-syntax"), None)
    if exe is None:
        return None
    import subprocess

    got = subprocess.run([str(exe), "--export_json", "--printrawtokens", str(src)],
                         capture_output=True, text=True)
    data = list(json.loads(got.stdout).values())[0]
    out = []
    for t in data["rawtokens"]:
        a, b = max(t["start"], 0), min(t["end"], size)
        if b > a and t["tag"] not in judge.BLANK:
            out.append((t["tag"], a, b))
    return out


#: An element of a concatenation that is exactly one selected identifier, and
#: nothing else. Hierarchical names included, since `m.a[3]` walls the same way.
LONE_SELECT = re.compile(r"^[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*\s*\[[^\[\]]*\]$")


def elements(text: str) -> list[tuple[int, int, int]]:
    """Top-level element spans of every `{...}` group, each with its group's `}`.

    A hand-written scan rather than a parse, because the thing being measured is
    what happens when the parse is wrong: asking joints to find its own
    concatenations would make the counterfactual a function of the defect. It
    knows only what a lexer knows — strings, both comment shapes, and the three
    bracket pairs — which is enough to say where one element of a brace group
    ends, and admits it knows nothing else by matching a conservative pattern.
    """
    out: list[tuple[int, int, int]] = []
    stack: list[int] = []  # start of the element open at each brace depth
    held: list[list[tuple[int, int]]] = []  # its elements, until the `}` dates them
    depth = 0  # inside () or [], where a comma separates nothing of ours
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            i = text.find("\n", i)
            if i < 0:
                break
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            i = text.find("*/", i)
            if i < 0:
                break
            i += 1
        elif c == '"':
            i += 1
            while i < n and text[i] != '"':
                i += 2 if text[i] == "\\" else 1
        elif c in "([":
            depth += 1
        elif c in ")]":
            depth -= 1
        elif c == "{":
            stack.append(i + 1)
            held.append([])
        elif c == "}" and stack:
            held[-1].append((stack.pop(), i))
            out += [(a, b, i) for a, b in held.pop()]
        elif c == "," and stack and depth == 0:
            held[-1].append((stack[-1], i))
            stack[-1] = i + 1
        i += 1
    return out


def assigned(text: str, close: int) -> bool:
    """Is the `{...}` closing at `close` the target of an assignment?

    `{a[3]} = x` and `{a[3]} <= x` are lvalues, where a parenthesis is not legal
    verilog and rewriting one produces a wall of the counterfactual's own making
    rather than a measurement of ours. Conservative on purpose: anything that
    could be an assignment is left alone, so the experiment can only understate.
    """
    i, n = close + 1, len(text)
    while i < n and (text[i].isspace() or text.startswith("//", i) or text.startswith("/*", i)):
        i = (text.find("\n", i) if text.startswith("//", i)
             else text.find("*/", i) + 1 if text.startswith("/*", i) else i + 1)
        if i <= 0:
            return False
    return text.startswith("<=", i) or (text.startswith("=", i)
                                        and not text.startswith("==", i))


def parenthesise(text: str) -> tuple[str, int]:
    """Wrap every concatenation element that is a lone select in parentheses.

    The counterfactual for the wall this dossier names, and the narrowest one
    that exists: `{a[3]}` refuses and `{(a[3])}` is accepted, with the same
    tokens in the same order and one pair added. Everything else in the file is
    byte-identical, so whatever the leaf share does is what this construct was
    costing and not what a preprocessor or a comment sweep would have paid.

    Concatenations in lvalue position are left alone — see `assigned`. Rewriting
    one is not legal verilog, and an experiment that produces its own wall is
    measuring itself.
    """
    edits = [(a, b) for a, b, close in elements(text)
             if LONE_SELECT.match(text[a:b].strip()) and not assigned(text, close)]
    for a, b in sorted(edits, reverse=True):
        body = text[a:b]
        lead = len(body) - len(body.lstrip())
        text = text[:a + lead] + "(" + body.strip() + ")" + text[b - (len(body) - len(body.rstrip())):]
    return text, len(edits)


def runs(flags: list[bool] | bytearray) -> list[tuple[int, int]]:
    out, run = [], None
    for i, on in enumerate(flags):
        if on and run is None:
            run = i
        elif not on and run is not None:
            out.append((run, i))
            run = None
    if run is not None:
        out.append((run, len(flags)))
    return out


class Gap:
    """One measurement of the leaf gap over one source."""

    def __init__(self, name: str, source: Path | None = None):
        case = next(c for c in plumb.slate() if c.name == name)
        if source is not None:
            case = case._replace(source=source)
        self.case = case
        saw = plumb.read(case)
        if saw is None:
            raise SystemExit(f"leaf.py: no folio for {name} on this arm"
                             f" — `python3 tool/pin.py arm <name>`")
        self.saw = saw
        self.size = len(saw.blob)
        self.ours, self.theirs = judge.masks(saw, self.size)
        self.tok = tokens(case.source, self.size)
        # One judge is enough to price a deficit, and which one is present is a
        # property of the machine rather than of the question. Verible needs no
        # oracle seat and no grammar checkout, so a source tree-sitter cannot be
        # pointed at is still measurable - and saying so beats refusing, which is
        # what made a second verilog file look impossible to obtain.
        self.blind = saw.why if self.tok is None else ""
        if self.blind:
            raise SystemExit(f"leaf.py: {name}: {saw.why}, and no verible either")

    @property
    def yardstick(self) -> bytearray | None:
        if self.tok is None:
            return None
        m = bytearray(self.size)
        for _, a, b in self.tok:
            m[a:b] = b"\1" * (b - a)
        return m

    def deficit(self) -> list[bool]:
        """Bytes some judge names and we stand no leaf on.

        Union of the two yardsticks that exist, so the answer does not depend on
        which one is installed: a byte tree-sitter leafs, or a byte Verible
        calls a token. Both are `there is a token here` claims; neither needs a
        shape to agree with.
        """
        ref = self.yardstick
        return [not self.ours[p] and (bool(self.theirs[p]) or bool(ref and ref[p]))
                for p in range(self.size)]

    def reached(self) -> bytearray:
        """Bytes under some node of ours, leaf or not."""
        m = bytearray(self.size)
        for n in self.saw.mine:
            a, b = max(n.start, 0), min(n.end, self.size)
            if b > a:
                m[a:b] = b"\1" * (b - a)
        return m

    def whereabouts(self) -> tuple[int, int]:
        """The deficit split by whether we ever reached the byte.

        The question that decides which half of the machine is at fault, and the
        one every tag histogram hides. A byte inside a node we built and under no
        leaf is a *shape* failure — the parse stood there and put nothing under
        it. A byte outside every node is a *reach* failure: recovery walked past
        it and the tree has no opinion about it at all. They have nothing in
        common but the column they land in.
        """
        want, seen = self.deficit(), self.reached()
        inside = sum(1 for p in range(self.size) if want[p] and seen[p])
        return inside, sum(want) - inside

    def recovery(self) -> tuple[int, int]:
        """(mends, bytes those mends stepped over), off the parse's own summary.

        Read back from the line the binary already prints rather than recomputed,
        so the two can never disagree about a word they both spell `skipped`.
        """
        import subprocess

        got = subprocess.run([str(plumb.BIN), "parse",
                              str(plumb.WORK / f"{self.case.name}.folio"),
                              str(self.case.source)], capture_output=True, text=True)
        m = re.search(r"mended (\d+) over (\d+)B", got.stderr)
        return (int(m[1]), int(m[2])) if m else (0, 0)

    def by_tag(self) -> list[tuple[str, int, int, int]]:
        """(tag, deficit bytes, token bytes, tokens wholly missed)."""
        if self.tok is None:
            return []
        want = self.deficit()
        held: dict[str, list[int]] = collections.defaultdict(lambda: [0, 0, 0])
        for tag, a, b in self.tok:
            miss = sum(want[a:b])
            row = held[tag]
            row[0] += miss
            row[1] += b - a
            row[2] += miss == b - a
        return sorted(((t, *v) for t, v in held.items()), key=lambda r: -r[1])

    def by_region(self, top: int = 20) -> list[tuple[int, int, str]]:
        out = []
        for a, b in sorted(runs(self.deficit()), key=lambda r: r[0] - r[1])[:top]:
            out.append((a, b, self.saw.blob[a:b].decode("utf-8", "replace")))
        return out


def report(g: Gap, top: int, only: str, as_json: bool) -> int:
    want = g.deficit()
    gap = sum(want)
    ref = g.yardstick
    rows = g.by_tag()
    if as_json:
        print(json.dumps({
            "grammar": g.case.name, "source": str(g.case.source), "size": g.size,
            "ours": sum(g.ours), "theirs": sum(g.theirs),
            "on_token": covered(g), "share": round(share(g), 2),
            "token_bytes": sum(ref) if ref else None, "deficit": gap,
            "tag": [{"tag": t, "deficit": d, "bytes": n, "whole": w} for t, d, n, w in rows],
            "region": [{"start": a, "end": b, "text": s} for a, b, s in g.by_region(top)],
        }, indent=2))
        return 0

    print(f"\n# leaf gap — {g.case.name}  {g.case.source.name}  {g.size} B")
    if ref is not None:
        print(f"  verible: {sum(ref)} B carry a non-blank token, in {len(g.tok)} tokens")
    print(f"  joints leafs {sum(g.ours)} B · tree-sitter {sum(g.theirs)} B"
          f" · DEFICIT {gap} B")
    if ref is not None:
        print(f"  of verible's token bytes we stand a leaf on {covered(g)}"
              f" — {share(g):.1f}%")
    inside, never = g.whereabouts()
    print(f"  of that deficit: {inside} B under a node we built with no leaf on it,"
          f" {never} B under no node at all")
    mends, skipped = g.recovery()
    if mends:
        print(f"  recovery stepped over {skipped} B in {mends} mend(s)"
              f" — {skipped / max(never, 1) * 100:.0f}% of the unreached half")

    if only:
        sel = [(t, a, b) for t, a, b in g.tok if t == only]
        print(f"\n# every `{only}` token we do not wholly leaf ({len(sel)} total)")
        for t, a, b in sel:
            miss = sum(want[a:b])
            if miss:
                print(f"  [{a:>6},{b:>6}) {miss:>3}/{b - a:>3} B  "
                      f"{g.saw.blob[a:b].decode('utf-8', 'replace')!r}")
        return 0

    print(f"\n  {'verible tag':<24}{'deficit':>9}{'tok B':>8}{'share':>8}{'whole miss':>12}")
    print("  " + "-" * 61)
    for t, d, n, w in rows:
        if d:
            print(f"  {t:<24}{d:>9}{n:>8}{d / n * 100:>7.0f}%{w:>12}")
    clean = [(t, n) for t, d, n, _ in rows if not d]
    if clean:
        print(f"\n  wholly leafed ({len(clean)} tags): "
              + " · ".join(f"{t} {n}" for t, n in clean[:12]))

    print(f"\n# widest contiguous deficit runs")
    for a, b, s in g.by_region(top):
        print(f"  [{a:>6},{b:>6}) {b - a:>5} B  {s[:64]!r}")
    return 0


def share(g: Gap) -> float:
    """Of the bytes the yardstick calls a token, the fraction we stand a leaf on.

    The intersection, not `our leaf bytes over their token bytes` — that ratio
    was the first thing written here and it can exceed 100%, because a leaf span
    may cover trivia the lexer calls blank. A coverage number that can read 100.2
    is not a coverage number, and it flatters exactly the arm a counterfactual is
    trying to price.
    """
    ref = g.yardstick
    if not ref or not (tok := sum(ref)):
        return 0.0
    return covered(g) / tok * 100


def covered(g: Gap) -> int:
    """Token bytes we stand a leaf on."""
    ref = g.yardstick
    return sum(1 for p in range(g.size) if ref[p] and g.ours[p]) if ref else 0


def ablate(g: Gap, as_json: bool) -> int:
    """The lone-select counterfactual, priced against the file it came from.

    Not a repair and not a proposal to write verilog differently: it is the one
    experiment that can say *no*. If parenthesising the construct this dossier
    blames moves the leaf share by nothing, the construct was not the cost and
    the diagnosis is wrong.
    """
    text = g.case.source.read_text()
    fixed, edits = parenthesise(text)
    with tempfile.TemporaryDirectory() as tmp:
        alt = Path(tmp) / g.case.source.name
        alt.write_text(fixed)
        after = Gap(g.case.name, alt)
        rows = [("as written", g), ("lone selects parenthesised", after)]
        if as_json:
            print(json.dumps({
                "grammar": g.case.name, "source": str(g.case.source),
                "edits": edits,
                "arm": [{"arm": k, "size": x.size, "leaf": sum(x.ours),
                         "on_token": covered(x),
                         "token_bytes": sum(x.yardstick or b""),
                         "share": share(x), "deficit": sum(x.deficit())}
                        for k, x in rows],
                "delta_share": share(after) - share(g),
            }, indent=2))
            return 0
        print(f"\n# lone-select counterfactual — {g.case.name}  {g.case.source.name}")
        print(f"  {edits} concatenation element(s) rewritten `x[s]` -> `(x[s])`,"
              f" nothing else touched")
        print(f"\n  {'arm':<30}{'on token B':>11}{'token B':>9}{'share':>8}{'deficit':>9}")
        print("  " + "-" * 67)
        for k, x in rows:
            print(f"  {k:<30}{covered(x):>11}{sum(x.yardstick or b''):>9}"
                  f"{share(x):>7.1f}%{sum(x.deficit()):>9}")
        print(f"\n  delta {share(after) - share(g):+.1f} points of Verible's token bytes")
    return 0


#: The floor this gap may not sink back through, and the only file in this
#: folder a passing run reads. Committed so the number is a claim somebody made
#: rather than whatever the last measurement happened to be.
FLOOR = Path(__file__).with_name("leaf.floor.json")


def digest(src: Path) -> str:
    """A second source is only the file it was measured on if it hashes so."""
    import hashlib

    return hashlib.sha256(src.read_bytes()).hexdigest()


def verdict(grammar: str, src: Path) -> str:
    """`accepted` or `refused`, read off the parse's own last word."""
    import subprocess

    got = subprocess.run([str(plumb.BIN), "parse", str(plumb.WORK / f"{grammar}.folio"),
                          str(src)], capture_output=True, text=True)
    return "accepted" if ": accepted" in got.stderr else "refused"


def check(as_json: bool) -> int:
    """Hold every grammar with an external token yardstick to a committed floor.

    The gap this dossier is about was invisible for the life of the project
    because every column on the board is computed from our own tree: `standing`
    and `damage` read top-level root spans, `square` reads agreement with an
    oracle that had gone blind over the whole file, and none of them can see a
    token nobody stood on. An outside lexer can, it needs no agreement about
    shape, and it is the one number directly comparable to tree-sitter.

    A grammar earns a row here by having a yardstick installed; a missing
    yardstick skips rather than passes, because a check that goes green when its
    instrument is absent is a check that reports on the machine.
    """
    floor = json.loads(FLOOR.read_text())
    rows, bad, skipped = [], 0, []
    for name, want in sorted(floor["floor"].items()):
        for row in want:
            src = ROOT / row["source"] if row.get("source") else None
            if src is not None and not src.exists():
                skipped.append((name, row["source"], "absent — fetch it from `url`"))
                continue
            if src is not None and digest(src) != row["sha256"]:
                rows.append((name, src.name, 0.0, row["share"], False, "DIGEST MOVED"))
                bad += 1
                continue
            try:
                g = Gap(name, src)
            except SystemExit as why:
                # A machine without this grammar pressed, or without verible, is
                # a machine that cannot answer - which is not the same as an
                # answer. Skip it by name and keep the other rows honest.
                skipped.append((name, src.name if src else "—", str(why).split(": ")[-1]))
                continue
            got = share(g)
            ok = got + 1e-9 >= row["share"]
            rows.append((name, g.case.source.name, got, row["share"], ok, ""))
            bad += not ok

    seen = []
    for name, want in sorted(floor["witness"].items()):
        if plumb.folio_for(name, plumb.WORK) is None:
            skipped.append((name, "witness/*", "no folio on this arm"))
            continue
        for w in want:
            src = FLOOR.parent / w["file"]
            got = verdict(name, src)
            seen.append((Path(w["file"]).name, w["verdict"], got, got == w["verdict"]))
            bad += not seen[-1][3]

    if as_json:
        print(json.dumps({"row": [{"grammar": n, "source": s, "share": round(v, 2),
                                   "floor": f, "ok": ok, "why": why}
                                  for n, s, v, f, ok, why in rows],
                          "witness": [{"file": f, "want": w, "got": got, "ok": ok}
                                      for f, w, got, ok in seen],
                          "skipped": [{"grammar": n, "source": s, "why": w}
                                      for n, s, w in skipped],
                          "failed": bad}, indent=2))
        return 1 if bad else 0
    print(f"\n# leaf coverage against an external token yardstick")
    print(f"  {'grammar':<10}{'source':<18}{'share':>8}{'floor':>8}  ")
    print("  " + "-" * 50)
    for n, s, v, f, ok, why in rows:
        print(f"  {n:<10}{s:<18}{v:>7.1f}%{f:>7.1f}%  {why or ('ok' if ok else 'BELOW FLOOR')}")
    for n, s, why in skipped:
        print(f"  {n:<10}{s:<18}{'—':>8}{'—':>8}  {why} — not a pass")
    print(f"\n# witnesses")
    for f, w, got, ok in seen:
        note = "ok" if ok else (
            "REPAIRED — flip the manifest row and keep it as the guard"
            if w == "refused" else "REGRESSED")
        print(f"  {f:<36}want {w:<9}got {got:<9}{note}")
    if bad:
        print(f"\n  {bad} row(s) failed. Fix the parse, or say in the same commit"
              f"\n  why the floor or a verdict moved and move it deliberately.")
    return 1 if bad else 0


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--grammar", default="verilog")
    p.add_argument("--source", type=Path)
    p.add_argument("--tag", default="")
    p.add_argument("--top", type=int, default=20)
    p.add_argument("--ablate", action="store_true",
                   help="price the lone-select wall by parenthesising it away")
    p.add_argument("--check", action="store_true",
                   help="hold every yardsticked grammar to its committed floor")
    p.add_argument("--json", action="store_true")
    a = p.parse_args(argv)
    if a.check:
        rc = check(a.json)
        if not a.json:
            print(stamp.take(plumb.BIN).line())
        return rc
    g = Gap(a.grammar, a.source)
    rc = ablate(g, a.json) if a.ablate else report(g, a.top, a.tag, a.json)
    if not a.json:
        print(stamp.take(plumb.BIN).line())
    return rc


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

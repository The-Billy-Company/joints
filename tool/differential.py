#!/usr/bin/env python3
"""Hold outliner's tree against the tree tree-sitter actually builds.

Node names are the whole compatibility surface: every `highlights.scm` and every
editor integration in the ecosystem is keyed on them. `src/kernel/quire` builds
its tree from the naming rules as written down, and its own tests are derived by
hand from the same reading - so a misreading of those rules would be invisible
to them. Only tree-sitter can settle it. This is rung 6 of
`research/joinery/TESTING.md`.

The tree-sitter CLI is a **dev-only oracle**. Nothing in the package links,
vendors, or ships it; it is installed under `.local/differential/cli` by the
`install` verb and nowhere else. When it is absent every case skips and the run
exits 0, because a missing baseline tool is not a failing comparison.

Both sides read the *same bytes*: the oracle's parser is generated from
`upstream/grammars/<name>.json`, the file the press reads, hashed on the way in.
Comparing outliner against a differently-pinned tree-sitter grammar would make
every diff meaningless.

Three normalisations, and no others:

  * **position spelling.** tree-sitter reports `row:column` in bytes; outliner
    reports byte offsets. Both are converted to byte offsets against the source.
    Same positions, one spelling.
  * **the oracle's own three faces.** The tree is read out of `--cst`, which is
    the only format carrying anonymous node *types* (an aliased node's type and
    its text differ), and cross-checked against `--xml`, which nests
    unambiguously. If the two disagree the case refuses rather than guessing;
    the CLI's CST indentation is unreliable inside an error tree. Neither
    printer spells the field on an *anonymous* child, though tree-sitter itself
    resolves one - so the fields are recovered from the third face, `query`,
    which is the same runtime a `highlights.scm` runs through.
  * **nothing else.** A node name, a field name, and the presence of a node are
    the things under test and are never normalised. Extras and error recovery
    are known gaps and are *reported as diffs*, classified, never filtered out.

Exit 0 nothing unexplained, 1 at least one difference nobody owns yet, 2 an
error. That is the CLI's family, so a shell script can treat both the same way.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any, NamedTuple

from grammars import digest, load
from rung1 import pairs

ROOT = Path(__file__).resolve().parent.parent
GRAMMARS = ROOT / "upstream" / "grammars"
CORPUS = ROOT / "research" / "joinery" / "corpus"
WORK = ROOT / ".local" / "differential"
CLI = WORK / "cli"
TS = CLI / "node_modules" / ".bin" / "tree-sitter"
BIN = Path(os.environ.get("OUTLINER_BIN", ROOT / "zig-out" / "bin" / "outliner"))

USAGE = """\
differential.py - is outliner's tree the tree tree-sitter builds?

usage:
  differential.py run       compare every case (offline; skips if no oracle)
  differential.py show      both trees for one case, side by side
  differential.py list      the cases, and where each one's grammar comes from
  differential.py oracle    is the tree-sitter CLI here, and which version
  differential.py install   put that CLI under .local/differential (the network verb)

flags:
  --case=NAME     one case, by the name `list` prints
  --grammar=NAME  every case on one grammar
  --json          machine output, on the read verbs
  --verbose       every finding, not the first few per case
"""

# The probe grammars. Small on purpose: each one asks a single question about
# how a name is chosen, and asks it of both parsers at once. They are not
# language grammars and are not pinned - they are hand-written here, and both
# sides read this exact JSON, so a probe cannot compare two different languages.
WORD = {"type": "PATTERN", "value": "[a-z]+"}


def sym(name: str) -> dict[str, Any]:
    return {"type": "SYMBOL", "name": name}


def alias(inner: dict[str, Any], value: str, named: bool = True) -> dict[str, Any]:
    return {"type": "ALIAS", "content": inner, "named": named, "value": value}


def seq(*members: dict[str, Any]) -> dict[str, Any]:
    return {"type": "SEQ", "members": list(members)}


def grammar(name: str, rules: dict[str, Any], **rest: Any) -> dict[str, Any]:
    return {
        "name": name, "word": None, "rules": rules,
        "extras": rest.get("extras", [{"type": "PATTERN", "value": "\\s"}]),
        "conflicts": [], "precedences": [], "externals": [],
        "inline": rest.get("inline", []), "supertypes": rest.get("supertypes", []),
    }


PROBES: dict[str, tuple[dict[str, Any], str]] = {
    # The judgement call quire flagged: an alias landing on an already-visible
    # symbol. Renamed in place, or wrapped in a second node? Also an alias to a
    # string (anonymous, and its type is not its text), an alias onto a hidden
    # rule (which invents a visible node), and the same hidden rule unaliased
    # (which splices its children into the parent).
    "alias": (grammar("alias", {
        "source": seq(sym("item"), alias(sym("item"), "renamed"),
                      alias(sym("item"), "ANON", named=False),
                      alias(sym("_pair"), "lifted"), sym("_pair")),
        "_pair": seq(sym("item"), sym("item")),
        "item": WORD,
    }), "a b c d e f g"),
    # Where a field lands when the thing it is attached to is not one node: on
    # an alias, and on a hidden rule that splices two children into the parent.
    "field": (grammar("field", {
        "source": seq(
            {"type": "FIELD", "name": "head", "content": sym("item")},
            {"type": "FIELD", "name": "tail", "content": alias(sym("item"), "renamed")},
            {"type": "FIELD", "name": "both", "content": sym("_pair")},
        ),
        "_pair": seq(sym("item"), sym("item")),
        "item": WORD,
    }), "a b c d"),
    # A supertype is hidden, so it should leave no node of its own behind.
    "supertype": (grammar("supertype", {
        "source": seq(sym("_value"), sym("_value")),
        "_value": {"type": "CHOICE", "members": [sym("word"), sym("digits")]},
        "word": WORD,
        "digits": {"type": "PATTERN", "value": "[0-9]+"},
    }, supertypes=["_value"]), "abc 12"),
    # The four ways to spell one anonymous terminal inline. A bare string, a
    # `token(...)`, a `token(prec(n, ...))`, and a `token.immediate(...)` all
    # leave the same node behind in tree-sitter: the wrappers change when the
    # lexer may fire and how it ranks, not what the tree calls the result. (An
    # inline *regex* is the one that genuinely contributes no node, and
    # `src/node-types.json` next to this grammar is where tree-sitter says so.)
    # Four in one source, so a run says which spellings survive rather than
    # that something somewhere went missing.
    "wrapped": (grammar("wrapped", {
        "source": seq({"type": "STRING", "value": "("}, sym("item"),
                      {"type": "TOKEN", "content": {"type": "STRING", "value": ")"}},
                      {"type": "TOKEN", "content": {"type": "PREC", "value": 1,
                                                    "content": {"type": "STRING", "value": "!"}}},
                      {"type": "IMMEDIATE_TOKEN", "content": {"type": "STRING", "value": "]"}}),
        "item": WORD,
    }), "(ab ) !]"),
    "twin": (grammar("twin", {
        "source": seq({"type": "STRING", "value": "|"},
                      {"type": "REPEAT", "content": alias(
                          {"type": "IMMEDIATE_TOKEN", "content": {"type": "PATTERN", "value": "[^|]+"}},
                          "content")},
                      {"type": "IMMEDIATE_TOKEN", "content": {"type": "STRING", "value": "|"}}),
    }), "|ab|"),
    # The known gap, on its own: a visible extra between two tokens.
    "extras": (grammar("extras", {
        "source": {"type": "REPEAT1", "content": sym("item")},
        "item": WORD,
        "comment": {"type": "TOKEN", "content": seq(
            {"type": "STRING", "value": "#"}, {"type": "PATTERN", "value": "[^\\n]*"})},
    }, extras=[{"type": "PATTERN", "value": "\\s"}, sym("comment")]), "a # note\nb"),
}

# Small sources over the pinned grammars, written next to the run and keyed by
# the grammar they belong to. The corpus is one shape of each language; these
# are the shapes it does not happen to contain, and the two-line reproducers a
# whole-corpus difference boiled down to.
SOURCES: dict[str, str] = {
    "json/flat.json": '{"a": 1, "b": [true, false, null]}',
    "json/nested.json": '{"a": {"b": {"c": [[1], [2, 3]]}}, "d": []}\n',
    "json/escapes.json": '{"k\\"\\\\\\n": "\\u00e9\\t"}',
    "json/unicode.json": '{"\u00e9\u4e2d": "\U0001f600"}',
    "json/comment.json": '{"a": 1, /* between */ "b": 2}\n// trailing\n',
    "json/truncated.json": '{"a": 1, "b": [2,',
    "json/scalar.json": "  42  \n",
    "c/include.c": "#include <stdio.h>\nint x;\n",
    "go/string.go": 'package main\n\nimport "fmt"\n',
    "rust/generic.rs": "struct S { v: Vec<i64> }\n",
}


class Node:
    """One node of either tree, in the terms both parsers agree exist: a name,
    whether that name is a named node's or an anonymous token's, the field the
    parent reached it through, and the bytes it covers."""

    __slots__ = ("name", "named", "field", "start", "end", "kids")

    def __init__(self, name: str, named: bool, field: str | None, start: int, end: int) -> None:
        self.name, self.named, self.field = name, named, field
        self.start, self.end, self.kids = start, end, []

    @property
    def key(self) -> tuple[str | None, str, bool]:
        """What makes two nodes the same node for alignment. Deliberately not
        the span: a node in the right place with the wrong extent must read as
        one node with a bad span, not as an insert next to a delete."""
        return (self.field, self.name, self.named)

    def label(self) -> str:
        tag = self.name if self.named else f'"{self.name}"'
        return f"{self.field}: {tag}" if self.field else tag

    def count(self) -> int:
        return 1 + sum(k.count() for k in self.kids)

    def named_only(self) -> Node:
        """The tree `tree-sitter parse` prints. An anonymous node is always a
        leaf token, so dropping one whole drops nothing under it."""
        copy = Node(self.name, self.named, self.field, self.start, self.end)
        copy.kids = [k.named_only() for k in self.kids if k.named]
        return copy

    def render(self, depth: int = 0) -> list[str]:
        out = [f"{'  ' * depth}{self.label()} [{self.start}, {self.end})"]
        for k in self.kids:
            out += k.render(depth + 1)
        return out


class Lines:
    """row/column in bytes to a byte offset. tree-sitter counts columns in
    bytes, so this is arithmetic and not a decoding."""

    def __init__(self, blob: bytes) -> None:
        self.size = len(blob)
        self.starts = [0] + [i + 1 for i, b in enumerate(blob) if b == 0x0A]

    def off(self, row: int, col: int) -> int:
        base = self.starts[row] if row < len(self.starts) else self.size
        return min(base + col, self.size)


class Finding(NamedTuple):
    where: str
    kind: str  # name · named · field · span · absent · surplus · unanchored
    ours: str
    theirs: str
    owner: str  # extras · recovery · root-extent · partial · unexplained

    def line(self) -> str:
        return f"    {self.where}: {self.kind}: outliner {self.ours}, tree-sitter {self.theirs}"


class Case(NamedTuple):
    name: str
    grammar: Path  # the bytes both sides read
    lang: Path  # where the oracle's parser is generated
    source: Path
    origin: str  # corpus · case · probe


class Report(NamedTuple):
    case: Case
    mode: str  # whole · prefix · skipped
    why: str
    ours: int
    theirs: int
    findings: list[Finding]

    @property
    def unexplained(self) -> int:
        return sum(f.owner == "unexplained" for f in self.findings)

    def as_dict(self) -> dict[str, Any]:
        owners: dict[str, int] = {}
        for f in self.findings:
            owners[f.owner] = owners.get(f.owner, 0) + 1
        return {"case": self.case.name, "grammar": self.case.grammar.stem, "mode": self.mode,
                "why": self.why, "ours": self.ours, "theirs": self.theirs, "owners": owners,
                "findings": [f._asdict() for f in self.findings]}


# ---------------------------------------------------------------- reading trees

BODY = re.compile(r"^(?:([A-Za-z_]\w*): )?(.*)$", re.S)
OURS = re.compile(r"^( *)(.*) \[(\d+), (\d+)\)$")
CST = re.compile(r"^ *(\d+):(\d+) +- +(\d+):(\d+)( +)(\S.*)$")


def unquote(text: str) -> tuple[str, str]:
    """An anonymous node's name, as both printers spell it: double quoted, with
    a backslash before a quote or a backslash. tree-sitter also escapes the
    control characters, which is a difference in spelling and not in name."""
    out, i = [], 1
    while i < len(text) and text[i] != '"':
        if text[i] == "\\" and i + 1 < len(text):
            out.append({"n": "\n", "t": "\t", "r": "\r", "0": "\0"}.get(text[i + 1], text[i + 1]))
            i += 2
            continue
        out.append(text[i])
        i += 1
    return "".join(out), text[i + 1:]


def head(body: str) -> tuple[str | None, str, bool, str]:
    """`field: name` or `field: "name"`, and whatever trails it."""
    m = BODY.match(body)
    field, rest = m[1], m[2]
    if rest.startswith('"'):
        name, tail = unquote(rest)
        return field, name, False, tail
    name, _, tail = rest.partition(" ")
    return field, name, True, tail


def ours_tree(text: str) -> list[Node]:
    """`outliner parse --ranges --all`: one node a line, two spaces a level."""
    roots: list[Node] = []
    stack: list[Node] = []
    for raw in text.splitlines():
        if not raw.strip():
            continue
        m = OURS.match(raw)
        if not m:
            raise ValueError(f"cannot read outliner's own output: {raw!r}")
        depth = len(m[1]) // 2
        field, name, named, _ = head(m[2])
        node = Node(name, named, field, int(m[3]), int(m[4]))
        del stack[depth:]
        (stack[-1].kids if stack else roots).append(node)
        stack.append(node)
    return roots


def cst_tree(text: str, at: Lines) -> tuple[Node, bool]:
    """`tree-sitter parse --cst`. The only format that gives an anonymous node's
    *type* rather than its text, which is exactly what an alias to a string
    changes. Its indentation is two spaces a level, except that a node the CLI
    marks with a bullet is printed one column left of where it belongs - so a
    tree with any error in it is reported as untrustworthy and cross-checking
    against the XML is what decides whether to believe this at all."""
    roots: list[Node] = []
    stack: list[tuple[int, Node]] = []
    hurt = False
    for raw in text.splitlines():
        m = CST.match(raw)
        if not m:
            continue  # the trailing summary line, or a token's own newline
        col, body = m.start(6), m[6]
        if body.startswith("\u2022"):
            col, body, hurt = col + 1, body[1:], True
        missing = body.startswith("MISSING: ")
        if missing:
            col, body, hurt = col + len("MISSING: "), body[len("MISSING: "):], True
        field, name, named, _ = head(body)
        node = Node("MISSING " + name if missing else name, named or missing, field,
                    at.off(int(m[1]), int(m[2])), at.off(int(m[3]), int(m[4])))
        while stack and stack[-1][0] >= col:
            stack.pop()
        (stack[-1][1].kids if stack else roots).append(node)
        stack.append((col, node))
    if len(roots) != 1:
        raise ValueError(f"tree-sitter's CST has {len(roots)} roots")
    return roots[0], hurt


def xml_tree(text: str, at: Lines) -> Node:
    """`tree-sitter parse -x`. Nests unambiguously and carries fields and
    ranges, but writes anonymous nodes as bare text - so it is the independent
    check on the CST's shape rather than the tree this compares against."""
    start = text.index("<?xml")
    end = text.index("</sources>") + len("</sources>")
    source = ET.fromstring(text[start:end]).find("source")
    if source is None or len(source) != 1:
        raise ValueError("tree-sitter's XML has no single root node")

    def build(el: ET.Element) -> Node:
        a = el.attrib
        node = Node(el.tag, True, a.get("field"),
                    at.off(int(a["srow"]), int(a["scol"])), at.off(int(a["erow"]), int(a["ecol"])))
        node.kids = [build(k) for k in el]
        return node

    return build(source[0])


QPATTERN = re.compile(r"^ *pattern: (\d+)\s*$")
QCAPTURE = re.compile(r"^ *capture: \d+ - (\w+), start: \((\d+), (\d+)\), end: \((\d+), (\d+)\)")


def declared(doc: dict[str, Any], kind: str, key: str) -> list[str]:
    """Every name the grammar declares under one node kind, in a stable order.
    From the grammar, which is the contract, and never from either parser."""
    seen: dict[str, None] = {}

    def walk(node: Any) -> None:
        if isinstance(node, dict):
            if node.get("type") == kind and isinstance(node.get(key), str):
                seen.setdefault(node[key], None)
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)

    walk(doc.get("rules", {}))
    return list(seen)


def graft_fields(root: Node, lang: Path, source: Path, names: list[str], at: Lines) -> None:
    """Put back the fields the printers drop.

    `--cst` and `--xml` both leave an anonymous child bare even where the
    grammar wraps it in a `FIELD`, but `ts_node_child_by_field_name` finds it
    and so does a query - which is the surface that actually matters, since a
    `highlights.scm` is queries. So the oracle is asked in its query voice:
    one pattern per declared field, capturing the parent and the child. A
    printed field that the query contradicts raises rather than being
    overwritten; the two faces of one runtime must agree or neither is usable.
    """
    q = WORK / "query.scm"
    while names:
        q.write_text("".join(f"((_ {n}: _ @child) @parent)\n" for n in names), encoding="utf-8")
        got = subprocess.run([str(TS), "query", "-p", str(lang), str(q), str(source)],
                             capture_output=True, text=True, cwd=WORK)
        if got.returncode == 0:
            break
        # A field the grammar declares but the compiled language does not have
        # (typescript inherits rules from javascript that its own parser prunes)
        # is a field no node can be carrying. Drop it and ask again.
        gone = re.search(r'Invalid field name "(\w+)"', got.stderr)
        if not gone:
            raise ValueError(f"tree-sitter query: {gripe(got.stderr)}")
        names = [n for n in names if n != gone[1]]
    else:
        return
    table: dict[tuple[int, int, int, int], str | None] = {}
    field, hit = "", {}
    for line in got.stdout.splitlines():
        if m := QPATTERN.match(line):
            field, hit = names[int(m[1])], {}
        elif (m := QCAPTURE.match(line)) and field:
            hit[m[1]] = (at.off(int(m[2]), int(m[3])), at.off(int(m[4]), int(m[5])))
            if len(hit) == 2:
                key = (*hit["parent"], *hit["child"])
                # Two children of one parent covering the same bytes cannot be
                # told apart by span, so that key is retired rather than guessed.
                table[key] = field if table.get(key, field) == field else None
    def apply(node: Node) -> None:
        for kid in node.kids:
            want = table.get((node.start, node.end, kid.start, kid.end))
            if want is None:
                pass
            elif kid.field is None:
                kid.field = want
            elif kid.field != want:
                raise ValueError(f"tree-sitter's printer says {kid.field}, its query says {want}")
            apply(kid)

    apply(root)


def same(a: Node, b: Node) -> bool:
    return (a.key == b.key and a.start == b.start and a.end == b.end
            and len(a.kids) == len(b.kids) and all(same(x, y) for x, y in zip(a.kids, b.kids)))


# ------------------------------------------------------------------ the compare

def align(a: list[Node], b: list[Node]) -> list[tuple[Node | None, Node | None]]:
    """Longest common subsequence over the child keys, so one absent node reads
    as one absent node and not as every node after it being in the wrong place."""
    n, m = len(a), len(b)
    if n * m > 1 << 18:  # a fan-out no grammar produces; positional is still honest
        return [(a[i] if i < n else None, b[i] if i < m else None) for i in range(max(n, m))]
    t = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n - 1, -1, -1):
        for j in range(m - 1, -1, -1):
            t[i][j] = t[i + 1][j + 1] + 1 if a[i].key == b[j].key else max(t[i + 1][j], t[i][j + 1])
    out: list[tuple[Node | None, Node | None]] = []
    i = j = 0
    while i < n and j < m:
        if a[i].key == b[j].key:
            out.append((a[i], b[j]))
            i, j = i + 1, j + 1
        elif t[i + 1][j] >= t[i][j + 1]:
            out.append((a[i], None))
            i += 1
        else:
            out.append((None, b[j]))
            j += 1
    return out + [(x, None) for x in a[i:]] + [(None, y) for y in b[j:]]


class Judge(NamedTuple):
    """What a difference at this spot can be blamed on. Two gaps are known and
    owned elsewhere; one more is what an unfinished parse cannot be asked about
    yet; everything else is unexplained until somebody explains it. Nothing here
    looks at what outliner said in order to decide that."""

    extras: set[str]  # the grammar's own visible extras, from the grammar
    aliases: set[str]  # every name an ALIAS can rename something to, likewise
    blob: bytes
    orphan: bool  # this tree is a fragment of a parse that stopped early

    def absent(self, theirs: Node) -> str:
        if theirs.name in self.extras:
            return "extras"
        if theirs.name == "ERROR" or theirs.name.startswith("MISSING "):
            return "recovery"
        return "unexplained"

    def at_root(self, kind: str, ours: Node, theirs: Node) -> str:
        # tree-sitter's root reaches the end of the input; outliner's stops at
        # the last token, so the two differ exactly when the file ends in
        # extras. Sound on its own: a dropped trailing *token* would show up as
        # an absent child as well, and that is judged separately.
        if kind == "span" and ours.start == theirs.start and theirs.end == len(self.blob):
            return "root-extent"
        # A root of a forest was never reduced into a parent, and both an alias
        # and a field are written into the *parent's* production - so a
        # fragment's own root cannot yet be asked for either. Narrow on purpose:
        # only a field nobody has supplied yet, and only a name tree-sitter got
        # from an alias this grammar declares. Any other name difference is a
        # different rule, which a missing parent does not excuse.
        if self.orphan and kind == "field" and ours.field is None:
            return "partial"
        if self.orphan and kind == "name" and theirs.name in self.aliases:
            return "partial"
        return "unexplained"


def compare(ours: Node, theirs: Node, where: str, out: list[Finding], judge: Judge,
            root: bool = False) -> None:
    def note(kind: str, a: str, b: str) -> None:
        blame = judge.at_root(kind, ours, theirs) if root else "unexplained"
        out.append(Finding(where, kind, a, b, blame))

    if ours.name != theirs.name or ours.named != theirs.named:
        note("name", ours.label(), theirs.label())
        return  # two different nodes; anything under them is a consequence
    if ours.field != theirs.field:
        note("field", str(ours.field), str(theirs.field))
    if (ours.start, ours.end) != (theirs.start, theirs.end):
        note("span", f"[{ours.start}, {ours.end})", f"[{theirs.start}, {theirs.end})")
    for i, (a, b) in enumerate(align(ours.kids, theirs.kids)):
        at = f"{where}/{(a or b).label()}#{i}"
        if a is None:
            out.append(Finding(at, "absent", "-", b.label(), judge.absent(b)))
        elif b is None:
            out.append(Finding(at, "surplus", a.label(), "-", "unexplained"))
        else:
            compare(a, b, at, out, judge)


# ------------------------------------------------------------------- both sides

def oracle_ready() -> str:
    if not TS.exists():
        return ""
    got = subprocess.run([str(TS), "--version"], capture_output=True, text=True)
    return got.stdout.strip() if got.returncode == 0 else ""


def gripe(stderr: str) -> str:
    """The one line of a CLI complaint worth repeating."""
    if "external_scanner" in stderr:
        return ("this grammar needs the external scanner from its own commit; "
                "`differential.py install` fetches those beside the pins")
    lines = [ln.strip() for ln in stderr.splitlines()
             if ln.strip() and "parser directories" not in ln and "init-config" not in ln
             and "language grammars" not in ln and "configuration file" not in ln]
    return lines[-1] if lines else "no reason given"


def oracle_run(lang: Path, source: Path, *flags: str) -> str:
    got = subprocess.run([str(TS), "parse", "-p", str(lang), *flags, str(source)],
                         capture_output=True, text=True, cwd=WORK)
    # Exit 1 means the file has an ERROR in it, which is an answer, not a
    # refusal - so what separates the two is whether a tree came back at all.
    if not got.stdout.strip():
        raise ValueError(gripe(got.stderr))
    return got.stdout


def oracle_build(lang: Path, want: Path) -> None:
    """Generate the oracle's parser from the same bytes the press reads."""
    src = lang / "src" / "grammar.json"
    src.parent.mkdir(parents=True, exist_ok=True)
    if not src.exists() or digest(src) != digest(want):
        shutil.copyfile(want, src)
        shutil.rmtree(lang / "src" / "tree_sitter", ignore_errors=True)
        (lang / "src" / "parser.c").unlink(missing_ok=True)
    if (lang / "src" / "parser.c").exists():
        return
    got = subprocess.run([str(TS), "generate", "src/grammar.json"],
                         capture_output=True, text=True, cwd=lang)
    if got.returncode != 0:
        raise ValueError(f"tree-sitter generate: {gripe(got.stderr)}")


INCLUDE = re.compile(rb'#\s*include\s+"([^"]+)"')


def beside(url: str, home: Path, blob: bytes) -> int:
    """The headers a scanner includes by relative path, from the same commit.

    tree-sitter-typescript's scanner is one line of `#include
    "../../common/scanner.h"` and 573 bytes of stubs, so without this there is
    no typescript oracle at all. The paths are resolved against the scanner's
    own directory on both sides at once, which is the only reading under which
    the file it gets is the file it asked for.
    """
    bad = 0
    for hit in INCLUDE.findall(blob):
        want = hit.decode()
        if want.startswith("tree_sitter/"):
            continue  # the runtime's own headers; `generate` already wrote them
        target = (home / want).resolve()
        away = "/".join(url.split("/")[:-1]) + "/" + want
        try:
            with urllib.request.urlopen(away, timeout=60) as r:  # noqa: S310 - https literal
                more = r.read()
        except (urllib.error.URLError, OSError):
            print(f"  none {'':<11} {want} is not beside the scanner upstream")
            bad += 1
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(more)
        print(f" wrote {'':<11} {want:<11} {hashlib.sha256(more).hexdigest()[:16]} {len(more)} bytes")
        bad += beside(away, target.parent, more)
    return bad


def fetch_scanners() -> int:
    """The external scanners, from the same commit as the grammar beside them.

    Seven of the eleven pins are for grammars whose lexer is partly hand-written
    C, and tree-sitter cannot build one of those without it - so without this
    there is no oracle for seven languages no matter what outliner's lexer does.
    `grammars.toml` pins a repo, a commit and a path; the scanner is the file
    next to that path in that same commit, which is the same pin and not a new
    one. Its sha256 is printed so it can be written into the manifest by
    whoever owns that file.
    """
    bad = 0
    for pin in load():
        doc = json.loads((GRAMMARS / f"{pin.name}.json").read_text(encoding="utf-8")) \
            if (GRAMMARS / f"{pin.name}.json").exists() else {}
        if not doc.get("externals") or not pin.reproducible:
            continue
        home = WORK / "lang" / pin.name / "src"
        home.mkdir(parents=True, exist_ok=True)
        for leaf in ("scanner.c", "scanner.cc"):
            url = pin.url[: -len(pin.path)] + pin.path.rsplit("/", 1)[0] + "/" + leaf
            try:
                with urllib.request.urlopen(url, timeout=60) as r:  # noqa: S310 - https literal
                    blob = r.read()
            except (urllib.error.URLError, OSError):
                continue
            (home / leaf).write_bytes(blob)
            (home / "parser.c").unlink(missing_ok=True)  # relink against the scanner
            print(f" wrote {pin.name:<11} {leaf:<11} {hashlib.sha256(blob).hexdigest()[:16]} "
                  f"{len(blob)} bytes")
            bad += beside(url, home, blob)
            break
        else:
            print(f"  none {pin.name:<11} no scanner.c or scanner.cc at {pin.commit[:12]}")
            bad += 1
    return 1 if bad else 0


def ours_run(case: Case) -> tuple[list[Node], str]:
    got = subprocess.run([str(BIN), "parse", str(case.grammar), str(case.source), "--ranges", "--all"],
                         capture_output=True, text=True, cwd=ROOT)
    if got.returncode == 2:
        raise ValueError(f"outliner refused: {got.stderr.strip().splitlines()[-1:] or ['?']}")
    stop = next((ln.split(": ", 2)[2] for ln in reversed(got.stderr.splitlines())
                 if ln.startswith("outliner: ") and ln.count(": ") >= 2), "no verdict")
    return ours_tree(got.stdout), stop


def cases(pins: set[str]) -> list[Case]:
    out = [Case(f"corpus/{g}", GRAMMARS / f"{g}.json", WORK / "lang" / g, CORPUS / f, "corpus")
           for g, f in pairs() if g in pins]
    for name in SOURCES:
        lang = name.split("/", 1)[0]
        if lang not in pins:
            continue
        out.append(Case(f"{lang}/{Path(name).stem}", GRAMMARS / f"{lang}.json",
                        WORK / "lang" / lang, WORK / "case" / name, "case"))
    for name in PROBES:
        out.append(Case(f"probe/{name}", WORK / "probe" / name / "src" / "grammar.json",
                        WORK / "probe" / name, WORK / "probe" / name / "sample.txt", "probe"))
    return out


def lay_out() -> None:
    """Write the cases this file carries. Probe grammars are written before the
    oracle generates from them, so the grammar the oracle builds and the grammar
    outliner imports are one file rather than two copies."""
    for name, text in SOURCES.items():
        leaf = WORK / "case" / name
        leaf.parent.mkdir(parents=True, exist_ok=True)
        leaf.write_text(text, encoding="utf-8")
    for name, (doc, text) in PROBES.items():
        home = WORK / "probe" / name
        (home / "src").mkdir(parents=True, exist_ok=True)
        (home / "src" / "grammar.json").write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
        (home / "sample.txt").write_text(text, encoding="utf-8")


def measure(case: Case) -> Report:
    def skip(why: str) -> Report:
        return Report(case, "skipped", why, 0, 0, [])

    if not case.source.exists():
        return skip(f"no source at {case.source.relative_to(ROOT)}")
    if not case.grammar.exists():
        return skip("grammar not resolved; run `python3 tool/grammars.py fetch`")
    try:
        oracle_build(case.lang, case.grammar)
        doc = json.loads(case.grammar.read_text(encoding="utf-8"))
        blob = case.source.read_bytes()
        at = Lines(blob)
        theirs = xml_tree(oracle_run(case.lang, case.source, "-x"), at)
        full, hurt = cst_tree(oracle_run(case.lang, case.source, "--cst"), at)
        if not same(full.named_only(), theirs):
            # Either the CST indentation lied (it does inside an error tree) or
            # this reader is wrong about one of the two formats. Refusing is the
            # only honest move: a comparison against a tree nobody can confirm
            # is noise wearing the clothes of a result.
            return skip("tree-sitter's CST and XML disagree with each other"
                        + (" (the tree has errors in it)" if hurt else ""))
        graft_fields(full, case.lang, case.source, declared(doc, "FIELD", "name"), at)
        roots, stop = ours_run(case)
    except (ValueError, KeyError, ET.ParseError, OSError) as e:
        return skip(str(e))

    extras = {e["name"] for e in doc.get("extras", []) if e.get("type") == "SYMBOL"}
    aliases = set(declared(doc, "ALIAS", "value"))
    out: list[Finding] = []
    if stop.startswith("accepted") and len(roots) == 1:
        compare(roots[0], full, full.label(), out, Judge(extras, aliases, blob, False), root=True)
        return Report(case, "whole", stop, roots[0].count(), full.count(), out)

    # A partial parse leaves a forest. Anchor a root only where the oracle has a
    # node covering exactly those bytes; a root with no counterpart is reported
    # as unanchored rather than guessed at, and a case that anchors nothing is
    # a skip rather than a pass.
    index: dict[tuple[int, int], list[Node]] = {}

    def walk(n: Node) -> None:
        index.setdefault((n.start, n.end), []).append(n)
        for k in n.kids:
            walk(k)

    walk(full)
    judge = Judge(extras, aliases, blob, True)
    held = 0
    for r in roots:
        peers = index.get((r.start, r.end), [])
        if len(peers) != 1:
            out.append(Finding(r.label(), "unanchored", f"[{r.start}, {r.end})",
                               f"{len(peers)} nodes cover those bytes", "partial"))
            continue
        held += 1
        compare(r, peers[0], r.label(), out, judge, root=True)
    if not held:
        return skip(f"stopped at once ({stop}); no root lines up with an oracle node")
    return Report(case, "prefix", f"{stop}; {held}/{len(roots)} roots anchored",
                  sum(r.count() for r in roots), full.count(), out)


# ------------------------------------------------------------------------ verbs

def run(picked: list[Case], as_json: bool, verbose: bool) -> int:
    reports = [measure(c) for c in picked]
    if as_json:
        print(json.dumps({"oracle": oracle_ready(), "case": [r.as_dict() for r in reports]}, indent=2))
        return 1 if any(r.unexplained for r in reports) else 0
    print(f"{'case':<20} {'mode':<8} {'ours':>7} {'theirs':>7} {'known':>6} {'unexplained':>12}  why")
    for r in reports:
        known = len(r.findings) - r.unexplained
        print(f"{r.case.name:<20} {r.mode:<8} {r.ours:>7} {r.theirs:>7} {known:>6} "
              f"{r.unexplained:>12}  {r.why}")
    for r in reports:
        shown = [f for f in r.findings if verbose or f.owner == "unexplained"]
        if not shown:
            continue
        print(f"\n  {r.case.name} ({r.case.source.name})")
        for f in shown[:200]:
            print(f"{f.line()}  [{f.owner}]")
        if len(shown) > 200:
            print(f"    ... {len(shown) - 200} more")
    tally: dict[str, int] = {}
    for r in reports:
        for f in r.findings:
            tally[f.owner] = tally.get(f.owner, 0) + 1
    done = [r for r in reports if r.mode != "skipped"]
    print(f"\n{len(done)} compared, {len(reports) - len(done)} skipped · "
          + (", ".join(f"{n} {k}" for k, n in sorted(tally.items())) or "no differences at all"))
    sys.stdout.flush()
    if bad := sum(r.unexplained for r in reports):
        print(f"differential: {bad} difference(s) nobody owns", file=sys.stderr)
        return 1
    return 0


def show(picked: list[Case]) -> int:
    for case in picked:
        r = measure(case)
        print(f"# {case.name}  {here(case.source)}")
        if r.mode == "skipped":
            print(f"  skipped: {r.why}\n")
            continue
        blob = case.source.read_bytes()
        at = Lines(blob)
        theirs, _ = cst_tree(oracle_run(case.lang, case.source, "--cst"), at)
        ours, stop = ours_run(case)
        print(f"  {r.why}\n\n  -- outliner ({stop})")
        for root in ours:
            print("\n".join("    " + ln for ln in root.render()))
        print("\n  -- tree-sitter")
        print("\n".join("    " + ln for ln in theirs.render()))
        print()
    return 0


def here(p: Path) -> str:
    return str(p.relative_to(ROOT) if p.is_relative_to(ROOT) else p)


def inventory(picked: list[Case], as_json: bool) -> int:
    rows = [{k: here(v) if isinstance(v, Path) else v for k, v in c._asdict().items()} for c in picked]
    if as_json:
        print(json.dumps({"case": rows}, indent=2))
        return 0
    print(f"{'case':<20} {'origin':<7} {'source':<46} grammar")
    for r in rows:
        print(f"{r['name']:<20} {r['origin']:<7} {r['source']:<46} {r['grammar']}")
    return 0


def install() -> int:
    if not shutil.which("npm"):
        return oops("no npm on this machine; the oracle cannot be installed here")
    CLI.mkdir(parents=True, exist_ok=True)
    (CLI / "package.json").write_text(
        json.dumps({"name": "outliner-differential-oracle", "private": True,
                    "description": "dev-only tree-sitter CLI; never a dependency of the package"},
                   indent=2) + "\n", encoding="utf-8")
    got = subprocess.run(["npm", "install", "--no-audit", "--no-fund", "tree-sitter-cli"], cwd=CLI)
    if got.returncode != 0 or not TS.exists():
        return oops(f"npm could not put a tree-sitter CLI in {CLI}")
    print(f"oracle {oracle_ready()} at {here(TS)}")
    return fetch_scanners()


def oops(msg: str) -> int:
    print(f"differential.py: {msg}", file=sys.stderr)
    return 2


def main(argv: list[str]) -> int:
    as_json = verbose = False
    want_case = want_grammar = verb = ""
    for a in argv:
        if a == "--json":
            as_json = True
        elif a in ("-v", "--verbose"):
            verbose = True
        elif a.startswith("--case="):
            want_case = a.split("=", 1)[1]
        elif a.startswith("--grammar="):
            want_grammar = a.split("=", 1)[1]
        elif a in ("-h", "--help"):
            print(USAGE)
            return 0
        elif a.startswith("-"):
            return oops(f"unknown flag {a}\n\n{USAGE}")
        elif verb:
            return oops(f"one verb at a time, got {verb} and then {a}")
        else:
            verb = a
    if not verb:
        print(USAGE, file=sys.stderr)
        return 2
    if verb == "install":
        return install()
    version = oracle_ready()
    if verb == "oracle":
        print(f"tree-sitter {version} at {TS}" if version else
              f"no tree-sitter CLI at {TS}\nrun `python3 tool/differential.py install` to put one there")
        return 0 if version else 1
    if verb not in ("run", "show", "list"):
        return oops(f"no such verb {verb!r}\n\n{USAGE}")
    try:
        lay_out()
        pins = {p.name for p in load()}
        picked = [c for c in cases(pins)
                  if (not want_case or c.name == want_case or c.name.endswith("/" + want_case))
                  and (not want_grammar or c.grammar.stem == want_grammar)]
    except (OSError, ValueError) as e:
        return oops(str(e))
    if not picked:
        return oops(f"no case matches {want_case or want_grammar}")
    if verb == "list":
        return inventory(picked, as_json)
    if not version:
        # The one skip that is not a case's: no oracle, nothing to compare
        # against, and that is not a failing comparison.
        print(f"differential: no tree-sitter CLI at {TS}; {len(picked)} case(s) skipped")
        print("differential: `python3 tool/differential.py install` puts a dev-only one there",
              file=sys.stderr)
        return 0
    if not BIN.exists():
        return oops(f"no binary at {BIN}; run `zig build` first")
    return show(picked) if verb == "show" else run(picked, as_json, verbose)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

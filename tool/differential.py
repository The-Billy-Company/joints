#!/usr/bin/env python3
"""Hold joints's tree against the tree tree-sitter actually builds.

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
Comparing joints against a differently-pinned tree-sitter grammar would make
every diff meaningless.

Three normalisations, and no others:

  * **position spelling.** tree-sitter reports `row:column` in bytes; joints
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

import atexit
import contextlib
import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from collections.abc import Iterator
from pathlib import Path
from typing import Any, NamedTuple

from grammars import digest, load
from rung1 import pairs
from stamp import Outcome, take
from stamp import ask as ask_one

ROOT = Path(__file__).resolve().parent.parent
GRAMMARS = ROOT / "upstream" / "grammars"
CORPUS = ROOT / "research" / "joinery" / "corpus"
WORK = ROOT / ".local" / "differential"
CLI = WORK / "cli"
TS = CLI / "node_modules" / ".bin" / "tree-sitter"
# Ours, not `~/.cache/tree-sitter/lib`, which every tool on the machine shares
# and keys by language name alone; see `cli()`.
# A lane's own corner of the workspace. Keyed by the *calling shell* rather than
# by this process, so running the tool twice in one terminal reuses everything
# it built the first time, while two lanes in two terminals share nothing
# writable. `JOINTS_LANE` names it explicitly where a caller knows better.
#
# What goes in here is what a second writer corrupts. `TREE_SITTER_LIBDIR` moves
# the compiled libraries and *nothing else*: the CLI also keeps a lockfile per
# language under `$XDG_CACHE_HOME/tree-sitter/lock/` and deletes it on the way
# out, so two processes sharing that directory have one removing the file the
# other is opening - the loser reports `No such file or directory` on a language
# sitting right there. And the libraries themselves cannot be shared either,
# because the CLI recompiles on its own criterion, not one this side can
# predict; asked to do it twice at once it says so plainly: `Are you running
# multiple processes building to the same output location?`.
#
# What stays shared is `lang/`, where the expensive work is - `tree-sitter
# generate` on c and cpp is minutes - and that one is guarded by `alone()`
# instead, because it is worth queueing for. Compiling a `.dylib` is seconds, so
# owning one outright is cheaper than any protocol for sharing it.
# `getppid()` of an orphan is 1, and pid 1 is both immortal and shared - so
# every orphaned run would pile into one seat that is never reaped, which is the
# collision this whole mechanism exists to stop. A run with no living caller
# owns itself instead.
SEAT = WORK / "seat" / os.environ.get(
    "JOINTS_LANE", str(os.getppid() if os.getppid() > 1 else os.getpid()))
LIB = SEAT / "lib"
BIN = Path(os.environ.get("JOINTS_BIN", ROOT / "zig-out" / "bin" / "joints"))
# How long a lane will wait for another lane's compile of the same language
# before refusing. Long enough for the slowest grammar in the set to generate
# and compile from cold; short enough that a crashed holder is not forever.
PATIENCE = float(os.environ.get("JOINTS_ORACLE_PATIENCE", "300"))
# The token a contended skip carries, so the summary can tell a fact about the
# grammar apart from a fact about how many lanes were running.
CONTENDED = "another lane holds"
# Skip reasons that are facts about the machine rather than about a grammar.
FRAGILE = (CONTENDED, "dlopen", "same output location", "No such file or directory",
           "printer says", "not found after build attempt")
WAITED: set[str] = set()  # languages this run had to queue behind
# Which grammars *this process* already holds, and whether exclusively. `flock`
# is per open file description, so without this a nested acquire waits on a lock
# the same process is holding - see `alone`.
_HELD: dict[str, tuple[int, bool]] = {}

USAGE = """\
differential.py - is joints's tree the tree tree-sitter builds?

usage:
  differential.py run       compare every case (offline; skips if no oracle)
  differential.py show      both trees for one case, side by side
  differential.py list      the cases, and where each one's grammar comes from
  differential.py spans     every reader of their stdout, across every span shape
  differential.py sandbox   does every scanner include resolve inside its own grammar\n  differential.py scanners  lay every external scanner down, pinned bytes where pinned\n  differential.py oracle    is the tree-sitter CLI here, and which version
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
        leaf token, so dropping one whole drops nothing under it.

        A `MISSING` placeholder goes with them. The CLI prints one as
        `MISSING: "kind"` from the branch it takes for *anonymous* nodes - a
        named node it had to insert prints as a bare kind and is a node in both
        renders - and `cst_tree` calls it named anyway so a caller counting
        repairs can see it. The XML has no element for it, so leaving it in is
        what made twenty-one inserted semicolons read as a shape disagreement."""
        copy = Node(self.name, self.named, self.field, self.start, self.end)
        copy.kids = [k.named_only() for k in self.kids
                     if k.named and not k.name.startswith("MISSING ")]
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
        return f"    {self.where}: {self.kind}: joints {self.ours}, tree-sitter {self.theirs}"


class Case(NamedTuple):
    name: str
    grammar: Path  # the bytes both sides read
    lang: Path  # where the oracle's parser is generated
    source: Path
    origin: str  # corpus · case · probe · span · held-out


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
    """`joints parse --ranges --all`: one node a line, two spaces a level."""
    roots: list[Node] = []
    stack: list[Node] = []
    for raw in text.splitlines():
        if not raw.strip():
            continue
        m = OURS.match(raw)
        if not m:
            raise ValueError(f"cannot read joints's own output: {raw!r}")
        depth = len(m[1]) // 2
        field, name, named, _ = head(m[2])
        node = Node(name, named, field, int(m[3]), int(m[4]))
        del stack[depth:]
        (stack[-1].kids if stack else roots).append(node)
        stack.append(node)
    return roots


def digits(n: int) -> int:
    """Rust's `n.checked_ilog10().unwrap_or(0)` - one less than the decimal
    width, and 0 rather than undefined at zero. The CLI's column arithmetic is
    written in it, so reading that arithmetic back needs the same function."""
    return len(str(n)) - 1


def indents(rows: list[re.Match[str]]) -> list[int]:
    """How far each CST row is indented, with the range prefix subtracted off.

    The prefix is not a fixed width and the CLI never says how wide it made it,
    so this inverts the format string that wrote it (`render_node_range`)::

        "{row}:{col}{:pad_start$}- {row}:{col}{:pad_end$}"
        pad = max(1, total_width - digits(row) - digits(col))

    `total_width` is one number for the whole render, and every row that was
    not clamped by that `max(1, ...)` states it outright, so the smallest thing
    any row implies is it. Clamping only ever raises a row's padding, never
    lowers it, so the minimum cannot be an overshoot.

    What is left after the prefix is `"  " * depth`, plus - and this is the
    whole reason the arithmetic has to be exact - **one extra space whenever the
    node sits inside an error subtree without carrying an error itself**
    (`in_error && !node.has_error()` in `cst_render_node`). That one space is
    the entire disagreement: it makes a clean node read a level deeper than it
    is and the bulleted sibling after it read a level shallower, so the sibling
    is adopted by the node above it. Two spaces a level means the space lands
    in the odd bit and integer division drops it, which is why callers divide
    rather than compare columns."""
    # Rows whose padding was clamped imply a width larger than the real one.
    width = min(m.start(3) - 2 - m.end(2) + digits(int(m[1])) + digits(int(m[2]))
                for m in rows) if rows else 1
    return [len(m[5]) - max(1, width - digits(int(m[3])) - digits(int(m[4]))) for m in rows]


def cst_tree(text: str, at: Lines) -> tuple[Node, bool]:
    """`tree-sitter parse --cst`. The only format that gives an anonymous node's
    *type* rather than its text, which is exactly what an alias to a string
    changes. Its indentation is two spaces a level and one further space for a
    clean node inside an error - see `indents`, which is where the columns are
    turned back into depths and where every subtlety of this format lives.

    The bullet marking a node that carries an error costs no indentation at all:
    the CLI writes it *after* the indent and after any `field: `, so it is part
    of the body and stripping the character is the whole correction. Reading it
    as a column - under a whole-render `shift` of one or zero, chosen by
    whichever reconciled - is what could not read verilog or sql, because the
    perturbation it was standing in for is per-row and in the other direction.

    A leaf short enough to sit on one line carries its text on its own row, as
    `identifier `a``. A leaf whose text crosses a newline cannot, so the CLI
    prints the name alone and follows it with one backtick-quoted piece of that
    text per line the token covers - blank lines included, `\\r\\n` and an inner
    backtick escaped, always exactly one output row each. Those pieces are the
    token the line above already named, so they are text and not nodes, and the
    leading backtick is what says so: an anonymous node is always double quoted,
    even when it is itself a backtick. Their ranges are worth nothing anyway,
    since a continuation row is printed with the *parent's* start column and can
    read as ending before it began."""
    roots: list[Node] = []
    stack: list[tuple[int, Node]] = []
    hurt = False
    rows = [m for m in map(CST.match, text.splitlines()) if m]
    for m, indent in zip(rows, indents(rows)):
        body = m[6]
        # The bullet sits immediately before the *name*, so after the `field: `
        # prefix when the node has one. Looking for it only at the start of the
        # body left every bulleted node that also carries a field uncorrected.
        cut = 0 if (mf := BODY.match(body))[1] is None else len(mf[1]) + 2
        if body[cut:].startswith("\u2022"):
            body, hurt = body[:cut] + body[cut + 1:], True
        if body.startswith("`"):
            continue  # a continuation row: the token above's own text, not a node
        missing = body.startswith("MISSING: ")
        if missing:
            body, hurt = body[len("MISSING: "):], True
        field, name, named, _ = head(body)
        node = Node("MISSING " + name if missing else name, named or missing, field,
                    at.off(int(m[1]), int(m[2])), at.off(int(m[3]), int(m[4])))
        deep = indent // 2
        while stack and stack[-1][0] >= deep:
            stack.pop()
        (stack[-1][1].kids if stack else roots).append(node)
        stack.append((deep, node))
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


def reconciled(text: str, at: Lines, theirs: Node) -> tuple[Node | None, bool]:
    """The CST, only if the XML confirms it. One reading, not a search: the
    indentation rule is now inverted exactly rather than guessed at (`indents`),
    so a disagreement here is a real disagreement and not a shift we failed to
    try. The check itself is unchanged and stays the falsifier - the XML nests
    unambiguously, so a CST whose named shape it does not confirm is a tree
    nobody can vouch for. `None` says exactly that, and stays a refusal."""
    full, hurt = cst_tree(text, at)
    return (full if same(full.named_only(), theirs) else None), hurt


QPATTERN = re.compile(r"^ *pattern: (\d+)\s*$")
# Their query printer has two forms for one capture and switches on the span
# alone: a capture with `end.row > start.row` loses both its index and its
# `text:` tail, and everything else keeps them. Probed across spans of one, two,
# three, four and twenty rows, a blank row inside, a 300-column single row, a
# backtick in the text, and a node ending at column zero of the next row - that
# last one has no characters on its final row and still takes the short form, so
# the switch is the row numbers and not the bytes. Demanding the index is what
# dropped every multi-line parent on the floor, and a dropped parent is a field
# never grafted; see `.local/queryprobe.py`.
QCAPTURE = re.compile(
    r"^ *capture: (?:\d+ - )?(\w+), start: \((\d+), (\d+)\), end: \((\d+), (\d+)\)")


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
    # Per lane, not per workspace. This file was `WORK / "query.scm"`, one
    # mutable path every concurrent measurement wrote its own pattern list to -
    # and the reader below maps a pattern *ordinal* back to a name through the
    # local `names`, so reading another lane's file does not fail, it silently
    # renames every field. That is the shape of "the printer says value, its
    # query says declaration": not a disagreement between two faces of one
    # library, but this process reading an answer to somebody else's question.
    q = SEAT / "query.scm"
    SEAT.mkdir(parents=True, exist_ok=True)
    while names:
        q.write_text("".join(f"((_ {n}: _ @child) @parent)\n" for n in names), encoding="utf-8")
        got = cli([str(TS), "query", "-p", str(lang), str(q), str(source)], WORK)
        if got.returncode == 0:
            break
        # A field the grammar declares but the compiled language does not have
        # (typescript inherits rules from javascript that its own parser prunes)
        # is a field no node can be carrying. Drop it and ask again.
        gone = re.search(r'Invalid field name "(\w+)"', got.stderr)
        if not gone:
            raise ValueError(f"tree-sitter query: {gripe(got.stderr)}")
        if gone[1] not in names:
            # The CLI is complaining about a field we did not ask about, so it
            # read a different file than the one just written and dropping the
            # name would not shrink anything. This loop used to spin on that
            # forever, silently, which is how a shared `query.scm` presented as
            # a hang rather than as a fault.
            raise ValueError(f"tree-sitter query: rejected {gone[1]!r}, which this "
                             "query never asked for; the query file was not ours")
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
    looks at what joints said in order to decide that."""

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
        # tree-sitter's root reaches the end of the input; joints's stops at
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

def cli(args: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    """Every call into their CLI, with its compiled-language cache pinned here.

    Left alone, the CLI compiles a grammar into `~/.cache/tree-sitter/lib/` under
    the *language name* - so this run's pinned `javascript` and any other tool's
    `javascript` are one file. One measurement is three separate invocations
    (`-x`, then `--cst`, then `query`), and a rebuild landing between two of them
    swaps the language out underneath a comparison that has already started.
    `graft_fields` caught exactly that once, as its two faces disagreeing, which
    is why it refuses rather than grafting. Own the directory and the race is
    gone rather than rare.
    """
    env = {**os.environ, "TREE_SITTER_LIBDIR": str(LIB), "XDG_CACHE_HOME": str(SEAT)}
    LIB.mkdir(parents=True, exist_ok=True)
    SEAT.mkdir(parents=True, exist_ok=True)
    return subprocess.run(args, capture_output=True, text=True, cwd=cwd, env=env)


def oracle_ready() -> str:
    if not TS.exists():
        return ""
    got = cli([str(TS), "--version"], WORK)
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


def builder_argv() -> list[str]:
    """How the oracle's parser is generated, spelled once.

    Run from inside the language directory, which is why the path is relative.
    See `oracle_argv` for why an argv is a thing this module hands out at all.
    """
    return [str(TS), "generate", "src/grammar.json"]


def oracle_argv(lang: Path, source: Path, *flags: str) -> list[str]:
    """How the oracle is asked for a tree, spelled once.

    The exchanges below are the door for a caller that wants the *answer*. This
    is the door for one that needs the exchange itself: `collate` publishes the
    generate and parse latencies as a table, so it cannot call `oracle_full` -
    the owner's exchange folds in a digest and a copy that a cold-build
    measurement has to exclude, and `oracle_build` is idempotent by design.
    What that caller needed was never the answer, it was the command line, and
    handing back the argv keeps its number honest without leaving it to spell
    the invocation a second time. A flag added here reaches the measurement too.
    """
    return [str(TS), "parse", "-p", str(lang), *flags, str(source)]


def refused(got: subprocess.CompletedProcess[str]) -> str:
    """Why the oracle gave us no tree, or `""` if it gave us one.

    **Exit 1 means the file has an `ERROR` in it, which is an answer, not a
    refusal** - so what separates the two is whether a tree came back at all,
    never the status. Named rather than left inline because `collate` has to
    draw the same line and cannot use `oracle_full`: it cross-checks the
    damage in the tree against the exit status, and an exception carries no
    status. Same rule, two readers, one place to be wrong.
    """
    return "" if got.stdout.strip() else gripe(got.stderr)


def oracle_full(lang: Path, source: Path, *flags: str) -> tuple[str, str]:
    """The oracle's tree, and everything it said around it.

    Both halves, because they carry different things: an `ERROR` is a node in
    the tree, while a `MISSING` is announced on the summary line and appears
    nowhere in it. A caller counting repairs needs the pair, and a caller
    counting nodes wants `oracle_run` below.
    """
    got = cli(oracle_argv(lang, source, *flags), WORK)
    if why := refused(got):
        raise ValueError(why)
    return got.stdout, got.stderr


def oracle_run(lang: Path, source: Path, *flags: str) -> str:
    return oracle_full(lang, source, *flags)[0]


_HOMES: dict[str, str] = {}


def oracle_root(name: str, work: Path | None = None) -> Path:
    """One grammar's whole sandbox. Nothing it includes may resolve above here."""
    return (work if work is not None else WORK) / "lang" / name


def named(home: Path) -> str:
    """Back from a language directory to the grammar's name.

    The directory under `lang/` rather than the leaf, since a monorepo grammar's
    home is nested and its leaf is not always its name - `lang/ocaml/grammars/
    ocaml` and `lang/ocaml/grammars/interface` are both ocaml's.
    """
    parts = home.parts
    return parts[parts.index("lang") + 1] if "lang" in parts else home.name


def rooted(lang: Path) -> tuple[Path, Path]:
    """A grammar's own sandbox root, and how deep inside it the CLI is handed.

    `named` above and this are the same inverse asked for different halves, so
    they live together: where `lang/` ends is one fact about a path, and it was
    being decided in two files. `oracle_home` reproduces a monorepo's depth
    under `lang/<name>/` because php's and typescript's scanners climb out of
    their own directory - so a pin that copied only the home would break exactly
    the three grammars the depth exists for. The root is what gets copied; the
    offset is what gets restored.
    """
    parts = lang.parts
    if "lang" not in parts:
        return lang, Path()
    root = Path(*parts[:parts.index("lang") + 2])
    return root, lang.relative_to(root)


def oracle_home(name: str, work: Path | None = None) -> Path:
    """The directory the oracle CLI is handed for one grammar.

    Usually `lang/<name>/`, holding `src/grammar.json` - and for 27 of the 30
    that is exactly what this returns. A monorepo grammar gets the *repository's
    own depth* reproduced under its own root: ocaml at
    `lang/ocaml/grammars/ocaml/`, php at `lang/php/php/`, typescript at
    `lang/typescript/typescript/`.

    The depth is not decoration. Those three scanners are shims whose whole body
    is `#include "../../common/scanner.h"` (ocaml climbs one further), written to
    resolve inside the repository they came from. Laid out flat, php's climb and
    typescript's climb land on the *same* `lang/common/scanner.h` - and those two
    files are 18,018 and 10,097 different bytes, so whichever was written second
    silently owned both oracles. Reproducing the repository depth under a
    per-grammar root makes the collision impossible instead of a matter of whose
    include happened to be a level deeper.
    """
    work = work if work is not None else WORK
    if name not in _HOMES:
        pin = next((p for p in load("all") if p.name == name), None)
        # `<dir>/src/grammar.json` -> `<dir>`; a bare `src/grammar.json` -> ``.
        deep = pin.path.rsplit("/src/", 1)[0] if pin and "/src/" in pin.path else ""
        _HOMES[name] = deep
    return oracle_root(name, work) / _HOMES[name]


def oracle_build(lang: Path, want: Path) -> None:
    """Generate the oracle's parser from the same bytes the press reads.

    **This writes into a directory every lane shares**, so it takes the lock
    itself. It used to be the caller's job and nine of twelve call sites did it;
    `recover.py`, `adjudicate.py` and this file's own `graft_fields` did not, and
    a measurement that overwrites a sibling's `grammar.json` and deletes the
    `parser.c` beside it is the same family as a folio cache keyed on an mtime -
    a comparison whose setup mutates the thing being compared, always in the
    flattering direction, because afterwards both arms agree.

    Nothing changes for a caller that already held it: `alone` is re-entrant.
    """
    with alone(named(lang)):
        src = lang / "src" / "grammar.json"
        src.parent.mkdir(parents=True, exist_ok=True)
        if not src.exists() or digest(src) != digest(want):
            shutil.copyfile(want, src)
            shutil.rmtree(lang / "src" / "tree_sitter", ignore_errors=True)
            (lang / "src" / "parser.c").unlink(missing_ok=True)
        if (lang / "src" / "parser.c").exists():
            return
        got = cli(builder_argv(), lang)
        if got.returncode != 0:
            raise ValueError(f"tree-sitter generate: {gripe(got.stderr)}")


INCLUDE = re.compile(rb'#\s*include\s+"([^"]+)"')


def includes(blob: bytes, beside: Path) -> list[tuple[str, Path]]:
    """Every `#include "…"` in `blob` that names a file of the grammar's own -
    the spelling, and where it resolves to relative to `beside`.

    **The runtime's own headers are not among them.** `generate` writes
    `src/tree_sitter/*.h` itself, so a closure that followed those would fold
    the CLI's version into the identity of the grammar's authored bytes - which
    is the same error as sweeping a compiled library in, from the other side.
    Three walks decided that separately and two of them were in this file: the
    upstream fetch in `beside`, the containment check in `sandboxed`, and
    `attest`'s digest closure. What each does with a hit still differs; which
    hits there are does not.
    """
    out = []
    for hit in INCLUDE.findall(blob):
        want = hit.decode()
        if want.startswith("tree_sitter/"):
            continue
        out.append((want, (beside / want).resolve()))
    return out


def refresh(target: Path, blob: bytes, home: Path) -> bool:
    """Lay a scanner down, and relink only if it is actually a different one.

    The unconditional `write_bytes` this replaces cost nothing in bytes and
    everything in identity. `attest` digests an oracle by its whole `src/`, and
    `parser.c` is in that digest, so unlinking a generated parser beside a
    scanner that did not change gives one grammar **two identities for one
    parser**. That is the whole of the source-tree divergence on this machine:
    30 grammars exist as more than one tree, 28 are byte-identical, and the two
    that are not - css and toml - agree the moment generated files come out of
    the comparison. We wrote that difference ourselves, with a `cp` of a file
    onto its own bytes.

    Returns whether anything moved, so a caller can say `wrote` or `same` rather
    than claiming a write it did not do.
    """
    if target.exists() and target.read_bytes() == blob:
        return False
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(blob)
    (home / "src" / "parser.c").unlink(missing_ok=True)  # relink against the scanner
    return True


def beside(url: str, home: Path, blob: bytes) -> int:
    """The headers a scanner includes by relative path, from the same commit.

    tree-sitter-typescript's scanner is one line of `#include
    "../../common/scanner.h"` and 573 bytes of stubs, so without this there is
    no typescript oracle at all. The paths are resolved against the scanner's
    own directory on both sides at once, which is the only reading under which
    the file it gets is the file it asked for.
    """
    bad = 0
    for want, target in includes(blob, home):
        away = "/".join(url.split("/")[:-1]) + "/" + want
        try:
            with urllib.request.urlopen(away, timeout=60) as r:  # noqa: S310 - https literal
                more = r.read()
        except (urllib.error.URLError, OSError):
            print(f"  none {'':<11} {want} is not beside the scanner upstream")
            bad += 1
            continue
        # Only on a difference. Rewriting a header with its own bytes leaves the
        # digest alone and moves the mtime, and the mtime is what `attest` reads
        # to decide a library predates its sources - so an unconditional `cp`
        # here reports every oracle on the machine as about to change parsers.
        moved = not target.exists() or target.read_bytes() != more
        if moved:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(more)
        print(f"{' wrote' if moved else '  same'} {'':<11} {want:<11} "
              f"{hashlib.sha256(more).hexdigest()[:16]} {len(more)} bytes")
        bad += beside(away, target.parent, more)
    return bad


def lay(pin: Any, work: Path | None = None) -> int:
    """A monorepo grammar's scanner, from the verified pins rather than a URL.

    Offline, and byte-checked on the way in: `grammars.py fetch` has already put
    these under `upstream/grammars/companion/<name>/` at their repo-relative
    paths and `verify` hashes them there. Laying them down at the *same*
    repo-relative paths under this grammar's own oracle root is what makes a
    shim's `#include "../../common/scanner.h"` reach its own repository's header
    - the pin frame and the oracle layout are deliberately one frame.

    Contrast `beside()` below, which derives a URL by gluing the include's
    relative path onto the grammar's own. That reads the *include* correctly and
    the *destination* not at all: php and typescript both climb two levels, so
    both landed on one shared file, and the second writer owned both oracles.
    """
    from grammars import DEST, digest as sha, kin
    root, bad = oracle_root(pin.name, work), 0
    for mate in pin.companion:
        have = kin(pin, DEST) / mate.path
        if not have.exists():
            print(f"  none {pin.name:<11} {mate.path}: not fetched; run grammars.py fetch")
            bad += 1
            continue
        if sha(have) != mate.sha256:
            print(f" DRIFT {pin.name:<11} {mate.path}: on disk {sha(have)[:16]}, "
                  f"pinned {mate.sha256[:16]}")
            bad += 1
            continue
        with alone(pin.name):
            moved = refresh(root / mate.path, have.read_bytes(),
                            oracle_home(pin.name, work))
        print(f"{' wrote' if moved else '  same'} {pin.name:<11} {mate.path:<32}"
              f" {mate.sha256[:16]} {mate.size} bytes")
    return 1 if bad else 0


def fetch_scanners(which: str = "dossier", work: Path | None = None) -> int:
    """The external scanners, from the same commit as the grammar beside them.

    Seven of the eleven pins are for grammars whose lexer is partly hand-written
    C, and tree-sitter cannot build one of those without it - so without this
    there is no oracle for seven languages no matter what joints's lexer does.
    `grammars.toml` pins a repo, a commit and a path; the scanner is the file
    next to that path in that same commit, which is the same pin and not a new
    one. Its sha256 is printed so it can be written into the manifest by
    whoever owns that file. A grammar whose scanner is *not* beside its grammar
    goes through `lay()` instead, off pinned bytes.
    """
    bad = 0
    for pin in load(which):
        doc = json.loads((GRAMMARS / f"{pin.name}.json").read_text(encoding="utf-8")) \
            if (GRAMMARS / f"{pin.name}.json").exists() else {}
        if not doc.get("externals") or not pin.reproducible:
            continue
        home = oracle_home(pin.name, work) / "src"
        home.mkdir(parents=True, exist_ok=True)
        if pin.companion:
            bad += lay(pin, work)
            continue
        for leaf in ("scanner.c", "scanner.cc"):
            url = pin.url[: -len(pin.path)] + pin.path.rsplit("/", 1)[0] + "/" + leaf
            try:
                with urllib.request.urlopen(url, timeout=60) as r:  # noqa: S310 - https literal
                    blob = r.read()
            except (urllib.error.URLError, OSError):
                continue
            with alone(pin.name):
                moved = refresh(home / leaf, blob, home.parent)
            print(f"{' wrote' if moved else '  same'} {pin.name:<11} {leaf:<11} "
                  f"{hashlib.sha256(blob).hexdigest()[:16]} {len(blob)} bytes")
            bad += beside(url, home, blob)
            break
        else:
            print(f"  none {pin.name:<11} no scanner.c or scanner.cc at {pin.commit[:12]}")
            bad += 1
    return 1 if bad else 0


def sandboxed(work: Path | None = None) -> int:
    """Does every `#include` a scanner writes resolve inside its own grammar?

    The check that would have caught the collision the day it was written, and
    the one that catches the next monorepo grammar. It reads the scanners on
    disk rather than the pins, so it judges what the compiler will actually
    open. A target that resolves above `lang/<name>/` is a file two grammars can
    reach, and two grammars reaching one mutable path is the whole fault.
    """
    work = work if work is not None else WORK
    bad = 0
    for sc in sorted((work / "lang").rglob("src/scanner.c*")):
        name = sc.relative_to(work / "lang").parts[0]
        root = oracle_root(name, work).resolve()
        for want, target in includes(sc.read_bytes(), sc.parent):
            if not target.is_relative_to(root):
                print(f"  ESCAPES {name:<12} {want:<30} -> {target}")
                bad += 1
            elif not target.exists():
                print(f"  MISSING {name:<12} {want:<30} -> {here(target)}")
                bad += 1
    print(f"includes: {'every one resolves inside its own grammar' if not bad else f'{bad} bad'}")
    return 1 if bad else 0


def ours_run(case: Case) -> tuple[list[Node], Outcome]:
    end = ask_one(BIN, case.grammar, case.source, tree=True)
    if end.code == 2:
        raise ValueError(f"joints refused: {end.verdict}")
    return ours_tree(end.tree), end


def cases(pins: set[str]) -> list[Case]:
    out = [Case(f"corpus/{g}", GRAMMARS / f"{g}.json", oracle_home(g), CORPUS / f, "corpus")
           for g, f in pairs() if g in pins]
    for name in SOURCES:
        lang = name.split("/", 1)[0]
        if lang not in pins:
            continue
        out.append(Case(f"{lang}/{Path(name).stem}", GRAMMARS / f"{lang}.json",
                        oracle_home(lang), WORK / "case" / name, "case"))
    for name in PROBES:
        out.append(Case(f"probe/{name}", WORK / "probe" / name / "src" / "grammar.json",
                        WORK / "probe" / name, WORK / "probe" / name / "sample.txt", "probe"))
    # The span fixtures compare like any other case, and that is the whole point:
    # `spans` says which reader broke, but only a comparison can *fail*. A reader
    # that drops a field leaves the oracle's tree short of one node's label, and
    # javascript is byte-exact, so the difference is the reader every time.
    if "javascript" in pins:
        out += [Case(f"span/{p.stem}", GRAMMARS / "javascript.json",
                     oracle_home("javascript"), p, "span")
                for p in sorted(SPANS.glob("*.js"))]
    out += held_out()
    return out


def held_out() -> list[Case]:
    """The nineteen, addressable by name like anything else.

    They were reachable only through `breadth.py run`, the whole sweep, so
    `differential.py run --grammar=toml` answered `no case matches` - which two
    lanes read as "this grammar cannot be compared" rather than "this CLI does
    not enumerate it". toml's oracle was the only thing standing between the
    scanner lane and 3,535 bytes, and lua is the control for the extras
    predicate; a control nobody can run is not a control.

    They point at breadth's workspace rather than this one, because that is
    where their scanners and generated parsers already are. One oracle per
    grammar, not two - which is the same discipline as one scanner walk.

    Imported here rather than at the top: `breadth` imports this module, so the
    dependency only works in one direction at load time.
    """
    import breadth  # noqa: PLC0415 - deliberate, see above
    out = []
    for pin in sorted(load("breadth"), key=lambda p: p.name):
        src = breadth.source_of(pin.name)
        if src.exists():
            out.append(Case(f"held-out/{pin.name}", GRAMMARS / f"{pin.name}.json",
                            oracle_home(pin.name, breadth.LANG.parent), src, "held-out"))
    return out


def lay_out() -> None:
    """Write the cases this file carries. Probe grammars are written before the
    oracle generates from them, so the grammar the oracle builds and the grammar
    joints imports are one file rather than two copies."""
    for name, text in SOURCES.items():
        leaf = WORK / "case" / name
        leaf.parent.mkdir(parents=True, exist_ok=True)
        leaf.write_text(text, encoding="utf-8")
    for name, (doc, text) in PROBES.items():
        home = WORK / "probe" / name
        (home / "src").mkdir(parents=True, exist_ok=True)
        (home / "src" / "grammar.json").write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
        (home / "sample.txt").write_text(text, encoding="utf-8")


def built(name: str, home: Path) -> bool:
    """Is there a library the CLI will *use* rather than rebuild?

    Existing is not enough, and assuming it was cost a concurrent sweep two
    rows. The CLI recompiles whenever anything under `src/` is newer than the
    library - which is exactly what laying a scanner down does - and it says so
    itself when two processes get there at once: `Are you running multiple
    processes building to the same output location?`. So the predicate that
    decides whether a build needs the exclusive lock has to be their predicate,
    not `exists()`.
    """
    so = next((LIB / f"{name}{x}" for x in (".dylib", ".so") if (LIB / f"{name}{x}").exists()), None)
    if so is None:
        return False
    made = so.stat().st_mtime
    return all(f.stat().st_mtime <= made for f in (home / "src").glob("*") if f.is_file())


def unbuilt(case: Case) -> bool:
    """Would a build write anything? Asked before taking the exclusive lock.

    `flock` is not fair: a writer waiting behind a stream of readers waits for
    all of them, and a sweep is 45 cases over 11 languages, so a per-case
    exclusive lock taken unconditionally has each lane starving the other on
    every language in turn - 2 minutes became 20. Asking first turns 45
    exclusive acquisitions into nought on a warm tree, which is the state every
    acquisition after the first is in anyway.
    """
    src = case.lang / "src" / "grammar.json"
    return (not built(named(case.lang), case.lang) or not src.exists()
            or not (case.lang / "src" / "parser.c").exists()
            or digest(src) != digest(case.grammar))


def measure(case: Case) -> Report:
    def skip(why: str) -> Report:
        return Report(case, "skipped", why, 0, 0, [])

    if not case.source.exists():
        return skip(f"no source at {case.source.relative_to(ROOT)}")
    if not case.grammar.exists():
        return skip("grammar not resolved; run `python3 tool/grammars.py fetch`")
    try:
        # The build takes the exclusive side and the measurement the shared one,
        # in that order and never nested - a writer inside a reader is how a
        # readers-writer lock becomes a deadlock. `warm` has usually done this
        # already, in which case both are a digest check and a no-op.
        if unbuilt(case):
            with alone(named(case.lang)):
                oracle_build(case.lang, case.grammar)
                # The CLI compiles on first use, so the compile has to happen on
                # the exclusive side too. `warm` normally gets here first; this
                # covers callers that measure without warming, like breadth.py.
                if not built(named(case.lang), case.lang):
                    cli([str(TS), "parse", "-p", str(case.lang), "-q", str(case.source)], WORK)
        with alone(named(case.lang), writing=False):
            # Shared for the whole measurement: `-x`, `--cst` and `query` are
            # three processes and must be three faces of one library. Held here
            # rather than around each call, because the window that matters is
            # between them.
            doc = json.loads(case.grammar.read_text(encoding="utf-8"))
            blob = case.source.read_bytes()
            at = Lines(blob)
            theirs = xml_tree(oracle_run(case.lang, case.source, "-x"), at)
            full, hurt = reconciled(oracle_run(case.lang, case.source, "--cst"), at, theirs)
            if full is None:
                # Either the CST indentation lied (it does inside an error tree)
                # or this reader is wrong about one of the two formats. Refusing
                # is the only honest move: a comparison against a tree nobody
                # can confirm is noise wearing the clothes of a result.
                return skip("tree-sitter's CST and XML disagree with each other"
                            + (" (the tree has errors in it)" if hurt else ""))
            graft_fields(full, case.lang, case.source, declared(doc, "FIELD", "name"), at)
        roots, stop = ours_run(case)
    except (ValueError, KeyError, ET.ParseError, OSError) as e:
        return skip(str(e))

    extras = {e["name"] for e in doc.get("extras", []) if e.get("type") == "SYMBOL"}
    aliases = set(declared(doc, "ALIAS", "value"))
    out: list[Finding] = []
    if stop.kind == "whole" and len(roots) == 1:
        compare(roots[0], full, full.label(), out, Judge(extras, aliases, blob, False), root=True)
        return Report(case, "whole", stop.verdict, roots[0].count(), full.count(), out)

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
        return skip(f"stopped at once ({stop.verdict}); no root lines up with an oracle node")
    return Report(case, "prefix", f"{stop.verdict}; {held}/{len(roots)} roots anchored",
                  sum(r.count() for r in roots), full.count(), out)


# -------------------------------------------------------------------- the spans

SPANS = ROOT / "research" / "joinery" / "spans"


def spans() -> list[tuple[str, str, str, str]]:
    """Drive every reader of their stdout across every span shape.

    Twice a reader here has broken at a newline - `cst_tree` on a token spanning
    rows, then `graft_fields` on a *capture* spanning rows - and both times the
    eleven ledger programs had nothing multi-line to catch it. Their printers
    change shape at `end.row > start.row` in at least two places, so the honest
    assumption is that the next reader will too.

    So the shapes live in the repo rather than in a probe somebody has to
    remember, and every reader is pointed at all of them on every run. javascript
    hosts them because it has a multi-row block comment, a multi-row template
    literal and a field on an anonymous child - the three faces' three weak
    points in one grammar - and because it is byte-exact, so a difference here is
    the reader and never the parser.

    One row per fixture: the three readers' verdicts, `ok` or the refusal.
    """
    lang, want = oracle_home("javascript"), GRAMMARS / "javascript.json"
    oracle_build(lang, want)
    fields = declared(json.loads(want.read_text()), "FIELD", "name")
    out = []
    for src in sorted(SPANS.glob("*.js")) + sorted((SPANS / "errors").glob("*.js")):
        at = Lines(src.read_bytes())
        try:
            theirs = xml_tree(oracle_run(lang, src, "-x"), at)
            xml = f"ok, {theirs.count()} nodes"
        except (ValueError, ET.ParseError, OSError) as e:
            out.append((src.stem, f"BROKE: {e}", "not reached", "not reached"))
            continue
        try:
            full, hurt = reconciled(oracle_run(lang, src, "--cst"), at, theirs)
        except (ValueError, OSError) as e:
            out.append((src.stem, xml, f"BROKE: {e}", "not reached"))
            continue
        if full is None:
            # A refusal used to be a shrug here, and that is what let two
            # grammars sit `unjudged` on the board for a day. The indentation
            # rule is inverted rather than guessed at now, so nothing in this
            # directory has a reading left to fall back on: a CST the XML will
            # not confirm is the gate's own failure and has to fail it.
            out.append((src.stem, xml, f"BROKE: CST and XML disagree (errors={hurt})",
                        "not reached"))
            continue
        cst = f"ok, {full.count()} nodes"
        # Count fields, not just survival: this round's bug threw no exception,
        # it quietly grafted nothing.
        def borne(n: Node) -> int:
            return bool(n.field) + sum(borne(k) for k in n.kids)
        was = borne(full)
        try:
            graft_fields(full, lang, src, fields, at)
            got = f"ok, {was} -> {borne(full)} fields"
        except (ValueError, OSError) as e:
            got = f"BROKE: {e}"
        out.append((src.stem, xml, cst, got))
    return out


def broke(rows: list[tuple[str, str, str, str]]) -> int:
    return sum(1 for r in rows for v in r[1:] if v.startswith("BROKE"))


@contextlib.contextmanager
def alone(name: str, writing: bool = True) -> Iterator[None]:
    """Hold one grammar, so a rebuild cannot land under a lane that is reading.

    Four lanes share this checkout, so `TREE_SITTER_LIBDIR` moved the race from
    `~/.cache` into `.local/differential` rather than ending it: `lang/<name>/`
    and `lib/<name>.dylib` are still one mutable path keyed by a language name
    with no owner. Isolating a copy per lane would end it too, but it would also
    throw away the cache, and thirty generates and thirty compiles is minutes
    per lane - so the shared directory is worth keeping and the writes are worth
    serialising.

    Readers-writer, because the two hazards are different. A *build* must be
    alone: it writes `lang/<name>/src/parser.c` and the CLI writes
    `lib/<name>.dylib`, and the second writer of a `.dylib` produces a file the
    first lane is halfway through `dlopen`-ing. A *measurement* only has to be
    sure no build lands in the middle of it - one measurement is three
    invocations, and they must all see one library - so measurements share.

    Only the cold path ever takes the exclusive side twice: a warm
    `oracle_build` sees a matching digest and returns without writing. So the
    second lane through waits once, per language, on the first day, and every
    lane after that reads in parallel with every other.

    The wait is announced and the timeout refuses, because the failure this
    replaces was silent: a contended run came back as a skip that read exactly
    like a grammar we could not parse.

    **Re-entrant within one process**, so the lock can live in the function that
    writes rather than in each of the twelve callers that remember to. `flock`
    is per open file description, so a second `open` of the same lock in the
    same process conflicts with the first and a nested acquire would hang
    forever against itself - which is why this used to be a caller's job, and
    why three of the twelve callers did not do it. Re-entry keeps the depth and
    returns; the outermost holder releases. A *writer* nested inside a reader
    still refuses, loudly: that one is a genuine lock-order fault and upgrading
    a shared hold to an exclusive one is the deadlock the readers-writer split
    exists to avoid.
    """
    if (have := _HELD.get(name)) is not None:
        if writing and not have[1]:
            raise ValueError(f"{name}: a build inside a measurement - take "
                             f"alone({name!r}, writing=True) before the read, "
                             f"never inside it")
        _HELD[name] = (have[0] + 1, have[1])
        try:
            yield
        finally:
            held, mine = _HELD[name]
            if held > 1:
                _HELD[name] = (held - 1, mine)
            else:
                del _HELD[name]
        return
    lock = WORK / "lock"
    lock.mkdir(parents=True, exist_ok=True)
    fd = os.open(lock / f"{name}.lock", os.O_CREAT | os.O_RDWR, 0o644)
    began, said = time.monotonic(), False
    try:
        while True:
            try:
                fcntl.flock(fd, (fcntl.LOCK_EX if writing else fcntl.LOCK_SH) | fcntl.LOCK_NB)
                break
            except OSError:
                waited = time.monotonic() - began
                if waited > PATIENCE:
                    raise ValueError(
                        f"{CONTENDED} the {name} oracle after {waited:.0f}s; "
                        f"refusing rather than writing beside it") from None
                if not said:
                    print(f"  waiting on {name}: another lane is building it", file=sys.stderr)
                    said, _ = True, WAITED.add(name)
                time.sleep(0.2)
        if writing:
            os.write(fd, f"{os.getpid()}\n".encode())
        _HELD[name] = (1, writing)
        yield
    finally:
        _HELD.pop(name, None)
        with contextlib.suppress(OSError):
            fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def warm(picked: list[Case]) -> None:
    """Compile every language before anything is measured.

    One measurement is three CLI invocations - `-x`, `--cst`, then `query` - and
    the CLI compiles a grammar on first use. A compile landing *between* two of
    them serves the second invocation a different library from the first, and the
    comparison is then between two runtimes rather than two faces of one. Only
    `graft_fields` cross-checks, so that is where it surfaces, as its printer and
    its query disagreeing about a field; it refuses, which is right, and the case
    reads as skipped for a reason that has nothing to do with the case.

    Doing every compile up front leaves no window inside a measurement. It costs
    one extra parse per language on a cold cache and nothing on a warm one.
    """
    for lang in dict.fromkeys(c.lang for c in picked):
        src = next(c.source for c in picked if c.lang == lang)
        try:
            # The lock spans generate *and* the probe parse, because the probe is
            # what triggers the compile into LIB; holding only the generate would
            # leave the two lanes racing on the .dylib instead of the parser.c.
            with alone(named(lang)):
                oracle_build(lang, next(c.grammar for c in picked if c.lang == lang))
                cli([str(TS), "parse", "-p", str(lang), "-q", str(src)], WORK)
        except (OSError, ValueError):
            pass  # measure() reports it properly; this pass only pre-compiles.


# ------------------------------------------------------------------------ verbs

def run(picked: list[Case], as_json: bool, verbose: bool) -> int:
    # Taken before the measurement rather than after, so the stamp names the
    # tree the run started against; a lane landing something mid-run then shows
    # up as a later run disagreeing, which is the honest way round.
    mark = take(BIN)
    warm(picked)
    reports = [measure(c) for c in picked]
    if as_json:
        print(json.dumps({"oracle": oracle_ready(), "stamp": mark.as_dict(),
                          "case": [r.as_dict() for r in reports]}, indent=2))
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
    print(mark.line())
    # A skip caused by another lane is not a fact about the grammar, and it used
    # to read exactly like one. Say so, loudly, rather than letting a contended
    # run be quoted as a measurement.
    # A skip is only ever quotable if it is a fact about the grammar. These
    # reasons are facts about the machine - a library half-written, a lockfile
    # deleted underneath us, a printer and a query reading two different
    # libraries - and every one of them has been mistaken for a result at least
    # once. Say so unconditionally rather than only when this process is the one
    # that noticed it queued.
    fought = [r for r in reports if r.mode == "skipped" and any(m in r.why for m in FRAGILE)]
    if fought or WAITED:
        who = sorted({named(r.case.lang) for r in fought} | WAITED)
        print(f"differential: another lane was in the oracle workspace during this run "
              f"({', '.join(who)})."
              + (f" {len(fought)} skip(s) are that, not the grammar. Do not quote this run; "
                 "re-run it when the checkout is quiet." if fought else ""), file=sys.stderr)
    sys.stdout.flush()
    if span := sum(r.unexplained for r in reports if r.case.origin == "span"):
        print(f"differential: {span} of those are span fixtures, so a reader of "
              "tree-sitter's own output is wrong before the parser is; "
              "`differential.py spans` says which one", file=sys.stderr)
    if bad := sum(r.unexplained for r in reports):
        print(f"differential: {bad} difference(s) nobody owns", file=sys.stderr)
        return 1
    return 0


def survey(as_json: bool) -> int:
    """`spans`: the reader inventory, one row per shape. A reader that survives
    is a row too - the output is an inventory, not a bug list."""
    warm([Case("javascript", GRAMMARS / "javascript.json", oracle_home("javascript"),
               p, "span") for p in sorted(SPANS.glob("*.js"))])
    rows = spans()
    if as_json:
        print(json.dumps({"span": [dict(zip(("shape", "xml", "cst", "query"), r))
                                   for r in rows]}, indent=2))
        return 1 if broke(rows) else 0
    wide = max((len(r[0]) for r in rows), default=10) + 2
    print(f"{'span shape':<{wide}}{'xml_tree (-x)':<26}{'cst_tree (--cst)':<26}query")
    for shape, x, c, q in rows:
        print(f"{shape:<{wide}}{x:<26}{c:<26}{q}")
    hurt = broke(rows)
    print(f"\n{len(rows)} shapes x 3 readers · {hurt or 'none'} broke")
    return 1 if hurt else 0


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
        print(f"  {r.why}\n\n  -- joints ({stop.verdict})")
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
        json.dumps({"name": "joints-differential-oracle", "private": True,
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


def vacate() -> None:
    """Drop the CLI's lockfiles; keep the libraries this lane compiled.

    Also reaps the seats of lanes that are gone, since a shell that exits takes
    its pid with it and nothing else would ever remove the directory.
    """
    shutil.rmtree(SEAT / "tree-sitter", ignore_errors=True)
    for seat in (WORK / "seat").glob("*"):
        if seat == SEAT:
            continue
        if seat.name.isdigit():
            try:
                os.kill(int(seat.name), 0)
                continue  # its owner is still running
            except ProcessLookupError:
                pass
            except OSError:
                continue  # alive, just not ours to signal
        # Either its owner is gone, or it is a named lane nobody has used in a
        # day. A named seat has no pid to ask after, so age is the only owner
        # test there is; a lane still working touches its libraries constantly.
        elif time.time() - seat.stat().st_mtime < 86400:
            continue
        shutil.rmtree(seat, ignore_errors=True)


def main(argv: list[str]) -> int:
    atexit.register(vacate)
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
    if verb == "scanners":
        return fetch_scanners("all")
    if verb == "sandbox":
        return sandboxed()
    version = oracle_ready()
    if verb == "oracle":
        print(f"tree-sitter {version} at {TS}" if version else
              f"no tree-sitter CLI at {TS}\nrun `python3 tool/differential.py install` to put one there")
        return 0 if version else 1
    if verb not in ("run", "show", "list", "spans"):
        return oops(f"no such verb {verb!r}\n\n{USAGE}")
    if verb == "spans":
        if not version:
            return oops(f"no tree-sitter CLI at {TS}; nothing to read the output of")
        lay_out()
        return survey(as_json)
    try:
        lay_out()
        pins = {p.name for p in load()}
        picked = [c for c in cases(pins)
                  if (not want_case or c.name == want_case or c.name.endswith("/" + want_case))
                  and (not want_grammar or c.grammar.stem == want_grammar)
                  # A held-out grammar answers when it is asked for by name; a
                  # bare `run` stays the corpus and the spans, which is the
                  # slate cheap enough to be a gate. `breadth.py run` is still
                  # how you sweep all nineteen.
                  and (c.origin != "held-out" or want_case or want_grammar)]
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

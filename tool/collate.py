#!/usr/bin/env python3
"""Hold joints against the incumbent on the axes a byte comparison cannot see.

`plumb.py` asks whether a `built` byte was built *right*, byte-indexed, against
tree-sitter. It is one-directional by construction: every disagreement is scored
against joints, because the oracle is assumed correct. Buried in its own
limits paragraph is the evidence that assumption has a hole - **34,687 built
bytes have no verdict at all, because tree-sitter's own tree is in recovery
there**, and on `picorv32.v` the recovery reaches the root.

This is the other direction, and the axes that are not correctness at all.

Measured, that inherited 34,687 is **30,959**: `plumb`'s `unjudged` folds bytes
under a recovery region together with bytes the oracle's tree does not cover,
and only the first is a refusal. Both are correct counts of different things.

## The one rule that makes an improvement an improvement

Producing a tree where the incumbent produces an `ERROR` is **not** a win. An
honest ERROR beats a confident wrong tree, and this repository holds the proof:
swift's blind `multiline_comment` reads `/* c\\n   d */` as a
`prefix_expression` over a `multiplicative_expression` - one root, zero mends,
every byte `built`, every instrument here green. A consumer handed that tree
folds the wrong region and selects the wrong bytes with total confidence.
Tree-sitter's ERROR over the same input is *less* structure and *more* useful.

So a byte counts toward an improvement only when all three hold:

  1. tree-sitter refuses it (an `ERROR` or `MISSING` covers it), and
  2. joints builds it (it is inside a top-level root that has a child), and
  3. the structure joints puts there is adjudicated **right, by hand**,
     against the language's own grammar, with the adjudication written down.

Bytes failing (3) are a **gap wearing an improvement's clothes**, which is the
most dangerous row a scoreboard can carry. Bytes nobody adjudicated are
neither, and are reported as their own column rather than folded anywhere.

## The verbs

  refusal      per file: what each side refuses, what survives inside a refusal
  disputed     inside a recovery region, where the two trees disagree byte by
               byte - **evidence for an adjudication, never a verdict**, and
               `research/collate/RESULT-1-refusal.md` demonstrates why
  adjudicated  do the hand verdicts still describe both live trees; exits 1 if
               any has drifted, and a drifted row counts toward nothing
  probe        both trees over one span, side by side, for judging the next one
  honesty      of the bytes each side reads wrong, how many does it mark
  cost         folio against dylib, mint against generate+cc, cold throughput,
               and the bytes of hand-written scanner C each grammar ships
  keystroke    microseconds per typed character, each side on its own inner
               clock - tree-sitter's headline claim, measured
  prove        every guard above, asked to say no where no is the right answer

`--json` on every read verb; `--grammar=<name>` (repeatable) narrows any of
them, and a name that names nothing is an error rather than a silent full
sweep. `--runs N` sets how many times a timed verb repeats (minimum wins, since
the minimum is the run least interrupted by the other nine agents here).

  JOINTS_BIN=<path>   measure a pinned binary (`tool/pin.py`), never `zig-out`

Exit 0 measured, 1 a clean negative (a verdict drifted, a guard cannot say no),
2 could not run.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import NamedTuple

sys.path.insert(0, str(Path(__file__).resolve().parent))

import differential as d  # noqa: E402 - the path has to be set first
import standing  # noqa: E402
import stamp  # noqa: E402
from order import folio_for  # noqa: E402
from rung1 import pairs  # noqa: E402
from walls import roster  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
GRAMMARS = ROOT / "upstream" / "grammars"
BIN = Path(os.environ.get("JOINTS_BIN", ROOT / "zig-out" / "bin" / "joints"))
WORK = Path(os.environ.get("JOINTS_WORK", ROOT / ".local" / "standing"))
OUT = ROOT / ".local" / "collate"
PATIENCE = 240

# What tree-sitter calls a node it is not standing behind. `MISSING` is a node in
# the tree with a zero-width span, so its bytes are nil and its *count* is the
# measurement; `ERROR` carries an extent and is the one worth painting.
REFUSED = ("ERROR", "MISSING")
SUMMARY = re.compile(r"Parse:\s+([\d.]+) ms")


class Their(NamedTuple):
    """Tree-sitter over one file, and what it refused."""

    ok: bool
    why: str
    code: int  # the CLI's own exit status: 1 means "this tree has an error in it"
    ms: float
    nodes: int
    error_spans: tuple[tuple[int, int], ...]
    error_bytes: int
    missing: int  # zero-width MISSING nodes, which have no bytes to paint
    inside_named: int  # named nodes that survive *inside* an error region
    inside_bytes: int  # and the bytes their leaves cover, deduplicated
    root_is_error: bool


class Ours(NamedTuple):
    """Joints over the same file, in the board's own words."""

    ok: bool
    why: str
    built: int
    damage: int
    roots: int
    leaves: int
    mends: int
    blind: int
    kind: str


class Row(NamedTuple):
    name: str
    size: int
    ours: Ours
    theirs: Their
    # Bytes tree-sitter refuses that joints builds. **A candidate, not a win** -
    # nothing here is adjudicated, and the whole point of the word is that it
    # stays unspent until somebody reads the tree.
    candidate: int = 0


# --------------------------------------------------------------------- corpus

class Case(NamedTuple):
    name: str
    grammar: Path
    lang: Path
    source: Path

    @property
    def size(self) -> int:
        return self.source.stat().st_size


def slate() -> list[Case]:
    """The same thirty rows the board has, pointed at the same sources and the
    same oracle homes `differential.py` generated - one oracle per grammar,
    because php's and typescript's scanners both climb to `../../common/
    scanner.h` and a second root re-opens that collision."""
    import breadth  # noqa: PLC0415 - breadth imports differential; keep it one-way
    corpus = {n for n, _ in pairs()}
    return [Case(name, GRAMMARS / f"{name}.json",
                 d.oracle_home(name) if name in corpus
                 else d.oracle_home(name, breadth.LANG.parent), src)
            for name, src in roster()]


def narrow(cases: list[Case], want: list[str] | None) -> list[Case]:
    if not want:
        return cases
    known = {c.name for c in cases}
    if bad := [w for w in want if w not in known]:
        raise SystemExit(f"collate: no such grammar: {', '.join(bad)}")
    return [c for c in cases if c.name in want]


# ------------------------------------------------------------------ their side

def merge(spans: list[tuple[int, int]]) -> list[tuple[int, int]]:
    """Disjoint, ascending. A byte inside two roots is one byte."""
    out: list[tuple[int, int]] = []
    for a, b in sorted(spans):
        if out and a <= out[-1][1]:
            out[-1] = (out[-1][0], max(out[-1][1], b))
        elif b > a:
            out.append((a, b))
    return out


def union(spans: list[tuple[int, int]]) -> int:
    return sum(b - a for a, b in merge(spans))


def refusals(node: d.Node, out: list[tuple[int, int]]) -> int:
    """Every `ERROR` extent, and the count of zero-width `MISSING` nodes.

    An ERROR's own span is taken whole and its children are not descended into
    for *further* errors - a nested ERROR is inside a span already counted, and
    counting it again would say nothing new. The children are still walked for
    what survives, which is `survivors` below and a different question.
    """
    missing = 0
    if node.name == "MISSING" or node.name.startswith("MISSING"):
        missing += 1
    if node.name == "ERROR":
        out.append((node.start, node.end))
    for kid in node.kids:
        missing += refusals(kid, out)
    return missing


def survivors(node: d.Node, inside: bool = False) -> tuple[int, list[tuple[int, int]]]:
    """What tree-sitter still hands back from **inside** an error region.

    A root-level `ERROR` is not an empty tree and must not be reported as one.
    tree-sitter's recovery adopts every subtree it had already reduced, so the
    honest reading of `picorv32.v` is not "the oracle produced nothing" but
    "the oracle produced structure and said the structure is untrustworthy" -
    which is a *feature* and belongs on tree-sitter's side of the scoreboard.

    Counted as named leaves only. An interior node's bytes are its children's
    bytes and adding both double-counts the same evidence.
    """
    count, spans = 0, []
    here = inside or node.name == "ERROR"
    if here and node.named and not node.kids and not node.name.startswith(REFUSED):
        count, spans = 1, [(node.start, node.end)]
    for kid in node.kids:
        c, s = survivors(kid, here)
        count += c
        spans += s
    return count, spans


def theirs(case: Case, blob: bytes) -> tuple[Their, d.Node | None]:
    """One oracle parse, read twice and cross-checked against its own exit code.

    The XML is the tree. The exit status is the independent witness: tree-sitter
    exits 1 when the tree it printed has an error in it, and that is a channel
    my parser cannot influence. When the two disagree the row is a **refusal**,
    not a measurement - "my harness lost the tree" and "the oracle refused the
    file" produce the same absence, and reading the first as the second is how
    a scoreboard invents bytes for its own column.
    """
    at = d.Lines(blob)
    try:
        with d.alone(d.named(case.lang), writing=False):
            # The owner's argv and the owner's refusal rule; the exchange itself
            # stays here because the two checks below need the exit status, which
            # is the one thing `oracle_full` cannot hand back.
            got = d.cli(d.oracle_argv(case.lang, case.source.resolve(), "-x"), d.WORK)
        # Uncapped: this is `gripe`, and its longest sentence is the one telling
        # you which commit's external scanner to fetch, which is the whole use.
        if why := d.refused(got):
            return blank_them(why), None
        root = d.xml_tree(got.stdout, at)
    except (ValueError, KeyError, ET.ParseError, OSError) as e:
        return blank_them(str(e)[:90]), None
    spans: list[tuple[int, int]] = []
    missing = refusals(root, spans)
    seen, kept = survivors(root)
    ms = float(m[1]) if (m := SUMMARY.search(got.stdout)) else 0.0
    hurt = bool(spans) or bool(missing)
    if hurt != (got.returncode == 1):
        return blank_them(f"tree says hurt={hurt}, exit says {got.returncode}"), None
    return Their(True, "", got.returncode, ms, count(root), tuple(sorted(spans)),
                 union(spans), missing, seen, union(kept), root.name == "ERROR"), root


def blank_them(why: str) -> Their:
    return Their(False, why, -1, 0.0, 0, (), 0, 0, 0, 0, False)


def count(node: d.Node) -> int:
    return 1 + sum(count(k) for k in node.kids)


# -------------------------------------------------------------------- our side

def ours(case: Case) -> tuple[Ours, list[tuple[int, int]], list[Leaf]]:
    """Joints over the same file, in the board's own words and its own function.

    `built` is `standing.tops` - the board's definition, imported rather than
    restated, because two instruments that each derive `built` are two
    instruments that will eventually disagree about it while both printing the
    word.
    """
    folio = folio_for(case.name, WORK)
    if folio is None:
        return blank_us("no folio"), [], []
    size = case.source.stat().st_size
    got = stamp.ask(BIN, folio, case.source, tree=True, patience=PATIENCE)
    if got.kind == "timeout":
        return blank_us("joints timed out"), [], []
    top = standing.tops(standing.rows(got.tree))
    stands = merge([(a, b) for _, a, b, kid in top if kid])
    built = union(stands)
    return (Ours(True, "", built, size - built, len(top),
                 sum(1 for *_, kid in top if not kid), got.mends, got.blind, got.kind),
            stands, mine(got.tree))


def blank_us(why: str) -> Ours:
    return Ours(False, why, 0, 0, 0, 0, 0, 0, "")


class Leaf(NamedTuple):
    name: str
    named: bool
    start: int
    end: int
    leaf: bool

    @property
    def kind(self) -> tuple[str, bool]:
        return (self.name, self.named)

    def label(self) -> str:
        return self.name if self.named else f'"{self.name}"'


def flatten(node: d.Node, out: list[Leaf] | None = None) -> list[Leaf]:
    out = [] if out is None else out
    out.append(Leaf(node.name, node.named, node.start, node.end, not node.kids))
    for kid in node.kids:
        flatten(kid, out)
    return out


def mine(tree: str) -> list[Leaf]:
    """Joints's forest, read by `standing.rows` - the same reader the board
    counts `built` with, so this is a split of `built` and not a second opinion
    about which bytes it holds."""
    seen = standing.rows(tree)
    out = []
    for i, (wide, body, a, b) in enumerate(seen):
        _, name, named, _ = d.head(body)
        out.append(Leaf(name, named, a, b, i + 1 >= len(seen) or seen[i + 1][0] <= wide))
    return out


def paint(nodes: list[Leaf], size: int) -> list[int]:
    """Per byte, the index of the deepest node over it, or -1. Pre-order slice
    assignment, so the last writer of a byte is the deepest node covering it."""
    who = [-1] * size
    for i, n in enumerate(nodes):
        a, b = max(n.start, 0), min(n.end, size)
        if b > a:
            who[a:b] = [i] * (b - a)
    return who


SOLID = ("PATTERN", "TOKEN", "IMMEDIATE_TOKEN")
WRAPS = ("PREC", "PREC_LEFT", "PREC_RIGHT", "PREC_DYNAMIC", "FIELD", "ALIAS")


def lexical(grammar: Path) -> set[str]:
    """Which of this grammar's rules are **terminals**, read off the grammar.

    This is the repair for the one printer defect that would otherwise make
    every number below flattering. `tree-sitter parse -x` writes an anonymous
    node as bare text, so `(integer_vector_type "reg")` arrives in the XML as a
    childless `integer_vector_type`. A leaf comparison reads that as a leaf,
    finds joints's anonymous `"reg"` under the same bytes, and files 450 bytes
    across 150 sites as tree-sitter disagreeing with us. It is not a
    disagreement at all: it is one wrapper node, and the token underneath is the
    same token on both sides. The first run of this file reported exactly that,
    and every one of those 150 rows pointed the way that made joints look
    right.

    The `--cst` printer does carry an anonymous node's type, and it is what
    `plumb` uses - but `differential.reconciled` refuses it whenever the CST and
    the XML disagree, and on a tree in recovery they always do (checked on both
    error files: neither indentation reading matches). So the CST is not
    available on precisely the files this verb exists for.

    The grammar is, and it is the contract both parsers were built from. A rule
    whose body is a `PATTERN` or a `TOKEN(...)` is lexed whole and can have no
    child, so a childless XML node of that name really is a leaf. A rule whose
    body is a `CHOICE` of `STRING`s - `integer_vector_type`, `port_direction`,
    `assignment_operator` - is a wrapper with an invisible anonymous child, and
    bytes under it are counted `interstice` and never judged. `simple_identifier`
    is a `PATTERN` and stays judged, which is what keeps the finding that
    matters: tree-sitter's recovery reading the keyword `parameter` as an
    identifier is a real reading, not a hidden wrapper.

    Conservative on purpose. A bare `STRING` rule is excluded even though it is
    usually collapsed, because being wrong in that direction only ever *drops*
    evidence from a column this lane wants to fill.
    """
    doc = json.loads(grammar.read_text(encoding="utf-8"))
    out = set()
    for name, rule in doc.get("rules", {}).items():
        while isinstance(rule, dict) and rule.get("type") in WRAPS:
            rule = rule.get("content", {})
        if isinstance(rule, dict) and rule.get("type") in SOLID:
            out.add(name)
    return out


def alias_pairs(grammar: Path) -> set[frozenset[str]]:
    """Every rename the grammar itself declares, as the unordered pair.

    The *pair*, never the set of alias values: `identifier` is a declared alias
    value in three of these grammars, so a name test excuses `else`-read-as-
    `identifier` as house style. Same rule `plumb` arrived at, and it is the
    single change that most moved that lane's conclusions.
    """
    out: set[frozenset[str]] = set()

    def walk(node: object) -> None:
        if isinstance(node, dict):
            if node.get("type") == "ALIAS" and isinstance(node.get("value"), str):
                inner = node.get("content") or {}
                was = (inner.get("name") if inner.get("type") == "SYMBOL"
                       else inner.get("value") if inner.get("type") == "STRING" else None)
                if isinstance(was, str) and was != node["value"]:
                    out.add(frozenset((was, node["value"])))
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)

    walk(json.loads(grammar.read_text(encoding="utf-8")).get("rules", {}))
    return out


class Run(NamedTuple):
    start: int
    end: int
    ours: str
    theirs: str

    @property
    def width(self) -> int:
        return self.end - self.start


class Dispute(NamedTuple):
    """Joints's built bytes judged against an oracle that is **in recovery**.

    `plumb` refuses these deliberately and correctly: a tree in recovery is not
    a contract. But refusing them is what turned the corpus's #1 damage row into
    a blank column, and a blank column is what got read as a win. So they are
    judged here under a weaker oracle, said out loud - tree-sitter's *lexer*
    still named those tokens, and the lexer is what a leaf comparison measures.

    A number from this verb is evidence for a hand adjudication, never a verdict
    on its own. That is the whole difference between this and a scoreboard.
    """

    name: str
    built: int
    agree: int
    regrouped: int
    relabelled: int
    renamed: int
    interstice: int
    silent: int  # the oracle has no node here at all
    worst: tuple[Run, ...]
    # (ours, theirs) -> (bytes, occurrences), every disagreement, not the widest.
    # Separate from `worst` because **frequency and cost are decoupled** here the
    # same way they are on the wall board: the widest run and the commonest pair
    # are different rows, and a ranking built from one routes a reader wrong.
    pairs: tuple[tuple[str, str, int, int], ...] = ()

    @property
    def judged(self) -> int:
        return self.agree + self.regrouped + self.relabelled + self.renamed


def dispute(case: Case, blob: bytes, stands: list[tuple[int, int]],
            us: list[Leaf], them: list[Leaf], top: int = 8) -> Dispute:
    o_who, t_who = paint(us, len(blob)), paint(them, len(blob))
    renames, terminals = alias_pairs(case.grammar), lexical(case.grammar)
    tally = dict.fromkeys(("agree", "regrouped", "relabelled", "renamed",
                           "interstice", "silent"), 0)
    runs: list[Run] = []
    run: list[int] | None = None

    def close() -> None:
        nonlocal run
        if run is not None:
            runs.append(Run(run[0], run[1], spell(us, o_who, run[0]),
                            spell(them, t_who, run[0])))
            run = None

    for lo, hi in stands:
        for i in range(lo, hi):
            t = them[t_who[i]] if t_who[i] >= 0 else None
            if t is None or t.name.startswith(REFUSED):
                tally["silent"] += 1
                close()
                continue
            if not t.leaf or t.name not in terminals:
                # Either a real interior node, or a childless XML node whose
                # grammar rule is a wrapper hiding an anonymous token. Both are
                # node shaping, and neither is a byte read differently.
                tally["interstice"] += 1
                close()
                continue
            o = us[o_who[i]] if o_who[i] >= 0 else None
            if o is not None and o.kind == t.kind:
                tally["agree"] += 1
                close()
                continue
            same = o is not None and (o.start, o.end) == (t.start, t.end)
            if same and frozenset((o.name, t.name)) in renames:
                tally["renamed"] += 1
                close()
                continue
            tally["relabelled" if same else "regrouped"] += 1
            if run is not None and run[1] == i:
                run[1] = i + 1
            else:
                close()
                run = [i, i + 1]
        close()
    close()
    seen: dict[tuple[str, str], list[int]] = {}
    for r in runs:
        got = seen.setdefault((r.ours, r.theirs), [0, 0])
        got[0] += r.width
        got[1] += 1
    return Dispute(case.name, sum(b - a for a, b in stands), tally["agree"],
                   tally["regrouped"], tally["relabelled"], tally["renamed"],
                   tally["interstice"], tally["silent"],
                   tuple(sorted(runs, key=lambda r: -r.width)[:top]),
                   tuple(sorted(((o, t, b, n) for (o, t), (b, n) in seen.items()),
                                key=lambda p: -p[2])))


def spell(nodes: list[Leaf], who: list[int], at: int) -> str:
    return nodes[who[at]].label() if who[at] >= 0 else "—"


def chain(nodes: list[Leaf], a: int, b: int) -> list[str]:
    """Every node of one tree whose extent is exactly `[a, b)`, outermost first.

    The unit a hand adjudication argues over. Two parsers that cut the same
    bytes out and call them different things is a question with an answer; two
    parsers that cut differently is a different question, and `enclosing` below
    is the one to ask then.
    """
    return [n.label() for n in nodes if (n.start, n.end) == (a, b)]


def enclosing(nodes: list[Leaf], a: int, b: int) -> str:
    inside = [n for n in nodes if n.start <= a and b <= n.end]
    return f"{inside[-1].label()} [{inside[-1].start},{inside[-1].end})" if inside else "—"


def overlap(a: list[tuple[int, int]], b: list[tuple[int, int]]) -> list[tuple[int, int]]:
    """The bytes in both span sets, as merged spans."""
    out: list[tuple[int, int]] = []
    for lo, hi in sorted(a):
        for x, y in sorted(b):
            if y <= lo:
                continue
            if x >= hi:
                break
            out.append((max(lo, x), min(hi, y)))
    return out


# ----------------------------------------------------------------- the census

def census(cases: list[Case]) -> list[Row]:
    out = []
    for case in cases:
        blob = case.source.read_bytes()
        us, stands, _ = ours(case)
        them, _ = theirs(case, blob)
        both = union(overlap(stands, list(them.error_spans))) if us.ok and them.ok else 0
        out.append(Row(case.name, len(blob), us, them, both))
    return out


def disputes(cases: list[Case]) -> list[Dispute]:
    """The bytes `plumb` goes silent on, judged against the oracle anyway."""
    out = []
    for case in cases:
        blob = case.source.read_bytes()
        us, stands, ours_leaves = ours(case)
        them, root = theirs(case, blob)
        if not us.ok or root is None:
            continue
        out.append(dispute(case, blob, stands, ours_leaves, flatten(root)))
    return out


# ---------------------------------------------------------------- the honesty

class Honest(NamedTuple):
    """Which parser tells a consumer more truthfully **where** it is untrustworthy.

    Not "who is right more often" - that is the dispute column. This asks the
    question the amendment put: given that a file did not parse cleanly, does
    the tree a consumer receives *mark* the part that cannot be trusted?

    Each side flags in its own vocabulary. Tree-sitter flags in-band, with an
    `ERROR` or `MISSING` node a walker trips over. Joints flags by *absence* -
    a byte with no built root over it is `orphan`, `rubble` or `spoil`, and the
    board's `damage` is the union. Both are answerable with the same question:
    of the bytes we know that side reads wrong, how many did it flag?
    """

    name: str
    size: int
    ours_flag: int  # damage: bytes joints puts no root over
    theirs_flag: int  # bytes under an ERROR or MISSING
    misread: int  # joints's, where the oracle is sound enough to say so
    ours_caught: int  # ... of those, how many joints flagged
    blind: int  # externals joints declares it cannot lex, in the run's own words
    ok: bool = True

    @property
    def recall(self) -> float | None:
        """Of joints's known misreadings, the share it flagged. See `honesty`
        for why this is an identity and not a statistic.

        `None` where there was nothing to catch. A row with no misread byte
        cannot fail to flag one, so a `0.00` printed there is not this parser
        catching nothing - it is the row having no question in it. The two read
        the same and mean opposite things, and it is the second that carries the
        board: the identity below is asserted over every row and *exercised*
        only by the rows this property does not blank.
        """
        return self.ours_caught / self.misread if self.misread else None

    @property
    def alarm(self) -> float:
        return self.ours_flag / self.size if self.size else 0.0

    @property
    def their_alarm(self) -> float:
        return self.theirs_flag / self.size if self.size else 0.0


def honesty(cases: list[Case]) -> list[Honest]:
    """P4, asserted rather than measured.

    `plumb`'s misread bytes are a subset of `built`; `damage` is the complement
    of `built` over the file. So a misread byte cannot be a flagged byte - the
    two sets are disjoint by construction, and joints's recall over its own
    misreadings is exactly 0.00 on every grammar, forever, for as long as the
    board is defined this way. This verb computes the intersection anyway and
    would report it if it were ever non-empty, because a prediction that the
    instrument is allowed to assume is not a prediction.
    """
    out = []
    for case in cases:
        blob = case.source.read_bytes()
        us, stands, mine_ = ours(case)
        them, root = theirs(case, blob)
        if not us.ok or root is None:
            out.append(Honest(case.name, len(blob), 0, 0, 0, 0, 0, False))
            continue
        # Judge only where the oracle is not itself in recovery. Inside its own
        # ERROR its names are a lexer's opinion, and `disputes` is where those go.
        sound = subtract(stands, merge(list(them.error_spans)))
        d_ = dispute(case, blob, sound, mine_, flatten(root))
        misread = d_.regrouped + d_.relabelled
        damage = subtract([(0, len(blob))], stands)
        caught = union(overlap(sound, damage))  # the identity: must be 0
        out.append(Honest(case.name, len(blob), len(blob) - us.built,
                          them.error_bytes, misread, caught, us.blind))
    return out


def subtract(keep: list[tuple[int, int]],
             drop: list[tuple[int, int]]) -> list[tuple[int, int]]:
    """`keep` minus `drop`, as merged spans."""
    out: list[tuple[int, int]] = []
    for lo, hi in merge(keep):
        at = lo
        for x, y in merge(drop):
            if y <= at or x >= hi:
                continue
            if x > at:
                out.append((at, min(x, hi)))
            at = max(at, y)
            if at >= hi:
                break
        if at < hi:
            out.append((at, hi))
    return out


def show_honesty(rows: list[Honest]) -> None:
    ok = [r for r in rows if r.ok]
    print(f"\n  {'grammar':<14}{'bytes':>9}{'damage':>9}{'%':>7}  |{'ERROR':>9}{'%':>7}"
          f"  |{'misread':>9}{'flagged':>9}{'recall':>8}{'blind':>7}")
    for r in rows:
        if not r.ok:
            print(f"  {r.name:<14}{r.size:>9,}   not measured")
            continue
        got = "       —" if r.recall is None else f"{r.recall:>8.2f}"
        print(f"  {r.name:<14}{r.size:>9,}{r.ours_flag:>9,}{r.alarm:>7.1%}  |"
              f"{r.theirs_flag:>9,}{r.their_alarm:>7.1%}  |{r.misread:>9,}"
              f"{r.ours_caught:>9,}" + got + f"{r.blind:>7}")
    if not ok:
        return
    miss, caught = sum(r.misread for r in ok), sum(r.ours_caught for r in ok)
    tried = [r for r in ok if r.recall is not None]
    print(f"\n  {miss:,} bytes joints reads wrong where the oracle is sound; "
          f"it flags {caught:,} of them — recall "
          + (f"{caught / miss:.2f}" if miss else "— (nothing to catch)"))
    print("  and that is an identity, not a score: misread bytes are inside "
          "`built`,\n  `damage` is everything outside it, so the two sets cannot "
          "intersect.")
    print(f"  {len(tried)} of {len(ok)} row(s) exercise it. The other "
          f"{len(ok) - len(tried)} print `—` rather than `0.00`: with no misread"
          f"\n  byte in them they cannot fail to flag one, and a vacuous row is "
          f"not\n  evidence for the identity it is sitting under.")
    hurt = [r for r in ok if r.theirs_flag]
    print(f"  tree-sitter marks {sum(r.theirs_flag for r in ok):,} bytes untrustworthy "
          f"in-band, over {len(hurt)} of {len(ok)} files")
    blind = [r for r in ok if r.blind]
    print(f"  joints names an external it cannot lex on {len(blind)} of {len(ok)} "
          f"files, on stderr — a channel no tree walker reads")


def show_disputes(rows: list[Dispute], blobs: dict[str, bytes], top: int) -> None:
    print(f"\n  {'grammar':<14}{'built':>8}{'agree':>8}{'regroup':>8}{'relabel':>8}"
          f"{'rename':>7}{'interst':>8}{'silent':>7}   agree/judged")
    for r in rows:
        share = f"{r.agree / r.judged:.1%}" if r.judged else "—"
        print(f"  {r.name:<14}{r.built:>8,}{r.agree:>8,}{r.regrouped:>8,}"
              f"{r.relabelled:>8,}{r.renamed:>7,}{r.interstice:>8,}{r.silent:>7,}   {share:>7}")
    for r in rows:
        if not r.pairs:
            continue
        print(f"\n  {r.name}: every disagreement, by bytes — ours · theirs")
        for o, t, b, n in r.pairs[:top]:
            print(f"    {b:>7,}B  x{n:<6,} {o} · {t}")
        rest = sum(p[2] for p in r.pairs[top:])
        if rest:
            print(f"    {rest:>7,}B  in {len(r.pairs) - top} further pairs")
        print(f"  {r.name}: the widest single runs")
        for run in r.worst[:4]:
            text = blobs[r.name][run.start:run.end].decode("utf8", "replace")
            print(f"    [{run.start:>6},{run.end:>6}) {run.width:>5}B  "
                  f"ours {run.ours} · theirs {run.theirs}  {text[:60]!r}")


def show(rows: list[Row]) -> None:
    print(f"\n  {'grammar':<19}{'bytes':>8}{'built':>8}{'damage':>8}{'mends':>7}"
          f"  |{'ERROR':>8}{'MISS':>5}{'kept':>7}{'nodes':>8}  {'candidate':>9}  why")
    for r in rows:
        t, o = r.theirs, r.ours
        why = t.why or o.why or ("root ERROR" if t.root_is_error else "")
        print(f"  {r.name:<19}{r.size:>8,}{o.built:>8,}{o.damage:>8,}{o.mends:>7,}"
              f"  |{t.error_bytes:>8,}{t.missing:>5}{t.inside_bytes:>7,}{t.nodes:>8,}"
              f"  {r.candidate:>9,}  {why}")
    ok = [r for r in rows if r.theirs.ok and r.ours.ok]
    hurt = [r for r in ok if r.theirs.error_bytes or r.theirs.missing]
    print(f"\n  {len(hurt)} of {len(ok)} files carry an oracle ERROR or MISSING")
    total = sum(r.theirs.error_bytes for r in ok)
    cand = sum(r.candidate for r in ok)
    print(f"  {total:,} bytes under an oracle ERROR; {cand:,} of them joints builds")
    if top := sorted(hurt, key=lambda r: -r.theirs.error_bytes)[:2]:
        share = sum(r.theirs.error_bytes for r in top) / total if total else 0.0
        print(f"  top two ({', '.join(r.name for r in top)}) are {share:.1%} of that total")
    if bad := [r.name for r in rows if not r.theirs.ok or not r.ours.ok]:
        print(f"  refused, not measured: {', '.join(bad)}")


# ------------------------------------------------------------------- the cost

class Cost(NamedTuple):
    """One grammar, priced on both sides for the same outcome: this language,
    parsing, starting from the `grammar.json` both of them read."""

    name: str
    size: int  # the corpus file, so throughput is comparable
    folio: int  # bytes of artifact joints needs at run time
    mint_ms: float  # grammar.json -> that artifact
    dylib: int  # bytes of artifact tree-sitter needs at run time
    gen_ms: float  # grammar.json -> parser.c
    cc_ms: float  # parser.c (+ scanner) -> dylib
    parser_c: int
    scanner: int  # bytes of hand-written C the grammar ships, 0 if none
    ours_ms: float  # in-parser time, no process, no print
    theirs_ms: float  # their own reported parse time, same exclusions
    why: str = ""

    @property
    def build_ours(self) -> float:
        return self.mint_ms

    @property
    def build_theirs(self) -> float:
        return self.gen_ms + self.cc_ms

    @property
    def bytes_ms(self) -> float:
        return self.size / self.ours_ms if self.ours_ms else 0.0

    @property
    def their_bytes_ms(self) -> float:
        return self.size / self.theirs_ms if self.theirs_ms else 0.0

    @property
    def slower(self) -> float:
        """Joints's time per byte over tree-sitter's. Over 1.0 is a loss."""
        return self.ours_ms / self.theirs_ms if self.theirs_ms else 0.0

    @property
    def resolved(self) -> bool:
        """Is the slope above the clock's own noise?

        The slope is a difference of two process timings, and two process
        timings on a loaded laptop agree to about a millisecond. If K-1 parses
        do not add up to that, the row is the noise floor wearing a throughput
        number - json's 774 bytes came back at 254,965 B/ms, which is 3
        microseconds of parse read off a 1 ms ruler. Unresolved rows are printed
        and excluded from every median.
        """
        return self.ours_ms * (REPEAT - 1) >= FLOOR_MS


def timed(cmd: list[str], cwd: Path = ROOT, patience: float = PATIENCE,
          env: dict[str, str] | None = None) -> tuple[float, subprocess.CompletedProcess[str]]:
    now = time.perf_counter()
    got = subprocess.run(cmd, capture_output=True, text=True, timeout=patience,
                         cwd=cwd, env=env)
    return (time.perf_counter() - now) * 1000, got


REPEAT = 8  # copies of the file each side parses inside one process
FLOOR_MS = 1.0  # two process timings on this machine agree to about this much
SPEED = re.compile(r"average speed:\s*(\d+)\s*bytes/ms")


def ours_speed(case: Case, folio: Path, runs: int, repeat: int = REPEAT) -> float:
    """Joints's milliseconds per parse, from the **slope** of "parse it N times".

    The first draft of this timed one process against a process over an empty
    file and subtracted. It reported go at 0.1 ms against tree-sitter's 46.6 ms
    over the same file - a 400x win, on a machine where tree-sitter's own clock
    says it parses 4 MB/s. Both numbers were process-start jitter with a parse
    somewhere inside them, and the sign of the noise picked the winner. That is
    Q8, and it took one run to arrive.

    Handing the same file over K times and then once measures the same startup,
    the same folio read, and K-1 extra parses; the difference over K-1 is a
    parse. **It is the unflattering measure of the two below**: it carries the
    open, the read, the tree build and the free, where tree-sitter's own clock
    carries only `ts_parser_parse`. Charged that way on purpose.
    """
    argv = lambda n: [str(BIN), "parse", str(folio), *[str(case.source)] * n, "--quiet"]
    best = float("inf")
    for _ in range(runs):
        many, one = timed(argv(repeat))[0], timed(argv(1))[0]
        best = min(best, (many - one) / (repeat - 1))
    return max(best, 0.0)


def theirs_speed(case: Case, runs: int, repeat: int = REPEAT) -> float:
    """Tree-sitter's, from `--stat`, which is **its own** clock around the parse.

    Not a slope, and not for lack of trying: `tree-sitter parse` re-resolves the
    language per path, so the same slope over its CLI reads 219 ms for a 5 KB go
    file against a wall clock that says its parser runs at 6,532 bytes/ms. That
    number would be a 600x win for us and it would be a measurement of their
    argument loop. `--stat` reports bytes/ms over the repeats and skips it.
    """
    argv = [str(d.TS), "parse", "-p", str(case.lang), "--quiet", "--stat",
            *[str(case.source.resolve())] * repeat]
    best = 0.0
    for _ in range(runs):
        _, got = timed(argv, d.WORK, env=ts_env())
        if hit := SPEED.search(got.stdout):
            best = max(best, float(hit.group(1)))
    return case.size / best if best else 0.0


def ts_env() -> dict[str, str]:
    d.LIB.mkdir(parents=True, exist_ok=True)
    d.SEAT.mkdir(parents=True, exist_ok=True)
    return {**os.environ, "TREE_SITTER_LIBDIR": str(d.LIB), "XDG_CACHE_HOME": str(d.SEAT)}


def cost(case: Case, runs: int, fresh: bool) -> Cost:
    size = case.source.stat().st_size
    folio = OUT / "folio" / f"{case.name}.folio"
    folio.parent.mkdir(parents=True, exist_ok=True)
    folio.unlink(missing_ok=True)
    mint_ms, got = timed([str(BIN), "mint", str(case.grammar), "-o", str(folio)], ROOT)
    if got.returncode != 0 or not folio.exists():
        return Cost(case.name, size, 0, 0, 0, 0, 0, 0, 0, 0, 0, "mint refused")
    lang, src = case.lang, lang_src(case.lang)
    scanner = sum(p.stat().st_size for p in scanners(lang))
    if fresh:
        (src / "parser.c").unlink(missing_ok=True)
        for stale in d.LIB.glob(f"{d.named(lang)}.*"):
            stale.unlink()
    gen_ms, got = timed(d.builder_argv(), lang, env=ts_env())
    if got.returncode != 0:
        return Cost(case.name, size, folio.stat().st_size, mint_ms, 0, gen_ms, 0, 0,
                    scanner, 0, 0, f"generate: {d.gripe(got.stderr)}")
    parser_c = (src / "parser.c").stat().st_size if (src / "parser.c").exists() else 0
    cc_ms, got = timed(d.oracle_argv(lang, case.source.resolve(), "-q"),
                       d.WORK, env=ts_env())
    lib = next((p for p in d.LIB.glob(f"{d.named(lang)}.*") if p.suffix != ".c"), None)
    if lib is None:
        return Cost(case.name, size, folio.stat().st_size, mint_ms, 0, gen_ms, cc_ms,
                    parser_c, scanner, 0, 0, f"compile: {d.gripe(got.stderr)}")
    return Cost(case.name, size, folio.stat().st_size, mint_ms, lib.stat().st_size,
                gen_ms, cc_ms, parser_c, scanner,
                ours_speed(case, folio, runs), theirs_speed(case, runs))


# ------------------------------------------------------------- the keystroke

class Edit(NamedTuple):
    """Tree-sitter's headline claim, and the reason editors adopted it: after a
    keystroke, do not parse the file again.

    Both sides are read from **their own inner clock** here, not a wall clock:
    `joints amend` prints microseconds per edit, `tree-sitter parse -t` prints
    one `Edit:` total over all of them. Neither includes process start, and the
    ratio of two inner clocks is the only honest form this comparison has -
    `tree-sitter parse` spends 295 ms per path resolving the language, which
    would drown a 10 microsecond re-parse three hundred times over.
    """

    name: str
    size: int
    edits: int
    ours_open_us: float  # cold, for the ratio that says whether either is incremental
    ours_us: float  # per keystroke
    theirs_open_us: float
    theirs_us: float
    why: str = ""

    @property
    def ours_gain(self) -> float:
        return self.ours_open_us / self.ours_us if self.ours_us else 0.0

    @property
    def theirs_gain(self) -> float:
        return self.theirs_open_us / self.theirs_us if self.theirs_us else 0.0

    @property
    def slower(self) -> float:
        return self.ours_us / self.theirs_us if self.theirs_us else 0.0


WORD = re.compile(rb"[A-Za-z_]")
OURS_US = re.compile(r"(\d+) us$", re.M)
TS_PARSE = re.compile(r"Parse:\s*([\d.]+) ms")
TS_EDIT = re.compile(r"Edit:\s*([\d.]+) ms")


def keystrokes(blob: bytes, want: int) -> list[int]:
    """Positions to type one character into, spread evenly through the file.

    Inside an identifier, never in a string or at a boundary: the byte on each
    side must be a word byte, which is true of an identifier interior in every
    language on the slate. An insertion there grows a token and invalidates the
    node above it - a keystroke - where a space typed into whitespace is the
    edit both parsers find easiest and a bracket typed anywhere is an edit that
    puts one or both of them into recovery, measuring error handling instead.
    """
    ok = [i for i in range(1, len(blob) - 1)
          if WORD.match(blob[i - 1:i]) and WORD.match(blob[i:i + 1])]
    if len(ok) <= want:
        return ok
    step = len(ok) / want
    return [ok[int(k * step)] for k in range(want)]


def keystroke(case: Case, folio: Path, runs: int, want: int = 24) -> Edit:
    blob = case.source.read_bytes()
    at = keystrokes(blob, want)
    if not at:
        return Edit(case.name, len(blob), 0, 0, 0, 0, 0, "no identifier interior")
    # Positions shift as earlier insertions land, so both sides are handed the
    # same already-shifted offsets rather than each computing its own.
    live = [p + n for n, p in enumerate(at)]
    ours = [str(BIN), "amend", str(folio), str(case.source), "--quiet",
            *[f"{p}..{p}=x" for p in live]]
    them = [str(d.TS), "parse", "-p", str(case.lang), "-q", "-t",
            str(case.source.resolve()), "--edits", *[f"{p} 0 x" for p in live]]
    o_open, o_edit, t_open, t_edit = [], [], [], []
    for _ in range(runs):
        got = timed(ours)[1]
        if us := OURS_US.findall(got.stderr):
            o_open.append(float(us[0]))
            o_edit.append(sum(map(float, us[1:])) / max(len(us) - 1, 1))
        got = timed(them, d.WORK, env=ts_env())[1]
        if (p := TS_PARSE.search(got.stdout)) and (e := TS_EDIT.search(got.stdout)):
            t_open.append(float(p[1]) * 1000)
            t_edit.append(float(e[1]) * 1000 / len(live))
    if not o_edit or not t_edit:
        return Edit(case.name, len(blob), len(live), 0, 0, 0, 0,
                    "no clock" if o_edit or t_edit else "neither side reported")
    return Edit(case.name, len(blob), len(live), min(o_open), min(o_edit),
                min(t_open), min(t_edit))


def show_edits(rows: list[Edit]) -> None:
    ok = [r for r in rows if not r.why]
    print(f"\n  {'grammar':<14}{'bytes':>9}{'edits':>6}  |{'ours open':>11}{'per key':>9}"
          f"{'gain':>7}  |{'theirs':>9}{'per key':>9}{'gain':>7}  |{'x':>6}")
    for r in rows:
        if r.why:
            print(f"  {r.name:<14}{r.size:>9,}{'':>6}  {r.why}")
            continue
        print(f"  {r.name:<14}{r.size:>9,}{r.edits:>6}  |{r.ours_open_us:>11,.0f}"
              f"{r.ours_us:>9,.0f}{r.ours_gain:>7.0f}x  |{r.theirs_open_us:>9,.0f}"
              f"{r.theirs_us:>9,.0f}{r.theirs_gain:>7.0f}x  |{r.slower:>6.1f}")
    if not ok:
        return
    print(f"\n  microseconds per keystroke, each side on its own inner clock")
    print(f"  ours   median {median([r.ours_us for r in ok]):,.0f} us, "
          f"{median([r.ours_gain for r in ok]):.0f}x cheaper than re-opening the file")
    print(f"  theirs median {median([r.theirs_us for r in ok]):,.0f} us, "
          f"{median([r.theirs_gain for r in ok]):.0f}x cheaper than re-opening")
    beat = [r for r in ok if r.slower < 1.0]
    worst = max(ok, key=lambda r: r.slower)
    print(f"  median {median([r.slower for r in ok]):.1f}x tree-sitter's time per "
          f"keystroke; faster on {len(beat)} of {len(ok)}; worst {worst.name} at "
          f"{worst.slower:.0f}x")


def lang_src(lang: Path) -> Path:
    return lang / "src"


def scanners(lang: Path) -> list[Path]:
    """Every hand-written external scanner under one oracle home.

    Not `lang/src/scanner.c`: `differential.py` had to reproduce three
    monorepos' directory depth to make their scanners compile, so php's is at
    `php/php/src/`, ocaml's at `grammars/ocaml/src/`, typescript's a level down
    and markdown's two. Looking only at the top would report those four as
    shipping no C, which is the flattering direction and the reason this walks.

    `.h` counts. php's `scanner.c` is 595 bytes and does nothing but include
    `../../common/scanner.h`, which is 18,018; counting only the `.c` would
    price php's external lexer at 3% of itself.
    """
    return [p for p in lang.rglob("scanner.*")
            if p.suffix in {".c", ".cc", ".h"} and "node_modules" not in p.parts]


def show_cost(rows: list[Cost]) -> None:
    ok = [r for r in rows if not r.why and r.theirs_ms and r.ours_ms and r.resolved]
    print(f"\n  {'grammar':<14}{'folio':>10}{'dylib':>11}{'ratio':>7}  |"
          f"{'mint ms':>9}{'gen+cc':>9}{'x':>7}  |{'ours B/ms':>11}{'theirs':>9}{'x':>7}"
          f"  {'scanner':>8}")
    for r in rows:
        head = f"  {r.name:<14}{r.folio:>10,}{r.dylib:>11,}"
        if r.why:
            print(f"  {r.name:<14}{'—':>10}{'—':>11}{'':>7}  |{'':>25}  |{'':>27}"
                  f"  {r.why}")
            continue
        speed = (f"{r.bytes_ms:>11,.0f}{r.their_bytes_ms:>9,.0f}{r.slower:>7.1f}"
                 if r.theirs_ms and r.ours_ms and r.resolved
                 else f"{'—':>11}{r.their_bytes_ms:>9,.0f}{'noise':>7}")
        print(f"{head}{r.folio / r.dylib:>7.2f}  |{r.build_ours:>9.0f}"
              f"{r.build_theirs:>9.0f}{r.build_theirs / r.build_ours:>7.1f}  |"
              f"{speed}  {(f'{r.scanner:,}' if r.scanner else '—'):>8}")
    priced = [r for r in rows if not r.why]
    if not priced:
        return
    small = [r for r in priced if r.folio < r.dylib]
    print(f"\n  size   folio smaller on {len(small)} of {len(priced)}, "
          f"median ratio {median([r.folio / r.dylib for r in priced]):.2f}; "
          f"{sum(r.folio for r in priced):,}B of folio against "
          f"{sum(r.dylib for r in priced):,}B of dylib")
    print(f"  build  median {median([r.build_theirs / r.build_ours for r in priced]):.1f}x "
          f"faster to mint; the whole slate "
          f"{sum(r.build_ours for r in priced) / 1000:.1f}s against "
          f"{sum(r.build_theirs for r in priced) / 1000:.1f}s")
    if ok:
        worst = max(ok, key=lambda r: r.slower)
        beat = [r for r in ok if r.slower < 1.0]
        print(f"  parse  median {median([r.slower for r in ok]):.1f}x tree-sitter's time "
              f"per byte (over 1.0 is joints slower); worst {worst.name} at "
              f"{worst.slower:.1f}x; faster on {len(beat)} of {len(ok)}")
    ship = [r for r in priced if r.scanner]
    print(f"  C      {len(ship)} of {len(priced)} grammars ship a hand-written external "
          f"scanner, {sum(r.scanner for r in ship):,} bytes of it, compiled per grammar;"
          f"\n         0 of {len(priced)} folios need a compiler at all")


def median(xs: list[float]) -> float:
    xs = sorted(xs)
    n = len(xs)
    return 0.0 if not n else (xs[n // 2] if n % 2 else (xs[n // 2 - 1] + xs[n // 2]) / 2)


# ------------------------------------------------------------- adjudication

VERDICTS = ROOT / "research" / "collate" / "verdicts.toml"
# Who the bytes belong to, decided by hand against the language's own grammar.
SIDES = {"ours": "joints is right", "theirs": "tree-sitter is right",
         "neither": "both are wrong", "agree": "both say the same thing",
         "neutral": "a declared difference that misreads nothing"}
# No node of any name over exactly these bytes. Not an empty string, because a
# reader scanning a chain column has to be able to see the absence.
NOTHING = "—"


class Verdict(NamedTuple):
    grammar: str
    source: str
    start: int
    end: int
    ours: str  # what joints's tree says here, at the time of adjudication
    theirs: str  # what tree-sitter's does
    side: str
    why: str

    @property
    def width(self) -> int:
        return self.end - self.start


def read_verdicts() -> list[Verdict]:
    import tomllib  # noqa: PLC0415 - stdlib, and only this verb needs it
    doc = tomllib.loads(VERDICTS.read_text(encoding="utf-8"))
    out = []
    for row in doc.get("verdict", ()):
        if row["side"] not in SIDES:
            raise SystemExit(f"collate: unknown side {row['side']!r} in verdicts.toml")
        out.append(Verdict(**row))
    return out


def direction(was: str, now: str) -> str:
    """Name the move a drifted chain made, because "DRIFTED" is not a work order.

    Chains are `/`-joined outermost-first, so the innermost name - the one every
    claim in this file is actually about - is the last segment. A row whose
    innermost name held and only grew an ancestor moved its **transcript**; a row
    whose innermost name went away moved its **verdict**. Reading those two as
    one finding is what cost the last reader of this check the whole
    investigation, and it is the difference between a stale line and a
    regression.
    """
    if was == now:
        return ""
    if was == NOTHING:
        return "gained"
    if now == NOTHING:
        return "lost"
    a, b = was.split("/"), now.split("/")
    if a[-1] != b[-1]:
        return "renamed"
    return ("deeper" if len(b) > len(a) else
            "shallower" if len(b) < len(a) else "reshaped")


def consistent(judged: list[tuple[Verdict, str]]) -> list[Verdict]:
    """Which live rows describe an agreement the two trees do not have, or a
    disagreement they no longer have.

    **This is the anchor `adjudicated` was missing.** Its reference is a stored
    artifact, so the cheap way out of a red row is to paste today's two names in
    and leave `side` alone - and then the file asserts one parser is right about
    a span where both now say the same thing. That lie is mechanically visible in
    two directions: a row naming a winner must have something for it to have won
    (`ours != theirs`), and a row saying `agree` must have the two names agree.

    `neither` and `neutral` are deliberately unconstrained: both parsers saying
    the same wrong thing is a real verdict, and it is `neither` rather than
    `agree` because it carries more. Drifted rows are excluded because their
    stored names are by definition not today's.
    """
    return [v for v, w in judged if not w and (
        (v.side in {"ours", "theirs"} and v.ours == v.theirs)
        or (v.side == "agree" and v.ours != v.theirs))]


def adjudicated(cases: list[Case], rows: list[Verdict]) -> list[tuple[Verdict, str]]:
    """Re-read both trees and check every hand verdict still describes them.

    **This is the anti-vacuity, and it is the whole reason the adjudication is a
    file rather than a paragraph.** A hand verdict is a claim about two trees on
    one day. Both parsers move: joints is under ten agents, and the oracle is
    a pin that can be regenerated. A scoreboard quoting hand verdicts against
    trees that have since changed is the twenty-seventh instrument.

    So each row carries what both sides *said* when it was judged, and this
    re-derives both from the live binary and the live oracle. A row whose two
    names no longer match is reported `DRIFTED` and is **excluded from every
    total** - it does not fail quietly and it does not count. Re-reading the
    bytes and re-judging is the only way to bring it back, and `consistent` is
    what stops a re-capture standing in for that. The report says which side
    moved and which way, because "DRIFTED" alone made the last reader re-derive
    three grammars from elsewhere.
    """
    by_name = {c.name: c for c in cases}
    out: list[tuple[Verdict, str]] = []
    trees: dict[str, tuple[list[Leaf], list[Leaf]]] = {}
    for row in rows:
        case = by_name.get(row.grammar)
        if case is None:
            out.append((row, "no such grammar"))
            continue
        key = f"{row.grammar}:{row.source}"
        if key not in trees:
            src = ROOT / row.source
            folio = folio_for(row.grammar, WORK)
            if folio is None or not src.exists():
                trees[key] = ([], [])
            else:
                got = stamp.ask(BIN, folio, src, tree=True, patience=PATIENCE)
                blob = src.read_bytes()
                them, root = theirs(Case(row.grammar, case.grammar, case.lang, src), blob)
                trees[key] = (mine(got.tree), flatten(root) if root else [])
        us, them_nodes = trees[key]
        if not us:
            out.append((row, "no tree from joints"))
            continue
        got_ours = "/".join(chain(us, row.start, row.end)) or NOTHING
        got_theirs = "/".join(chain(them_nodes, row.start, row.end)) or NOTHING
        drift = [(w, was, now) for w, (was, now) in
                 (("ours", (row.ours, got_ours)), ("theirs", (row.theirs, got_theirs)))
                 if was != now]
        if not drift:
            out.append((row, ""))
            continue
        # Direction and both readings, not just the fact of a move: a reader who
        # has to re-derive which grammar and which way is a reader who will
        # re-capture instead of re-judging.
        moves = "; ".join(f"{w} {direction(was, now)}: {was} -> {now}"
                          for w, was, now in drift)
        if got_ours == got_theirs == NOTHING:
            moves += "; neither tree has a node here any more"
        elif got_ours == got_theirs and row.ours != row.theirs:
            moves += ("; both trees now agree here, so the recorded `theirs` "
                      "defect is one somebody fixed - re-judge to `agree` and "
                      "keep this row as its regression guard"
                      if row.side == "theirs" else "; both trees now agree here")
        out.append((row, f"DRIFTED {moves}"))
    return out


def show_verdicts(judged: list[tuple[Verdict, str]]) -> int:
    live = [(v, w) for v, w in judged if not w]
    print(f"\n  {len(live)} of {len(judged)} hand verdicts still describe both trees\n")
    print(f"  {'grammar':<10}{'span':>18}{'bytes':>7}  {'verdict':<9} ours · theirs")
    for v, why in judged:
        mark = "DRIFT" if why else v.side
        print(f"  {v.grammar:<10}{f'[{v.start},{v.end})':>18}{v.width:>7,}  {mark:<9} "
              f"{v.ours} · {v.theirs}")
        if why:
            print(f"       ! {why}")
    print()
    for side, gloss in SIDES.items():
        rows = [v for v, w in live if v.side == side]
        print(f"  {side:<9} {len(rows):>3} verdicts {sum(r.width for r in rows):>8,}B"
              f"   {gloss}")
    ours = sum(v.width for v, _ in live if v.side == "ours")
    them = sum(v.width for v, _ in live if v.side == "theirs")
    print(f"\n  adjudicated bytes where one side is right: joints {ours:,}, "
          f"tree-sitter {them:,}")
    if drifted := [v.grammar for v, w in judged if w]:
        print(f"  EXCLUDED from every total above: {', '.join(sorted(set(drifted)))}")
        return 1
    return 0


def prove(cases: list[Case]) -> int:
    """Watch every check here fail before trusting it pass.

    Three gates carry claims in this lane, and each is asked to say no on an
    input where no is the right answer. Nothing in here touches `verdicts.toml`
    or any tree - the corruption is applied to a copy in memory.
    """
    rows = read_verdicts()
    live = adjudicated(cases, rows)
    ok = True

    def check(what: str, got: bool) -> None:
        nonlocal ok
        ok &= got
        print(f"  {'pass' if got else 'FAIL'}  {what}")

    print("\n  can these checks say no?")
    # Named for the reference it actually reads. Nothing here asserts anything
    # about a *clean tree* - it asserts that the names stored in `verdicts.toml`
    # still describe the two live trees - and the old label sent the last reader
    # looking for a nondeterminism that was never in the question.
    drifted = [(v, w) for v, w in live if w]
    check("every stored verdict still describes both live trees", not drifted)
    for v, why in drifted:
        print(f"        {v.grammar} [{v.start},{v.end}) {v.width:,}B  "
              f"judged `{v.side}` ({SIDES[v.side]})")
        print(f"          {why}")
    # The anchor. Everything above compares live trees against stored strings, so
    # a red row can be silenced by editing the strings; this is the part of the
    # file such an edit cannot leave standing.
    check("no live verdict names a winner where the two trees say one thing",
          not consistent(live))
    for v in consistent(live):
        print(f"        {v.grammar} [{v.start},{v.end}) says `{v.side}` over "
              f"{v.ours} · {v.theirs}")
    # ...driven negative on whichever row can answer it today, and loudly refusing
    # to pass over nothing if none can - the shape a claim pinned to a named row
    # cannot have.
    seat = next((i for i, (v, w) in enumerate(live)
                 if not w and v.ours != v.theirs and v.side != "agree"), None)
    poisoned = ([] if seat is None else
                [*live[:seat], (live[seat][0]._replace(side="agree"), ""), *live[seat + 1:]])
    check("...and it can say no: " + ("NO LIVE ROW CAN ANSWER IT" if seat is None else
          f"calling {live[seat][0].grammar} [{live[seat][0].start},"
          f"{live[seat][0].end}) an agreement is refused"),
          seat is not None and bool(consistent(poisoned)))
    bent = [r._replace(ours=r.ours + "_NOPE") for r in rows[:1]] + list(rows[1:])
    check("a corrupted `ours` is caught as drift",
          bool([w for _, w in adjudicated(cases, bent) if w]))
    bent = [r._replace(theirs="—" if r.theirs != "—" else "x") for r in rows[:1]] + list(rows[1:])
    check("a corrupted `theirs` is caught as drift",
          bool([w for _, w in adjudicated(cases, bent) if w]))
    # The identity behind P4. If `damage` ever intersects `built`, the board's
    # buckets overlap and every number in this lane is built on sand.
    hon = honesty([c for c in cases if c.name in {"php", "verilog", "go"}])
    check("misread bytes never lie in damage (the P4 identity)",
          all(r.ours_caught == 0 for r in hon if r.ok))
    check("the honesty verb finds php's misreadings at all",
          any(r.name == "php" and r.misread > 0 for r in hon))
    # ...and the same guard without a name in it, because the row above is one
    # grammar and a sibling fixing php would dissolve it silently. The identity
    # is asserted over every row and exercised only where `misread` is non-empty;
    # if that set ever empties, the check above passes over nothing.
    check("...and the identity is exercised by a row rather than asserted over "
          f"vacuous ones ({sum(1 for r in hon if r.ok and r.recall is not None)}"
          f" of {sum(1 for r in hon if r.ok)} sampled row(s) have a misread byte)",
          any(r.recall is not None for r in hon if r.ok))
    # A resolution guard that never fires is a guard that is not measuring.
    tiny = Cost("probe", 1, 1, 1, 1, 1, 1, 1, 0, 0.001, 0.001)
    check("a sub-millisecond slope is refused as noise", not tiny.resolved)
    check("a resolvable slope is not", Cost(*tiny[:9], 1.0, 1.0).resolved)
    print(f"\n  {'every check can say no' if ok else 'A CHECK CANNOT SAY NO'}")
    return 0 if ok else 1


def probe(case: Case, src: Path, a: int, b: int) -> None:
    folio = folio_for(case.name, WORK)
    got = stamp.ask(BIN, folio, src, tree=True, patience=PATIENCE)
    blob = src.read_bytes()
    us = mine(got.tree)
    _, root = theirs(Case(case.name, case.grammar, case.lang, src), blob)
    them = flatten(root) if root else []
    print(f"\n  {src} [{a},{b}) {b - a}B")
    print(f"  {blob[a:b][:200].decode('utf8', 'replace')!r}\n")
    print(f"  joints   at this exact extent: {'/'.join(chain(us, a, b)) or '—'}")
    print(f"             enclosing:            {enclosing(us, a, b)}")
    print(f"  tree-sitter at this exact extent: {'/'.join(chain(them, a, b)) or '—'}")
    print(f"             enclosing:            {enclosing(them, a, b)}")
    for who, nodes in (("joints", us), ("tree-sitter", them)):
        print(f"\n  {who}: every node overlapping the span")
        for n in nodes:
            if n.start < b and n.end > a:
                print(f"    {n.label():<40} [{n.start},{n.end})")


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("verb", nargs="?", default="refusal",
                    choices=("refusal", "disputed", "adjudicated", "probe", "cost",
                             "honesty", "keystroke", "prove"))
    ap.add_argument("--grammar", action="append", help="just this one (repeatable)")
    ap.add_argument("--top", type=int, default=8, help="how many disagreement runs to print")
    ap.add_argument("--source", type=Path, help="probe: the file, repo-root-relative")
    ap.add_argument("--span", help="probe: START:END")
    ap.add_argument("--runs", type=int, default=3, help="cost: parse timings per side")
    ap.add_argument("--fresh", action="store_true",
                    help="cost: delete parser.c and the dylib first, so the build "
                         "time is a build and not a cache read")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)

    if not BIN.exists():
        print(f"collate: no binary at {BIN}", file=sys.stderr)
        return 2
    if not d.oracle_ready():
        print("collate: no tree-sitter CLI; `differential.py install`", file=sys.stderr)
        return 2

    cases = narrow(slate(), args.grammar)
    OUT.mkdir(parents=True, exist_ok=True)

    if args.verb == "probe":
        if not args.span or not args.grammar:
            print("collate: probe needs --grammar and --span START:END", file=sys.stderr)
            return 2
        a, b = (int(x) for x in args.span.split(":"))
        case = cases[0]
        probe(case, ROOT / args.source if args.source else case.source, a, b)
        return 0

    if args.verb == "cost":
        rows = [cost(c, args.runs, args.fresh) for c in cases]
        (OUT / "cost.json").write_text(json.dumps([r._asdict() for r in rows], indent=2))
        if args.json:
            print((OUT / "cost.json").read_text())
        else:
            show_cost(rows)
        return 0

    if args.verb == "prove":
        return prove(slate())

    if args.verb == "keystroke":
        rows = []
        for c in cases:
            folio = OUT / "folio" / f"{c.name}.folio"
            rows.append(keystroke(c, folio, args.runs) if folio.exists()
                        else Edit(c.name, 0, 0, 0, 0, 0, 0, "no folio — run `cost` first"))
        (OUT / "keystroke.json").write_text(json.dumps([r._asdict() for r in rows], indent=2))
        if args.json:
            print(json.dumps([r._asdict() for r in rows], indent=2))
        else:
            show_edits(rows)
        return 0

    if args.verb == "honesty":
        rows = honesty(cases)
        (OUT / "honesty.json").write_text(json.dumps([r._asdict() for r in rows], indent=2))
        if args.json:
            print(json.dumps([r._asdict() for r in rows], indent=2))
        else:
            show_honesty(rows)
        return 0

    if args.verb == "adjudicated":
        judged = adjudicated(slate(), read_verdicts())
        (OUT / "adjudicated.json").write_text(json.dumps(
            [{**v._asdict(), "drift": w} for v, w in judged], indent=2))
        if args.json:
            print((OUT / "adjudicated.json").read_text())
            return 0
        return show_verdicts(judged)

    if args.verb == "disputed":
        # Only where the oracle is actually in recovery; everywhere else `plumb`
        # already judges these bytes and a second opinion is a second definition.
        if not args.grammar:
            cases = [c for c in cases
                     if (t := theirs(c, c.source.read_bytes())[0]).ok and t.error_bytes]
        rows = disputes(cases)
        (OUT / "disputed.json").write_text(json.dumps(
            [{**r._asdict(), "worst": [w._asdict() for w in r.worst],
              "judged": r.judged} for r in rows], indent=2))
        if args.json:
            print((OUT / "disputed.json").read_text())
        else:
            show_disputes(rows, {c.name: c.source.read_bytes() for c in cases}, args.top)
        return 0

    rows = census(cases)
    (OUT / "refusal.json").write_text(json.dumps(
        [{"name": r.name, "size": r.size, "candidate": r.candidate,
          "ours": r.ours._asdict(), "theirs": {**r.theirs._asdict(),
                                               "error_spans": list(r.theirs.error_spans)}}
         for r in rows], indent=2))
    if args.json:
        print((OUT / "refusal.json").read_text())
    else:
        show(rows)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

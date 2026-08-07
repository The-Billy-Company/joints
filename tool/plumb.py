#!/usr/bin/env python3
"""`built` counts bytes the tree PLACED. It never asks whether it placed them right.

The board decomposes the corpus into `built + orphan + rubble + spoil` and
prints `built / size` as the headline. All four measure **placement**: which
bucket a byte's root landed in, and whether that root had a child. None of them
can tell a right tree from a wrong one, because both are trees.

The exhibit is Swift. `/* c\\n   d */` has no seated `multiline_comment`, so the
ordinary lexer reads `/*` as a custom operator and `*/` as a multiply and a
divide, and the comment comes back as a `prefix_expression` over a
`multiplicative_expression`. **One root, zero mends, every byte `built`.** The
file scores perfect on every column this repository prints. A parse that reads
a comment as arithmetic looks better than an honest failure, which is the
whole reason nothing has caught it: `orphan` costs bytes, `spoil` costs bytes,
and being confidently wrong costs nothing at all.

So this asks the one question the board structurally cannot, against the only
oracle that can answer it - tree-sitter, whose trees joints exists to be
compatible with, generated from **the same `grammar.json` the press read**.

  For each byte, the DEEPEST node covering it in each tree.
  Same byte, two names. Different name = the byte is out of plumb.

## Byte-indexed, not tree-aligned, and that is the design

`differential.py` aligns the two trees node by node and reports findings. It is
the right instrument for "is our shape their shape" and the wrong one for
"how many bytes are wrong", because on 18 of 30 grammars joints hands back a
forest - verilog is 3,544 roots - and an alignment over that many roots is a
guess wearing a number. Two functions from byte offset to node name need no
alignment at all: they are defined over the same domain by construction, and a
mended forest indexes exactly as well as a whole tree.

That also makes this immune to the two shape differences that would otherwise
swamp it. A comment tree-sitter hands to the root as a child and joints
leaves as a top-level orphan is the SAME deepest node over those bytes, so
`orphan` and this are orthogonal - which is what makes the split safe to put
beside the board rather than on top of it.

## Four sub-buckets of `built`, and they total it exactly

  plumb       the oracle puts these bytes under a node of the same kind
  askew       it puts them under a different one - built, and built wrong
  interstice  they are under no oracle LEAF: whitespace between tokens, where a
              token-kind comparison has nothing to say
  unjudged    the oracle cannot adjudicate them: no oracle for this grammar, or
              tree-sitter's own tree is in recovery over exactly these bytes

`built = plumb + askew + interstice + unjudged` on every row. Nothing else
moves: `orphan`, `rubble`, `spoil`, their sum, and `standing` read exactly what
`standing.py` says they read, and `plumb.py board` asserts that against
`standing.py`'s own rows rather than restating them.

## What is compared, and what deliberately is not

**(name, named).** A node's kind. Not its field - a field is a property of the
edge from the parent, not of what the bytes are, and grafting one costs a third
CLI invocation per case (see `differential.graft_fields`, and the lane it cost).
Not its extent either: two nodes of one name over different spans disagree
byte by byte here anyway, which is the whole point of indexing by byte.

Dropping the field makes this **weaker** than `differential.py`, on purpose. A
lane claiming a headline is flattering should be the one holding the
conservative instrument.

**Interstitial bytes are set aside rather than judged.** Joints elides hidden
rules, splices inlined ones and invents nodes for aliases; tree-sitter's own
`--cst` shows a different set of interior nodes for the same parse. Over a byte
inside a *token* that does not matter - both trees bottom out at the token, and
that is the comparison. Over the whitespace between two tokens it is the only
thing that matters, so judging those bytes would report node-shaping as
misreading. They are counted, named and excluded; `plumb.py show --frame`
reports the interior comparison separately for anyone who wants it, flagged as
the weaker half.

**A byte whose innermost cover is an oracle ERROR is unjudged, structurally.**
That node is not standing behind those bytes, so there is no contract to
compare against. A byte under a *named* node inside an error region is still
judged, because tree-sitter's recovery adopts every subtree it had already
reduced and those subtrees are real parses - which is the whole reason
`collate.survivors` exists.

The distinction is not academic and it was got wrong here for the life of the
column: this asked whether an ERROR was anywhere in the byte's *ancestry*.
tree-sitter wraps `picorv32.v` in one `ERROR` spanning all 94,657 bytes, so
every byte in the file inherited one node's verdict and 31,671 in-scope bytes
came back "the oracle declines" from an oracle that had named all but 271 of
them. `hurt` now asks the node covering the byte; `engulfed` still answers the
ancestry question for a caller that wants a region, and `plumb.py decline`
prints the gap on every row so it can never go quiet again.

## The tripwires

`verify` runs both sides, because an instrument that can only say yes has said
nothing:

  RED   `specimen/swift/multiline-comment.swift`, whose wrong tree is written
        out by hand in `specimen/RESULT-1-coverage.md`. Those comment bytes MUST
        come back askew. If they read plumb, this file is broken.
  GREEN javascript, which `differential.py` calls byte-exact and builds its own
        span fixtures on top of for that reason. It MUST read zero askew.

  python3 tool/plumb.py run                 every grammar (~1 min warm)
  python3 tool/plumb.py run --grammar=swift one
  python3 tool/plumb.py board               the board's four buckets, `built` split
  python3 tool/plumb.py show --grammar=php  the askew regions, widest first
  python3 tool/plumb.py decline             who is refused, and on whose authority
  python3 tool/plumb.py verify              prove it can say no
  python3 tool/plumb.py list                who has an oracle and who does not

  JOINTS_BIN=<path>   measure a pinned binary (`tool/pin.py`), not `zig-out`

Exit 0 measured, 1 a clean negative (a tripwire moved, a row unjudged under
`--strict`), 2 could not run.
"""

from __future__ import annotations

import json
import os
import sys
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
SPECIMEN = ROOT / "research" / "joinery" / "specimen"
PATIENCE = 240
# Names tree-sitter gives a node it is not standing behind. A byte whose oracle
# ancestry passes through one of these has no contract over it.
HURT = ("ERROR", "MISSING ")


class Node(NamedTuple):
    name: str
    named: bool
    start: int
    end: int
    depth: int
    leaf: bool

    @property
    def kind(self) -> tuple[str, bool]:
        return (self.name, self.named)

    def label(self) -> str:
        return self.name if self.named else f'"{self.name}"'


class Region(NamedTuple):
    """One run of consecutive askew bytes, and what each side called them."""

    start: int
    end: int
    ours: str
    theirs: str

    @property
    def width(self) -> int:
        return self.end - self.start


class Seen(NamedTuple):
    name: str
    size: int
    built: int
    plumb: int
    regrouped: int  # the extents differ - the two parsers cut the bytes apart differently
    relabelled: int  # same extent, different name, and no ALIAS declares the pair
    renamed: int  # same extent, and the grammar declares an ALIAS between the names
    interstice: int
    unjudged: int
    frame_same: int  # of the interstitial bytes, how many agree at the interior
    frame_askew: int
    why: str  # why the oracle could not answer, when it could not
    worst: tuple[Region, ...] = ()

    @property
    def misread(self) -> int:
        """Every byte the two parsers disagree about, minus the declared renames.

        Split one level further than it is reported, because the two halves
        answer different questions and only one of them is the brief's. A
        **regrouped** byte was cut apart differently - php's docblock swallowed
        into a 40,995-byte `text`, a string that never closes - and is a byte
        read wrong in the sense that started this lane. A **relabelled** byte
        was cut in exactly the right place and given another name, like
        haskell's `name` for tree-sitter's `module_id`: a compatibility defect,
        and not a comment read as arithmetic.

        Reported together as `misread` and separable on demand, so a reader who
        wants the strict number can have it without a second run.
        """
        return self.regrouped + self.relabelled

    @property
    def askew(self) -> int:
        """Every byte the oracle names differently, both classes together.

        Kept as a rollup rather than a bucket, for exactly the reason `damage`
        is: the sub-buckets still total `built`, so nothing a reader quotes can
        move by adding it. Report it split; only `misread` is a byte read
        wrong.
        """
        return self.misread + self.renamed

    @property
    def judged(self) -> int:
        return self.plumb + self.askew

    @property
    def crooked(self) -> float:
        """Misread as a share of the bytes the oracle could actually adjudicate.

        The honest denominator, and `misread` rather than `askew` as the
        numerator. `askew / built` reads a grammar with no oracle as clean,
        which is the exact silence-as-a-zero this board has been caught on
        twice; folding `renamed` in reads a rename as a misreading, which is
        how swift briefly came second.
        """
        return self.misread / self.judged if self.judged else 0.0

    def as_dict(self) -> dict:
        return {**self._asdict(), "askew": self.askew, "judged": self.judged,
                "crooked": round(self.crooked, 4),
                "worst": [r._asdict() for r in self.worst]}


# ------------------------------------------------------------------- the trees

def flatten(node: d.Node, depth: int = 0, out: list[Node] | None = None) -> list[Node]:
    """The oracle's tree as a pre-order list, each node carrying its depth."""
    out = [] if out is None else out
    out.append(Node(node.name, node.named, node.start, node.end, depth, not node.kids))
    for kid in node.kids:
        flatten(kid, depth + 1, out)
    return out


def ours(text: str) -> list[Node]:
    """Joints's forest, read by `standing.rows` and nobody else.

    Deliberately not `differential.ours_tree`, which reads the same render one
    line at a time and raises on a node whose anonymous name carries a raw
    newline. `standing.rows` rejoins those, and - far more important - it is the
    reader the BOARD counts `built` with. Sharing it is what makes this a split
    of `built` rather than a second opinion about it.
    """
    seen = standing.rows(text)
    out: list[Node] = []
    for i, (wide, body, a, b) in enumerate(seen):
        _, name, named, _ = d.head(body)
        # A leaf is a node nothing is indented under, which in a pre-order
        # render is a node the next row does not go deeper than.
        leaf = i + 1 >= len(seen) or seen[i + 1][0] <= wide
        out.append(Node(name, named, a, b, wide // 2, leaf))
    return out


def paint(nodes: list[Node], size: int) -> list[int]:
    """Per byte: the index of the deepest node covering it, or -1 for none.

    Pre-order with slice assignment, so a child overwrites its parent and the
    last writer of a byte is the deepest node over it. That is the whole
    algorithm; it is O(bytes x depth) in C-speed slice stores rather than a
    search per byte.

    An index rather than a name, because the *extent* is load-bearing too: two
    nodes of different names over identical extents are two parsers naming one
    token, and two nodes over different extents are two parsers reading
    different tokens. Painting only the name lost that, and the loss read as a
    finding - see `askew_alias`.
    """
    who = [-1] * size
    for i, n in enumerate(nodes):
        a, b = max(n.start, 0), min(n.end, size)
        if b > a:
            who[a:b] = [i] * (b - a)
    return who


def alias_pairs(grammar: Path) -> set[frozenset[str]]:
    """Every rename this grammar declares, as the unordered pair it renames.

    `ALIAS` carries the thing (`content`) and the new name (`value`), so a
    grammar states its own renames and nothing here has to guess at one.
    Only a `SYMBOL` or a `STRING` content has a name of its own to pair with;
    an alias over an inline expression renames something unnameable and is left
    out, which keeps this a floor rather than an excuse.

    The set of alias *values* alone is not this test and must not be mistaken
    for it. `identifier` is a declared alias value in scala, python and elixir,
    so a name test would have excused `else`-read-as-`identifier` and
    `end`-read-as-`identifier` as renaming - three real misreadings, filed as
    house style. The pair is what a grammar actually says.
    """
    doc = json.loads(grammar.read_text(encoding="utf-8"))
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

    walk(doc.get("rules", {}))
    return out


def hurt(nodes: list[Node], size: int, who: list[int] | None = None) -> list[bool]:
    """Bytes the node ACTUALLY COVERING them is one the oracle disowns.

    Asked of the innermost cover - the node `paint` already computed - and not
    of the ancestry, which is what this used to ask and what made it wrong.
    Recovery in tree-sitter is a property of a *bracket*, not of a region: it
    adopts every subtree it had already reduced and hands the whole thing back
    under one `ERROR`, so an ancestry test lets the widest bracket in the file
    speak for every byte beneath it. On `picorv32.v` that bracket is the root
    and it is 94,657 bytes wide, over 48,883 nodes and 17,290 leaves the same
    parse built perfectly well; asked by ancestry the oracle refused all
    31,671 in-scope bytes, and asked by cover it refuses 271.

    The distance being measured is the whole content of the function. `ERROR`
    over the byte is a verdict about the byte. `ERROR` 94,657 bytes away is a
    verdict about the file, and reading one as the other converted the oracle's
    *agreement* into the oracle's *silence* on the corpus's largest damage row
    for as long as this column has existed - invisibly, because a column that
    reads zero because nobody could adjudicate is indistinguishable from one
    that reads zero because nobody asked.

    `engulfed` still answers the ancestry question for the caller that wants a
    region rather than a verdict. Nothing in this repository does; the two are
    kept apart so that asking for one can no longer deliver the other, and
    `decline` watches the gap between them on every row.
    """
    who = paint(nodes, size) if who is None else who
    return [w >= 0 and nodes[w].name.startswith(HURT) for w in who]


def engulfed(nodes: list[Node], size: int) -> list[bool]:
    """Bytes with a node in recovery anywhere ABOVE them. A region, not a verdict.

    The old `hurt`, kept under a name that says which question it answers, for
    two reasons. It is the honest instrument for "how much of this file is
    inside a recovery bracket" - `collate.refusals` asks exactly that and has
    always painted extents for it. And `decline` needs both rules at once to
    prove the one the board consumes is still the narrow one: where the two
    agree there is nothing to be wrong about, and where they part company is
    precisely the population this file spent its whole life mispricing.
    """
    bad = [False] * size
    for n in nodes:
        if n.name.startswith(HURT):
            a, b = max(n.start, 0), min(n.end, size)
            if b > a:
                bad[a:b] = [True] * (b - a)
    return bad


# ------------------------------------------------------------------ the compare

def judge(name: str, blob: bytes, mine: list[Node], theirs: list[Node],
          scope: list[tuple[int, int]], renames: set[frozenset[str]], top: int = 6) -> Seen:
    """Walk the `built` bytes once and file each into exactly one bucket.

    Two askew classes, separated mechanically off the grammar rather than by
    eye, because the first draft of this had one and the one was wrong:

      **misread** — the two parsers do not agree on what is here. Either the
      extents differ (they tokenised the bytes differently) or the names differ
      with no rename to account for it. php's docblocks read as `text`, latex's
      comments read as `word`, scala's `else` read as an `identifier`.

      **renamed** — identical extent, and the grammar itself declares an
      `ALIAS` between exactly these two names. The bytes were read the same and
      called something else. A real compatibility defect, since a
      `highlights.scm` keys on the name — but not a byte read wrong, and 1,096
      of swift's 1,213 askew bytes were this: method names joints resolves to
      `type_identifier` where tree-sitter leaves `simple_identifier`.

    Folding those together made swift the second-worst grammar in the corpus on
    a defect that misreads nothing.
    """
    size = len(blob)
    o_who, t_who = paint(mine, size), paint(theirs, size)
    t_bad = hurt(theirs, size, t_who)
    tally = {"plumb": 0, "regrouped": 0, "relabelled": 0, "renamed": 0,
             "interstice": 0, "unjudged": 0}
    frame = [0, 0]
    runs: list[Region] = []
    run: list[int] | None = None

    def close() -> None:
        nonlocal run
        if run is not None:
            a, b = run
            runs.append(Region(a, b, spell(mine, o_who, a), spell(theirs, t_who, a)))
            run = None

    for lo, hi in scope:
        for i in range(lo, hi):
            t_at = t_who[i]
            them = theirs[t_at] if t_at >= 0 else None
            if them is None or t_bad[i]:
                # No oracle node at all, or the node covering the byte is one
                # tree-sitter disowns: nothing here is a contract. One test
                # where there were two, because `hurt` is now asked of the
                # cover - so `t_bad[i]` and "the innermost node is named
                # ERROR/MISSING" are the same sentence, and the second reading
                # was the first one's ancestry clause wearing a leaf test.
                tally["unjudged"] += 1
                close()
                continue
            o_at = o_who[i]
            us = mine[o_at] if o_at >= 0 else None
            if not them.leaf:
                tally["interstice"] += 1
                frame[bool(us) and us.kind == them.kind] += 1
                close()
                continue
            if us is not None and us.kind == them.kind:
                tally["plumb"] += 1
                close()
                continue
            if (us is not None and (us.start, us.end) == (them.start, them.end)
                    and frozenset((us.name, them.name)) in renames):
                tally["renamed"] += 1
                close()
                continue
            same = us is not None and (us.start, us.end) == (them.start, them.end)
            tally["relabelled" if same else "regrouped"] += 1
            if run is not None and run[1] == i:
                run[1] = i + 1
            else:
                close()
                run = [i, i + 1]
        close()
    close()
    built = sum(b - a for a, b in scope)
    return Seen(name, size, built, tally["plumb"], tally["regrouped"], tally["relabelled"],
                tally["renamed"], tally["interstice"], tally["unjudged"], frame[1], frame[0],
                "", tuple(sorted(runs, key=lambda r: -r.width)[:top]))


def spell(nodes: list[Node], who: list[int], at: int) -> str:
    return nodes[who[at]].label() if who[at] >= 0 else "—"


# ---------------------------------------------------------------- one grammar

class Case(NamedTuple):
    name: str
    grammar: Path
    lang: Path
    source: Path


def slate() -> list[Case]:
    """The same thirty rows the board has, pointed at the same sources.

    Held-out grammars read their oracle out of `.local/breadth/lang/`, where
    `breadth.py` already generated and compiled them, rather than a second copy
    under `.local/differential/lang/`. One oracle per grammar - and it is not
    only tidiness: the two roots exist precisely because php's and typescript's
    scanners both climb to `../../common/scanner.h`, and a third root would
    reopen the collision that separation was built to close.
    """
    import breadth  # noqa: PLC0415 - breadth imports differential; keep it one-way
    corpus = {n for n, _ in pairs()}
    out = []
    for name, src in roster():
        home = d.oracle_home(name) if name in corpus else d.oracle_home(name, breadth.LANG.parent)
        out.append(Case(name, GRAMMARS / f"{name}.json", home, src))
    return out


def oracle(case: Case, blob: bytes) -> list[Node]:
    """Tree-sitter's tree over these exact bytes, or a refusal saying why.

    Both faces, exactly as `differential.measure` reads them: `--cst` for the
    tree (the only printer carrying an anonymous node's *type*), cross-checked
    against `-x`, which nests unambiguously. A disagreement is a refusal, not a
    guess - the CST's indentation is unreliable inside an error tree, and this
    file's whole output is a claim that somebody else's tree is wrong.
    """
    at = d.Lines(blob)
    with d.alone(d.named(case.lang), writing=False):
        theirs = d.xml_tree(d.oracle_run(case.lang, case.source, "-x"), at)
        full, ill = d.reconciled(d.oracle_run(case.lang, case.source, "--cst"), at, theirs)
    if full is None:
        raise ValueError("tree-sitter's CST and XML disagree with each other"
                         + (" (the tree has errors in it)" if ill else ""))
    return flatten(full)


def blank(case: Case, size: int, built: int, why: str) -> Seen:
    return Seen(case.name, size, built, 0, 0, 0, 0, 0, built, 0, 0, why)


class Read(NamedTuple):
    """Both trees over one file, and the board's own `built` scope across them.

    Split out of `measure` so a second comparison over the same population
    cannot quietly grow a second definition of `built`. `rack.py` asks for this
    and gets exactly the spans `standing.tops` handed the byte comparison; the
    alternative is two instruments that each derive the scope and eventually
    disagree about a word they both spell the same.
    """

    blob: bytes
    mine: list[Node]
    theirs: list[Node]
    scope: list[tuple[int, int]]  # merged spans, what `built` is counted over
    windows: list[tuple[int, int, int, int]]  # (judge_from, judge_to, root_start, root_end)
    renames: set[frozenset[str]]
    built: int
    why: str

    @property
    def ok(self) -> bool:
        return not self.why


def windowed(top_level: list[tuple[str, int, int, bool]]) -> list[tuple[int, int, int, int]]:
    """Each built root as (bytes to judge, the root's own extent).

    The bytes are clipped against every root already taken, so the total is
    `merge`'s total to the byte and no byte is judged twice. The extent is kept
    unclipped because it is the **window** a structural comparison judges
    inside: joints never reduced anything wider than this root, so an oracle
    bracket that reaches past it is a bracket joints could not have had, and
    charging one would report `orphan` a second time under a new name.
    """
    out: list[tuple[int, int, int, int]] = []
    end = -1
    for a, b in sorted((a, b) for _, a, b, kid in top_level if kid):
        lo = max(a, end)
        if b > lo:
            out.append((lo, b, a, b))
            end = b
    return out


def read(case: Case, extra: tuple[str, ...] = ()) -> Read | None:
    """Both trees over one source, or a `Read` carrying why there is only one.

    The folio is looked up by the **grammar**, not by the row's label. Those are
    the same word on all thirty board rows and are not the same word on a
    specimen - `swift-comment` is swift's grammar over a different file - so
    keying on the label found no folio, returned `None`, and the red tripwire
    reported `0 askew` for a case whose wrong tree is written out by hand two
    directories away. It read exactly like the parser being right.
    """
    folio = folio_for(case.grammar.stem, WORK)
    if folio is None or not case.source.exists():
        return None
    blob = case.source.read_bytes()
    nothing: list[Node] = []
    got = stamp.ask(BIN, folio, case.source, tree=True, patience=PATIENCE, extra=extra)
    if got.kind == "timeout":
        return Read(blob, nothing, nothing, [], [], set(), 0, "joints timed out")
    mine = ours(got.tree)
    # `built` is the board's definition and is read here from the board's own
    # function, not restated: the union of top-level spans that have a child.
    # A restatement is how two instruments come to disagree about a population
    # they both call `built`.
    top_level = standing.tops(standing.rows(got.tree))
    scope = merge([(a, b) for _, a, b, kid in top_level if kid])
    built = sum(b - a for a, b in scope)
    if not built:
        return Read(blob, mine, nothing, [], [], set(), 0, "nothing built")
    if not d.oracle_ready():
        return Read(blob, mine, nothing, scope, [], set(), built, "no tree-sitter CLI")
    try:
        if d.unbuilt(d.Case(case.name, case.grammar, case.lang, case.source, "plumb")):
            with d.alone(d.named(case.lang)):
                d.oracle_build(case.lang, case.grammar)
                if not d.built(d.named(case.lang), case.lang):
                    d.cli([str(d.TS), "parse", "-p", str(case.lang), "-q", str(case.source)],
                          d.WORK)
        theirs = oracle(case, blob)
        renames = alias_pairs(case.grammar)
    except (ValueError, KeyError, ET.ParseError, OSError) as e:
        return Read(blob, mine, nothing, scope, [], set(), built, str(e)[:90])
    return Read(blob, mine, theirs, scope, windowed(top_level), renames, built, "")


def measure(case: Case, top: int = 6) -> Seen | None:
    """One row: the board's own `built` spans, judged byte by byte."""
    saw = read(case)
    if saw is None:
        return None
    if saw.why:
        return blank(case, len(saw.blob), saw.built, saw.why)
    return judge(case.name, saw.blob, saw.mine, saw.theirs, saw.scope, saw.renames, top)


def merge(got: list[tuple[int, int]]) -> list[tuple[int, int]]:
    """The same union `standing.union` totals, kept as spans instead of a count.

    Its arithmetic, restated as intervals so the walk can visit each byte once
    and once only; `standing.union` is asserted against the total in `board`.
    """
    out: list[tuple[int, int]] = []
    for a, b in sorted(got):
        if out and a <= out[-1][1]:
            out[-1] = (out[-1][0], max(out[-1][1], b))
        elif b > a:
            out.append((a, b))
    return out


# ----------------------------------------------------------------------- verbs

def sweep(picked: list[Case], top: int = 6) -> list[Seen]:
    d.lay_out()
    for case in picked:
        try:
            with d.alone(d.named(case.lang)):
                d.oracle_build(case.lang, case.grammar)
                d.cli([str(d.TS), "parse", "-p", str(case.lang), "-q", str(case.source)], d.WORK)
        except (OSError, ValueError):
            pass  # `measure` reports it properly; this only pre-compiles
    return [r for c in picked if (r := measure(c, top)) is not None]


def run(rows: list[Seen], as_json: bool, mark: stamp.Stamp) -> int:
    if as_json:
        print(json.dumps({"stamp": mark.as_dict(), "oracle": d.oracle_ready(),
                          "row": [r.as_dict() for r in rows]}, indent=2))
        return 0
    print(f"\n{'grammar':<19}{'built':>8}{'judged':>8}{'plumb':>8}{'misread':>8}{'renamed':>8}"
          f"{'crooked':>9}{'intstc':>7}{'unjudg':>7}  what the oracle could not say")
    print("-" * 124)
    for r in sorted(rows, key=lambda r: -r.misread):
        print(f"{r.name:<19}{r.built:>8}{r.judged:>8}{r.plumb:>8}{r.misread:>8}{r.renamed:>8}"
              f"{r.crooked * 100:>8.1f}%{r.interstice:>7}{r.unjudged:>7}  {r.why[:40]}")
    total(rows)
    print(mark.line())
    return 0


def total(rows: list[Seen]) -> None:
    built = sum(r.built for r in rows)
    bad, alias = sum(r.misread for r in rows), sum(r.renamed for r in rows)
    ok = sum(r.plumb for r in rows)
    gap = sum(r.interstice for r in rows)
    out = sum(r.unjudged for r in rows)
    judged = ok + bad + alias
    print(f"\n{len(rows)} grammars · {sum(1 for r in rows if r.why)} could not be judged at all")
    print(f"bytes: {ok} plumb + {bad} misread + {alias} renamed + {gap} interstice"
          f" + {out} unjudged = {built} built — the five are disjoint and total")
    print(f"       {bad / built * 100:.2f}% of `built` is provably read as something other than"
          f" what tree-sitter reads it as")
    print(f"       {bad / judged * 100:.2f}% of the {judged} bytes the oracle could"
          f" ADJUDICATE — the honest denominator, since the {out} bytes it could not"
          f"\n       ({out / built * 100:.1f}% of built) read as clean under the first one")
    print(f"       {alias} further bytes are RENAMED, not misread: identical extent, and the"
          f" grammar\n       declares an ALIAS between the two names. A compatibility defect"
          f" — every `highlights.scm`\n       keys on the name — but not a byte read wrong."
          f" Counted, never folded in.")
    # The split inside `misread`, because the two halves are not the same claim
    # and only the first is the one this lane was opened on.
    cut, tag = sum(r.regrouped for r in rows), sum(r.relabelled for r in rows)
    print(f"\n       of the {bad} misread: {cut} REGROUPED — the extents differ, the bytes were"
          f"\n       cut apart differently, and this is the class the lane was opened on"
          f" ({cut / built * 100:.2f}% of built)."
          f"\n       {tag} RELABELLED — cut in exactly the right place, called another name with"
          f"\n       no ALIAS to declare it. A compatibility defect, not a comment read as"
          f" arithmetic.")
    # An interior comparison, printed and not folded in. It is the half that
    # node-shaping can move, so it rides beside the headline rather than in it.
    same, off = sum(r.frame_same for r in rows), sum(r.frame_askew for r in rows)
    if same + off:
        print(f"       interstitial bytes agree at the interior {same} to {off}"
              f" ({off / (same + off) * 100:.1f}% differ) — WEAKER: joints elides hidden"
              f"\n       rules and invents alias nodes, so a difference here can be node"
              f" shaping rather than misreading")
    hit = [r for r in rows if r.misread]
    if hit:
        print("\nwidest by MISREAD " + " · ".join(
            f"{r.name} {r.misread}" for r in sorted(hit, key=lambda r: -r.misread)[:5]))
        worst = sorted(hit, key=lambda r: -r.crooked)[:5]
        print("worst share       " + " · ".join(f"{r.name} {r.crooked * 100:.0f}%" for r in worst)
              + "  ← disagrees with the line above; both are the work order")
    if renamed := [r for r in rows if r.renamed]:
        print("widest by RENAMED " + " · ".join(
            f"{r.name} {r.renamed}" for r in sorted(renamed, key=lambda r: -r.renamed)[:5]))
    blindly = [r for r in rows if r.why]
    if blindly:
        print(f"\nno verdict on {sum(r.built for r in blindly)} built bytes over"
              f" {len(blindly)} grammar(s):")
        for r in sorted(blindly, key=lambda r: -r.built):
            print(f"  {r.name:<19}{r.built:>8}  {r.why}")


def board(rows: list[Seen], as_json: bool) -> int:
    """The board's four buckets with `built` split, and the totals asserted.

    This does not re-measure anything the board measures. It calls
    `standing.survey` and prints its rows verbatim; the only new columns are
    the split of a bucket that already existed. The three assertions at the
    bottom are what make that claim checkable rather than stated - if a column
    added here moved `standing`, the third one reddens.
    """
    seen = {r.name: r for r in rows}
    base = standing.survey("all")
    print(f"\n{'grammar':<19}{'bytes':>8}{'stand':>7}{'built':>8}{'plumb':>8}{'misread':>8}"
          f"{'renamed':>8}{'intstc':>7}{'unjudg':>7}{'orphan':>7}{'rubble':>7}{'spoil':>8}"
          f"{'damage':>8}")
    print("-" * 120)
    for b in sorted(base, key=lambda b: -seen[b.name].misread if b.name in seen else 0):
        r = seen.get(b.name)
        cell = (f"{r.plumb:>8}{r.misread:>8}{r.renamed:>8}{r.interstice:>7}{r.unjudged:>7}" if r
                else f"{'—':>8}{'—':>8}{'—':>8}{'—':>7}{'—':>7}")
        print(f"{b.name:<19}{b.size:>8}{b.standing * 100:>6.1f}%{b.built:>8}{cell}"
              f"{b.orphan:>7}{b.rubble:>7}{b.spoil:>8}{b.damage:>8}")
    size = sum(b.size for b in base)
    built = sum(b.built for b in base)
    orphan = sum(b.orphan for b in base)
    rubble = sum(b.rubble for b in base)
    spoil = sum(b.spoil for b in base)
    ok, bad = sum(r.plumb for r in rows), sum(r.misread for r in rows)
    alias = sum(r.renamed for r in rows)
    gap, out = sum(r.interstice for r in rows), sum(r.unjudged for r in rows)
    covered = sum(r.built for r in rows)
    print(f"\nbytes: {built} built + {orphan} orphan + {rubble} rubble + {spoil} spoil"
          f" = {size} — unmoved")
    print(f"       {built} built = {ok} plumb + {bad} misread + {alias} renamed"
          f" + {gap} interstice + {out} unjudged")
    print(f"       {built / size * 100:.2f}% standing, unmoved — of which {bad} bytes"
          f" ({bad / built * 100:.2f}% of built) are read as something else")
    checks = [
        (orphan + rubble + spoil + built == size,
         f"the four buckets still total the corpus: {size} bytes"),
        (ok + bad + alias + gap + out == covered,
         f"the split totals `built` on every row it judged: {covered} bytes"),
        (covered == built,
         f"and it judged every built byte the board has: {covered} of {built}"),
    ]
    for held, said in checks:
        print(f"{'CHECK' if held else '**BROKEN**':<18}{said}")
    if as_json:
        print(json.dumps({"row": [{**b.as_dict(),
                                   **({k: v for k, v in seen[b.name].as_dict().items()
                                       if k not in ("name", "size", "built")}
                                      if b.name in seen else {})}
                                  for b in base]}, indent=2))
    return 0 if all(h for h, _ in checks) else 1


def show(picked: list[Case]) -> int:
    for case in picked:
        r = measure(case, top=25)
        if r is None:
            print(f"# {case.name}: no folio\n")
            continue
        print(f"# {case.name}  {case.source.relative_to(ROOT)}")
        if r.why:
            print(f"  no verdict: {r.why}\n")
            continue
        print(f"  {r.built} built · {r.plumb} plumb · {r.misread} misread"
              f" ({r.crooked * 100:.1f}% of judged) · {r.renamed} renamed"
              f" · {r.interstice} interstice · {r.unjudged} unjudged")
        blob = case.source.read_bytes()
        if r.worst:
            print(f"\n  widest MISREAD runs (renamed bytes are not listed — same extent,"
                  f" declared ALIAS)")
            print(f"  {'bytes':<16}{'wide':>6}  {'joints':<28}{'tree-sitter':<28}text")
        for reg in r.worst:
            text = blob[reg.start:min(reg.end, reg.start + 30)].decode("utf-8", "replace")
            print(f"  {f'[{reg.start}, {reg.end})':<16}{reg.width:>6}  {reg.ours:<28}"
                  f"{reg.theirs:<28}{text!r}")
        print()
    return 0


# ------------------------------------------------------- on whose authority
#
# The class of defect this section exists for: a refusal column reads zero the
# same way an unasked question does, so an instrument can convert somebody
# else's ANSWER into its own SILENCE and every board it feeds still totals.
# It ran here for the life of `unjudged` and nothing caught it, because there
# was no row on which "the oracle could not say" and "nobody asked the oracle"
# printed differently.
#
# So the guard is not "verilog must read 271" - that pins the bug's address
# rather than its shape, and the next instrument to make this mistake will make
# it somewhere else. It is: no byte may be refused on the authority of a node
# that is not covering it, asked of every row; and some row must still be able
# to tell that rule apart from the one it replaced, or this proves nothing.

class Authority(NamedTuple):
    """One row's refusal, priced by the cover and by the ancestry at once."""

    name: str
    size: int
    sick: int  # recovery nodes in the oracle's tree
    widest: int  # the widest one's span — the bracket that speaks for everyone
    rest: int  # union of every OTHER recovery extent — the recovery that is real
    cover: int  # in-scope bytes the INNERMOST cover disowns — the rule we consume
    region: int  # in-scope bytes with a recovery node anywhere above — the old rule
    named: int  # of the bytes the two rules differ over, how many the oracle NAMES
    token: int  # ...and how many of those it names with a leaf
    sound: bool  # every refused byte's own cover is an ERROR/MISSING, or nothing
    why: str

    @property
    def gap(self) -> int:
        return self.region - self.cover

    @property
    def wide(self) -> bool:
        """Does one bracket here speak for more than every other one together?

        The shape, stated without a threshold and without a grammar's name in
        it: the widest recovery node covers more than every OTHER recovery node
        put together. On `picorv32.v` that is one root over 94,657 bytes
        against 12,526 bytes of recovery that is actually local to something.
        On a row whose errors are all local it is false, and there is
        correspondingly little for two rules to disagree about.

        `rest` excludes the widest node deliberately. The union WITH it is the
        widest node on any row that has a root bracket - a recovery region
        containing every other one - so a test against the union is a test that
        can only ever say no, which is the shape of instrument this whole lane
        is about.
        """
        return self.widest > self.rest


def authority(case: Case) -> Authority | None:
    """Both refusal rules over one row, and what the difference is made of.

    One read and one walk. `sound` is computed here, against the node list,
    rather than off `hurt` - a check that asks the implementation whether it
    did what it says is a check that cannot go red.
    """
    saw = read(case)
    if saw is None:
        return None
    size = len(saw.blob)
    if saw.why:
        return Authority(case.name, size, 0, 0, 0, 0, 0, 0, 0, True, saw.why)
    who = paint(saw.theirs, size)
    cover, region = hurt(saw.theirs, size, who), engulfed(saw.theirs, size)
    sick = [n for n in saw.theirs if n.name.startswith(HURT)]
    top = max(sick, key=lambda n: n.end - n.start, default=None)
    rest = merge([(max(n.start, 0), min(n.end, size)) for n in sick if n is not top])
    n_cover = n_region = n_named = n_token = 0
    sound = True
    for a, b in saw.scope:
        for p in range(a, b):
            if cover[p]:
                n_cover += 1
                sound &= who[p] >= 0 and saw.theirs[who[p]].name.startswith(HURT)
            if region[p]:
                n_region += 1
                if not cover[p]:
                    # The disputed bytes. `who[p] >= 0` here by construction —
                    # a byte with no cover at all is refused under both rules —
                    # so this counts what the oracle was saying about them
                    # while they were being reported as its silence.
                    n_named += 1
                    n_token += saw.theirs[who[p]].leaf
    return Authority(case.name, size, len(sick),
                     (top.end - top.start) if top else 0,
                     sum(b - a for a, b in rest),
                     n_cover, n_region, n_named, n_token, sound, "")


def decline(picked: list[Case], as_json: bool) -> int:
    """Every row's refusal, and on whose authority it was refused.

    Four assertions. The first two are the invariant; the last two are what
    stop this being a check that cannot fail.

      NESTS   the rule the board consumes must be a REFINEMENT of the region
              rule on every row. If the two ever cross, `hurt` is not a
              narrower version of the same question and nothing below is safe.
      SOUND   every refused byte's own cover is a node named ERROR or MISSING,
              or there is no node over it at all. The rule, restated over the
              tree rather than over the implementation, so a re-introduced span
              paint reddens on the first row carrying a wide bracket.
      PARTS   at least one row must still be able to TELL THE TWO RULES APART.
              The day the corpus holds no wide bracket, everything above is
              true for free — so on that day this says so and exits 1 rather
              than printing greens nobody earned. This is the assertion the
              defect's own witness became: it went red for the whole life of
              the bug and there was no one to read it.
      SPOKEN  and on the rows that part, every disputed byte must be one the
              oracle NAMES. If those bytes were genuinely unnameable the old
              rule was right and this change is wrong; that is the falsifier
              for the fix, and it is checked rather than asserted.
    """
    rows = [r for c in picked if (r := authority(c)) is not None]
    if not rows:
        return oops("no grammar resolved to a folio and a source")
    print(f"\n{'grammar':<19}{'bytes':>8}{'Enode':>6}{'widest':>8}{'rest':>8}"
          f"{'cover':>8}{'region':>8}{'gap':>8}{'named':>7}{'token':>7}  one bracket for all?")
    print("-" * 112)
    for r in sorted(rows, key=lambda r: (-r.gap, -r.widest)):
        if not r.sick and not r.why:
            continue
        print(f"{r.name:<19}{r.size:>8}{r.sick:>6}{r.widest:>8}{r.rest:>8}"
              f"{r.cover:>8}{r.region:>8}{r.gap:>8}{r.named:>7}{r.token:>7}"
              f"  {'YES' if r.wide else '—':<5}{r.why[:28]}")
    quiet = [r for r in rows if not r.sick and not r.why]
    print(f"\n{len(quiet)} further row(s) carry no recovery node at all — both rules read 0,"
          f" which is\nagreement and not evidence, and is why PARTS below asks a different"
          f" question.")

    parted = sorted((r for r in rows if r.gap), key=lambda r: -r.gap)
    crossed = [r for r in rows if r.cover > r.region]
    unsound = [r for r in rows if not r.sound]
    out = [
        (not crossed, f"NESTS   the consumed rule refines the region rule on all {len(rows)}"
                      f" row(s)" + (f" — {crossed[0].name} crosses" if crossed else "")),
        (not unsound, f"SOUND   every one of the {sum(r.cover for r in rows)} refused byte(s)"
                      f" is covered by an ERROR/MISSING of its own"
                      + (f" — {', '.join(r.name for r in unsound[:3])} is not" if unsound else "")),
        (bool(parted), "PARTS   " + (
            f"{len(parted)} row(s) still tell the two rules apart: "
            + " · ".join(f"{r.name} {r.gap}" for r in parted[:4])
            if parted else
            "NO ROW can tell the two rules apart — this check is proving nothing."
            " A corpus with no wide recovery bracket cannot witness this defect;"
            " add one or retire the column.")),
        (all(r.named == r.gap for r in parted),
         f"SPOKEN  the oracle NAMES all {sum(r.named for r in parted)} disputed byte(s),"
         f" {sum(r.token for r in parted)} with a token — the rule this replaced was"
         f" reporting those answers as the oracle's silence"),
    ]
    for held, said in out:
        print(f"{'ok  ' if held else 'FAIL':<8}{said}")
    if as_json:
        print(json.dumps({"row": [{**r._asdict(), "gap": r.gap, "wide": r.wide}
                                  for r in rows]}, indent=2))
    bad = sum(not held for held, _ in out)
    print(f"\n{len(out) - bad} of {len(out)} held")
    return 1 if bad else 0


# -------------------------------------------------------------------- tripwire

RED = SPECIMEN / "swift" / "multiline-comment.swift"


def verify() -> int:
    """Prove this can say no, on cases whose answer is known without it.

    Three assertions, and two of them exist only to show the predicate still
    has a negative. The instrument this file is checking is the one that will
    be confident before it is correct - it compares two trees and calls one
    wrong - so it does not get to argue that it would go red.
    """
    out: list[tuple[bool, str]] = []
    swift = next(c for c in slate() if c.name == "swift")
    js = next(c for c in slate() if c.name == "javascript")

    # The specimen this file's RED tripwire was built on, KEPT — and inverted,
    # because a sibling lane fixed the parser underneath it. `/* c\n d */` came
    # back as a `custom_operator` over a `multiplicative_expression` when this
    # assertion was written; swift's `multiline_comment` is now seated on its
    # own `marrow` vein and the two specimens went 2/4 -> 4/4 (see
    # `changelog.d/+swifts-comment-was-arithmetic-and-the-board-called-it-built`).
    # So "these bytes MUST come back askew" now encodes the defect rather than
    # the contract, and the honest move is to keep the witness pointed at the
    # same bytes and demand the CORRECT reading: this is the regression guard
    # for that seating, and it reddens the day the comment is arithmetic again.
    # The negative this used to supply is supplied below, off a tree written
    # out here, so `judge`'s ability to say no no longer depends on the parser
    # still being wrong about something.
    if not RED.exists():
        out.append((False, f"the red tripwire is missing from {RED}"))
    else:
        got = measure(Case("swift-comment", swift.grammar, swift.lang, RED), top=9)
        blob = RED.read_bytes()
        # A row that came back `None` is a row nothing measured, and it used to
        # arrive here as `askew == 0` - the shape that let a missing folio pass
        # for a correct parse. Absence is asserted against, not defaulted.
        out.append((got is not None, "the specimen produced a row at all"
                                     + ("" if got is not None else
                                        f" — nothing measured {RED.name}")))
        saw = got.misread if got and not got.why else -1
        out.append((saw == 0, f"a comment is no longer read as arithmetic: {saw} misread"
                              f" byte(s) in {RED.name}"
                              + (f" — {got.why}" if got and got.why else "")))
        # And that the comment's own bytes are the ones being judged, not merely
        # that nothing anywhere came back askew - a row that judged none of them
        # would read identically to a row that judged all of them correctly,
        # which is this lane's whole subject.
        a, b = blob.index(b"/*"), blob.index(b"*/") + 2
        names = {n.name for n in ours(stamp.ask(BIN, folio_for(swift.grammar.stem, WORK),
                                                RED, tree=True, patience=PATIENCE).tree)
                 if a <= n.start < b} if got and not got.why else set()
        out.append(("multiline_comment" in names,
                    f"and joints names the comment's own bytes [{a}, {b}):"
                    f" {', '.join(sorted(names)) or 'nothing'}"))

    # RED, and it does not depend on the parser still being wrong about
    # anything. Two trees over the same twelve bytes, one calling them a
    # comment and one calling them arithmetic — the swift specimen's own shape,
    # written out, so `judge` has to prove it can still say no on a day when
    # every grammar in the corpus is right. `regrouped` rather than
    # `relabelled` because the extents differ, which is the class this file was
    # opened on.
    text = b"/* c\n d */\n"
    theirs = [Node("source_file", True, 0, 11, 0, False),
              Node("multiline_comment", True, 0, 10, 1, True)]
    mine = [Node("source_file", True, 0, 11, 0, False),
            Node("custom_operator", True, 0, 2, 1, True),
            Node("simple_identifier", True, 3, 4, 1, True),
            Node("multiplicative_expression", True, 6, 10, 1, True)]
    liar = judge("a-comment-read-as-arithmetic", text, mine, theirs, [(0, 11)], set())
    out.append((liar.misread == 10 and liar.regrouped == 10,
                f"a comment read as arithmetic is still caught: {liar.misread} misread"
                f" byte(s) ({liar.regrouped} regrouped) over the 10 the two trees"
                f" tokenise differently"))
    # ...and that it is not simply calling everything wrong. The same walk over
    # two trees that agree has to come back silent, or the assertion above is a
    # function that returns a number rather than a test.
    honest = judge("agreement", text, theirs, theirs, [(0, 11)], set())
    out.append((honest.misread == 0 and honest.plumb == 10,
                f"and agreement is not: {honest.misread} misread, {honest.plumb} plumb"
                f" over the same bytes with the same tree on both sides"))

    # GREEN. differential.py builds its own span fixtures on javascript because
    # a difference there is the reader and never the parser.
    got = measure(js)
    out.append((got is not None and not got.why and got.askew == 0,
                f"the byte-exact control stays green: javascript {got.askew if got else '?'}"
                f" askew over {got.judged if got else 0} judged byte(s)"
                + (f" — {got.why}" if got and got.why else "")))

    # And that the rename class cannot swallow a misreading. `identifier` is a
    # declared ALIAS *value* in scala, so a name test would have excused
    # `else`-read-as-`identifier`; the pair test must not. Asked of the grammar
    # rather than of a measurement, so it holds whatever the parser does today.
    renames = alias_pairs(GRAMMARS / "scala.json")
    out.append((frozenset(("identifier", "else")) not in renames
                and any("identifier" in p for p in renames),
                f"a rename is a declared PAIR, not a name: scala declares {len(renames)}"
                f" alias pair(s), some naming `identifier`, and none of them pairs it"
                f" with `else`"))

    # And that a refusal is the COVER's verdict and not an ancestor's. Asked of
    # a tree written out here rather than of a corpus row, because the corpus
    # sweep costs a minute and this has to be cheap enough to be in the tripwire
    # everybody already runs; `plumb.py decline` makes the same claim against
    # all thirty real trees. The shape is `picorv32.v`'s, ten thousand times
    # smaller: one recovery bracket over everything, real structure underneath.
    wide = [Node("ERROR", True, 0, 100, 0, False),
            Node("identifier", True, 10, 20, 1, True),  # a token inside the ERROR
            Node("call", True, 30, 45, 1, False),  # a construct it still built
            Node("identifier", True, 30, 40, 2, True)]
    cover, region = hurt(wide, 100), engulfed(wide, 100)
    out.append((all(region), "the region rule taints every byte under a wide bracket:"
                             f" {sum(region)} of 100"))
    out.append((sum(cover) == 75 and not any(cover[10:20]) and not any(cover[30:45]),
                f"a refusal is the COVER's verdict, not an ancestor's: {sum(cover)} of 100"
                f" refused, and none of the 25 byte(s) under a node tree-sitter DID build"
                f" inside that bracket"))
    # The byte class the whole defect was: interior to a healthy construct, and
    # inside a recovery bracket. Named separately because it is the one an
    # ancestry rule and a cover rule answer differently, and a test that only
    # checked the leaves would have gone green throughout the bug.
    out.append((not cover[40] and region[40],
                "and a byte interior to a construct built inside the bracket (40, under"
                " `call` and no leaf) is judged, not refused — the exact class the"
                " ancestry rule wrote off"))

    for held, said in out:
        print(f"{'ok  ' if held else 'FAIL'}  {said}")
    bad = sum(not held for held, _ in out)
    print(f"\n{len(out) - bad} of {len(out)} held")
    return 1 if bad else 0


def inventory(picked: list[Case], as_json: bool) -> int:
    rows = []
    for c in picked:
        lang = c.lang / "src" / "grammar.json"
        rows.append({"name": c.name, "source": str(c.source.relative_to(ROOT)),
                     "oracle": str(c.lang.relative_to(ROOT)) if c.lang.is_relative_to(ROOT)
                     else str(c.lang), "generated": (c.lang / "src" / "parser.c").exists(),
                     "pinned": lang.exists()})
    if as_json:
        print(json.dumps({"case": rows}, indent=2))
        return 0
    print(f"{'grammar':<19}{'gen':<5}{'source':<52}oracle")
    for r in rows:
        print(f"{r['name']:<19}{'yes' if r['generated'] else 'NO':<5}{r['source']:<52}{r['oracle']}")
    return 0


def oops(msg: str) -> int:
    print(f"plumb.py: {msg}", file=sys.stderr)
    return 2


def main(argv: list[str]) -> int:
    as_json = "--json" in argv
    # A name may arrive either way. Both land in the same set, and a name that
    # names nothing is an ERROR — a filter silently ignored is how an instrument
    # reports the corpus while you believe you asked it about one grammar.
    bare = [a for a in argv if not a.startswith("-")]
    verb, want = (bare[0] if bare else ""), set(bare[1:])
    want |= {a.split("=", 1)[1] for a in argv if a.startswith("--grammar=")}
    if "-h" in argv or "--help" in argv or not verb:
        print(__doc__)
        return 0 if verb or "-h" in argv or "--help" in argv else 2
    if verb not in ("run", "board", "show", "verify", "list", "decline"):
        return oops(f"no such verb {verb!r}; try run, board, show, verify, list, decline")
    if not BIN.exists():
        return oops(f"no binary at {BIN}; run `zig build` first")
    known = {c.name for c in slate()}
    if stray := sorted(want - known):
        return oops(f"no grammar named {', '.join(stray)}; `list` names all {len(known)}")
    picked = [c for c in slate() if not want or c.name in want]
    if verb == "list":
        return inventory(picked, as_json)
    if not d.oracle_ready():
        print(f"plumb.py: no tree-sitter CLI at {d.TS}; there is nothing to compare against",
              file=sys.stderr)
        print("plumb.py: `python3 tool/differential.py install` puts a dev-only one there",
              file=sys.stderr)
        return 2
    if verb == "verify":
        return verify()
    if verb == "show":
        return show(picked)
    if verb == "decline":
        return decline(picked, as_json)
    mark = stamp.take(BIN)
    rows = sweep(picked)
    if not rows:
        return oops("no grammar resolved to a folio and a source")
    return board(rows, as_json) if verb == "board" else run(rows, as_json, mark)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

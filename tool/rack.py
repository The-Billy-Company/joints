#!/usr/bin/env python3
"""`plumb` asks whether a byte's *token* is right. Nothing asks whether its *tree* is.

`plumb.py` indexes each byte to the deepest node covering it and compares the
two names. That is the right instrument for "did we lex this the same" and a
structurally blind one for "did we parse this the same", and the previous lane
proved its own number a floor by finding the case that shows why:

    fmt.Print("x")

go reads that as a `type_conversion_expression` over a `qualified_type` - a
cast, not a call - at **100.0% standing, zero damage, zero mends**. Every
column this repository prints scores the file perfect. `plumb` charges it
**5 misread bytes of 996**: the length of `Print`, the only *leaf* whose name
moves. A wrong shape built over right leaves is nearly invisible to a
byte-indexed comparison, which is the board's own blind spot reproduced one
level up in the instrument built to catch it.

So this compares the **derivation**, not the byte's membership in a token.

## What is compared: the spine

For each byte, the sequence of `(name, named, start, end)` for every node
covering it, outermost first. Two spines are the same when they are equal
element for element. That is `plumb`'s test with everything above the deepest
node put back, so it is strictly stronger over the same population: a byte
`plumb` calls misread is misread here too, and a byte whose leaf agrees under a
parent that does not is caught here and nowhere else.

Labeled brackets - `(name, named, start, end)` per node - are the standard
constituency measure and they survive contact with this corpus. Measured before
this file was written: **javascript's two trees carry 324 nodes each and their
labeled bracket sets are identical**, 324 shared and none on either side alone.
Joints elides hidden rules, splices inlined ones and invents nodes for
aliases, and none of that moved a bracket on a grammar that works. A strict
comparison is therefore viable rather than drowned, which is the fact this
whole file rests on and the first thing to re-check if it starts reporting
nonsense.

## What is deliberately NOT compared

**Anything wider than the joints root the byte sits under.** Joints hands
back a forest on 18 of 30 grammars; tree-sitter always hands back one tree, so
its `source_file` covers bytes joints never reduced under anything. Charging
those would report *"joints returned a forest"*, which the board already
measures as `orphan`, `rubble` and `spoil`. Each built top-level root is a
**window** and the oracle's brackets are judged only where they are contained
in it. A byte with no contained oracle bracket at all is `unwindowed` - counted,
named, and never folded into a disagreement.

**Fields.** Both printers drop the field on an anonymous child, so including
one is a third CLI invocation per case (`differential.graft_fields`, and the
lane it cost). Dropping it makes this weaker than it could be, on purpose; a
lane whose whole claim is that the number should be **larger** should hold the
conservative instrument.

**A rename the grammar declares.** 1,096 of swift's 1,213 byte-level
disagreements were `ALIAS`es swift's own grammar states, and folding them in
made swift the corpus's second-worst grammar on a defect that misreads nothing.
Same rule here, applied position by position along the spine.

## Six buckets, and they total `built`

    square      the two spines are identical
    renamed     identical once the grammar's own declared ALIAS pairs are applied
    askew       they differ at the DEEPEST node - the class `plumb` already sees
    racked      the deepest node agrees and something ABOVE it differs
                - a right leaf under a wrong parent, and the reason this exists
    unframed    the bytes sit UNDER A FRAME WE NEVER BUILT, whatever we put
                underneath - the rung `within` drops, and the hole this file
                shipped with
    unjudged    the oracle has no verdict: `plumb`'s rule, plus `unwindowed`

## The price of a byte under a missing frame, and why it is a flag

`unframed` used to mean *"the spines agree rung for rung under a frame we never
built"*, and the agreement was doing work it should never have done. Where the
oracle had nothing below the frame and joints had something - our own extra
structure under a construct we are missing - the walk reached `not t_sp[k]`
first and filed the bytes `unwindowed`, which reads as the oracle's silence.
**Corpus-wide that was 1,237 of 1,264 `unwindowed` bytes: 97.9% of a column
that reads as silence was a charge.** Same missing frame, same bytes; the
column turned on nothing but whether we had built something wrong underneath,
so building MORE wrong structure under a frame you are missing moved bytes out
of a charge and into silence. Nineteen tripwires passed over it because not one
of them asserted anything about that branch.

It is now charged, and the retired rule is kept as a **price** rather than
deleted, because three lanes hold baselines taken under it:

    --price=charged     a byte under a frame we never built is unframed (today)
    --price=sheltered   ...unless we built something under it, which shelters
                        it into `unwindowed` (the rule before 2026-08-05)

Every report says which price it was taken under and digests the code that
decides it (`rack.py rule`), so a held baseline is re-derivable by name instead
of by archaeology and a rule change is ONE refusal instead of thirty phantom
drifts - `attest.py`'s pattern, one level down. `rack.py against <board.json>`
re-sweeps and diffs, and refuses at exit 4 across prices rather than subtracting
two numbers that mean different things.

`shade` is the disputed population and does not move with the price: bytes under
an unbuilt frame with our structure and none of the oracle's. `shelter` is how
many of them the active price still files `unwindowed` - **zero under
`charged`**, and the assertion `verify` now makes.

`racked + askew` is `crooked`, and it still means exactly that - `unframed` is
reported beside it rather than folded in, because every figure quoted off this
instrument means `askew + racked` and a word that quietly grows is worse than a
word with a sibling. `built`, `orphan`, `rubble`, `spoil`, their sum and
`standing` are not touched and are asserted against `standing.py`'s own rows
rather than restated.

## Two things `crooked` over-charges, and one it used to miss

`rack.py soft` subtracts what this file would not defend: an extra hanging in
two places, whitespace between two tokens, and - found by the toml lane - a
parent BOTH SIDES AGREE ON whose right edge moved. That last is a real defect
and it is not "a shape tree-sitter does not build", which is the sentence it
was feeding.

`unframed` is the other direction. `<p>x</q>`: tree-sitter reads one
`element [0, 8)`, joints reads three roots and no element, both spines agree
about every byte underneath, and this file scored it 7 built / 7 square / 0
askew / 0 racked. A perfect row for a parse missing the node the file is about.

## It is also the guard the verilog lane retired

*"Falling node counts are only reading-less when `covered` falls or `spoil`
rises alongside them"* fails because `covered` and `spoil` are built from the
same top-level spans as `built`: one root stretched over a hole moves all three
the flattering way at once. `square` is the only column here not made out of
the thing it checks - it is agreement with a second parser's derivation - so a
stretched root cannot buy it. `rack.py guard` runs the mend policies and prints
`built` beside `square`; a policy that buys one and pays the other is the trap.

    python3 tool/rack.py run            the sweep, per grammar, with and without php
    python3 tool/rack.py whole          the twelve grammars the board calls perfect
    python3 tool/rack.py board          standing.py's board, unmoved, with the split
    python3 tool/rack.py show go        the widest wrong-shape runs, with their bytes
    python3 tool/rack.py guard swift    built against square across the mend policies
    python3 tool/rack.py verify         the tripwires

    python3 tool/rack.py soft           how much of `crooked` is not a disputed shape
    python3 tool/rack.py rule           the pricing rule, and what its digest reads
    python3 tool/rack.py reprice        every row priced BOTH ways off one parse
    python3 tool/rack.py against b.json a kept board, re-swept and diffed

`--json` on `run` / `whole` / `board`; a positional name filters, and a name
that names nothing is an error rather than a silent full sweep.

    JOINTS_BIN=<path>   measure a pinned binary (`tool/pin.py`), not `zig-out`
    --oracle=<tag>        measure against a FROZEN oracle (`tool/attest.py`)
    --price=<name>        `charged` (default) or `sheltered` (see above)

The oracle is half of every number here and it moves: 28 of the 29 compiled
oracles on this machine exist as several different files at once, and one
grammar read 1,278 crooked in one run and 9,087 in the next off the same pinned
binary. Every report now closes with an `oracle:` line saying which one
answered, and a before/after pair wants `attest.py freeze <tag>` first - a
comparison whose two halves saw different oracles is not one.

Exit 0 measured, 1 a clean negative (a tripwire moved, a check failed), 2 could
not run, 4 a refusal to compare two things that are not comparable.
"""

from __future__ import annotations

import hashlib
import inspect
import json
import sys
from pathlib import Path
from typing import NamedTuple

sys.path.insert(0, str(Path(__file__).resolve().parent))

import attest  # noqa: E402
import differential as d  # noqa: E402 - the path has to be set first
import plumb  # noqa: E402
import standing  # noqa: E402
import stamp  # noqa: E402

ROOT = plumb.ROOT
# The twelve rows the board reads at 100.0% standing. Not a list kept here:
# `whole` reads it off `standing.survey`, because a hardcoded twelve is a
# twelve that goes stale the first time somebody fixes a grammar.
WHOLE = 1.0
# Every `--mend` policy the binary accepts, in the order `parse.zig` lists them.
POLICY = ("none", "keep", "fell", "relent")

# Which oracle answered. Every number below is a claim about two parsers and
# this file used to name one: `stamp` records fourteen fields and all fourteen
# are about joints. On a tree four lanes rebuild, that is not pedantry - 28 of
# the 29 compiled oracles on this machine exist as several different files at
# once, and 25 have a library older than the sources beside it. See `attest.py`.
# The oracle is half of every number this file prints, and until `attest`
# existed it carried no attribution at all - three libraries under
# `.local/differential/` were rebuilt by other lanes mid-session and scala read
# 1,278 crooked in one run and 9,087 in the next, same pin, same script.
consult, told = attest.consult, attest.told

# What a byte under a frame we never built costs. `charged` since 2026-08-05;
# `sheltered` is the rule this file shipped with, kept runnable because three
# lanes hold baselines taken under it and a baseline nobody can re-derive is a
# number, not a measurement.
WHITE = frozenset(b" \t\r\n\f\v")
CHARGED, SHELTERED = "charged", "sheltered"
PRICES = (CHARGED, SHELTERED)
PRICE = CHARGED
# The code that decides which bucket a byte lands in. Everything named here is
# folded into `rule()`; the walk that CALLS them is not, so adding a column or
# a print does not move the digest and rewriting the classification does.
DECIDES = ("bucket", "unframed", "excused", "inorder", "within", "cover")


class Rung(NamedTuple):
    """One node of a spine: what covers this byte, and where it covers."""

    name: str
    named: bool
    start: int
    end: int

    def label(self) -> str:
        return self.name if self.named else f'"{self.name}"'


class Run(NamedTuple):
    """One stretch of consecutive bytes filed the same way, and what each side
    called the node where the two spines first part."""

    start: int
    end: int
    kind: str  # racked · askew
    depth: int  # how far down the spine the disagreement starts
    ours: str
    theirs: str
    # Both sides name the same construct, starting in the same place, and
    # disagree only about where it STOPS. Nobody disputes a parent here, and
    # charging these to "a shape tree-sitter does not build" is an over-claim -
    # toml's whole row is one of them, and it is 62% of that grammar. Carried
    # as a flag rather than a fifth bucket because it is a *softness*, and
    # `soft` is where this file already separates what it would not defend.
    edge: bool = False

    @property
    def width(self) -> int:
        return self.end - self.start

    def as_dict(self) -> dict:
        return {**self._asdict(), "width": self.width}


class Seen(NamedTuple):
    name: str
    size: int
    built: int
    square: int
    renamed: int
    askew: int  # the spines part at the deepest node
    racked: int  # the deepest node agrees; a node above it does not
    unframed: int  # a node the oracle frames these bytes with that we never built
    engulf: int  # ...of those, how many the SINGLE WIDEST missing frame accounts for
    unjudged: int  # plumb's rule: no oracle node, or an interior under an ERROR
    unwindowed: int  # no oracle bracket contained in this joints root
    shade: int  # ...the disputed population: `unwindowed`-shaped AND under an unbuilt frame
    shelter: int  # ...of `shade`, how many the ACTIVE price still files unwindowed (0 charged)
    mute: int  # of `unjudged`, how many also sit under a frame we never built
    stretch: int  # of `built`, how many bytes no leaf of ours actually covers
    airy: int  # ...of those, how many are a WHITESPACE BYTE (the byte-class rule)
    # ...and the same split made by the second parser instead of by a byte class.
    # `stretch = warp + slack + veiled`, exactly, on every row.
    warp: int  # of `stretch`, bytes the ORACLE stands a leaf on — a token we owe
    slack: int  # ...bytes under no leaf on EITHER tree — the shared representation
    veiled: int  # ...bytes the oracle cannot adjudicate (`plumb`'s own blind rule)
    padding: int  # of `built`, bytes THEIR OWN TREE leaves under no leaf of its own
    gap: int  # of `askew + racked`, how many sit on a byte with no oracle LEAF
    ours_nodes: int  # labeled brackets inside the built windows, our side
    their_nodes: int
    shared: int  # ...and how many of them are the same bracket
    frames: int  # built roots, each the frame of one window
    framed: int  # ...of which this many disagree with the oracle about the frame's own name
    why: str
    worst: tuple[Run, ...] = ()

    @property
    def crooked(self) -> int:
        """Every byte whose derivation differs BELOW the frame, renames excused.

        Deliberately still `askew + racked` and nothing else. `unframed` is a
        real defect of the same family and it is reported beside this rather
        than folded into it, because every figure anybody has quoted off this
        instrument means `askew + racked` and a word that quietly grows is
        worse than a word with a sibling.
        """
        return self.askew + self.racked

    @property
    def unbuilt(self) -> int:
        """Crooked, plus the frames we never built at all. The whole defect."""
        return self.crooked + self.unframed

    @property
    def judged(self) -> int:
        return self.square + self.renamed + self.crooked + self.unframed

    @property
    def blind(self) -> int:
        return self.unjudged + self.unwindowed

    @property
    def damage(self) -> int:
        """`size - built`: the board's own column, restated so the next one can be."""
        return self.size - self.built

    @property
    def honest(self) -> int:
        """...and the same figure with the built bytes NO LEAF OF OURS covers put back.

        Read `text` beside it. A leaf is a token, so the space between two
        tokens is inside their parent and under no leaf - real by this
        definition and not a construct anybody failed to build. Both are
        printed and neither is the headline on its own.

        `built` is the union of the extents of our top-level roots that have
        children, so a root reaching over a hole carries the hole with it: the
        bytes are inside `built` and under no leaf, which is the same "we did
        not build this" the `damage` column is for. verilog's board damage is
        63,937 and its honest damage is 68,119 - the 4,182-byte difference is
        `stretch`, and three lanes optimised that row against `damage` before
        `square` could be read on it at all.

        `damage` itself is `standing.py`'s column and is not redefined here.
        This is the same file's bytes with the second figure printed beside the
        first, which is what "reconcile" means when both numbers are correct
        about different populations.
        """
        return self.damage + self.stretch

    @property
    def text(self) -> int:
        """Honest damage over the bytes that are not whitespace.

        The **byte-class** reading, and the one that used to be offered to a
        work order. Kept because a lane holds a baseline in it, and no longer
        the figure to quote: it excuses a whitespace byte on the strength of the
        byte being whitespace, where the question is whether a *token* stands on
        it. Those differ exactly over the tokens we failed to build — a
        `macro_text`, an html `text`, a string body — whose interior whitespace
        is not between two tokens at all. `owed` is the same reconciliation with
        the second parser asked instead of the byte.
        """
        return self.damage + self.stretch - self.airy

    @property
    def owed(self) -> int:
        """...and the same figure with the second parser asked instead.

        `damage + warp`: bytes outside `built` at all, plus bytes inside it that
        no leaf of ours covers **and tree-sitter stands a leaf on**. Every term
        is a byte some parser placed a token over and we did not.

        This is the adjudicated reconciliation and the figure to quote. It is
        strictly between `damage` and `honest` by construction, and it is not
        `text`: `text` is drawn by a byte class we chose, this one by the oracle
        the rest of the file is already judged against.
        """
        return self.damage + self.warp

    @property
    def share(self) -> float:
        """Crooked over the bytes the oracle could adjudicate.

        The honest denominator, and the same one `plumb.crooked` uses, so the
        two instruments' headline shares are comparable rather than merely
        adjacent. `crooked / built` reads a grammar with no oracle as clean,
        which is the silence-as-a-zero this board has been caught on twice.
        """
        return self.crooked / self.judged if self.judged else 0.0

    @property
    def recall(self) -> float:
        """Of the oracle's brackets inside the windows, how many we also have.

        Node-weighted where everything else here is byte-weighted, and printed
        beside it for exactly that reason: one wrong node over 40,995 bytes and
        forty thousand wrong nodes over 40,995 bytes are the same byte count
        and very different defects. If the byte column is red and this one is
        not, the byte column is one big node and should be read as one.
        """
        return self.shared / self.their_nodes if self.their_nodes else 0.0

    @property
    def precision(self) -> float:
        return self.shared / self.ours_nodes if self.ours_nodes else 0.0

    def as_dict(self) -> dict:
        return {**self._asdict(), "crooked": self.crooked, "unbuilt": self.unbuilt,
                "judged": self.judged, "blind": self.blind, "share": round(self.share, 4),
                "recall": round(self.recall, 4), "precision": round(self.precision, 4),
                "damage": self.damage, "honest": self.honest, "text": self.text,
                "owed": self.owed, "worst": [r.as_dict() for r in self.worst]}


# ------------------------------------------------------------------ the price

class Price(NamedTuple):
    """Which rule priced a board, and the version of the code that spells it.

    Both, because they fail differently. The NAME is what a lane holding a
    baseline needs - `--price=sheltered` re-derives it - and the RULE is what
    catches the case the name cannot: the same word meaning something else
    tomorrow. `attest.py` learned this the expensive way one level up, where
    five oracle pins disagreed on all thirty grammars and the oracle had not
    moved a byte; the rule had, and nothing on disk said so.
    """

    name: str
    rule: str

    def line(self) -> str:
        return (f"price: {self.name} · rule {self.rule[:12]}"
                + ("" if self.name == CHARGED else
                   "  ← the RETIRED rule; a byte under a frame we never built is"
                   " sheltered from the charge by our own structure"))

    def as_dict(self) -> dict:
        return {"name": self.name, "rule": self.rule}


_RULE: str | None = None


def rule() -> str:
    """A digest of the code that decides which bucket a byte lands in.

    Narrow on purpose, and the bound is stated rather than left in a dossier.
    It folds the six functions in `DECIDES` and the price table, so a column
    that changes meaning moves it. It does NOT reach `plumb` - the trees
    themselves, and the `built` scope they are judged over, are attributed by
    `stamp` (ours) and `attest` (theirs), and folding them in here would move
    this digest on every binary rebuild, which is a rule that changes for no
    reason. Three attributions, three questions: which binary, which oracle,
    which classification.
    """
    global _RULE
    if _RULE is None:
        h = hashlib.sha256()
        for name in DECIDES:
            h.update(f"{name}\0".encode())
            h.update(inspect.getsource(globals()[name]).encode())
            h.update(b"\0")
        h.update(repr(PRICES).encode())
        _RULE = h.hexdigest()
    return _RULE


def priced(name: str = "") -> Price:
    return Price(name or PRICE, rule())


# ------------------------------------------------------------------ the spines

def inorder(nodes: list[plumb.Node]) -> list[Rung]:
    """Every node as a spine rung, in pre-order: outer before inner, left to right.

    The tie-break is `depth`, and it is the whole reason this function exists
    rather than a `sorted` call at the call site. A parent and its only child
    routinely hold the **same extent** - tree-sitter's go reads `fmt.Print(b)`
    as `expression_statement [23, 35)` over `call_expression [23, 35)` - and a
    span key alone cannot order them. The first version broke that tie on
    `name`, so `call_expression` sorted above its own parent while joints's
    `expression_statement` over `type_conversion_expression` sorted correctly,
    and the two spines were charged with a disagreement at a rung where they
    in fact agreed. Nesting is not alphabetical; ask the tree.
    """
    ordered = sorted(nodes, key=lambda n: (n.start, -n.end, n.depth))
    return [Rung(n.name, n.named, n.start, n.end) for n in ordered]


def within(pile: list[Rung], starts: list[int], lo: int, hi: int) -> list[Rung]:
    """The rungs strictly INSIDE the window `[lo, hi)`, still in pre-order.

    Strictly, and that word cost this file its first set of numbers. Keeping a
    rung as wide as the window looks harmless and is not, because the window is
    an **joints root** and the two sides frame it differently by construction:
    joints hands back a forest whose root stops at the last token, tree-sitter
    one tree whose root reaches EOF. On `ascii.zig` those are `source_file
    [4163, 16124)` and `source_file [0, 16125)` - the same node, disagreeing
    about a leading comment run and a trailing newline. The first version of
    this file dropped theirs for reaching past the window, kept ours, and
    charged **11,914 bytes - 81.3% of zig - to a spine that was otherwise
    identical rung for rung.** The bracket recall column said 99.9% at the same
    time, which is what a byte number driven by one wide node looks like.

    So the frame is not judged from inside the frame. Both sides lose every
    rung that spans the window or more; what is compared is the derivation
    **below** it. The frame's own disagreement is real and is counted, once per
    root, by `framed` - and it is the thing `orphan`, `rubble` and `spoil`
    already price.

    Bisected on the pre-order start column rather than filtered, because the
    caller has one window per built root and haskell has 2,562 of them - a scan
    per window is a scan of every node 2,562 times, which is how a correct
    instrument becomes one nobody runs.
    """
    import bisect  # noqa: PLC0415 - one call site, kept beside its reason
    a = bisect.bisect_left(starts, lo)
    b = bisect.bisect_right(starts, hi)
    return [r for r in pile[a:b] if r.end <= hi and not (r.start <= lo and r.end >= hi)]


def cover(pile: list[Rung], cuts: list[int]) -> list[tuple[Rung, ...]]:
    """For each cut, every rung covering it, outermost first.

    A sweep rather than a search per byte: the spine only changes where a node
    begins or ends, so the cuts are those boundaries and the answer between two
    of them is one tuple.

    The active set is filtered by extent on every cut rather than popped like a
    stack, because a stack assumes proper nesting and this corpus contains a
    forest that is not: `standing.py` reports toml `UNSOUND - child outside its
    parent`, on one of the twelve grammars this file was written to audit. An
    instrument that assumes the shape it is checking for cannot report on it.
    """
    live: list[Rung] = []
    at, out = 0, []
    for p in cuts:
        while at < len(pile) and pile[at].start <= p:
            live.append(pile[at])
            at += 1
        if any(r.end <= p for r in live):
            live = [r for r in live if r.end > p]
        out.append(tuple(live))
    return out


def unframed(saw: plumb.Read, pile: list[Rung]) -> list[tuple[int, int, str]]:
    """The oracle brackets that FRAME two of our roots and that we never built.

    The hole this file shipped with. `within` refuses to judge a frame from
    inside itself - rightly, because joints hands back a forest and
    tree-sitter one tree, and the two disagree about a root's extent by
    construction. But that refusal is total: it also excuses the case where the
    oracle has a genuine construct spanning several of our roots and we simply
    do not have it. The whole disagreement then sits at a rung neither spine is
    judged at, and every byte underneath reads `square`.

    `<p>x</q>` is the specimen. tree-sitter reads one `element [0, 8)`;
    joints reads three roots side by side and no element at all. Both spines
    agree rung for rung about every byte below, so the old walk scored it
    **7 built, 7 square, 0 askew, 0 racked** - a perfect row for a parse that
    is missing the node the file is about.

    The rule is a **seam** test rather than a containment test, and the
    difference is the whole design:

      for each ADJACENT pair of our built roots, the NARROWEST oracle bracket
      that wholly contains both. If it is not the oracle's own root, and we
      have no node with exactly that extent, it is a frame we did not build.

    Containment alone would charge a forest grammar its entire file the moment
    the oracle had any node above `source_file` - haskell has 2,562 roots, so
    one `declarations` node would swallow the grammar and the number would say
    nothing about anything. A seam is local: it names the join our forest has
    and their tree does not, and it charges the construct that spans it.

    The oracle's own root is excluded because that disagreement is the
    forest-versus-tree one `within` already set aside, priced by `orphan`,
    `rubble` and `spoil`. Charging it here would be the same byte twice, under
    two instruments, with neither saying so.
    """
    import bisect  # noqa: PLC0415 - one call site, kept beside its reason

    roots = sorted({(ra, rb) for _, _, ra, rb in saw.windows})
    if len(roots) < 2:
        return []
    theirs = inorder(saw.theirs)
    if not theirs:
        return []
    # The oracle's root is the widest bracket, which is `inorder`'s first.
    crown, starts = theirs[0], [r.start for r in theirs]
    mine = {(r.start, r.end) for r in pile}
    out: dict[tuple[int, int], str] = {}
    for (lo, _), (_, hi) in zip(roots, roots[1:]):
        # Narrowest bracket holding BOTH roots whole - not merely the gap
        # between them, which a node starting inside the left root would also
        # span without framing either. Bisected on the pre-order start column
        # so a 2,562-root forest costs a scan of the candidates rather than of
        # every node per seam.
        span = min((r for r in theirs[:bisect.bisect_right(starts, lo)]
                    if r.end >= hi and r != crown),
                   key=lambda r: r.end - r.start, default=None)
        if span is not None and (span.start, span.end) not in mine:
            out[span.start, span.end] = span.name
    return [(lo, hi, name) for (lo, hi), name in out.items()]


def excused(ours: tuple[Rung, ...], theirs: tuple[Rung, ...],
            renames: set[frozenset[str]]) -> bool:
    """Do these two spines agree once the grammar's own renames are applied?

    A rename is a **declared pair over one extent**, never a name. `identifier`
    is a declared alias value in scala, python and elixir, so a name test would
    excuse `else`-read-as-`identifier`; the pair test does not. Spans must be
    equal at every position, so a rename can never launder a regrouping.
    """
    if len(ours) != len(theirs):
        return False
    for a, b in zip(ours, theirs):
        if a == b:
            continue
        if (a.start, a.end) != (b.start, b.end):
            return False
        if frozenset((a.name, b.name)) not in renames:
            return False
    return True


def bucket(ours: tuple[Rung, ...], theirs: tuple[Rung, ...],
           renames: set[frozenset[str]], blind: bool, missing: bool,
           price: str = "") -> str:
    """Which bucket one cut belongs to. THE classification, in one place.

    Extracted from the middle of `survey`'s walk because a second copy of this
    rule already exists in `research/joinery/flag/spans.py` - it re-implements
    the branch order to file one record per interval instead of a sum, and it
    does not have the `missing` test at all, so what this calls `unframed` that
    file calls `square`. An unwatched second copy of a rule is how this
    repository has arrived at two instruments spelling one word two ways,
    repeatedly and always in the flattering direction. Call this.

    **The order is the whole content of the function**, and it was wrong. The
    old walk asked `not theirs` - "the oracle had nothing to say here" - before
    it ever asked whether the frame overhead is one we failed to build, so a
    byte under a missing frame with our own structure under it read `unwindowed`
    (silence) instead of `unframed` (a charge). 97.9% of that column corpus-wide.
    The `missing` test now runs INSIDE that branch, under `charged`.

    `blind` still comes first and stays first. That is `plumb`'s rule verbatim -
    no oracle node over the byte, or an interior position under an `ERROR` - and
    it is a statement about the ORACLE's competence, not about ours. A missing
    frame does not make the oracle's silence into our defect; `survey` counts
    the overlap as `mute` rather than moving it, because the day this file
    charges a byte the oracle never adjudicated is the day `square`'s
    denominator stops meaning anything.

    `askew` and `racked` are likewise not moved: a byte already charged is
    charged, and moving it here would flatter both columns at once.
    """
    if blind:
        return "unjudged"
    if ours == theirs:
        # Including both empty, which is agreement and not absence: a byte
        # under the frame and nothing else, on both sides, is two parsers
        # saying the same thing about it. Filing that `unwindowed` cost
        # javascript 11 of its 1,080 bytes and made the green control fail its
        # own anti-vacuity assertion.
        #
        # ...unless the agreement is only true below a frame we never built.
        # Two spines can match rung for rung and still describe different
        # trees, because the rung they differ at is the one `within` dropped.
        # That is the whole `<p>x</q>` defect.
        return "unframed" if missing else "square"
    if not theirs:
        # The oracle has nothing below the frame here and joints does. Where
        # the frame itself is one we never built, these are the SAME bytes as
        # the branch above under the SAME missing construct, differing only in
        # whether we put something of our own underneath - so charging one and
        # not the other prices our own extra structure as a mitigation.
        # Elsewhere it is still counted and named rather than charged: the
        # oracle's silence inside a window is not a verdict.
        return "unframed" if missing and (price or PRICE) == CHARGED else "unwindowed"
    if excused(ours, theirs, renames):
        return "unframed" if missing else "renamed"
    return "racked" if (ours[-1] if ours else None) == theirs[-1] else "askew"


def parts(ours: tuple[Rung, ...], theirs: tuple[Rung, ...]) -> int:
    """The depth at which two spines first differ, or -1 when they do not."""
    for i, (a, b) in enumerate(zip(ours, theirs)):
        if a != b:
            return i
    return -1 if len(ours) == len(theirs) else min(len(ours), len(theirs))


# ------------------------------------------------------------------- the judge

def survey(name: str, saw: plumb.Read, top: int = 6, price: str = "") -> Seen:
    """One row: the board's `built` spans, judged by derivation instead of token.

    `unjudged` is `plumb`'s rule verbatim - no oracle node over the byte, or an
    interior position under an `ERROR` - so the two instruments partition the
    same population the same way and a share from one can be read beside a
    share from the other.

    `price` selects which rule prices a byte under a frame we never built; it
    defaults to the module's, which the CLI sets. `bucket` decides, this
    counts, and the two are separate so that a second walk (`flag/spans.py`)
    can be a different walk without being a second classification.
    """
    import bisect  # noqa: PLC0415 - one call site, kept beside its reason

    size = len(saw.blob)
    t_who = plumb.paint(saw.theirs, size)
    t_bad = plumb.hurt(saw.theirs, size, t_who)
    tally = dict.fromkeys(
        ("square", "renamed", "askew", "racked", "unframed", "engulf",
         "unjudged", "unwindowed", "shade", "shelter", "mute"), 0)
    gap = 0
    runs: list[Run] = []
    ours_nodes = their_nodes = shared = 0
    o_pile, t_pile = inorder(saw.mine), inorder(saw.theirs)
    # Bytes the oracle frames with a construct we never built. Taken from
    # `square` and `renamed` only: a byte already charged `askew` or `racked`
    # is charged, and moving it here would flatter both columns at once.
    missing = bytearray(size)
    holes = sorted(unframed(saw, o_pile), key=lambda s: s[1] - s[0])
    for lo, hi, _ in holes:
        missing[lo:hi] = b"\1" * (hi - lo)
    # How much of the charge is ONE node. elixir's corpus file is a single
    # `do_block` over 46,063 of its 46,089 bytes and php's is one
    # `declaration_list` over 67,146 of 67,845: the forest-versus-tree
    # difference standing one level below the oracle's root, where the depth-0
    # exclusion cannot see it. A predicate would need a threshold, so this is
    # not one - it is the plain share the widest frame accounts for, and a row
    # where it approaches the whole is a row nobody should read as N missing
    # constructs.
    swallow = bytearray(size)
    if holes:
        lo, hi, _ = holes[-1]
        swallow[lo:hi] = b"\1" * (hi - lo)

    def frame(p: int) -> str:
        """The narrowest unbuilt frame over this byte - `holes` is width-sorted."""
        return next((n for lo, hi, n in holes if lo <= p < hi), "—")

    def note(p: int, wide: int, kind: str, at: int, a: str, b: str, slid: bool = False) -> None:
        """File one interval, coalescing with the last if it says the same thing."""
        if runs and runs[-1].end == p and runs[-1][2:] == (kind, at, a, b, slid):
            runs[-1] = runs[-1]._replace(end=p + wide)
        else:
            runs.append(Run(p, p + wide, kind, at, a, b, slid))
    o_from = [r.start for r in o_pile]
    t_from = [r.start for r in t_pile]
    # Every boundary either tree has, once for the file rather than once per
    # window. Both trees and not only the contained ones: `t_who` and `t_bad`
    # are painted from the WHOLE oracle tree, so a bracket reaching past a
    # window must still break an interval or the plumb-identical `unjudged`
    # rule would be read off the wrong byte.
    edge = sorted({v for r in (*o_pile, *t_pile) for v in (r.start, r.end)})

    frames = framed = 0
    for lo, hi, ra, rb in saw.windows:
        mine = within(o_pile, o_from, ra, rb)
        yours = within(t_pile, t_from, ra, rb)
        # The frame itself: what each side calls the construct this window IS.
        # Not judged byte by byte - the two sides disagree about a root's
        # extent by construction, which is `orphan`/`rubble`/`spoil`'s job -
        # but counted, because dropping a rung is not the same as pretending
        # nobody ever stood on it.
        frames += 1
        ours_frame = next((r.name for r in o_pile[bisect.bisect_left(o_from, ra):]
                           if (r.start, r.end) == (ra, rb)), None)
        their_frame = min((r for r in t_pile[:bisect.bisect_right(t_from, ra)] if r.end >= rb),
                          key=lambda r: r.end - r.start, default=None)
        framed += ours_frame is not None and their_frame is not None \
            and ours_frame != their_frame.name
        ours_nodes += len(mine)
        their_nodes += len(yours)
        ledger = set(mine)
        shared += sum(r in ledger for r in yours)
        cuts = sorted({lo, hi, *edge[bisect.bisect_right(edge, lo):
                                    bisect.bisect_left(edge, hi)]})
        o_sp = cover(mine, cuts[:-1])
        t_sp = cover(yours, cuts[:-1])
        for k, p in enumerate(cuts[:-1]):
            wide = cuts[k + 1] - p
            them = saw.theirs[t_who[p]] if t_who[p] >= 0 else None
            # `plumb`'s rule verbatim, and it is one test now rather than
            # three: `hurt` is asked of the node covering the byte, so
            # `t_bad[p]` already means "the innermost cover is disowned" and
            # the leaf clause it used to carry was the ancestry rule's.
            blind = them is None or t_bad[p]
            hole = bool(missing[p])
            kind = bucket(o_sp[k], t_sp[k], saw.renames, blind, hole, price)
            if kind == "unjudged":
                tally["unjudged"] += wide
                # Counted, never moved. See `bucket`: the oracle's silence is
                # not our defect, but a fifth of it standing under a hole is a
                # fact a report should say rather than a lane rediscover.
                tally["mute"] += wide if hole else 0
                continue
            # The disputed population, priced either way and reported both
            # ways: `shade` does not move with the price and `shelter` is
            # exactly what the retired rule still lets through.
            if hole and not t_sp[k] and o_sp[k]:
                tally["shade"] += wide
                tally["shelter"] += wide if kind == "unwindowed" else 0
            if kind in ("square", "renamed", "unwindowed"):
                tally[kind] += wide
                continue
            if kind == "unframed":
                tally["unframed"] += wide
                tally["engulf"] += wide if swallow[p] else 0
                note(p, wide, "unframed", -1, "—", frame(p))
                continue
            tally[kind] += wide
            gap += wide if not them.leaf else 0
            at = parts(o_sp[k], t_sp[k])
            mine_at = o_sp[k][at] if at < len(o_sp[k]) else None
            their_at = t_sp[k][at] if at < len(t_sp[k]) else None
            a = mine_at.label() if mine_at else "—"
            b = their_at.label() if their_at else "—"
            note(p, wide, kind, at, a, b,
                 # The same construct, starting in the same place, stopping
                 # somewhere else. `soft` subtracts these; see `Run.edge`.
                 bool(mine_at and their_at and mine_at[:3] == their_at[:3]
                      and mine_at.end != their_at.end))

    # Of the bytes the board calls `built`, the ones no leaf of ours covers.
    # `built` is the union of our top-level roots' extents, so a root reaching
    # over a hole carries the hole inside `built` and out of `damage` - the
    # column three lanes optimised verilog against. Counted here because this
    # walk already holds both trees; `standing.py`'s `damage` is untouched and
    # `Seen.honest` prints beside it.
    stood = bytearray(size)
    for n in saw.mine:
        if n.leaf:
            stood[n.start:n.end] = b"\1" * (n.end - n.start)
    stretch = saw.built - sum(sum(stood[a:b]) for a, b in saw.scope)
    # ...and how much of that is the space BETWEEN two tokens, which is under
    # no leaf on any tree and is not a construct anybody failed to build.
    # Split rather than argued about, the same way `soft` splits `crooked`: a
    # number that cannot say which part of itself is soft gets quoted whole.
    airy = sum(1 for a, b in saw.scope
               for c, on in zip(saw.blob[a:b], stood[a:b]) if not on and c in WHITE)
    # ...and the same split asked of the OTHER PARSER instead of of the byte.
    # `airy` excuses a byte because the byte is a space; the claim being made is
    # that no *token* stands there. Those are different questions and they part
    # company exactly over the tokens we failed to build - a `macro_text`, an
    # html `text`, the interior of a string - whose whitespace is inside one
    # token rather than between two. So the oracle is asked which of the three
    # each stretch byte is, and `stretch == warp + slack + veiled` on every row
    # because the three exhaust the bytes of `scope` that `stood` does not hold.
    #
    #   warp    tree-sitter stands a leaf here and we stand none: a token we owe
    #   slack   under no leaf on EITHER tree: both representations leave it bare
    #   veiled  the oracle declines - `plumb`'s own blind rule, not a fourth one
    #
    # `veiled` is a VERDICT and reads like an absence, which is what let it be
    # wrong in silence: 4,586 of this arm's 4,615 were verilog, refused not by
    # tree-sitter but by an ancestry test reading one 94,657-byte root. It is
    # now the cover's own answer, and `plumb.py decline` is the tripwire that
    # would have said so.
    t_leaf, t_ok = bytearray(size), bytearray(size)
    for n in saw.theirs:
        a0, b0 = max(n.start, 0), min(n.end, size)
        if n.leaf and b0 > a0:
            t_leaf[a0:b0] = b"\1" * (b0 - a0)
            # A leaf tree-sitter names `ERROR`/`MISSING` inside a recovery
            # region is the one leaf `plumb` will not quote, so it cannot be a
            # token we owe either. Painted separately rather than tested per
            # byte, which keeps this identical to `blind` above by construction.
            if not n.name.startswith(plumb.HURT):
                t_ok[a0:b0] = b"\1" * (b0 - a0)
    warp = slack = veiled = padding = 0
    for a, b in saw.scope:
        for on, tl, tk, who, bad in zip(stood[a:b], t_leaf[a:b], t_ok[a:b],
                                        t_who[a:b], t_bad[a:b]):
            # Their own gap, whatever we did: a byte their tree covers with a
            # node and with no leaf. The oracle's answer to the question this
            # column asks about us, so `slack` has something to be a share of.
            padding += who >= 0 and not tl
            if on:
                continue
            # `bad` is the cover's own verdict now, so the `not tk` guard that
            # used to sit beside it is gone: nothing can be deeper than a leaf,
            # so a byte whose innermost cover is disowned has no healthy leaf
            # over it by construction. The guard was load-bearing only under
            # the ancestry rule, where `bad` was true of every byte in the file
            # and `tk` was the one thing rescuing verilog's 17,290 real tokens
            # from being called unadjudicable along with the whitespace.
            if who < 0 or bad:
                veiled += 1
            elif tk:
                warp += 1
            else:
                slack += 1

    return Seen(name=name, size=size, built=saw.built, square=tally["square"],
                renamed=tally["renamed"], askew=tally["askew"], racked=tally["racked"],
                unframed=tally["unframed"], engulf=tally["engulf"],
                unjudged=tally["unjudged"], unwindowed=tally["unwindowed"],
                shade=tally["shade"], shelter=tally["shelter"], mute=tally["mute"],
                stretch=stretch, airy=airy, warp=warp, slack=slack, veiled=veiled,
                padding=padding, gap=gap, ours_nodes=ours_nodes,
                their_nodes=their_nodes, shared=shared, frames=frames, framed=framed,
                why="", worst=widest(runs, top))


def widest(runs: list[Run], top: int) -> tuple[Run, ...]:
    """The `top` widest runs OF EACH KIND, not of all of them.

    `unframed` runs are whole constructs and `askew`/`racked` runs are byte
    stretches under one, so a single ranking would let one grammar's missing
    frame evict every crooked run it contains - and `soft`, which reads these
    as its sample of `crooked`, would silently start reading a different
    population than the column it divides into.
    """
    kinds = {r.kind for r in runs}
    keep = {id(r) for k in kinds
            for r in sorted((x for x in runs if x.kind == k),
                            key=lambda r: -r.width)[:top]}
    return tuple(sorted((r for r in runs if id(r) in keep), key=lambda r: -r.width))


def blank(name: str, size: int, built: int, why: str) -> Seen:
    """A row nothing could judge: every built byte is the oracle's silence.

    Named fields rather than eighteen positional zeroes - the positional form
    put `built` in the right slot by counting commas, and the row has grown
    four columns since.
    """
    return Seen(name=name, size=size, built=built, square=0, renamed=0, askew=0,
                racked=0, unframed=0, engulf=0, unjudged=built, unwindowed=0,
                shade=0, shelter=0, mute=0, stretch=0, airy=0, warp=0, slack=0,
                veiled=0, padding=0, gap=0, ours_nodes=0,
                their_nodes=0, shared=0, frames=0, framed=0, why=why)


def measure(case: plumb.Case, top: int = 6, extra: tuple[str, ...] = (),
            price: str = "") -> Seen | None:
    saw = plumb.read(case, extra)
    if saw is None:
        return None
    if saw.why:
        return blank(case.name, len(saw.blob), saw.built, saw.why)
    return survey(case.name, saw, top, price)


def warm(picked: list[plumb.Case]) -> None:
    d.lay_out()
    for case in picked:
        try:
            with d.alone(d.named(case.lang)):
                d.oracle_build(case.lang, case.grammar)
                d.cli([str(d.TS), "parse", "-p", str(case.lang), "-q", str(case.source)], d.WORK)
        except (OSError, ValueError):
            pass  # `measure` reports it properly; this only pre-compiles


def sweep(picked: list[plumb.Case], top: int = 6) -> list[Seen]:
    warm(picked)
    return [r for c in picked if (r := measure(c, top)) is not None]


def twice(picked: list[plumb.Case]) -> list[tuple[Seen, Seen]]:
    """Every row surveyed under BOTH prices off one parse.

    Not two runs. `plumb.read` is called once per grammar and the single `Read`
    it returns - same forest, same oracle tree, same windows, same renames - is
    classified twice, so the delta is the rule and can be nothing else. Two
    boards taken minutes apart would each be correct and their difference would
    still carry every byte a sibling landed in between; ten lanes share this
    tree and one of them cost a sibling twenty minutes this morning. There is
    no such term here, which is why this and not a pair of `--price=` boards is
    what the re-priced table is read off.
    """
    warm(picked)
    out: list[tuple[Seen, Seen]] = []
    for case in picked:
        saw = plumb.read(case)
        if saw is None:
            continue
        if saw.why:
            flat = blank(case.name, len(saw.blob), saw.built, saw.why)
            out.append((flat, flat))
            continue
        out.append((survey(case.name, saw, 1, SHELTERED),
                    survey(case.name, saw, 1, CHARGED)))
    return out


# ----------------------------------------------------------------------- verbs

def totals(rows: list[Seen], label: str) -> None:
    built = sum(r.built for r in rows)
    ok = sum(r.square for r in rows)
    bad, rack = sum(r.askew for r in rows), sum(r.racked for r in rows)
    alias = sum(r.renamed for r in rows)
    frame = sum(r.unframed for r in rows)
    out = sum(r.blind for r in rows)
    judged = ok + alias + bad + rack + frame
    crooked = bad + rack
    if not built:
        return
    print(f"\n{label}")
    print(f"  bytes: {ok} square + {alias} renamed + {bad} askew + {rack} racked"
          f" + {frame} unframed + {out} unjudged = {built} built")
    if not judged:
        print("  nothing was adjudicable, so there is no share to report")
        return
    print(f"  {crooked} bytes are built in a shape tree-sitter does not build:"
          f" {rack} of them under a")
    print("  RIGHT leaf and a WRONG parent, which a byte-indexed comparison"
          " files as correct.")
    print(f"    {crooked / built * 100:>6.2f}%  of `built`")
    print(f"    {crooked / judged * 100:>6.2f}%  of the {judged} bytes the oracle could ADJUDICATE"
          f"  ← the honest denominator")
    print(f"    {crooked / 526798 * 100:>6.2f}%  of the 526,798-byte corpus")
    if frame:
        # Kept a separate sentence rather than added to the one above. These
        # bytes are not derived differently - rung for rung the two spines
        # agree - they are derived under a node one parser has and the other
        # never built, and every one of them used to read `square`.
        print(f"  a further {frame} bytes ({frame / built * 100:.2f}% of built) agree rung for"
              f" rung UNDER A FRAME WE\n  NEVER BUILT, which the walk below the frame cannot"
              f" see and used to score square.")
        print(f"    {(crooked + frame) / judged * 100:>6.2f}%  of adjudicable once both are"
              f" counted — {crooked} crooked + {frame} unframed")
        if eat := sum(r.engulf for r in rows):
            # The caveat this bucket has to carry itself. elixir's whole file
            # is one `do_block` and php's one `declaration_list` - the
            # forest-versus-tree difference standing one level below the
            # oracle's root, where the depth-0 exclusion cannot see it.
            # Charged, and never averaged in silently.
            hog = sorted((r for r in rows if r.engulf), key=lambda r: -r.engulf)[:3]
            print(f"  {eat} of those {frame} ({eat / frame * 100:.1f}%) are ONE frame per file —"
                  f" the widest single missing\n  node on each row, which for a grammar whose"
                  f" file is one construct is the whole\n  forest-versus-tree difference wearing"
                  f" a new name: "
                  + ", ".join(f"{r.name} {r.engulf}/{r.unframed}" for r in hog) + ".")
            print(f"  {frame - eat} bytes ({(frame - eat) / built * 100:.2f}% of built) are the"
                  f" charge over every OTHER missing frame.")
    print(f"  {out} built bytes ({out / built * 100:.1f}%) have no verdict at all and read as"
          f" clean under the first denominator.")


def run(rows: list[Seen], as_json: bool, mark: stamp.Stamp) -> int:
    if as_json:
        print(json.dumps({"stamp": mark.as_dict(),
                          "oracle": attest.SEATED.as_dict() if attest.SEATED else None,
                          "price": priced().as_dict(),
                          "row": [r.as_dict() for r in rows]}, indent=2))
        return 0
    print(f"\n{'grammar':<19}{'built':>8}{'judged':>8}{'square':>8}{'askew':>8}{'racked':>8}"
          f"{'unframed':>9}{'crooked':>9}{'renamed':>8}{'unjudg':>8}{'recall':>8}"
          f"  what the oracle could not say")
    print("-" * 138)
    for r in sorted(rows, key=lambda r: -r.unbuilt):
        print(f"{r.name:<19}{r.built:>8}{r.judged:>8}{r.square:>8}{r.askew:>8}{r.racked:>8}"
              f"{r.unframed:>9}{r.share * 100:>8.1f}%{r.renamed:>8}{r.blind:>8}"
              f"{(f'{r.recall * 100:.1f}%' if r.their_nodes else '—'):>8}  {r.why[:34]}")
    totals(rows, "ALL THIRTY GRAMMARS")
    # php is 97% of the byte-indexed number and 97% of that is one unlexable
    # token, so it wears a corpus-sized number that belongs to one afternoon of
    # lexer work. Printed both ways rather than picked between.
    rest = [r for r in rows if r.name != "php"]
    if len(rest) != len(rows):
        totals(rest, "WITHOUT php — one blind external, `encapsed_string_chars`, is not a corpus")
    hit = [r for r in rows if r.crooked]
    if hit:
        print("\nwidest by CROOKED " + " · ".join(
            f"{r.name} {r.crooked}" for r in sorted(hit, key=lambda r: -r.crooked)[:6]))
        wrong = [r for r in rows if r.racked]
        print("widest by RACKED  " + " · ".join(
            f"{r.name} {r.racked}" for r in sorted(wrong, key=lambda r: -r.racked)[:6])
            + "  ← right leaves, wrong parents: the class `plumb` cannot see")
        print("worst share       " + " · ".join(
            f"{r.name} {r.share * 100:.0f}%" for r in sorted(hit, key=lambda r: -r.share)[:6]))
        thin = [r for r in hit if r.their_nodes and r.recall < 0.999]
        print("worst BRACKET recall " + (" · ".join(
            f"{r.name} {r.recall * 100:.1f}%" for r in sorted(thin, key=lambda r: r.recall)[:6])
            or "none — every crooked row still shares every oracle bracket")
            + "\n                  ← node-weighted, so a row red on bytes and green here is"
              " one wide node")
    seep = sum(r.gap for r in rows)
    if seep:
        crooked = sum(r.crooked for r in rows)
        print(f"\nof the {crooked} crooked bytes, {seep} ({seep / crooked * 100:.1f}%) sit"
              f" between two tokens rather than inside one —\nbytes `plumb` set aside as"
              f" `interstice` because a token-kind comparison had nothing to say about\nthem."
              f" A derivation does: whitespace inside a construct is described by that"
              f" construct.")
    frame = [r for r in rows if r.unframed]
    if frame:
        print("\nwidest by UNFRAMED " + " · ".join(
            f"{r.name} {r.unframed}" for r in sorted(frame, key=lambda r: -r.unframed)[:6])
            + "\n                  ← the oracle frames these bytes with a construct we"
              " never built, and\n                    the two spines agree about everything"
              " underneath it")
    silence(rows)
    hollow(rows)
    unread(rows)
    print(told())
    print(priced().line())
    print(mark.line())
    return 0


def silence(rows: list[Seen], loud: float = 0.05) -> None:
    """Where the oracle said nothing, at the size it actually is.

    There was a block here keyed on `r.why` - the grammar the oracle refused
    whole. Right idea, one level too coarse, and it failed in both directions.
    verilog was refused whole and got one line among forty, under a heading
    softer than the fact; and a row silent over a *seventh* of its bytes got
    nothing at all, because `why` is empty when the bytes were refused one at a
    time by `plumb`'s own rule rather than by the reader giving up. So the two
    states that matter - `cannot be scored` and `is mostly not scored` - were a
    footnote and a blank.

    This fires on the **share**, so the mechanism cannot hide it, and it names
    a whole refusal separately because that is the case where `damage` is the
    only instrument left on the row and a work order will use it anyway.

    The two states inside `blind` are printed apart, because rolling them up
    under one sentence mislabeled a row for a day. haskell's 1,013 bytes were
    read - and quoted in a dossier - as "carry no oracle verdict" when its
    `unjudged` is exactly **0**: all 1,013 were `unwindowed`, and 1,013 of 1,013
    sat under a frame the oracle has and we do not. Corpus-wide that was 1,237
    of 1,264 unwindowed bytes (97.9%) - not the oracle having nothing to say
    about a byte, but `unframed`'s own population reaching the one branch of the
    walk checked BEFORE `missing[p]` was. **Those bytes are charged now**
    (`bucket`, and `--price=sheltered` to re-derive a baseline taken before it);
    what prints here is what is left, plus the two figures that say so:
    `shelter`, which the charged rule holds at zero, and `mute` - the same
    overlap in `unjudged`, which is NOT moved and is reported so that the next
    lane finds it as a column instead of as a discovery.
    """
    out = sum(r.blind for r in rows)
    built = sum(r.built for r in rows)
    if not out or not built:
        return
    hush = sorted((r for r in rows if r.built and r.blind / r.built >= loud),
                  key=lambda r: -r.blind / r.built)
    dumb, wide = sum(r.unjudged for r in rows), sum(r.unwindowed for r in rows)
    dark, kept = sum(r.shade for r in rows), sum(r.shelter for r in rows)
    gagged = sum(r.mute for r in rows)
    print(f"\nNOT JUDGED — {out} of {built} built bytes ({out / built * 100:.2f}%) got no"
          f" verdict: {dumb} `unjudged`, where the oracle\nhad nothing to say, and {wide}"
          f" `unwindowed`, where it framed the window from outside and we built inside"
          f" it.\nState it every time a percentage is quoted: neither is uniformly"
          f" distributed, and both are\nwidest exactly where the parsing is hardest.")
    print(f"  {dark} byte(s) sit under a frame we never built with our own structure and none"
          f" of the\n  oracle's — the population that used to read as silence."
          f" {kept} of them still do under the\n  `{priced().name}` price"
          + ("; the charge is on." if not kept else
             " — THE RETIRED RULE IS IN FORCE.")
          + (f"\n  A further {gagged} `unjudged` byte(s) ({gagged / dumb * 100:.1f}% of it) also"
             f" stand under a frame we never\n  built. They are NOT charged — the oracle's"
             f" silence is not our defect — but a column that\n  is one-fifth hole is not"
             f" 'the oracle had nothing to say' either." if gagged and dumb else ""))
    if not hush:
        print(f"  no row is over {loud * 100:.0f}% blind — what is left is scattered residue.")
        return
    for r in hush:
        # The reason column is the row's own split, not a constant: haskell read
        # `plumb rule, byte by byte` for a day while its `unjudged` was zero.
        why = r.why or ("plumb rule, byte by byte" if r.unjudged
                        else "no oracle refusal at all — every byte is unwindowed")
        print(f"  {r.name:<19}{r.blind:>8}{r.blind / r.built * 100:>7.1f}% of {r.built:<8}"
              f"  unjudged {r.unjudged:<6} unwindowed {r.unwindowed:<6}  {why}")
    if whole := [r for r in hush if r.why]:
        print(f"  {len(whole)} row(s) above were refused WHOLE: no square, no crooked, no"
              f" unframed. `damage`\n  is then the only instrument left on the row, and"
              f" `damage` is joints's own words\n  about its own forest. Do not rank work"
              f" off it.")


def hollow(rows: list[Seen], top: int = 6) -> None:
    """The bytes inside `built` that no leaf of ours covers - and whose they are.

    `damage` is `size - built` and `built` is the union of the extents of our
    top-level roots that have children, so a root reaching over a hole keeps the
    hole out of `damage`. `stretch` is that discrepancy derived from the leaves,
    on every row. A sibling lane established it and then had to guess what it
    meant, excusing the whitespace bytes among it on a sentence it chose: *a
    leaf is a token, so whitespace between two tokens is under no leaf and is
    not a defect.* It closed by saying nothing in the repository adjudicated
    that sentence, and the two prices it left standing were 77,000 bytes apart.

    **Tree-sitter adjudicates it, and it makes the same claim.** Its parent
    takes its first child's padding and adds every later child's `padding +
    size` to its own `size` (`ts_subtree_summarize_children`), each later
    child's node then starts *after* its own padding
    (`ts_node_child_iterator_next`), and a node ends at `start + size`
    (`ts_node_end_byte`). So on tree-sitter's tree the space between two tokens
    is inside every ancestor and inside no leaf. Joints's `Node` says the
    same thing in its own words - *a node spans from its first token to its
    last, so the extras between them are inside it and the ones around it are
    not* - and `Gather.reduce` implements it by refusing to let a child that
    consumed nothing set the start.

    So `stretch` is a property of the REPRESENTATION, and `padding` is the same
    property measured on the oracle's own tree by this same walk. What is left
    over after the oracle is asked - `warp` - is the part that is a defect.
    `airy` is not that question: it asks whether a byte is a space, where the
    sentence asks whether a token stands on it, and the two part company over
    the tokens we failed to build. Both figures are printed, because a lane
    holds a baseline in `text` and a baseline nobody can re-derive is a number.
    """
    seen = [r for r in rows if r.stretch]
    if not seen:
        return
    hurt, out = sum(r.damage for r in rows), sum(r.stretch for r in rows)
    air, bare = sum(r.airy for r in rows), sum(r.slack for r in rows)
    owe, blind = sum(r.warp for r in rows), sum(r.veiled for r in rows)
    theirs = sum(r.padding for r in rows)
    print(f"\nSTRETCH — {out} byte(s) sit inside `built` under no leaf of ours."
          f" The oracle's own tree\nleaves {theirs} of the same bytes under no leaf of ITS"
          f" own ({theirs / out * 100:.1f}%), so the hole is\nwhat both representations do"
          f" with the space between two tokens and not our defect.")
    def line(r: Seen) -> str:
        return (f"  {r.name:<19}{r.built:>8}{r.stretch:>8}{r.padding:>8}{r.slack:>8}"
                f"{r.warp:>7}{r.veiled:>8}{r.damage:>8}{r.owed:>8}{r.text:>8}")

    print(f"  {'grammar':<19}{'built':>8}{'stretch':>8}{'theirs':>8}{'slack':>8}{'warp':>7}"
          f"{'veiled':>8}{'damage':>8}{'owed':>8}{'text':>8}")
    for r in sorted(seen, key=lambda r: -r.stretch)[:top]:
        print(line(r))
    print(f"  of the {out}: {bare} ({bare / out * 100:.1f}%) under no leaf on EITHER tree,"
          f" {owe} ({owe / out * 100:.1f}%) a token the\n  oracle built and we did not,"
          f" {blind} ({blind / out * 100:.1f}%) the oracle declines to judge.")
    # BOTH POLES, always, and never off the bottom of a widest-first table. The
    # rows that owe a token are the whole reason `warp` is a column rather than
    # an assertion that it is zero, and they are small - swift's 63 bytes would
    # never appear beside html's 25,241 under any ranking by width.
    owing = sorted((r for r in seen if r.warp), key=lambda r: -r.warp)
    print(f"\n  and the {len(owing)} row(s) that owe a token the oracle built — the pole a"
          " width ranking cannot show:" if owing else
          "\n  NO row owes a token the oracle built. `warp` is vacuous on this board and"
          "\n  `owed` is `damage` under another name; retire it or widen the corpus.")
    for r in owing:
        print(line(r))

    # `damage` is legitimately zero on a clean single-grammar run, and a report
    # that divides by it dies on exactly the rows nothing is wrong with.
    def more(n: int) -> str:
        return f"{n / hurt * 100:.2f}% more" if hurt else "from a clean board"

    print(f"\n  corpus {hurt} `damage` on the board"
          f"\n         {hurt + owe} ADJUDICATED (`owed` = damage + warp) — +{owe},"
          f" {more(owe)}"
          f"\n         {hurt + out - air} by the byte class (`text` = damage + stretch −"
          f" airy) — {hurt + out - air - (hurt + owe):+} against the oracle"
          f"\n         {hurt + out} charging every stretch byte (`honest`) —"
          f" {more(out)}, and the oracle stands a leaf on"
          f" {owe / out * 100:.1f}% of what it charges."
          f"\n  Quote `owed`. `standing.py` owns `damage` and still means what it says;"
          f"\n  `text` is kept because a lane holds a baseline in it, not because it is right.")


def unread(rows: list[Seen]) -> None:
    """Diagnostics the parse already printed and no board has ever read.

    Not a new measurement. `standing.py` puts `UNSOUND — child outside its
    parent` on toml's row, and the board scores toml **100.0% standing** and
    `whole` in the same table, and this file's own `cover` cites that exact
    string in a comment explaining why it cannot assume proper nesting. Three
    instruments knew, and no report said it out loud where a number was being
    quoted, so a lane spent a day adjudicating toml against `rack` before
    finding the parser had been announcing it the whole time.

    A diagnostic nobody surfaces is a diagnostic nobody has. It costs one line.
    """
    seen = {b.name: b for b in standing.survey("all")}
    bad = [(r, seen[r.name]) for r in rows
           if r.name in seen and seen[r.name].unsound]
    if not bad:
        return
    print(f"\n{len(bad)} row(s) here carry a soundness complaint the PARSE ITSELF printed,"
          " which no board reads:")
    for r, b in sorted(bad, key=lambda p: -p[1].standing):
        print(f"  {r.name:<19}{b.standing * 100:>6.1f}% standing  UNSOUND: {b.unsound}")
    print("  These are joints's own words about its own forest. A grammar can score"
          " 100.0%\n  and `whole` on a board that never asked.")


def whole(as_json: bool, mark: stamp.Stamp, pin: str = "") -> int:
    """The grammars the board calls perfect, audited one at a time.

    Read off `standing.survey` rather than a list kept here, so a grammar that
    is fixed tomorrow leaves this table on its own.
    """
    base = {b.name: b for b in standing.survey("all") if b.standing >= WHOLE}
    picked = consult([c for c in plumb.slate() if c.name in base], pin)
    rows = sweep(picked, top=4)
    if as_json:
        print(json.dumps({"stamp": mark.as_dict(),
                          "oracle": attest.SEATED.as_dict() if attest.SEATED else None,
                          "price": priced().as_dict(),
                          "row": [r.as_dict() for r in rows]}, indent=2))
        return 0
    print(f"\nTHE {len(rows)} GRAMMARS THE BOARD READS AT 100.0% STANDING")
    print("Zero damage, zero mends, one root. Nothing about these ever reddens, which is"
          "\nexactly why a wrong shape would have gone unnoticed here and nowhere else.\n")
    print(f"{'grammar':<19}{'bytes':>8}{'built':>8}{'square':>8}{'askew':>7}{'racked':>8}"
          f"{'unframed':>9}{'crooked':>9}{'brackets':>10}{'shared':>8}{'recall':>8}"
          f"  the widest wrong shape")
    print("-" * 146)
    for r in sorted(rows, key=lambda r: -r.unbuilt):
        worst = next((w for w in r.worst if w.kind == "racked"), None) or (
            r.worst[0] if r.worst else None)
        note = (f"{worst.ours} where tree-sitter has {worst.theirs}" if worst else
                ("a frame we never built" if r.unframed else
                 "—" if not r.why else r.why[:40]))
        print(f"{r.name:<19}{r.size:>8}{r.built:>8}{r.square:>8}{r.askew:>7}{r.racked:>8}"
              f"{r.unframed:>9}{r.share * 100:>8.1f}%{r.their_nodes:>10}{r.shared:>8}"
              f"{(f'{r.recall * 100:.1f}%' if r.their_nodes else '—'):>8}  {note[:44]}")
    dirty = [r for r in rows if r.crooked]
    print(f"\n{len(dirty)} of {len(rows)} carry a byte the two parsers derive differently;"
          f" {sum(1 for r in rows if r.racked)} carry a RIGHT LEAF UNDER A WRONG PARENT;"
          f"\n{sum(1 for r in rows if r.unframed)} carry a frame the oracle builds and"
          f" joints does not.")
    totals(rows, "THE WHOLE TWELVE, TOGETHER")
    hollow(rows)
    unread(rows)
    print(told())
    print(priced().line())
    print(mark.line())
    return 0


def show(picked: list[plumb.Case]) -> int:
    for case in picked:
        r = measure(case, top=20)
        if r is None:
            print(f"# {case.name}: no folio\n")
            continue
        print(f"# {case.name}  {case.source.relative_to(ROOT)}")
        if r.why:
            print(f"  no verdict: {r.why}\n")
            continue
        print(f"  {r.built} built · {r.square} square · {r.askew} askew · {r.racked} racked"
              f" ({r.share * 100:.1f}% of judged) · {r.unframed} unframed · {r.renamed} renamed"
              f" · {r.blind} unjudged")
        if r.unframed and (saw := plumb.read(case)) is not None:
            for lo, hi, span in unframed(saw, inorder(saw.mine)):
                print(f"  NO FRAME for [{lo}, {hi}): the oracle builds {span} there and"
                      f" joints builds nothing"
                      f" — {saw.blob[lo:min(hi, lo + 40)].decode('utf-8', 'replace')!r}")
        print(f"  brackets: {r.shared} of the oracle's {r.their_nodes} shared"
              f" ({r.recall * 100:.1f}% recall), {r.ours_nodes} ours"
              f" ({r.precision * 100:.1f}% precision)")
        blob = case.source.read_bytes()
        if r.worst:
            print(f"\n  {'bytes':<18}{'wide':>6} {'kind':<8}{'at':>3}  {'joints':<30}"
                  f"{'tree-sitter':<30}text")
        for w in r.worst:
            text = blob[w.start:min(w.end, w.start + 26)].decode("utf-8", "replace")
            print(f"  {f'[{w.start}, {w.end})':<18}{w.width:>6} {w.kind:<8}{w.depth:>3}  "
                  f"{w.ours:<30}{w.theirs:<30}{text!r}")
        print()
    return 0


def board(rows: list[Seen], as_json: bool) -> int:
    """`standing.py`'s rows, reprinted unmodified, with `built` split by shape.

    Nothing here re-measures anything the board measures. The three checks at
    the bottom are what make that claim checkable rather than stated.
    """
    seen = {r.name: r for r in rows}
    base = standing.survey("all")
    print(f"\n{'grammar':<19}{'bytes':>8}{'stand':>7}{'built':>8}{'square':>8}{'askew':>7}"
          f"{'racked':>8}{'unfrmd':>7}{'renamed':>8}{'unjudg':>8}{'orphan':>7}{'rubble':>7}"
          f"{'spoil':>8}{'damage':>8}  sound")
    print("-" * 144)
    for b in sorted(base, key=lambda b: -seen[b.name].unbuilt if b.name in seen else 0):
        r = seen.get(b.name)
        cell = (f"{r.square:>8}{r.askew:>7}{r.racked:>8}{r.unframed:>7}{r.renamed:>8}"
                f"{r.blind:>8}" if r else
                f"{'—':>8}{'—':>7}{'—':>8}{'—':>7}{'—':>8}{'—':>8}")
        print(f"{b.name:<19}{b.size:>8}{b.standing * 100:>6.1f}%{b.built:>8}{cell}"
              f"{b.orphan:>7}{b.rubble:>7}{b.spoil:>8}{b.damage:>8}"
              f"  {'UNSOUND' if b.unsound else ''}")
    size = sum(b.size for b in base)
    built = sum(b.built for b in base)
    kept = sum(b.orphan for b in base) + sum(b.rubble for b in base) + sum(b.spoil for b in base)
    split = sum(r.square + r.renamed + r.askew + r.racked + r.unframed + r.blind for r in rows)
    covered = sum(r.built for r in rows)
    crooked = sum(r.crooked for r in rows)
    frame = sum(r.unframed for r in rows)
    print(f"\nbytes: {built} built + {kept} orphan+rubble+spoil = {size} — unmoved")
    print(f"       {built / size * 100:.2f}% standing, unmoved — of which {crooked} bytes"
          f" ({crooked / built * 100:.2f}% of built) are derived differently"
          f"\n       and a further {frame} ({frame / built * 100:.2f}%) sit under a frame"
          f" joints never built")
    if eat := sum(r.engulf for r in rows):
        print(f"       of those {frame}, {eat} ({eat / frame * 100:.1f}%) are ONE frame per file"
              f" — the widest single missing node\n       on each row, and where a file is one"
              f" construct that is the forest-versus-tree\n       difference wearing a new name."
              f" {frame - eat} bytes are every other missing frame.")
    checks = [
        (built + kept == size, f"the four buckets still total the corpus: {size} bytes"),
        (split == covered, f"the split totals `built` on every row it judged: {covered} bytes"),
        (covered == built, f"and it judged every built byte the board has: {covered} of {built}"),
        # Anti-vacuity. A run that judged nothing would satisfy all three above
        # by arithmetic and read as a clean board; this is the one that says the
        # instrument looked at something and was capable of disagreeing.
        (0 < sum(r.square for r in rows) < covered,
         f"and it is not vacuous: {sum(r.square for r in rows)} square is neither 0 nor"
         f" all {covered} built bytes"),
    ]
    for held, said in checks:
        print(f"{'CHECK' if held else '**BROKEN**':<18}{said}")
    hollow(rows)
    unread(rows)
    print(told())
    print(priced().line())
    if as_json:
        print(json.dumps({"price": priced().as_dict(),
                          "row": [{**b.as_dict(),
                                   **({k: v for k, v in seen[b.name].as_dict().items()
                                       if k not in ("name", "size", "built")}
                                      if b.name in seen else {})}
                                  for b in base]}, indent=2))
    return 0 if all(h for h, _ in checks) else 1


def reprice(pairs: list[tuple[Seen, Seen]], as_json: bool, mark: stamp.Stamp) -> int:
    """What the re-pricing moved, off one parse per row.

    The whole point of this verb is the last block it prints. A reclassification
    is exactly as trustworthy as the list of columns it did NOT touch, and that
    list is COMPUTED here rather than claimed: every numeric column is compared
    on every row, and any column that moved outside the expected set is printed
    as a break. `square` is the one that matters - it is the only column on this
    instrument that is a claim about a second parser - and if a rule about which
    bucket an UNADJUDICABLE byte lands in has moved it, the branch that moved was
    not the branch anybody meant to move.
    """
    moves = ("unframed", "engulf", "unwindowed", "shelter", "blind", "unbuilt", "judged")
    held = [c for c in Seen._fields if c not in ("name", "why", "worst")]
    held += ["crooked", "unbuilt", "judged", "blind", "damage", "honest", "text"]
    held = [c for c in dict.fromkeys(held) if c not in moves]
    print(f"\n{len(pairs)} row(s), each parsed ONCE and classified twice."
          f"  `sheltered` → `charged`\n")
    print(f"{'grammar':<15}" + "".join(f"{c[:9]:>10}{'Δ':>7}" for c in
                                       ("unframed", "unwindowed", "blind"))
          + f"{'share':>9}{'Δ':>9}")
    print("-" * 96)
    stirred = [(was, now) for was, now in pairs if was.as_dict() != now.as_dict()]
    for was, now in sorted(stirred, key=lambda p: p[1].unframed - p[0].unframed, reverse=True):
        cells = "".join(f"{getattr(now, c):>10}{getattr(now, c) - getattr(was, c):>+7}"
                        for c in ("unframed", "unwindowed", "blind"))
        print(f"{now.name:<15}{cells}{now.share * 100:>8.2f}%"
              f"{(now.share - was.share) * 100:>+9.3f}")
    quiet = len(pairs) - len(stirred)
    got = sum(n.unframed - w.unframed for w, n in pairs)
    print(f"\n{len(stirred)} row(s) moved, {quiet} did not."
          f"  {got} byte(s) move from `unwindowed` to `unframed` corpus-wide,"
          f"\nwhich is {got / max(sum(w.unwindowed for w, _ in pairs), 1) * 100:.1f}% of the"
          f" {sum(w.unwindowed for w, _ in pairs)} the retired rule filed as the oracle's silence.")
    # The columns that did not move, named and checked. A re-price is only as
    # honest as this list, so it is derived from `Seen._fields` - a column added
    # tomorrow is checked tomorrow without anybody remembering to add it here.
    broke = {c: [n.name for w, n in pairs if getattr(w, c) != getattr(n, c)] for c in held}
    broke = {c: rows for c, rows in broke.items() if rows}
    print(f"\n{len(held)} column(s) are byte-identical under both rules on all"
          f" {len(pairs)} row(s):\n  {', '.join(held)}")
    for c, rows in sorted(broke.items()):
        print(f"**BROKEN**        `{c}` moved on {len(rows)} row(s): {', '.join(rows[:6])}")
    if not broke:
        print("\nCHECK             `square` did not move on any row. The branch re-pointed is"
              " reached\n                  only where the oracle has nothing inside the window,"
              " which is\n                  disjoint from every branch that can produce a square"
              " byte.")
    print(told())
    print(priced().line())
    print(mark.line())
    if as_json:
        print(json.dumps({"price": priced().as_dict(), "stamp": mark.as_dict(),
                          "held": held, "broke": broke,
                          "row": [{"name": n.name,
                                   **{c: [getattr(w, c), getattr(n, c)] for c in moves}}
                                  for w, n in stirred]}, indent=2))
    return 1 if broke else 0


# ------------------------------------------------------------------- the guard

def guard(picked: list[plumb.Case], as_json: bool) -> int:
    """`built` against `square`, across every mend policy.

    The column the verilog lane needed and could not have. `covered` and
    `spoil` are functions of the same top-level spans as `built`, so a root
    stretched over a hole raises `built`, raises `covered` and lowers `spoil`
    together and the guard's two witnesses agree with the thing they witness.
    `square` is agreement with a second parser's derivation. A stretched root
    claims bytes that parser derives some other way, so it cannot buy `square`
    - and a policy that buys `built` while paying `square` is the trap, stated
    by a measurement that is not made out of `built`.
    """
    out = []
    for case in picked:
        base: Seen | None = None
        rows = []
        for how in POLICY:
            r = measure(case, top=2, extra=(f"--mend={how}",))
            if r is None:
                continue
            base = base or r
            rows.append((how, r))
        if not rows:
            print(f"# {case.name}: no folio\n")
            continue
        print(f"\n# {case.name}  {case.source.relative_to(ROOT)}")
        if all(r.why for _, r in rows):
            print(f"  no verdict under any policy: {rows[0][1].why}")
            print("  THE GUARD CANNOT RUN HERE. The oracle refuses this grammar, so a policy"
                  "\n  change on it is judged by nothing. State this rather than reading the"
                  "\n  absence as agreement.\n")
            out.append({"grammar": case.name, "usable": False, "why": rows[0][1].why})
            continue
        print(f"  {'policy':<9}{'built':>9}{'Δbuilt':>9}{'square':>9}{'Δsquare':>9}"
              f"{'crooked':>9}{'unjudged':>10}  verdict")
        fell = next((r for how, r in rows if how == "fell"), rows[0][1])
        seen = []
        for how, r in rows:
            db, ds = r.built - fell.built, r.square - fell.square
            say = ("baseline" if how == "fell" else
                   "BOUGHT `built`, PAID `square` — a stretched root" if db > 0 and ds < 0 else
                   "real: both rise" if db > 0 and ds > 0 else
                   "reads less, and says so" if db < 0 else "no change")
            print(f"  {how:<9}{r.built:>9}{db:>+9}{r.square:>9}{ds:>+9}{r.crooked:>9}"
                  f"{r.blind:>10}  {say}")
            seen.append({"policy": how, "built": r.built, "square": r.square,
                         "crooked": r.crooked, "unjudged": r.blind, "verdict": say})
        trap = [s for s in seen if s["built"] > fell.built and s["square"] < fell.square]
        print(f"  → {len(trap)} of {len(seen)} policies buy `built` and pay `square`"
              + (f": {', '.join(s['policy'] for s in trap)}" if trap else ""))
        out.append({"grammar": case.name, "usable": True, "policy": seen,
                    "trapped": [s["policy"] for s in trap]})
    if as_json:
        print(json.dumps({"case": out}, indent=2))
    return 0


# -------------------------------------------------------------------- tripwire

def verify() -> int:
    """Prove this can say no, on cases whose answer is known without it.

    Every assertion here is one this file must be able to FAIL. Two of them
    exist only to show the predicate still has a negative, and one exists
    because the failure mode nearest this work is a check that passes by
    examining nothing.
    """
    out: list[tuple[bool, str]] = []
    slate = plumb.slate()
    go = next(c for c in slate if c.name == "go")
    js = next(c for c in slate if c.name == "javascript")

    # RED. A wrong shape over right leaves is what this file exists to charge and
    # what `plumb` structurally cannot see, so that claim needs a live witness.
    #
    # Until today the witness was `specimen/go/selector-field.go` — `fmt.Print("x")`
    # read as a `type_conversion_expression` over a `qualified_type`, 100.0%
    # standing, zero damage, 5 misread bytes to `plumb` and the whole call to
    # this file. **A press lane fixed go and the witness dissolved.** The
    # specimen now scores 60 square of 60 built and agrees node for node, so
    # four assertions written against it went red for the best possible reason.
    #
    # That is the second falsifier on this file a sibling has dissolved, and the
    # lesson arrived the same shape both times (see `engulf` below): **a red
    # pinned to a named row is a red a sibling can delete**, and picking a
    # different row only picks the next one to be deleted. So it is asked of the
    # CORPUS. Some row must carry `racked` bytes — the deepest node agreed on
    # both sides, a node above it not — and `plumb`, which compares only that
    # deepest node, must charge the SAME FILE strictly less. Whichever row that
    # is today; a corpus with none fails here loudly rather than passing by
    # having nothing left to say.
    worst = None
    for c in slate:
        r = measure(c, top=9)
        if r is None or r.why or not r.racked:
            continue
        worst = max(worst, r, key=lambda x: x.racked) if worst else r
    out.append((worst is not None,
                f"some row is charged for a shape its leaves agree about:"
                f" {worst.name} carries {worst.racked} racked byte(s)"
                if worst is not None else
                "no row on the board carries a single `racked` byte, so the one defect"
                " class this file exists to catch has no witness on this corpus"))
    if worst is not None:
        flat = plumb.measure(next(c for c in slate if c.name == worst.name))
        # The whole claim in one inequality, and the only one that cannot be
        # satisfied by this file being broken in the charging direction: the
        # byte-indexed instrument, run over the same bytes of the same file,
        # scores it CLEANER. If these two ever converge, either go's defect
        # class is extinct or this file stopped looking above the leaf.
        out.append((flat is not None and not flat.why and flat.misread < worst.crooked,
                    f"and the byte-indexed instrument scores the same file cleaner:"
                    f" `plumb` charges {flat.misread if flat else '—'} misread where this"
                    f" charges {worst.crooked} crooked"
                    + (f" — {flat.why}" if flat is not None and flat.why else "")))
        seen = [w for w in worst.worst if w.kind == "racked"]
        out.append((bool(seen),
                    f"and the widest runs say so at a rung ABOVE the leaf:"
                    f" {len(seen)} of {len(worst.worst)} carry kind `racked`"))

    # ...and the dissolved witness is kept, as the regression guard for the fix
    # that dissolved it. The day go reads a call as a conversion again, this row
    # stops being square and this line is where it says so.
    red = plumb.SPECIMEN / "go" / "selector-field.go"
    if not red.exists():
        out.append((False, f"the retired red specimen is missing from {red}"))
    else:
        got = measure(plumb.Case("go-selector", go.grammar, go.lang, red), top=9)
        # A row that came back `None` is a row nothing measured, and it used to
        # arrive at the previous lane's assertions as `askew == 0` — the shape
        # that let a missing folio read as a correct parse. Absence is asserted
        # against, never defaulted.
        out.append((got is not None and not got.why,
                    "the retired red specimen produced a row at all"
                    + ("" if got is not None else f" — nothing measured {red.name}")))
        out.append((got is not None and not got.why and got.square == got.built > 0
                    and got.crooked == 0,
                    f"and go still builds the call it used to read as a conversion:"
                    f" {got.square if got else 0} square of {got.built if got else 0} built,"
                    f" {got.crooked if got else '—'} crooked"))

    # GREEN. 324 labeled brackets, identical on both sides, checked before this
    # file was written. If the byte walk finds a disagreement the bracket sets
    # do not have, the walk is wrong and not the parser.
    got = measure(js)
    out.append((got is not None and not got.why and got.crooked == 0,
                f"the bracket-exact control stays green: javascript {got.crooked if got else '?'}"
                f" crooked over {got.judged if got else 0} judged byte(s)"
                + (f" — {got.why}" if got and got.why else "")))
    out.append((got is not None and got.their_nodes > 0 and got.shared == got.their_nodes,
                f"and it is green for the right reason: {got.shared if got else 0} of"
                f" {got.their_nodes if got else 0} oracle brackets shared, so it agrees"
                f" node for node and not by having judged nothing"))

    # ANTI-VACUITY, and this is the assertion that caught itself. It first read
    # `0 < square < built` on javascript and FAILED, because javascript is
    # entirely square: the check asserted that a perfect control must be
    # imperfect. A green run and a run that examined nothing are still the two
    # things that must be told apart, so the claim is split rather than
    # loosened — the control must account for EVERY built byte, and the red
    # case must account for its bytes and disagree about some of them. One of
    # those cannot be satisfied by measuring nothing and the other cannot be
    # satisfied by measuring everything as wrong.
    out.append((got is not None and got.square == got.built > 0,
                f"the green control accounts for every built byte: javascript"
                f" {got.square if got else 0} square of {got.built if got else 0} built"))
    out.append((worst is not None and 0 < worst.square < worst.built,
                f"and the red case accounts for its bytes while disagreeing about some:"
                f" {worst.name if worst else '—'} {worst.square if worst else 0} square,"
                f" strictly between 0 and {worst.built if worst else 0} built"))

    # NESTING IS NOT ALPHABETICAL, and this file shipped a run of numbers that
    # believed it was. A parent and its only child share an extent often enough
    # that the tie-break in `inorder` is load-bearing, and breaking it on `name`
    # ordered tree-sitter's `expression_statement [23, 35)` BELOW its own child
    # `call_expression [23, 35)` while joints's same-extent pair happened to
    # sort right — charging a disagreement at a rung where the two agreed. It
    # moved 340 bytes between `askew` and `racked` corpus-wide and left the
    # total untouched, which is exactly why nothing else here would have caught
    # it. Asked of the real oracle tree, on the file the lane was sent at.
    if red.exists():
        pile = inorder(plumb.read(plumb.Case("go-selector", go.grammar, go.lang, red)).theirs)
        seat = {}
        for i, r in enumerate(pile):
            seat.setdefault((r.name, r.start, r.end), i)
        kid = next(((k, v) for k, v in seat.items() if k[0] == "call_expression"), None)
        mum = next(((k, v) for k, v in seat.items()
                    if k[0] == "expression_statement" and kid and k[1:] == kid[0][1:]), None)
        out.append((bool(kid and mum and mum[1] < kid[1]),
                    "a parent sharing its child's extent still sorts above it:"
                    f" expression_statement at {mum[1] if mum else '—'},"
                    f" call_expression at {kid[1] if kid else '—'}"
                    + ("" if mum and kid else " — no same-extent pair in the oracle tree")))

    # THE MISSING FRAME. `<p>x</q>`: tree-sitter reads one `element [0, 8)`,
    # joints reads three roots and no element at all. Every byte below the
    # frame is derived identically, so the walk this file shipped with scored
    # it 7 built / 7 square / 0 askew / 0 racked - a perfect row for a parse
    # missing the node the file is about. The specimen lane wrote it down and
    # this file could not see it.
    #
    # Driven both ways on purpose. The charge is asserted, AND the old rule is
    # run beside it, because "the new bucket is non-zero" is satisfied by a
    # rule that charges everything and the row that proves this one bites is
    # the row where the previous rule read clean.
    html = next((c for c in slate if c.name == "html"), None)
    spec = plumb.SPECIMEN / "html" / "erroneous-end-tag.html"
    if html is None or not spec.exists():
        out.append((False, f"the missing-frame specimen is not at {spec}"))
    else:
        case = plumb.Case("html-frame", html.grammar, html.lang, spec)
        saw = plumb.read(case)
        got = measure(case, top=9)
        out.append((got is not None and not got.why,
                    "the missing-frame specimen produced a row"
                    + (f" — {got.why}" if got and got.why else "")))
        if saw is not None and not saw.why and got is not None and not got.why:
            roots = sorted({(ra, rb) for _, _, ra, rb in saw.windows})
            span = unframed(saw, inorder(saw.mine))
            out.append((len(roots) > 1, f"joints builds a forest here: {len(roots)} roots"
                                        f" over {len(saw.blob)} bytes"))
            out.append((len(span) == 1 and span[0][0] <= roots[0][0]
                        and span[0][1] >= roots[-1][1],
                        f"and one oracle bracket frames every one of them that we never"
                        f" built: {span} over roots {roots}"))
            out.append((got.unframed == got.built > 0,
                        f"every built byte is charged `unframed`: {got.unframed} of"
                        f" {got.built}"))
            out.append((got.square == 0,
                        f"and none of them still reads square: {got.square}"))
            # The demonstration. Under the rule this file had before today,
            # the same bytes are a clean row - so the charge is load-bearing
            # rather than decorative, and the gate can be seen to bite.
            was = got._replace(square=got.built, unframed=0)
            out.append((was.crooked == 0 and was.square == was.built,
                        f"...where the rule this file shipped with scored the same bytes"
                        f" {was.square} square, {was.crooked} crooked — a perfect row"))
            # Anti-vacuity, and this is the one that matters: a rule charging
            # every forest its whole file would satisfy every assertion above.
            # A row of genuinely independent declarations must NOT be swallowed
            # whole - some of its roots are the oracle's roots too.
            #
            # Asked of whichever row can answer, haskell first because it is the
            # widest forest on the board. Naming *only* haskell is the shape that
            # broke the `engulf` tripwire below: a sibling press change dissolves
            # the named row's precondition and the assertion then fails for a
            # reason that has nothing to do with what it guards. The root count
            # is read off the measurement rather than written down, because the
            # comment that used to carry it said 2,562 while the row said 624.
            hs = next((c for c in slate if c.name == "haskell"), None)
            deep = measure(hs, top=1) if hs else None
            forest = deep if deep and not deep.why and 0 < deep.unframed < deep.built else None
            if forest is None:
                forest = next((r for c in slate if (r := measure(c, top=1))
                               and not r.why and r.frames > 1
                               and 0 < r.unframed < r.built), None)
            out.append((forest is not None,
                        f"and a forest is not swallowed whole: {forest.name}'s"
                        f" {forest.frames} roots cost it {forest.unframed} unframed of"
                        f" {forest.built} built — strictly between none and all of it"
                        if forest is not None else
                        "no row on the board is a forest charged strictly between none and"
                        " all of its built bytes, so the seam rule cannot be seen to stop"
                        " short of swallowing one"))
            # ...and that `engulf` can tell one file-wide frame from N missing
            # constructs, which is the whole reason the column exists.
            #
            # **This assertion named elixir until today and that was the bug.**
            # elixir's corpus file is one `do_block` over 46,063 of 46,089
            # bytes, so it was the pole: `engulf` had to account for nearly all
            # of its `unframed`. Then a press change on another lane let elixir
            # build that `do_block`, its `unframed` went to 0, and `engulf > 0 *
            # 0.9` is false - so the tripwire failed, and had the inequality
            # been non-strict it would have gone *vacuous* and read green
            # forever. A falsifier whose precondition a sibling can dissolve is
            # not a falsifier, and the fix is not to pick a different row: the
            # next row is dissolvable too.
            #
            # So it is asked of the CORPUS. Some row's `unframed` must be one
            # frame and some row's must not, whichever rows those are today, and
            # the population itself is asserted - a corpus with no `unframed`
            # left fails here loudly instead of passing by having nothing to
            # say. The widest of each pole is kept rather than the first, so the
            # line names a row where quoting `unframed` whole would actually
            # mislead; the row already measured above is offered to the scan
            # first to save a measurement, and nothing here depends on it.
            one = many = None
            # Chained rather than unpacked: `*(...)` would measure the whole
            # slate before the loop ever ran, which is the cost this avoids.
            import itertools  # noqa: PLC0415 - one call site, kept beside its reason
            for r in itertools.chain((deep,), (measure(c, top=1) for c in slate)):
                if one is not None and many is not None:
                    break
                if r is None or r.why or not r.unframed:
                    continue
                if r.engulf > r.unframed * 0.9:
                    one = max(one, r, key=lambda x: x.unframed) if one else r
                else:
                    many = max(many, r, key=lambda x: x.unframed) if many else r
            said = ("no row on the board has any `unframed` left, so this pole cannot be"
                    " read at all" if one is None and many is None else
                    f"and `engulf` still tells one frame from many: {one.name}"
                    f" {one.engulf}/{one.unframed} is a single frame, {many.name}"
                    f" {many.engulf}/{many.unframed} is not"
                    if one is not None and many is not None else
                    "every row with `unframed` is "
                    + ("one wide frame" if many is None else "several constructs")
                    + f" — {(one or many).name} {(one or many).engulf}/{(one or many).unframed}"
                    f" — so the column cannot be seen to discriminate")
            out.append((one is not None and many is not None, said))
            out.append((got.engulf == got.unframed > 0,
                        f"the specimen is honest about being that shape too:"
                        f" {got.engulf} of {got.unframed}"))

    # One corpus sweep, read by both corpus-shaped gates. Two sweeps would be
    # two populations whenever a sibling lands mid-run, and the two gates would
    # then disagree about a board they both call "the corpus".
    board = [r for c in slate if (r := measure(c, top=1)) and not r.why]
    out += shaded(slate, board)
    out += adjudged(board)

    # And that those gates can SAY NO, asked of the predicate rather than of a
    # run. A corpus-shaped assertion is only a falsifier if some board turns it
    # red, and the board that should is the one where the sentence is false: the
    # oracle's leaves tile its root, so every bare byte of ours is a token we
    # owe. That board cannot be produced by editing the corpus, so it is
    # constructed here and handed to the same function the corpus is.
    lied = blank("all-ours", 100, 100, "")._replace(
        stretch=50, airy=50, warp=50, slack=0, veiled=0, padding=0)
    said = adjudged([lied])
    out.append((sum(not held for held, _ in said) >= 3,
                f"the adjudication can be failed: a board where the oracle leaves no hole"
                f" of its own turns {sum(not held for held, _ in said)} of {len(said)}"
                f" row(s) red"))
    out.append((said[0][0],
                "and it fails for the right reason — the population row still holds,"
                " so the red rows are about the oracle's answer and not about"
                " having measured nothing"))

    # And that the rename excuse cannot swallow a regrouping: it requires an
    # identical extent, so two nodes over different bytes are never a rename
    # however their names are declared. Asked of the predicate, not of a run.
    a = (Rung("identifier", True, 0, 5),)
    b = (Rung("type_identifier", True, 0, 9),)
    pair = {frozenset(("identifier", "type_identifier"))}
    out.append((not excused(a, b, pair) and excused(a, (Rung("type_identifier", True, 0, 5),), pair),
                "a declared rename over DIFFERENT extents is not excused, and the same"
                " rename over identical extents is"))

    for held, said in out:
        print(f"{'ok  ' if held else 'FAIL'}  {said}")
    bad = sum(not held for held, _ in out)
    print(f"\n{len(out) - bad} of {len(out)} held")
    print(priced().line())
    return 1 if bad else 0


def adjudged(rows: list[Seen]) -> list[tuple[bool, str]]:
    """The sentence `stretch` and `airy` rest on, asked of the second parser.

    A sibling lane added both columns on one sentence it chose - *a leaf is a
    token, so whitespace between two tokens is under no leaf and is not a
    defect* - and closed by saying **nothing in the repository adjudicates the
    sentence**. Its 28 tripwires asserted nothing about either column, and the
    two prices it left standing were 77,000 bytes apart in the corpus headline.

    Tree-sitter settles it, and settles it in its own source rather than in
    prose about it. `ts_subtree_summarize_children` gives a parent its FIRST
    child's padding and then adds every later child's `total_size`
    (`padding + size`) to its own `size`; `ts_node_child_iterator_next` skips
    each later child's padding before minting that child's node; and
    `ts_node_end_byte` is `start + size`. So on tree-sitter's own tree the
    whitespace between two tokens is inside **every ancestor's** byte range and
    inside **no leaf**: measured on `research/joinery/corpus/ledger.go`, the gap
    `[784, 786)` between `}` and `var` sits inside `source_file`,
    `method_declaration`, `block` and `statement_list`, and inside nothing else.
    The sentence is tree-sitter's own rule, not a choice this repository made.

    Which makes `stretch` a property of the REPRESENTATION rather than a
    defect, and these assert exactly that: the oracle must be shown to have the
    same hole, of the same size, over the same bytes. `padding` is that hole
    measured on their tree by the walk that measures ours.

    The gates are corpus-shaped on purpose. A witness pinned to one row is a
    witness a sibling dissolves by fixing the product under it - it happened
    twice this week - so every row below is a share of the whole board and none
    of them names a grammar.
    """
    out: list[tuple[bool, str]] = []
    if not rows:
        return [(False, "no row on the board could be measured, so the stretch"
                        " population cannot be adjudicated at all")]
    out_of = sum(r.stretch for r in rows)
    bare, owe, blind = (sum(r.slack for r in rows), sum(r.warp for r in rows),
                        sum(r.veiled for r in rows))
    theirs = sum(r.padding for r in rows)
    air = sum(r.airy for r in rows)

    # POPULATION FIRST, or every row below is vacuous. A corpus that stopped
    # producing bare bytes must say so loudly rather than pass by having
    # nothing to adjudicate.
    out.append((out_of > 0,
                f"the population exists to be adjudicated: {out_of} byte(s) of `built`"
                f" sit under no leaf of ours"
                + ("" if out_of else
                   " — NOTHING, so nothing below is asserted about anything")))
    # THE ADJUDICATION. The oracle's own tree must leave a hole of its own in
    # the same scope, or `stretch` is ours alone and every byte of it is owed.
    out.append((theirs > 0,
                f"and the ORACLE leaves a hole of its own in the same scope:"
                f" {theirs} byte(s) of the same `built` are under no leaf of"
                f" tree-sitter's either"
                + ("" if theirs else
                   " — tree-sitter covers every built byte with a token, so"
                   " `stretch` is OUR defect and `airy` is excusing it")))
    # ...and of the same ORDER, which is the claim `honest` rests on. A rule
    # both parsers obey cannot price one of them 63% worse than the board does.
    out.append((0.5 <= theirs / out_of <= 2.0,
                f"and it is the same order of magnitude, not a token gesture:"
                f" theirs {theirs} against ours {out_of}"
                f" ({theirs / out_of * 100:.1f}%)"))
    # THE SPLIT IS EXHAUSTIVE, on every row. If this can drift, the three
    # columns beneath `stretch` are three numbers rather than a partition of it.
    off = [r.name for r in rows if r.stretch != r.warp + r.slack + r.veiled]
    out.append((not off,
                f"the split partitions it on every row: `stretch == warp + slack + veiled`"
                f" holds for all {len(rows)}"
                + (f" — EXCEPT {', '.join(off)}" if off else "")))
    # THE VERDICT. Almost all of it must be the shared gap, or the sentence is
    # false and `damage` is the larger figure after all. This is the row that
    # goes red if joints starts leaving bytes bare that tree-sitter tokenises.
    out.append((bare / out_of >= 0.5,
                f"and it is overwhelmingly the SHARED gap rather than a token we owe:"
                f" {bare} of {out_of} byte(s) ({bare / out_of * 100:.1f}%) are under no"
                f" leaf on either tree, against {owe} the oracle stands a leaf on"
                f" and {blind} it declines to judge"))
    # THE RESIDUE, and the reason `warp` is a column instead of an assertion
    # that it is zero. A hole both parsers have is a representation; a byte
    # tree-sitter tokenises and we do not is a defect, and there ARE some.
    owing = sorted((r for r in rows if r.warp), key=lambda r: -r.warp)
    out.append((owe > 0,
                f"`warp` still means something on its own: {owe} byte(s) over"
                f" {len(owing)} row(s) carry a token the oracle built and we did not"
                + ("" if owe else
                   " — the column reads zero everywhere and is an assertion pretending"
                   " to be a measurement; retire it or find the row it was for")))
    # THE BYTE CLASS IS NOT THE RULE, which is the whole defect in `airy`. The
    # sentence says "between two tokens"; `airy` asks whether the byte is a
    # space. Those part company, and the gap is what `owed` exists to price.
    out.append((air != bare,
                f"and the byte class is demonstrably not the rule it stands for:"
                f" `airy` excuses {air} byte(s) where the oracle leaves {bare} bare"
                f" — {abs(air - bare)} byte(s) apart"
                + ("" if air != bare else
                   " — identical, so nothing here distinguishes the two rules and"
                   " `owed` is not measuring anything `text` did not")))
    # AND THE PRICES ARE ORDERED, by construction rather than by luck. `owed`
    # charges a subset of `honest`, so a reader handed the wrong one of the
    # three is wrong by a bounded amount and can be told which way.
    out.append((all(r.damage <= r.owed <= r.honest for r in rows),
                f"the three prices stay ordered on every row:"
                f" damage {sum(r.damage for r in rows)} ≤ owed"
                f" {sum(r.owed for r in rows)} ≤ honest {sum(r.honest for r in rows)}"))
    return out


def shaded(slate: list[plumb.Case], rows: list[Seen]) -> list[tuple[bool, str]]:
    """The branch nobody tested: a byte under a frame we never built, with our
    own structure under it and none of the oracle's.

    Nineteen tripwires passed while 97.9% of `unwindowed` was that shape. Not
    one of them said anything about the branch, so the column could have been
    anything. These do, and they are asked of the CORPUS rather than of a named
    row - the `engulf` assertion named elixir, a sibling's press change
    dissolved elixir's precondition overnight, and the tripwire then failed for
    a reason that had nothing to do with what it guarded.

    Every row here is one `--price=sheltered` is meant to turn red, and that is
    the demonstration: the retired rule is not a mock of the old branch order,
    it IS the old branch order, reached by one `if` in `bucket`. Run
    `rack.py verify --price=sheltered` and the population rows stay green while
    the charge rows go red - which is the difference between a falsifier and a
    sentence about one.
    """
    out: list[tuple[bool, str]] = []
    if not rows:
        return [(False, "no row on the board could be measured, so the shade population"
                        " cannot be read at all")]
    dark = sum(r.shade for r in rows)
    kept = sum(r.shelter for r in rows)
    wide = sum(r.unwindowed for r in rows)
    lit = sorted((r for r in rows if r.shade), key=lambda r: -r.shade)

    # POPULATION. First, because every assertion below is vacuous without it
    # and a corpus that has stopped producing the shape must say so loudly
    # rather than pass by having nothing to price.
    out.append((dark > 0,
                f"the disputed population exists to be priced: {dark} byte(s) over"
                f" {len(lit)} row(s) sit under a frame we never built with our own"
                f" structure and none of the oracle's"
                + (f", widest {lit[0].name} {lit[0].shade}" if lit else
                   " — NOTHING, so nothing below is being asserted about anything")))

    # THE CHARGE. The one assertion whose absence let the column be 97.9%
    # mislabelled: no byte is BOTH filed as the oracle's silence AND standing
    # under a hole of ours.
    #
    # Unconditional, and the first draft was not - it read
    # `kept == 0 or PRICE != CHARGED`, which is a falsifier that excuses itself
    # exactly where it is supposed to bite, and it printed `ok` against 1,486
    # sheltered bytes on the first run under the retired rule. A gate that
    # cannot go red under the bug it was written for is the nineteen-passing-
    # tripwires state with one more row in it.
    out.append((kept == 0,
                f"no byte reads as silence while standing under a frame we never built:"
                f" {kept} sheltered of {dark}"
                + (f" — {', '.join(f'{r.name} {r.shelter}' for r in lit if r.shelter)}."
                   f" THE RETIRED BRANCH ORDER IS IN FORCE: `unwindowed` reads as the"
                   f" oracle's silence and is a charge." if kept else "")))

    # BOTH PRICES, ONE PARSE. That the re-pricing moves those two columns and
    # NOTHING else - `square` above all, the only column here that is a claim
    # about a second parser. Measured on one read of one file, because two
    # reads would compare two runs of the binary, which is the shape of
    # tripwire that passes while measuring nothing.
    case = next((c for c in slate if c.name == (lit[0].name if lit else "")), None)
    saw = plumb.read(case) if case else None
    if saw is None or saw.why:
        out.append((False, "the widest shade row could not be re-read, so the two prices"
                           " cannot be run over one parse"))
    else:
        hot = survey(case.name, saw, top=1, price=CHARGED)
        cold = survey(case.name, saw, top=1, price=SHELTERED)
        moved = {k: (getattr(hot, k), getattr(cold, k)) for k in
                 ("square", "renamed", "askew", "racked", "unjudged", "shade",
                  "mute", "built", "stretch",
                  # The oracle's answer about a byte cannot depend on OUR
                  # pricing policy. If one of these ever moves with the price,
                  # the adjudication is reading our own rule back to itself.
                  "warp", "slack", "veiled", "padding")
                 if getattr(hot, k) != getattr(cold, k)}
        out.append((not moved,
                    f"re-pricing moves nothing else on {case.name}: square"
                    f" {hot.square} either way"
                    + (f" — MOVED {moved}" if moved else
                       f", and crooked {hot.crooked}, and unjudged {hot.unjudged}")))
        out.append((hot.unframed - cold.unframed == cold.unwindowed - hot.unwindowed
                    == hot.shade > 0,
                    f"and it moves exactly the disputed bytes: unframed"
                    f" {cold.unframed}→{hot.unframed}, unwindowed"
                    f" {cold.unwindowed}→{hot.unwindowed}, shade {hot.shade}"))
        # The retired rule is RUN, not described. A price that cannot be
        # reproduced is a baseline nobody can re-derive, which is the whole
        # reason it was kept instead of deleted.
        out.append((cold.shelter == cold.shade == hot.shade > 0 and hot.shelter == 0,
                    f"and `--price=sheltered` restores the branch order rather than"
                    f" approximating it: {cold.shelter} of {cold.shade} sheltered under"
                    f" the retired rule, {hot.shelter} under this one"))

    # THE RESIDUE. `unwindowed` must still be able to hold something, or the
    # bucket has become an alias for `unframed` and should be retired rather
    # than kept as a column that only ever reads zero. This is the row that
    # stops "charge until the board looks right" from passing.
    left = [r for r in rows if r.unwindowed - r.shelter]
    out.append((wide - kept > 0,
                f"`unwindowed` still means something on its own: {wide - kept} byte(s)"
                f" over {len(left)} row(s) are the oracle framing a window from outside"
                f" with no missing frame of ours under them"
                + ("" if wide - kept else
                   " — the column is now exactly `unframed`'s population and should be"
                   " retired rather than printed as a second word for it")))

    # THE COLUMN NEXT DOOR, checked because the branch that was checked first
    # was wrong and there is no reason to assume the others were ordered more
    # carefully. `unjudged` is tested BEFORE `missing[p]` too - deliberately,
    # and it stays that way - so the overlap is asserted to be REPORTED rather
    # than asserted to be zero.
    gagged, dumb = sum(r.mute for r in rows), sum(r.unjudged for r in rows)
    out.append((dumb == 0 or gagged == sum(min(r.mute, r.unjudged) for r in rows),
                f"the same overlap in `unjudged` is counted rather than discovered:"
                f" {gagged} of {dumb} byte(s) the oracle could not adjudicate also stand"
                f" under a frame we never built"
                + (f" ({gagged / dumb * 100:.1f}%)" if dumb else "")))
    out.append((all(r.mute <= r.unjudged for r in rows),
                "and it is a subset of it on every row, never a second charge for the"
                " same byte"))
    return out


def oops(msg: str) -> int:
    print(f"rack.py: {msg}", file=sys.stderr)
    return 2


def refuse(msg: str) -> int:
    print(f"rack.py: REFUSED — {msg}", file=sys.stderr)
    return 4


def spelled() -> int:
    """What the pricing rule is, and what its digest does and does not read."""
    print(f"\n{priced().line()}\n")
    print(f"{'the rule reads':<20}{'bytes':>8}  what it decides")
    print("-" * 78)
    for name in DECIDES:
        said = inspect.getsource(globals()[name])
        head = (globals()[name].__doc__ or "—").strip().splitlines()[0]
        print(f"{name:<20}{len(said):>8}  {head[:52]}")
    print(f"\n{'it does NOT read':<20}{'':>8}  why")
    print("-" * 78)
    for name, why in (("plumb", "the trees themselves — `stamp` attributes ours,"
                                " `attest` theirs"),
                      ("survey", "the walk that calls the classification, so a new column"
                                 " is not a new rule"),
                      ("standing", "`built`, `damage`, `orphan` — another file's columns,"
                                   " restated not remade")):
        print(f"{name:<20}{'':>8}  {why}")
    print(f"\nprices: {', '.join(PRICES)} — `--price=<name>`. A board says which one it was"
          f"\ntaken under; `rack.py against <board.json>` refuses across two of them at exit 4.")
    return 0


def admit(path: Path) -> tuple[dict, int]:
    """May this kept board be compared with what this file measures?

    Asked BEFORE the sweep. A refusal that costs three minutes of measuring
    first is a refusal nobody runs a second time, and the whole value of the
    thing is that it arrives instead of the thirty phantom rows.

    `attest.py`'s pattern one level down. A held baseline and a fresh sweep are
    two measurements of two different things whenever the rule between them
    moved, and subtracting them produces a table of drifts that are all the
    same drift wearing thirty names.

    A board with no `price` key at all predates the field, which dates it
    exactly: there was one rule then and it was `sheltered`.
    """
    try:
        kept = json.loads(path.read_text())
    except (OSError, ValueError) as bad:
        return {}, oops(f"cannot read the kept board at {path}: {bad}")
    old = kept.get("price") or {"name": SHELTERED, "rule": ""}
    now = priced()
    if not [r for r in kept.get("row", ()) if "name" in r]:
        return {}, oops(f"{path} carries no rows;"
                        f" `rack.py run --json > {path.name}` writes one")
    if old["name"] != now.name:
        return {}, refuse(
            f"that board was priced `{old['name']}` and this run is `{now.name}`."
            f" The same byte under a frame we never built is a charge under one and"
            f" silence under the other, so every row would differ and none of the"
            f" differences would be the binary.\n"
            f"  re-derive it: python3 tool/rack.py run --price={old['name']} --json")
    if old.get("rule") and old["rule"] != now.rule:
        return {}, refuse(
            f"same price `{now.name}`, different rule: the board was taken under"
            f" {old['rule'][:12]} and this file spells it {now.rule[:12]}. The code that"
            f" decides which bucket a byte lands in moved between them; `rack.py rule`"
            f" says what that digest reads.\n"
            f"  re-derive the baseline under this file rather than subtracting the two.")
    if not old.get("rule"):
        print(f"note: {path.name} predates the price field, so it was taken under"
              f" `{SHELTERED}` by construction — there was one rule then.", file=sys.stderr)
    return kept, 0


def against(kept: dict, rows: list[Seen], mark: stamp.Stamp) -> int:
    """A kept board `admit` has cleared, re-swept and diffed row by row."""
    now = priced()
    was = {r["name"]: r for r in kept.get("row", ()) if "name" in r}
    seen = [r for r in rows if r.name in was]
    # Named, never defaulted. A column the kept board does not carry is not a
    # zero, and `- o.get(k, 0)` printed nine phantom `blind` moves the first
    # time this ran - against a board whose every column was in fact identical.
    # That is the absence-as-a-zero this repository has been caught on twice
    # already, reproduced inside the tool written to stop it.
    cols = ("square", "crooked", "unframed", "blind")
    print(f"\n{len(seen)} row(s) held by both boards, priced `{now.name}`\n")
    print(f"{'grammar':<19}" + "".join(f"{c:>9}{'Δ':>8}" for c in cols))
    print("-" * 96)
    moved, dumb = 0, {c: 0 for c in cols}
    for r in sorted(seen, key=lambda r: -abs(r.square - was[r.name].get("square", r.square))):
        o, cells = was[r.name], ""
        for c in cols:
            mine = getattr(r, c)
            gap = None if c not in o else mine - o[c]
            dumb[c] += gap is None
            moved += gap not in (None, 0)
            cells += f"{mine:>9}" + (f"{gap:>+8}" if gap is not None else f"{'—':>8}")
        print(f"{r.name:<19}{cells}")
    if blank := [c for c in cols if dumb[c]]:
        print(f"\nthe kept board does not carry {', '.join(blank)} on"
              f" {max(dumb.values())} of its row(s) — printed `—` rather than compared"
              f" against a zero it never claimed.")
    gone = sorted(set(was) - {r.name for r in seen})
    if gone:
        print(f"\n{len(gone)} row(s) the kept board has and this sweep did not measure:"
              f" {', '.join(gone)}")
    print(f"\n{moved} cell(s) moved over {len(seen)} row(s).")
    print(told())
    print(now.line())
    print(mark.line())
    return 0


def soft(cases: list[plumb.Case]) -> int:
    """How much of `crooked` is EXTRAS PLACEMENT rather than derivation.

    The number this file prints is opinionated by construction, and this is the
    part of it I would not defend. An `extra` - a comment, a blank line - may
    attach at any point the grammar allows, and where a parser hangs one is an
    internal choice rather than a claim about structure. tree-sitter swallows a
    leading scaladoc into the `function_definition` it precedes; joints keeps
    it a sibling. Neither has misread a byte, and my walk charges every byte of
    the comment to whichever spine it isn't on.

    So it is separated and named rather than argued about, because a number
    that cannot say which part of itself is soft is a number that will be
    quoted whole. Run it before quoting anything this file prints.

    **The third column is a second over-claim, found by another lane.** A run
    can part at a rung where both sides name the same construct, starting at
    the same byte, and disagree only about where it STOPS. Nobody disputes a
    parent there. `toml`'s entire row is that shape - both parsers hang the
    `comment` under the same `pair`, and joints's `pair` merely ends early -
    and this file scored it as a derivation tree-sitter does not build. It is
    62% of toml, 96% of latex and 80% of zig. A moved edge is a real defect and
    somebody else's to price; it is not "built in a shape tree-sitter does not
    build", which is the sentence these bytes were feeding.
    """
    tot = dict.fromkeys(("crooked", "blank", "extra", "edge", "unframed", "hollow"), 0)
    rows, holes = [], []
    for c in cases:
        saw = plumb.read(c)
        if saw.why or not saw.built:
            continue
        try:
            book = json.loads(c.grammar.read_text())
        except (OSError, ValueError) as bad:
            print(f"{c.name}: cannot read the grammar to find its extras: {bad}", file=sys.stderr)
            continue
        xs = {e["name"] for e in book.get("extras", ()) if e.get("type") == "SYMBOL"}
        # `top` is set past any plausible run count: this asks about ALL of the
        # crooked bytes, and a truncated list would understate the soft share,
        # which is the direction that flatters the instrument.
        r = survey(c.name, saw, top=1 << 20)
        # Each byte is attributed once, in this order, so the three columns
        # sum to `soft` rather than overlapping: whitespace first, then an
        # extra hanging in two places, then a parent whose edge moved. Without
        # the precedence a blank line inside a moved `pair` is subtracted twice
        # and HARD goes negative on toml.
        blank = loose = slid = hollow = 0
        for w in r.worst:
            text = saw.blob[w.start:w.end]
            if w.kind == "unframed":
                # A missing frame is charged over the construct's whole extent,
                # so its own soft share is the whitespace inside it - asked
                # here rather than in a side script, because the walk is the
                # only thing that knows which bytes it actually charged.
                hollow += w.width if not text.strip() else 0
            elif not text.strip():
                blank += w.width
            elif w.ours in xs or w.theirs in xs:
                loose += w.width
            elif w.edge:
                slid += w.width
        rows.append((c.name, r.crooked, blank, loose, slid, sorted(xs)))
        if r.unframed:
            holes.append((c.name, r.unframed, hollow))
        for k, v in (("crooked", r.crooked), ("blank", blank), ("extra", loose),
                     ("edge", slid), ("unframed", r.unframed), ("hollow", hollow)):
            tot[k] += v
    if not tot["crooked"]:
        return oops("nothing crooked to attribute; the sweep judged no disagreement at all")
    print("\nHOW MUCH OF `crooked` IS NOT A DERIVATION EITHER PARSER DISPUTES")
    print("A comment attaches where a parser chooses, and a parent both sides agree on can end")
    print("in the wrong place without anybody disputing the parent. Subtract all three before")
    print("quoting the headline.\n")
    print(f"{'grammar':<20}{'crooked':>9}{'blank':>8}{'extra':>8}{'edge':>8}{'soft':>8}"
          f"{'HARD':>9}   the grammar's extras")
    print("-" * 116)
    for name, ck, bl, ex, sl, xs in sorted(rows, key=lambda r: -(r[2] + r[3] + r[4])):
        if ck:
            print(f"{name:<20}{ck:>9}{bl:>8}{ex:>8}{sl:>8}{(bl + ex + sl) / ck:>7.1%}"
                  f"{ck - bl - ex - sl:>9}   {', '.join(xs) or '—'}")
    gone = tot["blank"] + tot["extra"] + tot["edge"]
    hard = tot["crooked"] - gone
    print(f"\n{'TOTAL':<20}{tot['crooked']:>9}{tot['blank']:>8}{tot['extra']:>8}"
          f"{tot['edge']:>8}{gone / tot['crooked']:>7.1%}{hard:>9}")
    print(f"\n  {tot['blank'] + tot['extra']} of {tot['crooked']} crooked bytes are an extra"
          f" hanging in two places, or whitespace\n  between two tokens. A further"
          f" {tot['edge']} are a parent BOTH SIDES AGREE ON whose right\n  edge moved, which is"
          f" a defect and is not the one this column's headline names.")
    print(f"  {hard} bytes are a derivation the two parsers genuinely disagree about,"
          f" and that\n  is the number I would defend.")
    if tot["unframed"]:
        worst = max(holes, key=lambda h: h[2] / h[1])
        print(f"\n  `unframed` is a separate column and gets the same treatment:"
              f" {tot['unframed']} bytes,\n  of which {tot['hollow']}"
              f" ({tot['hollow'] / tot['unframed']:.1%}) are whitespace inside the construct we"
              f"\n  never built - softest at {worst[0]} ({worst[2]}/{worst[1]}"
              f" = {worst[2] / worst[1]:.1%}). The frame is\n  missing either way; the share"
              f" says how much of the charge is the gap between\n  its children rather than"
              f" the children themselves.")
    print(told())
    print(priced().line())
    return 0


def main(argv: list[str]) -> int:
    global PRICE
    as_json = "--json" in argv
    bare = [a for a in argv if not a.startswith("-")]
    verb, want = (bare[0] if bare else ""), set(bare[1:])
    want |= {a.split("=", 1)[1] for a in argv if a.startswith("--grammar=")}
    pin = next((a.split("=", 1)[1] for a in argv if a.startswith("--oracle=")), "")
    PRICE = next((a.split("=", 1)[1] for a in argv if a.startswith("--price=")), PRICE)
    if PRICE not in PRICES:
        return oops(f"no such price {PRICE!r}; there are {' and '.join(PRICES)}")
    if "-h" in argv or "--help" in argv or not verb:
        print(__doc__)
        return 0 if verb or "-h" in argv or "--help" in argv else 2
    if verb == "rule":
        return spelled()
    if verb not in ("run", "whole", "board", "show", "soft", "guard", "verify",
                    "against", "reprice"):
        return oops(f"no such verb {verb!r}; try run, whole, board, show, soft, guard,"
                    f" verify, rule, reprice, against")
    if not plumb.BIN.exists():
        return oops(f"no binary at {plumb.BIN}; run `zig build` first")
    kept: dict = {}
    if verb == "against":
        if len(bare) < 2:
            return oops("against needs a board: `rack.py run --json > before.json`")
        kept, bad = admit(Path(bare[1]))
        if bad:
            return bad
        want = set()
    known = {c.name for c in plumb.slate()}
    if stray := sorted(want - known):
        return oops(f"no grammar named {', '.join(stray)}; there are {len(known)}")
    if not d.oracle_ready():
        print(f"rack.py: no tree-sitter CLI at {d.TS}; there is nothing to compare against",
              file=sys.stderr)
        return 2
    if verb == "verify":
        return verify()
    try:
        picked = consult([c for c in plumb.slate() if not want or c.name in want], pin)
    except ValueError as bad:
        return oops(str(bad))
    if verb == "show":
        return show(picked)
    if verb == "soft":
        return soft(picked)
    mark = stamp.take(plumb.BIN)
    if verb == "reprice":
        return reprice(twice(picked), as_json, mark)
    if verb == "whole":
        return whole(as_json, mark, pin)
    if verb == "guard":
        return guard(picked, as_json)
    rows = sweep(picked)
    if not rows:
        return oops("no grammar resolved to a folio and a source")
    if verb == "against":
        return against(kept, rows, mark)
    return board(rows, as_json) if verb == "board" else run(rows, as_json, mark)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

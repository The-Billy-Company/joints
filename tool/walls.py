#!/usr/bin/env python3
"""How many walls deep is the tail, and where does the parse actually stop?

The census reports each grammar's **first** wall and nothing after it. Fourteen
grammars mend past that wall and stop somewhere it never names, and some of them
mend in the thousands doing it - haskell 4,940, julia 4,749, verilog 1,652 -
which is repair rather than parsing. So the size of the remaining work is not
known: nobody can say whether those fourteen are one bug deep or two hundred,
and that unmeasured depth is the whole difference between a bounded tail and a
second project.

This turns it into a number, in three parts:

  **Where it really stops.** `furthest(tree)` over the forest, not the byte in
  the verdict. A mended verdict names where trouble *began*, so reading it as
  reach reports the parses that read the most as the ones that read least - the
  defect `stamp.outcome` was consolidated to kill. Reported as bytes and as a
  share of the file.

  **How many walls it crossed.** The parse is peeled: parse, take the wall it
  names, resume from just past it, repeat. Each round yields one wall, and the
  rounds stop when the remainder reads whole, when nothing advances, or at
  `--depth`.

  **How many of them are the same wall.** A grammar that hits
  `unexpected : in state 880` four thousand times has one defect with a loud
  voice; a grammar that hits four hundred distinct (terminal, state) pairs has
  four hundred. `distinct` against `crossed` is the bounded-tail-versus-second-
  project ratio, per grammar.

  **And what each of them is worth.** Recurrence is not cost and this file spent
  a while implying it was. On `picorv32.v` the verilog lane measured the
  disagreement twice: by statements stopped `` ` `` in 1108 leads with nine, by
  bytes a different state leads with one statement and 16,289 - and state 2394,
  which takes seven of nine warm-only walls *here*, is worth **-167 bytes**.
  So every wall is priced: the cold peel's rounds tile the file, so wall *i* owns
  `[A_i, A_i+1)` and `prefix + priced + unpeeled == size` to the byte on every
  grammar, printed every run. The warm peel cannot partition anything - it parses
  the whole file each round - so it prices by **reach delta**, which is allowed to
  be negative and frequently is. `voice` stays a column because warm behaviour is
  real information; it stopped being the ranking, and both peels now print which
  wall a count ordering *would* have led with.

**What the cold peel is, and is not.** Resuming means parsing the remaining
bytes from a clean start, so each round begins in state 0 rather than in
whatever state the product loop had actually accumulated. So a peeled wall is a
wall this grammar hits reading that text cold - real, reproducible, and not
necessarily the identical wall the mending loop met at that byte. It is an
enumeration of the tail's *distinct difficulties*, which is the question. Every
row says how it was obtained.

**And after round 1 the text is not the document, which the row now says too.**
A suffix of a program is not a program: its openers were left behind, so its
closers are refused correctly and the peel prices the refusal. That cost 13,056
bytes of swift, sold as construct damage, until `../research/joinery/strand/`
took the population apart. The excluded set was `in state 0` walls, and a state
number cannot carry the distinction - the same orphan `}` reproduces at states 0,
681 and 1166 and the number is only a count of the statements in front of it. So
the discriminator is the **round**, carried on `Cold.turns` and surfaced as
`Priced.torn`: round 1 read the file, everything after it read a fragment. That
is a fact about the run rather than an inference from a wall, it costs nothing,
and it cannot be fooled by a statement.

`torn` is a *provenance*, not a dismissal. A fragment wall the parser really does
meet on the document is witnessed by `warm`, which never restarts; the join lives
in `research/joinery/owners/cut.py` and is three-valued, because a bounded warm
run that never reached the byte is silent about it rather than acquitting it.

**Which biases the count in one direction, and `warm` measures how far.** A wall
that only exists in accumulated context - a state the table can only be in after
four thousand lines - is unreachable from a clean start, so the cold peel cannot
find it and the count is a **floor** on wall variety. `python3 tool/walls.py
warm --grammar haskell` bounds that: it parses the **whole file from byte 0**
every round and blanks the offending byte with a space, so the prefix stays real
and the accumulated state is the one the parser would actually have. Then it
diffs the two sets and reports the walls only the warm peel could reach, the
round each new one first appeared at, and whether they are still arriving at the
end of the run. Saturating early makes the floor a ceiling in practice;
arriving at a steady rate makes it the first layer of an onion, and the rate is
the number that tells those apart.

Exit 0 measured, 2 could not.
"""

from __future__ import annotations

import argparse
import collections
import json
import re
import sys
from pathlib import Path
from typing import NamedTuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
from breadth import DEST, SOURCES  # noqa: E402
from order import BIN, GRAMMARS, ROOT, folio_for  # noqa: E402
from rung1 import pairs  # noqa: E402
from stamp import ask, furthest, take  # noqa: E402

CORPUS = ROOT / "research" / "joinery" / "corpus"
DEPTH = 400  # rounds of peeling before a row is reported as unfinished
BUDGET = 40  # `gate` rounds per grammar per peel - fixed so the check is reproducible
# The two-path parity check gets its own, smaller budget. It asks a yes/no
# question about whether pressing loses meaning, and nine grammars disagreeing
# nowhere in ten rounds is already a strong witness - where the family check is
# a survey and wants depth. It is also the expensive half: the grammar path pays
# an import per round, which on scala and kotlin dwarfs the parse.
PARITY = 10
# The gate asks whether anything new in KIND turns up, so it wants one witness
# per family at a budget CI can afford - the widest tails, the two that peel
# lexically, the two that are nearly all brackets. That is a different question
# from "which grammars are held out" and cannot be derived from it.
# sole: a chosen subset of the roster, not a second roster - `roster()` stays the
# only place a grammar is declared to exist, and `gate` refuses to run if a name
# here has drifted out of it, so this can go stale in exactly one visible way.
GATE = ("kotlin", "julia", "scala", "sql", "verilog", "ocaml", "go", "zig", "markdown")


class Priced(NamedTuple):
    """One distinct wall, how often the peel met it, and what it cost.

    `hits` is recurrence and `cost` is bytes, and the two are **not** a proxy for
    each other. On `picorv32.v` the verilog lane measured the disagreement twice:
    `` ` `` in 1108 leads by statements stopped with nine, while a different state
    leads by bytes with one statement and 16,289 - and state 2394, which takes
    seven of nine warm-only walls, costs **-167 bytes** and lands twelfth of
    thirteen. So recurrence stays a column and stops being the ranking.

    `turn` and `first` are the wall's **provenance**: the earliest round that met
    it and the earliest byte it stands at. They are here because nothing
    downstream can recover either, and because `turn` is the only thing in the
    row that says whether the text this wall was refused in was the document.
    """

    kind: str
    who: str
    hits: int
    cost: int  # bytes of file this wall stands in front of
    turn: int = 1  # earliest round that met it - round 1 read the whole file
    first: int = 0  # earliest absolute byte it stands at
    roofed: bool = False  # round 1 built a node over `first` - see `Cold.covered`

    @property
    def wall(self) -> tuple[str, str]:
        return (self.kind, self.who)

    @property
    def term(self) -> str:
        """Just the terminal, with the state dropped.

        The state is what a *fragment* reached, so it is the one part of the
        phrase that cannot be compared between two peels. Anything joining the
        cold peel to a whole-file parse has to join on this and on `first`."""
        return self.who.split(" in state ")[0]

    @property
    def torn(self) -> bool:
        """Was this wall refused in a **fragment** rather than in the document?

        Round 1 parses the file. Every round after it parses `text[cut:]` - a
        suffix whose openers the peel left behind - so a wall met only there is a
        statement about text nobody wrote. The state number cannot say which:
        `../../joinery/strand/witness/sw-cut-*.swift` reproduces the same orphan
        `}` at states 0, 681 and 1166, and the number is a count of how many
        statements happened to precede it. The **round** can say, exactly, and
        for free - so it does.

        `torn` is not a verdict of worthlessness. It is a verdict that this row
        has not been witnessed on the document yet. `roofed` is what convicts one
        outright and `warm` is what witnesses one: see `Cold.covered` and
        `Warm.frontier`. Many-valued, because a bounded warm run that never
        reached the byte is silent about it rather than acquitting it."""
        return self.turn > 1


def price(marks: list[int], seen: list[tuple[str, str]], turns: list[int],
          size: int, closed: bool, roof=None) -> tuple[list[Priced], int, int]:
    """What each wall costs in bytes, as a **partition** of the file.

    Wall *i* stands at absolute byte `A_i` and owns `[A_i, A_i+1)` - the stretch
    from itself to wherever the next wall takes over. That is what stepping past
    it buys, which is the only sense in which a wall has a price, and it makes
    the arithmetic auditable in a way a per-round measurement is not:

        prefix + sum(every wall's cost) + unpeeled == size

    to the byte, on every grammar, printed rather than asserted. A cold peel
    re-parses on every round, so anything summing per-round reach or per-round
    remainder double-counts, and a byte number that can double-count is the same
    class of number as the recurrence count it is replacing.

    `unpeeled` is the honest hole. When the peel stops at the depth ceiling
    nobody knows where the *next* wall is, so the last wall gets the one byte the
    resume stepped over and the unexplored tail is reported as itself instead of
    being credited to whichever wall happened to be last.

    `roof` is `Cold.covered`, asked of each wall's earliest byte. It is passed in
    rather than looked up because pricing is the only place that knows which byte
    is a row's *earliest*, and the earliest is the one the question is about.
    """
    if not marks:
        return [], size, 0
    edge = marks[-1] + 1  # where the peel resumed from after the last wall
    ends = marks[1:] + [size if closed else edge]
    total: dict[tuple[str, str], list[int]] = {}
    for (kind, who), start, end, turn in zip(seen, marks, ends, turns, strict=True):
        # The **earliest** round and the **earliest** byte, not the last: a wall
        # first met on the document and met again in a fragment is a wall on the
        # document, and taking a max here would launder the provenance of exactly
        # the rows that matter.
        row = total.setdefault((kind, who), [0, 0, turn, start])
        row[0] += 1
        row[1] += max(end - start, 0)
        row[2], row[3] = min(row[2], turn), min(row[3], start)
    out = [Priced(k, w, *rest, bool(roof and roof(rest[3])))
           for (k, w), rest in total.items()]
    return (sorted(out, key=lambda p: (-p.cost, -p.hits, p.who)), marks[0],
            0 if closed else max(size - edge, 0))


class Depth(NamedTuple):
    name: str
    source: str
    size: int
    kind: str
    first: tuple[str, int] | None  # the wall the census reports, and only that
    reach: int  # where the forest says it actually stopped
    roots: int
    mends: int
    crossed: int  # walls the peel met
    distinct: list[tuple[str, str]]  # ...and how many of them were different
    closed: bool  # the peel reached the end of the file
    why: str = ""
    priced: list[Priced] = []  # the same walls, ranked by what they cost
    prefix: int = 0  # bytes before the first wall, which no wall owns
    unpeeled: int = 0  # bytes past where peeling stopped, which nobody priced

    @property
    def covered(self) -> float:
        return 100.0 * self.reach / self.size if self.size else 0.0

    @property
    def behind(self) -> int:
        """Bytes the peel puts behind a wall. **Not** `damage` - that is
        `tool/standing.py`'s word and is `size - built`. This is the file lying
        past the first wall and inside the stretch the peel actually walked."""
        return sum(p.cost for p in self.priced)

    @property
    def balances(self) -> bool:
        """The partition identity, per grammar. False is a refusal to print a
        price, not a footnote."""
        return self.prefix + self.behind + self.unpeeled == self.size

    @property
    def loudest(self) -> Priced | None:
        """The wall a recurrence ordering would have led with."""
        return max(self.priced, key=lambda p: (p.hits, p.cost), default=None)

    @property
    def dearest(self) -> Priced | None:
        return self.priced[0] if self.priced else None

    @property
    def torn(self) -> int:
        """Of `behind`, the bytes standing behind a wall the peel met only in a
        **fragment** - see `Priced.torn`.

        This column used to be `state0` and counted `in state 0` walls only. That
        caught the fragment that refuses its own first token and missed the same
        fragment with one statement in front of it, which is how 13,056 bytes of
        swift came to be sold as construct damage. Printed rather than netted
        out: it is the peel's own reach that is in question, and a column a
        reader can subtract is honest where a corrected total nobody can check
        is not."""
        return sum(p.cost for p in self.priced if p.torn)

    @property
    def standing(self) -> Priced | None:
        """The dearest wall the peel met while reading the whole document."""
        return next((p for p in self.priced if not p.torn), None)

    @property
    def disagrees(self) -> bool:
        """Do the two orderings name different walls at the top? This is the
        whole reason the ranking changed, so it is a property and not a remark."""
        a, b = self.dearest, self.loudest
        return a is not None and b is not None and a.wall != b.wall

    @property
    def voice(self) -> float:
        """Mends per distinct wall - how loudly one problem shouts.

        This is the bounded-tail-against-second-project number. haskell mending
        4,940 times behind a single distinct wall is one defect with a very loud
        voice; the same 4,940 spread over four hundred distinct walls would be a
        second project. The census reports the mend count and stops, which is
        exactly the half that cannot tell those apart.

        **It is not a cost and must not be ranked by.** Mends per wall is a rate
        over an unpriced denominator: the state that recurs most on `picorv32.v`
        is very nearly the one that costs least. Read it as warm behaviour, take
        the ordering from `priced`."""
        return self.mends / len(self.distinct) if self.distinct else 0.0


class Cold(NamedTuple):
    """What one cold peel met, where, and **in which round**.

    The three lists are parallel and `price` zips them strictly, which is how a
    round that recognises a wall and then fails the byte guard shows up as a
    length mismatch instead of as a quietly shifted price.

    `turns` is the addition that stops the peel manufacturing walls. Round 1
    parses the file; round *i* parses a suffix. Nothing downstream can tell those
    apart from a wall's name, its state, or its terminal - and three lanes tried
    - so the round rides along beside the offset it was always coming with."""

    seen: list[tuple[str, str]]
    marks: list[int]
    turns: list[int]
    closed: bool
    why: str
    canopy: list[tuple[int, int]] = []  # spans round 1 built a node over

    @property
    def walls(self) -> set[tuple[str, str]]:
        return set(self.seen)

    @property
    def under(self) -> int:
        """Bytes round 1 demonstrably built something over.

        Not a reach: a mended forest has holes where the parse put its stack
        down, and the holes are the point."""
        return sum(b - a for a, b in merge(self.canopy))

    def covered(self, byte: int) -> bool:
        """Did round 1 - reading the file as written - build a node over this byte?

        **This is the falsifier that is a presence rather than an absence**, and
        it is why it belongs here rather than in the warm peel. `Warm` answers "is
        this cold wall real" with *I never met it*, and that answer gets stronger
        the weaker the run is: a budget that stalls at byte 2,904 of 28,467
        acquits everything past it for free. A node covering the byte is the
        opposite shape. Round 1 read the file nobody cut and consumed a token
        there, so it did not refuse there, so a later round refusing there is
        refusing in text this peel made. A shorter run cannot manufacture that
        evidence; it can only fail to find it.

        One parse per grammar, no blanking, no budget, and no cascade - see
        `Warm.paid` for the cascade this avoids by never modifying the file."""
        return any(a <= byte < b for a, b in self.canopy)


def merge(spans: list[tuple[int, int]]) -> list[tuple[int, int]]:
    """Overlapping spans as disjoint ones. A forest nests, so summing widths
    without this counts every interior byte once per level of depth."""
    out: list[tuple[int, int]] = []
    for a, b in sorted(spans):
        if out and a <= out[-1][1]:
            out[-1] = (out[-1][0], max(out[-1][1], b))
        else:
            out.append((a, b))
    return out


SPANS = re.compile(r"\[(\d+), (\d+)\)")


def peel(folio: Path, text: bytes, work: Path, ext: str, depth: int) -> Cold:
    """Walk the tail one wall at a time, and say what it met **and where**.

    Each round writes the remaining bytes and parses them, takes the wall the
    verdict names, steps past it, and goes again. Two kinds of wall come back,
    and keeping them apart is most of the value here because they have different
    owners:

      **state** - `unexpected <terminal> in state <n>`. The table refused a
      token it was handed. Named by terminal and state.
      **lexical** - `stray byte at <n>`. Nothing could tokenize there at all,
      which on a grammar with unrunnable external scanners is usually theirs
      rather than the table's. Named by the byte itself, so fifty stray bytes
      that are all one UTF-8 lead byte read as one wall and not fifty.

    Guards are reported rather than silently ended on: a round that does not
    advance, a parse that times out, and the depth ceiling.

    **The absolute offset of every wall comes back beside it**, because that is
    what a price is made of and nothing downstream can recover it: round *i*
    parses `text[cut:]`, so the wall's own `at` is relative to a cut only this
    loop knows. `price()` turns the offsets into a partition of the file.
    """
    seen: list[tuple[str, str]] = []
    marks: list[int] = []
    turns: list[int] = []
    canopy: list[tuple[int, int]] = []
    cut, scratch = 0, work / f"tail.{ext}"
    for turn in range(1, depth + 1):
        if cut >= len(text):
            return Cold(seen, marks, turns, True, "", canopy)
        scratch.write_bytes(text[cut:])
        out = ask(BIN, folio, scratch, tree=True)
        if turn == 1 and out.tree:
            # Round 1 and only round 1: these spans are offsets into the file as
            # written, and every later round's are offsets into a suffix this loop
            # cut. Rebasing them by `cut` would be arithmetic over a document
            # nobody wrote. See `Cold.covered`.
            canopy = [(int(a), int(b)) for a, b in SPANS.findall(out.tree)]
        if out.kind == "whole":
            return Cold(seen, marks, turns, True, "", canopy)
        if out.kind == "timeout":
            return Cold(seen, marks, turns, False,
                        f"a tail parse timed out after {len(seen)} walls", canopy)
        # `at`, never `reach`. A mended verdict reaches the end of the file
        # while naming a wall in the first kilobyte, so stepping past `reach`
        # steps past everything and every grammar reports exactly one wall. It
        # did, and the count that came out of it was retracted.
        here = out.at
        if (wall := out.wall) is not None:
            what = ("state", f"{wall[0]} in state {wall[1]}")
        elif (spot := out.stray) is not None:
            here = spot
            what = ("lexical", f"stray {text[cut + spot:cut + spot + 1]!r}"
                               if cut + spot < len(text) else "stray byte")
        else:
            # Closed no root over every byte, or refused outright. Real, and not
            # a wall stepping past one byte can clear.
            return Cold(seen, marks, turns, False,
                        f"{out.kind} at {cut + max(out.reach, 0)}, which no step gets past", canopy)
        if here is None:
            return Cold(seen, marks, turns, False, f"{out.kind} naming no byte at {cut}", canopy)
        # All three lists, in one place. Appending the wall where it is recognised
        # and its offset after the byte guard is how they come back different
        # lengths, and `price` zips them strictly for exactly that reason.
        seen.append(what)
        marks.append(cut + here)
        turns.append(turn)
        cut += here + 1
    return Cold(seen, marks, turns, False, f"still walled after {depth} rounds", canopy)


class Warm(NamedTuple):
    """One grammar peeled from a warm resume, and how the two peels differ."""

    name: str
    rounds: int
    cold: list[tuple[str, str]]
    walls: list[tuple[str, str]]
    arrived: list[int]  # the round each distinct wall was first seen at
    why: str
    costs: list[Priced] = []  # what blanking each wall was worth, in reach
    unpriced: int = 0  # rounds whose delta nobody can know - see `warm`
    frontier: int = 0  # the furthest byte any round of this run demonstrably read
    spots: list[tuple[str, int]] = []  # (terminal, absolute byte) per round blanked
    bought: list[bool] = []  # did the blank at `spots[i]` buy the parse anything

    @property
    def barren(self) -> int:
        """Rounds whose blank bought the parse nothing - see `bought`."""
        return sum(1 for b in self.bought if not b)

    @property
    def paid(self) -> set[tuple[str, int]]:
        """The subset of `seat` a **purchase** stands behind.

        Blanking is not a neutral act:
        `../../joinery/reprice/PREDICTION-2-alias.md`
        measures one file three times and finds that blanking swift's `)` at 1492
        makes the `}` at 1498 a wall **in the same state, with the same 308 roots
        and the same reach** - and that the `}` is not a wall in the file as
        written at all. The blank bought nothing and the refusal was re-reported
        against the next token.

        So the run's own tree output is the falsifier, asked of each wall's own
        blank: **remove this wall and does the parse build anything it could not
        build before?** A blank that closes no new root and reads no further did
        not clear a trouble, so the thing it removed was not obstructing one.

        This is deliberately not a state-number rule. The state was *identical*
        across the swift cascade, which is exactly why no predicate over state
        numbers could have separated these two cases.

        The last round has no parse after it, so its blank has no answer and is
        left out - the same distinction `deltas` draws with `unpriced`, and in the
        same direction: an unknown is not a purchase."""
        return {s for s, ok in zip(self.spots, self.bought, strict=False) if ok}

    @property
    def seat(self) -> set[tuple[str, int]]:
        """Every (terminal, byte) this run refused, which is the **only** join key
        a whole-file parse and a cold peel can both satisfy.

        A wall's phrase carries the state it was refused in, and a fragment's
        state number is a count of the statements that preceded it - so joining on
        the phrase can only ever match rounds where the two peels read the same
        text, which is round 1. `../../joinery/reprice/RESULT-1-provenance.md`
        measures how much of a published 96.3% was that join rather than this
        peel. Blanking keeps offsets stable across rounds for exactly this
        reason, so the byte is comparable where the state is not."""
        return set(self.spots)

    @property
    def only(self) -> list[tuple[str, str]]:
        """Walls the warm peel reached and the cold peel could not - the whole
        question. A cold peel restarts in state 0, so a wall that exists only
        after four thousand lines of accumulated context is invisible to it."""
        return sorted(set(self.walls) - set(self.cold))

    @property
    def quiet(self) -> int:
        """Rounds since the last new distinct wall. Large means saturated."""
        return self.rounds - (self.arrived[-1] if self.arrived else 0)

    @property
    def rate(self) -> float:
        """New distinct walls per hundred rounds over the back half of the run -
        the half that matters, since the front half finds the easy ones no
        matter which world we are in."""
        half = self.rounds / 2
        late = sum(1 for a in self.arrived if a > half)
        return 100.0 * late / half if half else 0.0


def deltas(met: list[tuple[str, str]], reach: list[int]) -> tuple[list[Priced], int]:
    """Each warm wall's reach delta, summed over the rounds that blanked it.

    `reach` is one longer than the priced rounds whenever the run ended on a
    parse, and exactly as long when it ended without one - so the pairing is
    `zip` over the shorter, and the rounds left over are returned rather than
    given a delta of zero. A zero and an unknown are not the same number, and
    this instrument has been bitten by exactly that substitution before."""
    total: dict[tuple[str, str], list[int]] = {}
    priced = min(len(met), max(len(reach) - 1, 0))
    for what, before, after in zip(met[:priced], reach[:priced], reach[1:priced + 1], strict=True):
        row = total.setdefault(what, [0, 0])
        row[0] += 1
        row[1] += after - before
    out = [Priced(k, w, hits, cost) for (k, w), (hits, cost) in total.items()]
    return sorted(out, key=lambda p: (-p.cost, -p.hits, p.who)), len(met) - priced


def warm(folio: Path, text: bytes, work: Path, ext: str, depth: int) -> Warm:
    """Peel without ever restarting: parse the whole file, blank the byte the
    wall names, parse the whole file again.

    The prefix stays real, so the state the table is in when it meets round N's
    wall is the state it would actually have been in - which is precisely what
    the cold peel throws away. Blanking rather than deleting keeps every offset
    stable across rounds, so `at 3057` means the same place in round 1 and round
    300 and a repeat is recognisable as a repeat.

    A wall whose terminal is longer than a byte survives one blank, so the
    blanking widens on the spot until the wall moves; refusing to widen forever
    is the guard, and it is reported rather than treated as saturation.

    **The warm price is a reach delta, and it is allowed to be negative.** A cold
    peel can partition the file because its rounds tile it; a warm peel parses
    the whole file every round, so there is nothing to partition. What there is
    instead is the question the verilog lane's `lvalue.py` asked: blank this
    wall, and does the parse get further? State 2394 answered **-167 bytes** - a
    perfect diagnosis worth less than nothing, because the construct it stood in
    front of was partly parsing and blanking took that away too. A wall's delta
    is `reach` after the blank minus `reach` before it, and the final round has
    no after, so it is counted in `unpriced` rather than given a zero."""
    scratch = work / f"warm.{ext}"
    body = bytearray(text)
    seen: list[tuple[str, str]] = []
    arrived: list[int] = []
    met: list[tuple[str, str]] = []  # the wall each round blanked, in order
    spots: list[tuple[str, int]] = []  # ...and the terminal and byte it stood at
    reach: list[int] = []
    roots: list[int] = []  # ...and how many roots that round closed
    last, wide = -1, 0

    def far(out) -> int:
        return furthest(out.tree) if out.tree else max(out.reach, 0)

    def done(turn: int, why: str, whole: bool = False) -> Warm:
        costs, spare = deltas(met, reach)
        # Did each round's blank buy the parse anything? A purchase is a root the
        # parse could not close before or a byte it could not reach before, and
        # either alone is enough - a blank that unlocks structure without moving
        # the frontier is still a repair. Both numbers come off the same round's
        # parse, so this costs no extra run. See `Warm.paid` for why it is the
        # only thing standing between a witness and a cascade.
        bought = [reach[i + 1] > reach[i] or roots[i + 1] > roots[i]
                  for i in range(min(len(reach), len(roots)) - 1)]
        # **The frontier is what bounds this peel's own absence**, and it is the
        # last byte the run *complained about*, not the furthest byte it read.
        # A verdict names where trouble began, so this peel marches left to right
        # through a file's troubles and blanks them in order. When the budget runs
        # out at byte B, every trouble past B was never surfaced - not because
        # there is none, but because the run was still working on earlier ones. A
        # cold wall out there is `untested`, and calling it an artifact reads a
        # budget as evidence, which is how an absence gets stronger the weaker the
        # run is.
        #
        # Reach is the wrong number for this and was the first thing tried: a
        # mended parse reaches end-of-file while naming a wall in the first
        # kilobyte, so `max(reach)` said "I looked everywhere" on every mending
        # grammar and the `untested` bucket came out empty on all thirty.
        #
        # A run that ends having cleared the file, or complaining at its last
        # byte, really has surfaced everything, and says so.
        edge = len(body) if whole else max([at for _, at in spots] or [0])
        return Warm("", turn, [], seen, arrived, why, costs, spare, edge, spots, bought)

    for turn in range(1, depth + 1):
        scratch.write_bytes(body)
        out = ask(BIN, folio, scratch, tree=True)
        if out.kind == "whole":
            reach.append(len(body))
            roots.append(out.roots)
            return done(turn, "reads whole", whole=True)
        if out.kind == "timeout":
            return done(turn, f"timed out at round {turn}")
        at = out.at  # the byte the verdict names, never `reach` - see `peel`
        if at is None:
            return done(turn, f"{out.kind}, which names no byte")
        if (wall := out.wall) is not None:
            what = ("state", f"{wall[0]} in state {wall[1]}")
        elif out.stray is not None:
            what = ("lexical", f"stray {bytes(body[at:at + 1])!r}" if at < len(body) else "stray byte")
        else:
            return done(turn, f"{out.kind}, which blanking cannot clear")
        reach.append(far(out))
        roots.append(out.roots)
        met.append(what)
        spots.append((what[1].split(" in state ")[0], at))
        if what not in seen:
            seen.append(what)
            arrived.append(turn)
        # Widen only while stuck in one place; any move resets it, so a long
        # terminal costs a few rounds rather than poisoning the rest of the run.
        wide = wide + 1 if at == last else 0
        last = at
        if at >= len(body) - 1:
            # The complaint is at the last byte, so every byte before it was
            # read: this is the parse running out of file, not a wall standing
            # in front of one. Blanking cannot clear it and should not try.
            return done(turn, f"read to the last byte ({at:,})", whole=True)
        if wide > 32:
            return done(turn, f"blanking 32 bytes did not clear byte {at}")
        body[at:at + 1 + wide] = b" " * (1 + wide)
    return done(depth, f"still walled after {depth} rounds")


def measure(name: str, src: Path, work: Path, depth: int) -> Depth | None:
    folio = folio_for(name, work)
    if folio is None or not src.exists():
        return None
    text = src.read_bytes()
    out = ask(BIN, folio, src, tree=True)
    got = (Cold([], [], [], True, "") if out.kind == "whole" else
           peel(folio, text, work, src.suffix.lstrip(".") or "txt", depth))
    ranked, prefix, unpeeled = price(got.marks, got.seen, got.turns, len(text),
                                     got.closed, got.covered)
    return Depth(
        name=name, source=src.name, size=len(text), kind=out.kind, first=out.wall,
        reach=furthest(out.tree) if out.tree else max(out.reach, 0),
        roots=out.roots, mends=out.mends, crossed=len(got.seen),
        distinct=sorted(got.walls), closed=got.closed, why=got.why,
        priced=ranked, prefix=prefix, unpeeled=unpeeled,
    )


# What kind of thing the parse refused, and whose lane that is. Five families,
# assigned by the SHAPE of the terminal rather than by grammar, because the same
# shape is the same defect wherever it turns up - `(?:[^\\"\n]+)` is one bug with
# five witnesses (c, cpp, verilog, zig, and swift's cousin), not five bugs.
#
# The classification is judgment and is meant to be argued with, so it is one
# table rather than scattered conditionals, and anything it cannot place is
# printed as `unplaced` rather than swept into the nearest bucket.
FAMILY: tuple[tuple[str, str, str], ...] = (
    # family, lane, why this lane owns it
    ("permissive body pattern", "scanner",
     "a pattern that matches a run of anything-but-a-delimiter. This is the same "
     "family as the throughput defect: a permissive member survives to end-of-file, "
     "and bounding the walk is what stops it both refusing and costing"),
    ("unrunnable external", "scanner",
     "no terminal was producible at that byte at all, which on a grammar that "
     "declares externals is the stand-in machinery rather than the table"),
    ("bracket refused", "weave",
     "an opener or closer the state would not take. zig's `{` in 715 was already "
     "here as `offer()`; every other grammar in this row is a second witness"),
    ("separator refused", "press",
     "a comma, semicolon, colon, dot or operator refused where the table should "
     "have shifted it - a lookahead or merge question, not a lexing one"),
    ("string delimiter", "scanner",
     "the quote that opens or closes the run a permissive body pattern matches. "
     "One machine with the body, so it is the same lane - c and cpp carry both "
     "halves and it would be perverse to route them apart"),
    ("named terminal", "unassigned",
     "a keyword or a named terminal. No single lane owns these by shape; each "
     "needs reading, and they are the residue this classifier will not guess at"),
)
BRACKETS = frozenset("{}()[]") | {"]]", "*)"}
DELIMITERS = frozenset({'"', "`", '"""', "'''"})
BODYISH = ("_text", "_content")
WORD = re.compile(r"^[\\A-Za-z_][\w.]*$")
# Punctuation is a PREDICATE, not a list. An enumeration of operators is a
# list of the operators someone has already seen, so `:=` and `@` fell through
# it and the gate reported two ordinary operators as an unknown shape. A rule
# that reads "made only of punctuation, and not a bracket or a quote" needs no
# row when a grammar spells its assignment differently, and it leaves the
# residue meaning something: neither word-shaped nor punctuation-shaped.
PUNCTUATION = frozenset("!#$%&'*+,-./:;<=>?@\\^|~")


def family(kind: str, who: str) -> str | None:
    """Which family a distinct wall belongs to, from the terminal's shape alone,
    or **None** when no family claims it.

    Shape rather than name, so it generalises: a grammar added tomorrow with a
    string-body terminal nobody has seen lands in the right bucket without this
    table growing a row.

    Returning None is the point of the whole function. `named terminal` used to
    be the else-branch, which made the classifier total and therefore incapable
    of ever reporting a surprise - the closure claim it exists to support could
    not have been falsified by it. Now `named terminal` is a predicate like the
    others and an unrecognised shape falls through, which is what `walls.py
    gate` fails on."""
    if kind == "lexical":
        return "unrunnable external"
    term = who.split(" in state ")[0]
    if term.startswith("(?") or term.endswith(BODYISH) or term in {
            "word", "uninterpreted", "escape_sequence"}:
        return "permissive body pattern"
    if term in BRACKETS:
        return "bracket refused"
    if term in DELIMITERS:
        return "string delimiter"
    if term and set(term) <= PUNCTUATION:
        return "separator refused"
    return "named terminal" if WORD.match(term) else None


def roster() -> list[tuple[str, Path]]:
    """Every grammar the dossier measures: the corpus eleven from the corpus's
    own README, and the held-out nineteen from `breadth.SOURCES`. Both imported
    from their owner, so a language added to either is measured here with
    nothing to update."""
    out = [(n, CORPUS / leaf) for n, leaf in pairs()]
    have = {n for n, _ in out}
    return out + [(n, DEST / leaf) for n, (_, leaf, _) in SOURCES.items() if n not in have]


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("verb", nargs="?", default="run",
                    choices=("run", "list", "warm", "board", "gate"))
    ap.add_argument("--from-json", type=Path, help="read a saved `--json` survey instead of re-measuring")
    ap.add_argument("--grammar", action="append", help="just this one (repeatable)")
    ap.add_argument("--depth", type=int, default=DEPTH, help="rounds of peeling before giving up")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--names", type=int, default=0, help="print the N widest distinct walls per grammar")
    args = ap.parse_args(argv)

    todo = roster()
    if args.grammar:
        todo = [(n, p) for n, p in todo if n in args.grammar]
    if args.verb == "list":
        print(f"{'grammar':<20}{'source':<26}{'bytes':>9}")
        for n, p in todo:
            print(f"{n:<20}{p.name:<26}{p.stat().st_size if p.exists() else 0:>9,}")
        return 0
    if not BIN.exists():
        print(f"walls: no binary at {BIN}; `zig build` first", file=sys.stderr)
        return 2

    work = ROOT / ".local" / "walls"
    work.mkdir(parents=True, exist_ok=True)

    if args.verb == "gate":
        # Fixed roster, fixed budget, both peels. Reproducible on purpose: a
        # gate whose scope drifts with the corpus cannot say whether a change
        # is the tree's or its own. It does NOT gate the wall count - that is a
        # floor that grows with the budget and would fail on a longer run for
        # no reason. It gates **family closure**: every wall the budget reaches
        # must belong to a family this file already names. A shape nothing
        # claims is the finding, and it is the one thing here worth a red CI.
        #
        # **What it reaches, stated, because a closure gate that cannot see the
        # whole space is only worth having if its reach is written down.** The
        # roster is 9 of 30 grammars and the budget is 40 rounds per peel, which
        # is deep enough that no grammar here is still finding new families at
        # the end of it. It is not the whole space: `walls.py run` peels the full
        # roster deeper, and it found two walls - verilog's `'2` in states 1328
        # and 534 - that 40 rounds never reach. So green means **no new KIND of
        # difficulty inside this reach**, and never "no unclassified wall
        # exists". Read as the latter it would be a gate that quietly licenses
        # the survey to stop, which is the opposite of what it is for.
        rows, loose, forked = [], [], []
        pool = [(n, p) for n, p in roster() if n in GATE]
        if drift := set(GATE) - {n for n, _ in pool}:
            # A name that has left the roster would otherwise shrink the gate in
            # silence, which is the one way a fixed budget can stop being fixed.
            print(f"walls: gate: {', '.join(sorted(drift))} is not in the roster - "
                  f"the gate would run narrower than it claims", file=sys.stderr)
            return 2
        for name, src in pool:
            folio = folio_for(name, work)
            if folio is None or not src.exists():
                print(f"walls: gate: {name}: no grammar or no source", file=sys.stderr)
                return 2
            text, kind = src.read_bytes(), src.suffix.lstrip(".") or "txt"
            cold = peel(folio, text, work, kind, BUDGET).walls
            hot = warm(folio, text, work, kind, BUDGET)
            for k, w in sorted(cold | set(hot.walls)):
                (rows if family(k, w) else loose).append((name, k, w))
            # The board is measured through a folio, because that is what ships.
            # A folio is also capable of dropping a fact its grammar carried -
            # the reachability mask was derived at import and, for one afternoon,
            # never written into the folio at all. That loss was in cost only;
            # this asserts it was never in MEANING, which is the claim every
            # lane's work list rests on and which nothing else here would notice.
            if (named := GRAMMARS / f"{name}.json").exists():
                near = peel(folio, text, work, kind, PARITY).walls
                other = peel(named, text, work, kind, PARITY).walls
                if gap := other ^ near:
                    forked.append((name, sorted(gap)))
        kept = collections.Counter(family(k, w) for _, k, w in rows)
        print(f"walls: gate: {len(rows) + len(loose)} walls over {len(GATE)} grammars "
              f"at {BUDGET} rounds, cold and warm")
        for fam, n in kept.most_common():
            print(f"  {fam:<26}{n:>4}")
        if forked:
            print(f"\nwalls: gate: **{len(forked)} grammar(s) wall DIFFERENTLY through a "
                  f"folio than through their grammar** - the pressing is losing something "
                  f"that changes the parse, and the board is a list of one path's walls:",
                  file=sys.stderr)
            for g, gap in forked:
                print(f"  {g:<12}{len(gap)} wall(s) on one path only: "
                      f"{', '.join(w for _, w in gap[:4])}", file=sys.stderr)
            print(take(BIN).line())
            return 1
        if loose:
            print(f"\nwalls: gate: **{len(loose)} wall(s) belong to no family** - this is a "
                  f"shape the board has never seen, and it is the finding:", file=sys.stderr)
            for g, k, w in loose:
                print(f"  {g:<12}{k:<9}{w}", file=sys.stderr)
            print("\nRoute it, then give it a row in `FAMILY` and a predicate in `family()`. "
                  "Do NOT widen an existing predicate to swallow it - the point of the "
                  "residue is that it is visible.", file=sys.stderr)
            print(take(BIN).line())
            return 1
        print(f"\nwalls: gate: every wall lands in one of {len(kept)} known families. "
              f"Closure holds at this budget.")
        print(f"walls: gate: this covers {len(GATE)} of {len(roster())} grammars at "
              f"{BUDGET} rounds, both peels. It is not a claim that no unclassified "
              f"wall exists - `walls.py run` goes deeper and has found two the gate "
              f"cannot reach. Green here means no NEW kind of difficulty inside this "
              f"reach.")
        print(take(BIN).line())
        return 0

    if args.verb == "warm":
        hot = []
        for name, src in todo:
            folio = folio_for(name, work)
            if folio is None or not src.exists():
                print(f"walls: {name}: no grammar or no source, skipped", file=sys.stderr)
                continue
            text, ext = src.read_bytes(), src.suffix.lstrip(".") or "txt"
            cold = peel(folio, text, work, ext, args.depth).walls
            got = warm(folio, text, work, ext, args.depth)._replace(
                name=name, cold=sorted(cold))
            hot.append(got)
            print(f"walls: {name}: {got.rounds} warm rounds, {len(got.walls)} distinct, "
                  f"{len(got.only)} the cold peel could not reach", file=sys.stderr)
        if args.json:
            print(json.dumps([{**h._asdict(), "only": h.only, "quiet": h.quiet,
                               "rate": round(h.rate, 1)} for h in hot], indent=2, default=list))
            return 0
        print(f"\n{'grammar':<12}{'rounds':>8}{'cold':>7}{'warm':>7}{'warm-only':>11}"
              f"{'last new':>10}{'quiet':>7}{'per 100':>9}{'frontier':>10}  stopped")
        for h in hot:
            print(f"{h.name:<12}{h.rounds:>8}{len(h.cold):>7}{len(h.walls):>7}{len(h.only):>11}"
                  f"{(h.arrived[-1] if h.arrived else 0):>10}{h.quiet:>7}{h.rate:>9.1f}"
                  f"{h.frontier:>10,}  {h.why}")
            for kind, who in h.only:
                print(f"{'':<14}only warm reaches   {kind:<9}{who}")
            # What blanking each wall was worth, best and worst. A wall the warm
            # peel meets over and over can still be worth a negative number of
            # bytes, and that is the pair worth printing beside a recurrence.
            if h.costs:
                best, worst = h.costs[0], h.costs[-1]
                often = max(h.costs, key=lambda p: (p.hits, p.cost))
                print(f"{'':<14}reach delta   best {best.cost:+,}B x{best.hits} {best.who[:34]}")
                print(f"{'':<14}              worst {worst.cost:+,}B x{worst.hits} {worst.who[:34]}")
                print(f"{'':<14}              loudest x{often.hits} at {often.cost:+,}B "
                      f"{often.who[:34]}"
                      + ("" if often.wall == best.wall else "  <- not the dearest"))
                if h.unpriced:
                    print(f"{'':<14}              {h.unpriced} round(s) have no after-reach "
                          f"and are unpriced rather than zero")
        fresh = sum(len(h.only) for h in hot)
        rounds = sum(h.rounds for h in hot)
        # The two worlds, named rather than left to the reader. Saturation is
        # the claim that matters and it is a claim about the BACK half: finding
        # nothing new in the last N rounds is evidence; finding nothing new in
        # the first ten is what both worlds look like.
        print(f"\n{rounds} warm rounds over {len(hot)} grammar(s) reached **{fresh} wall(s) the "
              f"cold peel could not**, {sum(len(h.walls) for h in hot)} distinct in total.")
        if hot:
            worst = max(h.rate for h in hot)
            print("  -> " + (
                f"the cold count is a CEILING in practice: no grammar is still finding new walls "
                f"late (worst back-half rate {worst:.1f} per 100 rounds, quietest tail "
                f"{max(h.quiet for h in hot)} rounds silent). 24 is the tail."
                if worst < 1.0 and fresh == 0 else
                f"the cold count is a FLOOR and the tail is layered: new walls are still arriving "
                f"at {worst:.1f} per 100 rounds in the back half. Multiply, do not quote."
                if worst >= 1.0 else
                f"the cold count is a FLOOR by {fresh} wall(s), but a bounded one: the back-half "
                f"arrival rate is {worst:.1f} per 100 rounds, so what accumulated context adds is "
                f"a fixed handful rather than a layer that keeps giving."))
        print(take(BIN).line())
        return 0

    rows = []
    if args.from_json:
        # Re-measuring costs twenty minutes and the classification is pure, so
        # the board reads a saved survey by default rather than paying for the
        # same walls twice. It is the survey that has to be fresh, not this.
        rows = [Depth(**{k: v for k, v in r.items() if k in Depth._fields})
                for r in json.loads(args.from_json.read_text())]
        rows = [r._replace(distinct=[tuple(d) for d in r.distinct],
                           first=r.first and tuple(r.first),
                           priced=[Priced(*p) for p in r.priced])
                for r in rows]
    else:
        for name, src in todo:
            got = measure(name, src, work, args.depth)
            if got is None:
                print(f"walls: {name}: no grammar or no source, skipped", file=sys.stderr)
                continue
            rows.append(got)
            print(f"walls: {name}: {got.crossed} crossed, {len(got.distinct)} distinct", file=sys.stderr)
    if args.grammar:
        rows = [r for r in rows if r.name in args.grammar]

    if args.verb == "board":
        # Every wall carries its price, so a family can be read by what it costs
        # rather than by how many witnesses it happens to have. Those orderings
        # are not the same and the board used to only be able to show one.
        cost = {(r.name, p.kind, p.who): p for r in rows for p in r.priced}
        seen = [(r, k, w) for r in rows for k, w in r.distinct]

        def bytes_of(rows_in) -> int:
            return sum(p.cost for r, k, w in rows_in
                       if (p := cost.get((r.name, k, w))) is not None)

        lanes = {f: (lane, why) for f, lane, why in FAMILY}
        print(f"\n{len(seen)} distinct (terminal, state) walls over "
              f"{len({r.name for r, _, _ in seen})} grammars, "
              f"{bytes_of(seen):,} bytes, by family.\n")
        print("| family | lane | bytes | walls | shapes | grammars |")
        print("|---|---|---:|---:|---:|---|")
        packs = [(fam, [(r, k, w) for r, k, w in seen if family(k, w) == fam])
                 for fam in lanes]
        for fam, mine in sorted(packs, key=lambda x: -bytes_of(x[1])):
            if not mine:
                continue
            shapes = {w.split(" in state ")[0] for _, k, w in mine}
            who = sorted({r.name for r, _, _ in mine})
            print(f"| {fam} | **{lanes[fam][0]}** | {bytes_of(mine):,} | {len(mine)} | "
                  f"{len(shapes)} | {len(who)}: {', '.join(who)} |")
        print()
        for fam, mine in sorted(packs, key=lambda x: -bytes_of(x[1])):
            if not mine:
                continue
            shapes: dict[str, list[tuple]] = {}
            for r, k, w in mine:
                shapes.setdefault(w.split(" in state ")[0], []).append((r, k, w))
            print(f"### {fam} - {lanes[fam][0]}\n\n{lanes[fam][1]}.\n")
            print("| terminal | bytes | walls | grammars |")
            print("|---|---:|---:|---|")
            for shape, whos in sorted(shapes.items(), key=lambda s: -bytes_of(s[1])):
                tick = shape.replace("|", "\\|")
                print(f"| `{tick}` | {bytes_of(whos):,} | {len(whos)} | "
                      f"{', '.join(sorted({r.name for r, _, _ in whos}))} |")
            print()
        # `family` returns None on a shape no row claims, and that is the whole
        # point of it - so the residue is the `unassigned` lane **plus** the
        # unplaced, and indexing `lanes` with None would have crashed on exactly
        # the surprise the classifier exists to be able to report.
        held = [(r, k, w) for r, k, w in seen
                if (f := family(k, w)) is None or lanes[f][0] == "unassigned"]
        loose = [x for x in held if family(x[1], x[2]) is None]
        print(f"**{len(seen)} walls, "
              f"{len({f for _, k, w in seen if (f := family(k, w)) is not None})} families, "
              f"{len({w.split(' in state ')[0] for _, _, w in seen})} distinct terminals.** "
              f"{len(held)} sit in the unassigned residue ({bytes_of(held):,} bytes), which "
              f"is the honest size of what shape alone cannot route"
              + (f" - and {len(loose)} of those ({bytes_of(loose):,} bytes) no row "
                 f"claims at all, which is what `walls.py gate` fails on."
                 if loose else "."))
        print(take(BIN).line())
        return 0

    if args.json:
        print(json.dumps([{**r._asdict(), "covered": round(r.covered, 1),
                           "voice": round(r.voice, 1), "behind": r.behind,
                           "torn": r.torn, "balances": r.balances}
                          for r in rows], indent=2, default=list))
        return 0

    # Ranked by bytes behind a wall, not by how many distinct walls there are.
    # A count of walls is a count of difficulties and says nothing about what any
    # of them is worth; `behind` is the file lying past the first one.
    print(f"\n{'grammar':<20}{'read':>7}{'reach':>10}{'of':>9}{'roots':>7}{'mends':>7}"
          f"{'crossed':>9}{'distinct':>10}{'voice':>7}{'behind':>10}{'torn':>9}"
          f"{'clear':>9}{'unpeeled':>10}  tail")
    for r in sorted(rows, key=lambda r: (-r.behind, -len(r.distinct))):
        tail = ("closes" if r.closed and r.kind != "whole" else
                "whole, no wall" if r.kind == "whole" else r.why or "open")
        print(f"{r.name:<20}{r.covered:>6.1f}%{r.reach:>10,}{r.size:>9,}{r.roots:>7}"
              f"{r.mends:>7}{r.crossed:>9}{len(r.distinct):>10}{r.voice:>7.1f}"
              f"{r.behind:>10,}{r.torn:>9,}{r.prefix:>9,}{r.unpeeled:>10,}"
              f"{'' if r.balances else '  UNBALANCED'}  {tail}")
        if args.names and r.priced:
            for p in r.priced[:args.names]:
                print(f"{'':<22}{p.cost:>9,}B  x{p.hits:<4} {p.kind:<9}{p.who}"
                      f"   (round {p.turn} - refused in a fragment)" if p.torn else "")

    walled = [r for r in rows if r.kind != "whole"]
    if walled:
        deep = max(walled, key=lambda r: len(r.distinct))
        dear = max(walled, key=lambda r: r.behind)
        total = sum(len(r.distinct) for r in walled)
        opened = [r for r in walled if not r.closed]
        print(f"\n{len(walled)} of {len(rows)} grammars hit a wall. Between them the peel names "
              f"**{total} distinct walls** over **{sum(r.behind for r in walled):,} bytes**, "
              f"deepest {deep.name} at {len(deep.distinct)}, dearest {dear.name} at "
              f"{dear.behind:,}.")
        print(f"{len(rows) - len(walled)} read whole. "
              f"{len(walled) - len(opened)} tails close after their walls; "
              f"{len(opened)} did not finish peeling and are lower bounds"
              + (f" ({', '.join(r.name for r in opened)})" if opened else "") + ".")
        # The partition, checked on every run rather than argued once. A byte
        # price that can double-count is the same class of number as the count it
        # replaced, and the only thing standing between the two is this identity.
        off = [r for r in rows if not r.balances]
        print(f"prefix + priced + unpeeled == size on {len(rows) - len(off)}/{len(rows)} "
              f"grammar(s)" + (f" - **OFF on {', '.join(r.name for r in off)}**, whose "
                               f"prices are not published" if off else
                               ", so no wall is credited bytes another wall also owns."))
        # And the disagreement, printed rather than left to be rediscovered.
        split = [r for r in walled if r.disagrees]
        print(f"\n**Bytes and recurrence name a different worst wall in {len(split)} of "
              f"{len(walled)} walled grammars.** Ranking from `distinct` or `voice` "
              f"ranks the wrong thing in every one of them:")
        for r in sorted(split, key=lambda r: -(r.dearest.cost if r.dearest else 0)):
            a, b, c = r.dearest, r.loudest, r.standing
            print(f"  {r.name:<12}by bytes  {a.cost:>8,}B x{a.hits:<4} {a.who[:44]}")
            print(f"  {'':<12}by count  {b.cost:>8,}B x{b.hits:<4} {b.who[:44]}")
            if c is not None and c.wall != a.wall:
                print(f"  {'':<12}on the document {c.cost:>4,}B x{c.hits:<4} {c.who[:44]}")
        if not split:
            print("  (none - on this corpus the two orderings agree, which would make "
                  "the byte column a confirmation rather than a correction)")
        # How much of the byte board is the peel looking at its own resume. Named
        # here because it is the one number that would make the rest of this
        # ranking worth less than it looks, and it is large.
        seen_b, shade = sum(r.behind for r in walled), sum(r.torn for r in walled)
        blind = [r for r in walled if r.priced and r.standing is None]
        print(f"\n**{shade:,} of those {seen_b:,} bytes ({100.0 * shade / seen_b:.1f}%) stand "
              f"behind a wall the peel met only in a **fragment** - a suffix whose openers "
              f"round 1 left behind, which is not text this parser meets reading the file "
              f"whole. It is not a dismissal: `walls.py warm` witnesses a fragment wall on "
              f"the document, and `research/joinery/owners/cut.py` joins the two. Until it "
              f"has, subtract this before quoting a cost"
              + (f"; {len(blind)} grammar(s) ({', '.join(r.name for r in blind)}) have "
                 f"nothing else, so the peel priced only its own resume there." if blind
                 else ", and every walled grammar here has at least one wall on the document."))
        loud = [r for r in walled if r.voice >= 5]
        if loud:
            print(f"\n{len(loud)} grammar(s) hit one wall far more often than they hit distinct "
                  f"ones ({', '.join(f'{r.name} {r.voice:.0f}x' for r in sorted(loud, key=lambda r: -r.voice)[:5])}) "
                  f"- that is repetition, not depth. It is not an ordering: read `behind` "
                  f"and the priced rows for what any of it is worth.")
    print(take(BIN).line())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

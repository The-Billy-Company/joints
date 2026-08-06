#!/usr/bin/env python3
"""Is this wall a construct the parser cannot read, or the peel's own scissors?

`owners.py` labels a wall `stranded` when the state holds a completed item: a
fold could have left it, so the refusal may be several constructs downstream of
the mistake and nothing in the state can say. That is an honest report of what
the state cannot own. It is **not** a claim that a construct is hard, and this
file exists because most of the population turned out not to be one.

**The cold peel restarts in state 0.** `tool/walls.py` says so in its own words
- "resuming means parsing the remaining bytes from a clean start, so each round
begins in state 0 rather than in whatever state the product loop had actually
accumulated". So after the first wall the peel hands the parser a *fragment*,
and a fragment cut out of the middle of a brace body is not a program. Its
closers have no openers. The parser refuses them, correctly, and the peel prices
the refusal as damage.

Swift shows the shape in one line. `Chunked.swift` reads 1,492 bytes cleanly and
walls at `)` in state 141 - with **three braces still open**. The tail the peel
then parses cold begins `)`, `}`, `}`, `}`: four orphan closers. Every `}` after
that is refused at whatever file-level state the fragment's own prefix reached,
and the state number is nothing but a count of how many statements preceded it:

    }                       ->  } in state 0      13,475 B on the board
    let x = 1 \\n }          ->  } in state 681     9,160 B
    let x = 1 \\n y = 2 \\n } ->  } in state 1166    3,896 B

Those three witnesses are in `../strand/witness/sw-cut-*.swift` and reproduce
the three states exactly.

**So the discriminator cannot be a state number.** The board's was `state != 0`,
which caught the first row and let the next two through as construct damage. It
is now the peel's own **round**: round 1 reads the document, every round after it
reads a fragment (`walls.py`'s `Priced.turn` / `Priced.torn`). That is a fact
about the run rather than an inference from a wall, and no amount of statements in
front of an orphan closer can disguise it.

**What this file adds is the other half: a fragment wall can still be a real one,
and only a peel that keeps its prefix can say.** `tool/walls.py warm` parses the
whole file from byte 0 every round and blanks the offending byte, so the prefix
stays real. If it refuses **the same terminal at the same byte**, the cold wall is
a wall on the document that the cold peel merely happened to meet in a fragment.

**And the join is on the byte, not on the state, which is a repair.** The first
spelling of this file diffed the two peels' *wall phrases* - `<terminal> in state
<n>`. A fragment's state number is a count of the statements before it and a
whole-file parse's is not, so the two peels can only ever agree on a phrase where
they read the same text, which is round 1 and only round 1. On swift the phrase
join matched **1 of 11** cold walls and that one was the round-1 wall: the warm
peel contributed nothing to a 96.3% headline it was credited with. Warm blanks
rather than deletes precisely so offsets stay stable, so the byte is the key both
peels can satisfy. See `../reprice/RESULT-1-provenance.md`.

**Three verdicts, because an absence from a bounded run is not an acquittal.**
The warm peel's answer to "is this cold wall real" is "I never met it", and that
answer looks stronger the weaker the run is - the failure mode runs the same
direction as the headline. So the run reports how far it ever read (`frontier`),
and a cold wall past that byte is `untested`: warm never looked, and reading a
budget as evidence is the flattery this whole directory exists to catch.

**And the warm peel manufactures walls too, which took a second falsifier.** Three
parses of `Chunked.swift` under one pinned binary: as written it refuses `)` at
1492; blank that `)` and it refuses `}` at 1498 **in the same state 141, with the
same 308 roots and the same reach**; blank the `}` alone and the wall is back at
1492. So `}` at 1498 is not a wall in the file at all - it is the 1492 refusal
re-reported against the next token, and warm's first six blanks are six such
aliases marching forward through a file with one wall in it. A byte join asked
"does a whole-file parse also refuse this" was being answered yes by a parse that
only refuses it because the peel took its partner away.

The falsifier is the run's own tree: **blank this wall and does the parse build
anything it could not build before?** A new root closed or a byte further read is
a purchase; neither is a cascade. See `Warm.paid` and
`../reprice/PREDICTION-2-alias.md`.

  document   met while parsing the whole file - round 1. Needs no warm run.
  witnessed  a whole-file peel refuses the same byte AND blanking it bought a
             root or a byte, so it was standing in front of real structure.
  alias      a whole-file peel refuses the same byte and blanking it bought
             nothing: warm's own cascade, agreeing with cold's cut by accident.
  torn       warm read past that byte and never complained: the fragment made it.
  untested   warm never reached the byte, or nobody warm-peeled this grammar.

  python3 tool/walls.py warm --json > .local/reprice/warm.json
  python3 research/joinery/owners/owners.py --json > .local/owners/labelled.json
  python3 research/joinery/owners/cut.py --warm .local/reprice/warm.json

Give the warm run its own `OUTLINER_WORK`: two pinned binaries sharing one work
directory both read whichever folio was written last, and the error is always
flattering because two runs of the same table always agree.

Exit 0 measured, 1 nothing to compare or a vacuous reader, 2 an error.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import NamedTuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
import closure  # noqa: E402

ROOT = closure.ROOT
# The four provenances, in order of how much they are worth to a lane picking
# work. `owners.py` imports these rather than spelling them again - two files
# deciding this independently is the shape `tool/sole.py` polices, and the
# state-0 rule was already living in two places when this lane arrived.
DOCUMENT, WITNESSED = "document", "witnessed"
ALIAS, TORN, UNTESTED = "alias", "torn", "untested"
STANDS = (DOCUMENT, WITNESSED)  # a wall a lane may be sized against
MADE = (ALIAS, TORN)  # a wall one of the two peels manufactured
ALL = (DOCUMENT, WITNESSED, ALIAS, TORN, UNTESTED)


class Seat(NamedTuple):
    """One grammar peeled without ever restarting, as something a cold wall can
    be asked about.

    `seat` is the join that works: every (terminal, absolute byte) a whole-file
    round refused. `phrases` is the join that did not - the wall names, kept as a
    column so the difference between the two is measured on every run instead of
    being a sentence in a dossier.
    """

    name: str
    seat: frozenset[tuple[str, int]]
    paid: frozenset[tuple[str, int]]
    phrases: frozenset[tuple[str, str]]
    frontier: int
    rounds: int
    barren: int
    why: str

    def holds(self, term: str, first: int) -> bool:
        return (term, first) in self.seat

    def bought(self, term: str, first: int) -> bool:
        """Did blanking this one buy the parse a root or a byte?

        `Warm.paid` measures it. Without this the warm peel witnesses its own
        cascade: blank swift's `)` at 1492 and the `}` six bytes later becomes a
        wall in the same state with the same roots and the same reach, so a byte
        join asked "does a whole-file parse also refuse this" gets told yes by a
        parse that only refuses it because the peel took its partner away."""
        return (term, first) in self.paid

    def saw(self, first: int) -> bool:
        """Did this run demonstrably read that byte? The bound on its own absence."""
        return first <= self.frontier


def stand(seat: Seat | None, term: str, first: int, turn: int,
          roofed: bool = False) -> str:
    """One cold wall's provenance. The whole taxonomy, in one place.

    Round 1 needs nothing asked of it: it parsed the file.

    `roofed` is asked next and answers outright: round 1 read the file as written
    and **built a node over this byte**, so it did not refuse there, so a later
    round refusing there is refusing in text the peel cut. That is a presence
    rather than an absence, which is the whole reason it is asked before the warm
    peel - `../reprice/PREDICTION-2-alias.md` and `Warm.frontier` are both about
    an absence from a bounded run getting stronger the weaker the run is, and a
    node either covers a byte or it does not.

    Only where round 1 built nothing over the byte does the warm peel get a turn,
    and then only if blanking the wall **paid** for itself."""
    if turn <= 1:
        return DOCUMENT
    if roofed:
        return TORN
    if seat is None:
        return UNTESTED
    if seat.holds(term, first):
        return WITNESSED if seat.bought(term, first) else ALIAS
    return TORN if seat.saw(first) else UNTESTED


def term_of(who: str) -> str:
    """A wall phrase without the state it was refused in.

    The state is the one part of a fragment's wall that means nothing outside
    that fragment, so nothing joining two peels may keep it."""
    return who.split(" in state ")[0]


def read(paths: list[Path]) -> dict[str, Seat]:
    """Every `walls.py warm --json` document, as one seat per grammar.

    The grammar is the survey's own `name`, never the filename's - a name parsed
    out of a path is a fact about somebody's shell history.
    """
    out: dict[str, Seat] = {}
    for path in paths:
        rows = json.loads(path.read_text())
        for row in (rows if isinstance(rows, list) else [rows]):
            if not (isinstance(row, dict) and (name := row.get("name"))):
                continue
            marks = [(t, at) for t, at in (tuple(s) for s in row.get("spots") or ())]
            bought = list(row.get("bought") or ())
            paid = {s for s, ok in zip(marks, bought, strict=False) if ok}
            phrases = {tuple(w) for w in row.get("walls") or ()}
            old = out.get(name)
            out[name] = Seat(
                name,
                frozenset(marks) | (old.seat if old else frozenset()),
                frozenset(paid) | (old.paid if old else frozenset()),
                frozenset(phrases) | (old.phrases if old else frozenset()),
                max(int(row.get("frontier") or 0), old.frontier if old else 0),
                int(row.get("rounds") or 0) + (old.rounds if old else 0),
                sum(1 for b in bought if not b) + (old.barren if old else 0),
                str(row.get("why") or ""))
    return out


class Split(NamedTuple):
    """One grammar's walls, cut into the provenances."""

    grammar: str
    walls: list[dict]

    def of(self, *kinds: str) -> list[dict]:
        return [w for w in self.walls if w["stand"] in kinds]

    def cost(self, *kinds: str) -> int:
        return sum(w["cost"] for w in self.of(*kinds))


def split(walls: list[dict], seats: dict[str, Seat], owner: str) -> list[Split]:
    """Every wall of the population, with a provenance attached."""
    out: list[Split] = []
    for name in sorted({w["grammar"] for w in walls}):
        mine = [w for w in walls if w["grammar"] == name
                and (not owner or w["owner"] == owner)]
        seat = seats.get(name)
        rows = [{**w, "stand": stand(seat, w.get("term") or term_of(w["who"]),
                                     int(w.get("first") or 0), int(w.get("turn") or 1),
                                     bool(w.get("roofed")))}
                for w in mine]
        if rows:
            out.append(Split(name, sorted(rows, key=lambda w: -w["cost"])))
    return out


def report(walls: list[dict], seats: dict[str, Seat], owner: str) -> int:
    parts = split(walls, seats, owner)
    if not parts:
        print(f"cut: no {owner or 'labelled'} wall to place", file=sys.stderr)
        return 1
    whole = sum(p.cost(*ALL) for p in parts)

    print(f"\n{'grammar':<12}{'priced':>10}{'document':>10}{'witnessed':>11}{'alias':>8}"
          f"{'torn':>9}{'untested':>10}{'walls':>7}  what a whole-file parse also refuses")
    for part in parts:
        stood = ", ".join(f"{w['who']} ({w['cost']:,} B)" for w in part.of(*STANDS)[:3])
        print(f"{part.grammar:<12}{part.cost(*ALL):>10,}"
              f"{part.cost(DOCUMENT):>10,}{part.cost(WITNESSED):>11,}{part.cost(ALIAS):>8,}"
              f"{part.cost(TORN):>9,}{part.cost(UNTESTED):>10,}{len(part.walls):>7}  "
              + (stood or "nothing"))

    tally = {k: sum(p.cost(k) for p in parts) for k in ALL}
    count = {k: sum(len(p.of(k)) for p in parts) for k in tally}
    stands = tally[DOCUMENT] + tally[WITNESSED]
    made = tally[ALIAS] + tally[TORN]
    print(f"\n**{made:,} B of the {whole:,} B population ({100.0 * made / whole:.1f}%) "
          f"is an instrument, not a construct** - {tally[TORN]:,} B refused only in a "
          f"fragment whose openers round 1 left behind, which a peel keeping its prefix "
          f"read past without complaint, and {tally[ALIAS]:,} B where that peel did "
          f"complain but blanking bought it no root and no byte, so it was re-reporting "
          f"its own last refusal against the next token.")
    print(f"**{stands:,} B ({100.0 * stands / whole:.1f}%) stands** - "
          f"{tally[DOCUMENT]:,} B met while parsing the whole file ({count[DOCUMENT]} walls) "
          f"and {tally[WITNESSED]:,} B a whole-file peel refuses at the same byte and paid "
          f"a root or a byte to clear ({count[WITNESSED]} walls). That is the population "
          f"worth a lane.")
    print(f"**{tally[UNTESTED]:,} B ({100.0 * tally[UNTESTED] / whole:.1f}%) is untested** "
          f"- past the furthest byte any warm round reached, or in a grammar nobody "
          f"warm-peeled. Neither claimed nor dismissed, and the honest home for the "
          f"bound: an absence from a budgeted run looks stronger the weaker the run is, "
          f"so a wall the run never reached is not evidence of anything.")

    # The join, measured against the join this file used to use. A cold wall's
    # phrase carries a fragment's state number, so the old key could only match
    # round 1 - which means a 96.3% credited to the warm peel was mostly the key.
    # Printed as a column because it is the finding as well as the falsifier.
    print(f"\n{'grammar':<12}{'rounds':>8}{'barren':>8}{'frontier':>10}{'by byte':>9}"
          f"{'paid':>6}{'by phrase':>11}{'round 1':>9}  what each key and each purchase buys")
    dud = 0
    for part in parts:
        seat = seats.get(part.grammar)
        if seat is None:
            print(f"{part.grammar:<12}{'-':>8}{'-':>8}{'-':>10}{'-':>9}{'-':>6}{'-':>11}"
                  f"{'-':>9}  nobody warm-peeled it")
            continue
        byte = [w for w in part.walls if seat.holds(w.get("term") or term_of(w["who"]),
                                                   int(w.get("first") or 0))]
        paid = [w for w in byte if seat.bought(w.get("term") or term_of(w["who"]),
                                               int(w.get("first") or 0))]
        phrase = [w for w in part.walls if (w["kind"], w["who"]) in seat.phrases]
        early = sum(1 for w in phrase if int(w.get("turn") or 1) <= 1)
        dud += not byte and not phrase
        print(f"{part.grammar:<12}{seat.rounds:>8}{seat.barren:>8}{seat.frontier:>10,}"
              f"{len(byte):>9}{len(paid):>6}{len(phrase):>11}{early:>9}  "
              + ("every byte match is a cascade of one refusal" if byte and not paid else
                 "the byte join matches walls a phrase join misses" if len(byte) > len(phrase)
                 else "the phrase join is round 1 restated" if phrase and early == len(phrase)
                 else "no cold wall of this grammar survives either join"))
    print("A cold-only row is evidence only because the join demonstrably matches other "
          "walls of the same grammar. Where a grammar matches nothing under either key "
          "the reader is not usable there and its rows are the reader restating itself.")
    print("The `by phrase` column is the retired key. Where it equals `round 1` the warm "
          "peel was contributing nothing that `Priced.turn` does not already know for "
          "free, and a headline resting on it was resting on a state number.")
    print("`barren` counts rounds whose blank bought no root and no byte, and `paid` is "
          "the byte matches that survive that test. A grammar with `by byte` well above "
          "`paid` was witnessing warm's own cascade, which is the second manufactured "
          "population in this file and the one that had a falsifier pointed at it last.")
    return 1 if dud and dud == len(parts) else 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--from-json", type=Path,
                    default=ROOT / ".local/owners/labelled.json",
                    help="an `owners.py --json` labelling, which carries the verdicts")
    ap.add_argument("--warm", type=Path, action="append", default=[],
                    help="a `walls.py warm --json` survey (repeatable)")
    ap.add_argument("--owner", default="stranded",
                    help="which owner's population to place (empty for all)")
    args = ap.parse_args(argv)

    if not args.warm:
        print("cut: needs at least one --warm survey; make one with\n"
              "  python3 tool/walls.py warm --json > <file>", file=sys.stderr)
        return 2
    if not args.from_json.exists():
        print(f"cut: no labelling at {args.from_json} - run\n"
              f"  python3 research/joinery/owners/owners.py --json > {args.from_json}",
              file=sys.stderr)
        return 2
    for path in args.warm:
        if not path.exists():
            print(f"cut: no warm survey at {path}", file=sys.stderr)
            return 2

    seats = read(args.warm)
    if not seats:
        print("cut: no warm survey named a grammar", file=sys.stderr)
        return 2
    if not any(s.seat for s in seats.values()):
        # A warm survey minted before `spots` existed carries phrases and no
        # bytes, and the byte join would then call the whole population torn for
        # want of a column. That is the flattering direction, so it is fatal.
        print("cut: no warm survey carries `spots` - re-run `walls.py warm --json` "
              "against a tree that records the byte each round blanked", file=sys.stderr)
        return 2
    return report(json.loads(args.from_json.read_text()), seats, args.owner)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Which of these walls does the file itself refuse, asked of one parse.

`../reprice/` left 18,146 B of the wall board `untested` and named the reason:
`Cold.canopy` decides provenance from "round 1 built a node over this byte",
and **a node in a mended forest is not a claim that the text under it was read
as the author wrote it**. The parse that built it had already repaired
somewhere, so the node proves round 1 did not refuse *there* - not that the
byte survived. The capability that settles it, enumerating the repair sites,
was not in the binary. It is now: `joints parse --scars`, one line per mend.

## The reading, and why it is `--mend=keep` and not the default

The old taxonomy reaches `document` only at `turn <= 1`, and a peel's round 1
yields exactly **one** wall - where the parse stopped. Every later refusal in
the same file was invisible, so a cold wall at byte 24,000 could never be
`document` however loudly the file refused there. A mending parse meets them
all, and `--scars` prints them.

Which policy matters. Under `--mend=fell` the stack is carried off and stood
back up in state zero, so every segment after the first is reading a **suffix
from cold** - which is the peel's own resume, and crediting those would be
importing the exact artifact `../reprice/` spent a round deleting. Under
`--mend=keep` the token is dropped and the parse reads on **holding the context
it built from byte 0**. A refusal there is the document's, met with the file's
own openers standing. So `keep` is the seat and `fell` is recorded beside it as
the control: where the two disagree, the disagreement is the resume artifact,
priced instead of assumed.

## The falsifier, which is the same one warm failed

`keep` cascades too: drop a token from a stuck state and the next token is often
refused for the same reason, in the same state, having bought nothing. That is
precisely what `../reprice/PREDICTION-2-alias.md` caught the warm peel doing at
a cost of one whole parse per byte. Here it costs nothing: a scar carries the
tokens the parse had **shifted** when it refused, so a repair that shifted
nothing since the last one is that one re-reported against the next token. Those
are **not credited** - they land in `alias`, the taxonomy's own word for a
refusal that agrees with a cut by accident - and their count is printed, because
an instrument that hides its own cascade is the instrument this directory exists
to catch. haskell is the exhibit: 16,634 repairs of which **16,632 shifted
nothing**, a parse that reads the whole file and takes two tokens off it.

## And `reach` is a watermark, which is the trap this nearly fell into

The first spelling of this file bounded its own ignorance with `Outcome.reach` -
"the last byte any root covers". On a parse that drops every token that is
*end of file*, so every wall byte reads as seen, so everything not scarred comes
back `torn` and the instrument reports the flattering answer everywhere it
understood least. That is the same defect `covered` was introduced to fix on the
standing board, met again one layer down.

So the bound is built here instead, out of the two things this lane owns: the
**canopy** (every byte some node of the keeping parse covers) minus the **holes**
(every byte some repair deleted). A byte in that difference was covered by a node
*and* not walked past, which is the claim `Cold.canopy` was making and could not
support. Their intersection - bytes under a node that a repair deleted anyway -
is printed as `papered`, and it is the size of the hole this lane was sent to
close.

## The self-check, which runs on every invocation

The 14 walls the board already calls `document` were met by a non-mending parse
of the same file. Each must therefore be the **first** credited scar of its
grammar, at the same byte. If one is not, this seat is not reading what the
board reads and the run says so and exits 1 rather than publishing a table.

  python3 research/joinery/owners/owners.py --json > .local/scars/labelled.json
  python3 research/joinery/scars/seat.py --from-json .local/scars/labelled.json

Give this its own `JOINTS_WORK`: two pinned binaries sharing one work
directory both read whichever folio was written last, and that error is always
flattering, because two runs of the same table always agree.

Exit 0 measured, 1 the self-check failed or nothing to compare, 2 an error.
"""

from __future__ import annotations

import argparse
import collections
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))
sys.path.insert(0, str(ROOT / "research" / "joinery" / "owners"))

import cut  # noqa: E402
import order  # noqa: E402
import stamp  # noqa: E402
import walls  # noqa: E402

# `scar 24582..24594 12B kept unexpected identifier in state 398, 122 heads, +3501 tokens`
SCAR = re.compile(
    r"^scar (\d+)\.\.(\d+) (\d+)B (fell|kept) (.+?), (\d+) heads, \+(\d+) tokens$")
# `stamp.SPAN` keeps only the end offset, because the one question it is asked -
# how far did a mended parse get - is a maximum. This one is asked which bytes
# are under a node, so it needs both edges. Same render, different question.
RANGE = re.compile(r"\[(\d+), (\d+)\)")


class Site(NamedTuple):
    """One repair, as the CLI printed it."""

    at: int
    over: int
    felled: bool
    why: str
    heads: int
    since: int

    @property
    def term(self) -> str:
        """The refused terminal, spelled as the wall board spells it."""
        m = re.match(r"unexpected (.*) in state (\d+)$", self.why)
        return m[1] if m else self.why


class Seat(NamedTuple):
    """One grammar's whole-file repair sites, and the bound on its own ignorance.

    `read` is a bitmap the length of the file: covered by a node of the keeping
    parse **and** not inside any repair. It is `Cold.canopy` with the papering
    subtracted, and it is the only thing here entitled to say a byte was read as
    the author wrote it.
    """

    name: str
    sites: tuple[Site, ...]
    read: bytes
    canopy: int
    papered: int
    kind: str
    # The same file read under the felling policy, as the control on the one
    # judgement call this instrument makes.
    felled: tuple[Site, ...]

    @property
    def credited(self) -> tuple[Site, ...]:
        """Sites that shifted at least one token since the previous one.

        The first is always credited: nothing precedes it to be a cascade of.
        """
        return tuple(s for i, s in enumerate(self.sites) if i == 0 or s.since > 0)

    @property
    def cascades(self) -> tuple[Site, ...]:
        return tuple(s for i, s in enumerate(self.sites) if i > 0 and s.since == 0)

    def refuses(self, byte: int) -> bool:
        return any(s.at == byte for s in self.credited)

    def restates(self, byte: int) -> bool:
        """Refused here having shifted nothing since the last refusal."""
        return any(s.at == byte for s in self.cascades)

    def saw(self, byte: int) -> bool:
        """Did the parse demonstrably read this byte as written?"""
        return 0 <= byte < len(self.read) and bool(self.read[byte])


def read(name: str, src: Path, art: Path, binary: Path, mend: str) -> tuple[Site, ...]:
    got = subprocess.run(
        [str(binary), "parse", str(art), str(src), "--scars", f"--mend={mend}"],
        capture_output=True, text=True, timeout=stamp.PATIENCE, cwd=ROOT)
    out: list[Site] = []
    for line in got.stdout.splitlines():
        if m := SCAR.match(line.strip()):
            out.append(Site(int(m[1]), int(m[2]), m[4] == "fell", m[5],
                            int(m[6]), int(m[7])))
    return tuple(out)


def seat(name: str, src: Path, work: Path, binary: Path) -> Seat | None:
    art = order.folio_for(name, work) or (order.GRAMMARS / f"{name}.json")
    if not Path(art).exists() or not src.exists():
        return None
    # `stamp.ask` is the one reader of this binary's stderr and the one place
    # that knows to ask for a forest when the verdict alone cannot answer, so
    # the tree comes from there rather than from a twelfth subprocess.
    end = stamp.ask(binary, art, src, tree=True, extra=("--mend=keep",))
    if not end.tree:
        return None
    size = src.stat().st_size
    under = bytearray(size)
    for a, b in RANGE.findall(end.tree):
        lo, hi = min(int(a), size), min(int(b), size)
        under[lo:hi] = b"\1" * (hi - lo)
    sites = read(name, src, art, binary, "keep")
    canopy = sum(under)
    for s in sites:
        under[s.at:s.over] = bytes(max(0, min(s.over, size) - min(s.at, size)))
    kept = sum(under)
    return Seat(name, sites, bytes(under), canopy, canopy - kept, end.kind,
                read(name, src, art, binary, "fell"))


def stand(seat: Seat | None, byte: int, turn: int) -> str:
    """One cold wall's provenance, decided from the repair sites.

    Round 1 still needs nothing asked of it. After that the question is no
    longer "did a node cover this byte" - which a mended forest cannot answer -
    but "did the whole file, read with its own context standing, refuse here",
    and that has three answers rather than one.
    """
    if turn <= 1:
        return cut.DOCUMENT
    if seat is None:
        return cut.UNTESTED
    if seat.refuses(byte):
        return cut.DOCUMENT
    # It refused here too, but it had shifted nothing since the last time, so
    # the agreement is worth what warm's was: the taxonomy already has a word.
    if seat.restates(byte):
        return cut.ALIAS
    return cut.TORN if seat.saw(byte) else cut.UNTESTED


def table(rows: list[dict], seats: dict[str, Seat]) -> int:
    was = collections.Counter()
    now = collections.Counter()
    moved: collections.Counter[tuple[str, str]] = collections.Counter()
    for w in rows:
        got = stand(seats.get(w["grammar"]), int(w["first"]), int(w["turn"]))
        was[w["stand"]] += w["cost"]
        now[got] += w["cost"]
        if got != w["stand"]:
            moved[(w["stand"], got)] += w["cost"]
    whole = sum(was.values())

    print(f"\n{'grammar':<12}{'sites':>7}{'restated':>10}{'credited':>10}"
          f"{'felled':>8}{'canopy':>9}{'papered':>9}{'read':>9}  what the file itself refuses")
    papered = canopy = 0
    for name in sorted(seats):
        s = seats[name]
        papered += s.papered
        canopy += s.canopy
        first = ", ".join(f"{x.at}" for x in s.credited[:5])
        print(f"{name:<12}{len(s.sites):>7}{len(s.cascades):>10}{len(s.credited):>10}"
              f"{len(s.felled):>8}{s.canopy:>9,}{s.papered:>9,}{s.canopy - s.papered:>9,}"
              f"  {first}")
    print(f"{'all':<12}{'':>7}{'':>10}{'':>10}{'':>8}{canopy:>9,}{papered:>9,}"
          f"{canopy - papered:>9,}")
    print(f"\n**{papered:,} B of the {canopy:,} B under a node "
          f"({100.0 * papered / canopy:.1f}%) was deleted by a repair anyway** - a node "
          f"covers it and the parse walked past it. That is the size of the hole "
          f"`Cold.canopy` could not see, measured rather than argued.")

    print(f"\n{'provenance':<12}{'was':>12}{'now':>12}{'delta':>12}")
    for k in cut.ALL:
        d = now[k] - was[k]
        print(f"{k:<12}{was[k]:>11,}B{now[k]:>11,}B{d:>+11,}B")
    print(f"{'total':<12}{whole:>11,}B{sum(now.values()):>11,}B")

    stands = sum(now[k] for k in cut.STANDS)
    made = sum(now[k] for k in cut.MADE)
    print(f"\n**{made:,} B ({100.0 * made / whole:.1f}%) is an instrument** and "
          f"**{stands:,} B ({100.0 * stands / whole:.1f}%) stands** - the file "
          f"itself refuses at that byte with its own context standing. "
          f"**{now[cut.UNTESTED]:,} B ({100.0 * now[cut.UNTESTED] / whole:.1f}%) "
          f"remains untested**: past the byte a whole-file parse ever reached.")

    if moved:
        print("\nwhat moved, and in which direction")
        for (a, b), v in sorted(moved.items(), key=lambda kv: -kv[1]):
            print(f"  {a:>9} -> {b:<9} {v:>9,} B")

    # Two bounds on the one judgement this instrument makes, both printed
    # because a reader who disputes it should be able to read their own answer
    # off the same table rather than take this one on trust.
    print(f"\n**If the cascade call is wrong the standing floor is "
          f"{now[cut.DOCUMENT] + now[cut.ALIAS]:,} B, not {now[cut.DOCUMENT]:,} B.** "
          f"{now[cut.ALIAS]:,} B is bytes the whole-file parse did refuse at, having "
          f"shifted nothing since its previous refusal. Credited, they would take the "
          f"instrument share from {100.0 * made / whole:.1f}% to "
          f"{100.0 * now[cut.TORN] / whole:.1f}%. The reason they are not is the reason "
          f"`../reprice/` deleted warm's `witnessed` column, applied to this lane's own "
          f"evidence rather than only to the one it inherited.")

    fell = collections.Counter()
    for w in rows:
        s = seats.get(w["grammar"])
        cold = None if s is None else s._replace(sites=s.felled)
        fell[stand(cold, int(w["first"]), int(w["turn"]))] += w["cost"]
    print(f"\n**The felling policy is the control, and it is the flattering arm.** "
          f"Built from `--mend=fell` - where every segment after the first reads a "
          f"suffix from state zero, which is the peel's own resume - the same test "
          f"calls {fell[cut.DOCUMENT]:,} B `document` against this seat's "
          f"{now[cut.DOCUMENT]:,} B. The difference, "
          f"{fell[cut.DOCUMENT] - now[cut.DOCUMENT]:+,} B, is what a lane would have "
          f"claimed by asking the question of a parse that had already thrown the "
          f"context away.")
    return 0


def subsumes(warm: Path, seats: dict[str, Seat]) -> None:
    """What the 400-round warm peel found, against one mending parse.

    Warm's whole method is to blank a wall byte and re-parse, four hundred times
    per grammar, to see where the file walls next. A `--mend=keep` parse walks
    the same ground once and reports every refusal it met - so this is the
    comparison that says whether the capability replaces the round budget or
    merely accompanies it. `spots` is warm's per-round wall byte; the distinct
    ones are what it actually learned.
    """
    got = json.loads(warm.read_text())
    print(f"\n{'grammar':<12}{'rounds':>8}{'warm bytes':>12}{'scar bytes':>12}"
          f"{'covered':>9}  the bytes warm found that one parse did not")
    for r in sorted(got, key=lambda r: -r["rounds"]):
        s = seats.get(r["name"])
        if s is None or not r["rounds"]:
            continue
        # A spot is `[terminal, byte]`; the byte is the join key everything else
        # in this taxonomy is indexed by.
        theirs = {int(x[1]) for x in r["spots"]}
        mine = {x.at for x in s.sites}
        missed = sorted(theirs - mine)
        print(f"{r['name']:<12}{r['rounds']:>8,}{len(theirs):>12,}{len(mine):>12,}"
              f"{100.0 * len(theirs & mine) / max(len(theirs), 1):>8.0f}%"
              f"  {', '.join(str(b) for b in missed[:6]) or '-'}")


def check(rows: list[dict], seats: dict[str, Seat]) -> list[str]:
    """Every wall the board reached without this instrument must still be one.

    A `turn <= 1` wall was met by a non-mending parse of the same file, so a
    keeping parse of it must refuse at the same byte and must do it first. This
    is the one claim that can be falsified without a second opinion, and it is
    asked before any table is printed.
    """
    bad = []
    for w in rows:
        if int(w["turn"]) > 1:
            continue
        s = seats.get(w["grammar"])
        if s is None or not s.credited:
            bad.append(f"{w['grammar']}: round-1 wall at {w['first']} but no scar at all")
        elif s.credited[0].at != int(w["first"]):
            bad.append(f"{w['grammar']}: round-1 wall at {w['first']} but first scar "
                       f"at {s.credited[0].at}")
    return bad


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--from-json", type=Path, required=True,
                    help="an `owners.py --json` labelling, which carries the verdicts")
    ap.add_argument("--json", type=Path, help="write the seats out for a later join")
    ap.add_argument("--warm", type=Path,
                    help="a `walls.py warm --json` survey, to price what its round "
                         "budget bought against one mending parse")
    args = ap.parse_args(argv)

    rows = json.loads(args.from_json.read_text())
    binary = order.BIN
    work = Path(order.os.environ.get("JOINTS_WORK", ROOT / ".local" / "work"))
    want = {w["grammar"] for w in rows}
    seats: dict[str, Seat] = {}
    for name, src in walls.roster():
        if name in want and (s := seat(name, src, work, binary)):
            seats[name] = s
    if not seats:
        print("seat: nothing measurable", file=sys.stderr)
        return 1

    if bad := check(rows, seats):
        print("seat: the round-1 walls this seat must reproduce, it does not:",
              file=sys.stderr)
        for line in bad:
            print(f"  {line}", file=sys.stderr)
        return 1
    print(f"seat: {len(seats)} grammar(s) · every round-1 wall reproduced as this "
          f"parse's first credited repair")

    if args.warm:
        subsumes(args.warm, seats)
    if args.json:
        args.json.write_text(json.dumps(
            {n: {"canopy": s.canopy, "papered": s.papered, "kind": s.kind,
                 "sites": [x._asdict() for x in s.sites],
                 "felled": [x._asdict() for x in s.felled]}
             for n, s in seats.items()}, indent=1))
    return table(rows, seats)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

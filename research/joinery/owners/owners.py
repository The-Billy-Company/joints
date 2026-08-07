#!/usr/bin/env python3
"""Whose defect is each wall - the grammar's, ours, or a scanner we don't run?

`research/joinery/verilog/reach.py` answered that for six walls on one grammar
by handing a closure a governing nonterminal **picked by hand** off a one-line
witness. The answer was worth having: 28,470 of verilog's bytes turned out to be
upstream gaps, so a lane trying to seat them in the press would have been
chasing a derivation that does not exist in the grammar it was reading. But
hand-picking positions does not scale to 170 walls in 17 grammars, and 170 hand
picks are 170 chances to pick the position that makes the verdict come out the
way I expected.

So the position comes off the wall's own LR state. `joints state <g.json> <n>`
prints the kernel items, and an item `A -> alpha . beta` says exactly what this
position can still consume, which turns the ownership question into the textbook
one:

  **viable(state) = FIRST(beta) over every item, plus FOLLOW(A) for every item
  whose beta can vanish.**

A terminal outside that set is a terminal *no* LR parser over this grammar
accepts in this state - after any sequence of reductions, under any lookahead.
That is an impossibility argument rather than a measurement, and it is the only
kind of argument that distinguishes `no derivation exists` from `we could not
get it to work`.

**Four owners, and the fourth one is the finding.** Two is verilog-shaped, and
the naive reading of the closure gets three of verilog's four hand verdicts
wrong - because a wall's state is *not* where the reading stood. `inquest.zig`
says so about its own `Owner.weave`: "the wall's state is where the folds ran
out, which is many reduces downstream of where the reading stood". State 701
holds one item, `casting_type -> constant_primary .`, and admits one terminal:
the parse's mistake was folding `a` to a cast at all, and by the time `;` is
refused there is nothing left of the construct to ask about. Read that state and
every conflict in the corpus looks exactly like a gap.

What separates them is **whether a fold could have left this state**:

  **conflict** - the terminal is inside viable. The grammar licenses it in this
  very state, after any of the folds available here, and the press's table has
  no cell for it. A press defect, proven without an input. **Ours.**

  **unowned** - the terminal is outside viable *and every item has its dot
  strictly inside the production*. Nothing was folded to arrive here, so this is
  the construct's own position and the right place to ask - and the automaton we
  built from this grammar holds no reading for the terminal. **That is all it
  establishes.** Four things produce it and three of them are ours: our table
  lost a reading, our lexer produced a terminal the program does not contain, an
  external was never seated, or the grammar genuinely has nothing.

  This verdict was called `gap` and printed "no LR parser over this grammar
  takes it here". Tree-sitter is an LR parser over that grammar and takes it on
  15 of the 18 rows that were checked, worth 99.94% of their bytes - see
  `../adjudicate/`. The sentence was false because the **item set is ours**:
  `viable()` computes FIRST/FOLLOW over the grammar, but the items come from our
  LR(0) collection, so a reading our table construction lost is indistinguishable
  from one the grammar never had. A lane in `src/press/` is fixing a splice that
  erases authored precedence with no conflict recorded and no fork - a reading
  deleted with nothing in the row to see, which is exactly this case.

  **stranded** - the terminal is outside viable and the state holds a completed
  item, so a fold could have left it and the refusal is that fold's consequence.
  **Whose defect this is cannot be decided from the state**, and this is the
  *wrong place to ask* where `unowned` is the right place with four answers.
  Verilog's three conflicts are all in this bucket and all three were settled by
  a witness built from nothing, which does not automate. This is a report of
  what the instrument cannot own, not a verdict.

  **scanner** - the terminal is a declared `external`, or the wall is lexical.
  An external has no rule body on purpose: tree-sitter runs a C scanner for it
  and parses the construct fine. A closure run naively over `rules` finds no
  derivation and would call every one of these a grammar gap - which is not a
  small correction, since 23 of 30 vendored grammars declare externals, **and
  the declaration comes in three shapes**: 461 named symbols, 21 literals and 2
  patterns. Reading only the named shape dropped bash's `]`, which this board
  published as a 495-byte grammar gap for one afternoon.

`conflict` is tested **before** `scanner`, and the order is a correction. A
terminal can be both - declared external and derivable in this very state - and
the first spelling let the name lookup win, which files a press defect the
closure has *proven* under a lane that does not run C. Viability is positive
evidence about this position; a blind-hit is a name in a list. Where both hold,
the row says so.

Everything is biased away from `unowned` where it is uncertain, deliberately and
in every place it is uncertain: FOLLOW over-approximates the LR(1) lookahead
sets; a terminal contributes every spelling it might answer to; an item whose
dot position is ambiguous contributes the union over every reading; a state that
could have been reached by a fold gets no `unowned` verdict at all.

**The control this earns its verdicts on** is the verilog lane's four hand
verdicts, which were reached from hand-built one-line witnesses and are entirely
independent of anything here: `` ` `` in 1108 gap, `;` in 701 conflict, `(` in
3772 conflict, `=` in 2394 conflict. `--control` checks all four on every run. The
naive state closure gets 1 of 4; with the settled test it gets 4 of 4, and the
one it changes its mind about (`(` in 3772, a live state with 31 shifts and 62
items) is the row that shows the test is doing work rather than restating
`shift == 0`.

**The anti-vacuity control, which is the reason to believe any of it.** The
closure could say `unreachable` for everything and every wall would read as a
grammar gap. So every state is also asked about the terminals the built table
**already admits** there - `joints state` prints them, and they are by
construction things this grammar accepts in this state. The closure has to find
those viable. Per state, per grammar, printed on every run: a grammar whose
control is not near 100% has its verdicts withheld rather than reported, because
a closure that cannot see what the parser demonstrably does is reading itself.

  python3 research/joinery/owners/owners.py --control     # the verilog four, both rules
  python3 research/joinery/owners/owners.py --from-json .local/owners/priced.json
  python3 research/joinery/owners/owners.py --grammar verilog --names
  python3 research/joinery/owners/owners.py --externals   # the census, and what one read drops
  python3 research/joinery/owners/owners.py --unowned     # the adjudication worklist
  python3 research/joinery/owners/owners.py --json

Exit 0 ran, 1 no wall to label or a control that failed, 2 an error.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
import closure  # noqa: E402
import cut  # noqa: E402

ROOT = closure.ROOT
GRAMMARS = closure.GRAMMARS
BIN = Path(os.environ.get("JOINTS_BIN") or ROOT / "zig-out" / "bin" / "joints")
IN_STATE = re.compile(r"^(.*) in state (\d+)$")
# `    {name: <28} {verdict}`, and the verdict may carry a `[declared …]` note
# after it - so the pattern stops at the verb rather than anchoring on the end of
# the line. Anchoring cost haskell fourteen admitted terminals, every one of them
# a whole line read as a terminal's name, which deflated its control to 72% and
# withheld all 56 of its verdicts.
ROW = re.compile(r"^ {4}(.*?)(?: {2,}| )(?:read on|accept|nothing|fold {2})")
# The control floor. Below it a grammar's verdicts are withheld: see `Bench`.
FLOOR = 95.0


class Bench(NamedTuple):
    """What the built table admits in one state, and what the closure made of it.

    This is the whole falsifiability of the file. `admitted` is not an opinion -
    those terminals have table cells in this state, so this grammar demonstrably
    accepts them here. `seen` is how many of them the closure independently
    derived from the items. A closure with a broken bridge, a mis-flattened
    grammar, or an off-by-one in FIRST scores low here *and* calls every wall a
    gap, and the two are the same failure. So the number is printed beside the
    verdicts it licenses rather than in a footnote.
    """

    admitted: int
    seen: int

    @property
    def rate(self) -> float:
        return 100.0 * self.seen / self.admitted if self.admitted else 100.0


class Wall(NamedTuple):
    grammar: str
    kind: str          # `state` or `lexical`, as the peel spelled it
    who: str           # the peel's whole phrase, e.g. `; in state 715`
    term: str          # just the terminal
    state: int | None  # None for a lexical wall - no state was ever consulted
    hits: int
    cost: int
    turn: int          # the earliest peel round that met it - 1 read the document
    first: int         # the earliest absolute byte it stands at
    roofed: bool       # round 1 built a node over `first` - see `Cold.covered`
    stand: str         # document|witnessed|alias|torn|untested - see `cut.stand`
    owner: str         # unowned | conflict | stranded | scanner | unplaced | withheld
    why: str
    settled: bool = True  # no item in this state has its dot at the end
    items: tuple[str, ...] = ()
    bench: Bench = Bench(0, 0)

    @property
    def real(self) -> bool:
        """Is this a wall on the file rather than an artifact of resuming?

        This was `not shadow and state != 0`, and the state number was the wrong
        predicate for a right instinct. A state-0 wall is a resumed fragment
        refusing its own first token - but so is the same fragment with one
        statement in front of it, at state 681, and with two, at state 1166. The
        state number is a count of the statements that preceded the wall, so no
        rule over it can separate the two, and 13,056 bytes of swift were sold as
        construct damage on the difference.

        The predicate that works is not a property of the wall at all. It is the
        **provenance of the text the round was handed**: round 1 read the file,
        every round after it read a suffix. `cut.stand` is the one place that
        decides it, and it is five-valued on purpose. A fragment wall a whole-file
        peel refuses at the same byte stands only if blanking it **bought** that
        peel a root or a byte (`witnessed`); if it bought nothing the whole-file
        peel was re-reporting its own last refusal against the next token
        (`alias`), which is warm's version of exactly this defect. A wall no
        whole-file peel ever reached is `untested` rather than acquitted.
        """
        return self.stand in cut.STANDS

    @property
    def torn(self) -> bool:
        """Refused in a fragment, and a peel that kept its prefix read past that
        byte without complaining there. The peel's own scissors."""
        return self.stand == cut.TORN

    @property
    def made(self) -> bool:
        """An instrument built this wall - either peel's scissors. See `cut.MADE`."""
        return self.stand in cut.MADE


def rows(text: str) -> tuple[tuple[str, ...], tuple[str, ...], int]:
    """One `joints state` dump into (items, admitted terminals, unparsed)."""
    items: list[str] = []
    admitted: list[str] = []
    lost, where = 0, ""
    for line in text.splitlines():
        if line.startswith("  items:"):
            where = "items"
        elif line.startswith("  row"):
            where = "row"
        elif line.startswith("  shift ") or not line.strip():
            where = ""
        elif where == "items" and line.startswith("    "):
            items.append(line.strip())
        elif where == "row" and line.strip() != "(none)":
            if (m := ROW.match(line)) is not None:
                admitted.append(m.group(1))
            else:
                lost += 1
    return tuple(items), tuple(admitted), lost


def split(item: str) -> tuple[str, list[tuple[str, ...]]]:
    """`A -> alpha . beta` into (A, every reading of beta).

    Plural because the printer writes the dot as a bare `.` and `.` is also a
    terminal in six of these grammars, so `expression . . identifier` has two
    readings and nothing in the line distinguishes them. Both are returned and
    the caller unions their FIRST sets, which widens viable and can only turn a
    gap into a conflict.
    """
    lhs, _, rhs = item.partition(" -> ")
    syms = rhs.split(" ")
    return lhs, [tuple(syms[i + 1:]) for i, s in enumerate(syms) if s == "."]


def viable(g: closure.Grammar, items: tuple[str, ...]) -> frozenset[str]:
    """Every terminal any LR parser over `g` could accept in this state.

    An item whose tail can vanish contributes FOLLOW(A), which is what makes this
    cover the folds available here as well as the shifts: a completed item's tail
    is empty, so its whole contribution is FOLLOW of its left-hand side. That is
    why `(` in verilog's 3772 comes back outside the set even though 31 terminals
    shift there - the state can fold `expression` five ways and none of the five
    is ever followed by `(`.
    """
    out: set[str] = set()
    for item in items:
        lhs, tails = split(item)
        for beta in tails:
            for s in beta:
                out |= g.spread(s)
                if s not in g.nullable:
                    break
            else:
                out |= g.follow.get(lhs, frozenset())
    return frozenset(s for t in out for s in g.spellings(t))


def settled(items: tuple[str, ...]) -> bool:
    """Did the parse *shift* into this state, or could a fold have left it?

    The whole difference between `gap` and `stranded`, and one line of text
    decides it: an item with the dot at the end is a reading this state can fold,
    so the parse may be here because something folded early - and then the wall is
    the fold's fault and the construct was never asked about. Every item strictly
    mid-production means nothing has completed, so this is the construct's own
    position and a refusal here is about the construct.

    Ambiguity is resolved toward *unsettled*, which is the direction that
    withholds a gap: the printer writes the dot as a bare `.` and `.` is also a
    terminal, so `A -> b . .` reads as complete under one of its two readings and
    that is enough to disqualify it.
    """
    return all(not item.endswith(" .") for item in items) and bool(items)


def dump(grammar: str, at: int, keep: dict[tuple[str, int], str]) -> str:
    """`joints state`, memoised - haskell walls crowd onto few states."""
    if (hit := keep.get((grammar, at))) is not None:
        return hit
    got = subprocess.run([str(BIN), "state", str(GRAMMARS / f"{grammar}.json"), str(at)],
                         capture_output=True, text=True, check=False)
    keep[(grammar, at)] = got.stdout
    return got.stdout


def verdict(g: closure.Grammar, term: str, seen: frozenset[str],
            firm: bool) -> tuple[str, str]:
    """One terminal against one viability set, and against how it got there.

    Viability is asked **first**, and that ordering is a repair. The two tests
    are not the same kind of evidence: `seen` is derived from this state's own
    items, so a hit is positive proof the grammar licenses the terminal *here*,
    while `blind` is a name in a list that says nothing about position. Letting
    the list win filed a proven press defect as somebody else's C scanner - and
    under a lane that does not run C, which is the worst possible place to send
    it. Where both hold the row still says so, because seating the external is
    real work even when the reading exists.
    """
    kin = g.spellings(term)
    dual = " (also a declared external - seating it may be the cheaper repair)"
    if kin & seen:
        return "conflict", ("the grammar derives it here and joints refused it"
                            + (dual if kin & g.blind else ""))
    if kin & g.blind:
        return "scanner", "a declared external - tree-sitter runs a C scanner for it"
    if not any(g.known(s) for s in kin):
        return "unplaced", "no symbol of this grammar answers to that name"
    if not firm:
        return "stranded", ("a fold can leave this state, so the refusal is that "
                            "fold's consequence and the state cannot own it")
    if seen <= {closure.END}:
        return "unowned", "the state can only end the input, so nothing may follow"
    return "unowned", ("shifted into, nothing folded: outside FIRST(beta) and FOLLOW(A) "
                       "over every item of the collection **we** built - a reading our "
                       "table lost reads identically to one the grammar never had")


def label(name: str, walls: list[tuple[str, str, int, int, int, int, bool]],
          keep: dict[tuple[str, int], str],
          seat: cut.Seat | None = None) -> tuple[list[Wall], Bench, int]:
    """Every wall of one grammar, labelled, with the grammar's own control."""
    g = closure.load(name)
    out: list[Wall] = []
    admits, saw, lost = 0, 0, 0
    for kind, who, hits, cost, turn, first, roofed in walls:
        # The provenance is asked of `cut`, which is the only file that decides
        # it. Two files agreeing on a rule is how the state-0 exclusion came to
        # live here *and* in `walls.py`, and only one of them was ever fixed.
        where = cut.stand(seat, cut.term_of(who), first, turn, roofed)
        if kind != "state" or (m := IN_STATE.match(who)) is None:
            out.append(Wall(name, kind, who, who, None, hits, cost, turn, first, roofed,
                            where,
                            "scanner",
                            "lexical - nothing tokenized, so no state was consulted"))
            continue
        term, at = m.group(1), int(m.group(2))
        items, admitted, missed = rows(dump(name, at, keep))
        lost += missed
        seen = viable(g, items)
        # The control, over the terminals this state already accepts.
        held = sum(1 for a in admitted if g.spellings(a) & seen)
        admits, saw = admits + len(admitted), saw + held
        firm = settled(items)
        owner, why = verdict(g, term, seen, firm)
        out.append(Wall(name, kind, who, term, at, hits, cost, turn, first, roofed, where,
                        owner, why, firm, items[:6], Bench(len(admitted), held)))
    bench = Bench(admits, saw)
    if bench.rate < FLOOR:
        out = [w._replace(owner="withheld",
                          why=f"grammar control {bench.rate:.0f}% - below the {FLOOR:.0f}% floor")
               for w in out if w.state is not None] + [w for w in out if w.state is None]
    return out, bench, lost


# The verilog lane's four hand verdicts, reached from one-line witnesses built
# from nothing and independent of every mechanism in this file. `naive` is what
# the state closure alone says, kept as a column so the settled test is seen to
# do work: it is right about one row of four, and the row it is right about is
# the only gap.
# Bytes are that lane's own attribution, off `RESULT-2-witness.md`'s table, and
# are here only to price what mislabelling one row would cost.
#   (state, terminal, the construct, the hand verdict, bytes)
CONTROL: tuple[tuple[int, str, str, str, int], ...] = (
    (1108, "`", "a directive in statement position - `` `assert(a); ``", "unowned", 21_535),
    (701, ";", "a select inside a concatenation - `x = {a[3], b};`", "conflict", 19_928),
    (3772, "(", "`$signed` both sides of an operator", "conflict", 360),
    (2394, "=", "an indexed lvalue under a *blocking* assignment - `c[i] = 0;`", "conflict", 93),
)


def control(keep: dict[tuple[str, int], str]) -> int:
    """Both rules against four verdicts neither of them produced.

    The naive column is the point. A file that only printed the fixed rule's
    answers would be four rows written to pass; printing what the state closure
    says on its own shows which rows the settled test is carrying, and that it is
    carrying three of them.
    """
    g = closure.load("verilog")
    bad, over = 0, 0
    print(f"\n{'wall':<16}{'items':>6}{'admits':>8}{'settled':>9}  {'naive':<11}"
          f"{'this file':<12}{'hand':<11}construct")
    for at, term, what, want, cost in CONTROL:
        items, admitted, _ = rows(dump("verilog", at, keep))
        seen, firm = viable(g, items), settled(items)
        naive = verdict(g, term, seen, True)[0]
        got = verdict(g, term, seen, firm)[0]
        # `stranded` is the honest answer where the hand found a conflict: the
        # state cannot prove it, and the hand needed a witness to. So it counts
        # as agreement only in the sense that matters - it does not claim `gap`.
        ok = got == want or (want == "conflict" and got == "stranded")
        bad += not ok
        over += cost if naive == "unowned" and want != "unowned" else 0
        print(f"{term + ' in ' + str(at):<16}{len(items):>6}{len(admitted):>8}"
              f"{('yes' if firm else 'no'):>9}  {naive:<11}{got:<12}{want:<11}{what}")
    print(f"\n{len(CONTROL) - bad}/{len(CONTROL)} agree. The naive state closure calls all "
          f"four unowned and only one of them is, so it files **{over:,} bytes** of "
          f"press work as a nobody-can-fix - which is the direction that costs a lane "
          f"its whole week.")
    print("A `stranded` where the hand found `conflict` is agreement here: the state "
          "declines to own it and the hand needed a hand-built witness to own it. An "
          "`unowned` there would be the failure.")
    return 1 if bad else 0


def vacuity(survey: list[dict], want: list[str],
            keep: dict[tuple[str, int], str]) -> int:
    """Score every state's admitted row against a **different** state's items.

    `PREDICTION-1`'s P3 promised to watch the control collapse before believing it
    high, and a control that cannot be made to fail is not one. So each row is
    scored twice: against the state that admits it, and against the next walled
    state in the same grammar. The first has to be ~100% and the second has to be
    far from it - if a neighbour scores as well, the closure is answering from the
    grammar at large rather than from the position, and every verdict in this file
    is a coin toss with a citation.
    """
    print(f"\n{'grammar':<12}{'admitted':>9}{'own state':>11}{'a neighbour':>13}")
    for r in survey:
        if want and r["name"] not in want:
            continue
        at = [int(w.split(" in state ")[1]) for _, w in (tuple(x) for x in r["distinct"])
              if " in state " in w]
        if len(at) < 2:
            continue
        g = closure.load(r["name"])
        right = astray = tot = 0
        for i, one in enumerate(at):
            items, admitted, _ = rows(dump(r["name"], one, keep))
            near, _, _ = rows(dump(r["name"], at[(i + 1) % len(at)], keep))
            mine, other = viable(g, items), viable(g, near)
            tot += len(admitted)
            right += sum(1 for a in admitted if g.spellings(a) & mine)
            astray += sum(1 for a in admitted if g.spellings(a) & other)
        if tot:
            print(f"{r['name']:<12}{tot:>9,}{100.0 * right / tot:>10.1f}%"
                  f"{100.0 * astray / tot:>12.1f}%")
    print("\nThe right-hand column is the same closure asked the same question about "
          "the wrong position. A grammar where the two columns are close is a grammar "
          "whose verdicts mean nothing.")
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--from-json", type=Path, default=ROOT / ".local/owners/priced.json",
                    help="a `walls.py run --json` survey, which carries the prices")
    ap.add_argument("--warm", type=Path, action="append", default=[],
                    help="a `walls.py warm --json` survey, which witnesses a fragment "
                         "wall on the document (repeatable). Without one, every wall "
                         "past round 1 is `untested` rather than assumed either way")
    ap.add_argument("--grammar", action="append", default=[])
    ap.add_argument("--names", action="store_true", help="every wall, not just the split")
    ap.add_argument("--unowned", action="store_true",
                    help="the unowned list - a worklist for adjudication")
    ap.add_argument("--externals", action="store_true",
                    help="the declared-external census, both reads, and the difference")
    ap.add_argument("--terminals", action="store_true",
                    help="re-derive each wall's terminal against its own state's row")
    ap.add_argument("--artifacts", action="store_true",
                    help="are the state-0 walls artifacts? against FIRST(start)")
    ap.add_argument("--stranded", action="store_true",
                    help="what the unownable population folds through")
    ap.add_argument("--control", action="store_true", help="the verilog four, and nothing else")
    ap.add_argument("--vacuity", action="store_true",
                    help="score each row against a neighbouring state, and watch it collapse")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)

    if args.externals:
        return externals(args.grammar)

    if args.control:
        if not BIN.exists():
            print(f"owners: no binary at {BIN}", file=sys.stderr)
            return 2
        return control({})

    if not args.from_json.exists():
        print(f"owners: no survey at {args.from_json} - run "
              f"`python3 tool/walls.py run --json > {args.from_json}` first", file=sys.stderr)
        return 2
    survey = json.loads(args.from_json.read_text())
    if not BIN.exists():
        print(f"owners: no binary at {BIN}", file=sys.stderr)
        return 2

    for path in args.warm:
        if not path.exists():
            print(f"owners: no warm survey at {path}", file=sys.stderr)
            return 2
    seats = cut.read(args.warm)

    keep: dict[tuple[str, int], str] = {}
    if args.vacuity:
        return vacuity(survey, args.grammar, keep)
    walls: list[Wall] = []
    benches: dict[str, Bench] = {}
    lost = 0
    for r in survey:
        if args.grammar and r["name"] not in args.grammar:
            continue
        priced = r.get("priced") or []
        # The peel names its distinct walls; the price and the **provenance** ride
        # on the same pairs. A survey minted before `walls.py` recorded the round
        # would default every wall to round 1 and read as if the whole board were
        # on the document, which is the flattering direction, so it is refused.
        cost = {(p[0], p[1]): tuple(p[2:7]) for p in priced if len(p) >= 7}
        if priced and not cost:
            print(f"owners: {r['name']}: the survey's priced rows carry no round, "
                  f"offset or roof - re-run `tool/walls.py run --json`", file=sys.stderr)
            return 2
        pack = [(k, w, *cost.get((k, w), (0, 0, 1, 0, False)))
                for k, w in (tuple(x) for x in r["distinct"])]
        if not pack:
            continue
        got, bench, missed = label(r["name"], pack, keep, seats.get(r["name"]))
        walls.extend(got)
        benches[r["name"]] = bench
        lost += missed
    if not walls:
        print("owners: no wall in the survey to label", file=sys.stderr)
        return 1

    if args.json:
        print(json.dumps([{**w._asdict(), "bench": w.bench._asdict(),
                           "real": w.real, "roofed": w.roofed} for w in walls], indent=2))
        return 0

    if args.terminals:
        return terminals(walls, keep)

    if args.artifacts:
        return artifacts(walls, keep)

    if args.stranded:
        return stranded(walls, keep)

    if args.unowned:
        return unowned(walls)

    OWNERS = ("unowned", "conflict", "stranded", "scanner")
    by = sorted({w.grammar for w in walls})
    print(f"\n{'grammar':<14}{'walls':>7}{'unown':>7}{'confl':>7}{'strand':>8}{'scan':>6}"
          f"{'other':>7}{'unown B':>10}{'confl B':>9}{'strand B':>10}{'scan B':>8}"
          f"{'stands B':>10}{'control':>9}")
    for name in sorted(by, key=lambda n: -sum(w.cost for w in walls if w.grammar == n)):
        mine = [w for w in walls if w.grammar == name]
        tally = {o: [w for w in mine if w.owner == o] for o in OWNERS}
        other = [w for w in mine if w.owner in ("unplaced", "withheld")]
        print(f"{name:<14}{len(mine):>7}"
              + "".join(f"{len(tally[o]):>{n}}" for o, n in zip(OWNERS, (7, 7, 8, 6)))
              + f"{len(other):>7}"
              + "".join(f"{sum(w.cost for w in tally[o]):>{n},}"
                        for o, n in zip(OWNERS, (10, 9, 10, 8)))
              + f"{sum(w.cost for w in mine if w.real):>10,}"
              + f"{benches[name].rate:>8.0f}%")
        if args.names:
            for w in sorted(mine, key=lambda w: -w.cost):
                print(f"{'':<16}{w.owner:<9}{w.cost:>8,}B x{w.hits:<4} {w.who:<32}"
                      f" [{w.stand}]")
                print(f"{'':<25}{w.why}")

    tally = {o: [w for w in walls if w.owner == o]
             for o in (*OWNERS, "unplaced", "withheld")}
    b = Bench(sum(x.admitted for x in benches.values()), sum(x.seen for x in benches.values()))
    print(f"\n**{len(walls)} distinct walls over {len(by)} walled grammars.** "
          + ", ".join(f"{len(tally[o])} {o}" for o in OWNERS)
          + f", {len(tally['unplaced'])} unplaced, {len(tally['withheld'])} withheld.")
    priced = {o: sum(w.cost for w in tally[o]) for o in OWNERS}
    if (both := sum(priced.values())):
        print(f"By the peel's byte price over {both:,} B: "
              + ", ".join(f"**{priced[o]:,} B {o}**" for o in OWNERS) + ".")
        seat = priced["conflict"] + priced["scanner"]
        print(f"So {100.0 * priced['conflict'] / both:.1f}% of the priced bytes are a "
              f"reading this grammar licenses and this table refused - provably ours - "
              f"and another {100.0 * priced['scanner'] / both:.1f}% is an external to "
              f"seat, which is also work this tree can do. Together "
              f"**{100.0 * seat / both:.1f}% is workable here.** "
              f"{100.0 * priced['unowned'] / both:.1f}% is unowned, which is four things "
              f"and only one of them is upstream, and "
              f"{100.0 * priced['stranded'] / both:.1f}% cannot be owned from the wall's "
              f"state at all.")
        stands = {s: sum(w.cost for w in walls if w.stand == s) for s in cut.ALL}
        held = sum(w.cost for w in walls if w.real)
        open_ = stands[cut.UNTESTED]
        # Provenance covers every wall, including the ones no owner column could
        # seat, so it is priced over `all_` and never over the columns' `both`.
        all_ = sum(w.cost for w in walls)
        print(f"\n**Every byte the peel prices is priced by a peel that restarts. "
              f"{held:,} B of the {all_:,} ({100.0 * held / all_:.1f}%) stands on the "
              f"document** - the rest is a wall in a suffix whose opener round 1 left "
              f"behind, which is not text this parser meets reading the file whole. "
              + ", ".join(f"{stands[s]:,} B {s}" for s in cut.ALL if stands[s]) + ". "
              f"`document` is round 1 itself; `witnessed` is a whole-file peel refusing "
              f"the same byte *and* buying something by blanking it; `alias` bought "
              f"nothing, `torn` is roofed by round 1's own canopy, and `untested` is "
              f"neither reached nor cleared. That denominator is every wall - "
              f"{all_:,} B - not the {both:,} B the four owner columns could seat, "
              f"because provenance answers for a wall no column places too. See "
              f"`cut.py` and `../reprice/`.")
        roof = sum(w.cost for w in walls if w.stand == cut.TORN and w.roofed)
        print(f"**Read that as a range, not a number: {held:,} B is the floor and "
              f"{held + open_:,} B the ceiling**, because {open_:,} B is `untested` - no "
              f"whole-file peel got that far, and a bounded run leaves more bytes "
              f"untested the *weaker* it is. Widening the warm budget moves bytes out of "
              f"`untested` in either direction, and it can also move the "
              f"{stands[cut.TORN] - roof:,} B of `torn` that rests on warm having *seen* "
              f"the byte. It cannot move the other {roof:,} B: round 1 built a node over "
              f"those, and a node either covers a byte or it does not. That subset is the "
              f"only part of this table no budget can flatter.")
        for o in OWNERS:
            got = sum(w.cost for w in tally[o] if w.real)
            print(f"  {o:<9}{sum(w.cost for w in tally[o]):>10,} B priced "
                  f"->{got:>9,} B standing"
                  + (f"  ({100.0 * got / priced[o]:.1f}% survives)" if priced[o] else ""))
    real = [w for w in tally["unowned"] if w.real]
    print(f"{len(real)} of the {len(tally['unowned'])} unowned walls are on the file "
          f"rather than on the peel's own resume ({sum(w.cost for w in real):,} B); "
          f"`--unowned` writes them out. Each needs adjudicating against a second parser "
          f"before anyone may call it upstream - `../adjudicate/` did that for eighteen "
          f"and 15 of them were takeable.")
    print(f"\n**Control: the closure derived {b.seen:,} of the {b.admitted:,} terminals "
          f"these states already admit ({b.rate:.1f}%).** Those are table cells, so the "
          f"grammar demonstrably accepts them there; a closure that could not see them "
          f"would call every wall unowned for the same reason it missed them. The four "
          f"verilog hand verdicts are the other control - `--control`.")
    weak = sorted((n for n, x in benches.items() if x.rate < FLOOR), key=str)
    print(f"{len(weak)} grammar(s) fell below the {FLOOR:.0f}% floor and have their verdicts "
          f"withheld" + (f": {', '.join(weak)}." if weak else ", so none is withheld."))
    if lost:
        print(f"{lost} row line(s) did not parse and were not counted either way.")
    return 0


def unowned(walls: list[Wall]) -> int:
    """The unowned list - a worklist for adjudication, not a claim of upstream.

    The predecessor of this function wrote `GAPS.md`, whose header read "no LR
    parser over it accepts the construct - tree-sitter included, since it reads
    the same file". A lane checked that against tree-sitter 0.26.11 and 15 of
    the 18 rows parsed, worth 99.94% of their bytes. The inference was wrong in
    one specific place: tree-sitter reads the same `grammar.json` but builds its
    *own* collection from it, and this file's items come from ours. So the
    header is now what the test supports - a state where no reading was found -
    and the disposal column says what has to happen before anyone believes it.
    """
    rows_ = sorted((w for w in walls if w.owner == "unowned"),
                   key=lambda w: (-w.cost, w.grammar))
    print("# Unowned walls - this table found no reading, and that is all\n")
    print("Every row: the LR(0) collection **we** build from the vendored "
          "`grammar.json` holds no item whose FIRST or FOLLOW admits this terminal "
          "here, and nothing in the state has folded. Four things produce that and "
          "three are ours - our table lost a reading (`src/press/` is fixing a splice "
          "that erases precedence with nothing in the row to see), our lexer produced a "
          "terminal the program does not contain, an external was never seated, or the "
          "grammar has nothing. Deciding which needs a second parser over the same "
          "file: see `../adjudicate/`. `real` marks walls the parser meets reading the "
          "file whole; the others are the peel resuming mid-construct.\n")
    print("| grammar | wall | bytes | hits | real | why |")
    print("|---|---|---|---|---|---|")
    for w in rows_:
        tick = w.who.replace("|", "\\|").replace("`", "'")
        print(f"| {w.grammar} | `{tick}` | {w.cost:,} | {w.hits} | "
              f"{'yes' if w.real else 'no - resume artifact'} | {w.why} |")
    live = [w for w in rows_ if w.real]
    print(f"\n**{len(rows_)} unowned, {len(live)} of them on the file itself "
          f"({sum(w.cost for w in live):,} bytes).** Ranked by the peel's byte price. "
          f"None of these is an upstream claim until a second parser has refused it too.")
    return 0


def terminals(walls: list[Wall], keep: dict[tuple[str, int], str]) -> int:
    """Ask each wall's own state whether it really refuses the wall's terminal.

    **The instrument this lane trusts least is the wall's own name**, inherited
    from the lane before it: four of eighteen hand-built witnesses refused a
    *different* terminal than the list named, and `verilog-sized` is named after
    a construct that parses whole. A wall's terminal decides its label, its
    price and its owner together, so a wrong name is three wrong answers that
    agree with each other.

    So re-derive rather than inherit. `joints state` prints the terminals a
    state's table row **admits** - those are cells, not opinions - and a stop
    line saying `unexpected T in state N` is the claim that `T` is not among
    them. The two come from different code paths over the same table, so they
    can disagree, and where they do the wall's name is not usable evidence about
    anything. This is the cheapest check in the lane and nobody had run it.

    A `refused` row is the expected shape and proves nothing on its own - which
    is why `admitted` is printed rather than filtered away. The rate is the
    finding.
    """
    live = [w for w in walls if w.state is not None]
    bad: list[tuple[Wall, str]] = []
    mute = 0  # the mirror: a wall re-asked about a terminal its state DOES admit
    for w in live:
        g = closure.load(w.grammar)
        _, admitted, _ = rows(dump(w.grammar, w.state, keep))
        kin = g.spellings(w.term)
        if (hit := [a for a in admitted if g.spellings(a) & kin]):
            bad.append((w, ", ".join(sorted(set(hit))[:3])))
        # Anti-vacuity, per wall and free: swap the wall's terminal for one this
        # very state admits and re-run the same predicate. It must flag every
        # one. Without this column, a `spellings()` that matched nothing would
        # score 100% coherent and read as a clean bill of health - which is the
        # exact failure shape this project has caught thirty-one times.
        mute += bool(admitted) and not any(g.spellings(a) & g.spellings(admitted[0])
                                           for a in admitted)
    print(f"\n**{len(live)} state walls re-derived against their own state's admitted "
          f"row.** A wall is coherent when the state it names does not admit the "
          f"terminal it names.")
    if bad:
        print(f"\n{'grammar':<14}{'wall':<34}{'bytes':>9}  admitted anyway as")
        for w, hit in sorted(bad, key=lambda p: -p[0].cost):
            print(f"{w.grammar:<14}{w.who:<34}{w.cost:>9,}  {hit}")
    print(f"\n**{len(bad)} incoherent, {len(live) - len(bad)} refused as named** "
          f"({100.0 * (len(live) - len(bad)) / len(live):.1f}% coherent, "
          f"{sum(w.cost for w, _ in bad):,} B at stake).")
    print(f"**Mirror: {len(live) - mute} of {len(live)} walls flag correctly when their "
          f"terminal is swapped for one their own state admits** - so the column above "
          f"is a test that can say no, not a `spellings()` that matches nothing."
          + (f" {mute} could not be mirrored and their coherence is not evidence."
             if mute else ""))
    print("An incoherent row is not a labelling bug - it is a wall whose name is not "
          "evidence, and every verdict resting on that name is withheld by hand until a "
          "witness re-derives it. A coherent row is necessary and nowhere near "
          "sufficient: the terminal can still be the *lexer's* choice rather than the "
          "program's, which this check cannot see and `../adjudicate/` found in 5 of 18.")
    return 1 if bad else 0


def artifacts(walls: list[Wall], keep: dict[tuple[str, int], str]) -> int:
    """Are the state-0 walls really the peel's own resume, or a refusal that counts?

    The board excludes them on an assertion nobody had tested: a state-0 wall is
    "a resumed fragment refusing its own first token", so it is evidence about
    where the peel cut rather than about any construct. That is *checkable*, and
    from the grammar alone. State 0 is the start state; the terminals a file may
    legally begin with are `FIRST(start)`, computed here over `grammar.json`
    without consulting our table at all. So:

      terminal outside FIRST(start)  ->  **artifact.** No parser over this
      grammar accepts a file beginning with it, tree-sitter included. Refusing
      it is correct behaviour, and the bytes are the peel's cut, not a defect.

      terminal inside FIRST(start)   ->  **not an artifact.** The grammar says a
      file may begin here and our start state refused - which is the same shape
      as every `conflict` on the board and has been excluded from it.

    The two columns are the point. A rule that answered `artifact` for
    everything would be the exclusion restated, so the second column is what
    makes the first one a measurement.
    """
    shade = [w for w in walls if not w.real]
    print(f"\n**{len(shade)} walls the board excludes as resume artifacts, "
          f"{sum(w.cost for w in shade):,} B.** Each terminal against FIRST(start), "
          f"computed from `grammar.json` alone.")
    print(f"\n{'grammar':<12}{'wall':<26}{'bytes':>9}{'start':<16}  verdict")
    keeps: list[Wall] = []
    for w in sorted(shade, key=lambda w: -w.cost):
        g = closure.load(w.grammar)
        # FIRST(start) over every production of the start symbol, spelled every
        # way the terminal might answer to - the same widening `viable` uses, so
        # this errs toward calling a wall real rather than dismissing it.
        opens = {s for beta in g.prods.get(g.start, ()) for s in openers(g, beta)}
        wide = frozenset(s for t in opens for s in g.spellings(t))
        real = bool(g.spellings(w.term) & wide)
        keeps += [w] if real else []
        print(f"{w.grammar:<12}{w.who:<26}{w.cost:>9,}{g.start:<16}  "
              f"{'NOT an artifact - FIRST(start) admits it' if real else 'artifact'}")
    print(f"\n**{len(shade) - len(keeps)} of {len(shade)} are artifacts by the grammar's "
          f"own start set ({sum(w.cost for w in shade) - sum(w.cost for w in keeps):,} B); "
          f"{len(keeps)} are not ({sum(w.cost for w in keeps):,} B).**")
    # The anti-vacuity. A rule that answered `artifact` unconditionally scores
    # exactly what the column above scores, so the column above is worth nothing
    # until the rule is shown refusing. Every grammar in the population is asked
    # again about a terminal its own start set **does** contain - real openers,
    # off `grammar.json` - and every one of those must come back NOT an artifact.
    print(f"\n{'grammar':<12}{'a real opener':<26}must read")
    dud = 0
    for name in sorted({w.grammar for w in shade}):
        g = closure.load(name)
        opens = sorted({s for beta in g.prods.get(g.start, ()) for s in openers(g, beta)
                        if g.spellings(s) and not g.prods.get(s)})
        if not opens:
            continue
        probe = opens[0]
        wide = frozenset(s for beta in g.prods.get(g.start, ())
                         for t in openers(g, beta) for s in g.spellings(t))
        got = bool(g.spellings(probe) & wide)
        dud += not got
        print(f"{name:<12}{probe[:24]:<26}"
              f"{'NOT an artifact - correct' if got else 'ARTIFACT - the rule is vacuous'}")
    print(f"\n{'Every' if not dud else f'{dud} of the'} grammar in the population "
          f"{'refuses' if not dud else 'FAILED to refuse'} a terminal that can really "
          f"open a file, so the 35 above are a measurement rather than the exclusion "
          f"restated.")
    return 1 if dud else 0


def openers(g: closure.Grammar, beta: tuple[str, ...]) -> frozenset[str]:
    """FIRST of one production body, stopping at the first non-nullable symbol."""
    out: set[str] = set()
    for s in beta:
        out |= g.spread(s)
        if s not in g.nullable:
            break
    return frozenset(out)


def stranded(walls: list[Wall], keep: dict[tuple[str, int], str]) -> int:
    """What the unownable population is *shaped* like, which decides what it needs.

    A `stranded` wall is a state holding a completed item: a fold could have
    left it, so the refusal may be that fold's consequence and the defect may be
    several constructs upstream. Nothing in the wall's own state can say which.

    The tool this wanted now exists: `joints state <g> --holding '<item>'`
    names the states holding a reading, and `--chain <n>` gives the arrivals and
    the folds. An earlier revision of this docstring said the flag "does not
    exist on this tree" on the strength of `git log -S`, which was wrong for a
    reason worth keeping: **`state.zig` is untracked**, and a history search
    cannot see a file that has never been committed. In a tree where most of
    `src/` is uncommitted, absence from the log is not absence.

    What the two verbs measure is the shape: how many distinct folds the
    population goes through, and how the bytes pile onto them. A population of
    30 walls over 3 folds is a week; over 30 folds it is a project. What they
    **cannot** measure is who owns a wall - see `cut.py`, which found that
    96.3% of the bytes below are the cold peel's own cut rather than a construct
    at all. Read that before sizing anything off this table.

    Grouped **two** ways on purpose, because the two disagree and the first one
    is the one that misleads. By whole item the population is 22 items with 14
    singletons, which reads as "does not collapse". By the *body* a fold is over
    - the item minus its left-hand side - 71% of the bytes are the top two and
    88% are the top three, where two of the three are swift's top-level
    statement separator spelled with and without its repeat. And the second is
    eight walls folding a bare `_identifier` under four competing left-hand
    sides, which is one reduce-reduce family wearing eight faces rather than
    eight defects. A wall in several items is counted in each, so the columns
    overlap; the totals are per-wall and do not.
    """
    mine = [w for w in walls if w.owner == "stranded"]
    item: dict[tuple[str, str], set[str]] = {}
    body: dict[tuple[str, str], list[Wall]] = {}
    for w in mine:
        items, _, _ = rows(dump(w.grammar, w.state, keep))
        for it in (i for i in items if i.endswith(" .")):
            item.setdefault((w.grammar, it), set()).add(w.who)
            lhs, _, rhs = it.partition(" -> ")
            key = (w.grammar, rhs[:-2].strip())
            if w not in body.setdefault(key, []):
                body[key].append(w)
    print(f"\n**{len(mine)} stranded walls, {sum(w.cost for w in mine):,} B.** By whole "
          f"item: {len(item)} distinct, {sum(1 for v in item.values() if len(v) == 1)} of "
          f"them held by exactly one wall. By the body the fold is over:")
    print(f"\n{'grammar':<12}{'completed body':<50}{'walls':>6}{'bytes':>10}  folded as")
    top = sorted(body.items(), key=lambda p: -sum(w.cost for w in p[1]))[:10]
    for (name, rhs), got in top:
        lhs = sorted({i.split(" -> ")[0] for (n, i) in item if n == name
                      and i.partition(" -> ")[2][:-2].strip() == rhs})
        print(f"{name:<12}{rhs[:48]:<50}{len(got):>6}{sum(w.cost for w in got):>10,}  "
              + ", ".join(lhs[:4]) + (" ..." if len(lhs) > 4 else ""))
    fat = {w.who for _, got in top[:2] for w in got}
    share = sum(w.cost for w in mine if w.who in fat)
    print(f"\n**The top two bodies carry {share:,} B of the {sum(w.cost for w in mine):,} "
          f"({100.0 * share / sum(w.cost for w in mine):.0f}%) over "
          f"{len(fat)} walls.** So the population concentrates by byte even though it "
          f"scatters by item, and the item grouping alone would have said the opposite.")
    print("Both instruments this asked for now exist: `joints state <g> --holding "
          "'<item>'` names every state holding a reading, and `--chain <n>` gives the "
          "arrivals, the folds, how far each pops and where its goto lands - flagging a "
          "handle origin wider than one state as frayed. They kill wrong hypotheses in "
          "one step and they do **not** attribute: nothing about a state says how the "
          "parse got its bytes.")
    held = [w for w in mine if w.real]
    made = [w for w in mine if w.made]
    print(f"**What attributes is `cut.py`, and the answer is that most of this table is "
          f"not a construct.** The cold peel restarts in state 0, so after the first wall "
          f"it hands the parser a fragment whose opener it left behind, and the closers "
          f"are refused correctly. Re-priced by provenance rather than by state number: "
          f"{sum(w.cost for w in held):,} B of these {sum(w.cost for w in mine):,} stands "
          f"on the document over {len(held)} wall(s), and {sum(w.cost for w in made):,} B "
          f"over {len(made)} is an instrument's own scissors - `torn` by round 1's canopy "
          f"or an `alias` warm manufactured for itself. The state-number rule this "
          f"paragraph used to quote could not tell those apart, because the state number "
          f"is a count of the statements that came first. See `../reprice/` for the "
          f"predicate and `../strand/` for the population that prompted it.")
    return 0


def externals(want: list[str]) -> int:
    """The declared-external census, and the counterfactual the narrow read cost.

    `closure.declared` reads three shapes; the first spelling of it read one.
    This runs both and prints the difference, so the repair is a number anyone
    can reproduce rather than a sentence in a dossier. The right-hand columns
    are what the narrow read *dropped*, per grammar.
    """
    names = sorted(want) or sorted(p.stem for p in GRAMMARS.glob("*.json"))
    print(f"\n{'grammar':<14}{'decls':>7}{'spellings':>11}{'named':>7}{'dropped':>9}"
          f"  by shape   spellings dropped")
    wide_n = narrow_n = decls = 0
    shapes: dict[str, int] = {}
    hit: list[str] = []
    for name in names:
        g = json.loads((GRAMMARS / f"{name}.json").read_text())
        wide, narrow = closure.declared(g), closure.declared(g, literals=False)
        wide_n, narrow_n = wide_n + len(wide), narrow_n + len(narrow)
        mine: dict[str, int] = {}
        for e in g.get("externals") or ():
            if isinstance(e, dict) and (t := e.get("type")):
                shapes[t] = shapes.get(t, 0) + 1
                mine[t] = mine.get(t, 0) + (t != "SYMBOL")
        if not (miss := wide - narrow):
            continue
        hit.append(name)
        # Declarations, not spellings: one non-SYMBOL entry may answer to two
        # names (`]` and `\]`), and quoting the spelling count as the population
        # is the error this column exists to prevent - it is how the sibling
        # docstring came to read `21 across 8`, a number under a filter nothing
        # here uses.
        n = sum(mine.values())
        decls += n
        show = ", ".join(sorted(miss)[:6]) + (" ..." if len(miss) > 6 else "")
        print(f"{name:<14}{n:>7}{len(wide):>11}{len(narrow):>7}{len(miss):>9}  "
              + f"{'+'.join(f'{k[:3].lower()}{v}' for k, v in sorted(mine.items()) if v):<10} {show}")
    print(f"\n**{decls} non-named declarations across {len(hit)} grammars, worth "
          f"{wide_n - narrow_n} spellings.** The two counts are different units and both "
          f"get quoted: an atom answers to its literal *and* to its escaped render, so "
          f"23 declarations are 31 spellings. Over all {len(names)} grammars the wide "
          f"read sees {wide_n} spellings and the named-only read {narrow_n}.")
    print("Declared by shape: "
          + ", ".join(f"{v} {k}" for k, v in sorted(shapes.items(), key=lambda p: -p[1]))
          + ". `declared()` reads them all - a `SYMBOL` by name, everything else through "
          "`names()` - rather than enumerating the shapes anyone has met, which is how "
          "the `PATTERN` pair nearly got dropped a second time.")
    print("A dropped external is a wall that reads `unowned` when it is `scanner` - work "
          "filed as nobody's. Today the `PATTERN` pair costs 0 B (neither `\\n` is a wall "
          "terminal); bash's `]` cost 495 B when the `STRING` shape was dropped.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Every built byte, filed by what the ORACLE said and by what OUTLINER knew.

`rack.py` answers "is this derivation right" against tree-sitter. That answer is
not available at runtime, is not available on a grammar tree-sitter does not
cover, and is not available on the 34,687 bytes where tree-sitter itself
`ERROR`s. So the question this file exists for is the next one: **does outliner
already know?** If some signal the parse computes for its own reasons lines up
with the regions rack calls misread, outliner can emit a calibrated
*untrustworthy* span - which is tree-sitter's `ERROR`, graded, and covering the
case tree-sitter has no node for at all: a region that parses cleanly and is
wrong.

## The two populations, and why the innocent one is the load-bearing half

    guilty    bytes rack calls `askew` or `racked`, minus the soft ones
    innocent  bytes rack calls `square` or `renamed`
    excluded  soft crooked (extras placement), `unjudged`, `unwindowed`

A signal that fires on 90% of the corpus catches every misread byte and is
worthless, so nothing here reports a recall without the base rate beside it and
the innocent population underneath it. `excluded` is named rather than folded
into either side: a byte the oracle could not adjudicate is not evidence for a
signal and is not evidence against one, and quietly counting it as innocent is
the silence-as-a-zero move this board has been caught on twice.

## It is rack's walk, and it is asserted to be rack's walk

The per-cut classification below is `rack.survey`'s loop with the verdict
recorded per interval instead of summed. That is a second copy of a rule, which
is a defect here even when it is convenient - so `check` re-derives every
grammar's six bucket totals from these spans and compares them against
`rack.survey`'s own `Seen`, field for field. A drift between the two is a
failure of this file, printed as one, rather than a number nobody can trace.

The soft attribution is `rack.soft`'s: a crooked RUN (not a cut) whose bytes are
blank, or whose name on either side is one the grammar declares as an extra.
Run granularity matters - a cut-level test would call the leading spaces of a
non-blank run soft and quietly shrink the defended number.

    python3 research/joinery/flag/spans.py check      the walk against rack's own totals
    python3 research/joinery/flag/spans.py score      precision · recall · base rate
    python3 research/joinery/flag/spans.py show go    the widest guilty runs and their flags
    python3 research/joinery/flag/spans.py prove      every check, asked to say no

    OUTLINER_BIN=<path>   measure a pinned binary (`tool/pin.py`), not `zig-out`

Exit 0 measured, 1 a clean negative, 2 could not run.
"""

from __future__ import annotations

import bisect
import json
import random
import sys
from pathlib import Path
from typing import NamedTuple

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))

import differential as d  # noqa: E402
import plumb  # noqa: E402
import rack  # noqa: E402
import standing  # noqa: E402

CACHE = ROOT / ".local" / "flag" / "sheets.json"

GUILTY = ("askew", "racked")
INNOCENT = ("square", "renamed")
# How near a fell boundary counts as "near a mend". Three, because one is a
# choice and three is a shape: a signal that only works at zero is a signal
# about the boundary byte and not about the region around it.
NEAR = (0, 16, 64)
# A spine this short over a byte is barely a derivation at all.
SHALLOW = 3
# A token this wide is the php `text` shape: one leaf swallowing a construct.
BROAD = 64


class Cut(NamedTuple):
    """One interval of consecutive bytes with one verdict and one flag set."""

    start: int
    end: int
    klass: str
    soft: bool
    flags: frozenset[str]

    @property
    def width(self) -> int:
        return self.end - self.start

    @property
    def guilty(self) -> bool:
        return self.klass in GUILTY and not self.soft

    @property
    def innocent(self) -> bool:
        return self.klass in INNOCENT


class Sheet(NamedTuple):
    name: str
    size: int
    built: int
    cuts: tuple[Cut, ...]
    roots: int
    why: str = ""

    def bytes_of(self, pick) -> int:
        return sum(c.width for c in self.cuts if pick(c))


# --------------------------------------------------------------- what we knew

def externals(grammar: Path) -> set[str]:
    """Terminals the grammar hands to a scanner it expected us to link.

    Read off the grammar's own `externals`, so this is the author's statement
    and not a guess. It conflates two things and the report says so: an
    external outliner seats for real (`marrow`, `fence`, `caesura`) and one it
    only has a spelling for. Both are "this token did not come from a rule in
    the grammar file", which is the question.
    """
    try:
        book = json.loads(grammar.read_text())
    except (OSError, ValueError):
        return set()
    return {e.get("name") or e.get("value") for e in book.get("externals", ())} - {None}


def contested(grammar: Path) -> set[str]:
    """Symbols the AUTHOR declared ambiguous, in the grammar's `conflicts`.

    The control signal of the slate. These are the cells a GLR parser is for -
    the author knew, said so, and the press files them `declared` rather than
    `residual`. If flagging them predicted misreading, the thing being measured
    would be "this grammar is hard" rather than "this parse went wrong here".
    """
    try:
        book = json.loads(grammar.read_text())
    except (OSError, ValueError):
        return set()
    return {s for group in book.get("conflicts", ()) for s in group if isinstance(s, str)}


def sites(mine: list[plumb.Node]) -> list[int]:
    """Where the parse put the stack down: the edges between top-level roots.

    A fell closes the standing stack into roots and begins again past the
    break, so the boundary between two consecutive roots is the only place in
    the tree a mend leaves a mark. Nothing prints a mend's offset, and this is
    the whole of what can be recovered without one.
    """
    top = sorted((n.start, n.end) for n in mine if n.depth == 0)
    return sorted({v for a, b in top for v in (a, b)}) if len(top) > 1 else []


def flags(sp: tuple[rack.Rung, ...], start: int, width: int,
          near: list[int], ext: set[str], said: set[str]) -> frozenset[str]:
    """Everything outliner knew about these bytes, without asking the oracle."""
    out: set[str] = set()
    names = {r.name for r in sp}
    deep = sp[-1] if sp else None
    if names & ext:
        out.add("external")
    if names & said:
        out.add("declared")
    if deep is not None and not deep.named:
        out.add("anon")
    if deep is not None and deep.end - deep.start >= BROAD:
        out.add("broad")
    if len(sp) <= SHALLOW:
        out.add("shallow")
    if near:
        at = bisect.bisect_left(near, start)
        gap = min((abs(near[k] - start) for k in (at - 1, at, at + 1)
                   if 0 <= k < len(near)), default=1 << 30)
        # Measured from the interval, not from its first byte: an interval that
        # straddles a boundary is at distance zero from it.
        gap = 0 if gap <= width else gap - width
        for k in NEAR:
            if gap <= k:
                out.add(f"mend{k}")
        out.add("forest")
    return frozenset(out)


# ------------------------------------------------------------------- the walk

def soften(saw: plumb.Read, seen: rack.Seen, was: set[str]) -> list[tuple[int, int]]:
    """`rack.soft`'s rule, over every crooked run: which of them I would not defend.

    An extra attaches where a parser chooses. tree-sitter swallows a leading
    doc comment into the definition it precedes and outliner keeps it a
    sibling; neither has misread a byte, and a walk over the two spines charges
    every byte of the comment to whichever one it is not on.
    """
    out = []
    for w in seen.worst:
        body = saw.blob[w.start:w.end]
        if not body.strip() or w.ours in was or w.theirs in was:
            out.append((w.start, w.end))
    return sorted(out)


def dissect(case: plumb.Case, saw: plumb.Read, seen: rack.Seen) -> Sheet:
    """`rack.survey`'s classification, one record per interval instead of a sum."""
    size = len(saw.blob)
    t_who, t_bad = plumb.paint(saw.theirs, size), plumb.hurt(saw.theirs, size)
    o_pile, t_pile = rack.inorder(saw.mine), rack.inorder(saw.theirs)
    o_from, t_from = [r.start for r in o_pile], [r.start for r in t_pile]
    edge = sorted({v for r in (*o_pile, *t_pile) for v in (r.start, r.end)})
    ext, said = externals(case.grammar), contested(case.grammar)
    near = sites(saw.mine)
    soft = soften(saw, seen, standing.extras(case.grammar.stem))
    soft_at = [a for a, _ in soft]

    # The window walk twice: once to collect every cut position, once to judge.
    # The full spine - the frame included - is covered in ONE pass over all of
    # them, because covering per window is a scan of the pile per window and
    # haskell has 2,562 of them.
    per: list[tuple[list[int], list[rack.Rung], list[rack.Rung]]] = []
    every: list[int] = []
    for lo, hi, ra, rb in saw.windows:
        cuts = sorted({lo, hi, *edge[bisect.bisect_right(edge, lo):
                                     bisect.bisect_left(edge, hi)]})
        per.append((cuts, rack.within(o_pile, o_from, ra, rb),
                    rack.within(t_pile, t_from, ra, rb)))
        every += cuts[:-1]
    every.sort()
    whole = dict(zip(every, rack.cover(o_pile, every)))

    out: list[Cut] = []
    for (cuts, mine, yours) in per:
        o_sp, t_sp = rack.cover(mine, cuts[:-1]), rack.cover(yours, cuts[:-1])
        for k, p in enumerate(cuts[:-1]):
            wide = cuts[k + 1] - p
            them = saw.theirs[t_who[p]] if t_who[p] >= 0 else None
            # `rack.survey`'s rule verbatim, and it is one test now: `hurt`
            # is asked of the node covering the byte, so the leaf clause this
            # used to carry was the ancestry rule's and nothing else.
            if them is None or t_bad[p]:
                klass = "unjudged"
            elif o_sp[k] == t_sp[k]:
                klass = "square"
            elif not t_sp[k]:
                klass = "unwindowed"
            elif rack.excused(o_sp[k], t_sp[k], saw.renames):
                klass = "renamed"
            else:
                deep = o_sp[k][-1] if o_sp[k] else None
                klass = "racked" if deep == t_sp[k][-1] else "askew"
            at = bisect.bisect_right(soft_at, p) - 1
            mild = klass in GUILTY and at >= 0 and soft[at][1] > p
            out.append(Cut(p, p + wide, klass, mild,
                           flags(whole[p], p, wide, near, ext, said)))
    return Sheet(case.name, size, saw.built, tuple(out),
                 sum(1 for n in saw.mine if n.depth == 0))


def read(case: plumb.Case) -> tuple[Sheet, rack.Seen] | None:
    """One grammar's spans, and the `rack.Seen` they are required to add up to.

    Both, from one parse. `check` compares the two and a second `plumb.read`
    here would double a sweep that already costs minutes - and, worse, would
    compare a walk against a survey of a *different* run of the binary, which
    is the shape of tripwire that passes while measuring nothing.
    """
    saw = plumb.read(case)
    if saw is None:
        return None
    if saw.why:
        return (Sheet(case.name, len(saw.blob), saw.built, (), 0, saw.why),
                rack.blank(case.name, len(saw.blob), saw.built, saw.why))
    seen = rack.survey(case.name, saw, top=1 << 20)
    return dissect(case, saw, seen), seen


def sweep(picked: list[plumb.Case]) -> list[tuple[Sheet, rack.Seen]]:
    return [got for c in picked if (got := read(c)) is not None]


# ----------------------------------------------------------------- the verdict

class Score(NamedTuple):
    flag: str
    hit: int      # guilty bytes flagged
    miss: int     # guilty bytes not flagged
    wrong: int    # innocent bytes flagged
    quiet: int    # innocent bytes not flagged

    @property
    def precision(self) -> float:
        return self.hit / (self.hit + self.wrong) if self.hit + self.wrong else 0.0

    @property
    def recall(self) -> float:
        return self.hit / (self.hit + self.miss) if self.hit + self.miss else 0.0

    @property
    def base(self) -> float:
        """How much of the judged population this fires on at all.

        The column that makes the other two readable. A flag at 100% recall and
        a base rate of 0.95 has said nothing; the same recall at 0.02 is the
        whole finding, and the two are indistinguishable without this.
        """
        tot = self.hit + self.miss + self.wrong + self.quiet
        return (self.hit + self.wrong) / tot if tot else 0.0

    @property
    def prevalence(self) -> float:
        tot = self.hit + self.miss + self.wrong + self.quiet
        return (self.hit + self.miss) / tot if tot else 0.0

    @property
    def lift(self) -> float:
        """Precision over prevalence: how much better than flagging at random."""
        return self.precision / self.prevalence if self.prevalence else 0.0

    def as_dict(self) -> dict:
        return {**self._asdict(), "precision": round(self.precision, 4),
                "recall": round(self.recall, 4), "base": round(self.base, 4),
                "prevalence": round(self.prevalence, 4), "lift": round(self.lift, 2)}


def slate(sheets: list[Sheet]) -> list[str]:
    return sorted({f for s in sheets for c in s.cuts for f in c.flags})


def tally(sheets: list[Sheet], flag: str) -> Score:
    hit = miss = wrong = quiet = 0
    for s in sheets:
        for c in s.cuts:
            lit = flag in c.flags
            if c.guilty:
                hit, miss = (hit + c.width, miss) if lit else (hit, miss + c.width)
            elif c.innocent:
                wrong, quiet = (wrong + c.width, quiet) if lit else (wrong, quiet + c.width)
    return Score(flag, hit, miss, wrong, quiet)


def spread(sheets: list[Sheet], flag: str) -> tuple[float, int, int]:
    """The same signal asked of one grammar at a time: median lift, and where.

    The corpus number is a byte-weighted average, and php and elixir hold 71.6%
    of every guilty byte there is - so a flag that is merely COMMON in those two
    scores well corpus-wide while predicting nothing anywhere. This is the
    check that separates the two, and it is the one this repository's byte
    comparison did not have when it reported 57.7% agreement across a span
    where both parsers were wrong the same way.
    """
    got = []
    for s in sheets:
        r = tally([s], flag)
        if r.hit + r.miss and r.wrong + r.quiet:
            got.append(r.lift)
    if not got:
        return 0.0, 0, 0
    got.sort()
    mid = got[len(got) // 2] if len(got) % 2 else (got[len(got) // 2 - 1]
                                                  + got[len(got) // 2]) / 2
    return mid, sum(v > 1.2 for v in got), len(got)


def scramble(sheets: list[Sheet], seed: int) -> list[Sheet]:
    """The same grammars, the same flags, guilt moved to random bytes inside each.

    `check` proves this file's six buckets equal `rack.survey`'s own on every
    grammar. That is a claim about TOTALS, and every precision on the table is
    a claim about WHICH BYTES - so a per-byte attribution that were scrambled
    inside a grammar would pass all 81 tripwires and make the whole slate
    meaningless. Worse, it would fail in the direction of the conclusion: every
    real signal would score at chance, which is what was observed.

    So: keep each grammar's guilty byte budget, spend it on a shuffled cut
    order, and re-score. A slate whose numbers survive this was never reading
    position; a slate that collapses to 1.00 was. It is the null the corpus
    lift needs and the byte-comparison lane did not have.
    """
    rng = random.Random(seed)
    out = []
    for s in sheets:
        judged = [c for c in s.cuts if c.guilty or c.innocent]
        budget = sum(c.width for c in judged if c.guilty)
        order = judged[:]
        rng.shuffle(order)
        spent, now = 0, {}
        for c in order:
            if spent < budget:
                now[c.start], spent = "askew", spent + c.width
            else:
                now[c.start] = "square"
        out.append(s._replace(cuts=tuple(
            c._replace(klass=now[c.start], soft=False) if c.start in now else c
            for c in s.cuts)))
    return out


def identity(sheets: list[Sheet]) -> Score:
    """The control that is not a signal at all: "this byte is in php or elixir".

    It reads nothing about the parse. If it outscores the slate, then what the
    slate measured is which language a byte is in - and every lift above is a
    fact about this corpus's composition wearing the costume of a prediction.
    """
    worst = sorted(sheets, key=lambda s: -s.bytes_of(lambda c: c.guilty))[:2]
    lit = {s.name for s in worst}
    hit = miss = wrong = quiet = 0
    for s in sheets:
        on = s.name in lit
        for c in s.cuts:
            if c.guilty:
                hit, miss = (hit + c.width, miss) if on else (hit, miss + c.width)
            elif c.innocent:
                wrong, quiet = (wrong + c.width, quiet) if on else (wrong, quiet + c.width)
    return Score("+".join(sorted(lit)), hit, miss, wrong, quiet)


def score(sheets: list[Sheet], as_json: bool) -> int:
    rows = [tally(sheets, f) for f in slate(sheets)]
    excluded = sum(s.bytes_of(lambda c: not c.guilty and not c.innocent) for s in sheets)
    judged = sum(s.bytes_of(lambda c: c.guilty or c.innocent) for s in sheets)
    if as_json:
        print(json.dumps({"row": [r.as_dict() for r in rows], "judged": judged,
                          "excluded": excluded,
                          "grammar": [{"name": s.name, "why": s.why,
                                       "guilty": s.bytes_of(lambda c: c.guilty),
                                       "innocent": s.bytes_of(lambda c: c.innocent)}
                                      for s in sheets]}, indent=2))
        return 0
    guilty = sum(r.hit + r.miss for r in rows[:1]) if rows else 0
    print(f"\n{len(sheets)} grammar(s) · {judged} bytes the oracle adjudicated ·"
          f" {guilty} of them misread ({guilty / judged * 100:.2f}% prevalence)")
    print(f"{excluded} further built bytes are excluded: soft crooked, unjudged, unwindowed."
          f"\nThey are evidence for nothing and are counted as neither.\n")
    print(f"{'signal':<12}{'fires on':>10}{'base':>8}{'precision':>11}{'recall':>9}"
          f"{'lift':>7}{'median':>8}{'>1.2':>7}   what it says")
    print("-" * 118)
    for r in sorted(rows, key=lambda r: -r.lift):
        mid, up, of = spread(sheets, r.flag)
        print(f"{r.flag:<12}{r.hit + r.wrong:>10}{r.base * 100:>7.1f}%"
              f"{r.precision * 100:>10.1f}%{r.recall * 100:>8.1f}%{r.lift:>7.2f}{mid:>8.2f}"
              f"{f'{up}/{of}':>7}   {SAYS[r.flag]}")
    print("\nlift is precision over prevalence: 1.00 is a coin, and a signal at 1.00 with"
          "\na high recall is catching misread bytes only by catching every byte."
          "\n`median` is the same lift computed one grammar at a time, and `>1.2` is how many"
          "\ngrammars it beat the coin on — a corpus lift that its median does not carry is a"
          "\nfact about which two languages hold the guilty bytes.")
    who = identity(sheets)
    print(f"\n{'CONTROL':<12}{who.hit + who.wrong:>10}{who.base * 100:>7.1f}%"
          f"{who.precision * 100:>10.1f}%{who.recall * 100:>8.1f}%{who.lift:>7.2f}"
          f"{'':15}   the byte is in {who.flag} — reads NOTHING about the parse")
    best = max(rows, key=lambda r: r.lift, default=None)
    if best is not None and who.lift >= best.lift:
        print(f"\n  Knowing only which of 30 grammars a byte is in scores {who.lift:.2f} lift,"
              f" against {best.lift:.2f}\n  for the best thing outliner actually knows"
              f" (`{best.flag}`). The slate is measuring the\n  corpus's composition, not the"
              f" parse. Read every number above through that.")
    null(sheets, rows)
    return 0


def null(sheets: list[Sheet], rows: list[Score], seeds: int = 5) -> None:
    """Re-score the whole slate against guilt scattered at random inside each
    grammar, and print how far each signal moved.

    Reading it: a signal whose real lift is far from its scrambled lift IS
    reading position, whatever its absolute number. A signal that scores the
    same either way is reading nothing but how often it fires. The second is
    the more damning result and this table is the only place it is visible -
    every other column on the page is compatible with an attribution that got
    the counts right and the bytes wrong.
    """
    print(f"\nNULL — the same slate over guilt scrambled inside each grammar,"
          f" {seeds} seeds.\nThe guilty byte budget per grammar is preserved; only WHICH bytes"
          f" moves.\n")
    print(f"{'signal':<12}{'real':>8}{'scrambled':>11}{'moved':>9}")
    print("-" * 42)
    fake = [scramble(sheets, s) for s in range(seeds)]
    for r in sorted(rows, key=lambda r: -r.lift):
        got = [tally(f, r.flag).lift for f in fake]
        mid = sum(got) / len(got)
        print(f"{r.flag:<12}{r.lift:>8.2f}{mid:>11.2f}{abs(r.lift - mid):>9.2f}")


SAYS = {
    "external": "a node here is a terminal the grammar hands to a scanner",
    "declared": "a node here is in a conflict the author declared",
    "anon": "the deepest node is an anonymous token",
    "broad": f"the deepest node is >= {BROAD}B wide",
    "shallow": f"the derivation over this byte is <= {SHALLOW} rungs",
    "forest": "the parse handed back more than one root",
    **{f"mend{k}": f"within {k}B of a boundary between two top-level roots" for k in NEAR},
}


def show(sheets: list[Sheet], top: int = 12) -> int:
    for s in sheets:
        bad = sorted((c for c in s.cuts if c.guilty), key=lambda c: -c.width)[:top]
        print(f"\n# {s.name}  {s.built} built · {s.bytes_of(lambda c: c.guilty)} guilty"
              f" · {s.bytes_of(lambda c: c.innocent)} innocent · {s.roots} root(s)")
        if s.why:
            print(f"  no verdict: {s.why}")
        for c in bad:
            print(f"  [{c.start}, {c.end}){c.width:>7}  {' '.join(sorted(c.flags)) or '—'}")
    return 0


# -------------------------------------------------------------------- tripwire

def buckets(s: Sheet) -> dict[str, int]:
    out = dict.fromkeys(
        ("square", "renamed", "askew", "racked", "unjudged", "unwindowed"), 0)
    for c in s.cuts:
        out[c.klass] += c.width
    return out


def check(got: list[tuple[Sheet, rack.Seen]]) -> int:
    """Is this walk still rack's walk? Asked per grammar, field for field.

    The one assertion that has to exist. This file re-implements a
    classification `rack.py` owns, for the sole reason that rack sums it and
    this needs it per interval - and an unwatched second copy of a rule is how
    this repository has arrived at two instruments spelling one word two ways,
    repeatedly and always in the flattering direction.
    """
    out: list[tuple[bool, str]] = []
    for s, want in got:
        if s.why:
            continue
        mine = buckets(s)
        theirs = {"square": want.square, "renamed": want.renamed, "askew": want.askew,
                  "racked": want.racked, "unjudged": want.unjudged,
                  "unwindowed": want.unwindowed}
        off = {k: (mine[k], theirs[k]) for k in theirs if mine[k] != theirs[k]}
        out.append((not off, f"{s.name}: the six buckets match rack's own"
                             + (f" — DRIFTED {off}" if off else
                                f" ({want.square} square, {want.crooked} crooked)")))
        out.append((sum(mine.values()) == want.built,
                    f"{s.name}: and they total `built`: {sum(mine.values())}"
                    f" of {want.built}"))
        hard = s.bytes_of(lambda c: c.guilty)
        out.append((hard <= want.crooked,
                    f"{s.name}: hard crooked {hard} <= rack's crooked {want.crooked}"
                    f" (soft removed {want.crooked - hard})"))
    for held, said in out:
        print(f"{'ok  ' if held else 'FAIL':<6}{said}")
    bad = sum(not h for h, _ in out)
    print(f"\n{len(out) - bad} of {len(out)} held")
    return 1 if bad else 0


# ------------------------------------------------------------------- on disk

def slate_mark() -> str:
    """What the flags MEANT when a sweep was taken.

    The flags are stored rather than re-derived - re-deriving them needs both
    trees, which is the whole cost the cache exists to avoid - so a cache read
    after a threshold moves is a table of numbers computed under a definition
    the reader no longer has. That is the frozen-artifact hazard exactly, so
    the definition rides along and a mismatch refuses rather than reports.
    """
    return json.dumps({"says": sorted(SAYS), "near": NEAR,
                       "shallow": SHALLOW, "broad": BROAD}, sort_keys=True)


def dump(got: list[tuple[Sheet, rack.Seen]]) -> None:
    """Keep the sweep, because it costs minutes and the scoring is iterated."""
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text(json.dumps({"slate": slate_mark(), "sheet": [
        {"name": s.name, "size": s.size, "built": s.built, "roots": s.roots, "why": s.why,
         "cuts": [[c.start, c.end, c.klass, c.soft, sorted(c.flags)] for c in s.cuts],
         "seen": w.as_dict()} for s, w in got]}))


def load() -> list[Sheet]:
    got = json.loads(CACHE.read_text())
    if got.get("slate") != slate_mark():
        raise ValueError("this cache was taken under a different flag slate; re-sweep")
    return [Sheet(r["name"], r["size"], r["built"],
                  tuple(Cut(a, b, k, m, frozenset(f)) for a, b, k, m, f in r["cuts"]),
                  r["roots"], r["why"]) for r in got["sheet"]]


def prove(sheets: list[Sheet]) -> int:
    """Break each claim on purpose and require the check to notice.

    A gate nobody has watched fail is decoration, so every assertion below is
    fed a corrupted input first and has to say no about it.
    """
    out: list[tuple[bool, str]] = []
    good = [s for s in sheets if not s.why and s.cuts]
    out.append((bool(good), f"there is something to prove against: {len(good)} sheet(s)"))
    if not good:
        return 1
    s = good[0]

    # A sheet whose verdicts are shuffled must not still total rack's buckets.
    bent = s._replace(cuts=tuple(c._replace(klass="square") for c in s.cuts))
    moved = sum(c.width for c in bent.cuts if c.klass == "square") \
        != sum(c.width for c in s.cuts if c.klass == "square")
    out.append((moved or all(c.klass == "square" for c in s.cuts),
                f"calling every cut `square` moves {s.name}'s square total, so `check`"
                f" has something to catch"))

    # A flag that fires everywhere must score a lift of 1.00, not a good
    # precision. This is the failure mode the whole method section is about.
    every = [x._replace(cuts=tuple(c._replace(flags=frozenset({"ALL"})) for c in x.cuts))
             for x in good]
    all_r = tally(every, "ALL")
    out.append((abs(all_r.lift - 1.0) < 1e-9 and all_r.recall == 1.0,
                f"a flag that fires on every byte scores recall {all_r.recall * 100:.0f}%"
                f" and lift {all_r.lift:.2f} — the shape a report would misread as a hit"))

    # And a flag that fires on nothing must be visibly empty rather than
    # perfect: 0/0 precision is not 100%.
    none = [x._replace(cuts=tuple(c._replace(flags=frozenset()) for c in x.cuts))
            for x in good]
    nil = tally(none, "NONE")
    out.append((nil.precision == 0.0 and nil.recall == 0.0 and nil.base == 0.0,
                "a flag that fires on nothing scores 0 precision and 0 recall, not an"
                " empty 100%"))

    # An oracle-silent byte must be in neither population, or every "innocent
    # control" claim in the report is counting unadjudicated bytes as innocent.
    mute = Cut(0, 10, "unjudged", False, frozenset())
    out.append((not mute.guilty and not mute.innocent,
                "an `unjudged` byte is neither guilty nor innocent, so the control"
                " population is proven-right bytes and not merely un-accused ones"))

    # And a soft crooked byte is excluded from `guilty` rather than defended.
    lax = Cut(0, 10, "askew", True, frozenset())
    out.append((not lax.guilty and not lax.innocent,
                "a soft crooked byte (extras placement) is excluded from `guilty`, so the"
                " defended number is what the signals are scored against"))

    for held, said in out:
        print(f"{'ok  ' if held else 'FAIL':<6}{said}")
    bad = sum(not h for h, _ in out)
    print(f"\n{len(out) - bad} of {len(out)} held")
    return 1 if bad else 0


def oops(msg: str) -> int:
    print(f"spans.py: {msg}", file=sys.stderr)
    return 2


def main(argv: list[str]) -> int:
    as_json, cached = "--json" in argv, "--cached" in argv
    bare = [a for a in argv if not a.startswith("-")]
    verb, want = (bare[0] if bare else ""), set(bare[1:])
    if "-h" in argv or "--help" in argv or not verb:
        print(__doc__)
        return 0 if verb or "-h" in argv or "--help" in argv else 2
    if verb not in ("check", "score", "show", "prove"):
        return oops(f"no such verb {verb!r}; try check, score, show, prove")
    if cached:
        if verb == "check":
            return oops("`check` compares this walk against a survey of the SAME parse;"
                        " a cached sheet cannot be checked against a run it did not come"
                        " from. Re-sweep.")
        if not CACHE.exists():
            return oops(f"nothing cached at {CACHE}; run without --cached once")
        try:
            sheets = [s for s in load() if not want or s.name in want]
        except (ValueError, KeyError, TypeError) as bad:
            return oops(str(bad))
        return {"prove": lambda: prove(sheets), "show": lambda: show(sheets)}.get(
            verb, lambda: score(sheets, as_json))()
    if not plumb.BIN.exists():
        return oops(f"no binary at {plumb.BIN}; run `zig build` first")
    known = {c.name for c in plumb.slate()}
    if stray := sorted(want - known):
        return oops(f"no grammar named {', '.join(stray)}; there are {len(known)}")
    if not d.oracle_ready():
        return oops(f"no tree-sitter CLI at {d.TS}; there is nothing to compare against")
    got = sweep([c for c in plumb.slate() if not want or c.name in want])
    if not got:
        return oops("no grammar resolved to a folio and a source")
    if not want:
        dump(got)
    sheets = [s for s, _ in got]
    if verb == "check":
        return check(got)
    if verb == "prove":
        return prove(sheets)
    if verb == "show":
        return show(sheets)
    return score(sheets, as_json)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Does joints's query answer tree-sitter's?

`gloss` could compile a `.scm` for months before it could run one, so the
compiler was tested against its own output and against no tree at all - the
strongest possible guarantee that a query compiles, and none whatsoever that it
finds anything. `scribe` closed that with fifteen hand-written tests, and those
tests have the same hole one rung up: **they assert what I believed
tree-sitter's semantics were.** Greedy quantifiers, an anchor that skips
comments, a bare supertype standing where a kind goes - each of those is a call
I made from reading, and a test I write from the same reading agrees with me
whether or not I was right.

This is the oracle. `tree-sitter query` takes the same two files and prints the
same kind of answer, so both engines can be asked the same question over the
same corpus and the answers diffed. It is the query half of what
`differential.py` already does for trees, and it borrows that file's whole
apparatus - the per-lane seat, the generated parser, the row-to-byte arithmetic,
the regexes that read their printer's output - rather than keeping a second copy
of any of it.

**The two engines must be holding the same grammar or none of this means
anything.** `oracle_build` copies `upstream/grammars/<name>.json` into the
oracle's own tree and regenerates its parser whenever the digest differs, so the
comparison is against a parser built from the bytes our press read, not against
whatever was on the machine.

What a disagreement can be, and none of the four is automatically ours:

  ours-refused    we would not compile a query they ran. Real ones live here:
                  a keyword token that exists for them and not for us.
  theirs-refused  they would not compile a query we ran, which is us being
                  laxer than the incumbent and is a finding in its own right.
  unparsed        our PARSER did not accept the file, so the query answered
                  correctly about a forest. A tree finding wearing a query
                  costume; `differential.py` is where it belongs.
  missing         they captured something at a span where we captured nothing.
  surplus         we captured something they did not.

Captures are compared as a **multiset of `(name, start, end)`**, sorted, so
match order is not a variable. Order is a real property and a weaker one; it
gets its own row (`sequence`) rather than being folded in, because an engine
that finds every capture in a different order is a different problem from one
that finds different captures.

Predicates are handed `--foreign=admit`, which is what their CLI does with a
filter it does not implement. Left at our default of `refuse` we would decline
half the corpus and call it a clean run.

  python3 tool/glance.py              every grammar with a query set; exit 1 on a
                                      disagreement
  python3 tool/glance.py --only go    one grammar
  python3 tool/glance.py --json       the whole answer as one object
  python3 tool/glance.py --list       what would be compared, without running it
  python3 tool/glance.py --verbose    every disagreement, not the first few
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path
from typing import NamedTuple

TOOL = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOL))

from differential import (  # noqa: E402
    BIN, CORPUS, GRAMMARS, QCAPTURE, QPATTERN, TS, WORK, Lines, cli, gripe,
    oracle_build, oracle_home, oracle_ready,
)
from rung1 import pairs  # noqa: E402

ROOT = TOOL.parent
# Harvested from the grammars' own repositories, and machine-local: they are
# somebody else's files and the corpus they came from moves. `--list` says what
# it found rather than asserting a count, so a thinner checkout is a smaller run
# and never a failure.
QUERIES = ROOT / ".local" / "glossprobe" / "queries"
# Long enough for a cold `tree-sitter generate` on the heaviest grammar in the
# set, which is minutes on c and cpp, and short enough that a wedged child does
# not own the terminal.
PATIENCE = 600
# How many disagreements a row prints before it stops, absent `--verbose`. A
# query that diverges usually diverges everywhere, and a hundred identical lines
# bury the row underneath that has one.
SHOWN = 4


class Case(NamedTuple):
    """One question asked of both engines."""

    lang: str
    scm: Path
    source: Path

    @property
    def query(self) -> str:
        """The query's name without the language prefix the harvest glued on."""
        return self.scm.name.split("__", 1)[-1].removesuffix(".scm")

    @property
    def where(self) -> str:
        return f"{self.lang}/{self.query}"


class Hit(NamedTuple):
    name: str
    start: int
    end: int


class Verdict(NamedTuple):
    case: Case
    kind: str  # agree · sequence · ours-refused · theirs-refused · unparsed · differ
    ours: int
    theirs: int
    detail: list[str]

    @property
    def ok(self) -> bool:
        return self.kind == "agree"


def cases(only: str | None) -> list[Case]:
    """Every (grammar, query, source) triple there is evidence for.

    The corpus README owns which file belongs to which grammar and `rung1.pairs`
    reads it, so a language added there is compared here with nothing to update.
    A grammar with no harvested queries is simply absent rather than a hole to
    report: the query set is not ours and its coverage is not a claim we make.
    """
    out = []
    for lang, filename in pairs():
        if only and lang != only:
            continue
        source = CORPUS / filename
        for scm in sorted(QUERIES.glob(f"{lang}__*.scm")):
            out.append(Case(lang, scm, source))
    return out


def theirs_of(case: Case, lang: Path) -> tuple[list[Hit], str]:
    """What tree-sitter captures, and why it would not say.

    Their printer has two forms and `QCAPTURE` in `differential.py` knows both -
    a capture spanning more than one row loses its index and its text tail. Read
    through that regex rather than a local one, because the fact is theirs and
    one file should hold it.
    """
    got = cli([str(TS), "query", "-p", str(lang), str(case.scm), str(case.source)], WORK)
    if got.returncode != 0:
        return [], gripe(got.stderr)
    at = Lines(case.source.read_bytes())
    hits = []
    for line in got.stdout.splitlines():
        if QPATTERN.match(line):
            continue
        if m := QCAPTURE.match(line):
            hits.append(Hit(m[1], at.off(int(m[2]), int(m[3])), at.off(int(m[4]), int(m[5]))))
    return hits, ""


def ours_of(case: Case) -> tuple[list[Hit], str, bool]:
    """What joints captures, why it would not say, and whether the tree was sound.

    `--foreign=admit` because their CLI does not filter on a predicate it cannot
    run either, and a differential whose two sides are answering different
    questions is worse than none.

    The third answer is the one that keeps this tool honest. A query run over a
    forest our parser gave up on is a correct answer to the wrong tree, and every
    capture it misses would otherwise be filed against the matcher. `sound` rides
    the `--json` object for exactly this.
    """
    got = cli([str(BIN), "query", str(GRAMMARS / f"{case.lang}.json"), str(case.scm),
               str(case.source), "--json", "--foreign=admit"], ROOT)
    body = got.stdout.strip()
    if not body:
        return [], gripe(got.stderr), True
    try:
        doc = json.loads(body.splitlines()[0])
    except json.JSONDecodeError as bad:
        return [], f"unreadable answer: {bad}", True
    hits = [Hit(c["name"], c["start"], c["end"])
            for m in doc["matches"] for c in m["captures"]]
    return hits, "", bool(doc.get("sound", True))


def compare(case: Case, lang: Path) -> Verdict:
    theirs, why_theirs = theirs_of(case, lang)
    ours, why_ours, sound = ours_of(case)

    # A refusal on either side is the whole answer; there is nothing to diff.
    # Both refusing is agreement, and it is the commonest honest outcome on a
    # harvested corpus, where a query is often newer than the pinned grammar.
    if why_ours and why_theirs:
        return Verdict(case, "agree", 0, 0, [f"both refused: {why_ours}"])
    if why_ours:
        return Verdict(case, "ours-refused", 0, len(theirs), [why_ours])
    if why_theirs:
        return Verdict(case, "theirs-refused", len(ours), 0, [why_theirs])

    mine, yours = Counter(ours), Counter(theirs)
    if mine == yours:
        # Same captures, and now the weaker question: in the same order?
        kind = "agree" if ours == theirs else "sequence"
        return Verdict(case, kind, len(ours), len(theirs), [])

    # Agreeing over a forest would be luck, so soundness is only asked about
    # once the answers already differ. It says whose problem this is: not the
    # matcher's, and not fixable here.
    if not sound:
        return Verdict(case, "unparsed", len(ours), len(theirs),
                       ["our parse did not accept this file; the query ran over a forest"])

    detail = []
    for hit, n in (yours - mine).items():
        detail.append(f"missing  {hit.name} [{hit.start}, {hit.end})" + (f" x{n}" if n > 1 else ""))
    for hit, n in (mine - yours).items():
        detail.append(f"surplus  {hit.name} [{hit.start}, {hit.end})" + (f" x{n}" if n > 1 else ""))
    detail.sort()
    return Verdict(case, "differ", len(ours), len(theirs), detail)


def warm(picked: list[Case]) -> dict[str, Path]:
    """Bring every grammar's oracle up to the bytes our press reads.

    Once per language rather than once per case; `oracle_build` is idempotent
    and takes the shared lock itself, so this is a queue and not a race.
    """
    homes: dict[str, Path] = {}
    for lang in sorted({c.lang for c in picked}):
        home = oracle_home(lang)
        oracle_build(home, GRAMMARS / f"{lang}.json")
        homes[lang] = home
    return homes


def report(rows: list[Verdict], verbose: bool) -> None:
    wide = max((len(r.case.where) for r in rows), default=20) + 2
    print(f"{'query':<{wide}}{'ours':>7}{'theirs':>8}  verdict")
    for r in rows:
        print(f"{r.case.where:<{wide}}{r.ours:>7}{r.theirs:>8}  {r.kind}")
        shown = r.detail if verbose else r.detail[:SHOWN]
        for line in shown:
            print(f"      {line}")
        if len(r.detail) > len(shown):
            print(f"      ... and {len(r.detail) - len(shown)} more (--verbose)")

    tally = Counter(r.kind for r in rows)
    print()
    print("  ".join(f"{k} {v}" for k, v in sorted(tally.items())) or "nothing compared")
    bad = [r for r in rows if not r.ok]
    if not bad:
        print(f"{len(rows)} query/source pair(s), no disagreement")


def main(argv: list[str]) -> int:
    if "--help" in argv or "-h" in argv:
        print(__doc__)
        return 0
    verbose = "--verbose" in argv
    as_json = "--json" in argv
    only = None
    if "--only" in argv:
        at = argv.index("--only")
        if at + 1 >= len(argv):
            print("glance.py: --only wants a grammar name", file=sys.stderr)
            return 2
        only = argv[at + 1]

    if not QUERIES.is_dir():
        print(f"glance.py: no query corpus at {QUERIES}", file=sys.stderr)
        return 2
    picked = cases(only)
    if not picked:
        print(f"glance.py: nothing to compare{f' for {only}' if only else ''}", file=sys.stderr)
        return 2
    if "--list" in argv:
        for c in picked:
            print(f"{c.where:<40}{c.source.relative_to(ROOT)}")
        print(f"\n{len(picked)} pair(s) over {len({c.lang for c in picked})} grammar(s)")
        return 0

    if not BIN.exists():
        print(f"glance.py: no joints binary at {BIN}; `zig build`", file=sys.stderr)
        return 2
    if not oracle_ready():
        print("glance.py: no tree-sitter CLI; `python3 tool/differential.py install`",
              file=sys.stderr)
        return 2

    try:
        homes = warm(picked)
    except (ValueError, subprocess.SubprocessError) as bad:
        print(f"glance.py: could not build an oracle: {bad}", file=sys.stderr)
        return 2

    rows = [compare(c, homes[c.lang]) for c in picked]
    if as_json:
        print(json.dumps({"pairs": [
            {"lang": r.case.lang, "query": r.case.query,
             "source": str(r.case.source.relative_to(ROOT)),
             "kind": r.kind, "ours": r.ours, "theirs": r.theirs, "detail": r.detail}
            for r in rows]}, indent=2))
    else:
        report(rows, verbose)
    return 0 if all(r.ok for r in rows) else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

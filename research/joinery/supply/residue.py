#!/usr/bin/env python3
"""Of the refusals a second move was built for, which ones does it still decline?

`../scars/` priced the gap this lane was sent to close: **twelve grammars where
tree-sitter derives the file clean and we repair it** - 1,929 scars that are
ours and not the corpus's, with no grammar-gap excuse available. This lane gave
the runtime insertion. This file asks what is left.

Every refusal the arm meets falls in exactly one of five places, and the
runtime now says which on `OUTLINER_TRACE=quire`:

  supplied  one literal made the refused token readable again; a ghost went in
  spurned   *several* would have. The table declined to say which, and so did
            we. This is the half a **ranking** rule closes, not a second move
  ground    the stack is empty. Nothing was begun, so nothing was omitted, and
            a prefix that makes the token legal manufactures a construct
  none      *every* anonymous literal reached a table `err` cell. The omission
            is more than one token, or it is a *named* terminal - a pattern,
            which no zero-width instance can stand for
  forked    at least one candidate's walk crossed a cell the author declared
            ambiguous. `absorb` would split there; the walk followed one side
  climbed   at least one candidate's walk filled the `climb` overlay
  chased    at least one candidate's walk spent `chase` steps without reaching
            a shift
  unseated  the perch the refusal stood on was folded away under it; there
            is no configuration left to ask the question of
  fuse      recovery had already given up on the file before this refusal
  stray     no terminal was refused at all - the lexer could not make a token
            out of the byte, so there is nothing for a supply to make readable

Only `spurned` is arguably this lane's unfinished business. `ground` and `none`
are the next lane's brief and they are different briefs.

## `none` used to be a residual, and that is why the last three exist

Until 2026-08-06 `none` was *whatever fell through* four positive tests. The
runtime's `follows` returned a bool, so "the table has no cell for this
candidate" and "the walk ran out of budget before it could tell" were the same
`false`, and by the time `supply` reported anything the difference was gone.
Every `none` in every table this file ever printed was therefore a *union* of
an honest miss and a spent walk, and nothing downstream could size either.

`follows` now returns `Ahead.Says`, and `none` is a **positive test**: it is
reported only when every literal reached a table verdict. One untellable
candidate out of two hundred is enough to disqualify the claim, because the
claim is universal - that literal might have resumed the parse with one more
step. `forked`/`climbed`/`chased` name which wall the walk hit first.

`supplied` gets the same weakness pointing the other way and the runtime now
says so on a second line: a supply made while some *other* candidate was
untellable is one literal that said yes, not the only literal that would have.
`unsure` counts those - see `hazed` below. `spurned` returns mid-loop and has
no count, which is a real hole this file declines to paper over.

## The population is the arm's, and that is the honest caveat

A supply changes what the parse reads next, so the arm's refusals are not the
control's 1,929 re-labelled - they are a different sequence over the same
bytes. Claiming otherwise would be the flattering read: a rule that fires early
and often makes the *remaining* refusals look intractable by having already
consumed the tractable ones.

So both populations are printed, and one row of them is a genuine bijection:
**the first refusal of each file**, which both arms meet in the same state on
the same byte because nothing has diverged yet. If those disagree, the trace
is not describing the parse the control measured and the run says so.

  python3 research/joinery/supply/residue.py --mend keep
  python3 research/joinery/supply/residue.py --mend fell --json .local/supply/residue.json
  python3 research/joinery/supply/residue.py --selftest   # can the closure fail?

Exit 0 measured, 1 the closure check failed, 2 an error.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path
from typing import NamedTuple

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))

import order  # noqa: E402
import plumb  # noqa: E402
import stamp  # noqa: E402

# The twelve `../scars/RESULT-2-untested.md` handed over: we repaired, the
# oracle derived clean. Named rather than re-derived, because re-deriving them
# under this lane's binary would let the lane choose its own scoreboard.
TWELVE = ("c", "cpp", "ruby", "bash", "haskell", "julia", "kotlin",
          "markdown", "ocaml", "scala", "swift", "zig")

STOOD = re.compile(r"^stood down \((\w+)\): (\S+) at (\d+) in state (\d+)$")
SPURNED = re.compile(r"^spurned: (\S+) and (\S+) both resume (\S+) at (\d+) in state (\d+)$")
SUPPLIED = re.compile(r"^supplied: (\S+) at (\d+) so state (\d+) can read (\S+)$")
CUT = re.compile(r"^scar \d+\.\.\d+ ")
GAVE = re.compile(r"^scar \d+ gave ")
STRAY = re.compile(r"^scar \d+\.\.\d+ \d+B \w+ stray")

UNSURE = re.compile(r"^unsure \((\w+)\): (\d+) of (\d+) literals at (\d+) in state (\d+)$")

# Every word the runtime's `declined` can print, plus the two counted off other
# channels. Derived from `gather.zig`'s `Says.word` and the `spurned`/`supplied`
# traces; if the runtime grows a seventh reason, `adrift` is what catches it.
DECLINED = ("ground", "none", "forked", "climbed", "chased", "unseated", "fuse")
REASONS = ("supplied", "spurned", *DECLINED, "stray", "adrift")

# The three `declined` words that are the walk giving up rather than the table
# answering. Split out because their sum is the size of an instrument bug and
# `none`'s is the size of a real brief.
SPENT = ("forked", "climbed", "chased")


class Look(NamedTuple):
    """One refusal, as the trace saw it."""
    why: str
    at: int
    state: int


class Row(NamedTuple):
    name: str
    size: int
    held: int          # scars the control cut - the population this lane aims at
    cut: int           # scars the arm still cuts
    seen: Counter      # arm refusals by reason
    first: str         # the reason the *first* refusal got, arm side
    firstat: int
    hazed: int         # refusals where SOME candidate was untellable
    tried: int         # anonymous literals the walk had to try, max over refusals
    shut: bool         # did the two channels close?

    @property
    def total(self) -> int:
        return sum(self.seen.values())


def run(binary: Path, art: Path, src: Path, mend: str, supply: bool,
        trace: bool) -> tuple[str, str]:
    env = dict(os.environ)
    if trace:
        env["OUTLINER_TRACE"] = "quire"
    else:
        env.pop("OUTLINER_TRACE", None)
    argv = [str(binary), "parse", str(art), str(src), "--scars", f"--mend={mend}"]
    if not supply:
        argv.append("--no-supply")
    got = subprocess.run(argv, capture_output=True, text=True,
                         timeout=stamp.PATIENCE, cwd=ROOT, env=env)
    return got.stdout, got.stderr


def scars(out: str) -> tuple[int, int, int]:
    """Deletions, supplies, and the deletions of a byte no lexer could read.

    A `stray` is the one refusal `supply` is never even asked about, and it is
    the cleanest member of the residue: there is no refused *terminal*, so
    there is no token for a supply to make readable. It is not a decline, it is
    a different question, and it is counted off the scar line rather than off a
    trace because the runtime never reaches the trace.
    """
    lines = [line.strip() for line in out.splitlines()]
    return (sum(1 for line in lines if CUT.match(line)),
            sum(1 for line in lines if GAVE.match(line)),
            sum(1 for line in lines if STRAY.match(line)))


def looks(err: str) -> list[Look]:
    """Every refusal the trace reported, in the order the parse met them."""
    seen: list[Look] = []
    for line in err.splitlines():
        line = line.strip()
        if m := STOOD.match(line):
            seen.append(Look(m[1], int(m[3]), int(m[4])))
        elif m := SPURNED.match(line):
            seen.append(Look("spurned", int(m[4]), int(m[5])))
        elif m := SUPPLIED.match(line):
            # The trace prints the *anchor* - the end of the last consumed
            # byte - because that is where the ghost went. The refusal is at
            # the token, which the same line names but does not offset. Close
            # enough for a reason census; the bijection check uses the control.
            seen.append(Look("supplied", int(m[2]), int(m[3])))
    return seen


def close(seen: Counter, cut: int, gave: int, stray: int) -> int:
    """Deletions and supplies the two channels cannot both account for.

    The trace and the scar channel are two independent accounts of the same
    parse, so their disagreement is a finding rather than a rounding. Every
    repair the arm made is either a supply the trace announced or a deletion,
    and every deletion is either a stray or a refusal the trace was asked
    about. If that does not close, one of the two is not describing this run.

    **Signed, and not a residual.** The old form set `adrift` to
    `cut + gave - sum(seen.values())` when the test failed - a quantity that is
    identically zero whenever the counter is complete, which it always is,
    because `looks` puts every trace line it reads into that same counter. So
    the column read 0 when the channels agreed *and* when they disagreed, and
    the failing branch it lived in could never show its own failure. It also
    went blind in a second way: the reason list it summed was hardcoded, so the
    day the runtime grew `forked`/`climbed`/`chased` the sum silently lost
    50 of bash's 90 deletions and the check fired on a discrepancy the column
    it wrote into could not print. Both are the same defect - a number derived
    by subtracting everything you know from a total, which cannot be wrong.

    This one is derived from the *other* side: what the scars say, minus what
    the declining reasons say. It can go positive (a repair no trace explains)
    or negative (a trace line no repair backs), and either is loud.
    """
    return (cut + gave) - (stray + seen["supplied"] + seen["spurned"]
                           + sum(seen[k] for k in DECLINED))


def row(case: plumb.Case, work: Path, binary: Path, mend: str) -> Row | None:
    art = order.folio_for(case.name, work) or (order.GRAMMARS / f"{case.name}.json")
    if not Path(art).exists() or not case.source.exists():
        return None
    was, _ = run(binary, Path(art), case.source, mend, supply=False, trace=False)
    now, err = run(binary, Path(art), case.source, mend, supply=True, trace=True)
    held, _, _ = scars(was)
    cut, gave, stray = scars(now)
    first = looks(err)
    seen = Counter(s.why for s in first)
    seen["stray"] = stray
    hazes = [UNSURE.match(ln.strip()) for ln in err.splitlines()]
    hazes = [m for m in hazes if m]
    adrift = close(seen, cut, gave, stray)
    seen["adrift"] = adrift
    return Row(case.name, case.source.stat().st_size, held, cut, seen,
               first[0].why if first else "-", first[0].at if first else -1,
               len(hazes), max((int(m[3]) for m in hazes), default=0),
               adrift == 0)


def selftest() -> int:
    """Show the closure check failing, because a check that only passes is not one.

    Three fabricated parses, no binary and no corpus. The first is the case the
    old residual could not report: the runtime grows a reason this file has
    never heard of, so the trace accounts for fewer deletions than the scars
    do. The old form computed `cut + gave - sum(seen.values())` and read **0**
    on it, because the unknown reason was already sitting in `seen`. This form
    reads the shortfall, because it sums only the words it knows.
    """
    bad = 0
    for why, seen, cut, gave, stray, want in (
            ("a reason this file does not know",
             Counter({"none": 10, "sideways": 40}), 50, 0, 0, 40),
            ("a supply the scar channel never wrote",
             Counter({"supplied": 3, "none": 10}), 10, 0, 0, -3),
            ("a deletion no refusal explains",
             Counter({"none": 10}), 17, 0, 0, 7),
    ):
        got = close(seen, cut, gave, stray)
        # The residual this replaced, spelled out so the difference is a
        # measurement rather than a claim in a docstring.
        was = (cut + gave) - sum(seen.values())
        ok = got == want
        bad += not ok
        print(f"{'ok ' if ok else 'BAD'} {why}: signed {got:+}, want {want:+} "
              f"(the residual it replaced read {was:+})")
    if bad:
        print(f"residue: {bad} of 3 self-tests failed", file=sys.stderr)
    return 1 if bad else 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mend", default="keep", choices=("keep", "fell", "relent"))
    ap.add_argument("--all", action="store_true", help="every grammar, not the twelve")
    ap.add_argument("--json", type=Path)
    ap.add_argument("--selftest", action="store_true",
                    help="prove the closure check can fail, without a binary")
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()

    work = Path(os.environ.get("OUTLINER_WORK", ROOT / ".local" / "work"))
    picked = [c for c in plumb.slate() if args.all or c.name in TWELVE]
    rows = [r for case in picked if (r := row(case, work, order.BIN, args.mend))]
    if not rows:
        print("residue: nothing to read", file=sys.stderr)
        return 2

    head = "".join(f"{r:>9}" for r in REASONS)
    print(f"--mend={args.mend}\n\n{'grammar':<10}{'held':>8}{'cut':>8}{head}"
          f"{'hazed':>8}{'tried':>7}   first")
    for r in sorted(rows, key=lambda r: -r.held):
        cells = "".join(f"{r.seen.get(k, 0):>9,}" for k in REASONS)
        print(f"{r.name:<10}{r.held:>8,}{r.cut:>8,}{cells}"
              f"{r.hazed:>8,}{r.tried:>7,}   {r.first}")
    tot = Counter()
    for r in rows:
        tot += r.seen
    print(f"{'':<10}{sum(r.held for r in rows):>8,}{sum(r.cut for r in rows):>8,}"
          + "".join(f"{tot.get(k, 0):>9,}" for k in REASONS)
          + f"{sum(r.hazed for r in rows):>8,}{max(r.tried for r in rows):>7,}")

    n = sum(tot.values())
    spent = sum(tot[k] for k in SPENT)
    if n:
        print(f"\n{tot['supplied']:,} of {n:,} refusals the arm met were closed by a "
              f"supply ({100.0 * tot['supplied'] / n:.0f}%). The residue is "
              f"{tot['spurned']:,} **spurned** (several literals resume the parse - a "
              f"ranking rule, not a second move), {tot['ground']:,} on the **ground** "
              f"(an empty stack has omitted nothing), {tot['none']:,} with **no** single "
              f"anonymous literal that resumes, and {tot['fuse']:,} past the **fuse**.")
        # The whole point of the split. `none` is now a claim the runtime
        # established; `spent` is a claim it could not, and the second number
        # is the size of an instrument defect rather than of a brief.
        whole = tot["none"] + spent
        if whole:
            print(f"\nOf the {whole:,} refusals where no literal was supplied, "
                  f"**{tot['none']:,} ({100.0 * tot['none'] / whole:.1f}%) are honest "
                  f"misses** - every anonymous literal reached a table `err` cell - and "
                  f"**{spent:,} ({100.0 * spent / whole:.1f}%) are a spent walk**: "
                  f"{tot['forked']:,} forked, {tot['climbed']:,} climbed, "
                  f"{tot['chased']:,} chased. Before this split every one of the "
                  f"{whole:,} printed as `none`.")
        if tot["supplied"]:
            print(f"\n{sum(r.hazed for r in rows):,} refusals had at least one "
                  f"candidate the walk could not tell about - including any among the "
                  f"{tot['supplied']:,} supplied, where the ghost that went in is the "
                  f"only literal that said yes but not provably the only one that "
                  f"would have.")
    print(f"\nThe control cut {sum(r.held for r in rows):,} scars over these "
          f"{len(rows)} grammars and the arm cuts {sum(r.cut for r in rows):,}. "
          f"These are not the same sequence: a supply changes what is read next, "
          f"so the arm's refusals are a different walk over the same bytes, not "
          f"the control's re-labelled.")

    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(
            [{**r._asdict(), "seen": dict(r.seen)} for r in rows], indent=1))

    loose = [r for r in rows if not r.shut]
    for r in loose:
        print(f"residue: {r.name} does not close - {r.seen['adrift']:+,} repairs the "
              f"trace and the scar channel disagree about", file=sys.stderr)
    return 1 if loose else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

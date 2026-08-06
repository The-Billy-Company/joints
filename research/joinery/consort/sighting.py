#!/usr/bin/env python3
"""What fraction of the written record has asked a second parser, and is it rising.

`onlydamage.py` answers *which pages* are blind and ranks them for repair. This
answers the two questions that come after: **how much of the record is sighted
now**, and **is the blind population a fixed backlog or one that regrows** — the
second being the only one that decides whether the fix belongs on a page or
upstream of every page.

It agrees with `onlydamage.py` on the classification and adds one thing to it: a
**table-aware** reading of the oracle's columns. The triage's proximity regex
deliberately refuses to cross a `|`, so a page that reports

    | ...of built, the oracle adjudicates | 27,598 |
    | ...of those, **`square`** | **2,184** |

reads as blind while being the most sighted paragraph on the tree — the column
name and its number are in different cells. Every correction this lane wrote is
in that shape, so a sweep that could not see it would have scored its own work
as no work. The extra pass reads a markdown row's cells and pairs a name cell
with a number cell in the same row.

**Sighted is not attributed.** Naming the oracle says the figure was compared
against a second parser; it does not say *which tree* it was compared on. Four
pages published a corpus `square` total this morning - 311,540, 313,440 and
309,356 - and all of them are sighted, and none of them is wrong, and they
disagree by 1,900 bytes because a cpp fix landed between them. Two of the three
(`RESULT-4-borrow.md`, `RESULT-8-sighted.md`) carry no digest of any kind. So
the gate reads a **second, orthogonal axis**:

  `stamped`  the page names a tree or a binary somewhere on it - any digest of
             seven or more hex characters with a letter in it, which is how
             every attributed page on this tree writes one (`outliner f6a34cd7c`,
             `repo f7ba40004+55`, `tree c0cdbde69`, a `stamp:` line).

A page can be sighted and unstamped (this morning's three), stamped and blind
(`walls/README.md`), both, or neither.

**Only the stamp axis blocks.** `--rate` adjudicates a seeded, axis-stratified
sample of the refusals by hand: the stamp axis is false 6.9% of the time
[1.9%, 22.0%] and the blind axis is false 60% [35.7%, 80.2%] where it refuses
alone. So the blind axis prints `note:` and returns 0, and `--strict` runs it
blocking for anyone measuring whether it is ready to be promoted. An axis that
is wrong three times in five is not a gate, it is a tax on being right.

Four states, and the last two matter:

  `sighted`  quotes at least one number of the oracle's (`square`, `crooked`,
             `unframed`, `graded`, `soft`, `regrouped`, `relabelled`,
             `interstice`, `askew`) or carries a tree-identity proof, which is
             oracle-free and answers the same question more cheaply.
  `blind`    quotes a number of ours (`damage`, `built`, `standing`, `worth`,
             `rubble`, `spoil`, `orphan`, `unbuilt`) and none of theirs.
  `selfsame` quotes a number of ours that only a self-comparing instrument
             reports. `shear.py` presses the same bytes with the same grammar
             twice; there is no second parser in the question it asks, so
             "which oracle" has no answer and demanding one is a false refusal.
             Decided by `instrument.py` off the instrument's own record
             declarations - paired arms, no oracle column, no reach to the
             module that spawns the oracle - and never off a name list, so an
             instrument written next month is classified by what it does.
  `silent`   quotes neither, and is prose. Not a defect and not a denominator.

The fraction reported is over `sighted + blind`, because a page with no
measurement in it cannot be blind to one.

Regrowth is measured two ways, neither of which requires a network or a write:

  by day       each page's mtime, bucketed. A blind page written today is a page
               written *after* the instrument to see existed, which is the only
               kind the record can still be blamed for.
  by tracking  `git ls-files` (read-only). An untracked blind page has not
               reached anybody else yet and is the cheapest possible fix.

Usage:  sighting.py                the fraction, the buckets, the verdict
        sighting.py --blind        the blind pages, newest first
        sighting.py --gate         THE GATE. Exit 1 if a page changed since the
                                   pin quotes a measured figure and names no
                                   tree. Reads only the pages the diff names, so
                                   it costs what the diff costs and not what the
                                   record costs. Wired as the `record` job in
                                   .github/workflows/ci.yml.
        sighting.py --gate --strict
                                   the same, with the blind axis blocking too.
                                   Not what CI runs; this is how a lane measures
                                   whether that axis is ready to be promoted.
        sighting.py --gate --since REF
                                   override the pin. Allowed only when REF
                                   reaches FURTHER BACK than the pin, so a flag
                                   may ask harder and never softer.
        sighting.py --pin REF --because "..."
                                   move the ratchet. Appends to
                                   `sighting.since` and prints, before it
                                   writes, which refused pages the move clears.
        sighting.py --check        every claim above, built and watched to fail
        sighting.py --sample 15    a seeded, axis-stratified worklist of
                                   refusals to adjudicate by hand
        sighting.py --rate         the false-refusal rate from those
                                   adjudications, per axis, with its interval
        sighting.py --gate --max N exit 1 if the blind population exceeds N,
                                   which is the form that works while the whole
                                   record is still uncommitted
        sighting.py --unstamped    the measuring pages that name no tree
        sighting.py --json         all of it, machine-readable
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from collections import Counter
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import instrument  # what each instrument can be asked, read off its own records
import onlydamage  # the triage this agrees with, imported rather than copied

ROOT = onlydamage.ROOT
OURS, FOREST = onlydamage.OURS, onlydamage.FOREST
# The triage's vocabulary, plus the two columns *derived* from `square` that it
# does not list. `trued` is `square / size` and `unvouched` is `built - square`,
# so a number beside either is a claim about a second parser as surely as
# `square` itself is - and `trued` is the column this lane is asking the board to
# print, which would have left every corrected page reading as blind.
THEIRS = onlydamage.THEIRS + "|trued|unvouched"

# A markdown row's cells, with the outer pipes dropped. A row is a pairing when
# one cell names a column and another holds a number; which order they come in
# is the table author's business and not ours.
NUMBER = re.compile(r"[-+−]?\d[\d,]*")
NAMES = re.compile(rf"\b(?:{THEIRS})\b", re.I)
MINE = re.compile(rf"\b(?:{OURS})\b", re.I)

# A tree or binary identity. Seven hex characters is git's short form and the
# length every stamp on this tree uses; the lookahead-plus-`[a-f]` is there
# because `\b[0-9a-f]{7,}\b` alone matches a seven-digit *number*, and this
# record is made of numbers. Requiring one letter costs the 1-in-4,000 digest
# that is all digits and buys back every byte count in the corpus.
#
# Deliberately not anchored to a keyword. `named` (a digest preceded by
# `outliner`/`repo`/`tree`/...) refuses 203 of the 263 measuring pages where
# this refuses 184, and the 19 it adds are pages that carry a digest in a shape
# the keyword list had not met yet - a list that has to be complete to avoid a
# false refusal is the wrong shape for a gate lanes have to live under.
STAMP = re.compile(r"\b(?=[0-9a-f]{7,}\b)[0-9a-f]*[a-f][0-9a-f]*\b")


@lru_cache(maxsize=1)
def quotable() -> frozenset[str]:
    """The columns a board can total, asked of the board rather than listed.

    `standing.SUMMABLE` owns which columns add up over rows, and copying that
    tuple here would be a second copy of a rule with one owner - the thing
    `sole.py` audits the tree for. Imported late because it costs 38 ms and is
    only ever needed on a run that is already printing a refusal.
    """
    sys.path.insert(0, str(ROOT / "tool"))
    import standing  # noqa: PLC0415  (the owner of the rule, not a copy of it)
    return frozenset(standing.SUMMABLE)


def cells(line: str) -> list[str]:
    if line.count("|") < 2:
        return []
    return [c.strip() for c in line.strip().strip("|").split("|")]


def rule(row: list[str]) -> bool:
    return bool(row) and all(set(c) <= set("-: ") for c in row)


def tables(text: str) -> list[list[list[str]]]:
    """Contiguous runs of pipe rows, alignment rules dropped."""
    out: list[list[list[str]]] = []
    run: list[list[str]] = []
    for line in text.splitlines():
        got = cells(line)
        if len(got) < 2:
            if run:
                out.append(run)
                run = []
            continue
        if not rule(got):
            run.append(got)
    if run:
        out.append(run)
    return out


def paired(text: str, names: re.Pattern[str]) -> list[str]:
    """A markdown table saying a number about one of `names`, either way round.

    Two shapes, and a sweep that reads only one of them misgrades its own work:

      **across** `| grammar | built | square |` with the numbers in rows beneath
                 — the name is in the header and the number is three rows down,
                 in the same *column*.
      **down**   `| square | 2,184 |` — name and number in the same row.

    Returns the column names, one entry per pairing, so `len()` is the count the
    state is decided on and the entries themselves are what `instrument.py` asks
    its question about. Counting and naming from one pass is the point: a second
    pass would be free to disagree with the first about what the page said.
    """
    hits: list[str] = []
    for grid in tables(text):
        head, body = grid[0], grid[1:]
        for i, cell in enumerate(head):
            if (hit := names.search(cell)):
                hits += [hit.group(0)] * sum(1 for row in body
                                             if i < len(row) and NUMBER.search(row[i]))
        for row in grid:
            named = [(i, n.group(0)) for i, c in enumerate(row)
                     if (n := names.search(c))]
            numbered = {i for i, c in enumerate(row) if NUMBER.search(c)}
            hits += [n for i, n in named
                     for j in numbered if i != j]
    return hits


# `RESULT-9-reach.md` names the shape that is wrong in a *known* direction: a
# page that quotes our columns, is about a declared extra, and concludes that a
# seating **cost** something. That is ocaml's fragment exactly, and ocaml's
# fragment is the one verdict on the tree that flipped sign. Anything in the
# blind tail wearing all three is worth opening before anything that wears two.
COSTS = ("regression", "regressed", "cost", "fell", "worse", "lost", "declin",
         "gave back", "paid for")


def look(at: Path) -> dict:
    text = at.read_text(errors="replace")
    got = onlydamage.read(at)
    tabled, mine = paired(text, NAMES), paired(text, MINE)
    got["theirs_tabled"], got["ours_tabled"] = len(tabled), len(mine)
    # The triage's own proximity pass, re-run over the derived columns it omits.
    got["theirs_derived"] = onlydamage.near(text, "trued|unvouched")
    theirs = got["theirs"] + got["theirs_tabled"] + got["theirs_derived"]
    ours = got["ours"] + got["ours_tabled"]
    # Which of our columns carried a number, as written. The exemption below is
    # asked about exactly these and not about the page in general. The prose
    # pairings come back from the read that already counted them; the tabled
    # ones are this file's, since the triage does not read tables.
    got["quoted"] = sorted({w.lower() for w in got["quoted"] + mine})
    got["state"] = ("sighted" if theirs or got["forest"] else
                    "blind" if ours else "silent")
    got["why"] = ""
    if got["state"] == "blind":
        # Only ever asked of a page the blind axis was about to refuse, so the
        # instruments a page cites are parsed for the pages that need it and
        # never for the 123 pages of prose or the 152 that already asked.
        verdict = instrument.judge(text, set(got["quoted"]), THEIRS)
        got["why"] = verdict.why
        if verdict.exempt:
            got["state"] = "selfsame"
    # How many measured figures the page quotes, on either vocabulary. This is
    # the gate's subject: a page with none of these is prose and is not asked
    # for a stamp, which is the whole of the gate's precision.
    got["figures"] = theirs + ours
    got["stamp"] = len(STAMP.findall(text))
    low = text.lower()
    got["costs"] = sum(low.count(w) for w in COSTS)
    got["mtime"] = at.stat().st_mtime
    got["day"] = datetime.fromtimestamp(got["mtime"], timezone.utc).strftime("%Y-%m-%d")
    return got


def tracked() -> set[str]:
    try:
        out = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True,
                             text=True, timeout=30, check=True).stdout
    except (OSError, subprocess.SubprocessError):
        return set()
    return set(out.split("\n"))


def changed(since: str) -> set[str]:
    """Paths differing from REF, read-only. Includes untracked, which is where a
    page being written right now lives."""
    paths: set[str] = set()
    for cmd in (["git", "diff", "--name-only", since],
                ["git", "ls-files", "--others", "--exclude-standard"]):
        try:
            out = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True,
                                 timeout=30, check=True).stdout
        except (OSError, subprocess.SubprocessError):
            continue
        paths |= {p for p in out.split("\n") if p.endswith(".md")}
    return paths


def survey() -> list[dict]:
    return [look(p) for p in onlydamage.pages()]


def faults(got: dict) -> list[str]:
    """Why this page would be refused, in the order a lane can act on them.

    Empty for a page with no measured figure in it. That is the gate's whole
    claim to being affordable: prose is not asked to prove anything, and 123 of
    the 386 pages on this tree are prose.
    """
    if not got["figures"]:
        return []
    out = []
    if got["state"] == "blind":
        out.append("quotes our columns and never the oracle's — "
                   "`standing.py --audit` buys `trued`"
                   + (f" ({got['why']})" if got.get("why") else ""))
    if not got["stamp"]:
        out.append("names no tree or binary — a corpus total is only true of "
                   "one tree, and three of this morning's differ by 1,900 B")
    return out


# Which of the two axes may refuse a push, and it is one of them. Measured
# rather than chosen: `--rate` adjudicates 45 sampled refusals by hand and the
# blind axis is FALSE 60% of the time [35.7%, 80.2%] where it refuses alone,
# against 6.9% [1.9%, 22.0%] for the stamp axis. Nine of those fifteen blind
# refusals are pages that did ask a second parser and said so in a word the
# vocabulary has no entry for - `the oracle defends 611`, `median 2.9x
# tree-sitter's time`, `4300 unjudged where the oracle had nothing to say`. A
# closed word list cannot be completed by trying harder at it, which is the same
# finding `STAMP`'s comment records about anchoring a digest to a keyword.
#
# So the blind axis reports and does not block, and `--strict` runs it blocking
# for anyone measuring whether it is ready to. It is promoted the day `--rate`
# reads under 10% for `blind only` on a fresh seed, and the way there is a
# reading of "asked a second parser" that is not a vocabulary - the oracle's
# identity is already on the board as `still.Witness.asked`, and a page carrying
# a `--cite` line that says how many oracles were in the room needs no word list
# at all.
BLOCKING = ("names no tree or binary",)


def blocking(why: list[str], strict: bool = False) -> list[str]:
    return why if strict else [w for w in why
                               if any(w.startswith(b) for b in BLOCKING)]


def remedy(got: dict) -> str:
    """The command that clears this page, with the page's own column in it.

    A gate that names the fix is worth several of one that names the problem,
    and the fix here is one command whose output is one line. `--quote` is
    offered when the page quoted a column a board can total, because that form
    renders the figure and the world it was taken in *from the same board* and
    so cannot drift the way a hand-pasted pair can.
    """
    if column := next((c for c in got.get("quoted", ()) if c in quotable()), ""):
        return (f"python3 tool/standing.py --cite=<the board this number came "
                f"from> --quote={column}")
    return ("python3 tool/standing.py --cite"
            "     # one line naming binary, tree, oracle")


PIN = Path(__file__).resolve().parent / "sighting.since"


def git(*args: str) -> tuple[int, str]:
    try:
        done = subprocess.run(["git", *args], cwd=ROOT, capture_output=True,
                              text=True, timeout=30, check=False)
    except (OSError, subprocess.SubprocessError):
        return 1, ""
    return done.returncode, done.stdout.strip()


def ledger(text: str) -> list[tuple[str, str, str]]:
    """(date, commit, why) newest last, comments and blanks dropped."""
    out = []
    for line in text.splitlines():
        if not (row := line.split("#", 1)[0].split()):
            continue
        out.append((row[0], row[1], " ".join(row[3:]) if len(row) > 3 else ""))
    return out


def pinned() -> tuple[str, str, str]:
    """The live pin, or an empty commit when the ledger is missing or empty."""
    if not PIN.exists():
        return ("", "", "")
    rows = ledger(PIN.read_text())
    return rows[-1] if rows else ("", "", "")


def moved() -> str:
    """Has this working tree changed the pin without committing it?

    The one way a forward ratchet gets quietly defeated is a ref nudged past an
    inconvenient page, so a run whose ledger differs from the committed one is
    refused rather than trusted. A ledger with no committed version at all is
    the first pin and has nothing to have moved from; `git show` failing is read
    as that rather than as tampering, which is also what happens in a checkout
    with no history and is the safe reading in both.
    """
    rel = str(PIN.relative_to(ROOT))
    code, _ = git("show", f"HEAD:{rel}")
    if code:
        return ""
    code, out = git("diff", "--name-only", "HEAD", "--", rel)
    return rel if out else ""


def banner(since: str, why: str) -> None:
    date, commit, note = pinned()
    age = ""
    if date:
        try:
            days = (datetime.now(timezone.utc).date()
                    - datetime.strptime(date, "%Y-%m-%d").date()).days
            age = f", pinned {days} day(s) ago"
        except ValueError:
            age = ""
    print(f"\n  asking about pages changed since {since}{age}"
          f"{f' — {note}' if note and since == commit else ''}")
    print(f"  the ref is {PIN.relative_to(ROOT)}, committed and append-only"
          f"{f' · {why}' if why else ''}")


def override(since: str, commit: str) -> bool:
    """Is a hand-passed `--since` looser than the pin? Then it is refused.

    Reaching further back than the pin asks about more pages and is always
    allowed - that is how a lane checks its own work harder than CI will. The
    other direction asks about fewer, which is the pin moved by a flag rather
    than by a commit, and it is the whole thing the ledger exists to prevent.
    """
    if not commit:
        return False
    # Resolved, not compared as text: `--since HEAD` on the day the pin IS HEAD
    # is the same ref spelled differently, and refusing it would refuse the
    # honest invocation while a descendant sha slipped past as "not equal".
    here, there = (git("rev-parse", r)[1] for r in (since, commit))
    if not here or not there or here == there:
        return False
    code, _ = git("merge-base", "--is-ancestor", there, here)
    return code == 0  # the pin is behind the override, so the override is looser


def gate(since: str, explicit: bool, strict: bool = False) -> int:
    """Refuse the pages the diff names. Reads nothing else.

    The old form surveyed all 386 pages and then filtered to the changed ones,
    which costs the record's whole size to answer a question about a handful of
    files. A gate priced at the record is a gate that gets slower every week
    somebody writes a page; this one is priced at the diff.
    """
    date, commit, _ = pinned()
    if not commit and not explicit:
        print(f"\n  sighting.py: no pin at {PIN.relative_to(ROOT)}, and a gate "
              f"with no ref\n  is a gate that refuses the whole record. "
              f"`--pin <ref> --because \"...\"`.", file=sys.stderr)
        return 2
    if (dirty := moved()):
        banner(since, "")
        print(f"\n  the pin moved in this working tree and is not committed "
              f"({dirty}).\n  A ref that can be moved without review is not a "
              f"ratchet. Commit the move,\n  or `git diff -- {dirty}` to see "
              f"what it would have cleared.", file=sys.stderr)
        return 2
    if explicit and override(since, commit):
        banner(commit, "")
        print(f"\n  --since {since} reaches past the pin {commit}, so it asks "
              f"about fewer pages.\n  A flag may ask harder than the pin and "
              f"never softer. Move the pin instead.", file=sys.stderr)
        return 2
    banner(since, "overridden by --since, asking harder" if explicit else "")

    known = {str(p.relative_to(ROOT)): p for p in onlydamage.pages()}
    touched = sorted(p for p in changed(since) if p in known)
    bad, noted = [], 0
    for path in touched:
        got = look(known[path])
        if not (why := faults(got)):
            continue
        stop = blocking(why, strict)
        noted += len(why) - len(stop)
        print(f"\n  {path}  ({got['figures']} measured figure(s))")
        for line in why:
            print(f"      {'-' if line in stop else 'note:'} {line}")
        print(f"      $ {remedy(got)}")
        if stop:
            bad.append(path)
    print(f"\n  {len(bad)} of {len(touched)} page(s) changed since {since} "
          f"report a measurement they cannot stand behind"
          f"{f', and {noted} more carry a note' if noted else ''}.")
    if bad:
        print("  A figure is only true of the tree it was taken on, and the "
              "line above each page\n  renders the figure and that tree from "
              "the same board so they cannot drift apart.\n"
              "  What is checked is that a stamp is PRESENT, never that it is "
              "the figure's own:\n  a fresh `--cite` pasted beside a stale "
              "number passes here. Binding the two needs\n  a re-press at ~30 s "
              "a page — research/joinery/consort/RESULT-11-quotation.md.")
    if noted and not strict:
        print(f"  A `note:` never refuses. The blind axis is 60% false where it "
              f"refuses alone\n  (`--rate`), so it reports until that number "
              f"falls; `--strict` runs it blocking.")
    return 1 if bad else 0


def pin(ref: str, because: str) -> int:
    """Append a pin, after saying what the move stops asking about.

    Printing the cleared pages *before* the write is the whole ceremony: the
    number goes into the line, so a move that clears seven pages is a commit
    that says it clears seven pages, and a reviewer reads one column instead of
    re-deriving a diff of two refs.
    """
    if not because:
        print("sighting.py: --pin needs --because \"<why>\"", file=sys.stderr)
        return 2
    code, commit = git("rev-parse", "--short", ref)
    if code:
        print(f"sighting.py: no such ref {ref!r}", file=sys.stderr)
        return 2
    _, was, _ = pinned()
    known = {str(p.relative_to(ROOT)): p for p in onlydamage.pages()}
    before = {p for p in changed(was) if p in known} if was else set()
    after = {p for p in changed(commit) if p in known}
    clears = sorted(p for p in before - after if faults(look(known[p])))
    print(f"\n  moving the pin {was or '(none)'} → {commit} stops asking about "
          f"{len(clears)} refused page(s)")
    for path in clears:
        print(f"    {path}")
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    with PIN.open("a") as out:
        out.write(f"{today}    {commit:<10} {len(clears):<7} {because}\n")
    print(f"\n  appended to {PIN.relative_to(ROOT)}. Commit it: an uncommitted "
          f"pin refuses every run.\n")
    return 0


VERDICTS = Path(__file__).resolve().parent / "sighting.adjudicated.json"
AXES = ("blind only", "both", "stamp only")


def axis(why: list[str]) -> str:
    blind = any("never the oracle" in w for w in why)
    stamp = any("names no tree" in w for w in why)
    return "both" if blind and stamp else "blind only" if blind else "stamp only"


def sample(rows: list[dict], size: int, seed: int) -> list[dict]:
    """A seeded, axis-stratified draw from the pages the gate would refuse.

    Stratified because the three axes are three different questions and the
    rarest of them - blind only, 28 pages - is the half this gate is least sure
    of; a proportional draw would put four of it in a sample of 45 and report
    its rate to ±40 points. Seeded because a false-refusal rate that cannot be
    redrawn by somebody else is an assertion rather than a measurement.
    """
    import random  # noqa: PLC0415  (only the sampler needs it)
    pool: dict[str, list[dict]] = {a: [] for a in AXES}
    for got in rows:
        if (why := faults(got)):
            got["axis"] = axis(why)
            got["faults"] = why
            pool[got["axis"]].append(got)
    out = []
    for name in AXES:
        die = random.Random(f"{seed}:{name}")
        out += die.sample(pool[name], min(size, len(pool[name])))
    for got in out:
        got["population"] = len(pool[got["axis"]])
    return out


def wilson(hits: int, tries: int, z: float = 1.96) -> tuple[float, float, float]:
    """A share and its 95% interval, the score form rather than the normal one.

    `p ± 1.96·sqrt(p(1-p)/n)` is the interval everybody reaches for and it is
    wrong at exactly the counts this measurement has: it gives ±0 at 0/15, and
    0/15 is not certainty. Wilson's is not degenerate there and needs no
    dependency.
    """
    if not tries:
        return (0.0, 0.0, 1.0)
    p, n = hits / tries, tries
    mid = (p + z * z / (2 * n)) / (1 + z * z / n)
    half = (z / (1 + z * z / n)) * ((p * (1 - p) / n + z * z / (4 * n * n)) ** 0.5)
    return (p, max(0.0, mid - half), min(1.0, mid + half))


def rate(rows: list[dict]) -> int:
    """The false-refusal rate, reweighted from the strata back to the record."""
    if not VERDICTS.exists():
        print(f"\n  no adjudications at {VERDICTS.relative_to(ROOT)}. "
              f"`--sample 15` draws a worklist.\n", file=sys.stderr)
        return 2
    done = json.loads(VERDICTS.read_text())
    seen = {r["path"]: r for r in done["pages"]}
    pool: dict[str, list[dict]] = {a: [] for a in AXES}
    for got in rows:
        if (why := faults(got)):
            pool[axis(why)].append(got)
    print(f"\n  {done['method']}\n")
    print(f"  {'axis':<12}{'refused':>8}{'judged':>8}{'false':>7}   rate "
          f"(95% Wilson)")
    weighted = lo = hi = 0.0
    total = sum(len(v) for v in pool.values())
    for name in AXES:
        got = [seen[r["path"]] for r in pool[name] if r["path"] in seen]
        bad = sum(1 for r in got if r["verdict"] == "false")
        p, a, b = wilson(bad, len(got))
        share = len(pool[name]) / total
        weighted, lo, hi = weighted + share * p, lo + share * a, hi + share * b
        print(f"  {name:<12}{len(pool[name]):>8}{len(got):>8}{bad:>7}   "
              f"{p:6.1%}  [{a:.1%}, {b:.1%}]")
    print(f"\n  {'record':<12}{total:>8}{len(seen):>8}"
          f"{sum(1 for r in seen.values() if r['verdict'] == 'false'):>7}   "
          f"{weighted:6.1%}  [{lo:.1%}, {hi:.1%}]   stratum-weighted")
    # The blocking half on its own. `both` counts here because a page failing
    # both axes is still refused by the stamp axis alone, and the two false ones
    # are false on the stamp axis too - neither carries a figure at all.
    fires = [seen[r["path"]] for name in ("stamp only", "both")
             for r in pool[name] if r["path"] in seen]
    bad = sum(1 for r in fires if r["verdict"] == "false")
    p, a, b = wilson(bad, len(fires))
    print(f"  {'stamp axis':<12}{len(pool['stamp only']) + len(pool['both']):>8}"
          f"{len(fires):>8}{bad:>7}   {p:6.1%}  [{a:.1%}, {b:.1%}]   "
          f"the half that blocks")
    print(f"\n  {total} refusals over {len(rows)} page(s); the record rate is "
          f"the three axis rates\n  weighted by how much of the refused "
          f"population each axis is. Only the last row\n  is the enforced "
          f"gate's rate - the blind axis reports and does not block.")
    # Every axis above is re-derived from the tree as it is right now and joined
    # to the adjudications by path, so a page somebody stamped this morning
    # leaves the stratum it was judged in and stops counting. That is the right
    # arithmetic - the rate is about what the gate does today - but it is also
    # how a measurement quietly decays into a smaller and smaller sample while
    # still printing a number, so it says how much of itself it has lost.
    live = {r["path"] for v in pool.values() for r in v}
    gone = sorted(set(seen) - live)
    moved_ = [p for p in seen if p in live
              and seen[p].get("axis") not in ("", None)
              and seen[p]["axis"] != next(a for a in AXES
                                          if any(r["path"] == p for r in pool[a]))]
    if gone or moved_:
        print(f"\n  {len(gone)} adjudicated page(s) no longer refuse at all and "
              f"{len(moved_)} changed axis\n  since 2026-08-06; they are dropped "
              f"rather than carried. Redraw with `--sample`\n  when this passes "
              f"a fifth of the sample"
              + (f" — gone: {', '.join(Path(p).name for p in gone[:4])}"
                 if gone else "") + ".")
    print()
    return 0


def check(rows: list[dict]) -> int:
    """Can the gate say no, and is it saying no about two different things?

    Corpus-shaped on purpose. A check pinned to `RESULT-4-borrow.md` being
    sighted-and-unstamped dies the morning somebody stamps that one page, and
    dies looking like a pass. These ask the population instead: *some* page must
    exhibit each corner, and if the corpus ever stops exhibiting one the check
    fails loudly rather than passing over nothing.
    """
    ok = True

    def say(what: str, got: bool) -> None:
        nonlocal ok
        ok &= got
        print(f"  {'pass' if got else 'FAIL'}  {what}")

    print("\n  can this gate say no?")
    figure = "corpus `square` reads 311,540 over the thirty rows."
    say("a measured figure with no tree named is refused",
        bool(faults({"figures": 3, "state": "sighted", "stamp": 0})))
    say("...and the same page with a digest on it is not",
        not faults({"figures": 3, "state": "sighted", "stamp": 1}))
    say("prose is never asked for a stamp",
        not faults({"figures": 0, "state": "silent", "stamp": 0}))
    say("a blind page is reported even when it is stamped",
        bool(faults({"figures": 3, "state": "blind", "stamp": 1})))
    say("...and reporting is all it does — the blind axis never blocks",
        not blocking(faults({"figures": 3, "state": "blind", "stamp": 1})))
    say("...unless --strict is asked for, which is how it gets promoted",
        bool(blocking(faults({"figures": 3, "state": "blind", "stamp": 1}), True)))
    say("the stamp axis does block",
        bool(blocking(faults({"figures": 3, "state": "sighted", "stamp": 0}))))
    say(f"the sentence that started this is refused ({figure!r})",
        bool(STAMP.search("outliner f6a34cd7c")) and not STAMP.search(figure))
    # The tightening: `\b[0-9a-f]{7,}\b` alone reads a seven-digit number as a
    # digest, and this record is made of seven-digit numbers.
    say("a seven-digit number is not mistaken for a digest",
        not STAMP.search("3712000 bytes") and bool(STAMP.search("3d980e308")))

    # --- the self-comparison exemption, asked structurally.
    print("\n  can the self-comparison exemption say no?")
    kits = {m: k for m in instrument.index()
            if (k := instrument.kit(m, THEIRS)) and not k.mute}
    same = sorted(m for m, k in kits.items() if k.selfsame)
    asked = sorted(m for m, k in kits.items() if not k.selfsame)
    say(f"some instrument reads as self-comparing ({', '.join(same) or 'none'})",
        bool(same))
    say(f"...and most do not ({len(asked)} of {len(kits)} can be asked an "
        f"oracle)", len(asked) > len(same))
    say("the module that spawns the oracle is never exempt",
        instrument.DRIVER in kits and not kits[instrument.DRIVER].selfsame)
    say("an unnamed instrument earns nothing",
        not instrument.judge("no code named here", {"damage"}, THEIRS).exempt)
    say("a column no cited instrument reports earns nothing",
        not instrument.judge(f"{same[0]}.py" if same else "shear.py",
                             {"speedup"}, THEIRS).exempt)
    if same:
        mine = sorted(c for c, _ in kits[same[0]].arms)
        say(f"...but a column {same[0]} does report is exempt (`{mine[0]}`)",
            instrument.judge(f"{same[0]}.py", {mine[0]}, THEIRS).exempt)

    # --- the ratchet's ref, which is the part most worth defeating quietly.
    print("\n  can the pin be moved quietly?")
    _, commit, _ = pinned()
    back = git("rev-parse", f"{commit}~1")[1] if commit else ""
    say(f"a pin is committed and resolves ({commit or 'none'})",
        bool(commit) and git("rev-parse", "--verify", f"{commit}^{{commit}}")[0] == 0)
    say("a --since that asks about FEWER pages than the pin is refused",
        bool(back) and override(commit, back))
    say("...one that asks about more is allowed", bool(back)
        and not override(back, commit))
    say("...and the pin spelled another way is not mistaken for a move",
        bool(commit) and not override("HEAD", commit)
        if git("rev-parse", "HEAD")[1] == git("rev-parse", commit)[1] else True)

    # --- the two axes, asked of the corpus rather than of a named page.
    meas = [r for r in rows if r["figures"]]
    corners = {(r["state"] == "blind", not r["stamp"]) for r in meas}
    loose = [r for r in meas if r["state"] == "sighted" and not r["stamp"]]
    say(f"the stamp axis is not the oracle axis wearing a hat: "
        f"{len(loose)} of {len(meas)} measuring page(s) ask an oracle and name "
        f"no tree", bool(loose))
    say(f"...and the corpus exhibits {len(corners)} of the 4 corners, so "
        f"neither axis is implied by the other",
        (True, False) in corners and (False, True) in corners)
    say(f"a page with no measured figure exists to be let through "
        f"({len(rows) - len(meas)} of {len(rows)})", len(meas) < len(rows))
    print(f"\n  {'every check can say no' if ok else 'A CHECK CANNOT SAY NO'}")
    return 0 if ok else 1


def main(argv: list[str]) -> int:
    if "--pin" in argv:
        because = next((a.split("=", 1)[1] for a in argv
                        if a.startswith("--because=")), "")
        if not because and "--because" in argv:
            because = argv[argv.index("--because") + 1]
        return pin(argv[argv.index("--pin") + 1], because)

    if "--gate" in argv and "--max" not in argv:
        explicit = "--since" in argv
        since = (argv[argv.index("--since") + 1] if explicit
                 else pinned()[1] or "HEAD")
        return gate(since, explicit, "--strict" in argv)

    rows = survey()
    keep = tracked()
    for got in rows:
        got["tracked"] = got["path"] in keep
    blind = [r for r in rows if r["state"] == "blind"]
    sighted = [r for r in rows if r["state"] == "sighted"]
    silent = [r for r in rows if r["state"] == "silent"]
    same = [r for r in rows if r["state"] == "selfsame"]
    judged = len(blind) + len(sighted)
    days = Counter(r["day"] for r in blind)
    newest = max((r["day"] for r in rows), default="")

    if "--gate" in argv and "--max" in argv:
        # The ceiling form, for a tree whose record is not committed yet: today
        # every page is "changed since HEAD", so the diff form flags all 102 and
        # says nothing. A ceiling only ever has to fall.
        ceiling = int(argv[argv.index("--max") + 1])
        print(f"blind {len(blind)}  ceiling {ceiling}  "
              f"{'over' if len(blind) > ceiling else 'under'}")
        if len(blind) > ceiling:
            print("A ceiling is lowered by making a page sighted, never by "
                  "raising the ceiling.")
        return 1 if len(blind) > ceiling else 0

    if "--check" in argv:
        return check(rows)

    if "--rate" in argv:
        return rate(rows)

    if "--sample" in argv:
        size = int(argv[argv.index("--sample") + 1])
        seed = int(argv[argv.index("--seed") + 1]) if "--seed" in argv else 11
        drawn = sample(rows, size, seed)
        print(f"\n  {len(drawn)} refusal(s) drawn at seed {seed}, "
              f"{size} per axis\n")
        for got in drawn:
            print(f"  [{got['axis']}] {got['path']}")
            print(f"      figures {got['figures']}  stamp {got['stamp']}  "
                  f"quoted {got['quoted']}")
            if got["why"]:
                print(f"      blind: {got['why']}")
        print()
        return 0

    if "--unstamped" in argv:
        loose = [r for r in rows if r["figures"] and not r["stamp"]]
        print(f"\n  {len(loose)} of the {judged} measuring page(s) name no tree "
              f"or binary, newest first\n")
        for got in sorted(loose, key=lambda r: -r["mtime"])[:40]:
            print(f"  {got['day']} {got['state']:<8}{got['figures']:>4} fig  "
                  f"{got['path']}")
        print(f"\n  {sum(1 for r in loose if r['state'] == 'sighted')} of them "
              f"are sighted: they asked an oracle and did not say on what tree."
              f"\n  That is the axis `--gate` reads that the blind/sighted "
              f"split cannot.\n")
        return 0

    if "--json" in argv:
        json.dump({"rows": rows, "sighted": len(sighted), "blind": len(blind),
                   "silent": len(silent), "by_day": dict(days)},
                  sys.stdout, indent=1, sort_keys=True)
        print()
        return 0

    if "--risk" in argv:
        at = [r for r in blind if r["extras"] and r["costs"] and r["claims"]]
        at.sort(key=lambda r: -(r["costs"] * r["extras"]))
        print(f"\n  {len(at)} of the {len(blind)} blind pages wear all three: "
              f"our columns only,\n  a declared extra as the subject, and a "
              f"seating that cost something.\n")
        for got in at:
            print(f"  {got['costs']:3} cost {got['extras']:4} extra   "
                  f"{got['path']}")
        print()
        return 0

    if "--blind" in argv:
        print(f"\n  {len(blind)} blind page(s), newest first\n")
        for got in sorted(blind, key=lambda r: -r["mtime"]):
            mark = " " if got["tracked"] else "?"
            print(f"  {got['day']} {mark} {got['path']}")
        print()
        return 0

    print(f"\n  {len(rows)} page(s) under research/ and changelog.d/\n")
    print(f"  sighted  {len(sighted):5}   quotes the oracle, or proves trees identical")
    print(f"  blind    {len(blind):5}   quotes only our own words about our own forest")
    print(f"  selfsame {len(same):5}   quotes an instrument with one parser in it, "
          f"which has no oracle to name")
    print(f"  silent   {len(silent):5}   no measurement in it")
    print(f"\n  {len(sighted) / judged:.1%} of the {judged} pages that report a "
          f"measurement have asked a second parser.")
    print(f"  The {len(same)} selfsame page(s) are in neither number: an "
          f"instrument that presses the\n  same bytes twice cannot name an "
          f"oracle, so it can be neither blind nor sighted.")
    print(f"\n  blind pages by the day they were last written "
          f"(today is {newest}):\n")
    for day, count in sorted(days.items(), reverse=True)[:8]:
        bar = "#" * min(count, 60)
        print(f"  {day}  {count:4}  {bar}")
    fresh = days.get(newest, 0)
    loose = sum(1 for r in blind if not r["tracked"])
    print(f"\n  {fresh} of the {len(blind)} were written or last touched today, "
          f"and {loose} are untracked.")
    print("  A backlog would be flat and old. This is not flat and it is not old:"
          "\n  the population regrows every day work is done, because nothing "
          "stops a page\n  reporting `damage` alone. `sighting.py --gate --since "
          "<ref>` is that stop.\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

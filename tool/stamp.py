#!/usr/bin/env python3
"""What tree produced this number.

Four lanes edit this repo at once, so every measurement is a claim about a tree
state that nothing recorded. That has already gone wrong twice: a report said
the widened corpus cost four whole files when a lexer fix had landed mid-lane
and the real cost was one, and a file-split lane watched state counts move
under it mid-measurement. Both times the numbers were honestly taken and both
times they described a tree that no longer existed.

So an instrument stamps what it ran on, in its own output, without anyone
having to remember to. The load-bearing fact is a digest of the *source the
binary was built from* rather than of the repo the run happened in, because a
measurement is only ever about the former; git is context around it.

There are three ways to be measuring a tree that no longer exists, and they
need different detectors:

  stale   something under the binary's own source root is newer than the
          binary, so an in-place rebuild is overdue
  drift   the binary's source root no longer matches the live repo, which is
          the one that bit us - a snapshot build is internally consistent and
          perfectly happy while the world moves on without it
  split   the artifacts the run READ were not one generation - a folio
          re-minted or a binary reinstalled between two rows, so the rows are
          not comparable with each other

The first two watch the *sources*, which is why the third had to be added
separately: a `zig build` landing mid-run need not change a single source
byte, and the folio cache reports only what it decided when each row asked it.
Between that decision and the end of the board sits the whole measurement.

All three are warnings and none is an error. Measuring an old binary on purpose
is a legitimate thing to do; that is what a before/after pair is. The point is
that the report says so rather than that the run refuses.

`verdict` lives here for the same reason: it is the other half of not fooling
yourself about a run. A stamp says which binary spoke; a verdict says what it
said, and both are read rather than guessed at.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import time
from pathlib import Path
from typing import NamedTuple

ROOT = Path(__file__).resolve().parents[1]

# What a build reads. Digesting these is ~3 ms over this tree, cheap enough to
# do on every run, which is the only way a stamp nobody remembers to ask for
# still ends up in the report.
SOURCES = ("src", "build.zig", "build.zig.zon")


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def git(*args: str) -> str:
    got = subprocess.run(("git", *args), capture_output=True, text=True, cwd=ROOT)
    return got.stdout.strip() if got.returncode == 0 else ""


class Source(NamedTuple):
    """One source tree, hashed. `newest` is carried because an mtime answers a
    question the digest cannot: whether a build has happened since the edit."""

    root: Path
    digest: str
    newest: float
    where: str
    files: int


def builds(rel: str) -> bool:
    """Whether editing this file could change a *product* binary.

    A `*_test.zig` is reachable only from `src/proof.zig`, the test build's own
    root, which nothing but a test compilation is rooted at - so it enters the
    test binary and never the CLI. Letting one set `stale` made the warning
    fire on a tree where nothing that could move the binary had moved, and with
    ten lanes editing tests continuously it fired most of the time, which is how a
    warning teaches people to ignore it.

    Only the mtime side takes this exclusion. The digest still covers every file,
    because "is this the same tree as over there" is a different question from "can
    this binary be believed" and drift wants the whole answer.
    """
    return not rel.endswith("_test.zig")


def survey(root: Path) -> Source:
    h = hashlib.sha256()
    when, where, count = 0.0, "", 0
    for name in SOURCES:
        base = root / name
        leaves = [base] if base.is_file() else sorted(
            p for p in base.rglob("*") if p.is_file()) if base.is_dir() else []
        for p in leaves:
            try:
                blob = p.read_bytes()
                m = p.stat().st_mtime
            except OSError:
                # A file another lane is mid-write on is itself a fact about
                # this tree state; record it rather than failing a measurement
                # this was only supposed to describe.
                h.update(str(p.relative_to(root)).encode() + b"\0?\0")
                continue
            rel = str(p.relative_to(root))
            h.update(rel.encode() + b"\0")
            h.update(hashlib.sha256(blob).digest())
            count += 1
            if m > when and builds(rel):
                when, where = m, rel
    return Source(root, h.hexdigest(), when, where, count)


def home(binary: Path) -> Path:
    """The tree a binary was built from. `zig build` installs to
    `<root>/zig-out/bin/`, so the root is three parents up - but only claim
    that when a `build.zig` is actually sitting there, since JOINTS_BIN can
    point anywhere and a wrong guess here would make every other field lie."""
    try:
        guess = binary.resolve().parents[2]
    except IndexError:
        return ROOT.resolve()
    return guess if (guess / "build.zig").is_file() else ROOT.resolve()


def usual() -> Path:
    """The binary an instrument measures when nobody has said otherwise."""
    return ROOT / "zig-out" / "bin" / "joints"


def pinned(binary: Path) -> Source | None:
    """The tree a binary was built from, if the binary wrote it down.

    `home` has to guess, and above a private prefix it guesses wrong in the one
    direction that matters: no `build.zig` sits over `.local/pin/<x>/bin/`, so
    it falls back to the repo and `take` then compares the live tree against
    itself. `drift` is False for every pinned binary, forever - which means the
    binary you pinned *because* you expected the tree to move under it is
    precisely the one that could never say so. That is not a missing feature,
    it is an instrument that is quietest where the hazard is loudest.

    `tool/pin.py` records the digest at build time beside the binary, so when
    that record is there it is read rather than re-derived. Nothing else
    changes: an unpinned binary keeps the guess, because for `zig-out` the
    guess is right.
    """
    try:
        got = json.loads((binary.resolve().parents[1] / "pin.json").read_text())
        # `touched` is the newest source mtime at build time, so `stale` keeps
        # meaning "an in-place rebuild is overdue" - which for a snapshot is
        # never, and should read as never rather than as an accident.
        return Source(Path(got["root"]), got["tree"], got["touched"],
                      got["newest"], got["files"])
    except (OSError, ValueError, KeyError, IndexError):
        return None


class Stamp(NamedTuple):
    binary: str
    build: str  # sha256 of the bytes that ran
    built: float  # its mtime
    source: str  # the tree it was built from, relative to the repo
    tree: str  # digest of that tree's sources
    live: str  # digest of the repo's sources, right now
    newest: str  # most recently touched file under `source`
    commit: str
    dirty: int  # uncommitted files in the repo, for context
    stale: bool  # `newest` is newer than the binary
    drift: bool  # `tree` and `live` disagree
    told: bool  # JOINTS_BIN chose this binary rather than the default
    when: float

    def moved(self) -> tuple[bool, str]:
        """Did the repo's sources change since this stamp was taken?

        Answered now rather than at `take` time, because it is a question about
        an interval and the interval is not over until somebody prints. Four
        lanes land in this tree while a sweep runs; three of today's gate runs
        read three different tree digests inside one minute. A number taken
        across a moving tree is not wrong, but it is not a measurement of either
        tree, and only the run itself can say which it was.
        """
        now = survey(ROOT.resolve())
        return now.digest != self.live, now.where

    def as_dict(self) -> dict:
        shifted, where = self.moved()
        return {
            "binary": self.binary, "build": self.build[:12],
            "built": iso(self.built), "source": self.source,
            "tree": self.tree[:12], "live": self.live[:12],
            "newest": self.newest, "commit": self.commit[:12],
            "dirty": self.dirty, "stale": self.stale, "drift": self.drift,
            "told": self.told, "moved": shifted, "moved_at": where if shifted else "",
            "when": iso(self.when),
        }

    def line(self) -> str:
        """One line plus a warning per hazard, meant for the foot of a report.

        Printing is where `moved` gets asked, so calling this at the end of a
        run is what makes the interval the run's own.
        """
        out = [f"stamp: joints {self.build[:9]} at {self.binary}"
               f" built {iso(self.built)} from {self.source} {self.tree[:9]}"
               f" · repo {self.commit[:9]}+{self.dirty} · run {iso(self.when)}"]
        if self.told:
            # The press lane nearly published "rust regressed" off an exported
            # JOINTS_BIN left over from a scratch build. A deliberate override
            # is legitimate and this is not an error; it just has to be visible,
            # because the one thing it looks like otherwise is the default.
            out.append(f"stamp: TOLD - JOINTS_BIN chose this binary; the tree's"
                       f" own is {here(usual())}")
        if self.stale:
            out.append(f"stamp: STALE - {self.source}/{self.newest} is newer than"
                       " the binary; rebuild before believing this")
        if self.drift:
            out.append(f"stamp: DRIFT - the binary's tree {self.tree[:9]} is not"
                       f" the repo's {self.live[:9]}; this measures a tree that"
                       " no longer exists")
        if old := sorted(p for p, s in FED.items() if Path(p).suffix in PRESSED
                         and s[0].mtime and s[0].mtime < self.built):
            out.append(f"stamp: FED - {len(old)} pressed artifact(s) older than the"
                       f" binary, so this measures whatever pressed them:"
                       f" {', '.join(here(Path(p)) for p in old[:3])}"
                       + (f" (+{len(old) - 3} more)" if len(old) > 3 else ""))
        shifted, where = self.moved()
        if shifted:
            out.append(f"stamp: MOVED - {where} changed while this ran"
                       f" ({time.time() - self.when:.0f}s); the tree it describes"
                       " is not the tree you are reading")
        # Last, and printed whether or not it fires. `MOVED` says the *repo*
        # moved; this says whether the artifacts the numbers were actually read
        # off did, which is a different question and the one no line answered.
        # A claim that only appears when it fails is a claim nobody reads.
        if FED:
            out.append(reconcile().line())
        return "\n".join(out)


def iso(when: float) -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(when))


def here(path: Path) -> str:
    """A path said the shortest way that still identifies it."""
    try:
        return str(path.resolve().relative_to(ROOT.resolve()))
    except ValueError:
        return str(path)


def verdict(stderr: str, source: Path | str, reader=None) -> str:
    """What the parse said, with its own prefix stripped rather than guessed at.

    The line is `joints: <path>: <verdict>` and *both* halves of the prefix
    can be followed by more of the same delimiter, because a verdict can name
    the token it refused: python's reads `unexpected : at 482 in state 880`.
    Four instruments took the tail after the last `": "` and so reported that
    wall as `at 482 in state 880`, dropping the one field that said which token
    it was. The prefix is not a thing to infer - we passed the path in, and the
    binary echoes it verbatim - so strip exactly that and no colon anywhere in
    the payload or the path can move the boundary.

    **Which line, and why it is a search rather than an index.** The stop is
    not the last line. `inquest` prints *after* it, prefixed with the grammar
    rather than the source, on every one of the eighteen rows that hit a wall -
    which is to say on every row anybody is reading this for. Taking the last
    line handed inquest's prose back as the verdict, and because `outcome`
    derives `kind`, `reach`, `roots`, `at` and `wall` from this one string, all
    five went with it: seventeen mending grammars reported `mends 0`,
    `kind state`, `reach 0`, and no wall at all. `walls.py` then found nothing
    to step past and reported `0 crossed, 0 distinct` for every walled grammar
    in the corpus, so its `voice` - mends per distinct wall - read 0.0 with a
    zero on *both* sides of the divide.

    So the line is the one the *source* names, found by asking rather than by
    counting from either end. The binary prints exactly one of those (yaml, the
    grammar that lexes nothing, prints none and falls through below), so this
    cannot become the same guess in the other direction.

    `reader` exists for the gates and nothing else: it lets `stops` drive a
    superseded generation of the prefix rule through this same derivation and
    print what that generation got wrong, which is the only way to *see* a gate
    bite instead of asserting that it does. Callers leave it alone.
    """
    reader = reader or behind
    lines = [ln for ln in reversed(stderr.splitlines()) if ln.strip()]
    for line in lines:
        if (rest := reader(line, source)) is not None:
            return rest
    # Nothing here is about this file: another tool's line, a path the binary
    # rewrote, or a refusal printed before the parse got a source at all. The
    # last line is still the closest thing to an answer; two fields of prefix
    # at most, which is still better than counting from the right.
    return lines[0].split(": ", 2)[-1] if lines else "(silent)"


def behind(line: str, source: Path | str) -> str | None:
    """What one `joints: <path>: ` line says, or None if it is not one.

    The prefix is never a thing to *infer* - the caller passed the path in and
    the binary echoes it back verbatim. Three readers inferred it anyway, two
    of them with a non-greedy `.*?: ` that quietly takes too little the moment
    a path or a payload contains the delimiter.

    So the verbatim prefix is still tried first and is still the only fast path.
    What is new is the second half: a caller that spells the path differently
    from the way the binary echoed it - relative against absolute, a resolved
    symlink, a `./` or a doubled slash - used to get **None for every line**,
    fall through `verdict`'s last resort, and be handed an `inquest` line back
    as the stop. That is the fourth reader's defect re-armed, and it was pinned
    as a live hazard rather than fixed because every caller in this tree happens
    to pass the object it invoked with. Nothing made that hold tomorrow.

    The cure is to compare the two spellings as **paths** instead of as strings:
    walk this line's `": "` boundaries and accept the first left half that names
    the same file as `source`. `same()` is lexical unless both sides exist, so a
    fixture path is compared without touching the disk and a real one gets its
    symlinks resolved. Two different files never compare equal, which is what
    keeps this from becoming "trust any prefix" - the `./a.md` against `/a.md`
    row in `STOPS` is exactly that control and still reads None.
    """
    head = f"joints: {source}: "
    if line.startswith(head):
        return line[len(head):]
    if not line.startswith(SAYS):
        return None
    body, want, at = line[len(SAYS):], same(source), -1
    while (at := body.find(": ", at + 1)) >= 0:
        if same(body[:at]) == want:
            return body[at + 2:]
    return None


SAYS = "joints: "


def same(path: Path | str) -> str:
    """One spelling of a path reduced to the file it names.

    `realpath` when the thing is on disk - that is the only reading that sees
    through a symlink - and a lexical `abspath` when it is not, so a fixture
    naming `/a.md` is still comparable without inventing a file. Both halves are
    normalised the same way, which is the whole requirement: the answer only ever
    gets compared against another answer from this function.
    """
    text = str(path)
    try:
        return os.path.realpath(text) if os.path.exists(text) else os.path.abspath(text)
    except OSError:
        return os.path.normpath(text)


STATE = re.compile(r"in state \d+")
AT = re.compile(r"\bat (\d+)")
# `mended 16635 over 17314B` - the count and the bytes it walked past. Both are
# read here rather than in the instrument that wants the second one, because the
# byte fuse is stated as a *share of the file* and a share needs a numerator
# nobody else is entitled to spell.
MENDED = re.compile(r"mended (\d+)(?: over (\d+)B)?")
BLIND = re.compile(r"blind to (\d+)")
# `, UNSOUND: 1 loose, 0 disorder, 0 torn [...]` - what `Quire.survey` found
# wrong with the forest, printed by `parse.zig` on the stop's own line because
# it is the same kind of fact: what this parse handed back.
#
# It is read here and lifted off the verdict in one pattern, so a caller gets
# the stop and the soundness as two answers instead of one string it has to
# slice. Searched over the whole stderr rather than over the verdict, because
# the last `joints:` line is the *owner*'s on every grammar that hit a wall -
# so on twelve of the thirty the clause is not on the line a verdict comes from.
UNSOUND = re.compile(r", UNSOUND: (.*)")
# `, surveyed 731 of 731 nodes` - the POSITIVE half of the same clause, printed
# by `parse.zig` on every parse whether it liked the tree or not.
#
# Without it, `UNSOUND` above is evidence by absence, and an absence is what a
# binary that stopped calling `Quire.survey` produces too - so thirty rows would
# read `sound` off a check nobody ran. That is the identical defect `collate`'s
# `recall` and `shear`'s `cut_rubble` were each repaired for on 2026-08-06, in
# the last place it still lived and the one guarding the only cheap interior
# check this project has.
#
# `walked of held` rather than a bare "surveyed", because a claim with a size in
# it can be checked: a caller can insist the walk covered the arena instead of
# merely declining to complain about it. An older binary prints no clause, and
# `Outcome.surveyed` stays -1 to say so - which is `unasked`, and is not `sound`.
SURVEYED = re.compile(r", surveyed (\d+) of (\d+) nodes?")
SPAN = re.compile(r"\[\d+, (\d+)\)")
ROOTS = re.compile(r"(\d+) roots?")
WALL = re.compile(r"unexpected (.+?) at \d+ in state (\d+)")


class Outcome(NamedTuple):
    kind: str  # whole · unclosed · mended · lexical · state · timeout · other
    reach: int  # bytes read; -1 when only the forest can say and it was not given
    verdict: str
    mends: int
    blind: int  # externally scanned terminals we cannot run
    roots: int = 1
    tree: str = ""  # the forest, when the caller asked for one
    code: int = 0  # the binary's own exit status; 2 is a refusal, not a parse
    skipped: int = 0  # bytes recovery walked past, which is what the fuse caps
    unsound: str = ""  # what `Quire.survey` found wrong with the forest, if anything
    # Nodes the survey walk reached, and nodes the arena held. **-1 means the
    # parse never said it surveyed**, which is a different answer from zero and
    # a very different answer from `unsound == ""`.
    surveyed: int = -1
    arena: int = -1

    @property
    def looked(self) -> bool:
        """Did anything actually inspect the shape of this forest?

        The distinction `unsound` alone cannot draw. An empty `unsound` means
        "the survey complained about nothing", and a binary that never ran the
        survey complains about nothing too - so a gate reading only that word
        turns *I could not look* into *I looked and it was fine*, which is the
        vacuous pass this repository has now caught in four instruments.

        Read off the positive clause, so it is false for an older binary and
        false the day someone deletes the `survey` call - loudly, on every row
        at once, rather than quietly on the one row that would have failed.
        """
        return self.surveyed >= 0

    @property
    def covered(self) -> bool:
        """Did the walk reach every node the arena held?

        Not a soundness claim: an arena may hold a node no root reaches, and
        `Quire.survey` deliberately does not call that a fault. It is the
        strength of the positive signal - `walked == held` says the check saw
        the whole forest, where `walked < held` says part of it went unlooked-at
        inside a parse that still reported nothing wrong.
        """
        return self.looked and self.surveyed == self.arena

    @property
    def wall(self) -> tuple[str, int] | None:
        """*Which* wall this stop names - the terminal and the LR state - or
        None if nothing stopped it.

        A property rather than a field because it is a second reading of the
        verdict already stored, and `walls.py` asking for it is exactly the
        moment a twelfth instrument would have written a twelfth regex over
        `in state`. The count of mends says how often the parse fell over; this
        says whether it fell over the same thing each time, which is the
        difference between a bounded tail and a second project."""
        m = WALL.search(self.verdict)
        return (m[1], int(m[2])) if m else None

    @property
    def at(self) -> int | None:
        """The byte the verdict **names**, which is not `reach`.

        These come apart precisely where it matters most. Haskell says
        `unexpected . at 681 in state 7, 94 roots, mended 4940` over a 34,240
        byte file: 681 is where trouble began and 34,239 is where the parse got
        to, and `reach` is deliberately the second because a mended verdict
        would otherwise report the parses that read the *most* as reading least.
        Anything asking "what stopped it, and where is that" needs the first,
        and reading `reach` for it silently answers a question about the end of
        the file. That mistake cost this project a retracted wall count."""
        return int(m[1]) if (m := AT.search(self.verdict)) else None

    @property
    def stray(self) -> int | None:
        """`at`, but only when the stop was a *lexical* one.

        `kind` reports `mended` the moment anything mended, so a caller reading
        it alone cannot tell julia's `stray byte at 87 ... mended 4749` from a
        table refusing a token. The two stops have different owners, so anything
        enumerating them has to tell them apart."""
        return self.at if self.verdict.startswith("stray byte") else None


def furthest(tree: str) -> int:
    """The last byte any root covers, which is what an editor actually asks."""
    return max((int(m) for m in SPAN.findall(tree)), default=0)


def outcome(stderr: str, source: Path | str, size: int, tree: str = "",
            reader=None) -> Outcome:
    """What the parse did and how far it got, in one rule.

    There were three of these. `census` and `breadth` each read a wall out of
    the verdict, and `recover` read a fourth kind the other two do not have -
    **`mended`, which means the parse hit a wall, put the stack down and kept
    reading.** A mended verdict still names its *first* stop, because that is
    where the trouble began, so the two copies that count `at N` as the answer
    now report the parses that read the most as the ones that read least. That
    is the same defect `recover` was fixed for, living on in the copies nobody
    fixed - which is the argument for there being one of these.

    Where a mended parse got to is a question for the forest rather than the
    verdict, so pass `tree` when the answer has to be right; without it the
    reach is -1 and says so rather than guessing zero.

    `reader` is `verdict`'s, for the gates only - every field below is derived
    from the one string it returns, which is exactly why a gate has to be able to
    swap it and watch all five fields go wrong together.
    """
    # The soundness clause is lifted off the stop rather than left riding it.
    # Two facts on one line is how one of them ends up sliced off in every
    # reader that wants the other, and the board was already doing exactly that.
    sound = m[1] if (m := UNSOUND.search(stderr)) else ""
    # Lifted off the same way and for the same reason. Both clauses are facts
    # about the forest rather than about the stop, and a `verdict` string
    # carrying them would move under every reader that string-matches a stop -
    # `SHAPES` below pins that it does not.
    walk = SURVEYED.search(stderr)
    said = SURVEYED.sub("", UNSOUND.sub("", verdict(stderr, source, reader)))
    hit = MENDED.search(said)
    mends = int(hit[1]) if hit else 0
    skipped = int(hit[2]) if hit and hit[2] else 0
    blind = int(m[1]) if (m := BLIND.search(stderr)) else 0
    roots = int(m[1]) if (m := ROOTS.search(said)) else 1
    rest = (mends, blind, roots, tree)
    tail = {"skipped": skipped, "unsound": sound,
            "surveyed": int(walk[1]) if walk else -1,
            "arena": int(walk[2]) if walk else -1}
    if said.startswith("accepted"):
        return Outcome("whole", size, said, *rest, **tail)
    if said.startswith("truncated"):
        # Every byte lexed, no root closed. Reporting this as reach 0 is what
        # made five files read as unparsed while the lexer had read them whole.
        return Outcome("unclosed", size, said, *rest, **tail)
    if mends:
        return Outcome("mended", furthest(tree) if tree else -1, said, *rest, **tail)
    kind = ("lexical" if said.startswith("stray byte")
            else "state" if STATE.search(said) else "other")
    return Outcome(kind, int(m[1]) if (m := AT.search(said)) else 0, said, *rest, **tail)


PATIENCE = 120.0


class Sight(NamedTuple):
    """One observation of one artifact's identity, at the moment it was read.

    `mark` is a digest of the bytes and not an mtime, because the question is
    not *when was this written* but **did these two rows read the same bytes**,
    and only the bytes answer that. An mtime is wrong in both directions at
    once: it moves when identical bytes are republished (and a channel that
    cries wolf is a channel people learn to scroll past - `stale` already had
    to stop counting `*_test.zig` for exactly that reason), and it is a
    correlated proxy rather than an identity, so a folio restored from a copy
    that preserved it reads as the same artifact when it is not.

    `mtime` rides along anyway because the FED warning below asks a genuinely
    different question - *was this pressed before the binary was built* - and
    an mtime is the right answer to that one.
    """

    path: str
    mark: str  # sha256 of the bytes as they were read; "gone" if it vanished
    size: int
    mtime: float
    when: float
    row: str  # what was being measured when it was read; "" for the reconcile pass


FED: dict[str, list[Sight]] = {}
# Only artifacts the binary itself PRESSES are worth watching **for age**. A
# `grammar.json` is a checked-in source and is older than every binary ever
# built from this tree, so flagging it would be noise that trains people to
# ignore the channel. A folio is derived, and a derived artifact older than the
# binary may have been pressed by an older one - which is how a fixed parser can
# be measured with a broken lexer and look unfixed.
#
# The generation ledger below has no such filter: *every* artifact a run read is
# one the run's numbers depend on, including the binary itself.
PRESSED = (".folio",)


def fed(artifact: Path | str, row: str = "") -> None:
    """Record what an instrument was handed, **by its content, at read time**.

    Three instrument bugs in one session each produced a *plausible* number:
    a peel stepping past `reach` instead of `at`, a cache handing back a folio
    minted before the fix it was measuring, and a classifier that could not
    return "I do not know". None had an oracle. This is the cheapest general
    one - not correctness, but **provenance**: whatever an instrument actually
    read is named in its own output, so a stale input is visible on the page
    rather than reconstructed hours later from a discrepancy.

    It used to record an mtime, which said an artifact was *there* and nothing
    about what was in it. That is the gap `reconcile` closes: folios are
    published with `os.replace`, so a re-mint landing mid-run hands every
    reader a whole, individually valid folio and leaves no torn byte anywhere
    to notice it by. A board can assemble a table out of two generations, print
    `cache: kept 30`, and be telling the truth about the question it asked.

    The digest is taken microseconds before the exec that reads the file, not
    by the reader itself, so a publish landing inside that window is still
    invisible to this. Closing it for real needs the binary to print the digest
    of the bytes it mapped; that is `src/folio`'s to say, not ours to infer, and
    it is a hole rather than a scope.
    """
    p = Path(artifact)
    try:
        mark, it = digest(p), p.stat()
        size, mtime = it.st_size, it.st_mtime
    except OSError:
        # An artifact that vanished between being chosen and being read is
        # itself a fact about this tree state - record it rather than dropping
        # the one observation that would have explained the row.
        mark, size, mtime = "gone", 0, 0.0
    FED.setdefault(str(p), []).append(Sight(str(p), mark, size, mtime, time.time(), row))


def swapped(artifact: Path | str) -> str:
    """Say so if this is no longer the artifact the run first read, else "".

    Asked at the moment a caller is about to blame something, and the caller
    that needs it is `order.folio_for`: when a press is followed by a refusal
    it says *the binary disagrees with itself about its own folio format*, and
    that reading is only true while there is one binary. Swap the binary
    mid-run - which is what the 2026-08-05 event did - and the press and the
    read are two different programs, so the sentence names the wrong culprit
    at exactly the moment somebody is deciding whether to trust a whole run.
    """
    seen = FED.get(str(Path(artifact)))
    if not seen:
        return ""
    try:
        now = digest(Path(artifact))
    except OSError:
        now = "gone"
    return "" if now == seen[0].mark else f"{seen[0].mark[:9]} → {now[:9]}"


class Moved(NamedTuple):
    """One artifact that was not the same thing throughout a run."""

    path: str
    rows: tuple[str, ...]  # what was being measured against a generation now gone
    was: str  # the generation those rows read - or the first one seen, if none
    now: str  # what is at that path once the run is over
    seen: int  # distinct generations this run saw at this path


class Ledger(NamedTuple):
    """Whether every row of a run was measured against one generation."""

    artifacts: int
    reads: int
    moved: tuple[Moved, ...]
    when: float
    # Artifacts republished under the run with **identical bytes** - the same
    # folio pressed again, atomically renamed on, and nothing about any
    # measurement changed. Carried because it is precisely what an mtime rule
    # would have called a split, and keeping the old rule's answer beside the
    # new one is the only way the difference between them stays visible after
    # the argument for it has been read once.
    republished: tuple[str, ...] = ()

    @property
    def uniform(self) -> bool:
        """Is every live row's artifact the one this tree holds now?

        Not "did nothing move" - an artifact may move mid-run and every row
        that read the old generation may then be re-measured, which leaves the
        table whole. `churned` is that case, and it is worth telling apart:
        one is a table nobody can read, the other is a tree that shifted and a
        board that noticed and caught up.
        """
        return not any(m.rows for m in self.moved)

    @property
    def churned(self) -> int:
        return sum(1 for m in self.moved if not m.rows)

    @property
    def rows(self) -> tuple[str, ...]:
        """Every row measured against an artifact this tree no longer holds."""
        return tuple(sorted({r for m in self.moved for r in m.rows}))

    def as_dict(self) -> dict:
        return {"artifacts": self.artifacts, "reads": self.reads,
                "uniform": self.uniform, "churned": self.churned,
                "rows": list(self.rows),
                "republished": [here(Path(p)) for p in self.republished],
                "moved": [{"path": here(Path(m.path)), "was": m.was[:12],
                           "now": m.now[:12], "generations": m.seen,
                           "rows": list(m.rows)} for m in self.moved],
                "when": iso(self.when)}

    @property
    def aside(self) -> str:
        if not self.republished:
            return ""
        return (f" ({len(self.republished)} republished under it with identical bytes,"
                f" which an mtime rule would have called a split)")

    def line(self) -> str:
        if self.uniform:
            head = (f"generation: {self.artifacts} artifact(s) over {self.reads} read(s),"
                    f" one generation each — every row was measured against what this"
                    f" tree holds now{self.aside}")
            if not self.churned:
                return head
            return head + (f"\n  {self.churned} of them moved mid-run and every row that"
                           f" read the old generation was measured again: "
                           + ", ".join(here(Path(m.path)) for m in self.moved))
        out = [f"stamp: SPLIT - {len(self.moved)} of {self.artifacts} artifact(s) moved"
               f" after they were read, so this run is NOT one measurement."
               f" {len(self.rows)} row(s) span generations: {', '.join(self.rows)}"
               + self.aside]
        for m in self.moved:
            out.append(f"  {here(Path(m.path))}: read {m.was[:9]}, now {m.now[:9]}"
                       f" ({m.seen} generations this run)"
                       + (f" — measured: {', '.join(m.rows)}" if m.rows else
                          " — no live row read the old one"))
        return "\n".join(out)


_settled: Ledger | None = None


def reconcile(again: bool = False) -> Ledger:
    """Re-read every artifact this run was handed, and say which ones moved.

    The one question the folio cache structurally cannot answer. `order.miss`
    decides, per row, whether the folio on disk is usable *at the moment it is
    asked*, and reports that decision - `cache: kept 30`. Between that decision
    and the end of the board sits the entire measurement, and on 2026-08-05 a
    sibling's `zig build` landed at 11:43:49 and something re-minted all thirty
    folios between 11:43:55 and 11:44:04 while the board was running and
    printing exactly that line.

    So the claim is made the only way it can be: each read is stamped with the
    bytes it read, and at the end every artifact is read again. If a row's
    generation is still the generation on disk, that row was measured against
    what this tree holds now. If it is not, **that row is named**, because a
    partial answer that knows it is partial is worth more here than a clean
    number averaged over two trees.

    One read per artifact plus one pass at the end is exactly enough for that
    claim, and no bracket around each exec is needed for it: a change landing
    during a parse still leaves the artifact different at the end. The one
    shape it cannot see is A→B→A - two publishes inside one run that restore
    the original bytes - which needs two different minters and a coincidence,
    and is stated here rather than defended against.

    Idempotent within a run: the interval it closes ends at the **first** call,
    which is where the caller stopped measuring. `again=True` re-opens it, which
    is what a caller re-measuring the named rows wants.
    """
    global _settled
    if _settled is not None and not again:
        return _settled
    moved, again_, reads = [], [], 0
    for path, sights in sorted(FED.items()):
        seen = list(sights)  # snapshot: the reconcile sighting is appended below
        reads += len(seen)
        fed(path)  # the closing observation, unlabelled - it measured nothing
        close = FED[path][-1]
        now, marks = close.mark, {s.mark for s in seen} | {close.mark}
        if len(marks) == 1:
            if len({s.mtime for s in seen} | {close.mtime}) > 1:
                again_.append(path)
            continue
        # The **last** read a row made, not every read it ever made: a caller
        # that re-measures a named row appends a fresh sighting, and a row that
        # has since been measured against the live generation is no longer one
        # of the run's problems. Judging on every sighting would make `--settle`
        # structurally unable to settle anything.
        last: dict[str, Sight] = {s.row: s for s in seen if s.row}
        stale = tuple(sorted(r for r, s in last.items() if s.mark != now))
        # With no stale row, `was` is the generation this run FIRST saw rather
        # than the last: the last one is the settled one, and printing "read X,
        # now X" of an artifact the same line calls moved reads as a bug.
        was = last[stale[0]].mark if stale else seen[0].mark
        moved.append(Moved(path, stale, was, now, len(marks)))
    _settled = Ledger(len(FED), reads, tuple(moved), time.time(), tuple(again_))
    return _settled


def ask(binary: Path | str, grammar: Path | str, src: Path | str, *,
        size: int | None = None, tree: bool | None = None,
        patience: float = PATIENCE, extra: tuple[str, ...] = ()) -> Outcome:
    """Run one parse and say what it did. **The only place an instrument reads
    joints's stderr**, which is the point of it existing.

    Four instruments each ran the binary and read the answer back themselves,
    and three of them got a different answer out of the same bytes. Consolidating
    the *rule* into `outcome` fixed that once; it did not stop the next
    instrument from calling `subprocess` and writing a fifth reader, and it left
    the mended re-run spelled separately in two files. So the rule is not the
    thing to share - the whole exchange is.

    `tree` is one knob with three meanings, because "do I want the forest" and
    "do I need the right reach" are the same question asked from either end:

      None   ask for it only if the parse turns out to have mended, which is
             the only verdict whose reach the forest alone can answer. Right,
             and it costs a second run on the few files that need one.
      False  never ask. A mended reach comes back -1 and says so rather than
             quietly reporting the byte where trouble began.
      True   always ask, for a caller that wants the nodes as well as the number.
    """
    src = Path(src)
    size = src.stat().st_size if size is None else size
    forest = ("--ranges", "--all")
    # What this parse reads, named by what it is measuring. The row label is
    # inferred rather than passed, because every caller's row already *is* the
    # grammar's own stem and a parameter is one more thing to forget.
    #
    # The binary is fed too, and that is not decoration: it is the artifact the
    # 11:43:49 event actually replaced. `take` digests it once at the start of a
    # run and nothing looks again, so a `zig build` landing mid-board splits the
    # table by build and no detector here sees it - `STALE` and `DRIFT` and
    # `MOVED` all watch the *sources*, and a rebuild need not touch one.
    row = Path(grammar).stem
    fed(grammar, row)
    fed(binary, row)

    def run(*flags: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run([str(binary), "parse", str(grammar), str(src), *flags],
                              capture_output=True, text=True, timeout=patience, cwd=ROOT)
    try:
        got = run(*(forest if tree else ("--quiet",)), *extra)
        end = outcome(got.stderr, src, size, got.stdout if tree else "")
        if end.kind == "mended" and tree is None:
            end = outcome(got.stderr, src, size, run(*forest, *extra).stdout)
    except subprocess.TimeoutExpired:
        return Outcome("timeout", 0, f"no answer inside {patience:g}s", 0, 0)
    return end._replace(code=got.returncode)


def take(binary: Path) -> Stamp:
    """Read the tree state around one binary. Never raises: a stamp that failed
    would take a real measurement down with it, and an unknown field still says
    more than no stamp at all."""
    try:
        build, built = digest(binary), binary.stat().st_mtime
    except OSError:
        build, built = "missing", 0.0
    # A binary that wrote down its own tree is believed over a guess from its
    # path, because that is the whole difference between a path and a version.
    snap = pinned(binary)
    root = snap.root if snap else home(binary)
    # `home` resolves, so resolve this side too or a repo reached through a
    # symlink - which is every path under macOS's /var - reads as a foreign
    # tree and reports drift against itself.
    here = ROOT.resolve()
    mine = snap or survey(root)
    live = mine if (not snap and root == here) else survey(here)
    try:
        where = str(root.relative_to(here))
    except ValueError:
        where = str(root)
    return Stamp(binary=str(binary), build=build, built=built,
                 source=where or ".", tree=mine.digest, live=live.digest,
                 newest=mine.where, commit=git("rev-parse", "HEAD") or "unknown",
                 dirty=sum(1 for ln in git("status", "--porcelain").splitlines() if ln.strip()),
                 stale=bool(built and mine.newest > built),
                 drift=mine.digest != live.digest,
                 # Asked of the path, not of the environment, so a caller that
                 # was handed a scratch binary some other way still says so.
                 told=binary.resolve() != usual().resolve(),
                 when=time.time())


# The shapes a verdict line actually comes in, each with the answer derived
# from the format rather than from running the reader. Kept because this class
# of bug - a reader guessing a boundary off a delimiter the payload also uses -
# has now bitten three separate readers of two different tools, and every time
# it was found by a grammar going quiet rather than by a test.
#
# It happened a fourth time, and this table is why it took a month: every shape
# below put its noise ABOVE the verdict, which is the only side a
# take-the-last-line reader survives. The binary had been printing an `inquest`
# line BELOW the stop on eighteen of the thirty rows the whole time, and the
# gate could not see it because the gate had never been shown one. The last
# four rows are that shape, in each of the four voices `inquest` speaks with.
SHAPES: tuple[tuple[str, str, str, str], ...] = (
    ("plain", "/c/ledger.c", "joints: /c/ledger.c: stray byte at 1354, 28 roots",
     "stray byte at 1354, 28 roots"),
    ("colon in the verdict", "/p/ledger.py",
     "joints: /p/ledger.py: unexpected : at 482 in state 880, 52 roots",
     "unexpected : at 482 in state 880, 52 roots"),
    ("colon token, no state", "/p/x.py", "joints: /p/x.py: unexpected : at 7",
     "unexpected : at 7"),
    ("colon in the path", "/o: dd/l.c", "joints: /o: dd/l.c: stray byte at 9",
     "stray byte at 9"),
    ("a warning above it", "/r/ledger.rs",
     "joints: rust: blind to 6 externally scanned terminal(s)\n"
     "joints: /r/ledger.rs: accepted, 1 root", "accepted, 1 root"),
    ("trailing blank lines", "/j/l.json", "joints: /j/l.json: accepted, 1 root\n\n  \n",
     "accepted, 1 root"),
    ("no verdict at all", "/j/l.json", "", "(silent)"),
    ("no colon in the verdict", "/j/l.json", "joints: /j/l.json: truncated", "truncated"),
    # Real stderr, copied off the binary. `inquest`'s prose is another lane's
    # and moves, so each trailing line here is cut at its first sentence: what
    # this table pins is the *shape* - `joints: <grammar>: ` below the stop,
    # with a `: ` inside its own payload, so a reader that falls through to the
    # two-field split does not merely take the wrong line, it takes a fragment
    # of one.
    ("inquest below it", "upstream/sources/Maps.kt",
     "joints: kotlin: blind to 8 externally scanned terminal(s)\n"
     "joints: upstream/sources/Maps.kt: unexpected (?:[^\\r\\n]*) at 270 in state"
     " 433, 419 roots, mended 142 over 142B\n"
     "joints: kotlin: lexer on (?:[^\\r\\n]*) in state 433 [no stand-in for"
     " _string_start, admitted by shift]: this state admits a terminal the grammar"
     " hands to an external scanner we cannot run",
     "unexpected (?:[^\\r\\n]*) at 270 in state 433, 419 roots, mended 142 over 142B"),
    ("press? below it", "upstream/sources/picorv32.v",
     "joints: upstream/sources/picorv32.v: unexpected ` at 3712 in state 3438,"
     " 3544 roots, mended 2109 over 32992B\n"
     "joints: verilog: press? on ` in state 3438 (0 dropped, 24 misfolded): a"
     " merge damaged this terminal's cell elsewhere, and no fold chain was"
     " supplied to say whether this wall is downstream of it",
     "unexpected ` at 3712 in state 3438, 3544 roots, mended 2109 over 32992B"),
    # Two owner lines above and one below, so the search cannot be an off-by-one
    # from the bottom any more than it can be one from the top.
    ("unlexed byte below it", "research/joinery/corpus/README.md",
     "joints: markdown: blind to 47 externally scanned terminal(s)\n"
     "joints: markdown: 1 pattern(s) the engine would not build: entity_reference\n"
     "joints: research/joinery/corpus/README.md: stray byte at 44, 366 roots,"
     " mended 66 over 66B\n"
     "joints: markdown: lexer? at byte 44 (unlexed): no terminal in the grammar"
     " matches here even with the row's restriction lifted, so no table was consulted",
     "stray byte at 44, 366 roots, mended 66 over 66B"),
    # yaml. No line names the source at all, because the refusal happens before
    # a parse exists to name one - so the fallback still has to answer.
    ("no line names the file", "/y/ci.yml",
     "joints: yaml has no lexable terminal at all",
     "yaml has no lexable terminal at all"),
    # The soundness pair riding a stop, with an inquest line beneath it - the
    # real shape twelve of the thirty rows arrive in. `verdict` hands back the
    # whole stop INCLUDING both clauses; lifting them off is `outcome`'s job and
    # `SURVEYS` below is where that is pinned. Here the only claim is that a
    # line grown two clauses longer is still found, on the side of the file the
    # fallback has to search.
    ("surveyed, below a mend, inquest under it", "upstream/sources/Maps.kt",
     "joints: upstream/sources/Maps.kt: unexpected (?:[^\\r\\n]*) at 270 in state"
     " 433, 419 roots, mended 142 over 142B, surveyed 5077 of 5077 nodes\n"
     "joints: kotlin: lexer on (?:[^\\r\\n]*) in state 433 [no stand-in for"
     " _string_start, admitted by shift]: this state admits a terminal the grammar"
     " hands to an external scanner we cannot run",
     "unexpected (?:[^\\r\\n]*) at 270 in state 433, 419 roots, mended 142 over 142B,"
     " surveyed 5077 of 5077 nodes"),
)


# What `outcome` must make of the two forest clauses - the positive one and the
# complaint - in every combination a binary can print them.
#
# `SHAPES` pins which LINE a verdict comes from and `STOPS` pins what is derived
# from it; neither could say anything about these, because both clauses were
# invented after them and one of them was invented today. The row that matters
# most is the last: **a parse that printed no `surveyed` clause is `unasked`,
# not `sound`**, and until 2026-08-06 there was no way to spell that difference.
# `tool/sound.py`'s green over thirty grammars is worth exactly this table.
#
# (name, stderr, verdict, surveyed, arena, unsound)
SURVEYS: tuple[tuple[str, str, str, int, int, str], ...] = (
    ("sound, both numbers lifted off the stop",
     "joints: /t/a.toml: accepted, 1 root, surveyed 731 of 731 nodes",
     "accepted, 1 root", 731, 731, ""),
    ("unsound, and the stop keeps neither clause",
     "joints: /t/a.toml: accepted, 1 root, surveyed 731 of 731 nodes,"
     " UNSOUND: 1 loose, 0 disorder, 0 torn [child outside its parent:"
     " comment [17, 20) in pair [8, 15)]",
     "accepted, 1 root", 731, 731,
     "1 loose, 0 disorder, 0 torn [child outside its parent:"
     " comment [17, 20) in pair [8, 15)]"),
    ("a mended stop still reads its mend after the lift",
     "joints: /v/p.v: unexpected ` at 3712 in state 3438, 3544 roots,"
     " mended 2109 over 32992B, surveyed 41205 of 41205 nodes",
     "unexpected ` at 3712 in state 3438, 3544 roots, mended 2109 over 32992B",
     41205, 41205, ""),
    ("a walk that reached less than the arena holds says so",
     "joints: /x/a.json: accepted, 1 root, surveyed 9 of 11 nodes",
     "accepted, 1 root", 9, 11, ""),
    ("an empty forest surveyed nothing, which is not nothing surveyed",
     "joints: /x/a.json: accepted, 0 roots, surveyed 0 of 0 nodes",
     "accepted, 0 roots", 0, 0, ""),
    # The control, and the whole reason the clause exists. Same absent
    # complaint, same `sound`-looking row - and `surveyed` is -1, so a gate can
    # refuse it instead of counting it clean.
    ("no clause at all is UNASKED, and must not read as sound",
     "joints: /x/a.json: accepted, 1 root",
     "accepted, 1 root", -1, -1, ""),
)


def surveys() -> int:
    """Drive `outcome` over every combination of the two forest clauses.

    Asserted on the derived fields rather than on the regex, because the regex
    is not what a caller holds: `sound.py` reads `got.looked` and the board
    reads `got.surveyed`, and both would go quiet together if the lift moved.
    The last row is the negative control - a stderr with no clause - and it is
    the one that makes the other five worth asserting.
    """
    bad = 0
    print(f"{'case':<63}{'verdict':<8}{'walked':<8}{'held':<7}{'looked':<8}unsound")
    print("-" * 107)
    for what, err, want, walked, held, sick in SURVEYS:
        got = outcome(err, "/x/a.json", 0)
        rows = ((got.verdict, want), (got.surveyed, walked), (got.arena, held),
                (got.looked, walked >= 0), (got.unsound, sick))
        ok = all(a == b for a, b in rows)
        bad += not ok
        print(f"{what:<63}{'ok' if got.verdict == want else 'WRONG':<8}"
              f"{got.surveyed:<8}{got.arena:<7}{str(got.looked):<8}{got.unsound[:22] or '—'}"
              + ("" if ok else "   WRONG"))
        if not ok:
            for a, b in rows:
                if a != b:
                    print(f"{'':<63}got {a!r}, want {b!r}")
    print(f"\n{len(SURVEYS) - bad}/{len(SURVEYS)} forest clauses read correctly"
          f" — including the one that is absent, which is the point")
    return 1 if bad else 0


# A verdict read correctly can still be *derived from* incorrectly, and the two
# failures look identical from outside: a caller sees `wall is None` and cannot
# tell "this stop names no LR state because a byte would not lex" from "the
# reader missed one". Chasing that distinction is how the last count of walled
# grammars came back 15 of 17 and read as a residual bug; it is neither a bug
# nor 15, it is 15 table stops and 2 lexical ones, and `stray` was already there
# to say so. This table is the only thing that keeps the two Nones apart, so it
# pins both halves of every stop: what `wall` says AND what `stray` says.
#
# The source is per row and not a constant, and that is not tidiness. Writing
# this table with one shared `/a` while the fixtures said `/a.ml` put the reader
# straight back into the bug it was written to guard: no line carried the
# prefix, `verdict` fell through to the last line, and the last line was
# `inquest`'s.
#
# That was stated here as a **live hazard** rather than a fixture slip, and it is
# now closed: `behind` compares the two spellings as paths, so a caller naming
# the same file another way is read instead of falling through. The rows below
# are what closes it - three spellings of one real file that must read, and one
# pair of genuinely different files that must not. The last one is the control:
# without it, "resolve the path" and "trust any prefix" pass identically, and
# the second one hands back an inquest line on every walled grammar in the
# corpus. That is the same over-claim the fourth reader made, so it is pinned in
# the direction that catches it.
#
# (name, source, stderr, wall, stray)
STOPS: tuple[tuple[str, str, str, tuple[str, int] | None, int | None], ...] = (
    ("table stop, plain", "/a.c",
     "joints: /a.c: unexpected , at 1354 in state 822, 28 roots", (",", 822), None),
    ("table stop, colon token", "/a.py",
     "joints: /a.py: unexpected : at 482 in state 880", (":", 880), None),
    ("lexical stop", "/a.md",
     "joints: /a.md: stray byte at 20, 430 roots, mended 79 over 79B", None, 20),
    ("lexical stop, inquest below", "/a.ml",
     "joints: /a.ml: stray byte at 1996, 167 roots, mended 28 over 28B\n"
     "joints: ocaml: lexer? at byte 1996 (unlexed): no terminal matches here",
     None, 1996),
    # The one shape where both must be None: a stop with neither a state nor a
    # byte. Without it a `stray` that simply returned `at` unconditionally would
    # pass every row above.
    ("neither", "/a.json", "joints: /a.json: truncated", None, None),
    # The three spellings the hazard was about, each against a stop the reader
    # has to recover. Every one of these returned None - and therefore handed
    # back the `inquest` line under it - until `behind` compared paths.
    #
    # `tool/stamp.py` is used because it exists: a spelling only resolves through
    # `./`, `//` and a symlink if there is a file at the end of it, so a fixture
    # over an invented path would test the lexical half twice and the disk half
    # never. The stops are synthetic; only the prefix is real.
    ("same file, dot segment", "tool/./stamp.py",
     "joints: tool/stamp.py: unexpected , at 1354 in state 822, 28 roots\n"
     "joints: python: press? on , in state 822: this cell is one a merge invented",
     (",", 822), None),
    ("same file, doubled slash", "tool//stamp.py",
     "joints: tool/stamp.py: stray byte at 20, 430 roots, mended 79 over 79B\n"
     "joints: python: lexer? at byte 20 (unlexed): no terminal matches here",
     None, 20),
    ("same file, absolute against relative", str(ROOT / "tool" / "stamp.py"),
     "joints: tool/stamp.py: unexpected : at 482 in state 880\n"
     "joints: python: weave? on : in state 880: refused under every split",
     (":", 880), None),
    # And the control, which must stay None: two spellings that name **different
    # files**. `./a.md` is under this process's cwd and `/a.md` is at the root, so
    # a reader that resolved them to the same file would be trusting any prefix -
    # and would then read `inquest`'s line as a stop wherever the binary's own
    # grammar-prefixed line came last, which is twelve of the thirty rows.
    ("different files, not read", "./a.md",
     "joints: /a.md: stray byte at 20, 430 roots, mended 79 over 79B\n"
     "joints: markdown: lexer? at byte 20 (unlexed): no terminal matches here",
     None, None),
)


def verbatim_rule(line: str, source: Path | str) -> str | None:
    """Generation four of the prefix rule: the path matched as a **string**.

    Kept as a column rather than deleted, because a fixture that only ever sees
    the fixed reader cannot show that it is fixing anything - and the three
    spellings added to `STOPS` are precisely the rows a later reader would
    suspect of having been written to pass. Under this rule they read an
    `inquest` line as the stop, which is the whole defect in person.
    """
    head = f"joints: {source}: "
    return line[len(head):] if line.startswith(head) else None


def stops() -> int:
    """`wall` and `stray` together, over every stop shape, against both rules.

    Anti-vacuity is the whole point of two of these rows. Three of the first four
    would pass against a `stray` that returned `at` whenever it was set, and that
    reader would then claim a lexical stop on every walled grammar in the corpus.
    And `different files, not read` is the other direction: it is the row that
    fails if comparing spellings as paths ever slackens into trusting any prefix.
    """
    bad, saved = 0, 0
    print(f"{'stop':<36}{'wall':<20}{'stray':<8}{'verbatim':<10}verdict")
    print("-" * 104)
    for what, src, err, want_wall, want_stray in STOPS:
        out = outcome(err, src, 1)
        was = outcome(err, src, 1, reader=verbatim_rule)
        ok = out.wall == want_wall and out.stray == want_stray
        held = was.wall == want_wall and was.stray == want_stray
        bad += not ok
        saved += ok and not held
        print(f"{what:<36}{str(out.wall):<20}{str(out.stray):<8}"
              f"{'ok' if held else 'wrong':<10}{out.verdict[:30]}"
              f"{'' if ok else f'  WRONG - want {want_wall} / {want_stray}'}")
    named = sum(w is not None for *_, w, _ in STOPS)
    lex = sum(s is not None for *_, s in STOPS)
    print(f"\n{len(STOPS) - bad}/{len(STOPS)} stops read correctly "
          f"({named} name a state, {lex} name a byte, "
          f"{len(STOPS) - named - lex} name neither - a count of walls that "
          f"expects {len(STOPS)} is counting the wrong thing)")
    print(f"{saved} of them the verbatim rule got wrong, so the path comparison is "
          f"load-bearing on {saved} row(s) rather than on none.")
    return 1 if bad else 0


def rsplit_rule(stderr: str, _: object) -> str:
    """Generation one: take the last line, take what follows its last `": "`.
    Loses the token a verdict names whenever the token is a colon."""
    line = stderr.strip().splitlines()[-1] if stderr.strip() else "(silent)"
    return line.rsplit(": ", 1)[-1]


def lastline_rule(stderr: str, source: Path | str) -> str:
    """Generation two: strip the prefix we passed in, but only off the **last**
    non-blank line. Correct about the boundary and wrong about the line, which
    is the fourth time this reader has been wrong and the first time it was
    wrong on eighteen rows at once."""
    line = next((ln for ln in reversed(stderr.splitlines()) if ln.strip()), "")
    if (rest := behind(line, source)) is not None:
        return rest
    return line.split(": ", 2)[-1] if line else "(silent)"


def probe() -> int:
    """Drive the reader across every shape, and **both** rules it replaced
    beside it, so the gate is seen to bite rather than asserted to.

    Two superseded columns rather than one, because a gate that only carries
    the oldest wrong rule cannot show that its newest shapes are load-bearing:
    every one of the eight original shapes is read correctly by generation two,
    so against that column alone the four new rows would be the only evidence
    the table is doing anything - and they are exactly the rows a reader would
    suspect of having been written to pass.
    """
    prior = (("rsplit", rsplit_rule), ("last line", lastline_rule))
    bad = 0
    print(f"{'shape':<24}{'reads':<8}" + "".join(f"{n:<12}" for n, _ in prior) + "want")
    print("-" * 104)
    for what, src, err, want in SHAPES:
        got = verdict(err, src)
        bad += not (ok := got == want)
        print(f"{what:<24}{'ok' if ok else 'WRONG':<8}"
              + "".join(f"{'ok' if fn(err, src) == want else 'wrong':<12}" for _, fn in prior)
              + want[:44])
        if not ok:
            print(f"{'':<24}got {got!r}")
    print()
    for name, fn in prior:
        missed = [w for w, s, e, want in SHAPES if fn(e, s) != want]
        # ` · `, not `, `: one shape is called "colon token, no state", so a
        # comma-joined list of five reads as six and the count beside it looks
        # like an off-by-one in the gate. It was the separator, which is the
        # cheap version of reading your own presentation back as a fact.
        print(f"  the {name} rule gets {len(missed)}/{len(SHAPES)} wrong: {' · '.join(missed)}")
    print(f"\n{len(SHAPES) - bad}/{len(SHAPES)} shapes read correctly")
    return 1 if bad else 0


def plumbed() -> int:
    """Not "does the detector fire" - `hazards` asks that, with a synthetic
    sighting. This asks the question that was never asked: **is the artifact
    the detector is for ever handed to it?**

    `Ledger.moved` and `Ledger.republished` read `[]` on all 67 ledgers on
    disk, and `hazards` has always shown SPLIT firing, because it plants the
    sighting itself. What no test asked is where sightings come from. `ask`
    fed the grammar and the binary; `press` fed the binary; nothing fed the
    **folio** - the one artifact in this system that is re-minted while boards
    are running, and the exact thing `reconcile`'s own docstring is about. So
    the ledger truthfully reported that no checked-in source moved under a run,
    which is not what "the artifact that moved" says to a reader.

    Three claims, in the order they failed: the two columns fire on real bytes,
    and the folio a run is handed reaches `FED`.
    """
    import shutil
    import tempfile
    global _settled
    ok = True
    hold = Path(tempfile.mkdtemp(prefix="stamp-"))
    was_fed, was_settled = dict(FED), _settled
    try:
        FED.clear()
        _settled = None
        split, same = hold / "a.folio", hold / "b.folio"
        split.write_bytes(b"one")
        same.write_bytes(b"steady")
        fed(split, "swift")
        fed(same, "kotlin")
        # A re-mint landing mid-run: different bytes at `a`, identical bytes
        # republished at `b`. `os.replace` leaves no torn byte to notice either
        # by, which is why the closing digest is the only thing that can.
        split.write_bytes(b"two")
        os.utime(same, (time.time() + 2, time.time() + 2))
        book = reconcile()
        good = len(book.moved) == 1 and book.moved[0].rows == ("swift",)
        ok &= good
        print(f"{'held' if good else 'MISSED':<7} an artifact rewritten under the run"
              f" is named: moved={[m.rows for m in book.moved]}; wanted [('swift',)]")
        good = book.republished == (str(same),)
        ok &= good
        print(f"{'held' if good else 'MISSED':<7} and one republished with identical"
              f" bytes is told apart: {len(book.republished)} republished, 0 moved by it")

        FED.clear()
        _settled = None
        import order
        # Its own private `JOINTS_WORK`, which is what every pinned arm
        # already gets: minting into the cache ten agents share to have
        # something to look at is how an instrument earns being switched off.
        # One small grammar, pressed twice - the first call takes the re-mint
        # branch and the second the `kept` branch, and both are places a run is
        # handed a folio.
        work = hold / "work"
        work.mkdir(parents=True, exist_ok=True)
        name = next((p.stem for p in sorted(order.GRAMMARS.glob("json.json"))
                     or sorted(order.GRAMMARS.glob("*.json"))), "")
        if not (name and order.BIN.exists()):
            print("(skipped) no binary or no pinned grammar in this checkout,"
                  " so there is no folio for a run to be handed")
        else:
            # Run as `python3 tool/stamp.py`, this module is `__main__` and
            # `order`'s `from stamp import fed` imports a *second* copy of it
            # with a second `FED`. Asserting against the local one would report
            # zero artifacts fed no matter what `order` does - a falsifier that
            # fails for a reason that is not its subject, which is the same
            # class of mistake as one that passes for a reason that is not.
            book = sys.modules[order.fed.__module__].FED
            for branch in ("minted", "kept"):
                book.clear()
                got = order.folio_for(name, work)
                good = bool(got) and str(got) in book
                ok &= good
                print(f"{'held' if good else 'MISSED':<7} the folio a run is handed"
                      f" reaches the ledger ({branch}): {len(book)} artifact(s) fed by"
                      f" one `folio_for`, {name}.folio"
                      f" {'among' if good else 'NOT among'} them")
            print("        this is the one that was false - the detector worked and"
                  " was never shown the artifact")
    finally:
        shutil.rmtree(hold, ignore_errors=True)
        FED.clear()
        FED.update(was_fed)
        _settled = was_settled
    print(f"\nstamp: {'every falsifier held' if ok else 'a falsifier did not hold'}")
    return 0 if ok else 1


def hazards() -> int:
    """Each detector, driven by the condition it exists for.

    Constructed rather than staged: proving MOVED by touching a file under
    `src/` would make every other lane's stamp read STALE, and an instrument
    that has to vandalise the tree to test itself is not one anybody will run.
    A Stamp is a plain record, so the condition can simply be stated.
    """
    now = survey(ROOT.resolve())
    base = take(usual())._replace(live=now.digest, told=False, stale=False, drift=False)
    # A read of an artifact that is not there now, which is what every mid-run
    # publish looks like from the reconcile end: the bytes a row was measured
    # against are no longer the bytes at that path.
    ghost = {"/nowhere/kotlin.folio": [
        Sight("/nowhere/kotlin.folio", "a" * 64, 1, 1.0, base.when, "kotlin")]}
    trials = (
        ("quiet", base, {}, ()),
        ("TOLD - a binary somebody chose", base._replace(told=True), {}, ("TOLD",)),
        ("STALE - sources newer than the binary", base._replace(stale=True), {}, ("STALE",)),
        ("DRIFT - built from a tree that moved on", base._replace(drift=True), {}, ("DRIFT",)),
        ("MOVED - the tree changed mid-run", base._replace(live="0" * 64), {}, ("MOVED",)),
        ("SPLIT - an artifact moved after a row read it", base, ghost, ("SPLIT",)),
        ("all five at once", base._replace(told=True, stale=True, drift=True,
                                           live="0" * 64), ghost,
         ("TOLD", "STALE", "DRIFT", "MOVED", "SPLIT")),
    )
    bad = 0
    print(f"{'condition':<46}{'says':<34}want")
    print("-" * 116)
    for what, mark, read, want in trials:
        global _settled
        FED.clear()
        FED.update({k: list(v) for k, v in read.items()})
        _settled = None
        said = tuple(w for w in ("TOLD", "STALE", "DRIFT", "MOVED", "SPLIT")
                     if f"stamp: {w} -" in mark.line())
        ok = said == want
        bad += not ok
        print(f"{what:<46}{(', '.join(said) or 'nothing'):<34}"
              f"{', '.join(want) or 'nothing'}{'' if ok else '   WRONG'}")
    FED.clear()
    _settled = None
    print(f"\n{len(trials) - bad}/{len(trials)} conditions detected")
    return 1 if bad else 0


if __name__ == "__main__":
    import sys
    if "--verdicts" in sys.argv:
        raise SystemExit(probe())
    if "--stops" in sys.argv:
        raise SystemExit(stops())
    if "--surveys" in sys.argv:
        raise SystemExit(surveys())
    if "--hazards" in sys.argv:
        raise SystemExit(hazards())
    if "--plumbed" in sys.argv:
        raise SystemExit(plumbed())
    print(take(Path(os.environ.get(
        "JOINTS_BIN", ROOT / "zig-out" / "bin" / "joints"))).line())

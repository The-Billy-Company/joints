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

There are exactly two ways to be measuring a tree that no longer exists, and
they need different detectors:

  stale   something under the binary's own source root is newer than the
          binary, so an in-place rebuild is overdue
  drift   the binary's source root no longer matches the live repo, which is
          the one that bit us - a snapshot build is internally consistent and
          perfectly happy while the world moves on without it

Both are warnings and neither is an error. Measuring an old binary on purpose
is a legitimate thing to do; that is what a before/after pair is. The point is
that the report says so rather than that the run refuses.

`verdict` lives here for the same reason: it is the other half of not fooling
yourself about a run. A stamp says which binary spoke; a verdict says what it
said, and both are read rather than guessed at.
"""

from __future__ import annotations

import hashlib
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
            h.update(str(p.relative_to(root)).encode() + b"\0")
            h.update(hashlib.sha256(blob).digest())
            count += 1
            if m > when:
                when, where = m, str(p.relative_to(root))
    return Source(root, h.hexdigest(), when, where, count)


def home(binary: Path) -> Path:
    """The tree a binary was built from. `zig build` installs to
    `<root>/zig-out/bin/`, so the root is three parents up - but only claim
    that when a `build.zig` is actually sitting there, since OUTLINER_BIN can
    point anywhere and a wrong guess here would make every other field lie."""
    try:
        guess = binary.resolve().parents[2]
    except IndexError:
        return ROOT.resolve()
    return guess if (guess / "build.zig").is_file() else ROOT.resolve()


def usual() -> Path:
    """The binary an instrument measures when nobody has said otherwise."""
    return ROOT / "zig-out" / "bin" / "outliner"


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
    told: bool  # OUTLINER_BIN chose this binary rather than the default
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
        out = [f"stamp: outliner {self.build[:9]} at {self.binary}"
               f" built {iso(self.built)} from {self.source} {self.tree[:9]}"
               f" · repo {self.commit[:9]}+{self.dirty} · run {iso(self.when)}"]
        if self.told:
            # The press lane nearly published "rust regressed" off an exported
            # OUTLINER_BIN left over from a scratch build. A deliberate override
            # is legitimate and this is not an error; it just has to be visible,
            # because the one thing it looks like otherwise is the default.
            out.append(f"stamp: TOLD - OUTLINER_BIN chose this binary; the tree's"
                       f" own is {here(usual())}")
        if self.stale:
            out.append(f"stamp: STALE - {self.source}/{self.newest} is newer than"
                       " the binary; rebuild before believing this")
        if self.drift:
            out.append(f"stamp: DRIFT - the binary's tree {self.tree[:9]} is not"
                       f" the repo's {self.live[:9]}; this measures a tree that"
                       " no longer exists")
        shifted, where = self.moved()
        if shifted:
            out.append(f"stamp: MOVED - {where} changed while this ran"
                       f" ({time.time() - self.when:.0f}s); the tree it describes"
                       " is not the tree you are reading")
        return "\n".join(out)


def iso(when: float) -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(when))


def here(path: Path) -> str:
    """A path said the shortest way that still identifies it."""
    try:
        return str(path.resolve().relative_to(ROOT.resolve()))
    except ValueError:
        return str(path)


def verdict(stderr: str, source: Path | str) -> str:
    """What the parse said, with its own prefix stripped rather than guessed at.

    The line is `outliner: <path>: <verdict>` and *both* halves of the prefix
    can be followed by more of the same delimiter, because a verdict can name
    the token it refused: python's reads `unexpected : at 482 in state 880`.
    Four instruments took the tail after the last `": "` and so reported that
    wall as `at 482 in state 880`, dropping the one field that said which token
    it was. The prefix is not a thing to infer - we passed the path in, and the
    binary echoes it verbatim - so strip exactly that and no colon anywhere in
    the payload or the path can move the boundary.
    """
    line = next((ln for ln in reversed(stderr.splitlines()) if ln.strip()), "")
    if (rest := behind(line, source)) is not None:
        return rest
    # Some other tool's line, or a path the binary rewrote. Two fields of
    # prefix at most, which is still better than counting from the right.
    return line.split(": ", 2)[-1] if line else "(silent)"


def behind(line: str, source: Path | str) -> str | None:
    """What one `outliner: <path>: ` line says, or None if it is not one.

    The prefix is never a thing to infer - the caller passed the path in and
    the binary echoes it back verbatim. Three readers inferred it anyway, two
    of them with a non-greedy `.*?: ` that quietly takes too little the moment
    a path or a payload contains the delimiter.
    """
    head = f"outliner: {source}: "
    return line[len(head):] if line.startswith(head) else None


STATE = re.compile(r"in state \d+")
AT = re.compile(r"\bat (\d+)")
MENDED = re.compile(r"mended (\d+)")
BLIND = re.compile(r"blind to (\d+)")
SPAN = re.compile(r"\[\d+, (\d+)\)")
ROOTS = re.compile(r"(\d+) roots?")


class Outcome(NamedTuple):
    kind: str  # whole · unclosed · mended · lexical · state · timeout · other
    reach: int  # bytes read; -1 when only the forest can say and it was not given
    verdict: str
    mends: int
    blind: int  # externally scanned terminals we cannot run
    roots: int = 1
    tree: str = ""  # the forest, when the caller asked for one
    code: int = 0  # the binary's own exit status; 2 is a refusal, not a parse


def furthest(tree: str) -> int:
    """The last byte any root covers, which is what an editor actually asks."""
    return max((int(m) for m in SPAN.findall(tree)), default=0)


def outcome(stderr: str, source: Path | str, size: int, tree: str = "") -> Outcome:
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
    """
    said = verdict(stderr, source)
    mends = int(m[1]) if (m := MENDED.search(said)) else 0
    blind = int(m[1]) if (m := BLIND.search(stderr)) else 0
    roots = int(m[1]) if (m := ROOTS.search(said)) else 1
    rest = (mends, blind, roots, tree)
    if said.startswith("accepted"):
        return Outcome("whole", size, said, *rest)
    if said.startswith("truncated"):
        # Every byte lexed, no root closed. Reporting this as reach 0 is what
        # made five files read as unparsed while the lexer had read them whole.
        return Outcome("unclosed", size, said, *rest)
    if mends:
        return Outcome("mended", furthest(tree) if tree else -1, said, *rest)
    kind = ("lexical" if said.startswith("stray byte")
            else "state" if STATE.search(said) else "other")
    return Outcome(kind, int(m[1]) if (m := AT.search(said)) else 0, said, *rest)


PATIENCE = 120.0


def ask(binary: Path | str, grammar: Path | str, src: Path | str, *,
        size: int | None = None, tree: bool | None = None,
        patience: float = PATIENCE, extra: tuple[str, ...] = ()) -> Outcome:
    """Run one parse and say what it did. **The only place an instrument reads
    outliner's stderr**, which is the point of it existing.

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
    root = home(binary)
    # `home` resolves, so resolve this side too or a repo reached through a
    # symlink - which is every path under macOS's /var - reads as a foreign
    # tree and reports drift against itself.
    here = ROOT.resolve()
    mine = survey(root)
    live = mine if root == here else survey(here)
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
SHAPES: tuple[tuple[str, str, str, str], ...] = (
    ("plain", "/c/ledger.c", "outliner: /c/ledger.c: stray byte at 1354, 28 roots",
     "stray byte at 1354, 28 roots"),
    ("colon in the verdict", "/p/ledger.py",
     "outliner: /p/ledger.py: unexpected : at 482 in state 880, 52 roots",
     "unexpected : at 482 in state 880, 52 roots"),
    ("colon token, no state", "/p/x.py", "outliner: /p/x.py: unexpected : at 7",
     "unexpected : at 7"),
    ("colon in the path", "/o: dd/l.c", "outliner: /o: dd/l.c: stray byte at 9",
     "stray byte at 9"),
    ("a warning above it", "/r/ledger.rs",
     "outliner: rust: blind to 6 externally scanned terminal(s)\n"
     "outliner: /r/ledger.rs: accepted, 1 root", "accepted, 1 root"),
    ("trailing blank lines", "/j/l.json", "outliner: /j/l.json: accepted, 1 root\n\n  \n",
     "accepted, 1 root"),
    ("no verdict at all", "/j/l.json", "", "(silent)"),
    ("no colon in the verdict", "/j/l.json", "outliner: /j/l.json: truncated", "truncated"),
)


def probe() -> int:
    """Drive the reader across every shape, and the rule it replaced beside it,
    so the gate is seen to bite rather than asserted to."""
    def old(stderr: str, _: object) -> str:
        line = stderr.strip().splitlines()[-1] if stderr.strip() else "(silent)"
        return line.rsplit(": ", 1)[-1]

    bad = 0
    print(f"{'shape':<24}{'reads':<10}{'the rule it replaced':<22}want")
    print("-" * 96)
    for what, src, err, want in SHAPES:
        got, was = verdict(err, src), old(err, src)
        ok, prior = got == want, was == want
        bad += not ok
        print(f"{what:<24}{'ok' if ok else 'WRONG':<10}{'ok' if prior else 'wrong':<22}{want}")
        if not ok:
            print(f"{'':<24}got {got!r}")
    caught = sum(1 for w, s, e, want in SHAPES if old(e, s) != want)
    print(f"\n{len(SHAPES) - bad}/{len(SHAPES)} shapes read correctly; "
          f"the rule this replaced got {caught} of them wrong")
    return 1 if bad else 0


def hazards() -> int:
    """Each detector, driven by the condition it exists for.

    Constructed rather than staged: proving MOVED by touching a file under
    `src/` would make every other lane's stamp read STALE, and an instrument
    that has to vandalise the tree to test itself is not one anybody will run.
    A Stamp is a plain record, so the condition can simply be stated.
    """
    now = survey(ROOT.resolve())
    base = take(usual())._replace(live=now.digest, told=False, stale=False, drift=False)
    trials = (
        ("quiet", base, ()),
        ("TOLD - a binary somebody chose", base._replace(told=True), ("TOLD",)),
        ("STALE - sources newer than the binary", base._replace(stale=True), ("STALE",)),
        ("DRIFT - built from a tree that moved on", base._replace(drift=True), ("DRIFT",)),
        ("MOVED - the tree changed mid-run", base._replace(live="0" * 64), ("MOVED",)),
        ("all four at once", base._replace(told=True, stale=True, drift=True,
                                           live="0" * 64),
         ("TOLD", "STALE", "DRIFT", "MOVED")),
    )
    bad = 0
    print(f"{'condition':<40}{'says':<26}want")
    print("-" * 86)
    for what, mark, want in trials:
        said = tuple(w for w in ("TOLD", "STALE", "DRIFT", "MOVED")
                     if f"stamp: {w} -" in mark.line())
        ok = said == want
        bad += not ok
        print(f"{what:<40}{(', '.join(said) or 'nothing'):<26}"
              f"{', '.join(want) or 'nothing'}{'' if ok else '   WRONG'}")
    print(f"\n{len(trials) - bad}/{len(trials)} conditions detected")
    return 1 if bad else 0


if __name__ == "__main__":
    import sys
    if "--verdicts" in sys.argv:
        raise SystemExit(probe())
    if "--hazards" in sys.argv:
        raise SystemExit(hazards())
    print(take(Path(os.environ.get(
        "OUTLINER_BIN", ROOT / "zig-out" / "bin" / "outliner"))).line())

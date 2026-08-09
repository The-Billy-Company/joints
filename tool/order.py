#!/usr/bin/env python3
"""Hold the parse to costing the same for the same work in a different order.

This is a complexity gate, not a speed gate. It asserts nothing about how long a
parse takes - every absolute duration in this project is laptop-specific and
`research/joinery/bench.report.md` says so in its own section. It asserts that
**two runs on the same machine, in the same process, over the same bytes and the
same nodes, cost within a margin of each other when only the order changes.**

The construction is the whole finding. A file of many small tokens followed by
one large token, against the same two halves reversed:

    many-then-one.js    4000 statements, then a 100 KB string literal
    one-then-many.js    a 100 KB string literal, then 4000 statements

Both are 152,010 bytes. Both parse to 28,011 nodes. Nothing differs but which
end the bulk token sits at, and today the first costs 4.4x the second - because
the cost of scanning a byte is proportional to how much has already been read,
which makes the whole parse quadratic.

**Holding bytes constant is not holding work constant**, and that is not a
throwaway remark: the first attribution of this defect was wrong precisely
because an ablation held the byte count and quietly turned 99.96% of the file
into a line comment. This pair is the first construction here that pins **both**
axes, and a fixture without that property is just two javascript files. `verify`
exists so the property cannot rot: it re-derives the pair and refuses committed
bytes that the construction would not produce.

`lex` is a false-negative surface for this whole class. The same pair through the
bare lexer costs 46 ms and 47 ms - flat, and 350x cheaper than the slow order -
because the defect needs the per-position admitted set the parse loop supplies
and the bare lexer has none. A gate built on `lex` would pass forever while
`parse` stayed quadratic, so this one goes through `stamp.ask`, which parses, and
re-times the lexer on every run so the trap is shown rather than remembered.

Exit 0 the ratio held, 1 it did not, 2 the gate could not run.
"""

from __future__ import annotations

import argparse
import itertools
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import NamedTuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
from stamp import BOOK, ask, digest, fed, swapped, take  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
FIXTURE = ROOT / "research" / "joinery" / "order"
GRAMMARS = ROOT / "upstream" / "grammars"
BIN = Path(os.environ.get("JOINTS_BIN", ROOT / "zig-out" / "bin" / "joints"))

ROWS = 4000  # small tokens in the many half
BULK = 100_000  # bytes in the one big token

# Picked from measurement, not taste. The two grammars with no blind externals
# already achieve this and have no order effect at all: over three replicates
# each, json ran 0.96 / 1.01 / 1.00 and java ran 0.88 / 0.96 / 0.99. So the
# widest excursion a flat grammar showed is 12%, and a correct scanner is not a
# hypothetical here - it has been observed twice.
#
# The ceiling sits well above that rather than on it. The ratio is two parses
# back to back in one process, which cancels machine load far better than the
# wall-clock rows in bench.py do, but the 4.3x load swing that moved four of
# those rows is exactly what this must never flake under, and `--reps` taking
# the *best* ratio of N is the other half of that. 1.6x leaves a flat grammar
# roughly five times its observed noise, and still fails today's tree from
# 2.8x to 4.1x. Re-derive it with `--calibrate` rather than nudging it.
CEILING = 1.6


class Pair(NamedTuple):
    """One grammar's two orderings, and what they cost."""

    name: str
    many_first: float  # ms, the bulk token last
    one_first: float  # ms, the bulk token first
    size: int
    nodes: int
    same_nodes: bool

    @property
    def swing(self) -> float:
        return self.many_first / self.one_first if self.one_first else float("inf")


# One assignment, one big string literal, and whatever wrapper a file of that
# language needs - per grammar, and nothing else. `likeness.py` prices real
# corpus code against generated code for every one of these, so the shapes have
# to stay this plain: the moment a construction gets clever it stops being
# comparable to its neighbour and starts being its own finding.
#
# The key sets coincide with rung1's roster today and are not required to:
# `likeness.py` intersects the two rather than assuming they match, so a language
# added to the corpus without a shape here is skipped rather than guessed at.
#
# sole: not the corpus roster - this is how you spell an assignment in each
# language, and that has to be written down somewhere; no table of filenames
# implies it.
SHAPE: dict[str, tuple[str, str, str, str]] = {
    # grammar: (one small statement, the big one, head, foot)
    "javascript": ("let a%04d=1;\n", 'let s="%s";\n', "", ""),
    "typescript": ("let a%04d=1;\n", 'let s="%s";\n', "", ""),
    "rust": ("let a%04d = 1;\n", 'let s = "%s";\n', "fn m() {\n", "}\n"),
    "java": ("int a%04d = 1;\n", 'String s = "%s";\n', "class C { void m() {\n", "} }\n"),
    "c": ("int a%04d = 1;\n", 'char *s = "%s";\n', "int main() {\n", "}\n"),
    "cpp": ("int a%04d = 1;\n", 'const char *s = "%s";\n', "int main() {\n", "}\n"),
    "go": ("a%04d := 1\n", 's := "%s"\n', "package m\nfunc m() {\n", "}\n"),
    "python": ("a%04d = 1\n", 's = "%s"\n', "", ""),
    "ruby": ("a%04d = 1\n", 's = "%s"\n', "", ""),
    "bash": ("a%04d=1\n", 's="%s"\n', "", ""),
}
# sole: a file-extension table, not a roster. It answers "what do you call a
# file of this language", which the corpus README does not say and which a
# grammar name does not imply (python -> py, ruby -> rb, bash -> sh).
EXT = {"json": "json", "rust": "rs", "java": "java", "typescript": "ts", "c": "c",
       "cpp": "cpp", "go": "go", "python": "py", "ruby": "rb", "bash": "sh"}


def build(name: str) -> tuple[str, str]:
    """The two orderings for one grammar: (many-then-one, one-then-many).

    Every grammar spells the same two halves - N small tokens, and one token of
    `BULK` bytes - so the pair differs only in order, and the wrapper a grammar
    needs to make a file of it stays outside both halves and out of the ratio.
    """
    fill = "x" * BULK
    if name == "json":  # no statements to wrap; the array is the only shape
        many = ",".join('"a%04d"' % i for i in range(ROWS))
        return f'[{many},"{fill}"]\n', f'["{fill}",{many}]\n'
    small, big, head, foot = SHAPE[name]
    many, one = "".join(small % i for i in range(ROWS)), big % fill
    return head + many + one + foot, head + one + many + foot


def ext(name: str) -> str:
    return EXT.get(name, "txt")


class Price(NamedTuple):
    """What one parse of one file cost, and what it produced."""

    ms: float
    size: int
    nodes: int
    kind: str

    @property
    def per_byte(self) -> float:  # ns
        return self.ms * 1e6 / self.size if self.size else 0.0

    @property
    def per_node(self) -> float:  # us
        return self.ms * 1e3 / self.nodes if self.nodes else 0.0


def price(folio: Path, src: Path) -> Price:
    """Parse one file and say what it cost, in the one place that does.

    `admit.py` prices eleven grammars over two corpora each with this, and the
    gate above prices two orderings with it. A second timing loop would be a
    second answer to "how many nodes is that" the first time one of them counted
    a forest differently."""
    start = time.perf_counter()
    out = ask(BIN, folio, src, patience=900, tree=True)
    return Price(
        ms=(time.perf_counter() - start) * 1000,
        size=src.stat().st_size,
        nodes=len(out.tree.splitlines()) if out.tree else 0,
        kind=out.kind,
    )


def weigh(name: str, folio: Path, work: Path) -> Pair:
    """Parse both orderings and report what each cost, and whether they match."""
    both = []
    for label, text in zip(("many-then-one", "one-then-many"), build(name)):
        src = work / f"{label}.{ext(name)}"
        src.write_text(text)
        both.append(price(folio, src))
    a, b = both
    return Pair(
        name=name,
        many_first=a.ms,
        one_first=b.ms,
        size=a.size,
        nodes=a.nodes,
        same_nodes=a.size == b.size and a.nodes == b.nodes,
    )


class Refused(RuntimeError):
    """The binary will not read a folio it minted itself, moments ago.

    The one condition in this module worth stopping a run for. Everything else
    that can go wrong here is one grammar's problem - nobody fetched it, or the
    press could not take it - and a row that says so is a perfectly good answer.
    A binary that writes a file and then refuses it is not a row: it is the
    whole measurement, because nothing it went on to say about any other
    grammar can be believed either.
    """


# What the cache did for each grammar this process, and why.
#
# Module-level for the same reason `stamp.FED` is: the only provenance anybody
# actually gets is the kind nobody has to remember to ask for. `standing.py`
# prints this under the board, and that one line is the difference between the
# afternoon of 2026-08-05 and a minute.
CACHE: dict[str, str] = {}


def note(name: str, why: str) -> None:
    """Record what the cache did for one grammar, without a later look erasing it.

    `CACHE[name] = why` was a last-write, and `standing.py` asks twice per row -
    once in `ask` to find out whether the row is measurable and once in `ranged`
    to parse with. The first call presses; the second finds a folio that is now
    present and fresher than the binary and files `kept` over the top of it. So
    the line that exists **specifically** to say "eleven of your inputs were
    re-minted under you" could not say it: a board pressing all thirty folios
    from an empty cache, taking 9.8s to do it against a warm run's 0.9s,
    reported `cache: kept 30` (measured 2026-08-05).

    A re-mint is a thing that happened to the run and no later reading of the
    same path makes it un-happen, so the quiet answer never overwrites a loud
    one. Nothing else about the rule moves: the *decision* each call makes is
    unchanged, only what is remembered about it.
    """
    if why != "kept" or CACHE.get(name, "kept") == "kept":
        CACHE[name] = why

# `accepts` keyed by what would change the answer, so the second and third
# caller in one run pay nothing. `standing.py` alone asks twice per grammar.
_verdicts: dict[tuple[str, int, int, int], str] = {}
_serial = itertools.count()


def accepts(folio: Path) -> str:
    """Empty if this binary will read this folio, else what it said instead.

    **Asked of the binary, never worked out here.** `folio/leaf.zig` names
    sixteen ways to refuse a folio and every one of them is a comparison
    `open` makes against a layout this side cannot see. A Python reading of
    that judgement would be a second copy of the file format and the first
    thing to drift the next time a section is added - so the question goes to
    the only thing entitled to answer it.

    It is not free and the price is a process, not the read. `mint <folio>` is
    the same map-and-bind a parse pays with the parse left off, but it is paid
    across a `fork`/`exec`, so the floor is the spawn rather than the folio:
    2.7 ms for json's 10 KB and 4.7 ms for rust's 590 KB, out to 11.8 ms for
    sql's 1.4 MB. Over the board's thirty that is **136 ms a run** (4.5 ms
    mean, 2026-08-05), against a press that costs hundreds of ms for a single
    grammar and a board that would otherwise finish in ~750.

    Which is a sixth of a clean run spent asking a question whose answer is
    almost always yes, and it is still the right trade: the alternative is to
    remember a verdict across runs, keyed on the same mtimes that could not see
    a schema change in the first place. That is the bug, one indirection out.
    Within a run the memo below makes the second and third caller free.

    The **exit status is the decision** and the line is only ever quoted. What
    a refusal is called belongs to the binary; repeating it back is a report,
    where branching on it would be this file holding an opinion about a format
    it does not own.
    """
    try:
        it, built = folio.stat(), BIN.stat().st_mtime_ns
    except OSError:
        return "vanished"
    # Both ends of the question move. Ten agents share this tree, so a folio
    # can be replaced under a run and a `zig build` can change who is being
    # asked - a memo keyed on only one of them answers for the wrong pair.
    key = (str(folio), it.st_mtime_ns, it.st_size, built)
    if key not in _verdicts:
        got = subprocess.run([str(BIN), "mint", str(folio)], capture_output=True, text=True)
        said = next((ln.strip() for ln in reversed((got.stdout + got.stderr).splitlines())
                     if ln.strip()), "")
        _verdicts[key] = "" if got.returncode == 0 else (said or f"exit {got.returncode}")
    return _verdicts[key]


# Whoever pressed a folio, written down beside it. One line, `<sha256> <path>`,
# so it can be read by eye and by `cut` as well as by this.
#
# It exists because the question the cache has to answer is *which binary made
# this*, and for a year it asked an mtime instead. See `miss`.
def ticket(folio: Path) -> Path:
    return folio.with_suffix(".folio.by")


# `stamp.digest` reads the whole binary, and `miss` is asked twice per grammar -
# sixty full reads of a 3 MB binary a board, for an answer that cannot change
# unless the file does. Keyed on what would change it, the way `accepts` is.
_who: dict[tuple[str, int, int], str] = {}


def book(name: str) -> Path:
    """Where this grammar's customary would be, whether or not one is written."""
    return BOOK / f"{name}.json"


def maker(path: Path) -> str:
    """This artifact's identity, or "" if there is nothing to identify.

    Asked of the binary and of a customary alike: both are inputs a press reads,
    and a folio is only this tree's folio if both were.
    """
    try:
        it = path.stat()
    except OSError:
        return ""
    key = (str(path), it.st_mtime_ns, it.st_size)
    if key not in _who:
        _who[key] = digest(path)
    return _who[key]


def stub(folio: Path) -> list[str]:
    """The ticket's lines, or empty when there is no ticket to read."""
    try:
        return ticket(folio).read_text(encoding="utf-8").splitlines()
    except OSError:
        return []


def signed(folio: Path) -> str:
    """The digest of the binary that pressed this folio, or "" if unrecorded."""
    lines = stub(folio)
    return lines[0].split()[0] if lines and lines[0].split() else ""


def sealed(folio: Path) -> str:
    """The digest of the customary that press read, `-` for none, "" if the
    ticket predates the question.

    A second line rather than a wider first one, so a ticket written before
    customaries existed still answers `signed` and reads as *unasked* here -
    which `miss` treats as a miss, because the alternative is believing a folio
    minted without a scanner that now exists.
    """
    lines = stub(folio)
    return lines[1].split()[0] if len(lines) > 1 and lines[1].split() else ""


def miss(folio: Path) -> str:
    """Why this cached folio cannot be used, or "" to use it.

    Four ways to miss, and each of the last two cost an afternoon:

      missing       nothing is there yet
      unattributed  it is there and nothing records which binary pressed it
      foreign       a *different* binary pressed it, so it answers with that
                    one's lexer and table rather than this one's
      refused       this binary can see the file perfectly well and will not
                    read it

    **`foreign` was `older`, and `older` was the wrong question.** The rule here
    used to be `folio.st_mtime < BIN.st_mtime` - "was this made before the
    binary" - asked of a **path**. Two pinned binaries sharing one
    `JOINTS_WORK` are *both* older than a folio either of them minted five
    minutes ago, so the rule never fired for either and both arms of a
    before/after read whichever folio was written last. A lane's before-arm read
    its after-arm's verilog table (`811e808412d78cbc` on both sides, where the
    before binary mints `3ed97566244be7e3`) and nearly reported its own change
    inert. **The error is always in the flattering direction**, because two runs
    of the same table always agree.

    An mtime cannot answer "did *this* binary make this" and never could, so it
    is not asked. `press` writes the minter's digest beside the folio and this
    compares the two. That is strictly stronger - it catches the two-pin case an
    mtime is blind to - and also strictly quieter: a rebuild that lands on the
    same bytes, or a bare `touch`, no longer invalidates thirty folios that are
    still exactly what this binary would press.

    A folio with no ticket is a miss rather than a hit. Provenance that defaults
    to "probably fine" is how the last one got through, and the cost of being
    wrong is one press.

    **`refused` is not `foreign`.** An mtime also could not answer "does this
    binary understand it": folios minted at 10:13 were refused at 10:59 while
    being, by every clock in the tree, *fresher* than the binary refusing them.
    A refusal is a **cache miss** - not staleness, not a parse failure - and the
    only correct answer to a cache miss is to recompute. Rejection itself is the
    format working: `open` is supposed to refuse a folio it cannot prove, and a
    guard that fails closed on an unaccounted field is why a silently dropped
    one cannot print "30 grammars byte-identical" again.
    """
    if not folio.exists():
        return "missing"
    if not (was := signed(folio)):
        return "no record of which binary pressed it"
    if was != (now := maker(BIN)):
        return f"another binary pressed it ({was[:12]}, not {now[:12]})"
    # A customary is a scanner, so a folio pressed without the one now on disk
    # is a folio whose externals answer differently - the exact shape of the
    # `foreign` mistake, one input over. `-` records "there was none", which is
    # a fact worth keeping: it distinguishes a grammar with no customary from a
    # ticket written before the question was asked.
    if (held := sealed(folio)) != (want := maker(book(folio.stem)) or "-"):
        return ("no record of which customary pressed it" if not held else
                f"another customary pressed it ({held[:12]}, not {want[:12]})")
    return f"refused - {said}" if (said := accepts(folio)) else ""


def press(grammar: Path, folio: Path) -> bool:
    """Press one grammar **beside** the cache and move it on, never into it.

    Ten agents share this directory and the freshness rule fires for all of
    them at once - the moment anyone's `zig build` lands, every folio is stale
    and the next instrument to run re-mints all thirty. Two of those overlapping
    on one path is a torn file, which `open` then refuses exactly as it refuses
    a foreign one, and which therefore used to present as the same collapse.

    `os.replace` is atomic within a filesystem, so a reader sees the whole old
    folio or the whole new one and never half of each; the pid keeps two minting
    agents off one temp name. Watch it hold under two concurrent minters with
    `order.py cache`.
    """
    folio.parent.mkdir(parents=True, exist_ok=True)
    # Who pressed it. Recorded here rather than in `accepts`, which runs sixty
    # times a board and would pay a digest for each: a press happens once per
    # grammar and is the moment the binary's identity becomes part of an
    # artifact, so it is the cheapest place the ledger can learn it.
    fed(BIN, folio.stem)
    # The pid names the agent; the serial keeps one agent's own overlapping
    # mints off each other's temp file, so the cleanup below can never delete a
    # publish still in flight.
    part = folio.with_suffix(f".folio.{os.getpid()}.{next(_serial)}.part")
    # The customary is named rather than left to be discovered, because a cache
    # this binary shares with ten agents must not depend on anyone's environment
    # for *what the scanner is*: `mint` would find the same file through
    # `JOINTS_CUSTOMARY`, and a board run without it would then quietly measure
    # a folio with no externals against one that has them.
    told = book(folio.stem)
    order = [str(BIN), "mint", str(grammar), "-o", str(part)]
    if told.exists():
        order += ["--customary", str(told)]
        fed(told, folio.stem)
    try:
        got = subprocess.run(order, capture_output=True, text=True)
        if got.returncode != 0 or not part.exists():
            return False
        # The ticket lands **before** the folio it describes, and by the same
        # rename. A folio published ahead of its ticket is briefly a folio no
        # binary owns, and a concurrent reader in that window presses it again
        # - harmless, but it would make `cache: kept 30` depend on scheduling.
        # This ordering makes the worst case a stale ticket over a folio that
        # is not there yet, which `miss` reads as `missing` and recomputes.
        card = ticket(part)
        card.write_text(f"{maker(BIN)}  {BIN}\n"
                        f"{maker(told) or '-'}  {told if told.exists() else 'no customary'}\n",
                        encoding="utf-8")
        os.replace(card, ticket(folio))
        os.replace(part, folio)
    finally:
        part.unlink(missing_ok=True)
        ticket(part).unlink(missing_ok=True)
    return True


def folio_for(name: str, work: Path) -> Path | None:
    """A folio of our own this binary will actually read, or None with a reason.

    Pressed here rather than read out of `.local/bench`, because a folio someone
    else minted is a folio from someone else's tree and a ratio would then be
    two parsers as much as two orders. A grammar this checkout has not fetched
    is a row skipped, never a failure invented.

    Three outcomes, and the middle one used to be two things wearing one value:

      a path    this binary opened it, just now, and will open it again
      None      no grammar here to press - and `CACHE[name]` says which of the
                two reasons, because a row that vanishes without saying why is
                the same silence one level up from the one this fixes
      raise     `Refused`: the binary pressed a folio and then would not read
                it back. Not a row's problem; the run's.
    """
    grammar = GRAMMARS / f"{name}.json"
    if not grammar.exists():
        note(name, "absent - not pinned in this checkout")
        return None
    folio = work / f"{name}.folio"
    # Every artifact a run reads is one the run's numbers depend on, and until
    # now the folio - the one artifact in this system that is re-minted *while*
    # boards are running - was the only one the generation ledger never saw.
    # `press` fed the binary and `ask` feeds the grammar and the binary, so
    # `stamp.Ledger.moved` faithfully reported that no checked-in source moved
    # under a run and read as though nothing had. The 11:43:55 event `reconcile`
    # is written about was thirty folios; this is where a run is handed one.
    if not (why := miss(folio)):
        note(name, "kept")
        fed(folio, name)
        return folio
    if not press(grammar, folio):
        note(name, f"{why}, and the press then failed")
        print(f"order: {name}: {CACHE[name]} - the row is not measured", file=sys.stderr)
        return None
    # The claim is about the file at the path being handed back, so it is that
    # file that gets asked - not the temp `mint` read back before the rename,
    # and not the buffer that wrote it.
    if said := accepts(folio):
        # Two binaries look exactly like one binary contradicting itself, and
        # only the run's own ledger can tell them apart. Ten agents share this
        # tree; a `zig build` landing between the press and the read is the
        # likelier story, and blaming the format would send a lane after a bug
        # that is not there.
        raise Refused(
            f"{BIN} minted {folio} and then refused to read it: {said}. This is not a "
            f"stale cache and re-running will not clear it - "
            + (f"and the binary itself changed under this run ({moved}), so the press and "
               "the read were two different programs; re-run against a settled tree."
               if (moved := swapped(BIN)) else
               "the binary disagrees with itself about its own folio format, "
               "so no number in this run means anything.")
        )
    note(name, f"re-minted - {why}")
    fed(folio, name)
    return folio


def ledger() -> str:
    """One line saying what the cache did, for the foot of a report.

    Printed rather than available, because the whole defect was that a board
    could collapse to zero and not mention which of its inputs it had failed to
    open. A run where nothing moved says so in eight words; a run that re-minted
    eleven folios says *that*, and no reader mistakes it for a bad day in a lane.
    """
    if not CACHE:
        return "cache: nothing asked for"
    # What was DECIDED, and the line says so, because it reads like a statement
    # about the run and is not one. `kept 30` means "nothing needed re-minting
    # at the moment each row asked" - it cannot mean "the thirty folios I handed
    # out were still there afterwards", because the question was asked thirty
    # times, each time before a measurement, and the answers are separated from
    # the end of the board by the whole board. `stamp.reconcile` is the line
    # that closes that interval; this one opens it.
    tally: dict[str, list[str]] = {}
    for name, why in sorted(CACHE.items()):
        tally.setdefault(why, []).append(name)
    head = " · ".join(f"{why.split(' - ')[0]} {len(who)}"
                      for why, who in sorted(tally.items()))
    # `kept` is the quiet case and needs no roster. Everything else is a folio
    # that was not there, or was not this binary's, and naming those grammars is
    # the point - a re-mint of eleven is a fact about the tree, not about them.
    return (f"cache: {head} — what the cache decided when each row asked it, which is"
            f" not what was read; the generation line below says that") + "".join(
        f"\n  {why}: {', '.join(who)}" for why, who in sorted(tally.items()) if why != "kept")


# Every way a cached folio can stop being one, and how to make it happen to a
# real folio. `open` checks magic, then size, then version, then schema, then
# length, then the seal - so the first four are reachable by editing the header
# and need no second binary to stage, which is what makes this probe portable
# rather than a story about one afternoon's `.local`.
#
# The last two are the shapes of a **torn write**, which is the other way ten
# agents on one directory produce a `FolioBad*`: a file caught mid-publish is
# short, or is the right length with the wrong bytes in it.
def bend(good: bytes, how: str) -> bytes:
    if how == "a folio from another binary's format":
        return good[:8] + (0xBEEF).to_bytes(2, "little") + good[10:]  # version
    if how == "a press-side struct that grew a field":
        return good[:56] + bytes(32) + good[88:]                      # schema signet
    if how == "a torn write, caught short":
        return good[: len(good) // 2]
    if how == "a torn write, right length wrong bytes":
        at = len(good) // 2
        return good[:at] + bytes(64) + good[at + 64:]
    return b"not a folio at all, just some bytes\n"


def one(work: Path, name: str, how: str | None) -> tuple[str, str, bool]:
    """Put the cache in one state, ask it for a folio, and say what it did."""
    folio = work / f"{name}.folio"
    CACHE.clear()
    _verdicts.clear()
    if how == "the binary is newer than it":
        os.utime(folio, (0, BIN.stat().st_mtime - 60))
    elif how == "another binary pressed it":
        # A second binary staged without a second binary: the ticket is the
        # whole claim, so a ticket naming somebody else is exactly the state a
        # second pin's `JOINTS_WORK` would leave behind.
        ticket(folio).write_text(f"{'0' * 64}  /some/other/pin/bin/joints\n", encoding="utf-8")
    elif how == "no record of which binary pressed it":
        ticket(folio).unlink(missing_ok=True)
    elif how == "no record of which customary pressed it":
        # A ticket from before a scanner was data: it names the binary and stops.
        # Staged by truncation rather than by hiding the customary, so the trial
        # reads the same for a grammar that has one and a grammar that does not.
        ticket(folio).write_text(f"{maker(BIN)}  {BIN}\n", encoding="utf-8")
    elif how is not None:
        folio.write_bytes(bend(folio.read_bytes(), how))
        os.utime(folio, None)  # and fresher than the binary, as today's were
    got = folio_for(name, work)
    return CACHE.get(name, "-"), ("" if got is None else accepts(got)) or "reads", got is not None


# One minting agent, as its own interpreter. `atomic` picks between the guard
# and the control: `order.press` publishes beside the cache and renames onto it,
# where the control writes the identical bytes straight down the path a reader
# is already holding open.
MINTER = """
import sys, time
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import order
folio, grammar, atomic, spare = Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4] == "1", Path(sys.argv[5])
for _ in range(3):
    if atomic:
        order.press(grammar, folio)
        continue
    blob = spare.read_bytes()
    with folio.open("wb") as fh:
        for at in range(0, len(blob), 512):
            fh.write(blob[at:at + 512])
            time.sleep(0.001)
"""


def tearing(work: Path, name: str, atomic: bool) -> tuple[int, int]:
    """Two minters at one target, and a reader watching the whole time.

    Concurrency is the hazard the format cannot tell from a schema change: a
    reader that catches a publish half-done gets a `FolioBad*` out of a folio
    nobody's binary disagrees with. Provoked rather than reasoned about, and
    provoked **both ways** - the same race run through a writer that publishes
    in place is the control, because a guard nobody has watched fail is
    decoration.

    Returns (reads, refusals). Atomic must score zero refusals; the control
    exists to show that a non-atomic writer does not.
    """
    folio = work / f"{name}.folio"
    whole = folio.read_bytes()
    spare = folio.with_suffix(".folio.whole")
    spare.write_bytes(whole)
    # Two **processes**, because that is the hazard: ten agents, ten
    # interpreters, one `.local/standing`. Two threads would share a pid and so
    # share the temp name, which is the one collision the guard does not claim
    # to cover and would have made this pass for the wrong reason.
    hands = [subprocess.Popen(
        [sys.executable, "-c", MINTER, str(ROOT / "tool"), str(folio),
         str(GRAMMARS / f"{name}.json"), "1" if atomic else "0", str(spare)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) for _ in range(2)]
    seen = []
    while any(h.poll() is None for h in hands):
        seen.append(accepts(folio))
        time.sleep(0.0005)
    for h in hands:
        h.wait()
    folio.write_bytes(whole)  # leave the cache as this found it
    spare.unlink(missing_ok=True)
    return len(seen), sum(1 for s in seen if s)


def cache(name: str = "json") -> int:
    """Drive the folio cache through every way a cached folio stops being one.

    The gate for the defect of 2026-08-05, written as the thing that would have
    caught it: eleven folios that `open` refused stayed cached because the rule
    above them only knew how to compare two mtimes, and every instrument that
    read them reported zero rather than a miss.
    """
    import tempfile
    print(f"{'the cache holds':<40}{'it does':<12}{'hands back':<12}what the binary said about the cached one")
    print("-" * 118)
    bad = 0
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        # The refusal is quoted verbatim from the binary; only the scratch path
        # in it is elided, because a tmpdir name is not part of the finding.
        def short(said: str) -> str:
            return said.replace(f"{work}/", "").replace("joints: ", "")
        trials: tuple[tuple[str, str | None, str], ...] = (
            ("nothing yet", None, "re-minted"),
            ("a folio this binary just minted", None, "kept"),
            # An mtime was the rule here for a year and it answered the wrong
            # question in both directions. These two trials are that rule's two
            # halves, and the wanted answers are now opposite to what it gave.
            ("an older folio this same binary minted", "the binary is newer than it", "kept"),
            ("a fresher folio another pin minted", "another binary pressed it", "re-minted"),
            ("a folio with no record of its minter", "no record of which binary pressed it", "re-minted"),
            # A customary *is* the scanner, so a folio pressed without the one on
            # disk answers externals differently - the `foreign` mistake one
            # input over, and the one a board would report as a speed win.
            ("a folio pressed before its customary", "no record of which customary pressed it", "re-minted"),
            ("a folio from another binary's format", "a folio from another binary's format", "re-minted"),
            ("a press-side struct that grew a field", "a press-side struct that grew a field", "re-minted"),
            ("a torn write, caught short", "a torn write, caught short", "re-minted"),
            ("a torn write, right length wrong bytes", "a torn write, right length wrong bytes", "re-minted"),
            ("bytes that are not a folio at all", "garbage", "re-minted"),
        )
        for holds, how, want in trials:
            did, reads, gave = one(work, name, how)
            ok = did.startswith(want) and reads == "reads" and gave
            bad += not ok
            why = did.split(" - ", 1)[1] if " - " in did else ""
            print(f"{holds:<40}{did.split(' - ')[0]:<12}{reads:<12}"
                  f"{'' if ok else 'WRONG  '}{short(why)}")

        # The one condition worth stopping for, staged where it can be: a press
        # that writes a folio this binary will not read. `folio_for` must refuse
        # to hand that back rather than let a caller measure through it.
        global press
        keep = press
        press = lambda g, f: (f.write_bytes(bend(f.read_bytes(), "garbage")), True)[1]  # noqa: E731
        try:
            ticket(work / f"{name}.folio").unlink(missing_ok=True)
            folio_for(name, work)
            print(f"{'a press the binary then refuses':<40}{'hands back':<12}{'the folio':<12}"
                  f"WRONG  a run measuring through this reports zeros and calls them a parse")
            bad += 1
        except Refused:
            print(f"{'a press the binary then refuses':<40}{'raises':<12}{'nothing':<12}"
                  f"the binary disagrees with itself; no number in the run means anything")
        finally:
            press = keep

        # And the concurrency hazard, which presents as exactly the same refusal.
        one(work, name, None)
        print(f"\n{'two agents minting one folio at once':<40}{'reads':<12}{'refused':<12}")
        for atomic in (True, False):
            reads, refused = tearing(work, name, atomic)
            ok = (refused == 0) if atomic else (refused > 0)
            bad += not ok
            how = ("published beside it, then renamed on"
                   if atomic else "published in place (the control)")
            print(f"  {how:<38}{reads:<12}{refused:<12}{'' if ok else 'WRONG  '}"
                  + ("no reader ever saw a partial file" if not refused else
                     "readers caught a partial file - which is why the rename is there"))
    plural = "" if bad == 1 else "s"
    print(f"\n{f'{bad} condition{plural} did NOT route to a recompute' if bad else
              'every condition routes to a recompute'}; a refusal is a cache miss, "
          f"and the only answer to a cache miss is to recompute")
    return 1 if bad else 0


def lexed(name: str, work: Path) -> tuple[float, float] | None:
    """The same pair through the bare lexer, which is where the trap is.

    Printed on every run rather than written down once, because "`lex` does not
    reproduce this" is the single most expensive thing here to learn twice: the
    lexer walks the same bytes for a four-hundredth of the cost and shows no
    order effect at all, so a gate built on it would stay green through a
    quadratic parse forever. The defect needs the admitted set the parse loop
    supplies at each position, and the bare lexer has none to supply.
    """
    grammar = GRAMMARS / f"{name}.json"
    if not grammar.exists():
        return None
    out = []
    for label in ("many-then-one", "one-then-many"):
        src = work / f"{label}.{ext(name)}"
        start = time.perf_counter()
        got = subprocess.run([str(BIN), "lex", str(grammar), str(src), "--quiet"],
                             capture_output=True, text=True)
        if got.returncode not in (0, 1):
            return None
        out.append((time.perf_counter() - start) * 1000)
    return out[0], out[1]


def report(pairs: list[Pair], ceiling: float) -> list[str]:
    """The faults, in the words that say what a red row means."""
    faults = []
    for p in pairs:
        if not p.same_nodes:
            faults.append(
                f"{p.name}: the two orderings no longer hold bytes and nodes equal, so this "
                f"pair proves nothing - fix the construction in tool/order.py before reading "
                f"any ratio off it"
            )
        elif p.swing > ceiling:
            faults.append(
                f"{p.name}: the same {p.size:,} bytes and the same {p.nodes:,} nodes cost "
                f"{p.swing:.1f}x more in one order than the other ({p.many_first:.0f} ms "
                f"against {p.one_first:.0f} ms), past the {ceiling}x ceiling - "
                f"the parse is superlinear in what has already been read"
            )
    return faults


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("verb", nargs="?", default="run",
                    choices=("run", "verify", "build", "list", "status", "cache"))
    ap.add_argument("--grammar", action="append", help="just this one (repeatable)")
    ap.add_argument("--ceiling", type=float, default=CEILING)
    ap.add_argument("--reps", type=int, default=2, help="repeat each pair, and judge the best ratio")
    ap.add_argument("--calibrate", action="store_true", help="print every replicate rather than the best")
    ap.add_argument("--via", choices=("folio", "grammar", "both"), default="both",
                    help="which way to name the grammar; `both` gates each separately")
    args = ap.parse_args(argv)

    names = args.grammar or ["json", "java", "rust", "javascript", "typescript"]

    if args.verb == "list":
        print(f"{'grammar':<12}{'pressed from':<52}{'bytes':>10}")
        for n in names:
            g = GRAMMARS / f"{n}.json"
            where = str(g.relative_to(ROOT)) if g.exists() else "(not pinned here - would skip)"
            print(f"{n:<12}{where:<52}{len(build(n)[0]):>10,}")
        return 0

    if args.verb == "build":
        FIXTURE.mkdir(parents=True, exist_ok=True)
        for label, text in zip(("many-then-one", "one-then-many"), build("javascript")):
            (FIXTURE / f"{label}.js").write_text(text)
            print(f"order: wrote research/joinery/order/{label}.js ({len(text):,} bytes)")
        return 0

    if args.verb == "verify":
        bad = 0
        for label, text in zip(("many-then-one", "one-then-many"), build("javascript")):
            path = FIXTURE / f"{label}.js"
            if not path.exists():
                print(f"order: {path.relative_to(ROOT)} is missing; `order.py build` writes it", file=sys.stderr)
                bad += 1
            elif path.read_text() != text:
                print(
                    f"order: {path.relative_to(ROOT)} is not what the construction makes - "
                    f"the committed pair and tool/order.py have drifted apart, and the pair is "
                    f"only evidence while they agree",
                    file=sys.stderr,
                )
                bad += 1
        if bad:
            return 1
        a, b = build("javascript")
        print(f"order: the committed pair is what the construction makes, {len(a):,} bytes each")
        return 0

    if not BIN.exists():
        print(f"order: no binary at {BIN}; `zig build` first", file=sys.stderr)
        return 2

    if args.verb == "cache":
        return cache(names[0])

    work = Path(os.environ.get("TMPDIR", "/tmp")) / f"order-{os.getpid()}"
    work.mkdir(parents=True, exist_ok=True)
    best: dict[str, Pair] = {}
    skipped = []
    for name in names:
        # Both ways of naming the same grammar, because they are two code paths
        # and for one afternoon they disagreed by 110x: the reachability mask was
        # derived at import and never written into the folio, so a folio minted
        # by the fixed binary still parsed at the broken cost. The grammar path
        # is what a lane measures while fixing; the folio is what ships. A gate
        # that watched only one of them would have called that fix landed.
        ways = {}
        if args.via in ("folio", "both") and (f := folio_for(name, work)):
            ways["folio"] = f
        if args.via in ("grammar", "both") and (j := GRAMMARS / f"{name}.json").exists():
            ways["grammar"] = j
        if not ways:
            skipped.append(name)
            continue
        for rep, (via, grammar) in ((r, w) for r in range(args.reps)
                                    for w in ways.items()):
            # Keyed per path, never merged. Taking the better of the two would
            # have reported 1.0x on the afternoon one path was 4.4x, which is
            # the precise failure this check exists to make impossible.
            # `weigh` builds the fixture from the grammar's own name, so the
            # path only ever decorates the row it is reported on.
            row = f"{name} via {via}" if len(ways) > 1 else name
            p = weigh(name, grammar, work)._replace(name=row)
            if args.calibrate:
                print(f"  {name:<12} rep {rep + 1}  {p.many_first:>9.0f} / {p.one_first:>8.0f} = {p.swing:>6.2f}x")
            # The best ratio of N, because a ratio is only ever inflated by
            # noise on the slow side; a gate that judged the worst replicate
            # would be gating the machine rather than the parse.
            if row not in best or p.swing < best[row].swing:
                best[row] = p
    pairs = [best[k] for k in best]
    if not pairs:
        print("order: no grammar had a folio; nothing measured", file=sys.stderr)
        return 2

    mark = take(BIN)
    wide = max(12, max(len(p.name) for p in pairs) + 2)
    print(f"{'grammar':<{wide}}{'many-then-one':>15}{'one-then-many':>15}{'swing':>9}{'bytes':>10}{'nodes':>9}")
    for p in sorted(pairs, key=lambda p: -p.swing):
        flag = "" if p.same_nodes else "  <- bytes/nodes NOT equal"
        print(
            f"{p.name:<{wide}}{p.many_first:>13.0f} ms{p.one_first:>13.0f} ms"
            f"{p.swing:>8.1f}x{p.size:>10,}{p.nodes:>9,}{flag}"
        )
    if skipped:
        print(f"order: skipped, not pinned here: {', '.join(skipped)}")
    worst = max(pairs, key=lambda p: p.swing)
    bare = lexed(worst.name, work)
    if bare:
        print(
            f"order: the same {worst.name} pair through `lex` costs {bare[0]:.0f} ms and "
            f"{bare[1]:.0f} ms - flat, and {worst.many_first / max(bare[0], 0.001):.0f}x cheaper "
            f"than `parse`. `lex` is a false-negative surface for this class: it never sees the "
            f"admitted set, so it cannot see the defect. Gate the parse."
        )
    print(mark.line())
    sys.stdout.flush()

    if args.verb == "status":
        return 0
    faults = report(pairs, args.ceiling)
    for f in faults:
        print(f"order: {f}", file=sys.stderr)
    if faults:
        print(
            f"order: {len(faults)} grammar(s) cost more for the same work in a different order. "
            f"This is the defect research/joinery/bench.report.md attributes to the scanner; "
            f"the witness is the pair itself and needs no instrumentation.",
            file=sys.stderr,
        )
        return 1
    print(f"order: {len(pairs)} row(s) · order costs nothing past {args.ceiling}x · "
          f"the parse is linear in what it has read")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

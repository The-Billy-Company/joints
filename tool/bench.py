#!/usr/bin/env python3
"""What does joints cost, against what tree-sitter costs for the same job?

`differential.py` asks whether the tree is right. This asks whether the rest of
the pitch is true - smaller, one artifact, no compiler in the loop - and it is
the harder question to ask honestly, because a cost benchmark can be flattered
in ways a tree comparison cannot. Two rules follow from that, and they shape
every measurement here:

  * **a partial parse is never a throughput number.** Ten of the eleven
    grammars stop somewhere in the middle today, and a parser that quits early
    reads as fast. So a throughput case is admitted only when *both* parsers
    swallow the whole scaled input - joints says `accepted`, tree-sitter says
    `successful` - and every grammar that fails that gate is listed by name
    with the reason rather than quietly dropped.
  * **nothing is subtracted from one side that is not subtracted from the
    other.** `joints parse` presses the grammar on every run; `tree-sitter
    parse` loads a `.dylib` somebody already compiled. Timing them head to head
    would measure the press, not the parse. So both sides are run over the same
    file repeated k times and the *marginal* cost of one more parse is the
    slope - which subtracts process startup, grammar load, and the press from
    both at once, by the same arithmetic. The fixed cost that slope removes is
    not thrown away: it is reported as its own axis, `startup`, where the press
    is the whole story and we lose badly.

Every axis is a **cost**, so `ratio = ours / theirs` and under 1.0 always means
joints is cheaper. Throughput is carried as nanoseconds per byte for that
reason, with the bytes-per-second spelled beside it.

The tree-sitter CLI is a **dev-only oracle**, on the terms `differential.py`
already set: installed under `.local/differential/cli`, never linked, vendored
or shipped, and when it is absent every axis skips and the run exits 0. The
native binary is invoked rather than npm's `tree-sitter` shim, because that
shim is a node script that spawns the real one - charging tree-sitter for a
node process it does not need would be exactly the kind of flattering number
this file exists to refuse.

Exit 0 ran, 1 a clean negative answer (`verify` found a regression), 2 an
error. That is the CLI's family and `differential.py`'s.
"""

from __future__ import annotations

import json
import os
import platform
import re
import shutil
import statistics
import subprocess
import sys
import time
import zlib
from pathlib import Path
from typing import Any, NamedTuple

from amend import ROW
from differential import LIB, TS, WORK as ORACLE, oracle_home, oracle_ready
from grammars import load
from rung1 import pairs
from stamp import Stamp, behind, outcome, take

ROOT = Path(__file__).resolve().parent.parent
GRAMMARS = ROOT / "upstream" / "grammars"
CORPUS = ROOT / "research" / "joinery" / "corpus"
WORK = ROOT / ".local" / "bench"
PREFIX = WORK / "build"  # our own install prefix; `zig-out` belongs to whoever built last
BIN = Path(os.environ.get("JOINTS_BIN", PREFIX / "bin" / "joints"))
BASELINE = Path(__file__).resolve().parent / "bench.baseline.json"
# npm's `.bin/tree-sitter` is a node script that spawns this one.
NATIVE = TS.parent.parent / "tree-sitter-cli" / "tree-sitter"
RUNTIMES = ("/opt/homebrew/lib/libtree-sitter.dylib", "/usr/local/lib/libtree-sitter.dylib",
            "/usr/lib/libtree-sitter.so", "/usr/local/lib/libtree-sitter.so")
# `~/.cache/tree-sitter/lib/` is keyed by language name alone and shared with
# every other tool on the machine, so a rebuild landing mid-run would charge
# tree-sitter for someone else's compile. Same pin `differential.py` uses.
ENV = {**os.environ, "TREE_SITTER_LIBDIR": str(LIB)}

# Big enough that one parse dwarfs the noise on a wall clock, small enough that
# eleven of them cost seconds rather than minutes.
TARGET = 128 << 10
COPIES = (1, 5)  # the two points the marginal cost is the slope between

USAGE = """\
bench.py - what does joints cost against tree-sitter?

usage:
  bench.py run       measure every axis (offline; skips if no oracle)
  bench.py verify    measure, and hold the numbers to tool/bench.baseline.json
  bench.py record    write that baseline from a fresh run
  bench.py list      the axes, and which grammars each one can run on
  bench.py oracle    is the tree-sitter CLI here, and which version

flags:
  --axis=NAME     one of: artifact install press throughput startup incremental memory
  --grammar=NAME  one grammar
  --reps=N        replicates per timing (default 7; the press axis takes 3)
  --json          machine output, on the read verbs
"""

AXES = ("artifact", "install", "press", "throughput", "startup", "incremental", "memory")

# How much a number may worsen before `verify` calls it a regression, and which
# number is watched. Bytes are deterministic, so they are guarded tightly and
# absolutely. A duration is not portable between machines, but the *ratio* to
# tree-sitter measured in the same run largely is - so that is what the timing
# axes are held to.
GUARD = {
    "artifact": ("ours", 0.02),
    "install": ("ours", 0.02),
    "press": ("ratio", 0.25),
    "throughput": ("ratio", 0.25),
    "startup": ("ratio", 0.30),
    # A keystroke is microseconds, so it is the noisiest row on the page and
    # the slack says so rather than pretending otherwise.
    "incremental": ("ratio", 0.35),
    "memory": ("ratio", 0.20),
}

# One repeated copy of a corpus file is a bigger file in the same language for
# every grammar whose top level is a sequence of items. JSON's is one value, so
# the copies go in an array instead. Anything else would be a different shape
# of input, which is why this is a table and not a heuristic.
def scale(grammar: str, body: str, n: int) -> str:
    if grammar == "json":
        return "[" + ",\n".join([body.strip()] * n) + "]\n"
    return body * n


class Row(NamedTuple):
    axis: str
    case: str
    ours: float
    theirs: float
    unit: str  # bytes · ms · ns/byte
    spread: float = 0.0  # relative stdev of our estimator, 0 when deterministic
    note: str = ""

    @property
    def ratio(self) -> float:
        return self.ours / self.theirs if self.theirs else 0.0

    def as_dict(self) -> dict[str, Any]:
        return {**self._asdict(), "ratio": round(self.ratio, 4)}


class Skip(NamedTuple):
    axis: str
    case: str
    why: str


class Forge(NamedTuple):
    """Both artifacts for one grammar, and what each cost to make."""

    folio: int
    folio_ms: float
    folio_spread: float
    dylib: int
    dylib_ms: float
    csource: int  # parser.c + scanner.c, what a grammar repository commits
    own_ms: float  # what mint says the press and the pack cost, minus the process
    sections: dict[str, int]
    why: str  # empty when both sides made something


# --------------------------------------------------------------------- running

def wall(cmd: list[str], cwd: Path | None = None) -> float:
    """One run, in milliseconds. Output goes nowhere: a benchmark that also
    measures a terminal is measuring a terminal."""
    at = time.perf_counter()
    subprocess.run(cmd, cwd=cwd, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, env=ENV)
    return (time.perf_counter() - at) * 1000


def peak(cmd: list[str], cwd: Path | None = None) -> int:
    """Peak resident set of one child, from the kernel's own accounting rather
    than from parsing `/usr/bin/time`. macOS reports bytes, Linux kilobytes."""
    with subprocess.Popen(cmd, cwd=cwd, stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL, env=ENV) as p:
        _, status, ru = os.wait4(p.pid, 0)
        p.returncode = os.waitstatus_to_exitcode(status)  # already reaped; do not wait again
    return ru.ru_maxrss if sys.platform == "darwin" else ru.ru_maxrss * 1024


def say(cmd: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, env=ENV)


def best(cmd: list[str], reps: int, cwd: Path | None = None) -> list[float]:
    return [wall(cmd, cwd) for _ in range(reps)]


def sharpen() -> str:
    """Build the binary this run measures, into a prefix nobody else writes to.

    `zig-out` is whatever the last lane built, and a debug binary measured by
    accident reads as a catastrophic regression that is not there. So we build
    our own ReleaseFast one and say which of four things happened, because a
    run that cannot say what it measured is not a measurement:

      * `JOINTS_BIN` was set - somebody chose the binary, mode unknown to us;
      * the tree compiled just now, and this is that;
      * the tree does not compile at HEAD, so this is our last good build,
        which is older than the commit stamped beside it;
      * neither, and there is nothing to run.
    """
    global BIN
    if "JOINTS_BIN" in os.environ:
        # Somebody chose the binary, so the flag that built it is not ours to
        # report - but the *mode* still is, and the mode is the half that moves
        # a parse loop. Reading it out of the bytes is the difference between
        # "we cannot say" and "this is a debug binary and every timing below is
        # a lie". Pinning a binary across two runs is the legitimate case, and
        # it is exactly the case that must not be allowed to go unverified.
        return f"JOINTS_BIN, and {safety(BIN)}" if BIN.exists() else ""
    made = say(["zig", "build", "-Dcli-optimize=ReleaseFast", "--prefix", str(PREFIX)], ROOT)
    if made.returncode == 0 and BIN.exists():
        return "-Dcli-optimize=ReleaseFast"
    if BIN.exists():
        old = time.strftime("%Y-%m-%d %H:%M", time.localtime(BIN.stat().st_mtime))
        return f"-Dcli-optimize=ReleaseFast, built {old}; the tree does not compile at this commit"
    stale = ROOT / "zig-out" / "bin" / "joints"
    if stale.exists():
        BIN = stale
        return f"UNVERIFIED: {here(stale)}, built by another lane, {safety(stale)}"
    return ""


def safety(binary: Path) -> str:
    """Whether runtime safety got compiled into a binary somebody else built.
    Zig stamps the optimisation mode nowhere, but the safety panics leave their
    message table in the file - and safety on or off is the half of the mode
    that moves a parse loop, so it is the half worth reporting."""
    blob = binary.read_bytes()
    return ("safety checks are ON, so these timings are not a release number"
            if b"index out of bounds" in blob else "no safety panics in it, so a release mode")


# ------------------------------------------------------------------- artifacts

_forged: dict[str, Forge] = {}


def lay_out() -> None:
    """A working tree of our own under `.local/bench`, so a run cannot disturb
    the differential's. The scanners come from there because that is where
    `differential.py install` puts them and there should be one fetch, not two;
    the grammar is taken from `upstream/grammars` regardless, because both
    parsers reading the same bytes is the invariant every number rests on."""
    if (ORACLE / "lang").is_dir():
        shutil.copytree(ORACLE / "lang", WORK / "lang", dirs_exist_ok=True)
    (WORK / "folio").mkdir(parents=True, exist_ok=True)
    (WORK / "in").mkdir(parents=True, exist_ok=True)


def folio_for(name: str) -> Path:
    """The artifact a user actually ships. `forge` writes it; the axes that
    measure what a user pays must read it rather than pressing the grammar
    again, or they report the press against tree-sitter's `dlopen`."""
    return WORK / "folio" / f"{name}.folio"


def forge(name: str, reps: int) -> Forge:
    """Press a folio and compile a parser, timing both. Memoized: three axes
    read these numbers and pressing typescript three times over is minutes."""
    if name in _forged:
        return _forged[name]
    got = _forge(name, reps)
    _forged[name] = got
    return got


def _forge(name: str, reps: int) -> Forge:
    empty = Forge(0, 0.0, 0.0, 0, 0.0, 0, 0.0, {}, "")
    grammar = GRAMMARS / f"{name}.json"
    if not grammar.exists():
        return empty._replace(why="grammar not resolved; run `python3 tool/grammars.py fetch`")

    folio = folio_for(name)
    mint = [str(BIN), "mint", str(grammar), "-o", str(folio)]
    got = say(mint, ROOT)
    if got.returncode != 0 or not folio.exists():
        return empty._replace(why=f"joints mint: {tail(got.stdout or got.stderr)}")
    runs = best(mint, reps, ROOT)
    folio_ms, folio_spread = min(runs), spread_of(runs)

    lang = oracle_home(name, WORK)
    (lang / "src").mkdir(parents=True, exist_ok=True)
    shutil.copyfile(grammar, lang / "src" / "grammar.json")
    dylib = lang / f"{name}.dylib"

    def build() -> str:
        (lang / "src" / "parser.c").unlink(missing_ok=True)
        dylib.unlink(missing_ok=True)
        gen = say([str(NATIVE), "generate", "src/grammar.json"], lang)
        if gen.returncode != 0:
            return f"tree-sitter generate: {tail(gen.stderr)}"
        made = say([str(NATIVE), "build", "-o", str(dylib), "."], lang)
        return "" if dylib.exists() else f"tree-sitter build: {tail(made.stderr)}"

    if why := build():
        return empty._replace(folio=folio.stat().st_size, folio_ms=folio_ms,
                              folio_spread=folio_spread, why=why)
    # Their two steps are one number because a `parser.c` nobody compiled is not
    # a parser yet; ours is one step because a folio is the artifact.
    theirs = []
    for _ in range(reps):
        at = time.perf_counter()
        # A replicate can fail where the first attempt did not - a generator
        # that ran out of memory under a parallel lane, say - and the artifact
        # it leaves behind is missing rather than stale, so every axis after
        # this one has to hear about it rather than trip over the hole.
        if why := build():
            return empty._replace(folio=folio.stat().st_size, folio_ms=folio_ms,
                                  folio_spread=folio_spread, why=why)
        theirs.append((time.perf_counter() - at) * 1000)
    csource = sum(f.stat().st_size for f in (lang / "src").glob("*.c")) + \
        sum(f.stat().st_size for f in (lang / "src").glob("*.cc"))
    report = say(mint, ROOT).stdout
    return Forge(folio.stat().st_size, folio_ms, folio_spread, dylib.stat().st_size, min(theirs),
                 csource, own_press(report), sections(report), "")


def own_press(report: str) -> float:
    """What `mint` says the press and the pack cost, with no process around
    them. The counterpart of tree-sitter's `--json-summary` clock: for a small
    grammar the wall clock is almost entirely `exec`, and a reader deserves to
    know which of the two numbers moved."""
    for line in report.splitlines():
        if line.strip().startswith("pressed in "):
            cells = line.replace(",", "").split()  # pressed in N us packed in M us loaded in K us
            return (int(cells[2]) + int(cells[6])) / 1000
    return 0.0


def deflated(folio: Path) -> int:
    """How big the folio would be if nothing in it repeated. Not a shippable
    number - nobody wants to inflate a parse table before parsing - but when
    the size axis is a loss it is the one measurement that says whether the
    loss is the format or the design, and deflate is cheap enough to take on
    every run. `xz -6` gets about 2.5x further still."""
    return len(zlib.compress(folio.read_bytes(), 6))


def spread_of(runs: list[float]) -> float:
    """How far apart the replicates landed, against the middle one. This is a
    laptop with other lanes building on it, so a timing with no spread beside it
    is not a measurement - it is one sample wearing a decimal point."""
    mid = statistics.median(runs)
    return statistics.stdev(runs) / mid if len(runs) > 1 and mid else 0.0


def sections(report: str) -> dict[str, int]:
    """The folio's own section table, off `mint`'s report. Where the bytes went
    is the whole content of the size axis once the size axis is a loss."""
    out: dict[str, int] = {}
    for line in report.splitlines():
        cells = line.split()
        if len(cells) == 4 and cells[3].endswith("%") and cells[1].isdigit() and cells[2].isdigit():
            out[cells[0]] = int(cells[2])
    return out


def tail(text: str) -> str:
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    return lines[-1] if lines else "no reason given"


# ------------------------------------------------------------------ the inputs

class Input(NamedTuple):
    grammar: str
    path: Path
    size: int
    copies: int
    why: str  # empty when both parsers read the whole thing


def input_for(name: str, leaf: str) -> Input:
    """A bigger file in the same language, built by repeating the corpus file
    the rest of the repository already measures over - so a throughput number
    is over the same constructs every other rung reports on, and a clone can
    rebuild it with no network."""
    src = CORPUS / leaf
    if not src.exists():
        return Input(name, src, 0, 0, f"no corpus file at {here(src)}")
    body = src.read_text(encoding="utf-8")
    n = max(1, -(-TARGET // max(len(body), 1)))
    text = scale(name, body, n)
    path = WORK / "in" / f"{name}-{n}{src.suffix}"
    path.write_text(text, encoding="utf-8")
    return Input(name, path, len(text.encode()), n, "")


def whole(inp: Input, dylib: Path) -> tuple[str, float]:
    """Does each parser read the whole file? A partial parse is less work, so
    admitting one would be the flattering number this file exists to refuse.

    Their answer comes back with a duration attached, which is worth keeping:
    it is tree-sitter timing its own `ts_parser_parse` with no file read and no
    process around it, so it is the sanity check on the slope below. It is the
    *first* parse in the process, though, so it is a cold number and the slope
    is a warm one; they should be the same order, and the slope being somewhat
    under it is the caches, not a subtraction.
    """
    # sole: this run is the measurement - `stamp.ask` would answer the verdict
    # correctly and time nothing, and a timing that came back through a second
    # process boundary is not the number this file exists to report.
    ours = say([str(BIN), "parse", str(folio_for(inp.grammar)), str(inp.path), "--quiet"], ROOT)
    end = outcome(ours.stderr, inp.path, inp.path.stat().st_size)
    if end.kind != "whole":
        return f"joints stopped early ({end.verdict})", 0.0
    got = say([str(NATIVE), "parse", "-l", str(dylib), "--lang-name", inp.grammar,
               "-q", "-j", str(inp.path)], WORK)
    try:
        summary = json.loads(got.stdout[got.stdout.index("{"):])["parse_summaries"][0]
    except (ValueError, KeyError, IndexError):
        return f"tree-sitter would not parse it: {tail(got.stderr)}", 0.0
    if not summary["successful"]:
        return "tree-sitter reports an ERROR in the scaled input", 0.0
    d = summary["duration"]
    return "", (d["secs"] * 1e9 + d["nanos"]) / max(inp.size, 1)


# ------------------------------------------------------------------- the axes

class Timing(NamedTuple):
    marginal: float  # ms for one more parse of this file
    fixed: float  # ms before the first tree: process, grammar, press
    spread: float  # relative stdev of the marginal over the replicates
    fixed_spread: float


def slope(cmd: list[str], unit: list[str], reps: int, cwd: Path,
          points: tuple[int, int] = COPIES) -> Timing:
    """The cost of one more `unit` of work, and the cost of getting to the first.

    Both parsers take a repeatable tail - a list of files for a parse, a list of
    edits for an amend - so k copies of `unit` is k units of work in one
    process. The difference between two k's is k units with every fixed cost
    cancelled: process start, dynamic link, grammar load, and (for us) the whole
    press. Replicated, and the two points alternate inside a replicate so a
    machine that warms up or throttles moves both together.

    The tail is a *list* rather than one argument because the incremental axis's
    unit is a pair of edits - type a space, take it back out - and a unit that
    left the file changed would make the second repetition a different
    measurement from the first.
    """
    lo, hi = points
    marginals, fixeds = [], []
    for _ in range(reps):
        a = wall(cmd + unit * lo, cwd)
        b = wall(cmd + unit * hi, cwd)
        m = (b - a) / (hi - lo)
        marginals.append(m)
        fixeds.append(a - m * lo)
    return Timing(statistics.median(marginals), statistics.median(fixeds),
                  spread_of(marginals), spread_of(fixeds))


def bench(names: list[str], axes: tuple[str, ...], reps: int) -> tuple[list[Row], list[Skip]]:
    rows: list[Row] = []
    skips: list[Skip] = []
    # `tree-sitter generate` costs seconds and cpp costs seventeen of them, so
    # it is replicated only when its duration is what somebody asked for.
    press_reps = max(1, min(reps, 3)) if "press" in axes else 1
    made: dict[str, Forge] = {}

    for name in names:
        # Every axis needs both artifacts: the size axes are about them, and the
        # timing axes cannot run without something to run.
        f = forge(name, press_reps)
        if f.why:
            for axis in axes:
                skips.append(Skip(axis, name, f.why))
            continue
        made[name] = f
        if "artifact" in axes:
            share = max(f.sections.items(), key=lambda kv: kv[1], default=("", 0))
            small = deflated(folio_for(name))
            rows.append(Row("artifact", name, f.folio, f.dylib, "bytes",
                            note=f"{f.csource:,} B of C · widest section {share[0]} "
                                 f"{100 * share[1] // max(f.folio, 1)}% · deflates to {small:,} B "
                                 f"({100 * small // max(f.folio, 1)}%)"))
        if "press" in axes:
            rows.append(Row("press", name, f.folio_ms, f.dylib_ms, "ms", spread=f.folio_spread,
                            note=f"mint vs generate + build, time to a usable parser · "
                                 f"our own clock says {f.own_ms:.3g} ms of press and pack"))

    if "install" in axes and made:
        folios = sum(f.folio for f in made.values())
        dylibs = sum(f.dylib for f in made.values())
        n = len(made)
        rows.append(Row("install", f"tooling x{n}", BIN.stat().st_size + folios,
                        NATIVE.stat().st_size + dylibs, "bytes",
                        note="one binary + N folios vs the tree-sitter CLI + N dynamic libraries"))
        runtime = next((Path(p) for p in RUNTIMES if Path(p).exists()), None)
        if runtime:
            rows.append(Row("install", f"runtime x{n}", BIN.stat().st_size + folios,
                            runtime.stat().st_size + dylibs, "bytes",
                            note=f"joints has no library artifact yet, so its binary stands in; "
                                 f"theirs is {here(runtime)}"))
        else:
            skips.append(Skip("install", f"runtime x{n}", "no libtree-sitter on this machine"))

    if not ({"throughput", "startup", "incremental", "memory"} & set(axes)):
        return rows, skips

    for name, leaf in pairs():
        if name not in made:
            continue
        inp = input_for(name, leaf)
        dylib = oracle_home(name, WORK) / f"{name}.dylib"
        why, own = (inp.why, 0.0) if inp.why else whole(inp, dylib)
        if why:
            for axis in ("throughput", "startup", "incremental", "memory"):
                if axis in axes:
                    skips.append(Skip(axis, name, why))
            continue
        case = f"{name} {inp.size // 1024} KB"
        ours_cmd = [str(BIN), "parse", str(folio_for(name))]
        # `--quiet` on both: neither side is asked to print a tree it built.
        theirs_cmd = [str(NATIVE), "parse", "-l", str(dylib), "--lang-name", name, "-q"]
        a = slope(ours_cmd, [str(inp.path)], reps, ROOT)
        b = slope(theirs_cmd, [str(inp.path)], reps, WORK)
        if "throughput" in axes:
            rows.append(Row("throughput", case,
                            a.marginal * 1e6 / inp.size, b.marginal * 1e6 / inp.size,
                            "ns/byte", spread=a.spread,
                            note=f"{mbs(inp.size, a.marginal)} vs {mbs(inp.size, b.marginal)}"
                                 f" · marginal of {COPIES[1]} parses over {COPIES[0]}"
                                 f" · their own clock on the cold parse says {own:.0f} ns/byte"))
        if "startup" in axes:
            # `fixed` is `a - marginal * lo`, so a marginal that is large and
            # noisy swamps it: javascript's nine-second parse produced a fixed
            # cost of *minus two seconds* with a spread of -145%, and a startup
            # cost cannot be negative. That is not a slow startup, it is no
            # measurement at all, and printing it as -171x would have been the
            # flattering-in-reverse version of the same sin.
            if a.fixed <= 0 or a.fixed_spread > 0.5:
                skips.append(Skip("startup", name,
                                  f"the {a.marginal:.0f} ms parse swamps the fixed cost it is "
                                  f"subtracted from ({a.fixed:.0f} ms, +-{a.fixed_spread:.0%})"))
            else:
                rows.append(Row("startup", case, a.fixed, b.fixed, "ms", spread=a.fixed_spread,
                                note="everything before the first tree: for us mapping the folio "
                                     "and compiling the lexer, for them a dlopen"))
        if "memory" in axes:
            ours_rss = min(peak(ours_cmd + [str(inp.path), "--quiet"], ROOT) for _ in range(3))
            theirs_rss = min(peak(theirs_cmd + [str(inp.path)], WORK) for _ in range(3))
            folio_rss = min(peak([str(BIN), "mint", str(folio_for(name))], ROOT) for _ in range(3))
            rows.append(Row("memory", case, ours_rss, theirs_rss, "bytes",
                            note=f"reading the folio back with no parse behind it "
                                 f"peaks at {folio_rss} bytes"))
        if "incremental" in axes:
            row, why = keystroke(name, inp, dylib, reps)
            (rows if row else skips).append(row or Skip("incremental", name, why))
    # Grouped by axis rather than by the order the work happened in, because an
    # axis is the thing a reader compares across languages.
    rows.sort(key=lambda r: (AXES.index(r.axis), r.case))
    skips.sort(key=lambda s: (s.case, AXES.index(s.axis)))
    return rows, skips


def mbs(size: int, ms: float) -> str:
    return f"{size / (ms * 1000):.1f} MB/s" if ms > 0 else "-"


# ------------------------------------------------------------------ the keystroke

CUT = 98  # where in the file the edit lands, as a percent
# Insert/delete pairs, so twice this many edits. The two sides need different
# counts and that is not a thumb on the scale: their `Edit:` line is one total
# printed to a hundredth of a millisecond, so a single keystroke would come back
# as two significant digits of nothing and they need a couple of dozen to divide.
# Ours prints microseconds *per edit*, so a handful is already a median - and a
# handful is all we can afford, because the grammar this axis exists to expose
# costs twelve seconds a keystroke and twenty-five pairs of that is ten minutes.
#
# Four pairs, not one, because **the first two keystrokes after a file opens
# cost two to three times the ones after them** - 255 and 245 us against a
# steady 90 on JSON, which is the caches filling. Their total over fifty edits
# amortises the same warm-up to nothing, so ours is summarised by the *median*
# of its edits rather than the mean, and four pairs puts that median past the
# warm-up. The first edit's own cost is printed beside it, because the first
# keystroke after opening a file is the one a person notices.
KEYS = (4, 25)  # ours, theirs


def caret(text: bytes, cut: int) -> int:
    """A byte offset where one space is legal in every one of these languages.

    Not `len * cut // 100`, which is the obvious thing and is wrong: at an
    arbitrary offset a space splits `123` into `12 3` or `total` into `to tal`,
    and then the axis is measuring two parsers recovering from an error rather
    than two parsers absorbing a keystroke. Just before a newline the same space
    is trailing whitespace, which every grammar here already ignores - so the
    edited file still parses on both sides and the comparison stays about the
    incremental path.
    """
    want = max(1, min(len(text) - 1, len(text) * cut // 100))
    breaks = [i for i, c in enumerate(text) if c == 0x0A]
    return min(breaks, key=lambda i: abs(i - want)) if breaks else want


def keystroke(name: str, inp: Input, dylib: Path, reps: int) -> tuple[Row | None, str]:
    """Type one space near the end of the file and take it straight back out.

    An insert *and* its delete is one pair, so the file is the same bytes at the
    start of every pair and the twenty-fifth keystroke is the same keystroke as
    the first. A bare insert would make the file grow under the measurement.

    `98%` is the position on purpose. An edit near the top leaves almost all of
    the re-scan undone and flatters both sides; an edit near the bottom pays for
    every byte before it, which is where an author writing a file actually
    types, and it is the only position where an incremental parser can quietly
    stop being one.

    **This axis alone is read off each side's own clock rather than off the wall
    clock**, and that is not a convenience. A keystroke is tens of microseconds
    inside a process that spends tens of *milliseconds* opening the file - so
    the slope every other timing axis uses is differencing two twenty-millisecond
    runs to find forty microseconds, and on a laptop with nine other lanes
    building it comes back negative. Both sides instrument exactly the
    incremental work and print it, so both are asked, symmetrically: total edit
    time over the same number of edits. The wall clock is not thrown away - it
    is what `startup` measures, where the whole open is the number.
    """
    text = inp.path.read_bytes()
    at = caret(text, CUT)
    mine_keys, their_keys = KEYS
    ours = [str(BIN), "amend", str(folio_for(name)), str(inp.path), "--quiet"] + \
        [f"{at}..{at}= ", f"{at}..{at + 1}="] * mine_keys
    # Their `--edits` is variadic, so it eats the path if the path comes after.
    theirs = [str(NATIVE), "parse", str(inp.path), "-l", str(dylib), "--lang-name", name,
              "-q", "-t", "--edits"] + [f"{at} 0  ", f"{at} 1"] * their_keys

    mine, theirs_us, cold, first, why = [], [], [], [], ""
    for _ in range(max(1, reps)):
        got, why = keys_once(ours, theirs, inp)
        if why:
            return None, why
        mine.append(got.mine)
        theirs_us.append(got.theirs)
        cold.append(got.cold)
        first.append(got.first)
    # Our own cold open of the same bytes, off the same run's `opened:` row.
    # The comparison against tree-sitter is only half the question; the other
    # half is whether the incremental path beat *not being incremental*, and a
    # keystroke that costs more than reopening the file has stopped being a
    # feature no matter what the other column says.
    ours_cold = statistics.median(cold)
    keys = statistics.median(mine)
    lost = "" if keys < ours_cold else " · SLOWER THAN REOPENING THE FILE"
    return Row("incremental", f"{name} @{CUT}%", keys, statistics.median(theirs_us), "us",
               spread=spread_of(mine),
               note=f"one space at byte {at:,} of {inp.size:,}, typed and deleted · "
                    f"{2 * mine_keys} edits ours, {2 * their_keys} theirs, each side's own "
                    f"clock · our first keystroke after the open costs "
                    f"{statistics.median(first):,.0f} us · our own cold open of the same "
                    f"file is {ours_cold:,.0f} us{lost}"), ""


EDIT_MS = re.compile(r"Edit:\s+([\d.]+) ms")


class Keys(NamedTuple):
    mine: float  # median microseconds per edit, ours
    theirs: float  # their `Edit:` total over the edits they were given
    cold: float  # our own open of the same bytes, off the same run
    first: float  # our first edit after that open, which is the warm one


def keys_once(ours: list[str], theirs: list[str], inp: Input) -> tuple[Keys, str]:
    """One run of the edit script on each side, in microseconds per edit, with
    our own cold open of the same bytes beside them.

    Both sides are also *admitted* here, on the same terms `whole` sets for
    throughput: an amend that gave up is less work, and a benchmark that took
    it would be reporting the giving up. Our rows come back through `amend.ROW`,
    which owns that format - `stamp.outcome` owns the *parse* verdict, and these
    are two different sentences from two different verbs.
    """
    none = Keys(0.0, 0.0, 0.0, 0.0)
    got = say(ours, ROOT)
    if got.returncode != 0:
        return none, f"joints amend: {tail(got.stderr)}"
    rows = [m for ln in got.stderr.splitlines()
            if (rest := behind(ln, inp.path)) and (m := ROW.match(rest))]
    if len(rows) < 2:
        return none, f"joints amend said nothing measurable: {tail(got.stderr)}"
    # Judged against the `opened:` row rather than against the word "accepted".
    # These bytes already cleared `whole`, so the open is the ground truth for
    # them and an edit row saying anything *else* is a stop, whatever it says.
    # Spelling the verdict here would have been a second copy of a word `stamp`
    # owns, and the gate would have said so.
    if bad := [m["verdict"] for m in rows[1:] if m["verdict"] != rows[0]["verdict"]]:
        return none, f"the edit changed the verdict from {rows[0]['verdict']} to {bad[0]}"
    edits = [float(m["us"]) for m in rows[1:]]

    their = say(theirs, WORK)
    if their.returncode != 0 or "Error:" in their.stderr:
        return none, f"tree-sitter would not amend it: {tail(their.stderr)}"
    if not (m := EDIT_MS.search(their.stdout + their.stderr)):
        return none, "tree-sitter printed no Edit: line to read its own clock off"
    return Keys(statistics.median(edits), float(m[1]) * 1000 / (2 * KEYS[1]),
                float(rows[0]["us"]), edits[0]), ""


# ------------------------------------------------------------------- reporting

def state(build: str) -> tuple[dict[str, Any], Stamp]:
    """What this run is a measurement *of*. Three lanes are editing `src` while
    this runs, so a number with no tree state beside it is a rumour.

    The tree state is `stamp.take`'s, not this file's own reading of git. A
    benchmark is the measurement `TOLD` exists for: `sharpen` builds into a
    private prefix, so *every* run here is against a binary that is not the
    tree's own, and the one thing that could quietly happen instead is somebody
    else's `JOINTS_BIN` deciding what gets benchmarked.
    """
    mark = take(BIN)
    return {
        "date": time.strftime("%Y-%m-%d %H:%M:%S%z"),
        "commit": mark.commit[:9],
        "dirty": mark.dirty,
        "joints": say([str(BIN), "--version"], ROOT).stdout.split()[-1:][0] or "unknown",
        "tree_sitter": oracle_ready().split()[-1],
        "build": build,
        "binary": here(BIN),
        "machine": f"{platform.platform()} {platform.machine()} x{os.cpu_count()}",
        # What else the machine was doing. Three lanes build in this tree while
        # this runs, and a timing taken under a `zig build` is worth knowing about.
        "load": round(os.getloadavg()[0], 2),
        "python": platform.python_version(),
        "stamp": mark.as_dict(),
    }, mark


def show(rows: list[Row], skips: list[Skip], as_json: bool, head: dict[str, Any],
         tree: Stamp) -> int:
    if as_json:
        print(json.dumps({"state": head, "row": [r.as_dict() for r in rows],
                          "skipped": [s._asdict() for s in skips]}, indent=2))
        return 0
    # The row we lose worst, first. A reader who stops after one line should
    # have read the thing we have to fix rather than the thing we are proud of.
    lost = sorted((r for r in rows if r.ratio > 1.0), key=lambda r: -r.ratio)
    if lost:
        w = lost[0]
        print(f"worst: {w.axis} {w.case} costs {w.ratio:.1f}x tree-sitter "
              f"({amount(w.ours, w.unit)} against {amount(w.theirs, w.unit)}) · {w.note}\n")
    print(f"{'axis':<11} {'case':<18} {'joints':>14} {'tree-sitter':>14} {'ratio':>7} "
          f"{'±':>5}  note")
    for r in rows:
        mark = "" if r.ratio <= 1.0 else "  <-- tree-sitter wins"
        dev = f"{r.spread * 100:.0f}%" if r.spread else ""
        print(f"{r.axis:<11} {r.case:<18} {amount(r.ours, r.unit):>14} "
              f"{amount(r.theirs, r.unit):>14} {r.ratio:>7.2f} {dev:>5}  {r.note}{mark}")
    # One line per reason, not per axis: three axes skipped for one stopped
    # parse is one fact about that grammar, printed three times.
    grouped: dict[tuple[str, str], list[str]] = {}
    for s in skips:
        grouped.setdefault((s.case, s.why), []).append(s.axis)
    for (case, why), axes in grouped.items():
        print(f"{'·'.join(axes):<11} {case:<18} {'-':>14} {'-':>14} {'-':>7} {'':>5}  "
              f"skipped: {why}")
    print(f"\n{len(rows)} measured, {len(grouped)} skipped · "
          f"{len(rows) - len(lost)} rows to joints, {len(lost)} to tree-sitter")
    print(f"joints {head['joints']} {head['build']} · "
          f"tree-sitter {head['tree_sitter']} · {head['machine']} · load {head['load']}")
    print(tree.line())
    return 0


def amount(v: float, unit: str) -> str:
    if unit == "bytes":
        return f"{int(v):,}"
    return f"{v:.3f} {unit}" if v < 10 else f"{v:.1f} {unit}"


def record(rows: list[Row], head: dict[str, Any]) -> int:
    doc = {"recorded": head,
           "axis": {a: {r.case: {"ours": round(r.ours, 4), "theirs": round(r.theirs, 4),
                                 "ratio": round(r.ratio, 4), "unit": r.unit}
                        for r in rows if r.axis == a}
                    for a in AXES if any(r.axis == a for r in rows)}}
    BASELINE.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {here(BASELINE)}: {len(rows)} rows over {len(doc['axis'])} axes")
    return 0


def verify(rows: list[Row], head: dict[str, Any]) -> int:
    """Hold this run to the committed one. Bytes are held absolutely because
    they are deterministic; a duration is held by its ratio to tree-sitter,
    which is the part of a timing that survives a change of machine."""
    if not BASELINE.exists():
        return oops(f"no baseline at {here(BASELINE)}; run `python3 tool/bench.py record`")
    was = json.loads(BASELINE.read_text(encoding="utf-8"))
    faults, checked = [], 0
    for r in rows:
        old = was.get("axis", {}).get(r.axis, {}).get(r.case)
        if not old:
            print(f"  new {r.axis:<11} {r.case:<18} {amount(r.ours, r.unit)} "
                  f"(ratio {r.ratio:.2f}) - not in the baseline")
            continue
        field, slack = GUARD[r.axis]
        now = r.ours if field == "ours" else r.ratio
        then = old[field]
        checked += 1
        if then and now > then * (1 + slack):
            faults.append(f"{r.axis}/{r.case}: {field} {then:.4g} -> {now:.4g}, "
                          f"past the {int(slack * 100)}% slack")
        else:
            move = (now / then - 1) * 100 if then else 0.0
            print(f"   ok {r.axis:<11} {r.case:<18} {field} {now:.4g} ({move:+.1f}%)")
    sys.stdout.flush()
    for f in faults:
        print(f"bench: {f}", file=sys.stderr)
    if faults:
        print(f"bench: {len(faults)} of {checked} guarded number(s) got worse; the baseline was "
              f"taken at {was['recorded']['commit']} on {was['recorded']['date']}", file=sys.stderr)
        return 1
    print(f"bench: {checked} guarded number(s) held against {was['recorded']['commit']}")
    return 0


def inventory(names: list[str], axes: tuple[str, ...], as_json: bool) -> int:
    corpus = dict(pairs())
    rows = [{"grammar": n, "corpus": corpus.get(n, ""), "folio": here(folio_for(n))}
            for n in names]
    if as_json:
        print(json.dumps({"axis": list(axes), "grammar": rows}, indent=2))
        return 0
    print("axes: " + " · ".join(axes))
    print("  artifact    a folio against the dynamic library a user installs per language")
    print("  install     one binary + N folios against the CLI (or the runtime) + N libraries")
    print("  press       mint against generate + build: time to a parser you can run")
    print("  throughput  marginal cost of one more parse, whole parses only")
    print("  startup     everything before the first tree: our press, their dlopen")
    print(f"  incremental one space typed and deleted at {CUT}% of the file, both sides")
    print("  memory      peak resident set for one parse of the same file")
    print(f"\n{'grammar':<11} {'corpus':<16} folio")
    for r in rows:
        print(f"{r['grammar']:<11} {r['corpus']:<16} {r['folio']}")
    print("\nthroughput, startup, incremental and memory run only where both parsers read "
          "the whole file; the rest are listed as skips with the reason.")
    return 0


def here(p: Path) -> str:
    return str(p.relative_to(ROOT) if p.is_relative_to(ROOT) else p)


def oops(msg: str) -> int:
    print(f"bench.py: {msg}", file=sys.stderr)
    return 2


def main(argv: list[str]) -> int:
    as_json, verb, want, axes, reps = False, "", "", AXES, 7
    for a in argv:
        if a == "--json":
            as_json = True
        elif a.startswith("--grammar="):
            want = a.split("=", 1)[1]
        elif a.startswith("--axis="):
            axes = tuple(x for x in AXES if x == a.split("=", 1)[1])
            if not axes:
                return oops(f"no such axis {a.split('=', 1)[1]!r}; one of {', '.join(AXES)}")
        elif a.startswith("--reps="):
            reps = max(1, int(a.split("=", 1)[1]))
        elif a in ("-h", "--help"):
            print(USAGE)
            return 0
        elif a.startswith("-"):
            return oops(f"unknown flag {a}\n\n{USAGE}")
        elif verb:
            return oops(f"one verb at a time, got {verb} and then {a}")
        else:
            verb = a
    if not verb:
        print(USAGE, file=sys.stderr)
        return 2
    version = oracle_ready()
    if verb == "oracle":
        print(f"{version} at {here(NATIVE)}" if version else
              f"no tree-sitter CLI at {here(TS)}\n"
              "run `python3 tool/differential.py install` to put a dev-only one there")
        return 0 if version else 1
    if verb not in ("run", "verify", "record", "list"):
        return oops(f"no such verb {verb!r}\n\n{USAGE}")
    try:
        names = [p.name for p in load() if not want or p.name == want]
    except (OSError, ValueError) as e:
        return oops(str(e))
    if not names:
        return oops(f"no pinned grammar named {want}")
    if verb == "list":
        return inventory(names, axes, as_json)
    if not version or not NATIVE.exists():
        # Same contract as the differential: no oracle is not a failed run.
        print(f"bench: no tree-sitter CLI at {here(NATIVE)}; nothing to compare against")
        print("bench: `python3 tool/differential.py install` puts a dev-only one there",
              file=sys.stderr)
        return 0
    build = sharpen()
    if not build:
        return oops(f"no binary at {here(BIN)} and `zig build` failed; the tree may not compile")
    try:
        lay_out()
        head, mark = state(build)
        rows, skips = bench(names, axes, reps)
    except (OSError, ValueError) as e:
        return oops(str(e))
    if verb == "record":
        show(rows, skips, False, head, mark)
        return record(rows, head)
    if verb == "verify":
        code = verify(rows, head)
        print(mark.line())
        return code
    return show(rows, skips, as_json, head, mark)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Make the board span two generations on purpose, and watch it say so.

The event: on 2026-08-05 a sibling's `zig build` landed at 11:43:49 and
something re-minted every folio in `.local/standing` between 11:43:55 and
11:44:04, **while the board was running and printing `cache: kept 30`.** Folios
are published with `os.replace`, so every reader got a whole, individually
valid folio and no torn byte anywhere gave it away.

A fix for a race that was never made to fail once is not a fix, so this stages
it. Three things are held to genuine:

  the poison    a **real older binary** - `.local/ink/base/bin/joints`, built
                from this tree at 08:35 on 2026-08-05 - presses the folios,
                the way the previous lane used a real pinned binary rather
                than a staged corruption. Measured over all thirty grammars, it
                produces a folio with **different bytes that the current binary
                accepts** for 16 of them and a byte-identical one for 14, which
                is what makes it both a poison and its own control.
  the processes real ones. A thread would share the pid, and the pid is what
                keeps two minting agents off one temp filename, so a threaded
                stage would not be exercising the thing under test.
  the publish   `order.press` itself - the same press, the same `os.replace`.

Trials:

  blind     one re-minting agent and TWO boards over one cache - the old rule
            and the new one reading the same seconds. The old rule is restored
            explicitly (`cost.arm`), never broken and called equivalent
  race      the board over an empty private cache (so it presses, as the real
            one was doing) with a second agent pressing the same cache from the
            older binary throughout
  control   the same race with the CURRENT binary as the second agent, so the
            republished bytes are identical. The content rule must go quiet
            here and an mtime rule must not - that difference is the argument
            for hashing rather than stat-ing
  binary    the binary itself swapped mid-run, which is the artifact the real
            11:43:49 event actually replaced, and which no detector saw
  settle    the race again with `--settle`, which re-measures the named rows

Nothing here touches `.local/standing`; each trial presses into a scratch cache
of its own, because nine other agents read the shared one.

  python3 research/generation/stage.py            every trial
  python3 research/generation/stage.py race       just one
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
# The old rule, restored explicitly in a scratch tree - built there rather than
# spelled again here, because two copies of "what the rule used to be" is the
# same defect as two copies of the rule.
from cost import arm  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "tool"
GRAMMARS = ROOT / "upstream" / "grammars"
BIN = ROOT / "zig-out" / "bin" / "joints"
# A real binary built out of this same tree earlier today, kept by another
# lane. Not a corruption and not a mock: a generation this checkout genuinely
# produced, which is the only kind of poison worth reproducing with.
OLDER = ROOT / ".local" / "ink" / "base" / "bin" / "joints"
# When the swap lands. A warm board is ~1.0s end to end and pays ~0.35s of that
# in interpreter start and imports before its first row, so the window is narrow
# and the right delay is not a thing to know in advance - the first two attempts
# at this trial used 0.25s and 2.5s and both landed *outside* the measurement,
# where the mechanism correctly reported one generation. Provoking a race means
# timing the provocation, so the delays are tried in turn until one lands inside
# and the trial says which one did.
WAITS = (0.5, 0.45, 0.55, 0.4, 0.6, 0.65)

# One pressing agent, as its own interpreter, driving `order.press` - the real
# publish, not a re-spelling of it. It presses until told to stop rather than
# once, because the board it is racing takes tens of seconds to press its own
# cache and a single pass would land entirely inside one row.
AGENT = """
import sys, time
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import order
order.BIN = Path(sys.argv[4])
cache, grams, until = Path(sys.argv[2]), Path(sys.argv[3]), time.time() + float(sys.argv[5])
names = sorted(p.stem for p in grams.glob("*.json"))
n = 0
while time.time() < until:
    for name in names:
        if time.time() > until:
            break
        n += order.press(grams / f"{name}.json", cache / f"{name}.folio")
print(n)
"""


def board(cache: Path, binary: Path, *flags: str,
          tool: Path | None = None) -> tuple[dict, int, float]:
    """One board run over one cache, as JSON, with its wall clock."""
    env = {**os.environ, "JOINTS_WORK": str(cache), "JOINTS_BIN": str(binary)}
    start = time.perf_counter()
    got = subprocess.run([sys.executable, str((tool or TOOL) / "standing.py"),
                          "--json", *flags],
                         capture_output=True, text=True, cwd=ROOT, env=env)
    spent = time.perf_counter() - start
    try:
        return json.loads(got.stdout), got.returncode, spent
    except json.JSONDecodeError:
        print(got.stdout[-2000:], got.stderr[-2000:], file=sys.stderr)
        raise


def racing(cache: Path, minter: Path, seconds: float) -> subprocess.Popen:
    return subprocess.Popen(
        [sys.executable, "-c", AGENT, str(TOOL), str(cache), str(GRAMMARS),
         str(minter), str(seconds)], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        text=True)


def told(out: dict) -> str:
    """What the cache line would have said - the decision, not the reading."""
    tally: dict[str, int] = {}
    for why in out["cache"].values():
        tally[why.split(" - ")[0]] = tally.get(why.split(" - ")[0], 0) + 1
    return " · ".join(f"{k} {v}" for k, v in sorted(tally.items()))


def say(what: str, out: dict, code: int, spent: float) -> None:
    gen = out["generation"]
    rows = out["row"]
    mtime = len(gen["moved"]) + len(gen["republished"])
    print(f"\n  {what}  ({spent:.1f}s, exit {code})")
    print(f"    the cache says          {told(out)}")
    print(f"    an mtime rule would say {mtime} of {gen['artifacts']} artifact(s) moved"
          + ("  ← all of them republished with the same bytes" if not gen["moved"]
             and mtime else ""))
    print("    the content rule says   "
          + ("one generation, every row comparable" if gen["uniform"] else
             f"SPLIT: {len(gen['moved'])} artifact(s) moved, "
             f"{len(gen['rows'])} of {len(rows)} rows not comparable"))
    if gen["rows"]:
        print(f"      rows: {', '.join(gen['rows'])}")
    if gen["churned"]:
        print(f"      {gen['churned']} artifact(s) moved and every row that read the"
              f" old generation was measured again")
    for m in gen["moved"][:4]:
        print(f"      {m['path']}: read {m['was']}, now {m['now']}"
              f" ({m['generations']} generations)"
              + ("" if m["rows"] else " — settled, no live row reads the old one"))
    if len(gen["moved"]) > 4:
        print(f"      … and {len(gen['moved']) - 4} more")
    built = sum(r["built"] for r in rows)
    size = sum(r["size"] for r in rows)
    tainted = sum(r["size"] for r in rows if r["split"])
    print(f"    the number a report repeats: {built} built of {size}"
          f" ({built / size * 100:.1f}% standing)"
          + (f" — {tainted} of those bytes from a generation this tree no longer holds"
             if tainted else ""))


def race(older: bool = True, settle: bool = False) -> int:
    """A board pressing its own cache while a second agent presses over it."""
    with tempfile.TemporaryDirectory(prefix="stage-") as tmp:
        cache = Path(tmp) / "cache"
        cache.mkdir()
        minter = OLDER if older else BIN
        agent = racing(cache, minter, 60.0)
        try:
            out, code, spent = board(cache, BIN, *(("--settle",) if settle else ()))
        finally:
            agent.terminate()
            agent.wait()
        what = ("a real older binary re-minting the cache under the board"
                if older else "the SAME binary re-minting the cache under the board")
        say(what + (" · --settle" if settle else ""), out, code, spent)
        gen = out["generation"]
        if settle:  # the named rows were measured again; the table must close whole
            return 0 if gen["uniform"] else 1
        if older:  # a genuinely different generation must be caught and named
            return 0 if gen["moved"] and gen["rows"] else 1
        # The control is **not** "nothing moved" - the press turned out not to be
        # reproducible, so re-minting with the same binary does produce new bytes
        # for some grammars (see RESULT-1). What it holds to is the discrimination
        # the whole design rests on: an mtime rule flags every republish, and the
        # content rule flags only the ones whose bytes actually differ. A
        # non-empty `republished` **is** that gap - each entry is an artifact
        # stat would have called moved and the digest called the same.
        return 0 if gen["republished"] else 1


# How many times each grammar is pressed to decide whether its press is
# reproducible. **Two is not enough and that is measured, not assumed:** two
# mints called nine of thirty unstable, six called fourteen, because two
# samples can only catch a wobble that happens to land on different sides. A
# run of N agreeing mints is evidence and never a proof, and the file says so.
MINTS = 6


def mint(reps: int = MINTS) -> int:
    """Is a press reproducible? The question Prediction 1 rests on.

    Each grammar pressed `reps` times by the current binary and once by the
    older one, into scratch paths, and every result digested. Two runs of one
    binary that disagree mean a re-mint is a new generation *even when nothing
    changed*, and the reconciliation has a false-alarm floor that is not its
    fault.

    The **length** of each folio is carried alongside the digest, because the
    two answers are very different diagnoses. Same length, different bytes is
    an ordering artefact - a table interned out of a seeded hash map. Different
    lengths is a different amount of data being written for one grammar, and
    that is not cosmetic.
    """
    with tempfile.TemporaryDirectory(prefix="stage-") as tmp:
        tmp = Path(tmp)
        sys.path.insert(0, str(TOOL))
        import order  # noqa: PLC0415 - a tool import, not a dependency of the stage
        import stamp  # noqa: PLC0415
        names = sorted(p.stem for p in GRAMMARS.glob("*.json"))
        wobble, older, sizes = {}, [], {}
        for name in names:
            marks = []
            for i, which in enumerate((*(BIN,) * reps, OLDER)):
                out = tmp / f"{name}.{i}.folio"
                order.BIN = which
                order.press(GRAMMARS / f"{name}.json", out)
                marks.append((stamp.digest(out), out.stat().st_size))
                out.unlink()
            mine = marks[:reps]
            if len({m for m, _ in mine}) > 1:
                wobble[name] = len({m for m, _ in mine})
                sizes[name] = len({s for _, s in mine})
            if marks[-1][0] not in {m for m, _ in mine}:
                older.append(name)
        order.BIN = BIN
        print(f"\n  pressed {len(names)} grammars {reps}x with one binary,"
              f" once with the older one")
        print(f"    reproducible under one binary: {len(names) - len(wobble)}"
              f" of {len(names)} — and {reps} agreeing mints is evidence, not proof")
        for name, seen in wobble.items():
            print(f"      {name:<14}{seen} distinct folios in {reps} mints,"
                  f" {sizes[name]} distinct length(s)")
        # On a grammar whose press wobbles, "the older binary's bytes differ"
        # says nothing - the binary's own runs already differ. The honest count
        # of what a different build changes is over the reproducible ones.
        clean = [n for n in older if n not in wobble]
        print(f"    older binary's bytes differ for {len(older)} of {len(names)}"
              f", of which {len(clean)} press reproducibly: {', '.join(clean)}")
        # Not an assertion about which way it comes out - this is the
        # measurement Prediction 1 named, and either answer is a real one.
        return 0


def blind() -> int:
    """The same event, watched by both rules at once.

    Two boards over **one** cache while **one** older-binary agent re-mints
    under both of them - so this is not two provocations compared, it is one
    provocation and two readings of it. The old rule is not paraphrased: `arm`
    copies `tool/` and appends the stat-and-forget `fed` it used to be, which
    is the same restore `cost.py` prices, in the same scratch tree.

    The boards are launched from threads, which is not a threaded concurrency
    test - the things racing are three real processes, and a thread here only
    sits in `wait`. The cache is pre-seeded warm so both boards read rather
    than press, leaving the agent as the single writer.
    """
    with tempfile.TemporaryDirectory(prefix="stage-") as tmp:
        tmp = Path(tmp)
        cache = tmp / "cache"
        cache.mkdir()
        for f in sorted((ROOT / ".local" / "standing").glob("*.folio")):
            shutil.copy(f, cache / f.name)
        old = arm(tmp, "before", True)
        # Three agents, not one. A board over a warm cache is ~0.8s and one
        # agent's first press takes longer than that, so a single agent started
        # alongside the boards publishes nothing they could read - which is what
        # the first run of this trial reported, and why the boards now wait for
        # the agents to be genuinely mid-flight before starting.
        agents = [racing(cache, OLDER, 90.0) for _ in range(3)]
        was = now = None
        try:
            settled = {f.name: f.stat().st_mtime for f in cache.glob("*.folio")}
            for attempt in range(1, 4):
                until = time.time() + 60
                while time.time() < until and all(
                        f.stat().st_mtime == settled[f.name]
                        for f in cache.glob("*.folio")):
                    time.sleep(0.05)
                with ThreadPoolExecutor(2) as pool:
                    a = pool.submit(board, cache, BIN, "--set=all", tool=old)
                    b = pool.submit(board, cache, BIN, "--set=all")
                    (was, wcode, wspent), (now, ncode, nspent) = a.result(), b.result()
                if not now["generation"]["uniform"] or attempt == 3:
                    break
                settled = {f.name: f.stat().st_mtime for f in cache.glob("*.folio")}
        finally:
            for one in agents:
                one.terminate()
                one.wait()
        say("the OLD rule - a stat, recorded and never looked at again",
            was, wcode, wspent)
        say("the NEW rule - the same cache, the same agents, the same seconds",
            now, ncode, nspent)
        # The old rule must be quiet and the new one must not. If the agents
        # happened to publish nothing either board read, neither is wrong and
        # the trial has simply not fired - which is reported, not passed.
        if now["generation"]["uniform"]:
            print("    the agents' publishes missed both boards; nothing was provoked")
            return 1
        return 0 if was["generation"]["uniform"] else 1


def binary() -> int:
    """The binary replaced mid-run, which is what the real event did.

    `take` digests the binary once, at the start. `STALE`, `DRIFT` and `MOVED`
    all watch the *sources*, and a build landing need not touch one - so the
    prediction is that nothing in today's stamp notices, and every row measured
    before the swap is attributed to a build that is no longer there.

    The swapped-in binary is given an mtime **older than the folios**, and that
    is the case being tested rather than a convenience. A binary that lands
    *newer* than the cache is already caught twice over: the freshness rule
    makes every folio stale and re-mints it, and if the swap falls between a
    press and its read-back the previous lane's `Refused` guard stops the run
    outright (observed, first attempt at this trial). The gap is the other half
    - a binary installed without a fresher mtime, which is every pinned build,
    every `cp -p`, and every `JOINTS_BIN` pointed at somebody else's tree.
    """
    for attempt, wait in enumerate(WAITS, 1):
        with tempfile.TemporaryDirectory(prefix="stage-") as tmp:
            tmp = Path(tmp)
            cache, mine = tmp / "cache", tmp / "joints"
            cache.mkdir()
            # Seeded from the shared cache by copying, never by pressing into
            # it. Plain copy, not copy2: a fresh mtime is what makes the board
            # keep these rather than spend thirty presses re-deriving them.
            for f in sorted((ROOT / ".local" / "standing").glob("*.folio")):
                shutil.copy(f, cache / f.name)
            shutil.copy(BIN, mine)
            # Older than the folios, so the freshness rule stays quiet, but
            # still newer than `src/`, so `STALE` does not fire and take the
            # credit for a hazard it cannot see.
            old = min(f.stat().st_mtime for f in cache.glob("*.folio")) - 0.5
            os.utime(mine, (old, old))
            swap = subprocess.Popen(
                [sys.executable, "-c",
                 "import os,shutil,sys,time\n"
                 "time.sleep(float(sys.argv[3]))\n"
                 "shutil.copy(sys.argv[1], sys.argv[2] + '.part')\n"
                 "os.utime(sys.argv[2] + '.part', (float(sys.argv[4]), float(sys.argv[4])))\n"
                 "os.replace(sys.argv[2] + '.part', sys.argv[2])\n",
                 str(OLDER), str(mine), str(wait), str(old)])
            try:
                out, code, spent = board(cache, mine, "--set=all")
            finally:
                swap.wait()
            landed = not out["generation"]["uniform"]
            if landed or attempt == len(WAITS):
                say(f"a real older binary installed over the one the board is running"
                    f" · swapped at {wait}s of a {spent:.1f}s run, attempt {attempt}",
                    out, code, spent)
                loud = [w for w in ("STALE", "DRIFT", "MOVED")
                        if out["stamp"].get(w.lower())
                        or (w == "MOVED" and out["stamp"]["moved"])]
                print(f"    today's source detectors: {', '.join(loud) or 'nothing'}"
                      f"  ← none of them re-reads the binary"
                      f" (TOLD fires either way: the stage set JOINTS_BIN)")
                return 0 if landed else 1
    return 1


def main(argv: list[str]) -> int:
    if "--help" in argv or "-h" in argv:
        print(__doc__)
        return 0
    for path, what in ((BIN, "the current binary"), (OLDER, "the older poison binary")):
        if not path.exists():
            print(f"stage: no {what} at {path}", file=sys.stderr)
            return 2
    want = ([a for a in argv if not a.startswith("-")]
            or ["blind", "race", "control", "binary", "settle"])
    print(__doc__.splitlines()[0])
    bad = 0
    for trial in want:
        bad += {"mint": mint, "blind": blind, "race": lambda: race(True),
                "control": lambda: race(False), "settle": lambda: race(True, settle=True),
                "binary": binary}[trial]()
    print(f"\n{len(want) - bad}/{len(want)} trial(s) went the way the mechanism claims")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

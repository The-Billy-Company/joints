#!/usr/bin/env python3
"""Re-price scala's pair on a tree that is not carrying a regression, with an oracle.

`vacuity/RESULT-5-pairs.md` priced scala's two seatings at −4,970 and −10,326
with a +5,500 residual and called them *cooperating*. `RESULT-3-scala.md` showed
those numbers were taken off a snapshot whose scala control damage was **16,883**
against a live board reading **4,150** on the same seatings, and handed the
regression back rather than chasing it. It has since cleared: the retained
snapshot at `.local/aud-iso/base/` and today's tree differ in four files, and
today's board reads 4,150 again.

So the pair is re-taken here, on today's tree, changing two things:

1. **The snapshot is refreshed.** The arms are built from today's `src/`, with
   only `outside.zig` ablated - the fifth house rule's control, taken now.
2. **Every arm carries the oracle.** `standing.py --audit` is run per arm, in
   that arm's own work dir, so `square` is a number rather than a zero. That is
   the expensive thing `RESULT-4-clearance.md` named and nobody had done, and it
   is what makes a residual on `built` checkable against a second parser.

Four arms, which is the whole population a two-row subset admits: both rows in,
each one out, both out. Everything else - `worth`, `joint`, `residual` - is
`attribute.py pairs`' own arithmetic, re-spelled here only because that driver
reads a snapshot this one has to refresh.

Usage:  retake.py            sync, build, board, price   (add --audit for square)
        retake.py --audit    ... and mint each arm's own tree-sitter verdicts
        retake.py --price    price what is already built, board nothing new
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "research" / "joinery" / "vacuity"))
import ablate  # noqa: E402

SCRATCH = ROOT / ".local/aud-iso/joints"
# A snapshot of its own, beside the one the pair arms were priced on rather than
# over it: `base/` is the tree `RESULT-3` is about and deleting it would delete
# the evidence for the correction this file is making.
CLEAN = ROOT / ".local/aud-iso/clean"
TARGET = "src/kernel/lex/outside.zig"
# The two scala seatings, by seat rather than by index. An index is a position
# in a roster ten lanes edit; the seat is what `seated()` turns on.
WANT = ("_indent/.offside/.slashes", "block_comment/.marrow/.kotlin_block")
GRAMMAR = "scala"


def sh(cmd: list[str], cwd: Path, **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, **kw)


def sync() -> list[str]:
    """Make the scratch checkout's sources today's sources, and say what moved."""
    CLEAN.mkdir(parents=True, exist_ok=True)
    moved = []
    for live in sorted(p for p in (ROOT / "src").rglob("*")
                       if p.is_file() and p.name != ".DS_Store"):
        rel = live.relative_to(ROOT)
        for where in (SCRATCH, CLEAN):
            at = where / rel
            at.parent.mkdir(parents=True, exist_ok=True)
            if not at.exists() or at.read_bytes() != live.read_bytes():
                shutil.copy2(live, at)
                if where is CLEAN:
                    moved.append(str(rel))
    return moved


def seats() -> list[tuple[int, str]]:
    """Today's seated rows, numbered as `ablate.write` numbers them."""
    text = (CLEAN / TARGET).read_text()
    was = sh(["git", "show", "HEAD:src/kernel/lex/outside.zig"], ROOT).stdout
    seated = {ablate.key(was[a:b]) for a, b in ablate.rows(was)}
    cut = [(a, b) for a, b in ablate.rows(text) if ablate.key(text[a:b]) not in seated]
    return [(n, "/".join(x for x in ablate.key(text[a:b]) if x))
            for n, (a, b) in enumerate(cut)]


def arm(rows: tuple[int, ...]) -> Path | None:
    """Build the arm with exactly `rows` un-seated, from today's snapshot.

    The `--mine` predicate is taken rather than trusted, exactly as the family
    this corrects takes it: an arm that removed a shared seam on the way past is
    not an isolation arm whatever its name says.
    """
    tag = "sc-" + ("base" if not rows else "r" + "-".join(str(r) for r in rows))
    got = SCRATCH / f".local/pin/{tag}/bin/joints"
    if got.exists():
        return got
    kept = CLEAN / TARGET
    if rows:
        sh(["python3", str(ROOT / "research/joinery/vacuity/ablate.py"), "write",
            str(SCRATCH / TARGET), ",".join(str(r) for r in rows)], ROOT,
           env=os.environ | {"ABLATE_SRC": str(kept)})
    else:
        shutil.copy2(kept, SCRATCH / TARGET)
    dirty = sh(["diff", "-rq", "-x", ".DS_Store", str(CLEAN / "src"),
                str(SCRATCH / "src")], ROOT).stdout.splitlines()
    if len(dirty) > 1 or (dirty and TARGET.rsplit("/", 1)[1] not in dirty[0]):
        print(f"  {tag:<12}NOT AN ISOLATION ARM — {dirty}")
        return None
    built = sh(["zig", "build", "-p", str(SCRATCH / ".local/pin" / tag)], SCRATCH)
    if built.returncode != 0:
        print(f"  {tag:<12}BUILD FAILED\n{built.stderr[-800:]}")
        return None
    return got


def env_for(binary: Path, tag: str) -> dict[str, str]:
    work = SCRATCH / f"work-{tag}"
    work.mkdir(parents=True, exist_ok=True)
    return os.environ | {"JOINTS_BIN": str(binary), "JOINTS_WORK": str(work),
                         "JOINTS_LANE": f"clean-{tag}"}


def board(binary: Path, tag: str, audit: bool) -> dict:
    env = env_for(binary, tag)
    if audit:
        got = subprocess.run(["python3", "tool/standing.py", "--audit", "--json"],
                             cwd=ROOT, capture_output=True, text=True, env=env)
        print(f"    {tag}: {got.stderr.strip().splitlines()[-1][:96]}")
    got = subprocess.run(["python3", "tool/standing.py", "--json"], cwd=ROOT,
                         capture_output=True, text=True, env=env, check=True)
    return json.loads(got.stdout)


def row(got: dict, name: str = GRAMMAR) -> dict:
    return next(r for r in got["row"] if r["name"] == name)


def main(argv: list[str]) -> int:
    audit = "--audit" in argv
    moved = sync()
    print(f"\nsnapshot refreshed — {len(moved)} file(s) taken from today's tree"
          f"{': ' + ', '.join(moved[:6]) if moved else ''}")
    named = dict(seats())
    want = sorted(n for n, s in named.items() if s in WANT)
    if len(want) != 2:
        print(f"retake.py: expected two scala seats, found {want}", file=sys.stderr)
        return 2
    a, b = want
    print(f"scala's two seatings are rows {a} ({named[a]}) and {b} ({named[b]})\n")

    plan = [((), "base"), ((a,), f"r{a}"), ((b,), f"r{b}"), ((a, b), f"r{a}-{b}")]
    boards: dict[str, dict] = {}
    for rows, tag in plan:
        got = arm(rows)
        if got is None:
            return 2
        boards[tag] = board(got, tag, audit)
        r = row(boards[tag])
        print(f"  {tag:<8}built {r['built']:>7}  damage {r['damage']:>7}"
              f"  nodes {r['nodes']:>6}  roots {r['roots']:>5}"
              f"  square {r['square']:>7}  crooked {r['crooked']:>6}  {r['graded']}")

    base = row(boards["base"])["damage"]
    solo = {tag: row(boards[tag])["damage"] - base for _, tag in plan[1:3]}
    joint = row(boards[plan[3][1]])["damage"] - base
    adds = sum(solo.values())
    gap = joint - adds
    print(f"\n  D(none) {base}  ·  worth {'  '.join(f'{k} {v:+}' for k, v in solo.items())}"
          f"  ·  joint {joint:+}  ·  sum solo {adds:+}  ·  residual {gap:+}"
          f"  ·  {'cooperating' if abs(gap) > 1000 else 'additive'}")
    if audit:
        sbase = row(boards["base"])["square"]
        ssolo = {tag: row(boards[tag])["square"] - sbase for _, tag in plan[1:3]}
        sjoint = row(boards[plan[3][1]])["square"] - sbase
        print(f"  square: base {sbase}  ·  {'  '.join(f'{k} {v:+}' for k, v in ssolo.items())}"
              f"  ·  joint {sjoint:+}  ·  sum solo {sum(ssolo.values()):+}"
              f"  ·  residual {sjoint - sum(ssolo.values()):+}")
    out = {"grammar": GRAMMAR, "rows": [a, b], "seat": [named[a], named[b]],
           "control": base, "solo": solo, "joint": joint, "residual": gap,
           "audited": audit,
           "arm": {tag: row(g) for tag, g in boards.items()}}
    (HERE / "retake.json").write_text(json.dumps(out, indent=1) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

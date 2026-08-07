#!/usr/bin/env python3
"""Re-take the whole ablation family with an oracle seated in every arm.

`vacuity/RESULT-2-arms.md` (fourteen single-row arms), `RESULT-5-pairs.md` (five
pair arms) and the union arm were all read as *no collateral*: thirteen arms move
one grammar, one moves none, and the twenty-one grammars nobody seated are
byte-identical in all thirty-one columns. `consort/RESULT-5-blindness.md` then
established that every one of those arms read `square 0`, because the private
work dir that makes an arm an arm is where the oracle's verdicts live - so the
clearance was taken on `damage`, which is joints's own words about its own
forest and cannot see a change that leaves `built` untouched while moving every
leaf to a different parent.

This driver re-takes the same population with `standing.py --audit` paid inside
each arm's own work dir, so `square` - the only column that is a claim about
agreement with tree-sitter - is a number on every row of every arm.

Two things it does differently from `attribute.py`, both because of the fifth
and sixth house rules:

1. **One snapshot, taken now.** Every arm is built from a single copy of today's
   `src/`, so fifteen arms cannot disagree about which world they are in while
   ten lanes edit around them. The snapshot is this lane's own, beside rather
   than over `.local/aud-iso/`, whose `base/` carries the withdrawn press
   regression `RESULT-3-press.md` is about and whose `clean/` is `RESULT-6`'s
   evidence.
2. **The isolation predicate is taken, not asserted.** An arm whose `src/`
   differs from the snapshot in anything but `outside.zig` is not an isolation
   arm whatever its name says, and it is dropped by name rather than measured.

Usage:  sighted.py plan              the arms, and which of them are already taken
        sighted.py run [--jobs N] [tag…]   build · mint the oracle · board
        sighted.py score             per-arm `square` against the base arm
        sighted.py score --damage    the same table on `damage`, for the contrast
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "research" / "joinery" / "vacuity"))
import ablate  # noqa: E402

HOME = ROOT / ".local" / "sighted"
CLEAN = HOME / "clean"
BOARDS = HOME / "boards"
# Which tree the arms share. Live `src/` is the default and the right answer
# whenever it compiles; `$SIGHTED_SRC` is for the case this lane hit at 23:50,
# where the quire lane's in-flight `gather.zig` did not, and a family of
# twenty-one arms cannot be taken against a tree that will not build. A
# snapshot that is an hour old and whole beats a live one that is neither.
ORIGIN = Path(os.environ.get("SIGHTED_SRC") or ROOT / "src")
TARGET = "src/kernel/lex/outside.zig"
# The five pairs `RESULT-5-pairs.md` narrowed the 16,369 subsets down to, by the
# rows' own candidate sets, plus the union arm the clearance was quoted off.
PAIRS = ((0, 4), (2, 12), (3, 11), (6, 13), (7, 8))
SINGLES = tuple((r,) for r in range(14))
UNION = tuple(range(14))


def tag_of(rows: tuple[int, ...]) -> str:
    if not rows:
        return "base"
    if rows == UNION:
        return "union"
    return "r" + "-".join(str(r) for r in rows)


PLAN: tuple[tuple[int, ...], ...] = ((), *SINGLES, *PAIRS, UNION)


def sh(cmd: list[str], cwd: Path, **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, **kw)


def snapshot() -> list[str]:
    """Today's `src/` into this lane's own snapshot, and what that moved."""
    moved = []
    for live in sorted(p for p in ORIGIN.rglob("*")
                       if p.is_file() and p.name != ".DS_Store"):
        at = CLEAN / "src" / live.relative_to(ORIGIN)
        at.parent.mkdir(parents=True, exist_ok=True)
        if not at.exists() or at.read_bytes() != live.read_bytes():
            shutil.copy2(live, at)
            moved.append(str(live.relative_to(ORIGIN)))
    return moved


def seats() -> dict[int, str]:
    """Today's seated rows, numbered as `ablate.write` numbers them."""
    text = (CLEAN / TARGET).read_text()
    was = sh(["git", "show", "HEAD:src/kernel/lex/outside.zig"], ROOT).stdout
    seated = {ablate.key(was[a:b]) for a, b in ablate.rows(was)}
    cut = [(a, b) for a, b in ablate.rows(text) if ablate.key(text[a:b]) not in seated]
    return {n: "/".join(x for x in ablate.key(text[a:b]) if x)
            for n, (a, b) in enumerate(cut)}


def scratch(n: int) -> Path:
    """One build tree per worker, cloned from the first, sources from CLEAN."""
    at = HOME / f"scratch{n}"
    if not at.is_dir():
        sh(["cp", "-Rc", str(HOME / "scratch1"), str(at)], ROOT)
        shutil.rmtree(at / ".local" / "pin", ignore_errors=True)
    for live in sorted(p for p in (CLEAN / "src").rglob("*") if p.is_file()):
        rel = live.relative_to(CLEAN)
        into = at / rel
        into.parent.mkdir(parents=True, exist_ok=True)
        if not into.exists() or into.read_bytes() != live.read_bytes():
            shutil.copy2(live, into)
    return at


def build(rows: tuple[int, ...], at: Path) -> Path | None:
    tag = tag_of(rows)
    got = at / ".local/pin" / tag / "bin/joints"
    if got.exists():
        return got
    if rows:
        sh(["python3", str(ROOT / "research/joinery/vacuity/ablate.py"), "write",
            str(at / TARGET), ",".join(str(r) for r in rows)], ROOT,
           env=os.environ | {"ABLATE_SRC": str(CLEAN / TARGET)})
    else:
        shutil.copy2(CLEAN / TARGET, at / TARGET)
    # Taken rather than trusted: an arm that took a shared seam out on the way
    # past is not an isolation arm, and the file it lost is the useful report.
    dirty = sh(["diff", "-rq", "-x", ".DS_Store", str(CLEAN / "src"),
                str(at / "src")], ROOT).stdout.splitlines()
    if len(dirty) > 1 or (dirty and "outside.zig" not in dirty[0]):
        print(f"  {tag:<10}NOT AN ISOLATION ARM — {dirty}", flush=True)
        return None
    made = sh(["zig", "build", "-p", str(at / ".local/pin" / tag)], at)
    if made.returncode != 0:
        print(f"  {tag:<10}BUILD FAILED\n{made.stderr[-600:]}", flush=True)
        return None
    return got


def measure(binary: Path, tag: str, at: Path) -> dict | None:
    """Mint this arm's own verdicts, then board it. Sighted or it did not happen."""
    work = at / f"work-{tag}"
    work.mkdir(parents=True, exist_ok=True)
    env = os.environ | {"JOINTS_BIN": str(binary), "JOINTS_WORK": str(work),
                        "JOINTS_LANE": f"sq-{tag}"}
    swept = subprocess.run([sys.executable, "tool/standing.py", "--audit", "--json"],
                           cwd=ROOT, capture_output=True, text=True, env=env)
    if swept.returncode not in (0, 3):
        print(f"  {tag:<10}AUDIT FAILED — {swept.stderr.strip().splitlines()[-1:]}",
              flush=True)
        return None
    got = subprocess.run([sys.executable, "tool/standing.py", "--json"], cwd=ROOT,
                         capture_output=True, text=True, env=env)
    if got.returncode not in (0, 3):
        print(f"  {tag:<10}BOARD FAILED — {got.stderr.strip().splitlines()[-1:]}",
              flush=True)
        return None
    board = json.loads(got.stdout)
    board["tag"] = tag
    board["binary"] = str(binary)
    BOARDS.mkdir(parents=True, exist_ok=True)
    (BOARDS / f"{tag}.json").write_text(json.dumps(board, indent=1) + "\n")
    return board


def sighted(board: dict) -> tuple[int, int]:
    """Rows whose verdict the board *accepted*, and the square they carry.

    Off the rows and not off the cache, for the reason `blind.py` was written:
    a board holding thirty verdicts it refused as `stale` has read no square,
    and the cache cannot tell you that.
    """
    live = [r for r in board["row"] if r.get("graded") in ("read", "part")]
    return len(live), sum(r.get("square", 0) for r in live)


def one(rows: tuple[int, ...], n: int) -> tuple[str, dict | None]:
    tag = tag_of(rows)
    at = scratch(n)
    began = time.time()
    binary = build(rows, at)
    if binary is None:
        return tag, None
    board = measure(binary, tag, at)
    if board is None:
        return tag, None
    seen, square = sighted(board)
    print(f"  {tag:<10}{seen:>2}/30 sighted · square {square:>7} · "
          f"{time.time() - began:5.0f}s", flush=True)
    return tag, board


def run(argv: list[str]) -> int:
    jobs = next((int(a.split("=", 1)[1]) for a in argv if a.startswith("--jobs=")), 3)
    want = [a for a in argv if not a.startswith("-")]
    moved = snapshot()
    print(f"snapshot: {len(moved)} file(s) taken from today's tree"
          f"{': ' + ', '.join(moved[:4]) if moved else ' (already current)'}")
    named = seats()
    print(f"{len(named)} row(s) seated today\n")
    plan = [r for r in PLAN if not want or tag_of(r) in want]
    plan = [r for r in plan if not (BOARDS / f"{tag_of(r)}.json").exists()]
    if not plan:
        print("every arm asked for is already on disk")
        return 0
    print(f"{len(plan)} arm(s) to take, {jobs} at a time\n")
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        got = list(pool.map(lambda t: one(t[1], 1 + t[0] % jobs), enumerate(plan)))
    return 0 if all(b is not None for _, b in got) else 1


def boards() -> dict[str, dict]:
    return {p.stem: json.loads(p.read_text()) for p in sorted(BOARDS.glob("*.json"))}


def column(board: dict, field: str) -> dict[str, int]:
    return {r["name"]: r.get(field, 0) for r in board["row"]}


def score(argv: list[str]) -> int:
    """What each arm moved, per grammar, on both columns at once.

    `worth` is stated so that **positive means the seating is doing good**:
    on `square` that is `base − arm` (the arm has *less* agreement with
    tree-sitter), on `damage` it is `arm − base` (the arm has *more* unbuilt).
    Printing the two side by side is the point - a row whose two worths have
    different signs is a row `damage` was lying about, and ocaml's is the one
    already proven.

    **Collateral** is any grammar moving that the arm's rows cannot seat. That
    is the question the whole family was quoted for and the one it could not
    answer, because every arm in it read `square 0`.
    """
    got = boards()
    if "base" not in got:
        print("sighted.py: no base arm on disk yet", file=sys.stderr)
        return 2
    named = seats()
    seen, total = sighted(got["base"])
    base = {f: column(got["base"], f) for f in ("square", "damage", "roots", "crooked")}
    print(f"\nbase arm: {seen}/30 rows sighted · {total} square · "
          f"{sum(base['damage'].values())} damage\n")
    print(f"  {'arm':<9}{'grammar':<9}{'square':>17}{'worth':>8}"
          f"{'damage':>15}{'worth':>8}{'roots':>13}   collateral")
    out = []
    for rows in PLAN[1:]:
        tag = tag_of(rows)
        if tag not in got:
            continue
        arm = {f: column(got[tag], f) for f in base}
        mine = sorted({OWNER[r] for r in rows if r in OWNER})
        moved = sorted(g for g in base["square"]
                       if any(base[f].get(g) != arm[f].get(g) for f in
                              ("square", "damage", "roots")))
        other = [g for g in moved if g not in mine]
        for g in mine:
            sq = (base["square"][g], arm["square"].get(g, 0))
            dm = (base["damage"][g], arm["damage"].get(g, 0))
            rt = (base["roots"][g], arm["roots"].get(g, 0))
            print(f"  {tag:<9}{g:<9}{f'{sq[0]}→{sq[1]}':>17}{sq[0] - sq[1]:>+8}"
                  f"{f'{dm[0]}→{dm[1]}':>15}{dm[1] - dm[0]:>+8}"
                  f"{f'{rt[0]}→{rt[1]}':>13}   {', '.join(other) or 'none'}")
            out.append({"arm": tag, "rows": list(rows), "grammar": g,
                        "seat": [named.get(r, "") for r in rows],
                        "square": sq, "damage": dm, "roots": rt,
                        "square_worth": sq[0] - sq[1], "damage_worth": dm[1] - dm[0],
                        "crooked": (base["crooked"][g], arm["crooked"].get(g, 0)),
                        "collateral": other,
                        "graded": next(r["graded"] for r in got[tag]["row"]
                                       if r["name"] == g)})
    if "--json" in argv:
        (HERE / "sighted.json").write_text(json.dumps(out, indent=1) + "\n")
        print(f"\n  wrote {HERE / 'sighted.json'}")
    return 0


# Which grammar each row was seated for - `ablate.py guests`' candidate sets,
# every one of which is a single grammar for these fourteen rows.
OWNER = {0: "scala", 1: "haskell", 2: "kotlin", 3: "swift", 4: "scala", 5: "ocaml",
         6: "elixir", 7: "julia", 8: "julia", 9: "php", 10: "latex", 11: "swift",
         12: "kotlin", 13: "elixir"}


def plan(argv: list[str]) -> int:
    named = seats() if CLEAN.is_dir() else {}
    for rows in PLAN:
        tag = tag_of(rows)
        at = BOARDS / f"{tag}.json"
        seat = " + ".join(named.get(r, f"row {r}") for r in rows) or "nothing removed"
        print(f"  {tag:<10}{'taken' if at.exists() else '—':<7}{seat[:88]}")
    return 0


def main(argv: list[str]) -> int:
    verb = argv[0] if argv else "plan"
    match verb:
        case "run":
            return run(argv[1:])
        case "score":
            return score(argv[1:])
        case "plan":
            return plan(argv[1:])
        case _:
            print(__doc__)
            return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

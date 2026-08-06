#!/usr/bin/env python3
"""One isolation arm per seating, so a collateral claim is answered per lane.

The union arm answers *did any of today's fourteen seatings reach a grammar
nobody seated* - and cannot answer *which* seating moved a grammar two of them
share. Nine grammars carry fourteen rows, so scala's layout row and scala's
comment row are indistinguishable in the union, and a seating that broke a
grammar another seating also touches would hide inside it.

So: fourteen arms, each today's tree with exactly one row deleted, each compared
to today's tree. Every arm is an isolation arm by the fifth house rule's own
definition, and the diff against the live tree is one file - checked, not
asserted, because an arm that took out a shared seam on the way past is the
failure `--mine` exists to name.

**And one arm per seating cannot see a pair.** Scala's standing depends on two
seatings at once: with either of its two rows ablated scala reads identically on
both trees to the byte, so both of its own isolation arms price a 12,733-byte
regression at zero. A grammar in that state has a next regression attributable
to neither of its rows, and nothing in the one-arm family can say so. (This was
written as the two rows *cooperating*. Sighted, each row alone costs ~100% of
scala's `square`, so it is a **ceiling** - the blindness is what a grammar
already on the floor looks like. `consort/RESULT-8-sighted.md`.)

The fix is not the powerset. Fourteen rows is 16,369 subsets of size >= 2 and
almost every one of them is incoherent: `seated()` refuses a cast unless the
grammar declares every terminal the row names, so a row can only ever change a
grammar in its **candidate set**, and `ablate.py guests` computes that from the
roster and the grammars' externals without building anything. The subsets worth
testing are the multi-row subsets *within one grammar's candidate set*, and on
today's roster that is five pairs.

Usage:  attribute.py <control-board.json> [row…]   one arm per seating
        attribute.py pairs [control-board.json]    every multi-row subset a
                                                   grammar's candidates admit,
                                                   priced against its singles
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import ablate  # noqa: E402
ROOT = HERE.parents[2]
SCRATCH = ROOT / ".local/aud-iso/outliner"
BASE = ROOT / ".local/aud-iso/base"
TARGET = "src/kernel/lex/outside.zig"


def sh(cmd: list[str], cwd: Path, **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, **kw)


def plan() -> list[str]:
    out = sh(["python3", str(HERE / "ablate.py"), "plan"], ROOT,
             env=os.environ | {"ABLATE_SRC": str(BASE / TARGET)}).stdout
    return [ln.split(None, 1)[1].split()[0] for ln in out.splitlines()
            if ln.startswith("  ") and ln.split()[0].isdigit()]


def board(binary: Path, work: Path, lane: str) -> dict:
    env = os.environ | {"OUTLINER_BIN": str(binary), "OUTLINER_WORK": str(work),
                        "OUTLINER_LANE": lane}
    got = subprocess.run(["python3", "tool/standing.py", "--json"], cwd=ROOT,
                         capture_output=True, text=True, env=env, check=True)
    return json.loads(got.stdout)


def by_name(d: dict) -> dict[str, dict]:
    return {r["name"]: r for r in d["row"]}


def moved(a: dict, b: dict) -> dict[str, tuple]:
    A, B = by_name(a), by_name(b)
    out = {}
    for g in sorted(A):
        if any(A[g][k] != B[g][k] for k in A[g] if k in B[g]):
            out[g] = (A[g].get("damage"), B[g].get("damage"),
                      A[g].get("standing"), B[g].get("standing"))
    return out


# The residual below which two rows are called additive. Bytes, not a ratio,
# because the question is whether a single-row arm would have *named* the
# regression, and a hundred bytes of drift in a twelve-thousand-byte defect
# would still have named it. Set before the numbers were taken.
SLACK = 1000


def arm(rows: tuple[int, ...], names: list[str], kept: Path) -> Path | None:
    """Build the isolation arm with exactly `rows` removed, and return its bytes.

    Reuses a pin that already exists, which is what makes the pair sweep cheap:
    the fourteen single-row arms are retained from the previous lane, so only the
    genuinely new subsets cost a build.
    """
    tag = "aud-r" + "-".join(str(r) for r in rows) if len(rows) > 1 else f"aud-r{rows[0]}"
    got = SCRATCH / f".local/pin/{tag}/bin/outliner"
    if got.exists():
        return got
    shutil.copy2(kept, SCRATCH / TARGET)
    sh(["python3", str(HERE / "ablate.py"), "write", str(SCRATCH / TARGET),
        ",".join(str(r) for r in rows)], ROOT,
       env=os.environ | {"ABLATE_SRC": str(kept)})
    # The `--mine` predicate taken rather than trusted, exactly as the one-row
    # family takes it: an arm that removed a shared seam on the way past is not
    # an isolation arm, whatever its name says.
    dirty = sh(["diff", "-rq", str(BASE / "src"), str(SCRATCH / "src")], ROOT).stdout.splitlines()
    if len(dirty) != 1 or TARGET.rsplit("/", 1)[1] not in dirty[0]:
        print(f"  {tag:<20}NOT AN ISOLATION ARM — {dirty}")
        return None
    built = sh(["python3", "tool/pin.py", "build", "--name", tag], SCRATCH)
    if built.returncode != 0:
        print(f"  {tag:<20}BUILD FAILED\n{built.stderr[-600:]}")
        return None
    return got


def damage(got: dict, g: str) -> tuple[int, float]:
    r = by_name(got).get(g, {})
    return r.get("damage", 0), r.get("standing", 0.0)


def subsets(members: list[int]) -> list[tuple[int, ...]]:
    """Every subset of size >= 2, smallest first. The population is a grammar's
    candidate rows and nothing else, which is what keeps this finite."""
    import itertools
    return [c for k in range(2, len(members) + 1)
            for c in itertools.combinations(sorted(members), k)]


def pairs(argv: list[str]) -> int:
    """Which grammars owe their standing to two or more rows *interacting*.

    `worth(r) = D({r}) - D(none)` is what a single-row arm says a row is worth,
    and `joint(S) = D(S) - D(none)` is what its rows are worth together. The
    residual between them is precisely the quantity no single-row arm can
    observe, and a grammar whose residual is large is a grammar whose next
    regression is attributable to neither of its rows.

    The **invisible** case is the one the brief names: every member's `worth` is
    zero and the joint is not. There the one-arm family does not merely
    mis-attribute, it reports the whole defect as nothing, twice.
    """
    kept = BASE / TARGET
    control = json.load(open(argv[0] if argv else ROOT / ".local/aud-iso/base-board.json"))
    text = kept.read_text()
    was = sh(["git", "show", "HEAD:src/kernel/lex/outside.zig"], ROOT).stdout
    seated = {ablate.key(was[a:b]) for a, b in ablate.rows(was)}
    cut = [(a, b) for a, b in ablate.rows(text) if ablate.key(text[a:b]) not in seated]
    seats = ablate.guests(text, cut)
    who: dict[str, list[int]] = {}
    for n, (_, _, reach) in enumerate(seats):
        for g in reach:
            who.setdefault(g, []).append(n)

    # The falsifier for the narrowing itself, and it has to run first: if a row
    # was measured to move a grammar it is not a candidate for, the candidate set
    # is not a bound and every subset below is the wrong population.
    try:
        ledger = json.load(open(HERE / "arms.json"))
    except OSError:
        ledger = []
    loose = [(a["row"], g) for a in ledger for g in a["moved"]
             if a["row"] not in who.get(g, ())]
    print(f"{len(seats)} row(s) · {len(who)} grammar(s) reachable · "
          f"{sum(len(r) > 1 for r in who.values())} reachable by more than one row")
    print(f"narrowing falsifier: {len(loose)} row(s) moved a grammar they cannot seat"
          f"{' — ' + str(loose) if loose else ' (the bound holds)'}\n")

    want = {g: r for g, r in sorted(who.items()) if len(r) > 1}
    print(f"{'grammar':<10}{'subset':<12}{'D(none)':>9}{'D(S)':>9}{'joint':>9}"
          f"{'sum solo':>10}{'residual':>10}  verdict")
    print("-" * 96)
    out: list[dict] = []
    for g, members in want.items():
        base, _ = damage(control, g)
        solo: dict[int, int] = {}
        for r in members:
            at = arm((r,), [], kept)
            if at is None:
                return 2
            solo[r] = damage(board(at, SCRATCH / f"work-r{r}", f"aud-r{r}"), g)[0] - base
        for S in subsets(members):
            at = arm(S, [], kept)
            if at is None:
                return 2
            tag = "+".join(str(r) for r in S)
            got, stand = damage(board(at, SCRATCH / f"work-s{tag}", f"aud-s{tag}"), g)
            joint, adds = got - base, sum(solo[r] for r in S)
            gap = joint - adds
            blind = all(solo[r] == 0 for r in S) and joint != 0
            verdict = ("INVISIBLE - every member reads zero alone" if blind else
                       "cooperating" if abs(gap) > SLACK else "additive")
            print(f"{g:<10}{tag:<12}{base:>9}{got:>9}{joint:>+9}{adds:>+10}{gap:>+10}"
                  f"  {verdict}")
            out.append({"grammar": g, "rows": list(S),
                        "seat": [seats[r][0] for r in S], "control": base,
                        "joint_damage": got, "standing": stand,
                        "solo": {str(r): solo[r] for r in S},
                        "joint": joint, "sum_solo": adds, "residual": gap,
                        "verdict": verdict})
    (HERE / "pairs.json").write_text(json.dumps(out, indent=1) + "\n")
    coop = [r for r in out if r["verdict"] != "additive"]
    print(f"\n{len(coop)} of {len(out)} subset(s) are not the sum of their parts."
          f" A single-row arm mis-attributes each of them by the residual column.")
    return 0


def main(argv: list[str]) -> int:
    if argv and argv[0] == "pairs":
        return pairs(argv[1:])
    if not argv:
        print(__doc__)
        return 2
    live = json.load(open(argv[0]))
    names = plan()
    want = [int(x) for x in argv[1:]] or range(len(names))
    kept = BASE / TARGET

    print(f"{len(names)} seating(s) · one arm each · against today's tree\n")
    ledger: list[dict] = []
    for n in want:
        shutil.copy2(kept, SCRATCH / TARGET)
        sh(["python3", str(HERE / "ablate.py"), "write", str(SCRATCH / TARGET), str(n)],
           ROOT, env=os.environ | {"ABLATE_SRC": str(BASE / TARGET)})
        # The `--mine` predicate, taken rather than trusted: this arm must differ
        # from the snapshot in the one file whose rows it removed. The comparand is
        # the snapshot and not the live tree, because a sibling landing between two
        # arms would otherwise fail an arm for a file the arm never touched - and
        # every arm of this family is priced against the same snapshot anyway.
        dirty = [ln for ln in sh(["diff", "-rq", str(BASE / "src"),
                                  str(SCRATCH / "src")], ROOT).stdout.splitlines()]
        if len(dirty) != 1 or TARGET.rsplit("/", 1)[1] not in dirty[0]:
            print(f"  {names[n]:<44}NOT AN ISOLATION ARM — {dirty}")
            continue
        built = sh(["python3", "tool/pin.py", "build", "--name", f"aud-r{n}"], SCRATCH)
        if built.returncode != 0:
            print(f"  {names[n]:<44}BUILD FAILED\n{built.stderr[-600:]}")
            continue
        bin_ = SCRATCH / f".local/pin/aud-r{n}/bin/outliner"
        got = moved(board(bin_, SCRATCH / f".local/work-r{n}", f"aud-r{n}"), live)
        said = "  ".join(f"{g} {d0}→{d1}" for g, (d0, d1, _, _) in got.items())
        print(f"  {names[n]:<44}{len(got)} grammar(s)   {said}")
        ledger.append({"row": n, "seat": names[n], "moved": {
            g: {"damage": [d0, d1], "standing": [s0, s1]}
            for g, (d0, d1, s0, s1) in got.items()}})
    (HERE / "arms.json").write_text(json.dumps(ledger, indent=1) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

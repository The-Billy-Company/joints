#!/usr/bin/env python3
"""Put the borrowing back, and watch exactly the right rows go red.

`borrow.py` names the defect and prints the number a repair has to produce.
This is the other half: it restores the *shipped* sample rule - the one that
drew `soft` from `askew + racked + unframed` and subtracted it from
`askew + racked` - and hands the board the cache that rule would have written.
A check that has never been seen to fail is a check nobody has tested.

The bug is restored in a **sibling work dir**, never in `tool/standing.py`. Ten
lanes share this tree and a two-minute window in which the board is wrong on
disk is a window somebody else measures in. The arm's folios are copied across,
so every digest matches and the board accepts the adverse verdicts as live.

It is a reproduction rather than an imitation, and that is asserted rather than
claimed: the adverse `crooked` and `soft` must equal, to the byte on every row,
what the shipped rule actually wrote before the repair. Point `BORROW_WAS` at a
kept pre-fix `audit.json` and the run refuses if any row disagrees.

    eval "$(python3 tool/pin.py arm <name>)"
    BORROW_WAS=.local/consort-borrow/audit-before.json \
    python3 research/joinery/consort/restore.py
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
# The copy happens BEFORE `plumb` and `standing` are imported, because both
# read `OUTLINER_WORK` at module load. An arm is its work dir; pointing the
# import at the adverse one is what makes this a whole second arm rather than
# a script writing into somebody's cache.
ARM = Path(os.environ["OUTLINER_WORK"]) if os.environ.get("OUTLINER_WORK") else None
if ARM is None:
    print("restore.py: no OUTLINER_WORK - arm first: eval \"$(python3 tool/pin.py arm X)\"",
          file=sys.stderr)
    raise SystemExit(2)
BENT = ARM.parent / f"{ARM.name}-borrowing"
BENT.mkdir(parents=True, exist_ok=True)
for got in ARM.iterdir():
    if got.is_file() and got.name != "audit.json":
        shutil.copy2(got, BENT / got.name)
os.environ["OUTLINER_WORK"] = str(BENT)

sys.path.insert(0, str(ROOT / "tool"))

import plumb  # noqa: E402
import rack  # noqa: E402
import standing  # noqa: E402


def bent(case) -> dict | None:
    """`standing.audit()` as it stood before the repair, provenance included.

    Verbatim except for one thing: the kinds are recorded. The shipped rule
    kept no provenance, which is precisely why nothing could see it - so the
    counterfactual this proves the check against is *the same sample rule with
    the field the repair added*, and not a weaker bug that would be easier to
    catch.
    """
    saw = plumb.read(case)
    if saw is None:
        return None
    folio, binary, source, oracle = standing.marks(case.name, case.source)
    if saw.why or not saw.built:
        return standing.Held(0, 0, 0, 0, saw.built, saw.why or "nothing built",
                             folio, binary, source, oracle)._asdict()
    seen = rack.survey(case.name, saw, top=1 << 20)
    was = standing.extras(case.name)
    drawn: dict[str, int] = {}
    for w in seen.worst:  # ...and no `if w.kind in CROOKED`. That is the defect.
        if not saw.blob[w.start:w.end].strip() or w.ours in was or w.theirs in was:
            drawn[w.kind] = drawn.get(w.kind, 0) + w.width
    soft = sum(drawn.values())
    return standing.Held(seen.square + seen.renamed, seen.crooked - soft, soft,
                         seen.unjudged + seen.unwindowed, saw.built, "",
                         folio, binary, source, oracle, seen.unframed,
                         standing.spent(drawn))._asdict()


def main() -> int:
    out = {}
    for case in plumb.slate():
        if (got := bent(case)) is not None:
            out[case.name] = got
    (BENT / "audit.json").write_text(json.dumps(out, indent=2))
    print(f"\nrestored the borrowing into {BENT} — {len(out)} verdict(s)")

    if (kept := os.environ.get("BORROW_WAS")):
        held = json.loads(Path(kept).read_text())
        off = [n for n in out if n in held and not out[n]["why"]
               and (out[n]["crooked"], out[n]["soft"])
               != (held[n]["crooked"], held[n]["soft"])]
        if off:
            print(f"  REFUSE — this is not the shipped rule: {', '.join(off)} disagree with"
                  f" {kept}", file=sys.stderr)
            return 2
        print(f"  and it is the shipped rule: `crooked` and `soft` match {kept} on"
              f" {len(held)} of {len(held)} rows")

    over = {n: sum(w for k, w in standing.paid(v["drawn"]).items()
                   if k not in standing.CROOKED) for n, v in out.items()}
    over = {n: w for n, w in over.items() if w}
    print(f"  {len(over)} row(s) overdraw: "
          + " · ".join(f"{n} {w}" for n, w in sorted(over.items(), key=lambda kv: -kv[1])))

    ran = subprocess.run([sys.executable, "tool/standing.py"], cwd=ROOT, text=True,
                         capture_output=True, env={**os.environ, "OUTLINER_WORK": str(BENT)})
    said = [ln for ln in ran.stdout.splitlines() if ln.startswith(("CHECK", "**BROKEN**"))]
    print("\nthe board, reading it:\n")
    for ln in said:
        print("  " + ln)
    red = [ln for ln in said if ln.startswith("**BROKEN**")]
    print(f"\n  {len(red)} of {len(said)} gate(s) red, {len(said) - len(red)} green")
    return 0 if red else 1


if __name__ == "__main__":
    raise SystemExit(main())

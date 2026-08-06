#!/usr/bin/env python3
"""Corrupt the audit four ways and require the board to say no to each.

`tool/standing.py` grew a column that subtracts 60,138 bytes from its own
headline on the strength of a **cached file it did not compute**. That is a new
trust edge on a board fourteen other gates already guard, and the honest
question about a new gate is not whether it is written but whether anybody has
watched it fail.

So each tampering below is a specific lie the cache could tell, applied to a
real `audit.json`, run through a real board, and required to produce a specific
refusal. The control is the same cache untouched: it must pass everything, or
the four failures prove only that the board dislikes being run.

    forged     one row's folio digest changed - a verdict from another
               generation, which is the hazard `SPLIT` exists for one level up.
               The row must go `stale`, and its crooked bytes must leave the
               headline rather than being quietly kept.
    inflated   `square` raised by 1,000 with `built` untouched - the four parts
               no longer total. The `splits built and does not redefine it`
               check must go BROKEN.
    laundered  every part moved into `square` and `crooked` zeroed on every
               row. The identity still holds, `trued` reads 100%, and only the
               anti-vacuity check can catch it. This is the tampering that
               looks most like good news, which is why it is here.
    swapped    `crooked` and `square` exchanged on the worst row. The identity
               STILL holds and the partition is still inhabited, so both audit
               checks pass - and the board is wrong by 25,394 bytes. The
               expected result is that nothing catches it, and that is the
               finding this file exists to state rather than hide.

All thirty rows. The first draft ran `--set=corpus` to be quick and forged
**php**, which `--set=corpus` does not contain - so the board correctly showed
no change, and the demonstration reported its own blind spot as the board's.
Two of five refusals failed for that reason and the numbers looked exactly like
a real defect. With the folios staged the whole board is about a second, so
there was never anything to buy.

    python3 research/joinery/flag/tamper.py

Exit 0 every refusal arrived, 1 one did not, 2 could not run.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WORK = Path(os.environ.get("OUTLINER_WORK", ROOT / ".local" / "standing"))
BOARD = ROOT / "tool" / "standing.py"


def stage(into: Path) -> Path:
    """A private folio cache with the real folios and a copy of the real audit.

    Hardlinked, so staging thirty folios is instant and a tampered run can
    never write into the cache ten other agents are reading. `os.link` falls
    back to a copy across a filesystem boundary rather than failing.
    """
    into.mkdir(parents=True, exist_ok=True)
    for folio in WORK.glob("*.folio"):
        try:
            os.link(folio, into / folio.name)
        except OSError:
            shutil.copy2(folio, into / folio.name)
    shutil.copy2(WORK / "audit.json", into / "audit.json")
    return into / "audit.json"


def board(work: Path) -> dict:
    got = subprocess.run(
        [sys.executable, str(BOARD), "--json"], capture_output=True, text=True,
        env={**os.environ, "OUTLINER_WORK": str(work)})
    try:
        return json.loads(got.stdout)
    except ValueError:
        return {"row": [], "check": [], "broke": got.stderr[-300:]}


def crooked(seen: dict) -> int:
    return sum(r["crooked"] for r in seen.get("row", ()))


def held(seen: dict) -> list[str]:
    return [c["said"] for c in seen.get("check", ()) if not c["held"]]


def graded(seen: dict, name: str) -> str:
    return next((r["graded"] for r in seen.get("row", ()) if r["name"] == name), "?")


def worst(book: dict) -> str:
    """The row carrying the most crooked bytes - what a forger would target."""
    return max(book, key=lambda k: book[k]["crooked"])


def forged(book: dict) -> tuple[dict, str]:
    who = worst(book)
    book[who]["folio"] = "0" * 16
    return book, who


def inflated(book: dict) -> tuple[dict, str]:
    who = worst(book)
    book[who]["square"] += 1000
    return book, who


def laundered(book: dict) -> tuple[dict, str]:
    for v in book.values():
        v["square"] = v["built"]
        v["crooked"] = v["soft"] = v["unaudited"] = 0
    return book, "every row"


def swapped(book: dict) -> tuple[dict, str]:
    who = worst(book)
    v = book[who]
    v["square"], v["crooked"] = v["crooked"], v["square"]
    return book, who


def main() -> int:
    if not (WORK / "audit.json").exists():
        print(f"tamper.py: no audit at {WORK / 'audit.json'};"
              f" run `python3 tool/standing.py --audit` first", file=sys.stderr)
        return 2
    out: list[tuple[bool, str]] = []
    with tempfile.TemporaryDirectory(prefix="tamper-") as tmp:
        pure = Path(tmp) / "clean"
        stage(pure)
        clean = board(pure)
        base, broke = crooked(clean), held(clean)
        out.append((not broke and base > 0,
                    f"CONTROL: the untampered cache passes every check and the board"
                    f" subtracts {base} crooked bytes"
                    + (f" — but {len(broke)} check(s) already fail: {broke}" if broke else "")))
        if not base:
            print("tamper.py: the control found no crooked bytes, so no tampering below"
                  " could be distinguished from it", file=sys.stderr)
            for ok, said in out:
                print(f"{'ok  ' if ok else 'FAIL':<6}{said}")
            return 1

        for name, bend, want in (("forged", forged, "stale"), ("inflated", inflated, ""),
                                 ("laundered", laundered, ""), ("swapped", swapped, "")):
            where = Path(tmp) / name
            path = stage(where)
            book, who = bend(json.loads(path.read_text()))
            path.write_text(json.dumps(book))
            seen = board(where)
            bad, now = held(seen), crooked(seen)
            if name == "forged":
                out.append((graded(seen, who) == want and now < base,
                            f"forged {who}'s folio digest → the row reads"
                            f" `{graded(seen, who)}` and the headline lost"
                            f" {base - now} crooked bytes rather than keeping a verdict"
                            f" from another generation"))
            elif name == "swapped":
                out.append((not bad, f"swapped {who}'s square and crooked → NOTHING caught it"
                                     f" ({len(bad)} check(s) fired), and the board now"
                                     f" subtracts {now} instead of {base}. Stated, not"
                                     f" hidden: the identity cannot see a permutation of"
                                     f" itself"))
            else:
                out.append((bool(bad), f"{name} {who} → {len(bad)} check(s) went BROKEN"
                                       + (f": {bad[0][:96]}" if bad else
                                          " — NOTHING CAUGHT IT")))
    for ok, said in out:
        print(f"{'ok  ' if ok else 'FAIL':<6}{said}")
    miss = sum(not ok for ok, _ in out)
    print(f"\n{len(out) - miss} of {len(out)} refusals arrived")
    return 1 if miss else 0


if __name__ == "__main__":
    raise SystemExit(main())

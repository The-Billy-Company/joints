#!/usr/bin/env python3
"""If the parse resumed at each wall instead of stopping, how much would it cover?

The census says 5 of 30 grammars whole and 6.1% of bytes reached, with eighteen
walled on an external scanner we cannot run. The instinct is to grind those
walls down one at a time, and the lex lane priced that path at 461 externals of
per-grammar spelling. So before anyone builds either thing, price the other one:
**recovery does not have to exist to be measured.**

The counterfactual is denial, the way ruby's wall was priced. Parse; when it
stops, skip the offending token and parse the rest as a fresh file; add up what
each pass reached. No parser change, no guessing.

## What kind of number this is

**An upper bound, and a generous one.** Three reasons, each inflating it:

1. A resumed pass starts in the *start state*, which admits far more than the
   stack state a real resynchronisation would resume in. Starting fresh is the
   most permissive resumption that exists.
2. It counts bytes a pass *reached*, not bytes it placed correctly. Resuming
   inside a block comment, the parser will happily read the prose as
   identifiers, and every one of those bytes counts here.
3. Skipping a single punctuation byte at a time gives the parser the most
   chances it could possibly get.

So read it as an order of magnitude, not a forecast. What would tighten it:
resuming in the real stack state rather than the start state, and scoring the
resumed nodes against tree-sitter instead of counting bytes. Both need the
feature to exist; this does not.

  python3 tool/resync.py               the table
  python3 tool/resync.py --json
  python3 tool/resync.py --set=corpus  or --set=breadth
  python3 tool/resync.py --cap=8000    hops one file may take before we call it
"""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import NamedTuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
import census as C  # noqa: E402
from rung1 import pairs  # noqa: E402
from stamp import ask as ask_one  # noqa: E402
from stamp import take  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / ".local" / "resync"
BIN = Path(os.environ.get("JOINTS_BIN", ROOT / "zig-out" / "bin" / "joints"))
CAP = 6000        # hops one file may take before the row is reported as a floor
PATIENCE = 60

WORD = set(b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")


class Row(NamedTuple):
    name: str
    set_: str
    size: int
    now: int          # bytes the single pass reaches today
    bound: int        # bytes every pass reaches together
    hops: int         # resumptions it took
    capped: bool      # ran out of hops, so `bound` is itself a floor
    note: str

    def as_dict(self) -> dict:
        return {**self._asdict(), "now_share": round(self.now / self.size, 4) if self.size else 0,
                "bound_share": round(self.bound / self.size, 4) if self.size else 0}


def folio(name: str) -> Path | None:
    """Press once per grammar, not once per hop. A `parse` given a grammar.json
    presses it first, which is 109 ms against 6 ms for a minted folio - and this
    walks a file in thousands of hops."""
    WORK.mkdir(parents=True, exist_ok=True)
    out = WORK / f"{name}.folio"
    if out.exists():
        return out
    got = subprocess.run([str(BIN), "mint", str(C.GRAMMARS / f"{name}.json"), "-o", str(out)],
                         capture_output=True, text=True, cwd=ROOT, timeout=PATIENCE)
    return out if got.returncode == 0 and out.exists() else None


def token(blob: bytes, at: int) -> int:
    """How far to skip to get past the thing that stopped us.

    A word is skipped whole, since resuming inside `return` would just stop
    again on `eturn`. Anything else is skipped one byte, which is the most
    generous choice available and therefore the right one for a bound.
    """
    if at >= len(blob):
        return 1
    if blob[at] in WORD:
        n = at
        while n < len(blob) and blob[n] in WORD:
            n += 1
        return n - at
    return 1


def walk(name: str, src: Path, set_: str, cap: int) -> Row:
    size = src.stat().st_size if src.exists() else 0
    if not size:
        return Row(name, set_, 0, 0, 0, 0, False, "no source fetched")
    blob = src.read_bytes()
    pressed = folio(name)
    if pressed is None:
        return Row(name, set_, size, 0, 0, 0, False, "grammar does not press")

    now = C.ask(name, src, set_).reach
    at, covered, hops = 0, 0, 0
    with tempfile.TemporaryDirectory() as tmp:
        rest = Path(tmp) / src.name
        while at < size and hops < cap:
            rest.write_bytes(blob[at:])
            # `tree=False`: a mended pass breaks out of the loop below without
            # ever reading its reach, so buying the forest would be a second
            # subprocess per hop across thousands of hops for a number nobody
            # looks at.
            end = ask_one(BIN, pressed, rest, size=size - at, tree=False,
                          patience=PATIENCE)
            if end.kind == "timeout":
                return Row(name, set_, size, now, covered, hops, True,
                           f"a pass ran past {PATIENCE}s")
            if end.kind in ("whole", "unclosed", "mended"):
                # Read to the end of what was left, however it ended. `mended`
                # belongs here now that the parse resynchronises on its own:
                # the counterfactual this file prices is a hop the parser used
                # to need a person for, and counting a self-mended pass as a
                # stop would price a feature that has already shipped.
                covered += size - at
                break
            got_to = end.reach
            covered += got_to
            at += got_to + token(blob, at + got_to)
            hops += 1
    capped = hops >= cap
    note = f"stopped counting at {cap} hops" if capped else ""
    return Row(name, set_, size, now, min(covered, size), hops, capped, note)


def table(rows: list[Row]) -> None:
    print(f"\n{'grammar':<19}{'set':<10}{'bytes':>8}{'today':>9}{'':>2}{'resynced':>9}{'':>2}"
          f"{'hops':>6}  gain")
    print("-" * 96)
    for r in rows:
        a = f"{r.now / r.size * 100:.1f}%" if r.size else "-"
        b = f"{r.bound / r.size * 100:.1f}%" if r.size else "-"
        gain = f"x{r.bound / r.now:.0f}" if r.now else ("from nothing" if r.bound else "-")
        print(f"{r.name:<19}{r.set_:<10}{r.size:>8}{a:>9}{'':>2}{b:>9}{'':>2}"
              f"{r.hops:>6}  {gain}{' ' + r.note if r.note else ''}")

    size = sum(r.size for r in rows)
    now = sum(r.now for r in rows)
    bound = sum(r.bound for r in rows)
    capped = [r for r in rows if r.capped]
    print(f"\n{len(rows)} grammars · {size:,} bytes")
    print(f"today      {now:>9,}  {now / size * 100:.1f}%")
    print(f"resynced  <{bound:>9,}  {bound / size * 100:.1f}%   upper bound; "
          f"{sum(r.hops for r in rows):,} resumptions")
    print(f"the bound is {bound / now:.1f}x today's coverage")
    if capped:
        print(f"{len(capped)} row(s) hit the hop cap, so their bound is itself a floor: "
              + ", ".join(r.name for r in capped))


def main(argv: list[str]) -> int:
    if "--help" in argv or "-h" in argv:
        print(__doc__)
        return 0
    want = next((a.split("=", 1)[1] for a in argv if a.startswith("--set=")), "all")
    cap = int(next((a.split("=", 1)[1] for a in argv if a.startswith("--cap=")), CAP))
    if want not in ("all", "corpus", "breadth"):
        print(f"resync.py: --set must be all, corpus or breadth, not {want!r}", file=sys.stderr)
        return 2
    if not BIN.exists():
        print(f"resync.py: no binary at {BIN}", file=sys.stderr)
        return 2
    mark = take(BIN)
    picked = []
    if want in ("all", "corpus"):
        picked += [(n, C.CORPUS / leaf, "corpus") for n, leaf in sorted(pairs())]
    if want in ("all", "breadth"):
        picked += [(p.name, C.B.source_of(p.name), "held-out")
                   for p in sorted(C.load("breadth"), key=lambda p: p.name)]
    rows = [walk(n, s, k, cap) for n, s, k in picked]
    if "--json" in argv:
        print(json.dumps({"stamp": mark.as_dict(), "cap": cap,
                          "row": [r.as_dict() for r in rows]}, indent=2))
        return 0
    table(rows)
    print(mark.line())
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

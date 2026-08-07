#!/usr/bin/env python3
"""Which half of reuse is failing, per grammar, on the same edits collate times.

`collate.py keystroke` reports one number per grammar - microseconds - and one
derived ratio, `gain`. That is enough to see that 17 grammars are not
incremental and not enough to say which of the two reuse halves is missing,
because both of them show up as time.

The report line `joints amend` prints already separates them, and nothing was
reading it that way:

    N lifts over B bytes    the suffix half. Subtrees taken out of the old tree
                            instead of re-derived. Zero means every token after
                            the edit was re-read.
    T tokens read           what this run moved over *in total*. Against the
                            open's own T, this is the prefix half: a resume
                            that stood up near the edit declines the tokens
                            before it, so T falls; one that began on the ground
                            reads them all and T does not move.

So `read/open_read` is the prefix half's score and `lifts` is the suffix half's,
and a grammar can fail either independently. `stop` is the third column and it
is not decoration: `graft.stoop` refuses every candidate unless the old tree has
exactly one root, and a parse has exactly one root exactly when it was
`accepted` - `crown` runs only under `won.ok and mends == 0`. So the verdict
printed on the previous line predicts whether the next line can lift at all.

Positions are collate's, imported rather than restated, so this and the
scoreboard are asking about the same keystrokes.

Exit 0 ran, 2 an error.
"""

from __future__ import annotations

import json
import os
import re
import statistics
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tool"))

from collate import keystrokes  # noqa: E402
from order import folio_for  # noqa: E402
from walls import roster  # noqa: E402

BIN = Path(os.environ.get("JOINTS_BIN", ROOT / "zig-out" / "bin" / "joints"))
WORK = Path(os.environ.get("JOINTS_WORK", ROOT / ".local" / "standing"))
GRAMMARS = ROOT / "upstream" / "grammars"
OUT = ROOT / ".local" / "keystroke"

# `joints: <path>: opened: accepted, 274/274 leaves reminted at 0, height 9,
#  0 lifts over 0 bytes, 274 tokens read, 900 us`
ROW = re.compile(
    r": (?P<what>opened|\d+\.\.\d+ \+\d+): (?P<verdict>.+?)"
    r"(?:, (?P<minted>\d+)/(?P<leaves>\d+) leaves reminted at (?P<at>\d+),"
    r" height (?P<height>\d+))?"
    r", (?P<lifts>\d+) lifts over (?P<skipped>\d+) bytes,"
    r" (?P<read>\d+) tokens read, (?P<us>\d+) us$"
)


class Beat(NamedTuple):
    verdict: str
    spun: bool  # the spine kept a tiling; false means it was dropped whole
    minted: int
    leaves: int
    lifts: int
    skipped: int
    read: int
    us: int


class Row(NamedTuple):
    name: str
    size: int
    accepted: bool  # the open parse, which is `roots == 1` and so the lift gate
    verdict: str
    open_us: int
    open_read: int
    edits: int
    us: int
    read: int
    lifts: int
    minted: int
    leaves: int
    spun: int  # edits that kept a tiling
    warm_accepted: int
    why: str = ""

    @property
    def gain(self) -> float:
        return self.open_us / self.us if self.us else 0.0

    @property
    def prefix(self) -> float:
        """Share of the open's tokens this edit still moved over. 1.0 is no
        prefix reuse at all; a resume just above the edit drives it toward the
        share of the file after the edit."""
        return self.read / self.open_read if self.open_read else 1.0


def beats(path: Path, folio: Path, src: Path, edits: list[int],
          policy: str | None = None) -> list[Beat]:
    argv = [str(BIN), "amend", str(folio), str(src), "--quiet"]
    if policy:
        argv.append(f"--policy={policy}")
    argv += [f"{p}..{p}=x" for p in edits]
    got = subprocess.run(argv, capture_output=True, text=True, cwd=ROOT)
    out = []
    for line in got.stderr.splitlines():
        if not (m := ROW.search(line)):
            continue
        out.append(Beat(
            verdict=m["verdict"], spun=m["minted"] is not None,
            minted=int(m["minted"] or 0), leaves=int(m["leaves"] or 0),
            lifts=int(m["lifts"]), skipped=int(m["skipped"]),
            read=int(m["read"]), us=int(m["us"]),
        ))
    if not out:
        raise RuntimeError(got.stderr.strip().splitlines()[-1] if got.stderr else "silent")
    del path
    return out


def probe(name: str, src: Path, want: int = 24, policy: str | None = None) -> Row:
    folio = folio_for(name, WORK)
    blob = src.read_bytes()
    at = keystrokes(blob, want)
    if not folio.exists():
        return blank(name, len(blob), "no folio")
    if not at:
        return blank(name, len(blob), "no identifier interior")
    live = [p + n for n, p in enumerate(at)]
    try:
        got = beats(folio, folio, src, live, policy)
    except RuntimeError as e:
        return blank(name, len(blob), str(e)[:70])
    head, rest = got[0], got[1:]
    if not rest:
        return blank(name, len(blob), "no edit measured")
    return Row(
        name=name, size=len(blob),
        accepted=head.verdict == "accepted", verdict=head.verdict,
        open_us=head.us, open_read=head.read, edits=len(rest),
        us=int(statistics.median(b.us for b in rest)),
        read=int(statistics.median(b.read for b in rest)),
        lifts=int(statistics.median(b.lifts for b in rest)),
        minted=int(statistics.median(b.minted for b in rest)),
        leaves=int(statistics.median(b.leaves for b in rest)),
        spun=sum(1 for b in rest if b.spun),
        warm_accepted=sum(1 for b in rest if b.verdict == "accepted"),
    )


def blank(name: str, size: int, why: str) -> Row:
    return Row(name, size, False, "", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, why)


def show(rows: list[Row]) -> None:
    print(f"\n  {'grammar':<12}{'bytes':>8} {'open':>4}  |{'open us':>8}{'per key':>9}"
          f"{'gain':>6}  |{'lifts':>6}{'read':>7}{'prefix':>7}  |{'spun':>5}{'ok':>4}")
    for r in rows:
        if r.why:
            print(f"  {r.name:<12}{r.size:>8,}       {r.why}")
            continue
        print(f"  {r.name:<12}{r.size:>8,} {'ok' if r.accepted else 'MEND':>4}  "
              f"|{r.open_us:>8,}{r.us:>9,}{r.gain:>5.0f}x  "
              f"|{r.lifts:>6}{r.read:>7,}{r.prefix:>6.2f}  "
              f"|{r.spun:>3}/{r.edits:<2}{r.warm_accepted:>4}")
    ok = [r for r in rows if not r.why]
    if not ok:
        return
    clean = [r for r in ok if r.accepted]
    mend = [r for r in ok if not r.accepted]
    print(f"\n  {len(clean)} grammars open cleanly (one root, lifts possible), "
          f"{len(mend)} mend")
    for label, group in (("clean", clean), ("mend ", mend)):
        if not group:
            continue
        print(f"  {label}: median gain {statistics.median(r.gain for r in group):.0f}x, "
              f"median lifts {statistics.median(r.lifts for r in group):.0f}, "
              f"median prefix {statistics.median(r.prefix for r in group):.2f}, "
              f"{sum(1 for r in group if r.gain < 1.5)} of {len(group)} at gain 1x")
    print("\n  lifts = subtrees taken from the old tree (suffix reuse)"
          "\n  prefix = tokens this edit moved over / tokens the open moved over"
          "\n           1.00 means the parse began on the ground and re-read everything")


def main(argv: list[str]) -> int:
    if not BIN.is_file():
        print(f"probe: no binary at {BIN}", file=sys.stderr)
        return 2
    want = [a for a in argv if not a.startswith("-")]
    policy = next((a.split("=", 1)[1] for a in argv if a.startswith("--policy=")), None)
    rows = [probe(n, p, policy=policy) for n, p in roster()
            if p.exists() and (not want or n in want)]
    show(rows)
    OUT.mkdir(parents=True, exist_ok=True)
    tag = f".{policy}" if policy else ""
    (OUT / f"probe{tag}.json").write_text(json.dumps(
        [{**r._asdict(), "gain": round(r.gain, 2), "prefix": round(r.prefix, 3)}
         for r in rows], indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        raise SystemExit(130)

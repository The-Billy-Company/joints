#!/usr/bin/env python3
"""Does the amended tree abide by a cold parse of the same bytes.

`rack --square` is the honest guard against a policy that buys speed with wrong
structure, and it is **blind to every change in this lane**: it measures the
cold open, and a cold open has no graft, so `graft.stoop` is never called. A
lift policy could hand back nonsense on every keystroke and `rack run` would
print the same five buckets it printed yesterday. Running it is not wrong, it
is vacuous, and reporting it as cover would be the twenty-ninth instrument.

The guard an incremental change actually needs compares the two derivations of
the *same bytes*: the one an amend arrived at through k edits, and the one a
cold parse of the edited file arrives at from nothing. Reuse is only ever an
optimization, so those two must be the same tree, element for element, at every
k - not just at the end, because a divergence the next edit happens to overwrite
is still a tree somebody's editor rendered.

Two things it deliberately does not do:

  * It does not shrink. A lane's shrinker was green while destructive, deleting
    a token while the failure still held and turning one defect into another
    that shared a state number. A disagreement here is reported at the k it
    happened, with the bytes on disk, and left alone.
  * It does not compare sha256 of anything. A folio's digest is not an oracle
    and neither is a binary's; this compares trees.

`--prove` is the demonstration that it can say no: it corrupts the amended tree
in memory - one character, after the parse, before the comparison - and the run
must fail. A guard that has never been seen to refuse is a guard nobody has
tested.

Exit 0 every tree abides, 1 one did not, 2 could not run.
"""

from __future__ import annotations

import os
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
SCRATCH = ROOT / ".local" / "keystroke" / "abide"


class Verdict(NamedTuple):
    name: str
    checked: int
    agreed: int
    first: str = ""  # the k and the shape of the first disagreement

    @property
    def ok(self) -> bool:
        return self.checked > 0 and self.agreed == self.checked


def trees(argv: list[str]) -> list[str]:
    """The s-expressions one invocation printed, one per root."""
    got = subprocess.run(argv, capture_output=True, text=True, cwd=ROOT)
    return [ln for ln in got.stdout.splitlines() if ln.startswith("(")]


def edited(blob: bytes, live: list[int]) -> bytes:
    """The bytes `amend` has after these edits, and the offsets must be the
    already-shifted ones it was handed.

    The first version of this took the unshifted list and applied it to a
    growing buffer, so from the second edit on the cold side inserted one byte
    too early and the two sides were parsing different files. It reported 27 of
    29 grammars diverging from a cold parse - a finding large enough to bury
    this lane's actual result, and entirely the instrument's.
    """
    for p in live:
        blob = blob[:p] + b"x" + blob[p:]
    return blob


def abide(name: str, src: Path, want: int = 24, spoil: bool = False) -> Verdict:
    folio = folio_for(name, WORK)
    blob = src.read_bytes()
    at = keystrokes(blob, want)
    if not folio.exists() or not at:
        return Verdict(name, 0, 0, "no folio" if not folio.exists() else "no interior")
    # collate's own rhythm: each insertion shifts the ones after it, so both
    # sides are handed the same already-shifted offsets.
    live = [p + n for n, p in enumerate(at)]
    SCRATCH.mkdir(parents=True, exist_ok=True)
    cold_at = SCRATCH / src.name

    agreed = 0
    first = ""
    for k in range(1, len(live) + 1):
        # No `--quiet`: it is the flag that withholds the tree, and the tree is
        # the entire question. The cost lines it also prints go to stderr and
        # are dropped, so this measures nothing and reads everything.
        warm = trees([str(BIN), "amend", str(folio), str(src),
                      *[f"{p}..{p}=x" for p in live[:k]]])
        if spoil and k == 1 and warm:
            # One character, after the parse, before the comparison. The parse
            # was correct; the guard must still refuse.
            warm[0] = warm[0].replace("(", "(_", 1)
        cold_at.write_bytes(edited(blob, live[:k]))
        cold = trees([str(BIN), "parse", str(folio), str(cold_at)])
        if warm == cold and warm:
            agreed += 1
        elif not first:
            first = why(k, warm, cold)
    return Verdict(name, len(live), agreed, first)


def why(k: int, warm: list[str], cold: list[str]) -> str:
    if not warm and not cold:
        return f"k={k} neither side printed a tree"
    if len(warm) != len(cold):
        return f"k={k} {len(warm)} roots amended, {len(cold)} cold"
    for i, (a, b) in enumerate(zip(warm, cold)):
        if a == b:
            continue
        n = next((j for j in range(min(len(a), len(b))) if a[j] != b[j]), min(len(a), len(b)))
        return f"k={k} root {i} diverges at char {n}: …{a[max(0, n - 30):n + 40]!r}"
    return f"k={k} equal lists compared unequal"  # unreachable, and says so


def main(argv: list[str]) -> int:
    if not BIN.is_file():
        print(f"abide: no binary at {BIN}", file=sys.stderr)
        return 2
    spoil = "--prove" in argv
    want = [a for a in argv if not a.startswith("-")]
    got = [abide(n, p, spoil=spoil) for n, p in roster()
           if p.exists() and (not want or n in want)]
    print(f"\n  {'grammar':<12}{'edits':>7}{'abide':>7}   first disagreement")
    for v in got:
        print(f"  {v.name:<12}{v.checked:>7}{v.agreed:>7}   {v.first}")
    bad = [v for v in got if not v.ok]
    ran = [v for v in got if v.checked]
    print(f"\n  {len(ran) - len(bad)} of {len(ran)} grammars: every amended tree "
          f"equals a cold parse of the same bytes")
    if spoil:
        print("  --prove corrupted one tree per grammar; a run that passes here is broken")
        return 0 if bad else 1
    return 1 if bad else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        raise SystemExit(130)

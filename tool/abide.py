"""Does a press change still abide by the hand verdicts?

`built`, `nodes` and `standing` are unions over spans, so they are blind to
which node covers a byte. A press change can keep every one of them steady and
still swap the structure underneath: verilog's `parameter` stopped building a
`parameter_declaration` and started lexing as a `simple_identifier`, over the
same bytes, and every headline column read flat. The one instrument that saw it
was `collate.py adjudicated`, which re-derives both trees and holds each hand
verdict to the two names it was judged against.

Nothing ran it on a press change. It found that regression because somebody
happened to ask, and a check that depends on somebody happening to ask is the
check that is not there the day it matters. So this is that check with a
trigger: any change under `src/press/` or `src/folio/` - the table and the
bytes it is written to - has to re-read every hand verdict before it lands.

    python3 tool/abide.py                 # the gate: what changed vs the base
    python3 tool/abide.py --base HEAD~3   # against some other base
    python3 tool/abide.py --all           # ask regardless of what changed

## Why here and not in CI

`collate.py adjudicated` needs the oracle, and `.github/workflows/ci.yml` says
in its own header that it installs no tree-sitter and never will. That is the
whole reason `sound.py` exists in the shape it does - it is the structural gate
that can run *without* an oracle. This one cannot, so it runs where the oracle
actually lives, on the machine making the change, in the same diff-scoped shape
`.githooks/pre-push` already uses for Markdown.

## Three answers, not two

Borrowed wholesale from `sound.py`, because the failure it warns about is the
one this gate is most exposed to. A press change with no oracle on the machine
must not read as a press change that was checked and found clean. If the paths
say ask and the oracle cannot answer, that is UNASKED and it fails - loudly,
naming what is missing - rather than passing on an absence.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# The table and the bytes it is written to. A change to either can move the
# structure a verdict names while every byte column holds still, which is
# exactly the class of regression the hand verdicts exist to catch.
WATCHED = ("src/press/", "src/folio/")


def changed(base: str) -> list[str]:
    """Paths this working tree changes relative to `base`, staged or not.

    Untracked files count. Up to ten agents cowork on one branch here, and a
    new `src/press/` file that has never been added is still a press change.
    """
    seen: set[str] = set()
    for cmd in (["git", "diff", "--name-only", base, "--"],
                ["git", "diff", "--name-only", "--cached", "--"],
                ["git", "ls-files", "--others", "--exclude-standard"]):
        got = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        if got.returncode == 0:
            seen.update(p for p in got.stdout.split("\n") if p)
    return sorted(p for p in seen if p.startswith(WATCHED))


def oracle() -> str | None:
    """What is missing before `adjudicated` can be asked, or None if nothing."""
    sys.path.insert(0, str(ROOT / "tool"))
    try:
        import differential as d  # noqa: PLC0415 - probing, not importing for use
    except ImportError as e:
        return f"tool/differential.py will not import ({e})"
    ts = Path(str(d.TS))
    if ts.name != str(d.TS) and not ts.exists():
        return f"no tree-sitter CLI at {ts}"
    got = subprocess.run([str(d.TS), "--version"], capture_output=True, text=True)
    if got.returncode != 0:
        return f"`{d.TS} --version` exits {got.returncode}"
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--base", default="HEAD", help="what to diff against")
    ap.add_argument("--all", action="store_true", help="ask regardless of the diff")
    args = ap.parse_args()

    touched = changed(args.base)
    if not touched and not args.all:
        print("abide: nothing under src/press/ or src/folio/ changed - not asked")
        return 0

    if args.all:
        print("abide: asked for the whole slate")
    else:
        print(f"abide: {len(touched)} press change(s) - the hand verdicts have to hold")
        for p in touched:
            print(f"  {p}")

    if missing := oracle():
        # The sound.py lesson, one level up: an oracle that cannot answer is
        # not an oracle that answered yes. A press change reaching here with no
        # way to re-read the trees is unchecked, and has to read as unchecked.
        print(f"\nabide: UNASKED - {missing}", file=sys.stderr)
        print("abide: a press change cannot land on a check that could not run",
              file=sys.stderr)
        return 1

    print()
    got = subprocess.run([sys.executable, "tool/collate.py", "adjudicated"], cwd=ROOT)
    if got.returncode != 0:
        # `show_verdicts` already prints grammar, span, bytes, both readings and
        # which way each side moved, one row per drifted verdict. Repeating any
        # of it here would give a reader two places to look and one of them
        # would go stale, so this only says what to do about it.
        print("\nabide: a hand verdict no longer describes the live trees.",
              file=sys.stderr)
        print("abide: the rows marked DRIFT above name the grammar, the span, "
              "its width, and which side moved which way.", file=sys.stderr)
        print("abide: re-read those bytes and re-judge the row - a re-capture "
              "is not a re-judgement. Do not edit verdicts.toml to go green.",
              file=sys.stderr)
        print("abide: drift a re-judgement cannot express - both sides at `—`, "
              "say - is recorded as a `[verdict.drifted]` note instead, and the "
              "row still counts toward nothing.", file=sys.stderr)
        return got.returncode
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

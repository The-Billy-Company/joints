#!/usr/bin/env python3
"""Does every test file actually run, and does production still not name one?

`zig build test` collects only the tests reachable from its root module's own
files. While `src/root.zig` was that root, the only way to reach a `*_test.zig`
was for production code to import it, so each area's module root imported its
own tests - and those tests then read downstream, because a parser generator is
only worth testing against the thing it generates for. That is what made
`folio -> press/press.zig -> press/docket/carry_test.zig -> folio` a real cycle
across five directories, over an arrow that was never in the program.

`src/proof.zig` is the repair: a test-only root that names every `*_test.zig` by
hand, so a test file is a leaf nothing production reaches. Hand-maintained means
it can be wrong in the one direction nobody notices. A new test file that no one
added to the roster does not run, and a suite that quietly shrank reads exactly
like a green run - the same hazard `build.zig` warns about where it explains why
the library gets its own compilation. This is that check.

Two invariants, because the roster is only half the repair:

    roster   every `src/**/*_test.zig` is named in `src/proof.zig`, and every
             name in the roster is a file that exists.
    one-way  no production file imports a `*_test.zig`. `charter.zone`
             no longer carries a variance for that cycle, so re-adding the arrow
             fails `zoning verify` a long way from the line that caused it, with
             a message about zones rather than about tests.

Exit 0 ran, 1 a clean negative answer (drift), 2 an error - the same family the
other tools here and the joints CLI use.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

SRC = Path(__file__).resolve().parent.parent / "src"
ROSTER = SRC / "proof.zig"
IMPORT = re.compile(r'@import\("([^"]+)"\)')


def present() -> set[str]:
    """Every test file on disk, spelled the way the roster would name it."""
    return {p.relative_to(SRC).as_posix() for p in SRC.rglob("*_test.zig")}


def named() -> set[str]:
    """Every test file the roster names. Non-test imports there are not our business."""
    found = IMPORT.findall(ROSTER.read_text(encoding="utf-8"))
    return {t for t in found if t.endswith("_test.zig")}


def stowaways() -> list[tuple[str, int, str]]:
    """Production files importing a test file - the arrow the untangle removed."""
    out: list[tuple[str, int, str]] = []
    for path in sorted(SRC.rglob("*.zig")):
        if path == ROSTER or path.name.endswith("_test.zig"):
            continue
        for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            for hit in IMPORT.finditer(line):
                if hit.group(1).endswith("_test.zig"):
                    out.append((path.relative_to(SRC).as_posix(), n, hit.group(1)))
    return out


def main(argv: list[str]) -> int:
    verb = argv[0] if argv else "verify"
    if verb not in ("verify", "list"):
        print(f"roll: unknown verb {verb!r} (verify | list)", file=sys.stderr)
        return 2
    if not ROSTER.is_file():
        print(f"roll: no test root at {ROSTER}", file=sys.stderr)
        return 2

    on_disk, in_roster = present(), named()
    if verb == "list":
        print("\n".join(sorted(in_roster)))
        return 0

    unrun, ghosts, arrows = sorted(on_disk - in_roster), sorted(in_roster - on_disk), stowaways()
    for t in unrun:
        print(f"roll: {t} exists and src/proof.zig does not name it, so it does not run")
    for t in ghosts:
        print(f"roll: src/proof.zig names {t}, which is not a file")
    for path, n, t in arrows:
        print(f"roll: {path}:{n} imports {t} - production may not name a test file")
    if unrun or ghosts or arrows:
        return 1

    print(f"roll: {len(in_roster)} test files, every one named, none named by production")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

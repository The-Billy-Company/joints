#!/usr/bin/env python3
"""Build one pin with a capacity constant moved, and put the tree back.

Ten agents share this working tree, so an arm that edits a constant has to hold
the edit for as short a time as it takes `zig build` to read it and has to put
the exact bytes back whatever happens - including a build that fails and a
keyboard interrupt. The edit window here is one `zig build`, the restore is in a
`finally`, and the original bytes are compared back on the way out.

    ./arm.py fz-fork src/kernel/quire/gather.zig \\
        'const crowd = 64;' 'const crowd = 512;' \\
        'const skeins = 512;' 'const skeins = 4096;'

Edits are OLD NEW pairs and each OLD must match exactly once - a substitution
that matched twice would move a constant the arm is not about. Prints the pin's
binary path.
"""

import pathlib
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[3]


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    name, rel, *edits = argv
    if len(edits) % 2:
        print("arm: edits come in OLD NEW pairs", file=sys.stderr)
        return 2
    path = ROOT / rel
    was = path.read_bytes()
    now = was
    for old, new in zip(edits[::2], edits[1::2]):
        o, n = old.encode(), new.encode()
        if now.count(o) != 1:
            print(f"arm: {old!r} matches {now.count(o)}x, need exactly 1", file=sys.stderr)
            return 2
        now = now.replace(o, n)
    if now == was:
        print("arm: no edit - the arm would be the control", file=sys.stderr)
        return 2

    # Distinct mtimes: two builds inside one second have collided with zig's
    # cache validation and failed with "file contents changed during update".
    time.sleep(1.1)
    try:
        path.write_bytes(now)
        r = subprocess.run(
            [sys.executable, "tool/pin.py", "build", "--name", name],
            cwd=ROOT, capture_output=True, text=True,
        )
    finally:
        # A sibling editing this file inside the window is the one case where
        # restoring is the wrong move: it would eat their work. Say so and
        # leave the tree alone rather than choosing for them.
        if path.read_bytes() != now:
            print("arm: a SIBLING wrote this file during the build - not restoring;"
                  f" put `{edits[0]}` back by hand if it is still there", file=sys.stderr)
            return 2
        path.write_bytes(was)
    if path.read_bytes() != was:
        print("arm: RESTORE FAILED - the tree is not as it was", file=sys.stderr)
        return 2
    if r.returncode != 0:
        sys.stderr.write(r.stdout + r.stderr)
        return r.returncode
    print(r.stdout.strip())
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

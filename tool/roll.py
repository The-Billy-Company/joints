#!/usr/bin/env python3
"""Does every hand-kept roster still describe the tree it was written against?

Two rosters in this package are lists of `@import` lines somebody maintains by
hand, and both can be wrong in the one direction nobody notices - too short. A
missing line does not fail anything; it removes something from what gets asked,
and a smaller question reads exactly like a green answer. This tool is the check
for both, because it is one question asked twice.

    src/proof.zig   which test files run
    src/idiom.zig   which files the lifecycle proof reads

The second one earned its place here. Five waves running ended with somebody
adding a line to `idiom.zig` by hand after the fact, and each of those lanes had
already run `zig build idiom` and been told 0 - not because the code was right
but because nothing had read it. The pin in that file cannot catch it either: a
count notices a type that MOVED and is structurally blind to an area that
ARRIVED. So the completeness of the roster wants asking against the tree, which
is a thing Zig cannot do at comptime and a directory walk can.

Does every test file actually run, and does production still not name one?

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

And one for the lifecycle roster:

    judged   every file that declares a self-freeing type is REACHED by
             `src/idiom.zig` - named there, or named by a file that imports it.

Reached and not named, because a facade is a legitimate way onto the roster and
in one case the only sensible one: `kernel/joint/joint.zig` is listed and the
four files behind it are not, so `joint.roster.Pool` and its siblings are judged
through the door rather than four times over. Demanding the leaf be named would
be demanding a type get judged twice, which breaks the count in that file. So the
question is whether the walk can get there, not whether somebody spelled it.

`surface/` is exempt and cannot not be: the CLI and the ABI are separate
compilations that reach the library through the module name `joints`, so no
import path from `src/idiom.zig` reaches them at all. Its one owner is
`parse.zig`, whose shape is checked by hand in that file's own docs.

Exit 0 ran, 1 a clean negative answer (drift), 2 an error - the same family the
other tools here and the joints CLI use.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

SRC = Path(__file__).resolve().parent.parent / "src"
ROSTER = SRC / "proof.zig"
IDIOM = SRC / "idiom.zig"
IMPORT = re.compile(r'@import\("([^"]+)"\)')
FREES = re.compile(r"^\s*pub fn deinit\b", re.MULTILINE)
# Reached through the module name `joints`, not through a path from src/idiom.zig.
EXEMPT = ("surface/",)


def imports(path: Path) -> set[Path]:
    """The `.zig` files `path` imports, resolved the way Zig resolves them."""
    found = IMPORT.findall(path.read_text(encoding="utf-8"))
    return {(path.parent / t).resolve() for t in found if t.endswith(".zig")}


def owners() -> set[Path]:
    """Every production file declaring a type that frees itself."""
    return {
        p.resolve()
        for p in SRC.rglob("*.zig")
        if not p.name.endswith("_test.zig")
        and not any(p.relative_to(SRC).as_posix().startswith(e) for e in EXEMPT)
        and FREES.search(p.read_text(encoding="utf-8"))
    }


def reached() -> set[Path]:
    """What the lifecycle roster can see: what it names, and what those import.

    One hop, because that is the shape of the walk it is checking - `area()`
    reads a listed module's decls and the decls of the types those publish, so a
    facade carries the files it re-exports and nothing carries a facade's
    facade.
    """
    named = {p for p in imports(IDIOM) if p.is_file()}
    return named | {q for p in named for q in imports(p) if q.is_file()}


def unjudged() -> list[str]:
    """Files that own memory and that the lifecycle proof never reads."""
    return sorted(p.relative_to(SRC).as_posix() for p in owners() - reached())


def phantoms() -> list[str]:
    """Names in the lifecycle roster that are not files."""
    return sorted(
        t
        for t in IMPORT.findall(IDIOM.read_text(encoding="utf-8"))
        if t.endswith(".zig") and not (SRC / t).is_file()
    )


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
    for who in (ROSTER, IDIOM):
        if not who.is_file():
            print(f"roll: no roster at {who}", file=sys.stderr)
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

    blind, gone = unjudged(), phantoms()
    for t in blind:
        print(
            f"roll: {t} declares a type that frees itself and src/idiom.zig cannot "
            "reach it, so the lifecycle proof passes without reading it"
        )
    for t in gone:
        print(f"roll: src/idiom.zig names {t}, which is not a file")
    if unrun or ghosts or arrows or blind or gone:
        return 1

    print(
        f"roll: {len(in_roster)} test files, every one named, none named by production; "
        f"{len(owners())} files own memory and the lifecycle proof reaches all of them"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

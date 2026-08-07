#!/usr/bin/env python3
"""Build a binary somewhere only you know about, and record which tree it is.

Ten agents share one `zig-out`. That is a race nobody notices losing: a sibling
running `zig build` while your before/after is half taken replaces the binary
under your feet, and the second half of the comparison measures a tree the
first half never saw. It has already happened twice in one afternoon - once
transiently breaking the tree mid-sweep, and once silently rebuilding the
*reference* arm with the lane's own fix in it, which turned a pre-fix binary
into a post-fix one and made a before/after read thirty-of-thirty for entirely
the wrong reason. The lane's own summary of it: in this tree, **a path is not a
version**.

`zig build -p <dir>` is the whole cure and has been available all along, so the
useful thing here is not the flag. It is that a prefix is still a *path*: point
at `.local/mine/bin/joints` a day later and nothing on disk can tell you what
it was built from. So a pin is a prefix **plus a record** - the digest of the
sources at build time, the commit, how dirty the tree was, and the sha256 of
the bytes that came out. That record is what makes it a version, and it is what
`stamp.py` reads so `DRIFT` can fire on a pinned binary at all. Without it
`stamp` guesses the source tree from the binary's path, finds no `build.zig`
above a private prefix, falls back to the repo, and compares the live tree
against itself - so the one binary you pinned *because* you expected the tree
to move underneath it is the one binary that could never report that it had.

  python3 tool/pin.py build                 build this tree into a pin of its own
  python3 tool/pin.py build --name before   ... and give it a name you'll recognise
  python3 tool/pin.py list                  every pin, newest first
  python3 tool/pin.py show before           one pin in full
  python3 tool/pin.py path before           just the binary, for JOINTS_BIN=$(...)
  python3 tool/pin.py arm before            binary + its own folio cache + its own
                                            oracle seat, as shell: eval "$(...)"
  python3 tool/pin.py oracle before         mint THIS arm's tree-sitter verdicts,
                                            so its `square` column is a number
  python3 tool/pin.py verify                every pin's bytes still hash to its record

A binary is only one third of what makes two numbers comparable. The folio
cache is derived from the binary and the oracle is the other parser in every
audited column, so `arm` hands out all three under one name - see its docstring
for what sharing either of the other two costs.

The third one had no way to be *handed over*, only named, and that is the hole
`oracle` closes. `square` - the only column on the board that is a claim about
agreement with another parser - is read from an `audit.json` inside
`JOINTS_WORK`, so the private cache that stops two arms contaminating each
other is also what leaves both of them with an empty oracle column reading `0`,
which is indistinguishable from thirty grammars agreeing perfectly. `arm` now
says which of the two it is, and `oracle` fixes it in one command.

Exit 0 ran, 1 a clean negative answer (no such pin, a pin that no longer holds
its own bytes), 2 an error. `--json` on the read verbs.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import still  # noqa: E402
from stamp import ROOT, digest, git, iso, survey  # noqa: E402

PINS = ROOT / ".local" / "pin"
RECORD = "pin.json"
BINARY = Path("bin") / "joints"


def home(name: str) -> Path:
    return PINS / name


def read(where: Path) -> dict | None:
    """A pin's record, or None if that directory is not one."""
    try:
        got = json.loads((where / RECORD).read_text())
    except (OSError, ValueError):
        return None
    return got if isinstance(got, dict) and "tree" in got else None


def every() -> list[tuple[str, dict]]:
    if not PINS.is_dir():
        return []
    found = [(p.name, r) for p in sorted(PINS.iterdir()) if p.is_dir()
             if (r := read(p)) is not None]
    return sorted(found, key=lambda kv: kv[1].get("built", 0), reverse=True)


def build(name: str | None, args: list[str]) -> int:
    """Install this tree into a prefix of its own, then write down what it was.

    The source survey is taken **after** the build rather than before. A build
    takes tens of seconds and a sibling can land inside one; surveying first
    would record the tree the build was asked for rather than the tree it may
    have read, and of the two possible lies that one is the flattering one. The
    honest failure mode is a pin that reports drift it does not have, which
    sends you to look; the other sends you nowhere.
    """
    now = survey(ROOT.resolve())
    # A pin nobody named is named for its tree, so two builds of one tree land
    # on one pin instead of accumulating identical copies.
    where = home(name or now.digest[:12])
    got = subprocess.run(
        ["zig", "build", "-p", str(where), *args], cwd=ROOT,
        capture_output=True, text=True)
    if got.returncode != 0:
        sys.stderr.write(got.stderr[-2000:])
        print(f"pin: build failed, {where} not written", file=sys.stderr)
        return 2
    binary = where / BINARY
    if not binary.is_file():
        print(f"pin: build succeeded but {binary} is not there", file=sys.stderr)
        return 2

    after = survey(ROOT.resolve())
    record = {
        "name": where.name,
        "tree": after.digest,
        "asked": now.digest,
        "newest": after.where,
        "touched": after.newest,
        "files": after.files,
        "build": digest(binary),
        "built": binary.stat().st_mtime,
        "commit": git("rev-parse", "HEAD") or "unknown",
        "dirty": sum(1 for ln in git("status", "--porcelain").splitlines() if ln.strip()),
        "flags": args,
        "root": str(ROOT.resolve()),
    }
    (where / RECORD).write_text(json.dumps(record, indent=2) + "\n")
    # ...and the same tree per FILE, beside it. `tree` says two pins differ and
    # cannot say in what, and on a tree ten lanes write to "the pins differ" is
    # true of every before/after all day. The one question a lane needs answered
    # is *which files*, because it knows which one it changed - a lane pinned a
    # baseline, worked eight minutes, pinned its arm, and read a latex win that
    # belonged to the lex lane. Only knowable while this tree is still the live
    # one, so it is recorded here rather than derived later.
    files = still.mark(where)

    print(f"pin: {where.name} · tree {after.digest[:12]}"
          f" · commit {record['commit'][:9]}+{record['dirty']}"
          f" · {record['build'][:12]} · {files} file(s) recorded")
    if now.digest != after.digest:
        # Not fatal and not rare with ten lanes running. It just has to be said,
        # because a pin taken across a moving tree is a pin of neither tree.
        print(f"pin: MOVED - {after.where} changed while this built; the pin"
              f" records the tree as it ended, not as it was asked for")
    print(f"export JOINTS_BIN={binary}")
    return 0


def resolve(name: str) -> tuple[Path, dict] | None:
    """A pin by name, or by any unambiguous prefix of one."""
    if (r := read(home(name))) is not None:
        return home(name), r
    hits = [(n, r) for n, r in every() if n.startswith(name)]
    return (home(hits[0][0]), hits[0][1]) if len(hits) == 1 else None


def show(name: str, as_json: bool) -> int:
    got = resolve(name)
    if got is None:
        print(f"pin: no pin named {name}", file=sys.stderr)
        return 1
    where, r = got
    live = survey(ROOT.resolve())
    moved = r["tree"] != live.digest
    if as_json:
        print(json.dumps({**r, "binary": str(where / BINARY), "live": live.digest,
                          "moved": moved}, indent=2))
        return 0
    print(f"  {r['name']}")
    print(f"    binary   {where / BINARY}")
    print(f"    bytes    {r['build'][:16]}")
    print(f"    tree     {r['tree'][:16]}  built {iso(r['built'])}")
    print(f"    live     {live.digest[:16]}  {'MOVED' if moved else 'same tree'}")
    print(f"    commit   {r['commit'][:12]}+{r['dirty']} · newest {r['newest']}")
    if r["flags"]:
        print(f"    flags    {' '.join(r['flags'])}")
    return 0


def listing(as_json: bool) -> int:
    found = every()
    if as_json:
        print(json.dumps([r for _, r in found], indent=2))
        return 0
    if not found:
        print(f"  no pins under {PINS}")
        return 0
    live = survey(ROOT.resolve()).digest
    print(f"\n  {len(found)} pin(s) under {PINS}\n")
    for name, r in found:
        print(f"  {name:<18}{r['tree'][:12]}  {iso(r['built'])}"
              f"  {r['commit'][:9]}+{r['dirty']}"
              f"  {'' if r['tree'] == live else 'MOVED'}")
    return 0


def verify(as_json: bool) -> int:
    """Does every pin still hold the bytes its record claims?

    A pin whose binary was replaced is worse than no pin: it is a path wearing
    a version's clothes, which is the exact failure this whole file exists to
    stop. So the record's own digest is checked rather than trusted, and a pin
    that fails this is a clean negative answer, not an error.
    """
    rows, bad = [], 0
    for name, r in every():
        binary = home(name) / BINARY
        now = digest(binary) if binary.is_file() else "missing"
        ok = now == r["build"]
        bad += not ok
        rows.append({"name": name, "ok": ok, "recorded": r["build"], "now": now})
    if as_json:
        print(json.dumps(rows, indent=2))
    else:
        for row in rows:
            print(f"  {row['name']:<18}{'holds' if row['ok'] else 'CHANGED'}"
                  f"  {row['recorded'][:12]} -> {row['now'][:12]}")
        print(f"\n  {len(rows) - bad} of {len(rows)} pin(s) still hold their bytes")
    return 1 if bad else 0


def where_is(name: str) -> int:
    """Just the path, for `JOINTS_BIN=$(python3 tool/pin.py path before)`."""
    got = resolve(name)
    if got is None:
        print(f"pin: no pin named {name}", file=sys.stderr)
        return 1
    print(got[0] / BINARY)
    return 0


def seat(where: Path) -> tuple[Path, dict[str, str]]:
    """One arm's three exports, as (work dir, environment)."""
    work = where / "work"
    work.mkdir(parents=True, exist_ok=True)
    return work, {"JOINTS_BIN": str(where / BINARY), "JOINTS_WORK": str(work),
                  "JOINTS_LANE": f"pin-{where.name}"}


def oracled(where: Path) -> tuple[int, int]:
    """How many of this pin's cached verdicts a board here would actually accept.

    The body moved to `still.live_verdicts`, which takes the `(work, binary)`
    pair every arm has rather than the pin layout only a pin has - because the
    witness needs the same answer and a witness is not always taken on a pin.
    A pin is the case where those two paths are derivable, so this is now the
    spelling of that derivation and nothing else.
    """
    return still.live_verdicts(where / "work", where / BINARY)


def oracle(name: str) -> int:
    """Mint this arm's own oracle verdicts, inside this arm's own environment.

    An arm is three things and the third one had no way to be handed over. A
    lane that armed correctly got a private folio cache, which is what makes two
    arms incapable of contaminating each other - and the oracle overlay lives in
    that same directory, so arming perfectly is what drops `square` and `crooked`
    to zero on every row. Zero is also what a board prints when thirty grammars
    agree, so nothing warned: nineteen controlled comparisons were read as a
    no-collateral clearance off an empty column.

    Seeding a neighbour's `audit.json` in here is not the fix and the machinery
    already says so: a verdict carries the folio, binary, source and oracle it
    was computed under, and two arms differ in the binary by construction, so a
    copied cache reads `stale` on all thirty rows. The verdicts have to be
    *minted* per arm, so the useful thing is to make minting them one command
    instead of three exports somebody has to remember in the right shell.

    Costs what the sweep costs - tree-sitter generated and run per grammar,
    minutes not seconds - which is why it is a verb and not something `arm` does
    on its own.
    """
    got = resolve(name)
    if got is None:
        print(f"pin: no pin named {name}", file=sys.stderr)
        return 1
    where, _ = got
    work, env = seat(where)
    live, held = oracled(where)
    if live:
        print(f"pin: {where.name} already carries {live} live verdict(s) in {work};"
              f" re-minting over them", file=sys.stderr)
    ran = subprocess.run(
        [sys.executable, str(Path(__file__).resolve().parent / "standing.py"), "--audit",
         "--json"], cwd=ROOT, env={**os.environ, **env},
        capture_output=True, text=True)
    sys.stderr.write("".join(ln + "\n" for ln in ran.stderr.splitlines()[-4:]))
    live, held = oracled(where)
    print(f"pin: {where.name} · {live} of {held} verdict(s) live for this arm"
          f" · {work / 'audit.json'}")
    # A sweep that wrote thirty verdicts none of which this arm can read is the
    # exact failure this verb exists to end, so it is a clean negative answer
    # rather than a success with a sad number in it.
    return 0 if live else 1


def arm(name: str) -> int:
    """Everything one arm of a before/after needs, as shell you can `eval`.

    `path` hands back a binary and leaves the other two thirds of a measurement
    to the caller's memory, which is how the two halves of a comparison came to
    share a folio cache. A folio is a **derived artifact of a binary**, so a pin
    owning a binary should own the cache it presses into; an oracle seat is the
    other parser in every audited number, so it should be named too, and named
    after the arm rather than after whichever shell's pid happened to run it.

    Three exports, because the three of them are one decision:

        eval "$(python3 tool/pin.py arm before)"

      JOINTS_BIN    this pin's binary - a version, not a path
      JOINTS_WORK   .../work beside it, so `order.py` presses into a directory
                      only this arm writes. The ticket rule below `press` makes
                      a shared one *fail closed* rather than lie, but failing
                      closed still costs a re-mint of thirty folios per
                      alternating run; a private one costs nothing and cannot
                      raise the question.
      JOINTS_LANE   this pin's oracle seat, so `--audit` under two arms is two
                      seats and neither is keyed on a parent process id.

    Printed rather than exported, because a tool cannot set a variable in the
    shell that ran it, and a tool that pretends it can is worse than one that
    hands you the line.

    **And it says whether the arm can see the oracle**, because the second
    export is what blinds it. `JOINTS_WORK` is where the `audit.json` behind
    `square` and `crooked` lives, so a fresh arm has no verdicts, prints `0` in
    both columns, and `0` is what perfect agreement looks like too. Nineteen
    controlled comparisons were read as a clearance off that. The line is on
    stderr with the rest of the commentary, so `eval` is unaffected and a lane
    that pipes this somewhere gets the same three exports it always did.
    """
    got = resolve(name)
    if got is None:
        print(f"pin: no pin named {name}", file=sys.stderr)
        return 1
    where, _ = got
    work, env = seat(where)
    for key, value in env.items():
        print(f"export {key}={value}")
    live, held = oracled(where)
    print(f"# arm '{name}' — binary, its own folio cache, its own oracle seat."
          f"\n# `eval \"$(python3 tool/pin.py arm {name})\"`, then measure.", file=sys.stderr)
    if live:
        print(f"# oracle: {live} of {held} verdict(s) live here — `square` is a"
              " measurement on this arm.", file=sys.stderr)
    else:
        print(f"# oracle: NONE{f' ({held} cached verdict(s), none live)' if held else ''}"
              " — every `square`/`crooked` column off this arm will read 0, and"
              "\n#         a comparison against it is not a claim about agreement"
              " with tree-sitter."
              f"\n#         Mint one: python3 tool/pin.py oracle {name}", file=sys.stderr)
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="verb")
    mk = sub.add_parser("build", help="build this tree into a pin of its own")
    mk.add_argument("--name", help="what to call it (default: the tree digest)")
    mk.add_argument("flags", nargs="*", help="passed to `zig build` after -p")
    for verb, helped in (("list", "every pin"), ("verify", "every pin's bytes")):
        sub.add_parser(verb, help=helped).add_argument("--json", action="store_true")
    one = sub.add_parser("show", help="one pin in full")
    one.add_argument("name")
    one.add_argument("--json", action="store_true")
    sub.add_parser("path", help="one pin's binary path").add_argument("name")
    sub.add_parser("arm", help="shell exports for one arm of a comparison").add_argument("name")
    sub.add_parser("oracle", help="mint this arm's own tree-sitter verdicts").add_argument("name")
    args = ap.parse_args(argv)

    PINS.mkdir(parents=True, exist_ok=True)
    match args.verb:
        case "build":
            return build(args.name, args.flags)
        case "show":
            return show(args.name, args.json)
        case "path":
            return where_is(args.name)
        case "arm":
            return arm(args.name)
        case "oracle":
            return oracle(args.name)
        case "verify":
            return verify(args.json)
        case _:
            return listing(getattr(args, "json", False))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Turn `grammars.toml` back into files, and say whether the files still match.

`upstream/` is gitignored on purpose, so the grammars every measurement runs
over are pinned rather than committed: a repo, a commit, a path, and the sha256
of the exact bytes. This is the only thing that resolves a pin into a file, and
the only thing that answers "are these still the bytes the dossier was written
against". `verify` and `status` never touch the network; only `fetch` does.

Exit 0 ran, 1 a clean negative answer (something missing or drifted), 2 an
error. That is the same family the outliner CLI uses, so a shell script can
treat both the same way.
"""

from __future__ import annotations

import hashlib
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, NamedTuple

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "grammars.toml"
DEST = ROOT / "upstream" / "grammars"
RAW = "https://raw.githubusercontent.com/{0.repo}/{0.commit}/{0.path}"

USAGE = """\
grammars.py - resolve and check the pinned tree-sitter grammars

usage:
  grammars.py fetch     populate upstream/grammars/ from grammars.toml
  grammars.py verify    hash what is on disk against the manifest (offline)
  grammars.py status    every pin and its state, in one glance (offline)
  grammars.py list      the manifest as a table

flags:
  --json          machine output, on the read verbs
  --dest=DIR      write to / read from DIR instead of upstream/grammars
"""


class Pin(NamedTuple):
    name: str
    repo: str
    commit: str
    path: str
    sha256: str
    size: int
    date: str
    note: str
    fixture: str

    @property
    def reproducible(self) -> bool:
        """Whether an upstream commit is known to produce these bytes. A pin
        that only carries a hash still checks a file on disk, but `fetch` has
        no URL to ask for, so it refuses instead of guessing one."""
        return len(self.commit) == 40 and all(c in "0123456789abcdef" for c in self.commit)

    @property
    def url(self) -> str:
        return RAW.format(self)


class Copy(NamedTuple):
    """A pinned grammar that also exists as a committed file.

    `build.zig` embeds one grammar into the test module, and a build graph that
    reads a gitignored path cannot be resolved from a clean checkout at all - so
    that one is committed at `test/grammar/json.json`. Hashing it against the pin
    it was taken from is the only thing that stops the committed copy and the
    manifest from quietly describing different bytes.
    """

    pin: Pin
    path: Path
    state: str  # ok · missing · drifted
    got: str

    def as_dict(self) -> dict[str, Any]:
        return {"name": self.pin.name, "path": self.pin.fixture, "state": self.state,
                "want": self.pin.sha256, "got": self.got}


class Row(NamedTuple):
    pin: Pin
    state: str  # ok · missing · drifted · unpinned
    got: str  # the sha256 on disk, empty when the file is not there

    def as_dict(self) -> dict[str, Any]:
        d = {"state": self.state, "got": self.got, **self.pin._asdict()}
        return {k: v for k, v in d.items() if v != ""}


def load(manifest: Path = MANIFEST) -> list[Pin]:
    doc = _toml(manifest.read_text(encoding="utf-8"))
    pins = []
    slack = {"note", "fixture"}  # the optional fields, so the rest are required
    for i, row in enumerate(doc.get("grammar", []), 1):
        if missing := set(Pin._fields) - slack - row.keys():
            raise ValueError(f"[[grammar]] #{i} is missing {', '.join(sorted(missing))}")
        if unknown := row.keys() - set(Pin._fields):
            raise ValueError(f"[[grammar]] #{i} has no such field {', '.join(sorted(unknown))}")
        pins.append(
            Pin(
                **{k: row.get(k, "") for k in slack},
                **{k: row[k] for k in Pin._fields if k not in slack},
            )
        )
    if not pins:
        raise ValueError("no [[grammar]] tables")
    return pins


def _toml(text: str) -> dict[str, Any]:
    try:
        import tomllib
    except ModuleNotFoundError:
        return _subset(text)
    return tomllib.loads(text)


def _subset(text: str) -> dict[str, Any]:
    """A closed reader for this one file's shape, because `tomllib` landed in
    3.11 and the python a bare macOS ships is 3.9.6. Nobody should need a newer
    interpreter to check a hash. It raises on anything outside `[[grammar]]`
    plus `key = "string"` / `key = 123`, so it cannot quietly disagree with
    tomllib about a file it accepted - it either reads it the same way or
    refuses it.
    """
    rows: list[dict[str, Any]] = []
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line == "[[grammar]]":
            rows.append({})
            continue
        key, sep, rest = line.partition("=")
        if not sep or not rows:
            raise ValueError(f"line {n}: {line!r} is outside this reader's subset")
        key, rest = key.strip(), rest.strip()
        if rest.startswith('"'):
            end = rest.find('"', 1)
            if end < 0:
                raise ValueError(f"line {n}: unterminated string")
            rows[-1][key] = rest[1:end]
        else:
            rows[-1][key] = int(rest.split("#", 1)[0].strip())
    return {"grammar": rows}


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def survey(pins: list[Pin], dest: Path) -> list[Row]:
    rows = []
    for pin in pins:
        f = dest / f"{pin.name}.json"
        if not f.exists():
            rows.append(Row(pin, "missing" if pin.reproducible else "unpinned", ""))
            continue
        got = digest(f)
        rows.append(Row(pin, "ok" if got == pin.sha256 else "drifted", got))
    return rows


def copies(pins: list[Pin]) -> list[Copy]:
    """Always repo-relative, never under `--dest`: a committed file is a fact
    about this checkout, not about wherever you happen to be fetching to."""
    out = []
    for pin in (p for p in pins if p.fixture):
        f = ROOT / pin.fixture
        got = digest(f) if f.exists() else ""
        out.append(Copy(pin, f, "missing" if not got else "ok" if got == pin.sha256 else "drifted", got))
    return out


def fetch(pins: list[Pin], dest: Path) -> int:
    dest.mkdir(parents=True, exist_ok=True)
    bad = 0
    for row in survey(pins, dest):
        pin, target = row.pin, dest / f"{row.pin.name}.json"
        if row.state == "ok":
            print(f"  have {pin.name:<11} {pin.sha256[:16]}")
            continue
        if row.state == "drifted":
            # Somebody edited this, or an older pin left it behind. Either way
            # it is news, and clobbering it would be the one outcome that
            # destroys the evidence of what happened.
            print(f" DRIFT {pin.name:<11} on disk {row.got[:16]}, pinned {pin.sha256[:16]}")
            print(f"       refusing to overwrite; delete {target} and re-run to take the pin")
            bad += 1
            continue
        if row.state == "unpinned":
            print(f"  skip {pin.name:<11} hash-only pin, no commit to fetch: {pin.note or 'no note'}")
            bad += 1
            continue
        try:
            with urllib.request.urlopen(pin.url, timeout=60) as r:  # noqa: S310 - https literal
                blob = r.read()
        except (urllib.error.URLError, OSError) as e:
            return oops(f"{pin.name}: {pin.url}: {e}")
        got = hashlib.sha256(blob).hexdigest()
        if got != pin.sha256:
            return oops(
                f"{pin.name}: upstream gave {len(blob)} bytes hashing {got}, "
                f"manifest pins {pin.sha256}\n  {pin.url}\n"
                "  nothing written. Either the pin is wrong or the bytes moved under it."
            )
        # Through a sibling then rename, so a reader in another process never
        # sees a half-written grammar - four of them read this directory while
        # a sweep runs.
        part = target.with_suffix(".json.part")
        part.write_bytes(blob)
        part.replace(target)
        print(f" wrote {pin.name:<11} {got[:16]} {len(blob)} bytes")
    return 1 if bad else 0


def report(pins: list[Pin], dest: Path, as_json: bool, terse: bool) -> int:
    rows, kept = survey(pins, dest), copies(pins)
    tally = {s: sum(r.state == s for r in rows) for s in ("ok", "missing", "drifted", "unpinned")}
    bad = len(rows) - tally["ok"] + sum(c.state != "ok" for c in kept)
    if as_json:
        print(json.dumps({
            "dest": str(dest), **tally,
            "grammar": [r.as_dict() for r in rows],
            "fixture": [c.as_dict() for c in kept],
        }, indent=2))
        return 1 if bad else 0
    for r in rows:
        if terse and r.state == "ok":
            continue
        mark = {"ok": "  ok", "missing": "  --", "drifted": "  !!", "unpinned": "  ??"}[r.state]
        detail = {
            "ok": r.got[:16],
            "missing": "not fetched",
            "drifted": f"on disk {r.got[:16]}, pinned {r.pin.sha256[:16]}",
            "unpinned": f"hash-only pin: {r.pin.note or 'no note'}",
        }[r.state]
        print(f"{mark} {r.pin.name:<11} {detail}")
    for c in kept:
        if c.state == "drifted":
            print(f"  !! {c.pin.fixture} no longer holds the bytes {MANIFEST.name} pins for {c.pin.name}")
            print(f"     {c.pin.fixture}: {c.got}")
            print(f"     {MANIFEST.name} [[grammar]] {c.pin.name}: {c.pin.sha256}")
            print(f"     one of the two is wrong; the pin is verified against {c.pin.repo}")
        elif c.state == "missing":
            print(f"  -- {c.pin.fixture} is gone, and build.zig embeds it - restore it from the {c.pin.name} pin")
        elif not terse:
            print(f"  ok {c.pin.fixture:<11} committed copy of the {c.pin.name} pin")
    verdict = ", ".join(f"{n} {s}" for s, n in tally.items() if n)
    where = dest.relative_to(ROOT) if dest.is_relative_to(ROOT) else dest
    held = sum(c.state == "ok" for c in kept)
    print(f"{len(rows)} pinned in {where}: {verdict}" + (f" · {held}/{len(kept)} committed copies ok" if kept else ""))
    if bad:
        # After the rows, and only after flushing them: a hint that lands above
        # the evidence it is a hint about reads like the first thing that went
        # wrong, and stdout is block-buffered into a log while stderr is not.
        # And only about the pins, since no fetch repairs a committed file.
        sys.stdout.flush()
        if len(rows) - tally["ok"]:
            print("run `python3 tool/grammars.py fetch` to resolve the pins", file=sys.stderr)
    return 1 if bad else 0


def inventory(pins: list[Pin], as_json: bool) -> int:
    if as_json:
        print(json.dumps({"grammar": [p._asdict() for p in pins]}, indent=2))
        return 0
    print(f"{'name':<11} {'bytes':>7}  {'date':<10} {'sha256':<16} {'commit':<48} path")
    for p in pins:
        where = f"{p.repo}@{p.commit[:12]}" if p.reproducible else f"{p.repo} (hash only)"
        print(f"{p.name:<11} {p.size:>7}  {p.date:<10} {p.sha256[:16]} {where:<48} {p.path}")
    return 0


def oops(msg: str) -> int:
    print(f"grammars.py: {msg}", file=sys.stderr)
    return 2


def main(argv: list[str]) -> int:
    dest, as_json, verb = DEST, False, ""
    for a in argv:
        if a == "--json":
            as_json = True
        elif a.startswith("--dest="):
            dest = Path(a.split("=", 1)[1]).expanduser()
        elif a in ("-h", "--help"):
            print(USAGE)
            return 0
        elif a.startswith("-"):
            return oops(f"unknown flag {a}\n\n{USAGE}")
        elif verb:
            return oops(f"one verb at a time, got {verb} and then {a}")
        else:
            verb = a
    if not verb:
        print(USAGE, file=sys.stderr)
        return 2
    try:
        pins = load()
    except (OSError, ValueError) as e:
        return oops(f"{MANIFEST}: {e}")
    if verb == "list":
        return inventory(pins, as_json)
    if verb in ("verify", "status"):
        return report(pins, dest, as_json, terse=verb == "verify")
    if verb == "fetch":
        return oops("fetch writes files; --json is for the read verbs") if as_json else fetch(pins, dest)
    return oops(f"no such verb {verb!r}\n\n{USAGE}")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

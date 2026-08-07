#!/usr/bin/env python3
"""Turn `grammars.toml` back into files, and say whether the files still match.

`upstream/` is gitignored on purpose, so the grammars every measurement runs
over are pinned rather than committed: a repo, a commit, a path, and the sha256
of the exact bytes. This is the only thing that resolves a pin into a file, and
the only thing that answers "are these still the bytes the dossier was written
against". `verify` and `status` never touch the network; only `fetch` and `pin`
do.

The file holds two sets now, and `set` is what tells them apart. `load()`
defaults to the dossier eleven because that is what "the grammars" has meant to
every caller since this file existed, and a held-out set that silently widened
what `differential.py` sweeps would be a held-out set that changed the thing it
was measuring. Ask for the other one by name.

Exit 0 ran, 1 a clean negative answer (something missing or drifted), 2 an
error. That is the same family the joints CLI uses, so a shell script can
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
API = "https://api.github.com/repos/{0}"
DOSSIER = "dossier"  # the eleven; what a pin means when it does not say

USAGE = """\
grammars.py - resolve and check the pinned tree-sitter grammars

usage:
  grammars.py fetch     populate upstream/grammars/ from grammars.toml
  grammars.py verify    hash what is on disk against the manifest (offline)
  grammars.py status    every pin and its state, in one glance (offline)
  grammars.py list      the manifest as a table
  grammars.py pin SPEC  mint a [[grammar]] from upstream HEAD, checked twice

flags:
  --json          machine output, on the read verbs
  --dest=DIR      write to / read from DIR instead of upstream/grammars
  --set=NAME      only this set; `all` for every pin (read verbs default to all)

a pin SPEC is `name=owner/repo` or `name=owner/repo:path/to/grammar.json`.
Without a path it searches the tree and refuses when a repo holds more than one
grammar, since a multi-dialect repo has to be told which dialect you meant.
"""


class Companion(NamedTuple):
    """A second file the grammar needs, pinned exactly as hard as the first.

    A `grammar.json` is not always the whole pin. ocaml and php are monorepo
    grammars whose `scanner.c` is a 27- and a 17-line shim over a
    `common/scanner.h` that lives one or two directories up, outside the
    grammar's own tree - so a pin naming one path cannot describe the bytes
    anyone needs to read. `path` is relative to the **repository root**, the
    same frame `Pin.path` uses, which is the only frame under which two
    grammars in the same monorepo cannot collide.
    """

    path: str
    sha256: str
    size: int
    note: str

    @property
    def leaf(self) -> str:
        return self.path.rsplit("/", 1)[-1]


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
    set: str
    companion: tuple[Companion, ...] = ()

    @property
    def reproducible(self) -> bool:
        """Whether an upstream commit is known to produce these bytes. A pin
        that only carries a hash still checks a file on disk, but `fetch` has
        no URL to ask for, so it refuses instead of guessing one."""
        return len(self.commit) == 40 and all(c in "0123456789abcdef" for c in self.commit)

    @property
    def url(self) -> str:
        return RAW.format(self)

    def url_of(self, path: str) -> str:
        """The raw URL of any repo-relative path at this pin's commit. A
        companion resolves through here rather than by gluing `../..` onto the
        grammar's own URL, which is how two monorepo grammars ended up writing
        different bytes to one `common/scanner.h`."""
        return RAW.format(self)[: -len(self.path)] + path


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


def load(which: str = DOSSIER, manifest: Path = MANIFEST) -> list[Pin]:
    """The pins in one set, `all` for every one of them.

    The default is the dossier eleven rather than everything, because every
    existing caller wrote `load()` when eleven was all there was, and the
    held-out set exists to be measured against them rather than folded in.
    """
    doc = _toml(manifest.read_text(encoding="utf-8"))
    pins = []
    # The optional fields, so the rest are required.
    slack = {"note", "fixture", "set", "companion"}
    for i, row in enumerate(doc.get("grammar", []), 1):
        if missing := set(Pin._fields) - slack - row.keys():
            raise ValueError(f"[[grammar]] #{i} is missing {', '.join(sorted(missing))}")
        if unknown := row.keys() - set(Pin._fields):
            raise ValueError(f"[[grammar]] #{i} has no such field {', '.join(sorted(unknown))}")
        pins.append(
            Pin(
                **{k: row.get(k, "") for k in slack - {"set", "companion"}},
                set=row.get("set", DOSSIER),
                companion=_companions(row.get("companion", ()), i),
                **{k: row[k] for k in Pin._fields if k not in slack},
            )
        )
    if not pins:
        raise ValueError("no [[grammar]] tables")
    if which != "all":
        pins = [p for p in pins if p.set == which]
        if not pins:
            raise ValueError(f"no [[grammar]] tables in set {which!r}")
    return pins


def _companions(rows: Any, at: int) -> tuple[Companion, ...]:
    """Same discipline as the grammar row: every field named, nothing guessed.
    A companion missing its hash would be a path we fetch and never check, which
    is worse than no pin at all because it looks like one."""
    out = []
    for j, row in enumerate(rows, 1):
        where = f"[[grammar.companion]] #{j} of [[grammar]] #{at}"
        if missing := {"path", "sha256", "size"} - row.keys():
            raise ValueError(f"{where} is missing {', '.join(sorted(missing))}")
        if unknown := row.keys() - set(Companion._fields):
            raise ValueError(f"{where} has no such field {', '.join(sorted(unknown))}")
        if row["path"].startswith(("/", "../")) or "/../" in row["path"]:
            raise ValueError(f"{where}: {row['path']!r} is not relative to the repository root")
        out.append(Companion(row["path"], row["sha256"], int(row["size"]), row.get("note", "")))
    return tuple(out)


def _toml(text: str) -> dict[str, Any]:
    try:
        import tomllib
    except ModuleNotFoundError:
        return _subset(text)
    return tomllib.loads(text)


def _subset(text: str) -> dict[str, Any]:
    """A closed reader for this one file's shape, because `tomllib` landed in
    3.11 and the python a bare macOS ships is 3.9.6. Nobody should need a newer
    interpreter to check a hash. It raises on anything outside `[[grammar]]` and
    `[[grammar.companion]]` plus `key = "string"` / `key = 123`, so it cannot
    quietly disagree with tomllib about a file it accepted - it either reads it
    the same way or refuses it.
    """
    rows: list[dict[str, Any]] = []
    # Keys land in the table the last header opened, which is TOML's own rule
    # for an array of tables nested inside an array of tables.
    into: dict[str, Any] | None = None
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line == "[[grammar]]":
            rows.append({})
            into = rows[-1]
            continue
        if line == "[[grammar.companion]]":
            if not rows:
                raise ValueError(f"line {n}: a companion before any [[grammar]]")
            into = {}
            rows[-1].setdefault("companion", []).append(into)
            continue
        key, sep, rest = line.partition("=")
        if not sep or into is None:
            raise ValueError(f"line {n}: {line!r} is outside this reader's subset")
        key, rest = key.strip(), rest.strip()
        if rest.startswith('"'):
            end = rest.find('"', 1)
            if end < 0:
                raise ValueError(f"line {n}: unterminated string")
            into[key] = rest[1:end]
        else:
            into[key] = int(rest.split("#", 1)[0].strip())
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


def kin(pin: Pin, dest: Path) -> Path:
    """Where a grammar's companions live: one tree per grammar, laid out at the
    repo-relative paths the pin names.

    Not one shared directory. ocaml and php both need a file called
    `common/scanner.h`, they are 14,631 and 18,018 different bytes, and anything
    that resolves both to one path silently hands one language the other's
    scanner.
    """
    return dest / "companion" / pin.name


def kinship(pins: list[Pin], dest: Path) -> list[Row]:
    """Every companion, hashed on disk against its pin. Offline, like `survey`."""
    rows = []
    for pin in pins:
        for mate in pin.companion:
            f = kin(pin, dest) / mate.path
            got = digest(f) if f.exists() else ""
            state = "missing" if not got else "ok" if got == mate.sha256 else "drifted"
            rows.append(Row(pin._replace(path=mate.path, sha256=mate.sha256,
                                         size=mate.size, note=mate.note), state, got))
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
    return (1 if bad else 0) | fetch_kin(pins, dest)


def fetch_kin(pins: list[Pin], dest: Path) -> int:
    """The companions, from the same commit, checked against the same kind of
    hash. Each URL is built from the repository root rather than by climbing out
    of the grammar's own directory, so a path is what it says it is."""
    bad = 0
    for row in kinship(pins, dest):
        pin = row.pin  # carries the companion's path, hash and size
        target = kin(pin, dest) / pin.path
        if row.state == "ok":
            print(f"  have {pin.name:<11} {pin.path}")
            continue
        if row.state == "drifted":
            print(f" DRIFT {pin.name:<11} {pin.path}: on disk {row.got[:16]}, "
                  f"pinned {pin.sha256[:16]}")
            print(f"       refusing to overwrite; delete {target} and re-run to take the pin")
            bad += 1
            continue
        if not pin.reproducible:
            print(f"  skip {pin.name:<11} {pin.path}: hash-only pin, no commit to fetch")
            bad += 1
            continue
        url = pin.url_of(pin.path)
        try:
            with urllib.request.urlopen(url, timeout=60) as r:  # noqa: S310 - https literal
                blob = r.read()
        except (urllib.error.URLError, OSError) as e:
            return oops(f"{pin.name}: {url}: {e}")
        got = hashlib.sha256(blob).hexdigest()
        if got != pin.sha256:
            return oops(
                f"{pin.name}: {pin.path}: upstream gave {len(blob)} bytes hashing {got}, "
                f"manifest pins {pin.sha256}\n  {url}\n  nothing written."
            )
        target.parent.mkdir(parents=True, exist_ok=True)
        part = target.with_name(target.name + ".part")
        part.write_bytes(blob)
        part.replace(target)
        print(f" wrote {pin.name:<11} {pin.path:<32} {got[:16]} {len(blob)} bytes")
    return 1 if bad else 0


def _api(url: str) -> Any:
    req = urllib.request.Request(url, headers={
        "Accept": "application/vnd.github+json",
        "User-Agent": "joints-grammars.py",
    })
    try:
        with urllib.request.urlopen(req, timeout=60) as r:  # noqa: S310 - https literal
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        if e.code == 403:
            raise OSError(
                "GitHub refused: unauthenticated API calls are rate limited to 60 an hour, "
                "and minting a pin costs two. Wait, or export a token the way `gh auth` does."
            ) from e
        raise OSError(f"{url}: HTTP {e.code}") from e


def blob_sha(data: bytes) -> str:
    """What `git hash-object` would say. The manifest header claims each pin
    was checked twice - the bytes hashed, and separately their blob hash
    compared inside a real clone. This is that second check without the clone:
    the number git would have stored is derived here from the bytes we
    downloaded, and compared against the one GitHub reports for that path at
    that commit. Two independent statements about the same object, so a pin
    cannot be right about the hash and wrong about the commit.
    """
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()  # noqa: S324 - git's format


def mint(spec: str, which: str) -> tuple[int, str]:
    """Resolve one `name=owner/repo[@ref][:path]` into a `[[grammar]]` table.

    `@ref` exists because not every repository keeps its generated grammar on
    the default branch - some publish it to a side branch instead, and a pin
    that can only see `HEAD` would call those unpinnable when they are merely
    somewhere else.
    """
    name, sep, rest = spec.partition("=")
    if not sep:
        return 2, f"{spec!r} is not `name=owner/repo[@ref][:path]`"
    repospec, _, path = rest.partition(":")
    repo, _, ref = repospec.partition("@")
    head = _api(f"{API.format(repo)}/commits/{ref or 'HEAD'}")
    commit, date = head["sha"], head["commit"]["committer"]["date"][:10]
    if path:
        entry = _api(f"{API.format(repo)}/contents/{path}?ref={commit}")
        want_blob = entry["sha"]
    else:
        tree = _api(f"{API.format(repo)}/git/trees/{commit}?recursive=1")
        if tree.get("truncated"):
            return 2, f"{name}: {repo}'s tree is truncated; name the path explicitly"
        # `src/grammar.json` is the tree-sitter convention. Anything else with
        # that basename is a fixture or a vendored copy, and taking one would
        # pin a grammar nobody ships.
        found = [e["path"] for e in tree["tree"] if e["path"].endswith("src/grammar.json")]
        if len(found) != 1:
            hint = "\n    ".join(sorted(found)) if found else "none found"
            return 2, f"{name}: {repo} holds {len(found)} grammars; name one with `:path`\n    {hint}"
        path = found[0]
        want_blob = next(e["sha"] for e in tree["tree"] if e["path"] == path)
    pin = Pin(name, repo, commit, path, "", 0, date, "", "", which)
    try:
        with urllib.request.urlopen(pin.url, timeout=60) as r:  # noqa: S310 - https literal
            blob = r.read()
    except (urllib.error.URLError, OSError) as e:
        return 2, f"{name}: {pin.url}: {e}"
    if (got := blob_sha(blob)) != want_blob:
        return 2, (f"{name}: raw bytes hash to blob {got} but {repo} reports {want_blob} "
                   f"at that path; refusing to pin bytes no commit reproduces")
    out = ["[[grammar]]", f'name = "{name}"', f'repo = "{repo}"', f'commit = "{commit}"',
           f'path = "{path}"', f'sha256 = "{hashlib.sha256(blob).hexdigest()}"',
           f"size = {len(blob)}", f'date = "{date}"']
    if which != DOSSIER:
        out.append(f'set = "{which}"')
    return 0, "\n".join(out)


def report(pins: list[Pin], dest: Path, as_json: bool, terse: bool) -> int:
    rows, kept, mates = survey(pins, dest), copies(pins), kinship(pins, dest)
    tally = {s: sum(r.state == s for r in rows) for s in ("ok", "missing", "drifted", "unpinned")}
    bad = (len(rows) - tally["ok"] + sum(c.state != "ok" for c in kept)
           + sum(m.state != "ok" for m in mates))
    if as_json:
        print(json.dumps({
            "dest": str(dest), **tally,
            "grammar": [r.as_dict() for r in rows],
            "fixture": [c.as_dict() for c in kept],
            "companion": [m.as_dict() for m in mates],
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
    for m in mates:
        if m.state == "ok" and terse:
            continue
        mark = {"ok": "  ok", "missing": "  --", "drifted": "  !!", "unpinned": "  ??"}[m.state]
        detail = {"ok": m.got[:16], "missing": "not fetched",
                  "drifted": f"on disk {m.got[:16]}, pinned {m.pin.sha256[:16]}",
                  "unpinned": "hash-only pin"}[m.state]
        print(f"{mark} {m.pin.name:<11} {m.pin.path:<32} {detail}")
    verdict = ", ".join(f"{n} {s}" for s, n in tally.items() if n)
    where = dest.relative_to(ROOT) if dest.is_relative_to(ROOT) else dest
    held = sum(c.state == "ok" for c in kept)
    ok_mates = sum(m.state == "ok" for m in mates)
    print(f"{len(rows)} pinned in {where}: {verdict}"
          + (f" · {held}/{len(kept)} committed copies ok" if kept else "")
          + (f" · {ok_mates}/{len(mates)} companions ok" if mates else ""))
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
    wide = max((len(p.name) for p in pins), default=4)
    print(f"{'name':<{wide}} {'set':<8} {'bytes':>7}  {'date':<10} {'sha256':<16} {'commit':<48} path")
    for p in pins:
        where = f"{p.repo}@{p.commit[:12]}" if p.reproducible else f"{p.repo} (hash only)"
        print(f"{p.name:<{wide}} {p.set:<8} {p.size:>7}  {p.date:<10} "
              f"{p.sha256[:16]} {where:<48} {p.path}")
    return 0


def oops(msg: str) -> int:
    print(f"grammars.py: {msg}", file=sys.stderr)
    return 2


def main(argv: list[str]) -> int:
    dest, as_json, verb, which, rest = DEST, False, "", "", []
    for a in argv:
        if a == "--json":
            as_json = True
        elif a.startswith("--dest="):
            dest = Path(a.split("=", 1)[1]).expanduser()
        elif a.startswith("--set="):
            which = a.split("=", 1)[1]
        elif a in ("-h", "--help"):
            print(USAGE)
            return 0
        elif a.startswith("-"):
            return oops(f"unknown flag {a}\n\n{USAGE}")
        elif verb:
            rest.append(a)
        else:
            verb = a
    if not verb:
        print(USAGE, file=sys.stderr)
        return 2
    if verb == "pin":
        if not rest:
            return oops(f"pin needs at least one spec\n\n{USAGE}")
        bad = 0
        for spec in rest:
            try:
                code, text = mint(spec, which or DOSSIER)
            except (OSError, KeyError, ValueError) as e:
                code, text = 2, f"{spec}: {e}"
            if code:
                bad += 1
                # Refused pins go to stderr so `pin ... > pins.toml` writes only
                # the ones that were actually checked.
                print(f"grammars.py: {text}", file=sys.stderr)
            else:
                print(text + "\n")
        return 2 if bad else 0
    if rest:
        return oops(f"one verb at a time, got {verb} and then {rest[0]}")
    try:
        # A human reading the manifest wants every pin; only a caller asking
        # programmatically gets the dossier default, and this is not that.
        pins = load(which or "all")
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

#!/usr/bin/env python3
"""`field.py` - how much of tree-sitter's field can this press build tables for?

Every number this repository quotes is measured over the same thirty grammars it
was developed against. That is in-sample twice over: the walls those thirty hit
are the walls that got fixed, and the percentages are taken on the same thirty.
Nothing in the tree could detect overfitting.

The claim that actually matters is not "we support thirty languages". It is
**"we take any `grammar.json`"**, and this is the cheapest possible test of it.

**Pressing is not measuring.** This tool builds tables and records what happened.
It never parses a file, never consults an oracle, never diagnoses a wall - so it
spends no validity and can be pointed at the entire field without burning
anything. `tool/holdout.py` is the expensive half, and it is sealed.

## The roster comes from somebody else

`nvim-treesitter/nvim-treesitter`'s `lua/nvim-treesitter/parsers.lua`, pinned to
a commit, is a third party's list of parsers authored for a different purpose
(which grammars a Neovim user can install). Each entry carries a repository, a
pinned revision, and - for the 27 that live in a monorepo - a subdirectory. I did
not choose which languages are on it, and changing the pin is a recorded edit.

## The outcome vocabulary, and the one bucket that matters

    clean      exit 0 · 0 RESIDUAL · 0 REFUSE
    refusing   exit 0 · 0 RESIDUAL · N cells that REFUSE a token
    residual   exit 0 · N RESIDUAL > 0
    unlexable  exit 0 · zero literal AND zero regex terminals
    refused    exit != 0, carrying the binary's own reason
    timeout    over the budget
    absent     no committed grammar.json at the pinned revision

`unlexable` is separate because **yaml already proves the trap**: 113 external
terminals, zero literal, zero regex, presses to 0 RESIDUAL, and `joints parse`
exits 2 with "no lexable terminal at all". A taxonomy that filed that under
`clean` would report the project's hardest stop as a success. Pressing whole and
lexing nothing are different questions and this tool answers only the first;
`seat` is the column that says how much of the second is missing.

`absent` is counted and named and is **never folded into a percentage of the
field**. A denominator you cannot see is worse than a small one.

    python3 tool/field.py roster              the pinned list, as a table
    python3 tool/field.py fetch               obtain every grammar.json (the network verb)
    python3 tool/field.py press               press what was obtained
    python3 tool/field.py run                 fetch, press, report
    python3 tool/field.py report              the distribution, from the cache
    python3 tool/field.py show <name>         one grammar's whole press report
    python3 tool/field.py verify              prove this instrument can still say no

    --json on the read verbs · --jobs N · --patience S · --limit N

    JOINTS_BIN=<path>   press with a pinned binary (`tool/pin.py`), not `zig-out`

Exit 0 ran, 1 a clean negative answer, 2 could not run.
"""

from __future__ import annotations

import argparse
import concurrent.futures as cf
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import NamedTuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
import stamp  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
BIN = Path(os.environ.get("JOINTS_BIN", ROOT / "zig-out" / "bin" / "joints"))
WORK = Path(os.environ.get("JOINTS_FIELD", ROOT / ".local" / "generalize" / "field"))

# The roster, pinned. Changing any of these four lines changes what "the field"
# means, and the sweep records them beside every number it prints.
ROSTER_REPO = "nvim-treesitter/nvim-treesitter"
ROSTER_COMMIT = "3d3321b560a63ff92a8692401f303a5123336b86"
ROSTER_PATH = "lua/nvim-treesitter/parsers.lua"
ROSTER_SHA = "4a8f2aac6a74475e52ddb0dd3b2cc12b190786191dd5caaf932455ec51a92403"

RAW = "https://raw.githubusercontent.com"
ENTRY = re.compile(r"^  ([A-Za-z0-9_]+) = \{$", re.M)
FIELD = {k: re.compile(rf"\b{k} = '([^']*)'") for k in ("url", "revision", "location")}
HEX40 = re.compile(r"^[0-9a-f]{40}$")

# What the press says about itself. Read off the report rather than restated:
# every one of these is a line `joints grammar` prints, and a bucket is a
# predicate over them - never a list of grammar names.
SAYS = {
    "symbols": re.compile(r"^\s*symbols\s+(\d+)\s+\((\d+) terminal, (\d+) nonterminal\)", re.M),
    "terms": re.compile(r"^\s*terminals\s+(\d+) literal, (\d+) regex, (\d+) external", re.M),
    "prods": re.compile(r"^\s*productions\s+(\d+)", re.M),
    "states": re.compile(r"^\s*lr\(0\) states\s+(\d+)", re.M),
    "cells": re.compile(r"^\s*lalr table\s+(\d+) cells", re.M),
    "contested": re.compile(r"^\s*contested\s+(\d+) cells", re.M),
    "residual": re.compile(r"(\d+) RESIDUAL", re.M),
    "frayed": re.compile(r"^\s*frayed\s+(\d+) cells.*?\((\d+) REFUSE", re.M),
    "barren": re.compile(r"^\s*BARREN\s+(\d+)", re.M),
}


class Pin(NamedTuple):
    """One roster entry: what to fetch, and from exactly where."""

    name: str
    owner: str
    repo: str
    revision: str
    location: str  # "" for a grammar at the repository root

    @property
    def slug(self) -> str:
        return f"{self.owner}/{self.repo}"

    def raw(self, path: str) -> str:
        inner = f"{self.location}/{path}" if self.location else path
        return f"{RAW}/{self.owner}/{self.repo}/{self.revision}/{inner}"

    @property
    def grammar_path(self) -> str:
        return f"{self.location}/src/grammar.json" if self.location else "src/grammar.json"


class Press(NamedTuple):
    """What the press did with one grammar."""

    name: str
    outcome: str
    reason: str = ""
    bytes_: int = 0
    sha: str = ""
    terminals: int = 0
    literal: int = 0
    regex: int = 0
    external: int = 0
    nonterminals: int = 0
    productions: int = 0
    states: int = 0
    cells: int = 0
    contested: int = 0
    residual: int = 0
    refuse: int = 0
    barren: int = 0
    ms: float = 0.0

    @property
    def pressed(self) -> bool:
        """Did a table come out at all? `unlexable` did - that is the point."""
        return self.outcome in ("clean", "refusing", "residual", "unlexable")

    @property
    def seat(self) -> float:
        """Share of terminals that are NOT external - the lexable fraction.

        The press's own report cannot see a scanner, so this is a ceiling on
        reach that has nothing to do with how well the tables came out. It is
        the column that separates "we built a table" from "we can read a byte".
        """
        return 0.0 if not self.terminals else (self.literal + self.regex) / self.terminals


# ------------------------------------------------------------------ the roster

def roster_text() -> str:
    """The pinned `parsers.lua`, cached, and refused if its bytes moved."""
    cache = WORK / "parsers.lua"
    if cache.exists():
        blob = cache.read_bytes()
    else:
        url = f"{RAW}/{ROSTER_REPO}/{ROSTER_COMMIT}/{ROSTER_PATH}"
        with urllib.request.urlopen(url, timeout=60) as r:  # noqa: S310 - https literal
            blob = r.read()
        cache.parent.mkdir(parents=True, exist_ok=True)
        cache.write_bytes(blob)
    got = hashlib.sha256(blob).hexdigest()
    if got != ROSTER_SHA:
        raise ValueError(f"roster bytes are not the pin: {got[:16]} != {ROSTER_SHA[:16]}")
    return blob.decode()


def entries() -> list[tuple[str, dict[str, str]]]:
    """Every block the pinned roster spells, in the order it spells them.

    A Lua reader rather than a Lua interpreter: the entries are found by their
    own indentation (`^  name = {`) and each block is read by key.
    """
    text = roster_text()
    marks = [(m.group(1), m.start()) for m in ENTRY.finditer(text)]
    out = []
    for i, (name, at) in enumerate(marks):
        body = text[at:marks[i + 1][1] if i + 1 < len(marks) else len(text)]
        out.append((name, {k: (m.group(1) if (m := rx.search(body)) else "")
                           for k, rx in FIELD.items()}))
    return out


def resolve(owner: str, repo: str, ref: str) -> str:
    """A tag to the commit it names. Only ever called under `--tags`."""
    url = f"https://api.github.com/repos/{owner}/{repo}/commits/{ref}"
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github.sha"})
    if tok := os.environ.get("GITHUB_TOKEN", ""):
        req.add_header("Authorization", f"Bearer {tok}")
    with urllib.request.urlopen(req, timeout=60) as r:  # noqa: S310 - https literal
        got = r.read().decode().strip()
    return got if HEX40.match(got) else ""


def roster(tags: bool = False) -> list[Pin]:
    """Every roster entry this tool can pin to an exact commit.

    An entry whose url is not a github.com repository, or whose revision is not
    40 hex, is dropped and counted as `unpinnable` - it fails E1 of
    `research/generalize/SELECTION.md`, which was written before any of this ran
    and is not being edited now that the count is known.

    `--tags` is the **addendum**, and it is off by default for that reason:
    ten of the thirteen pin a release tag rather than a commit, which is
    resolvable but is not what E1 says. Turning it on widens the field and is
    reported as a separate number, never folded into the sealed rule.
    """
    out: list[Pin] = []
    for name, got in entries():
        url, rev = got["url"], got["revision"]
        if not url.startswith("https://github.com/"):
            continue
        owner, _, repo = url[len("https://github.com/"):].partition("/")
        repo = repo.removesuffix(".git")
        if not HEX40.match(rev):
            if not tags or not rev:
                continue
            try:
                rev = resolve(owner, repo, rev)
            except (urllib.error.URLError, OSError):
                rev = ""
            if not rev:
                continue
        out.append(Pin(name, owner, repo, rev, got["location"]))
    return out


def unpinnable(tags: bool = False) -> int:
    """How many roster entries E1 dropped. Counted, because a silent drop is a
    denominator nobody can see."""
    return len(entries()) - len(roster(tags))


# ------------------------------------------------------------------- obtaining

def grab(pin: Pin) -> tuple[bytes | None, str]:
    """One grammar.json, or why there is not one."""
    try:
        with urllib.request.urlopen(pin.raw("src/grammar.json"), timeout=90) as r:  # noqa: S310
            return r.read(), ""
    except urllib.error.HTTPError as e:
        return None, f"http {e.code}"
    except (urllib.error.URLError, OSError, TimeoutError) as e:
        return None, f"{type(e).__name__}: {e}"


def fetch(pins: list[Pin], jobs: int = 8) -> dict[str, str]:
    """Obtain every grammar.json into the cache. Returns name -> why-not."""
    WORK.mkdir(parents=True, exist_ok=True)
    missing: dict[str, str] = {}

    def one(pin: Pin) -> tuple[str, str]:
        dest = WORK / f"{pin.name}.json"
        if dest.exists() and dest.stat().st_size:
            return pin.name, ""
        blob, why = grab(pin)
        if blob is None:
            return pin.name, why
        # A repository can serve an HTML 404 page with a 200; a grammar.json
        # that is not JSON is not a grammar and must not reach the press as one.
        try:
            json.loads(blob)
        except ValueError:
            return pin.name, "not JSON at that path"
        dest.write_bytes(blob)
        return pin.name, ""

    with cf.ThreadPoolExecutor(max_workers=jobs) as pool:
        for name, why in pool.map(one, pins):
            if why:
                missing[name] = why
    return missing


# --------------------------------------------------------------- the press run

def num(rx: re.Pattern[str], text: str, group: int = 1) -> int:
    m = rx.search(text)
    return int(m.group(group)) if m else 0


def press_one(pin: Pin, patience: float) -> Press:
    """Build tables for one grammar and file what happened."""
    path = WORK / f"{pin.name}.json"
    if not path.exists():
        return Press(pin.name, "absent", "no grammar.json obtained")
    blob = path.read_bytes()
    sha = hashlib.sha256(blob).hexdigest()
    began = time.perf_counter()
    try:
        got = subprocess.run([str(BIN), "grammar", str(path)], capture_output=True,
                             text=True, timeout=patience)
    except subprocess.TimeoutExpired:
        return Press(pin.name, "timeout", f"over {patience:.0f}s", len(blob), sha,
                     ms=patience * 1000)
    ms = (time.perf_counter() - began) * 1000
    said = got.stdout + got.stderr
    if got.returncode != 0:
        line = refusal(said)
        # `stamp.behind` strips the `joints: <path>: ` prefix using the path
        # we passed in. Nothing here infers one: two readers in this tree used
        # to, and both took too little the moment a payload held the delimiter.
        return Press(pin.name, "refused", stamp.behind(line, path) or line, len(blob), sha, ms=ms)
    lit, rex, ext = (num(SAYS["terms"], said, i) for i in (1, 2, 3))
    residual, refuse = num(SAYS["residual"], said), num(SAYS["frayed"], said, 2)
    # Ordered by what would be the most misleading thing to hide. `unlexable`
    # outranks `clean` because a perfect table over a grammar that cannot lex a
    # byte is the failure this project's headline is most exposed to.
    outcome = ("unlexable" if lit + rex == 0 else
               "residual" if residual else
               "refusing" if refuse else "clean")
    return Press(pin.name, outcome, "", len(blob), sha,
                 terminals=num(SAYS["symbols"], said, 2), literal=lit, regex=rex, external=ext,
                 nonterminals=num(SAYS["symbols"], said, 3),
                 productions=num(SAYS["prods"], said), states=num(SAYS["states"], said),
                 cells=num(SAYS["cells"], said), contested=num(SAYS["contested"], said),
                 residual=residual, refuse=refuse, barren=num(SAYS["barren"], said), ms=ms)


def refusal(said: str) -> str:
    """The one line of a refusal worth repeating."""
    lines = [ln.strip() for ln in said.splitlines() if ln.strip()]
    for ln in lines:
        if ln.startswith("joints:") or "error" in ln.lower():
            return ln
    return lines[-1] if lines else "no reason given"


def sweep(pins: list[Pin], patience: float) -> list[Press]:
    return [press_one(p, patience) for p in pins]


CACHE = "sweep.json"


SEAT = ("no oracle: pressing builds tables and parses nothing, so tree-sitter is"
        " never consulted and there is no oracle to seat. Every row's identity is"
        " its grammar.json sha256 in `rows[].sha` plus its pin below. That is the"
        " whole of what this sweep depends on.")


def save(rows: list[Press], missing: dict[str, str], mark: stamp.Stamp,
         tags: bool = False, pins: list[Pin] | None = None) -> None:
    WORK.mkdir(parents=True, exist_ok=True)
    (WORK / CACHE).write_text(json.dumps({
        "roster": {"repo": ROSTER_REPO, "commit": ROSTER_COMMIT, "sha256": ROSTER_SHA},
        "stamp": mark.as_dict(), "binary": str(BIN), "tags": tags,
        "unpinnable": unpinnable(tags), "missing": missing,
        # A path is not a version, and a sha256 without a source is not
        # re-fetchable. Both, per row, or a cold run months from now can check
        # that the bytes did not move and not get them back when they did.
        "seat": SEAT,
        "pin": {p.name: {"repo": p.slug, "revision": p.revision,
                         "path": p.grammar_path} for p in (pins or [])},
        "rows": [r._asdict() for r in rows],
    }, indent=2))


def load() -> tuple[list[Press], dict, dict[str, str]]:
    got = json.loads((WORK / CACHE).read_text())
    return ([Press(**r) for r in got["rows"]], got, got.get("missing", {}))


# --------------------------------------------------------------------- reports

ORDER = ("clean", "refusing", "residual", "unlexable", "refused", "timeout", "absent")


def report(rows: list[Press], meta: dict, missing: dict[str, str], as_json: bool) -> int:
    got = {k: [r for r in rows if r.outcome == k] for k in ORDER}
    obtained = [r for r in rows if r.outcome != "absent"]
    pressed = [r for r in obtained if r.pressed]
    if as_json:
        print(json.dumps({
            "roster": meta["roster"], "entries": len(rows) + meta.get("unpinnable", 0),
            "unpinnable": meta.get("unpinnable", 0),
            "obtained": len(obtained), "absent": len(got["absent"]),
            "pressed": len(pressed),
            "share_pressed": round(len(pressed) / len(obtained), 4) if obtained else 0.0,
            "outcomes": {k: len(v) for k, v in got.items()},
            "rows": [r._asdict() for r in rows],
        }, indent=2))
        return 0

    print(f"\n  the field: {ROSTER_REPO}@{ROSTER_COMMIT[:9]} · {ROSTER_PATH}")
    print(f"  {len(rows) + meta.get('unpinnable', 0)} roster entries · "
          f"{meta.get('unpinnable', 0)} not pinnable to a github commit\n")
    print(f"  {'outcome':<11}{'n':>5}  {'of obtained':>12}   what it means")
    print(f"  {'-' * 74}")
    means = {
        "clean": "tables built, nothing residual, nothing refusing",
        "refusing": "built, and some cell refuses a token it was handed",
        "residual": "built, with conflicts the resolver could not settle",
        "unlexable": "built, and cannot lex one byte - every terminal is external",
        "refused": "the press would not build tables",
        "timeout": "over the budget",
        "absent": "no committed grammar.json - NOT in any percentage below",
    }
    for k in ORDER:
        n = len(got[k])
        share = f"{n / len(obtained) * 100:>11.1f}%" if obtained and k != "absent" else " " * 12
        print(f"  {k:<11}{n:>5}  {share}   {means[k]}")
    print(f"  {'-' * 74}")
    print(f"  {'obtained':<11}{len(obtained):>5}   the denominator every share above is over")
    print(f"  {'pressed':<11}{len(pressed):>5}  {len(pressed) / len(obtained) * 100:>11.1f}%"
          f"   a table came out — clean · refusing · residual · unlexable"
          if obtained else "  pressed          0")

    if pressed:
        seats = sorted(r.seat for r in pressed)
        ext = [r for r in pressed if r.external]
        res = [r for r in pressed if r.residual]
        mid = seats[len(seats) // 2]
        print(f"\n  seating, over the {len(pressed)} pressed")
        print(f"    {len(ext):>5} declare at least one external terminal "
              f"({len(ext) / len(pressed) * 100:.1f}%)")
        print(f"    {len(res):>5} carry at least one RESIDUAL cell "
              f"({len(res) / len(pressed) * 100:.1f}%)")
        print(f"    {len(got['unlexable']):>5} can lex nothing at all")
        print(f"    median lexable share of terminals: {mid * 100:.1f}%"
              f"  (median external share {100 - mid * 100:.1f}%)")

    if missing:
        why: dict[str, int] = {}
        for reason in missing.values():
            why[reason] = why.get(reason, 0) + 1
        print(f"\n  why {len(missing)} could not be obtained")
        for reason, n in sorted(why.items(), key=lambda kv: -kv[1]):
            print(f"    {n:>5}  {reason}")
        print("    a repository that does not commit generated output ships `grammar.js`"
              "\n           and needs the tree-sitter CLI to emit one. Not pressed, not counted.")

    if hot := [r for r in pressed if r.outcome == "unlexable"]:
        print(f"\n  the {len(hot)} that press whole and cannot lex a byte")
        for r in sorted(hot, key=lambda r: -r.external)[:20]:
            print(f"    {r.name:<22}{r.external:>5} external · {r.residual:>4} residual"
                  f" · {r.states:>6} states")

    bad = [r for r in rows if r.outcome in ("refused", "timeout")]
    if bad:
        print(f"\n  the {len(bad)} the press would not build")
        for r in sorted(bad, key=lambda r: r.name):
            print(f"    {r.name:<22}{r.outcome:<9}{r.bytes_:>9} bytes  {r.reason[:60]}")
    mark = meta.get("stamp") or {}
    hazard = " ".join(k.upper() for k in ("told", "stale", "drift", "moved") if mark.get(k))
    print(f"\n  stamp: tree {mark.get('tree', '?')} · binary {mark.get('build', '?')}"
          f" · commit {mark.get('commit', '?')} · {hazard or 'no hazard'}")
    print(f"         {mark.get('binary', '?')}")
    print("  pressing is not measuring: no file was parsed and no oracle consulted here.")
    # Said rather than left implicit. A grammar is not one thing on this disk -
    # several corpus grammars exist as two or three different source trees at
    # once - so a sweep that names no oracle has to say that it *has* none,
    # not leave a reader to infer it from a missing line.
    print(f"  {meta.get('seat', SEAT)}")
    pin = meta.get("pin") or {}
    print(f"  every row re-fetchable: {len(pin)} pin(s) recorded as repo + revision + path,"
          f"\n  each row's grammar.json digested in `sha`. Nothing here reads"
          " `upstream/grammars/`.")
    return 0


def show(rows: list[Press], name: str) -> int:
    row = next((r for r in rows if r.name == name), None)
    if row is None:
        print(f"field.py: {name} is not on the roster", file=sys.stderr)
        return 2
    for k, v in row._asdict().items():
        print(f"  {k:<14}{v}")
    path = WORK / f"{name}.json"
    if path.exists():
        print()
        got = subprocess.run([str(BIN), "grammar", str(path)], capture_output=True, text=True)
        print(got.stdout or got.stderr)
    return 0


# ---------------------------------------------------------------- the tripwire

def verify() -> int:
    """Prove this instrument can still say no. Six assertions, all constructed.

    The failure this guards against is the one `specimen.py`'s `stop()` had: a
    default that looks like success. Every bucket here must be reachable, and
    the two that flatter - `clean`, and `absent` silently becoming a zero - must
    be impossible to reach by accident.
    """
    import tempfile
    out: list[tuple[bool, str]] = []
    with tempfile.TemporaryDirectory() as tmp:
        home, keep = Path(tmp), WORK
        globals()["WORK"] = home
        try:
            # A grammar with no `src/grammar.json` on disk is `absent`, and
            # `absent` is not `clean` and carries no zeroed table.
            gone = press_one(Pin("nothing", "o", "r", "0" * 40, ""), 10)
            out.append((gone.outcome == "absent" and not gone.pressed,
                        f"a grammar nobody fetched reads `{gone.outcome}`, not a clean press"))
            # Bytes that are not a grammar must refuse, not press to an empty
            # table that reads exactly like a tiny clean one.
            (home / "junk.json").write_text('{"name":"junk"}')
            junk = press_one(Pin("junk", "o", "r", "0" * 40, ""), 20)
            out.append((junk.outcome in ("refused", "timeout"),
                        f"a grammar with no rules reads `{junk.outcome}`, and carries a reason:"
                        f" {junk.reason[:48] or '(none)'}"))
            # yaml is the exhibit: it presses whole and lexes nothing, and the
            # taxonomy must not call that clean.
            yaml = ROOT / "upstream" / "grammars" / "yaml.json"
            if yaml.exists():
                (home / "yaml.json").write_bytes(yaml.read_bytes())
                y = press_one(Pin("yaml", "o", "r", "0" * 40, ""), 60)
                out.append((y.outcome == "unlexable" and y.residual == 0 and y.pressed,
                            f"yaml presses to {y.residual} residual and still reads"
                            f" `{y.outcome}` — 0 literal, 0 regex, {y.external} external"))
            # A roster whose bytes moved is refused rather than read.
            (home / "parsers.lua").write_text("-- not the pin\n")
            try:
                roster()
                out.append((False, "a roster whose bytes moved was READ"))
            except ValueError as e:
                out.append((True, f"a roster whose bytes moved is refused: {e}"))
        finally:
            globals()["WORK"] = keep
    # The roster reader finds the entries it claims to, off the real pin.
    live = roster()
    out.append((len(live) > 250, f"the pinned roster reads {len(live)} pinnable entries"))
    out.append((all(HEX40.match(p.revision) for p in live),
                "every entry carries a 40-hex revision, so every fetch is reproducible"))
    for ok, why in out:
        print(f"  {'ok  ' if ok else 'FAIL'}  {why}")
    bad = sum(1 for ok, _ in out if not ok)
    print(f"\n  {len(out) - bad}/{len(out)} held")
    return 1 if bad else 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("verb", nargs="?", default="report",
                    choices=("roster", "fetch", "press", "run", "report", "show", "verify"))
    ap.add_argument("name", nargs="?", default="")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--jobs", type=int, default=8)
    ap.add_argument("--patience", type=float, default=120.0)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--tags", action="store_true",
                    help="also pin the entries that name a release tag - the addendum, "
                         "outside E1 of SELECTION.md, reported separately")
    a = ap.parse_args(argv)

    if a.verb == "verify":
        return verify()
    try:
        pins = roster(a.tags)
    except (ValueError, urllib.error.URLError, OSError) as e:
        print(f"field.py: {e}", file=sys.stderr)
        return 2
    if a.limit:
        pins = pins[:a.limit]

    if a.verb == "roster":
        if a.json:
            print(json.dumps([p._asdict() for p in pins], indent=2))
            return 0
        print(f"\n  {len(pins)} pinnable of {len(pins) + unpinnable(a.tags)} entries\n")
        for p in pins:
            print(f"  {p.name:<22}{p.slug:<46}{p.revision[:9]}  {p.location}")
        return 0

    if a.verb == "fetch":
        missing = fetch(pins, a.jobs)
        print(f"  obtained {len(pins) - len(missing)} of {len(pins)}; {len(missing)} absent")
        (WORK / "missing.json").write_text(json.dumps(missing, indent=2))
        return 0

    if a.verb in ("press", "run"):
        mark = stamp.take(BIN)
        missing = fetch(pins, a.jobs) if a.verb == "run" else json.loads(
            (WORK / "missing.json").read_text()) if (WORK / "missing.json").exists() else {}
        rows = sweep(pins, a.patience)
        save(rows, missing, mark, a.tags, pins)
        return report(rows, load()[1], missing, a.json)

    try:
        rows, meta, missing = load()
    except (OSError, ValueError):
        print(f"field.py: no sweep cached at {WORK / CACHE}; run `field.py run`", file=sys.stderr)
        return 2
    if a.verb == "show":
        return show(rows, a.name)
    return report(rows, meta, missing, a.json)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

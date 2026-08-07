#!/usr/bin/env python3
"""`holdout.py` - twenty grammars nobody is allowed to diagnose against.

Every number this repository quotes is measured over the thirty grammars it was
developed against. We tune against those thirty, we fix the walls those thirty
hit, and we report percentages taken on the same thirty. Nothing in the tree
could detect overfitting, so nothing in the tree can say how much of this month
generalises.

This is the estimate. **Twenty grammars with real source files, pinned to
commits, selected by a rule written down before it ran, and sealed.**

    holdout/README.md                  the seal, at the entrance
    research/generalize/SELECTION.md   the rule, written before selection
    holdout/holdout.toml               the pins - repo, commit, path, sha256, size
    holdout/ledger.json                every unsealing, and what it cost

## The seal, and why it is enforced here rather than promised

`gate` prints **aggregate per grammar and nothing finer**: size, built, square,
crooked, soft, unaudited, trued, and how much of it the oracle could judge. It
prints no wall, no state number, no refused terminal, no byte offset, no tree,
no run. Those exist inside the measurement - `rack.survey` hands back every
crooked run with both parsers' names and both offsets - and this file drops them
on the floor by construction: the rich object never leaves `judge()`, and the
row type it returns has no field one could hide in.

Looking at *why* a holdout grammar failed is the thing that destroys it, so that
look has a price and the price is irreversible:

    holdout.py unseal <grammar> --reason "..."

records the unsealing in the ledger and **permanently retires that grammar from
the holdout into the working corpus**. The twenty shrinks, visibly, and the
ledger says who spent it and why. There is no verb that puts one back.

The protocol when the holdout reveals something: reproduce it on a
working-corpus grammar or an authored construct, fix it there, and never look at
the holdout witness again. **A defect crosses the seal as a shape, never as a
witness.**

`prove` is the demonstration, and it is the pattern `collate.py prove` set:
attempt to violate the seal and show the ledger catches you.

## What is measured

`trued = square / size` - bytes whose derivation tree-sitter defends, over the
whole file. The board's own floor, through the board's own code path
(`plumb.read` -> `rack.survey` -> `standing`'s soft rule), because a second copy
of that rule is how two instruments come to disagree about a word they spell the
same. `GRAMMARS` is rebound to the holdout's own vendor directory for the
duration of a measurement and never written to; nothing here touches
`upstream/grammars/`, which is the working corpus and is read by everything.

**Absence is its own outcome and is never a zero.** A grammar tree-sitter cannot
generate, a scanner that will not compile, a parse with nothing built - each
reads as `none` with a reason, is excluded from the headline's numerator *and*
its denominator, and is counted. `specimen.py`'s `stop()` defaulted a missing
stop line to one root and no mends - the exact shape of a perfect parse - and
scored a file HELD against a binary that had not read a byte of it.

    python3 tool/holdout.py select            run SELECTION.md, write the pins (once)
    python3 tool/holdout.py fetch             obtain the pinned bytes (the network verb)
    python3 tool/holdout.py verify            offline: bytes match pins, ledger is sound
    python3 tool/holdout.py press             tables only - cheap, spends nothing
    python3 tool/holdout.py gate              THE MEASUREMENT. Aggregate only.
    python3 tool/holdout.py status            what is sealed, what was spent
    python3 tool/holdout.py unseal N --reason "..."   spend one, forever
    python3 tool/holdout.py prove             break the seal on purpose, and be caught

    --json on the read verbs · --grammar N (repeatable) · --patience S

    JOINTS_BIN=<path>   measure a pinned binary (`tool/pin.py`), not `zig-out`

Exit 0 ran, 1 a clean negative answer (the seal refused you, a check failed),
2 could not run.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, NamedTuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
import field  # noqa: E402
import stamp  # noqa: E402
from grammars import _toml  # noqa: E402 - one TOML reader in this tree, not two

ROOT = Path(__file__).resolve().parents[1]
HOME = ROOT / "holdout"
MANIFEST = HOME / "holdout.toml"
LEDGER = HOME / "ledger.json"
VENDOR = HOME / "vendor"          # gitignored: the bytes, re-fetchable from the pins
SEATING = HOME / "oracle.json"    # which copy of each oracle answered, by digest
WORK = Path(os.environ.get("JOINTS_HOLDOUT", ROOT / ".local" / "generalize" / "holdout"))
BIN = Path(os.environ.get("JOINTS_BIN", ROOT / "zig-out" / "bin" / "joints"))

WANT = 20            # the size of the holdout, fixed by SELECTION.md
FLOOR, CEIL = 1024, 65536
SKIP_PREFIX = ("src/", "bindings/", "test/", "queries/", "node_modules/", "docs/", ".github/")
SKIP_INSIDE = ("/src/", "/test/", "/node_modules/", "/fixtures/")
SEAL = ("the seal: this gate prints aggregate per grammar and nothing finer. "
        "Diagnosing a holdout row is what destroys it — `holdout.py unseal <name> "
        "--reason \"…\"` is the only way, and it retires that grammar permanently.")


# ------------------------------------------------------------------- the pins

class Held(NamedTuple):
    """One sealed grammar: what to fetch, and the exact bytes to expect."""

    name: str
    repo: str
    commit: str
    location: str
    grammar_path: str
    grammar_sha256: str
    grammar_size: int
    source_path: str
    source_sha256: str
    source_size: int

    @property
    def grammar(self) -> Path:
        return VENDOR / "grammars" / f"{self.name}.json"

    @property
    def source(self) -> Path:
        return VENDOR / "sources" / self.name / Path(self.source_path).name

    @property
    def pin(self) -> field.Pin:
        owner, _, repo = self.repo.partition("/")
        return field.Pin(self.name, owner, repo, self.commit, self.location)

    def raw(self, inner: str) -> str:
        return blob(self.repo, self.commit, inner)


def manifest() -> list[Held]:
    if not MANIFEST.exists():
        return []
    got = _toml(MANIFEST.read_text())
    return [Held(**row) for row in got.get("grammar", [])]


def sealed() -> list[Held]:
    """The pins that are still sealed - the manifest minus everything spent."""
    spent = {e["grammar"] for e in ledger()["unsealed"]}
    return [h for h in manifest() if h.name not in spent]


def ledger() -> dict[str, Any]:
    if not LEDGER.exists():
        return {"unsealed": []}
    got = json.loads(LEDGER.read_text())
    got.setdefault("unsealed", [])
    return got


# --------------------------------------------------------------- github reach

def token() -> str:
    if tok := os.environ.get("GITHUB_TOKEN", ""):
        return tok
    got = subprocess.run(["gh", "auth", "token"], capture_output=True, text=True)
    return got.stdout.strip() if got.returncode == 0 else ""


def api(url: str) -> Any:
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json"})
    if tok := token():
        req.add_header("Authorization", f"Bearer {tok}")
    with urllib.request.urlopen(req, timeout=90) as r:  # noqa: S310 - https literal
        return json.loads(r.read())


def blob(repo: str, commit: str, inner: str) -> str:
    """A raw-content URL. Upstream paths carry `%`, `#`, and spaces; a path
    spliced in unquoted reads as an escape and the fetch 404s on a file that is
    demonstrably there."""
    return f"{field.RAW}/{repo}/{commit}/{urllib.parse.quote(inner)}"


def raw(url: str) -> bytes | None:
    try:
        with urllib.request.urlopen(url, timeout=90) as r:  # noqa: S310 - https literal
            return r.read()
    except (urllib.error.URLError, OSError):
        return None


# --------------------------------------------------------------- SELECTION.md

def types(pin: field.Pin) -> list[str]:
    """E4 - the file-type extensions the repository itself declares.

    Read from upstream's own `tree-sitter.json`, falling back to `package.json`.
    I do not get to decide what a `.rs` file is; if the grammar's own repository
    will not say, the grammar is ineligible and that is recorded.
    """
    for leaf, key in (("tree-sitter.json", "grammars"), ("package.json", "tree-sitter")):
        blob = raw(pin.raw(leaf))
        if blob is None:
            continue
        try:
            doc = json.loads(blob)
        except ValueError:
            continue
        rows = doc.get(key) or []
        out = [str(x).lstrip(".") for row in rows if isinstance(row, dict)
               for x in (row.get("file-types") or row.get("fileTypes") or [])]
        if out:
            return sorted(set(out))
    return []


def tree(pin: field.Pin) -> tuple[list[tuple[str, int]], str]:
    """Every blob in the repository at the pinned revision, with its size."""
    try:
        got = api(f"https://api.github.com/repos/{pin.slug}/git/trees/{pin.revision}?recursive=1")
    except (urllib.error.URLError, OSError) as e:
        return [], f"tree listing failed: {type(e).__name__}"
    if got.get("truncated"):
        return [], "tree listing truncated - E5"
    return [(n["path"], int(n.get("size") or 0))
            for n in got.get("tree", []) if n.get("type") == "blob"], ""


def candidates(paths: list[tuple[str, int]], exts: list[str], location: str,
               floor: int = FLOOR) -> list[tuple[str, int]]:
    """E6 - real source in the grammar's own repository. The rule, verbatim."""
    lead = f"{location}/" if location else ""
    out = []
    for path, size in paths:
        if location and not path.startswith(lead):
            continue
        inner = path[len(lead):]
        if not inner or inner.rsplit(".", 1)[-1] not in exts or "." not in inner:
            continue
        if not floor <= size <= CEIL:
            continue
        if inner.startswith(SKIP_PREFIX) or any(s in f"/{inner}" for s in SKIP_INSIDE):
            continue
        out.append((path, size))
    return out


def corpus_names() -> set[str]:
    """E3 - what the working corpus already holds, by folded name."""
    from grammars import load
    return {p.name.replace("_", "-") for p in load("all")}


def corpus_pins() -> set[tuple[str, str]]:
    from grammars import load
    return {(p.repo, p.path) for p in load("all")}


class Look(NamedTuple):
    pin: field.Pin
    ok: bool
    why: str
    exts: tuple[str, ...] = ()
    best: str = ""
    size: int = 0


def eligible(pin: field.Pin, names: set[str], pins: set[tuple[str, str]],
             floor: int = FLOOR) -> Look:
    """SELECTION.md's E2 .. E6, in the order it states them."""
    if pin.name.replace("_", "-") in names:
        return Look(pin, False, "E3: already in the working corpus, by name")
    if (pin.slug, pin.grammar_path) in pins:
        return Look(pin, False, "E3: already in the working corpus, by (repo, path)")
    paths, why = tree(pin)
    if why:
        return Look(pin, False, f"E5: {why}")
    if not any(p == pin.grammar_path for p, _ in paths):
        return Look(pin, False, "E2: no committed src/grammar.json at that revision")
    exts = types(pin)
    if not exts:
        return Look(pin, False, "E4: the repository declares no file-types")
    got = candidates(paths, exts, pin.location, floor)
    if not got:
        return Look(pin, False, f"E6: no candidate source file ({len(exts)} extension(s))")
    best = max(got, key=lambda pv: (pv[1], [-ord(c) for c in pv[0]]))
    return Look(pin, True, "", tuple(exts), best[0], best[1])


def select(patience: float = 0.0) -> int:
    """Run SELECTION.md and write the pins. Refuses to re-roll an existing one."""
    if MANIFEST.exists():
        print(f"holdout.py: {MANIFEST.relative_to(ROOT)} already exists. Re-running selection"
              " would re-roll the holdout, which is the one thing a holdout may never do."
              "\n            Delete it deliberately if you mean to start a new one.",
              file=sys.stderr)
        return 1
    names, pins = corpus_names(), corpus_pins()
    looked: list[Look] = []
    for i, pin in enumerate(field.roster()):
        looked.append(eligible(pin, names, pins))
        if (i + 1) % 25 == 0:
            print(f"  looked at {i + 1} …", file=sys.stderr)
        if patience:
            time.sleep(patience)
    fit = sorted((lk for lk in looked if lk.ok), key=lambda lk: lk.pin.name)
    if len(fit) < WANT:
        print(f"  only {len(fit)} eligible at the 1 KiB floor; dropping to 256 bytes once,"
              " exactly as SELECTION.md says in advance", file=sys.stderr)
        fit = sorted((lk for lk in (eligible(p, names, pins, 256) for p in field.roster())
                      if lk.ok), key=lambda lk: lk.pin.name)
    n = len(fit)
    take = [fit[(i * n) // WANT] for i in range(WANT)] if n >= WANT else fit
    rows: list[Held] = []
    for lk in take:
        gram = raw(lk.pin.raw("src/grammar.json"))
        src = raw(blob(lk.pin.slug, lk.pin.revision, lk.best))
        if gram is None or src is None:
            print(f"  {lk.pin.name}: bytes vanished between listing and fetch", file=sys.stderr)
            continue
        rows.append(Held(lk.pin.name, lk.pin.slug, lk.pin.revision, lk.pin.location,
                         lk.pin.grammar_path, hashlib.sha256(gram).hexdigest(), len(gram),
                         lk.best, hashlib.sha256(src).hexdigest(), len(src)))
    HOME.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(render(rows, looked, n))
    (HOME / "eligibility.json").write_text(json.dumps(
        [{"name": lk.pin.name, "ok": lk.ok, "why": lk.why, "repo": lk.pin.slug,
          "commit": lk.pin.revision, "best": lk.best, "size": lk.size} for lk in looked],
        indent=2))
    print(f"\n  {len(rows)} sealed of {n} eligible, out of {len(looked)} roster entries")
    print(f"  wrote {MANIFEST.relative_to(ROOT)} and holdout/eligibility.json")
    return 0


def render(rows: list[Held], looked: list[Look], fit: int) -> str:
    why: dict[str, int] = {}
    for lk in looked:
        if not lk.ok:
            why[lk.why.split(":")[0]] = why.get(lk.why.split(":")[0], 0) + 1
    head = [
        "# The sealed holdout. Twenty grammars nobody diagnoses against.",
        "#",
        "# Generated by `tool/holdout.py select`, which is",
        "# `research/generalize/SELECTION.md` as code. That document was written",
        "# BEFORE this file existed and is not edited to match it.",
        "#",
        f"# roster    {field.ROSTER_REPO}@{field.ROSTER_COMMIT}",
        f"#           {field.ROSTER_PATH}  sha256 {field.ROSTER_SHA}",
        f"# entries   {len(looked)} pinnable · {fit} eligible · {len(rows)} selected",
        "# rule      sort eligible names ascending, take floor(i * N / 20) for i in 0..19",
        "#",
        "# Why the rest fell out, by the condition that dropped them:",
        *[f"#   {k:<4} {n}" for k, n in sorted(why.items())],
        "#",
        "# DO NOT diagnose against these. `holdout/README.md` is the seal and",
        "# `holdout/ledger.json` records every time somebody spent one.",
        "",
        f'roster_repo = "{field.ROSTER_REPO}"',
        f'roster_commit = "{field.ROSTER_COMMIT}"',
        f'roster_sha256 = "{field.ROSTER_SHA}"',
        f"selected = {len(rows)}",
        "",
    ]
    for h in rows:
        head.append("[[grammar]]")
        for k, v in h._asdict().items():
            head.append(f"{k} = {v}" if isinstance(v, int) else f'{k} = "{v}"')
        head.append("")
    return "\n".join(head)


# -------------------------------------------------------------------- fetching

def fetch(rows: list[Held]) -> int:
    """Pinned bytes into the gitignored vendor tree, hash-checked on the way in."""
    (VENDOR / "grammars").mkdir(parents=True, exist_ok=True)
    bad = 0
    for h in rows:
        for want, dest, sha in ((h.grammar_path, h.grammar, h.grammar_sha256),
                                (h.source_path, h.source, h.source_sha256)):
            if dest.exists() and hashlib.sha256(dest.read_bytes()).hexdigest() == sha:
                continue
            blob = raw(h.raw(want))
            if blob is None:
                print(f"  none  {h.name:<16}{want}", file=sys.stderr)
                bad += 1
                continue
            got = hashlib.sha256(blob).hexdigest()
            if got != sha:
                print(f" DRIFT  {h.name:<16}{want}: {got[:16]} != pinned {sha[:16]}",
                      file=sys.stderr)
                bad += 1
                continue
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(blob)
    print(f"  {len(rows)} pinned · {bad} could not be resolved to their pinned bytes")
    return 1 if bad else 0


def scanner(h: Held, home: Path) -> str:
    """Lay this grammar's external scanner down beside its generated parser.

    Contained by construction: a monorepo grammar's home reproduces its own
    repository depth, so a shim's `#include "../../common/scanner.h"` resolves
    *inside* `lang/<name>/` rather than onto a path a sibling grammar also
    climbs to. `differential.py` learned this the expensive way - php's and
    typescript's headers are 18,018 and 10,097 different bytes at one path.
    """
    import differential as d
    root = WORK / "lang" / h.name
    for leaf in ("scanner.c", "scanner.cc", "scanner.cpp"):
        inner = f"{h.location}/src/{leaf}" if h.location else f"src/{leaf}"
        blob = raw(h.raw(inner))
        if blob is None:
            continue
        (home / "src").mkdir(parents=True, exist_ok=True)
        (home / "src" / leaf).write_bytes(blob)
        d.beside(h.raw(inner), home / "src", blob)
        loose = [p for p in root.rglob("*") if p.is_file() and root not in p.parents
                 and not str(p).startswith(str(root))]
        return f"escaped its own root: {loose[0]}" if loose else ""
    return ""


# ----------------------------------------------------------- the measurement

class Sealed(NamedTuple):
    """One holdout row, and there is nowhere in it to hide a diagnosis.

    This is the seal as a type. `judge()` below holds a `rack.Seen` carrying
    every crooked run with both parsers' node names and both byte offsets; it
    returns one of these and lets the rest go. A field added here that named a
    wall, a state or an offset would be the leak, and it would be visible in a
    diff of eleven lines.
    """

    name: str
    size: int
    built: int
    square: int
    crooked: int
    soft: int
    unframed: int
    unaudited: int
    graded: str      # read · part · none · void — about the ORACLE's reach, not our defect
    why: str = ""    # why there is no verdict, when there is none

    @property
    def measured(self) -> bool:
        return not self.why and self.built > 0 and self.graded in ("read", "part")

    @property
    def trued(self) -> float:
        return self.square / self.size if self.size else 0.0

    @property
    def splits(self) -> bool:
        """The board's five shares are disjoint and total `built`.

        The identity `square + crooked + soft + unframed + unaudited == built`
        is NOT this check. It holds by construction - `crooked` is written as
        `rack.crooked - soft` and `soft` is added straight back - so it cannot
        fail and asserting it proves nothing. I wrote it that way first and it
        flagged nothing while `crooked` was already negative on two rows.

        What can fail is the containment underneath: `soft` is sampled from
        `rack`'s widest RUNS, which include `unframed` ones, while `crooked` is
        `askew + racked` and excludes them. Subtract a population from a column
        it is not inside and the column goes negative. A negative `crooked` is
        that, and nothing else.
        """
        return self.crooked >= 0 and self.soft >= 0


def judge(h: Held, patience: float) -> Sealed:
    """One holdout row, measured through the board's own code path.

    `GRAMMARS` is rebound in three modules for the duration - `order` (which
    resolves a folio), `plumb` (which reads both trees) and `standing` (which
    reads a grammar's declared extras for the soft rule). Rebinding rather than
    copying, because a second copy of `built`, of the spine rule or of the soft
    rule is exactly the drift this tree has been bitten by six times.
    """
    import differential as d
    import order
    import plumb
    import rack
    import standing

    home = WORK / "lang" / h.name / h.location if h.location else WORK / "lang" / h.name
    keep = (order.GRAMMARS, plumb.GRAMMARS, standing.WORK, plumb.WORK, order.BIN, plumb.BIN)
    order.GRAMMARS = plumb.GRAMMARS = VENDOR / "grammars"
    standing.WORK = plumb.WORK = WORK / "folio"
    order.BIN = plumb.BIN = BIN
    plumb.PATIENCE = int(patience)
    def none(built: int, why: str, graded: str = "none") -> Sealed:
        return Sealed(h.name, h.source_size, built, 0, 0, 0, 0, 0, graded, why)

    try:
        if bad := scanner(h, home):
            return none(0, f"scanner {bad}")
        case = plumb.Case(h.name, h.grammar, home, h.source)
        try:
            if d.unbuilt(d.Case(h.name, h.grammar, home, h.source, "holdout")):
                with d.alone(h.name):
                    d.oracle_build(home, h.grammar)
        except (ValueError, OSError) as e:
            return none(0, f"oracle: {e}")
        try:
            saw = plumb.read(case)
        except (ValueError, OSError) as e:
            return none(0, f"oracle: {e}")
        # The oracle that just answered, recorded now that it exists. Consulting
        # before the build would name every row ABSENT on a cold run, and a line
        # that says ABSENT twenty times is not an attribution.
        COURT.append(case)
        witnessed(h.name, home)
        if saw is None:
            return none(0, "no folio, or no source")
        if saw.why or not saw.built:
            return none(saw.built, saw.why or "nothing built", "void" if not saw.built else "none")
        return score(h.name, h.source_size, saw, extras(h))
    finally:
        (order.GRAMMARS, plumb.GRAMMARS, standing.WORK,
         plumb.WORK, order.BIN, plumb.BIN) = keep


def score(name: str, size: int, saw: Any, was: set[str]) -> Sealed:
    """`standing.audit`'s arithmetic, once, for both sides of the comparison.

    The holdout number and the corpus number it is quoted beside come out of
    this function on the same run, off the same binary and the same oracle. A
    corpus figure copied from a report written yesterday is not a comparison:
    the board's own `square` for php read 19,016 in the cached audit and 662
    off `rack board` an hour later, so a gap measured against the cached one
    would be measuring `rack`'s repair.
    """
    import rack
    seen = rack.survey(name, saw, top=1 << 20)
    # `standing.audit`'s soft rule, at run granularity, read off `standing`
    # rather than restated. A cut-level test calls the leading spaces of a
    # non-blank run soft and quietly shrinks the number this subtracts.
    soft = sum(w.width for w in seen.worst
               if not saw.blob[w.start:w.end].strip() or w.ours in was or w.theirs in was)
    unaudited = seen.unjudged + seen.unwindowed
    graded = "part" if unaudited * 2 > saw.built else "read"
    return Sealed(name, size, saw.built, seen.square + seen.renamed,
                  seen.crooked - soft, soft, seen.unframed, unaudited, graded)


def extras(h: Held) -> set[str]:
    """The extras this grammar declares, for the soft rule."""
    try:
        doc = json.loads(h.grammar.read_text())
    except (OSError, ValueError):
        return set()
    return {x.get("name", "") for x in doc.get("extras", []) if isinstance(x, dict)}


def beside(patience: float) -> tuple[list[Sealed], float]:
    """The working corpus, scored by `score()` on this run. The other number.

    Reading it rather than quoting it is the whole point. `50.4% trued` is on
    the board and in the brief; `rack` is being repaired underneath both, and
    the gap between two numbers taken on different days off a moving oracle is
    not an estimate of generalisation, it is an estimate of the repair.

    The corpus folios are read into this lane's own directory rather than the
    shared one, so ten agents' caches are not raced for a number none of them
    asked for.
    """
    import plumb
    keep = (plumb.WORK, plumb.BIN, plumb.PATIENCE)
    plumb.WORK, plumb.BIN, plumb.PATIENCE = WORK / "corpus", BIN, int(patience)
    out: list[Sealed] = []
    try:
        for case in plumb.slate():
            size = case.source.stat().st_size if case.source.exists() else 0
            try:
                saw = plumb.read(case)
            except (ValueError, OSError) as e:
                out.append(Sealed(case.name, size, 0, 0, 0, 0, 0, 0, "none", f"oracle: {e}"))
                continue
            if saw is None or saw.why or not saw.built:
                why = "no folio, or no source" if saw is None else (saw.why or "nothing built")
                built = 0 if saw is None else saw.built
                out.append(Sealed(case.name, size, built, 0, 0, 0, 0, 0,
                                  "void" if not built else "none", why))
                continue
            COURT.append(case)
            witnessed(case.name, case.lang)
            out.append(score(case.name, size, saw, corpus_extras(case.grammar)))
    finally:
        plumb.WORK, plumb.BIN, plumb.PATIENCE = keep
    live = [r for r in out if r.measured]
    size = sum(r.size for r in live)
    return out, (sum(r.square for r in live) / size if size else 0.0)


def corpus_extras(grammar: Path) -> set[str]:
    try:
        doc = json.loads(grammar.read_text())
    except (OSError, ValueError):
        return set()
    return {x.get("name", "") for x in doc.get("extras", []) if isinstance(x, dict)}


def gate(rows: list[Held], patience: float, as_json: bool, versus: bool = False) -> int:
    mark = stamp.take(BIN)
    got = [judge(h, patience) for h in rows]
    live = [r for r in got if r.measured]
    size = sum(r.size for r in live)
    square = sum(r.square for r in live)
    trued = square / size if size else 0.0
    if as_json:
        print(json.dumps({"rows": [r._asdict() for r in got], "trued": round(trued, 4),
                          "measured": len(live), "sealed": len(rows),
                          "stamp": mark.as_dict(), "oracle": told(), "seal": SEAL}, indent=2))
        return 0
    print(f"\n  the sealed holdout — {len(rows)} grammar(s), {len(live)} with a live verdict\n")
    print(f"  {'grammar':<20}{'size':>8}{'built':>8}{'square':>8}{'crooked':>9}{'soft':>7}"
          f"{'unframed':>9}{'unaud':>8}{'trued':>8}  graded")
    print(f"  {'-' * 93}")
    for r in sorted(got, key=lambda r: r.name):
        if not r.measured:
            print(f"  {r.name:<20}{r.size:>8}{'':>57}  {r.graded:<5} {r.why[:34]}")
            continue
        print(f"  {r.name:<20}{r.size:>8}{r.built:>8}{r.square:>8}{r.crooked:>9}{r.soft:>7}"
              f"{r.unframed:>9}{r.unaudited:>8}{r.trued * 100:>7.1f}%  {r.graded}"
              + ("  ← SPLIT BROKEN" if not r.splits else ""))
    print(f"  {'-' * 93}")
    print(f"  {'TRUED':<20}{size:>8}{sum(r.built for r in live):>8}{square:>8}"
          f"{sum(r.crooked for r in live):>9}{sum(r.soft for r in live):>7}"
          f"{sum(r.unframed for r in live):>9}"
          f"{sum(r.unaudited for r in live):>8}{trued * 100:>7.1f}%")
    if dead := [r for r in got if not r.measured]:
        print(f"\n  {len(dead)} produced no verdict and are in NEITHER the numerator nor the"
              " denominator.\n  Absence is its own outcome here; it is never a zero.")
    if off := [r for r in live if not r.splits]:
        print(f"\n  {len(off)} of {len(live)} rows carry a NEGATIVE `crooked` —"
              f" {', '.join(r.name for r in off)}.\n"
              "  The board's soft rule subtracts a sample of `rack`'s widest RUNS from"
              " `askew + racked`,\n  and those runs include `unframed` ones, which are in"
              " neither: soft is drawn from a\n  population wider than the column it is"
              " taken out of. `trued` is unaffected — it is\n  `square / size` and never"
              " reads `crooked`. The shape crosses the seal; no witness does.")
    if versus:
        rest, corpus = beside(patience)
        alive = [r for r in rest if r.measured]
        print(f"\n  beside it, ON THIS RUN — the working corpus through the same `score()`,"
              f" the same\n  binary and the same oracle: {corpus * 100:.1f}% trued over"
              f" {len(alive)} of {len(rest)} rows"
              f" ({sum(r.size for r in alive)} bytes).")
        if gone := [r for r in rest if not r.measured]:
            print("  corpus rows with no verdict, out of both sides of that fraction: "
                  + ", ".join(f"{r.name} ({r.why[:22]})" for r in gone))
        print(f"  holdout {trued * 100:.1f}% · corpus {corpus * 100:.1f}% ·"
              f" gap {(corpus - trued) * 100:.1f} points"
              + (f" · holdout is {trued / corpus:.2f}× the corpus" if corpus else ""))
        # The same two numbers under the harsher denominator, where a row nobody
        # could measure is charged as zero rather than set aside. Printed because
        # the choice moves the gap by ten points and a reader who is not shown
        # both is being handed the framing, not the measurement.
        hb, hs = sum(r.size for r in got), sum(r.square for r in live)
        cb, cs = sum(r.size for r in rest), sum(r.square for r in alive)
        print(f"  charging the unmeasurable as zero instead: holdout {hs / hb * 100:.1f}%"
              f" · corpus {cs / cb * 100:.1f}% · gap {(cs / cb - hs / hb) * 100:.1f} points")
        # The class that separates the two populations, taken from the same run
        # as the headline rather than from a second instrument's report. These
        # bytes agree with the oracle rung for rung UNDER A PARENT WE NEVER
        # BUILT, which every column older than this week reads as clean.
        hu, hbuilt = sum(r.unframed for r in live), sum(r.built for r in live)
        cu, cbuilt = sum(r.unframed for r in alive), sum(r.built for r in alive)
        print(f"  built bytes under a frame we never built: holdout"
              f" {hu}/{hbuilt} ({hu / hbuilt * 100:.1f}%)"
              f" · corpus {cu}/{cbuilt} ({cu / cbuilt * 100:.1f}%)")
        sour = [r for r in alive if not r.splits]
        print(f"  negative `crooked`: {len(off)} of {len(live)} holdout rows,"
              f" {len(sour)} of {len(alive)} corpus rows"
              + (f" ({', '.join(r.name for r in sour)})" if sour else ""))
    # Asked last, so it names every oracle that answered rather than the ones
    # that had answered by the time the header was formatted.
    print(f"\n  {told()}")
    # Which copy answered. `attest` seats the oracle on its SOURCES, and on this
    # disk a grammar is not one thing: several of these exist as two or three
    # different source trees at once, and the divergence is not cosmetic. The
    # digest is the version; the path never was.
    forked = {n: c for n in SEEN for c in [copies(n, SEEN[n][1])] if len(c) > 1}
    print(f"  oracle: seated on sources, {len(SEEN)} row(s) recorded by digest"
          f" → {stamp.here(SEATING)}")
    if forked:
        print(f"  oracle: FORKED - {len(forked)} of {len(SEEN)} grammars exist as more than"
              f" one source tree on this\n          disk. The digest above is the copy that"
              f" answered; the others were not read: "
              + ", ".join(f"{n} ({len(c)})" for n, c in sorted(forked.items())[:8])
              + (f" (+{len(forked) - 8} more)" if len(forked) > 8 else ""))
    seated(SEATING)
    hazard = " ".join(k.upper() for k in ("told", "stale", "drift", "moved")
                      if mark.as_dict().get(k))
    print(f"  stamp: tree {mark.tree[:12]} · binary {mark.build[:12]} · {hazard or 'no hazard'}")
    print(f"\n  {SEAL}")
    return 0


COURT: list[Any] = []
# Which copy answered, by digest, captured at the instant each row was read
# rather than at the end of the run. `attest.court` surveys the disk when it is
# called, so a single call at the foot of a report attributes the measurement
# to whatever the bytes became - which is the same error as reading a folio's
# mtime and calling it a version. name -> (oracle src/ tree digest, home).
SEEN: dict[str, tuple[str, str, str]] = {}


def witnessed(name: str, home: Path) -> None:
    """Record which copy of this grammar's oracle just answered.

    Called immediately after the row is read, inside the same shared lock the
    read held, so what is recorded is what was consulted. Two digests, because
    two things can go wrong and one number cannot tell them apart.
    `attest.survey` is the **authored** bytes - grammar json, external scanner,
    the headers it climbs to - which is the language this row was graded
    against; `attest.built` is what `tree-sitter generate` wrote from them,
    which is the parser that actually ran. A *library* digest answers neither:
    two of scala's four libraries differ in 52 bytes of Mach-O UUID and are the
    same parser.
    """
    try:
        import attest
        got, *_ = attest.survey(home)
        if got:
            SEEN[name] = (got, stamp.here(home), attest.built(home)[0])
    except (ImportError, OSError):
        pass


def copies(name: str, home: str) -> list[str]:
    """Every distinct oracle source tree for this grammar on this disk.

    Not a count of directories - a count of *contents*. The hazard is not that
    a grammar is checked out twice, it is that the two are different parsers
    and nothing recorded which one a number came from. Returns the digests,
    the one that answered first.
    """
    try:
        import attest
    except ImportError:
        return []
    got: dict[str, None] = {}
    for p in (ROOT / ".local").rglob(f"lang/{name}"):
        if not p.is_dir():
            continue
        for src in p.rglob("src"):
            if src.is_dir() and (d := attest.survey(src.parent)[0]):
                got[d] = None
    here = SEEN.get(name, ("", home))[0]
    return ([here] if here in got else []) + [g for g in got if g != here]


def told() -> str:
    """Which oracle answered. Half of every number above, and it moves.

    28 of the 29 compiled oracles on this machine exist as several different
    files at once, and the same script has read one grammar at 1,278 crooked in
    one run and 9,087 in the next off a byte-identical stamp, because a sibling
    rebuilt the library underneath it. A number whose oracle is unnamed is not a
    measurement, so a failure to name it says so rather than staying quiet.

    Two attributions, because they answer different questions. `attest.court`
    is the identity of the oracle **as it stands now**; `SEEN` is what each row
    was actually read against, captured row by row. When they disagree, a
    sibling rebuilt something mid-run and the aggregate above is a number off
    two different parsers - which is exactly the failure this file exists to
    make impossible to publish quietly.
    """
    if not COURT:
        return "oracle: NOT RECORDED - nothing was read, so nothing answered"
    try:
        import attest
        attest.consult(COURT)
        out = [attest.told().replace("\n", "\n  ")]
        now = {r.name: r.tree for r in attest.SEATED.rows} if attest.SEATED else {}
        if moved := [n for n, (was, _, _) in SEEN.items()
                     if n in now and now[n] and now[n] != was]:
            out.append(f"oracle: MOVED MID-RUN - {len(moved)} oracle(s) are not the bytes"
                       f" the row above was read against: {', '.join(sorted(moved)[:6])}"
                       + (f" (+{len(moved) - 6} more)" if len(moved) > 6 else "")
                       + "\n          Those rows are not attributable and the aggregate"
                         " is off two parsers.")
        return "\n  ".join(out)
    except (ImportError, AttributeError, OSError) as e:
        return f"oracle: NOT RECORDED ({type(e).__name__}) - half of every number above"


def seated(where: Path) -> int:
    """Write the per-row oracle attribution beside the numbers it belongs to.

    A path is not a version. This file is what lets a cold run months from now
    prove it read the same bytes, and it is per row rather than per run,
    because the run digest is an aggregate and an aggregate cannot say *which*
    grammar's copy moved.
    """
    try:
        import attest
        cli = attest.oracle_cli()
        seen = attest.SEATED
    except (ImportError, OSError):
        cli, seen = "(unknown)", None
    book = {
        "when": stamp.iso(time.time()),
        "cli": cli,
        "oracle": seen.digest[:12] if seen else "",
        "seat": next((r.seat for r in seen.rows), "") if seen else "",
        "binary": stamp.take(BIN).build[:12],
        # `lower` beside `tree` rather than folded into it: the identity says
        # which language this row was graded against and the other says which
        # generated parser ran, and a cold reader months from now needs both to
        # tell a torn oracle from one that was simply rebuilt.
        "row": {n: {"tree": got, "lower": low, "home": home,
                    "distinct_on_disk": len(copies(n, home))}
                for n, (got, home, low) in sorted(SEEN.items())},
    }
    where.write_text(json.dumps(book, indent=2) + "\n", encoding="utf-8")
    return len(book["row"])


# ------------------------------------------------------------------ the seal

def unseal(name: str, reason: str) -> int:
    """Spend one, forever. There is no verb that puts it back."""
    if not reason.strip():
        return oops("an unsealing without a reason is exactly what the ledger exists to prevent")
    live = {h.name for h in sealed()}
    if name not in live:
        known = {h.name for h in manifest()}
        return oops(f"{name} is not sealed"
                    + (" — it was already spent; see holdout/ledger.json" if name in known
                       else f". Sealed today: {', '.join(sorted(live))}"))
    got = ledger()
    got["unsealed"].append({
        "grammar": name, "reason": reason.strip(), "when": stamp.iso(time.time()),
        "by": os.environ.get("JOINTS_LANE", os.environ.get("USER", "unknown")),
        "left": len(live) - 1,
    })
    LEDGER.write_text(json.dumps(got, indent=2))
    print(f"\n  {name} is retired from the holdout, permanently.")
    print(f"  reason: {reason.strip()}")
    print(f"  the holdout is now {len(live) - 1}, was {len(live)}.")
    print(f"  recorded in {stamp.here(LEDGER)}. There is no verb that undoes this.")
    return 0


def doubt(rows: list[Held], patience: float, as_json: bool) -> int:
    """Scatter my own labels and see whether the gap survives.

    The instrument I trust least in this lane is the **gap itself** - one
    number subtracted from another over two samples of twenty and thirty. It
    is the deliverable, it has no error bar anywhere in the tree, and every
    reading of it in `RESULT-2` treats 26.7 points as a fact about the parser.

    So: pool all forty-five measured rows, forget which side each came from,
    and re-split them at random into a group the holdout's size and a group
    the corpus's size, ten thousand times. Each split gets the same
    byte-weighted `trued` on both halves and the same subtraction. If a random
    partition of the same rows routinely produces a gap this wide, then the gap
    is a fact about grammars varying and not about which twenty nobody tuned
    against, and this whole lane measured its own sampling noise.

    A permutation is the honest null here because the rows are not
    exchangeable *bytes* - they are exchangeable *grammars*, weighted by their
    own file sizes, which is exactly how both headline numbers are computed.
    """
    import random
    got = [judge(h, patience) for h in rows]
    rest, _ = beside(patience)
    rolls = 10000

    def rate(part: list[Sealed]) -> float:
        n = sum(r.size for r in part)
        return sum(r.square for r in part) / n if n else 0.0

    def shake(mine: list[Sealed], theirs: list[Sealed]) -> tuple:
        """Observed gap, and where it falls in the null of random re-splits."""
        pool, k = mine + theirs, len(mine)
        real = rate(theirs) - rate(mine)
        rng = random.Random(0xA11CE)  # fixed, so the p-value is a fact, not a draw
        null = []
        for _ in range(rolls):
            deck = pool[:]
            rng.shuffle(deck)
            null.append(rate(deck[k:]) - rate(deck[:k]))
        wide = sum(1 for g in null if abs(g) >= abs(real))
        null.sort()
        return real, wide / rolls, wide, null, rate(theirs), rate(mine)

    # Both framings the gate prints. If the headline is only significant under
    # the one that discards rows, it is a framing and not a finding.
    ways = {"absence set aside": ([r for r in got if r.measured],
                                  [r for r in rest if r.measured]),
            "absence charged as zero": (got, rest)}
    if min(len(m) for m, _ in ways.values()) < 2:
        return oops("not enough measured rows on one side to permute")
    done = {name: shake(m, t) for name, (m, t) in ways.items()}

    if as_json:
        print(json.dumps({name: {"gap": round(real, 4), "p": round(p, 4),
                                 "corpus": round(c, 4), "holdout": round(h, 4),
                                 "null_p05": round(null[rolls // 20], 4),
                                 "null_p50": round(null[rolls // 2], 4),
                                 "null_p95": round(null[rolls * 19 // 20], 4)}
                          for name, (real, p, _, null, c, h) in done.items()}
                         | {"rolls": rolls}, indent=2))
        return 0

    n = len(got) + len(rest)
    print(f"\n  the gap, doubted — the {n} rows pooled, labels forgotten, and"
          f" re-split at random {rolls} times")
    for name, (real, p, wide, null, c, h) in done.items():
        print(f"\n  {name}")
        print(f"    observed gap               {real * 100:>7.1f} points"
              f"   (corpus {c * 100:.1f}% − holdout {h * 100:.1f}%)")
        print(f"    null  5th / 50th / 95th    {null[rolls // 20] * 100:>7.1f}"
              f" / {null[rolls // 2] * 100:.1f} / {null[rolls * 19 // 20] * 100:.1f}")
        print(f"    splits at least this wide  {wide:>7} of {rolls}   p = {p:.4f}")
    worst = max(p for _, p, _, _, _, _ in done.values())
    print(f"\n  {'the gap is not what a random partition of these grammars produces.'
                if worst < 0.05 else
                f'a random partition produces a gap this wide up to {worst * 100:.0f}%'
                ' of the time. The gap is NOT distinguishable from grammars varying;'
                '\n  twenty rows cannot resolve a difference this size.'}")
    print("\n  This tests one thing only: whether the split is doing work. It cannot"
          "\n  tell a harder holdout from an overfitted corpus — both produce the same"
          "\n  p-value, and the selection rule is the only argument that it is the second.")
    return 0


def forked(name: str, patience: float, as_json: bool) -> int:
    """Score one corpus grammar against **each** copy of its oracle on this disk.

    The claim under test is not "two directories exist". It is that the copies
    are different *parsers*, and therefore that a corpus number is a number per
    copy while nothing was recording which one answered. A count of directories
    cannot show that and neither can a digest; only re-reading the same file
    against each copy can.

    Everything except the oracle is held fixed: same grammar.json handed to
    joints, same source bytes, same binary, same `score()`. Each copy gets
    its own seat, so the two compiled libraries cannot collide on one name in
    one libdir - which is the quiet way this comparison would otherwise measure
    itself.

    **`oracle_build` is stood down for the duration, and that is the whole
    correctness of this verb.** `plumb.read` calls it, and it overwrites a
    copy's `src/grammar.json` with the one it was handed whenever the two
    digests differ, then regenerates `parser.c` from it. Left in, it normalises
    every copy to the same grammar before reading it, and the comparison
    reports that the copies agree - which they do, *after* being made
    identical. The first run of this function did exactly that across fourteen
    grammars and printed a spread of zero on all of them; the tell was on disk,
    where thirteen of the fourteen differ in `grammar.json` itself. A copy that
    cannot answer without being generated is reported as unable to answer,
    because generating it is the normalisation.

    Nothing shared is written. The copies are read out of `.local`, staged into
    this lane's own scratch, and compiled into this lane's own libdir; no other
    lane's seat, cache or source tree is touched.
    """
    import attest
    import differential as d
    import plumb
    case = next((c for c in plumb.slate() if c.name == name), None)
    if case is None:
        return oops(f"{name} is not a working-corpus grammar; `beside` reads "
                    f"{len(plumb.slate())} of them")
    got: dict[str, Path] = {}
    for p in (ROOT / ".local").rglob(f"lang/{name}"):
        for src in p.rglob("src") if p.is_dir() else []:
            if src.is_dir() and (dig := attest.survey(src.parent)[0]) and dig not in got:
                got[dig] = src.parent
    if len(got) < 2:
        return oops(f"{name} has {len(got)} oracle source tree(s) on this disk;"
                    " this verb needs two to compare")

    keep = (plumb.WORK, plumb.BIN, plumb.PATIENCE, d.SEAT, d.LIB, d.oracle_build)
    plumb.WORK, plumb.BIN, plumb.PATIENCE = WORK / "fork" / name, BIN, int(patience)
    d.oracle_build = lambda lang, want: None  # see the docstring; this IS the verb
    out = []
    try:
        for dig, home in sorted(got.items()):
            pen = WORK / "fork" / name / dig[:9]
            root, at = attest.split(home)
            stage = pen / "lang" / name
            if not (stage / at / "src").is_dir():
                stage.parent.mkdir(parents=True, exist_ok=True)
                with d.alone(name, writing=False):
                    shutil.copytree(root, stage, dirs_exist_ok=True,
                                    copy_function=shutil.copy2)
            # Its own seat, so this copy's library cannot be the other's.
            d.SEAT, d.LIB = pen / "seat", pen / "seat" / "lib"
            d.LIB.mkdir(parents=True, exist_ok=True)
            lang = stage / at
            here = plumb.Case(name, case.grammar, lang, case.source)
            try:
                saw = plumb.read(here)
            except (ValueError, OSError) as e:
                out.append((dig, stamp.here(home), None, f"oracle: {e}"))
                continue
            if saw is None or saw.why or not saw.built:
                out.append((dig, stamp.here(home), None,
                            (saw.why if saw else None) or "nothing built"))
                continue
            out.append((dig, stamp.here(home),
                        score(name, case.source.stat().st_size, saw,
                              corpus_extras(case.grammar)), ""))
    finally:
        plumb.WORK, plumb.BIN, plumb.PATIENCE, d.SEAT, d.LIB, d.oracle_build = keep

    if as_json:
        print(json.dumps({"grammar": name, "source": stamp.here(case.source),
                          "copies": [{"tree": dig, "home": home,
                                      "row": r._asdict() if r else None, "why": why}
                                     for dig, home, r, why in out]}, indent=2))
        return 0
    print(f"\n  {name} — the same {case.source.stat().st_size} source bytes and the same"
          f" grammar.json,\n  read against each of the {len(out)} oracle source trees on"
          " this disk\n")
    print(f"  {'oracle (src/ digest)':<24}{'built':>8}{'square':>8}{'unframed':>10}"
          f"{'trued':>8}  where")
    print(f"  {'-' * 88}")
    for dig, home, r, why in out:
        if r is None:
            print(f"  {dig[:20]:<24}{'':>34}  {home}   {why[:30]}")
            continue
        print(f"  {dig[:20]:<24}{r.built:>8}{r.square:>8}{r.unframed:>10}"
              f"{r.trued * 100:>7.1f}%  {home}")
    live = [r for _, _, r, _ in out if r is not None]
    if len(live) < 2:
        print("\n  fewer than two copies produced a verdict; nothing to compare.")
        return 0
    spread = max(r.trued for r in live) - min(r.trued for r in live)
    print(f"\n  {'THE SAME FILE READS' if spread else 'the copies agree:'}"
          f" {spread * 100:.1f} points apart depending on which copy answered."
          if spread else
          f"\n  the copies agree: identical `trued` from {len(live)} different source trees.")
    if spread:
        print("  A corpus number is therefore a number PER COPY, and until `oracle.json`"
              "\n  nothing recorded which one any published figure came from.")
    else:
        print("  Same parser, different bytes — which is why the digest is recorded and"
              "\n  the disagreement, not the digest, is what would have mattered.")
    return 0


def thin(rows: list[Held], as_json: bool) -> int:
    """`absent.py`'s question, asked of the holdout: how much of what these
    grammars can spell do these twenty files actually contain?

    The corpus presents 39.4% of its declared spellings, and a holdout whose
    files present LESS than that is a weaker test than its size suggests - the
    gap would then be partly a thinner sample rather than a worse parser. This
    is the number that says which. `absent`'s reader is rebound at `GRAMMARS`
    and otherwise untouched; a second copy of its literal walk would drift from
    the one the corpus figure came out of, which is the entire failure mode.
    """
    import absent
    keep = absent.GRAMMARS
    absent.GRAMMARS = VENDOR / "grammars"
    try:
        got = [absent.read(h.name, h.source, ()) for h in rows if h.source.exists()]
    finally:
        absent.GRAMMARS = keep
    lits = sum(r.judgeable for r in got)
    seen = sum(r.seen for r in got)
    ext = sum(r.unspelled for r in got)
    share = seen / lits if lits else 0.0
    if as_json:
        print(json.dumps({"grammars": len(got), "judgeable": lits, "present": seen,
                          "share": round(share, 4), "unspelled_externals": ext,
                          "row": [{"name": r.grammar, "judgeable": r.judgeable,
                                   "present": r.seen, "externals": r.unspelled}
                                  for r in got]}, indent=2))
        return 0
    print(f"\n  what the HOLDOUT does not contain — {len(got)} file(s), read with no parser\n")
    print(f"  {'grammar':<20}{'spelled':>9}{'present':>9}{'share':>8}{'ext':>6}")
    print(f"  {'-' * 52}")
    for r in sorted(got, key=lambda r: r.seen / r.judgeable if r.judgeable else 0):
        s = r.seen / r.judgeable if r.judgeable else 0.0
        print(f"  {r.grammar:<20}{r.judgeable:>9}{r.seen:>9}{s * 100:>7.1f}%{r.unspelled:>6}")
    print(f"  {'-' * 52}")
    print(f"  {'ALL':<20}{lits:>9}{seen:>9}{share * 100:>7.1f}%{ext:>6}")
    print(f"\n  the working corpus presents 39.4% of its 5,198 declared spellings."
          f" This holdout\n  presents {share * 100:.1f}% of {lits}. A holdout that presents"
          " LESS is a thinner sample, and\n  part of any gap in `trued` is that thinness"
          " rather than the parser.")
    print(f"\n  {ext} declared external(s) here have no body in `grammar.json` at all —"
          "\n  their spelling lives in a C scanner and this reader cannot see one of them.")
    return 0


def status(as_json: bool) -> int:
    all_, live, spent = manifest(), sealed(), ledger()["unsealed"]
    if as_json:
        print(json.dumps({"selected": len(all_), "sealed": len(live), "spent": spent}, indent=2))
        return 0
    print(f"\n  selected {len(all_)} · sealed {len(live)} · spent {len(spent)}\n")
    for h in sorted(live, key=lambda h: h.name):
        print(f"  {h.name:<20}{h.repo:<44}{h.commit[:9]}  {h.source_size:>7} bytes")
    for e in spent:
        print(f"  {e['grammar']:<20}SPENT {e['when']}  {e['by']:<10}{e['reason'][:40]}")
    print(f"\n  {SEAL}")
    return 0


def smuggle(rows: list[Held], sabotage: bool = False) -> list[tuple[bool, str]]:
    """Try to carry a witness across the seal, and fail.

    The smallest sealed source is measured for real. `rack.survey` is wrapped
    for the duration so this function - and nothing downstream of it - holds
    the disagreeing runs: node names on both sides, byte offsets on both sides.
    Then both of the gate's channels are rendered for that one grammar and
    searched for every one of them.

    A witness is a thing you could act on. The row's own name and size are not
    witnesses and are excluded from the search: a check that fails on those
    fails always, and a check that cannot pass says as little as one that
    cannot fail.

    The rows are walked smallest first and the walk stops at the first one that
    actually disagrees with the oracle somewhere. A row that agrees everywhere
    has no witness to smuggle, and running the search over it would report a
    pass that means nothing.
    """
    import io
    import contextlib
    import rack
    if not rows:
        return [(False, "no manifest, so the leak attempt had nothing to smuggle")]

    def render(h: Held) -> str:
        """Both of the gate's channels for one row, as one string."""
        pen = io.StringIO()
        with contextlib.redirect_stdout(pen), contextlib.redirect_stderr(io.StringIO()):
            gate([h], 600.0, False)
            gate([h], 600.0, True)
        return pen.getvalue()

    empty: list[str] = []
    for small in sorted(rows, key=lambda h: h.source_size)[:6]:
        caught: list[Any] = []
        real = rack.survey

        def wrapped(*a: Any, _real: Any = real, _at: list[Any] = caught, **k: Any) -> Any:
            got = _real(*a, **k)
            _at.append(got)
            return got

        rack.survey = wrapped
        try:
            said = render(small)
            # `sabotage` is the detector's own tripwire: one witness is stapled
            # to the gate's output and the search below must find it. A leak
            # test that has never been shown failing is a green light with no
            # bulb in it, and two of this one's earlier versions were exactly
            # that.
            if sabotage and caught and caught[0].worst:
                said += f"\n  leak: {caught[0].worst[0].ours} at {caught[0].worst[0].start}\n"
        finally:
            rack.survey = real
        if not caught:
            empty.append(f"{small.name} (no verdict)")
            continue
        seen = caught[0]
        names = {w.ours for w in seen.worst} | {w.theirs for w in seen.worst} - {""}
        marks = {str(w.start) for w in seen.worst} | {str(w.end) for w in seen.worst}
        # Every integer the row is ENTITLED to print. A byte offset that happens
        # to equal one of them is a collision between two numbers, not a channel
        # - the reader cannot tell it apart from the aggregate it collided with,
        # and there are only so many small integers. Subtracting them is the
        # difference between a leak test and a birthday-paradox detector; the
        # first version of this check did not, and reported a leak on a `941`.
        mine = {str(v) for v in judge(small, 600.0) if isinstance(v, int)}
        marks -= mine | {small.name}
        names -= {small.name}
        if not (names | marks):
            empty.append(f"{small.name} (agrees everywhere)")
            continue
        # The control. The same gate over the same row with every measured value
        # blanked, so anything the two renders share is the TEMPLATE and cannot
        # have been carried by this row. Without it a node spelled `source` or
        # `name` reads as a leak because the column headings contain those
        # letters - which is what the first run of this check reported, and it
        # was wrong. What is left is what only the measurement could have put
        # there.
        keep, globals()["judge"] = judge, lambda h, _p: Sealed(h.name, h.source_size, 0, 0,
                                                               0, 0, 0, 0, "read")
        try:
            base = render(small)
        finally:
            globals()["judge"] = keep
        loud = sorted(n for n in names if n in said and n not in base)
        seep = sorted(m for m in marks if m in said and m not in base)
        if sabotage:
            return [(bool(loud or seep),
                     f"and the detector is not blind: one witness stapled to the gate's own"
                     f" output is found ({len(loud)} name(s), {len(seep)} offset(s))")]
        return [(not (loud or seep),
                 f"{len(names)} node name(s) and {len(marks)} byte offset(s) held beside the"
                 f" gate for one sealed row; {len(loud)} name(s) and {len(seep)} offset(s)"
                 f" reached its output over the human and --json channels"
                 + (f", after {len(empty)} row(s) with nothing to smuggle" if empty else ""))]
    return [(False, "the leak attempt found no sealed row with a witness to carry: "
                    + ", ".join(empty))]


def swapped() -> list[tuple[bool, str]]:
    """Move one byte of a generated `parser.c` and show the attribution moves.

    This is the hazard the copy survey cannot close by itself. `oracle_build`
    regenerates only when the handed `grammar.json` and the one on disk have
    different digests; it never asks whether the `parser.c` beside them was
    generated from *that* grammar. So a source tree carrying a stale generated
    parser answers with a different language and every freshness check in the
    stack reads clean.

    Nothing shared is touched: a scratch copy of one oracle's `src/` is made in
    a tmpdir and the byte is moved there. The claim under test is only that
    what `oracle.json` records per row is sensitive to it, and the control is
    that an untouched copy digests the same twice, so a sensor that simply
    returns a fresh number every call cannot pass this pair.

    **The digest this reads moved on 2026-08-05 and the claim did not.**
    `attest.survey` used to fold `parser.c` into the oracle's identity, so a
    torn tree and an ordinary rebuild produced the same signal and two grammars
    on this machine read as two parsers because one copy had been generated and
    the other had not. Generated files are now `attest.built`, a second digest
    recorded beside the first, and this pair asks it the same question with one
    row added: the identity must **not** move, because a stale `parser.c` under
    a correct `grammar.json` is a torn tree and not a different language, and a
    single number that answered both was how the distinction got lost.
    """
    import shutil as sh
    import tempfile
    try:
        import attest
    except ImportError:
        return [(False, "attest is not importable, so nothing attributes the oracle")]
    # The language HOME - the directory holding `src/` - because that is what
    # `attest.survey` digests. Handing it `src/` itself reads an empty tree and
    # the pair below would then pass on two digests of nothing.
    home = next((p.parent.parent for p in (ROOT / ".local").rglob("lang/*/src/parser.c")
                 if p.is_file()), None)
    if home is None:
        return [(False, "no generated parser.c anywhere, so the swap had nothing to move")]
    with tempfile.TemporaryDirectory() as tmp:
        pen = Path(tmp) / home.name
        sh.copytree(home, pen, copy_function=sh.copy2)
        was, made = attest.survey(pen)[0], attest.built(pen)[0]
        again = attest.survey(pen)[0]
        gen = pen / "src" / "parser.c"
        blob = bytearray(gen.read_bytes())
        # A state-table byte, not a comment: the far end of the file, where the
        # generated tables live rather than the banner.
        at = int(len(blob) * 0.9)
        blob[at] = (blob[at] + 1) % 256
        gen.write_bytes(bytes(blob))
        now, torn = attest.survey(pen)[0], attest.built(pen)[0]
    return [
        (bool(was), "the swap had a real oracle to move a byte of"),
        (was == again, "the oracle digest is stable across two reads of an untouched copy"),
        (bool(made) and made != torn,
         "moving ONE byte of a generated parser.c moves the generated digest"
         " the gate records beside the identity"),
        (was == now, "...and leaves the identity alone, because a stale parser is a torn"
                     " tree and not a different language"),
    ]


def prove() -> int:
    """Attempt to violate the seal, and be caught. Six constructed assertions.

    The pattern is `collate.py prove`'s: corrupt the thing in memory and show
    the gate still says no. A seal held by good intentions is not one, and this
    tree has ten lanes in it.
    """
    import contextlib
    import io
    import tempfile
    out: list[tuple[bool, str]] = []
    rows = manifest()
    out.append((bool(rows), f"there is a manifest to seal: {len(rows)} pin(s)"))

    # 1. The row type cannot carry a diagnosis. Checked against the type, not
    #    against what today's printer happens to print.
    leaky = {"wall", "state", "terminal", "offset", "start", "end", "tree", "run",
             "verdict", "worst", "ours", "theirs", "blob"}
    hit = leaky & set(Sealed._fields)
    out.append((not hit, f"the sealed row type has no field a diagnosis fits in"
                         f"{' — LEAKS: ' + ', '.join(sorted(hit)) if hit else ''}"))

    # 2. The real attempt. Measure one sealed grammar for real, intercept the
    #    `rack.Seen` on its way past - which carries every disagreeing run with
    #    both parsers' node names and both byte offsets - and then assert that
    #    not one of those witnesses survives into anything the gate emits, in
    #    either channel. A substring scan of the gate's source constants was
    #    the first version of this check and it could not fail: it asserted
    #    that literals I wrote do not contain words I did not write.
    #
    #    The witnesses exist only inside this function and are never printed.
    out.extend(smuggle(rows))
    out.extend(smuggle(rows, sabotage=True))

    # 3. Re-running selection cannot re-roll the holdout.
    out.append((select() == 1, "a second `select` refuses rather than re-rolling the twenty"))

    # 4. An unsealing with no reason is refused.
    out.append((unseal(rows[0].name if rows else "x", "  ") == 2,
                "an unsealing with a blank reason is refused"))

    # 5. An unsealing of something not sealed is refused rather than recorded.
    out.append((unseal("a-grammar-that-does-not-exist", "smuggling") == 2,
                "an unsealing of a grammar that is not sealed is refused"))

    # 5b. The oracle attribution notices a swapped parser. The residual hazard
    #     the copy survey leaves open is a `parser.c` generated from something
    #     other than the `grammar.json` sitting beside it: `oracle_build` only
    #     regenerates when the two grammar digests differ, so a stale generated
    #     parser beside a correct grammar is used as-is and no verb complains.
    #     `attest.survey` covers `parser.c`, so the per-row digest moves; this
    #     asserts that it does, by moving one byte in a scratch copy rather
    #     than by trusting that it would.
    out.extend(swapped())

    # 6. A real unsealing, against a scratch ledger, shrinks the twenty and is
    #    recorded. Staged in a tmpdir so proving the mechanism costs nothing -
    #    an instrument that has to vandalise the tree to test itself is not one
    #    anybody runs.
    with tempfile.TemporaryDirectory() as tmp:
        keep = globals()["LEDGER"]
        globals()["LEDGER"] = Path(tmp) / "ledger.json"
        try:
            was = len(sealed())
            with contextlib.redirect_stdout(io.StringIO()):
                code = unseal(rows[0].name, "proving the ledger catches a spend") if rows else 2
            now = len(sealed())
            spent = ledger()["unsealed"]
            out.append((code == 0 and now == was - 1 and len(spent) == 1
                        and spent[0]["reason"].startswith("proving"),
                        f"a real unsealing takes the holdout {was} -> {now} and writes"
                        f" one ledger entry naming who and why"))
        finally:
            globals()["LEDGER"] = keep
    out.append((len(sealed()) == len(rows) - len(ledger()["unsealed"]),
                "and the live ledger is untouched by the proof above"))

    print()
    for ok, why in out:
        print(f"  {'ok  ' if ok else 'FAIL'}  {why}")
    bad = sum(1 for ok, _ in out if not ok)
    print(f"\n  {len(out) - bad}/{len(out)} held")
    return 1 if bad else 0


def verify(as_json: bool) -> int:
    """Offline. Do the bytes on disk still hash to their pins, and is the
    ledger a ledger?"""
    rows, bad = manifest(), []
    for h in rows:
        for path, sha, size in ((h.grammar, h.grammar_sha256, h.grammar_size),
                                (h.source, h.source_sha256, h.source_size)):
            if not path.exists():
                bad.append(f"{h.name}: {path.name} not fetched")
                continue
            blob = path.read_bytes()
            if hashlib.sha256(blob).hexdigest() != sha:
                bad.append(f"{h.name}: {path.name} is not the pinned bytes")
            elif len(blob) != size:
                bad.append(f"{h.name}: {path.name} is {len(blob)} bytes, pinned {size}")
    seen: set[str] = set()
    for e in ledger()["unsealed"]:
        if e["grammar"] in seen:
            bad.append(f"ledger: {e['grammar']} unsealed twice")
        seen.add(e["grammar"])
        if not e.get("reason", "").strip():
            bad.append(f"ledger: {e['grammar']} was spent with no reason")
    if as_json:
        print(json.dumps({"pins": len(rows), "faults": bad}, indent=2))
    else:
        for line in bad:
            print(f"  FAIL  {line}")
        print(f"\n  {len(rows) * 2 - len(bad)}/{len(rows) * 2} pinned files verify"
              f" · {len(seen)} spent · {len(sealed())} sealed")
    return 1 if bad else 0


def press(rows: list[Held]) -> int:
    """Tables only. Cheap, and it spends nothing - pressing is not measuring."""
    got = [press_one(h) for h in rows]
    print(f"\n  {'grammar':<20}{'outcome':<11}{'lit':>6}{'rex':>6}{'ext':>6}"
          f"{'states':>8}{'resid':>7}{'refuse':>8}")
    print(f"  {'-' * 73}")
    for r in sorted(got, key=lambda r: r.name):
        print(f"  {r.name:<20}{r.outcome:<11}{r.literal:>6}{r.regex:>6}{r.external:>6}"
              f"{r.states:>8}{r.residual:>7}{r.refuse:>8}")
    n = len(got)
    print(f"  {'-' * 73}")
    print(f"  {sum(1 for r in got if r.pressed)}/{n} press · "
          f"{sum(1 for r in got if r.external)} declare an external · "
          f"{sum(1 for r in got if r.residual)} carry a RESIDUAL cell")
    print(f"\n  {SEAL}")
    return 0


def press_one(h: Held) -> field.Press:
    keep = field.WORK
    field.WORK = VENDOR / "grammars"
    try:
        return field.press_one(field.Pin(h.name, "", "", "", ""), 120)
    finally:
        field.WORK = keep


def oops(msg: str) -> int:
    print(f"holdout.py: {msg}", file=sys.stderr)
    return 2


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("verb", nargs="?", default="status",
                    choices=("select", "fetch", "verify", "press", "gate",
                             "thin", "doubt", "forked", "status", "unseal", "prove"))
    ap.add_argument("name", nargs="?", default="")
    ap.add_argument("--reason", default="")
    ap.add_argument("--grammar", action="append", default=[])
    ap.add_argument("--patience", type=float, default=600.0)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--versus", action="store_true",
                    help="also score the working corpus on this run, so the gap"
                         " is one instrument's number and not two reports'")
    a = ap.parse_args(argv)

    if a.verb == "select":
        return select()
    if a.verb == "prove":
        return prove()
    if a.verb == "unseal":
        return unseal(a.name, a.reason) if a.name else oops("unseal needs a grammar name")
    rows = sealed()
    if a.grammar:
        want = set(a.grammar)
        if unknown := want - {h.name for h in rows}:
            return oops(f"not sealed: {', '.join(sorted(unknown))}")
        rows = [h for h in rows if h.name in want]
    if not rows and a.verb != "status":
        return oops(f"nothing sealed. Run `holdout.py select` (writes {MANIFEST.name}).")
    if a.verb == "fetch":
        return fetch(rows)
    if a.verb == "verify":
        return verify(a.json)
    if a.verb == "press":
        return press(rows)
    if a.verb == "thin":
        return thin(rows, a.json)
    if a.verb == "doubt":
        return doubt(rows, a.patience, a.json)
    if a.verb == "forked":
        return forked(a.name or "css", a.patience, a.json)
    if a.verb == "gate":
        return gate(rows, a.patience, a.json, a.versus)
    return status(a.json)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

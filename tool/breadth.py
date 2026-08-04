#!/usr/bin/env python3
"""Press the held-out grammars, and say plainly where each one stops.

The eleven in `research/joinery/corpus/` are a training set. Every lane that
built this package was shaped against them and measured against them, so no
number over those eleven can support the claim that this presses any language.
`grammars.toml`'s `breadth` set is the held-out half - chosen before any of it
was pressed, never tuned against - and this is the instrument that asks it four
questions, in the order they can fail:

  1. does it import           the front door, `outliner grammar`
  2. does it press            states, residual conflicts, frayed cells, refusals
  3. is the folio smaller     against the `.so` tree-sitter builds from the same bytes
  4. does a real file parse   a genuine file from a real project, not a toy

Question four is deliberately NOT the dossier's instrument. The corpus is the
same ledger program written eleven times, which is what makes those eleven
numbers comparable to each other; writing nineteen more of them would measure
the same program again rather than the languages. So each grammar here is
pointed at a file somebody actually shipped, and the bar is how far the parse
gets through it.

The differential is `differential.py`'s own `measure`, imported rather than
reimplemented, so a held-out grammar is judged against tree-sitter by exactly
the bar the eleven are judged by.

Exit 0 ran, 1 something failed a step, 2 the instrument could not run. Sources
are pinned by sha256 the way the grammars are: `fetch` refuses bytes that do
not hash to the recorded value rather than quietly measuring a different file.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, NamedTuple

sys.path.insert(0, str(Path(__file__).resolve().parent))

import differential as d  # noqa: E402 - the path has to be set first
from grammars import load  # noqa: E402
from stamp import ask as ask_one  # noqa: E402
from stamp import take  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
GRAMMARS = ROOT / "upstream" / "grammars"
DEST = ROOT / "upstream" / "sources"
BIN = Path(os.environ.get("OUTLINER_BIN", ROOT / "zig-out" / "bin" / "outliner"))
RAW = "https://raw.githubusercontent.com/"
LIB = Path.home() / ".cache" / "tree-sitter" / "lib"
OUT = ROOT / ".local" / "breadth"

# The held-out grammars get their own root rather than sharing
# `.local/differential/lang/`, and this is not tidiness. A scanner may `#include`
# a header by a relative path that climbs out of its own directory -
# tree-sitter-php's is `../../common/scanner.h` - and `differential.py` resolves
# that against the language directory, so the header lands in `lang/common/`.
# tree-sitter-typescript's scanner asks for exactly the same path. Fetching php
# beside the eleven overwrites the header typescript is built from, and
# typescript silently stops comparing. Anchoring the held-out set one level over
# means the same climb lands in `breadth/common/` and the two sets cannot reach
# each other's headers. See the report; the collision is `differential.py`'s to
# fix, not this file's to work around forever.
LANG = ROOT / ".local" / "breadth" / "lang"

# A generous ceiling rather than a tight one. The point of a held-out set is to
# find out what a grammar costs, so a press that takes four minutes is a result
# worth having; only one that will never finish is worth cutting off.
PATIENCE = 600

USAGE = """\
breadth.py - press the held-out grammars and say where each one stops

usage:
  breadth.py pin        print the SOURCES rows with their hashes (network)
  breadth.py fetch      download the real source files, hash-checked (network)
  breadth.py verify     hash what is on disk against SOURCES (offline)
  breadth.py scanners   fetch the external scanners the oracle needs (network)
  breadth.py run        the sweep
  breadth.py list       the set and its source files

flags:
  --json            machine output
  --only=NAME       one grammar (repeatable)
  --skip-oracle     press and parse, but do not build tree-sitter's parser
"""

# One real file per language, from a real project. Chosen for being something
# somebody shipped rather than for being convenient: a Pandoc module, the
# Prometheus CI config, the Kotlin standard library, PDF.js's viewer page. The
# hash is the authority - these are branch refs, so upstream can move under
# them, and a moved file has to announce itself rather than silently become a
# different measurement.
SOURCES: dict[str, tuple[str, str, str]] = {
    "css": ("necolas/normalize.css/master/normalize.css", "normalize.css",
        "580818700724d42d7fcc4979b0197971fca1c6d2e0286769237a0ac897df5512"),  # 6138 bytes
    "elixir": ("phoenixframework/phoenix/main/lib/phoenix/router.ex", "router.ex",
        "046564dae97dbd0ba58eb78e630fb226a2c8360a86b933dd9604e998c68b17bd"),  # 46089 bytes
    "embedded-template": ("discourse/discourse/main/app/views/layouts/application.html.erb", "application.html.erb",
        "c481f3977efa5fdb6badbbdb6acb8e4b9aaab1ebbe1a00e608882f3fb85fd095"),  # 6006 bytes
    "haskell": ("jgm/pandoc/main/src/Text/Pandoc/Shared.hs", "Shared.hs",
        "538874e0f17895a81d5a479d2a52b134777e2ef0eb6988657070862dfacb6600"),  # 34240 bytes
    "html": ("mozilla/pdf.js/master/web/viewer.html", "viewer.html",
        "52791712cc2185d4dbfcbd4321648ed3f719a531399568d479c05a09fcbcbdd7"),  # 72288 bytes
    "julia": ("JuliaLang/julia/master/base/set.jl", "set.jl",
        "4585eafb53f1ecef7559d7fa0e00e12d6932ac363ee2f9b0c682637bb29cf8e3"),  # 27360 bytes
    "kotlin": ("JetBrains/kotlin/master/libraries/stdlib/src/kotlin/collections/Maps.kt", "Maps.kt",
        "773f15240e05d648172b2953dd64f3345327fc2b1c76e8d73e67b569905a07b9"),  # 35815 bytes
    "latex": ("latex3/latex2e/develop/base/doc/ltnews01.tex", "ltnews01.tex",
        "54179c456281cdc625d4205a15e8dd52e61e5b8c6325350fc823c58ccaf56962"),  # 5246 bytes
    "lua": ("neovim/neovim/master/runtime/lua/vim/uri.lua", "uri.lua",
        "093810743028bfbdd24349ca28621a55db4804f255056fd617207af29b2d702b"),  # 3707 bytes
    "markdown": ("rust-lang/rust/master/README.md", "README.md",
        "b3f6ef2fef88b98cb9ec013a5c86213095e53e40eb228679574e4d06517f33c8"),  # 3304 bytes
    "ocaml": ("ocaml/ocaml/trunk/stdlib/list.ml", "list.ml",
        "3703bdaf69c532b535c3de70cafdc50cb6c4a31c6cb8ded0454b41f8178cc982"),  # 16878 bytes
    "php": ("laravel/framework/master/src/Illuminate/Support/Str.php", "Str.php",
        "ff74f29c097d584b9f5c98193704f10afbeccb53c22d8ffeaf311f9633ec6630"),  # 67845 bytes
    "scala": ("scala/scala/2.13.x/src/library/scala/Option.scala", "Option.scala",
        "2d64050477836528db8ddfd16582f33e90c78f94b4240c82bf3eab35a763ebcf"),  # 20107 bytes
    "sql": ("postgres/postgres/master/src/test/regress/sql/case.sql", "case.sql",
        "1979a7667d5632a0c7d5a164533f604688d9eecac98521749e0d332e6f82482b"),  # 6390 bytes
    "swift": ("apple/swift-algorithms/main/Sources/Algorithms/Chunked.swift", "Chunked.swift",
        "fb06bdb5febbcea03182b8116291c48daf3299c64f54f639905bdeb869b2d054"),  # 28468 bytes
    "toml": ("BurntSushi/ripgrep/master/Cargo.toml", "Cargo.toml",
        "2f95013e611a48735f349ff98fd1e9513676bc7145d0be9af29c585ffce5e4fe"),  # 3544 bytes
    "verilog": ("YosysHQ/picorv32/main/picorv32.v", "picorv32.v",
        "0836050971b3c6cdd28ac3b1e5719a67fb645161912bef1e472e63995ceb0622"),  # 94657 bytes
    "yaml": ("prometheus/prometheus/main/.github/workflows/ci.yml", "ci.yml",
        "f61b4ff89aa1a1a95272562c067e150b5ae528c255877a2e5d30b0b932e28c38"),  # 18935 bytes
    "zig": ("ziglang/zig/master/lib/std/ascii.zig", "ascii.zig",
        "da69803dffc9571f0c4f7ea452317433883c206aec5299788649c2623eda9452"),  # 16125 bytes
}

# `outliner grammar` prints one fact per line. Reading them by name rather than
# by position means a new line in that report cannot silently shift a column.
SHAPE = {
    "symbols": re.compile(r"symbols\s+(\d+)\s+\((\d+) terminal, (\d+) nonterminal\)"),
    "kinds": re.compile(r"terminals\s+(\d+) literal, (\d+) regex, (\d+) external"),
    "productions": re.compile(r"productions\s+(\d+)"),
    "declared": re.compile(r"conflicts\s+(\d+) declared"),
    "imported": re.compile(r"imported in\s+([\d.]+) (\w+)"),
    "states": re.compile(r"lr\(0\) states\s+(\d+)"),
    "cells": re.compile(r"lalr table\s+(\d+) cells"),
    "residual": re.compile(r"(\d+) RESIDUAL"),
    "frayed": re.compile(r"frayed\s+(\d+) cells.*?\((\d+) REFUSE"),
    "built": re.compile(r"built in\s+([\d.]+) (\w+)"),
}
MILLIS = {"ns": 1e-6, "us": 1e-3, "ms": 1.0, "s": 1000.0}


class Row(NamedTuple):
    name: str
    grammar_bytes: int
    step: str  # imported · pressed · parsed · the step it died at
    why: str
    shape: dict[str, Any]
    folio: int
    their_so: int
    reach: int
    source_bytes: int
    verdict: str
    diff: dict[str, Any]

    def as_dict(self) -> dict[str, Any]:
        return self._asdict()


def millis(value: str, unit: str) -> float:
    return float(value) * MILLIS.get(unit, 0.0)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pull(url: str) -> bytes:
    with urllib.request.urlopen(RAW + url, timeout=120) as r:  # noqa: S310 - https literal
        return r.read()


def source_of(name: str) -> Path:
    return DEST / SOURCES[name][1]


def picked(argv_only: list[str]) -> list[str]:
    have = {p.name for p in load("breadth")}
    if unknown := set(argv_only) - have:
        raise ValueError(f"no such breadth grammar: {', '.join(sorted(unknown))}")
    return sorted(argv_only or have)


# ------------------------------------------------------------------- the steps

def shape_of(name: str) -> tuple[dict[str, Any], str]:
    """Import and press in one call, since `outliner grammar` does both."""
    got = run_out([str(BIN), "grammar", str(GRAMMARS / f"{name}.json")])
    if got is None:
        return {}, f"press did not finish inside {PATIENCE}s"
    if got.returncode != 0:
        tail = [ln for ln in got.stderr.strip().splitlines() if ln.strip()]
        return {}, tail[-1] if tail else f"exit {got.returncode}, nothing on stderr"
    text = got.stdout
    out: dict[str, Any] = {}
    for key, pat in SHAPE.items():
        if not (m := pat.search(text)):
            continue
        if key in ("imported", "built"):
            out[key] = round(millis(m.group(1), m.group(2)), 3)
        elif key == "symbols":
            out["symbols"], out["terminals"], out["nonterminals"] = map(int, m.groups())
        elif key == "kinds":
            out["literal"], out["regex"], out["external"] = map(int, m.groups())
        elif key == "frayed":
            out["frayed"], out["refuse"] = map(int, m.groups())
        else:
            out[key] = int(m.group(1))
    # `built in` is only printed once the tables exist, so its absence is the
    # signal that the press reported a shape and then gave up, which reads very
    # differently from a press that never started.
    return out, "" if "built" in out else "imported, but the press printed no tables"


def folio_of(name: str) -> tuple[int, str]:
    target = OUT / "folio" / f"{name}.folio"
    target.parent.mkdir(parents=True, exist_ok=True)
    got = run_out([str(BIN), "mint", str(GRAMMARS / f"{name}.json"), "-o", str(target)])
    if got is None:
        return 0, f"mint did not finish inside {PATIENCE}s"
    if got.returncode != 0 or not target.exists():
        return 0, (got.stderr.strip().splitlines() or ["mint wrote nothing"])[-1]
    return target.stat().st_size, ""


def reach_of(name: str) -> tuple[int, int, str]:
    src = source_of(name)
    if not src.exists():
        return 0, 0, "no source fetched"
    size = src.stat().st_size
    # One exchange, in `stamp`, shared with the census - this file used to run
    # the binary and read the answer itself, and the two drifted apart the
    # moment recovery landed.
    end = ask_one(BIN, GRAMMARS / f"{name}.json", src, size=size, patience=PATIENCE)
    return max(end.reach, 0), size, end.verdict


def run_out(cmd: list[str]) -> subprocess.CompletedProcess[str] | None:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=PATIENCE, cwd=ROOT)
    except subprocess.TimeoutExpired:
        return None


def oracle_of(name: str) -> tuple[int, dict[str, Any]]:
    """tree-sitter's own `.so` for these bytes, and the tree it produces.

    Built from the pinned grammar.json rather than from the repo, so both sides
    read the same bytes; that is `differential.py`'s discipline and the only
    thing that makes the comparison mean anything.
    """
    lang = d.oracle_home(name, LANG.parent)
    case = d.Case(f"breadth/{name}", GRAMMARS / f"{name}.json", lang, source_of(name), "breadth")
    try:
        report = d.measure(case)
    except Exception as e:  # noqa: BLE001 - an oracle that explodes is a result
        return 0, {"mode": "skipped", "why": f"{type(e).__name__}: {e}"}
    so = LIB / f"{name}.dylib"
    if not so.exists():
        so = LIB / f"{name}.so"
    return (so.stat().st_size if so.exists() else 0), {
        "mode": report.mode, "why": report.why, "ours": report.ours,
        "theirs": report.theirs, "unexplained": report.unexplained,
        "known": len(report.findings) - report.unexplained,
    }


def sweep(names: list[str], oracle: bool) -> list[Row]:
    rows = []
    for name in names:
        gsize = (GRAMMARS / f"{name}.json").stat().st_size
        shape, why = shape_of(name)
        if not shape:
            rows.append(Row(name, gsize, "import", why, {}, 0, 0, 0, 0, "", {}))
            print(f"  {name:<18} import    {why}", file=sys.stderr)
            continue
        step = "pressed" if not why else "press"
        folio, folio_why = folio_of(name)
        reach, ssize, verdict = reach_of(name)
        so, diff = oracle_of(name) if oracle else (0, {})
        if not why and folio_why:
            why, step = folio_why, "folio"
        elif not why and reach >= ssize > 0:
            step = "parsed"
        rows.append(Row(name, gsize, step, why or verdict, shape, folio, so,
                        reach, ssize, verdict, diff))
        pct = f"{reach / ssize * 100:5.1f}%" if ssize else "    -"
        print(f"  {name:<18} {step:<9} {shape.get('states', 0):>6} states  "
              f"{shape.get('residual', 0):>5} residual  {pct} of {ssize}B", file=sys.stderr)
    return rows


# ------------------------------------------------------------------------ verbs

def mint_pins() -> int:
    for name, (url, leaf, _) in SOURCES.items():
        try:
            blob = pull(url)
        except (urllib.error.URLError, OSError) as e:
            print(f"breadth.py: {name}: {url}: {e}", file=sys.stderr)
            continue
        print(f'    "{name}": ("{url}", "{leaf}",\n'
              f'        "{hashlib.sha256(blob).hexdigest()}"),  # {len(blob)} bytes')
    return 0


def fetch() -> int:
    DEST.mkdir(parents=True, exist_ok=True)
    bad = 0
    for name, (url, leaf, want) in SOURCES.items():
        target = DEST / leaf
        if target.exists() and digest(target) == want:
            print(f"  have {name:<18} {want[:16]}")
            continue
        try:
            blob = pull(url)
        except (urllib.error.URLError, OSError) as e:
            print(f"breadth.py: {name}: {url}: {e}", file=sys.stderr)
            bad += 1
            continue
        if (got := hashlib.sha256(blob).hexdigest()) != want:
            print(f" DRIFT {name:<18} upstream now hashes {got[:16]}, pinned {want[:16]}",
                  file=sys.stderr)
            print("       nothing written; the file moved under the pin", file=sys.stderr)
            bad += 1
            continue
        part = target.with_suffix(target.suffix + ".part")
        part.write_bytes(blob)
        part.replace(target)
        print(f" wrote {name:<18} {got[:16]} {len(blob)} bytes")
    return 1 if bad else 0


def verify() -> int:
    bad = 0
    for name, (_, leaf, want) in SOURCES.items():
        target = DEST / leaf
        if not target.exists():
            print(f"  -- {name:<18} not fetched")
            bad += 1
        elif (got := digest(target)) != want:
            print(f"  !! {name:<18} on disk {got[:16]}, pinned {want[:16]}")
            bad += 1
    print(f"{len(SOURCES)} sources in {DEST.relative_to(ROOT)}: {len(SOURCES) - bad} ok")
    return 1 if bad else 0


def scanners() -> int:
    """The external scanners the oracle needs, from the grammar's own commit.

    This used to be a second copy of the same walk, laying every scanner flat at
    `lang/<name>/src/` and deriving its headers' URLs from the include's own
    relative path. That is the layout the monorepo collision lived in: ocaml and
    php both climb out of `src/` to a `common/scanner.h`, so both landed on one
    shared file and the second writer owned both oracles. It also put ocaml's
    scanner at a depth `oracle_home` does not look at, which is why ocaml has
    had no oracle at all and read as the held-out set's last unexplained finding.

    So there is one walk now, in `differential.py`, pointed at this workspace.
    Two copies of a rule is two places for the next monorepo grammar to break.
    """
    return d.fetch_scanners("breadth", LANG.parent)


def inventory() -> int:
    print(f"{'name':<18} {'grammar.json':>12}  {'source':<22} {'bytes':>7}  origin")
    for pin in sorted(load("breadth"), key=lambda p: p.name):
        url, leaf, _ = SOURCES.get(pin.name, ("", "", ""))
        f = DEST / leaf if leaf else None
        size = f.stat().st_size if f and f.exists() else 0
        print(f"{pin.name:<18} {pin.size:>12}  {leaf:<22} {size:>7}  {url.split('/')[0]}/"
              f"{url.split('/')[1] if url else ''}")
    return 0


def show(rows: list[Row], as_json: bool, whole: bool = True) -> int:
    mark = take(d.BIN)
    if as_json:
        print(json.dumps({"oracle": d.oracle_ready(), "stamp": mark.as_dict(),
                          "row": [r.as_dict() for r in rows]}, indent=2))
    else:
        print(f"\n{'grammar':<18} {'step':<8} {'states':>7} {'resid':>6} {'frayed':>7} "
              f"{'refuse':>7} {'press ms':>9} {'folio':>8} {'their .so':>10} {'x':>6} "
              f"{'reach':>7}  differential")
        for r in rows:
            s = r.shape
            ratio = f"{r.folio / r.their_so:.2f}" if r.their_so else "-"
            pct = f"{r.reach / r.source_bytes * 100:.1f}%" if r.source_bytes else "-"
            dif = (f"{r.diff.get('mode', '-')}"
                   + (f" {r.diff.get('unexplained', 0)}u" if r.diff.get("mode") not in
                      (None, "skipped") else ""))
            print(f"{r.name:<18} {r.step:<8} {s.get('states', 0):>7} {s.get('residual', 0):>6} "
                  f"{s.get('frayed', 0):>7} {s.get('refuse', 0):>7} "
                  f"{s.get('built', 0):>9.1f} {r.folio:>8} {r.their_so:>10} {ratio:>6} "
                  f"{pct:>7}  {dif}")
        stuck = [r for r in rows if r.step in ("import", "press", "folio")]
        print(f"\n{len(rows)} pressed cold · {len(stuck)} did not survive a step"
              + (": " + ", ".join(r.name for r in stuck) if stuck else ""))
        print(mark.line())
    # A `--only=` run must not overwrite the full sweep: the artifact is what a
    # report is read back from, and quietly replacing thirty rows with one is
    # how a lane ends up citing a file that no longer says what it cites.
    if whole:
        OUT.mkdir(parents=True, exist_ok=True)
        # The saved artifact carries the stamp too, since a sweep this slow is
        # read back from the file far more often than it is re-run.
        (OUT / "breadth.json").write_text(
            json.dumps({"oracle": d.oracle_ready(), "stamp": mark.as_dict(),
                        "row": [r.as_dict() for r in rows]}, indent=2) + "\n"
        )
    elif not as_json:
        print(f"breadth.py: subset run; {OUT.name}/breadth.json left alone")
    return 1 if any(r.step in ("import", "press", "folio") for r in rows) else 0


def oops(msg: str) -> int:
    print(f"breadth.py: {msg}", file=sys.stderr)
    return 2


def main(argv: list[str]) -> int:
    as_json, only, verb, oracle = False, [], "", True
    for a in argv:
        if a == "--json":
            as_json = True
        elif a == "--skip-oracle":
            oracle = False
        elif a.startswith("--only="):
            only.append(a.split("=", 1)[1])
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
        if verb == "pin":
            return mint_pins()
        if verb == "fetch":
            return fetch()
        if verb == "verify":
            return verify()
        if verb == "scanners":
            return scanners()
        if verb == "list":
            return inventory()
        if verb == "run":
            d.lay_out()
            return show(sweep(picked(only), oracle), as_json, whole=not only)
    except (OSError, ValueError) as e:
        return oops(str(e))
    return oops(f"no such verb {verb!r}\n\n{USAGE}")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

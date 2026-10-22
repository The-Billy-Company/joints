#!/usr/bin/env python3
"""Freeze portable Zig migration evidence; verify bytes and replay every case.

    python3 tool/migration.py freeze --build --core
    python3 tool/migration.py verify
    python3 tool/migration.py replay
    python3 tool/migration.py export --out test/migration/reference
    python3 tool/migration.py replay --bundle test/migration/reference --binary PATH

Run under the selected Zig/Python toolchain, e.g. `mise exec
zig@0.16.0 python@3.12.15 -- python3 tool/migration.py ...`.
No build fallback, downloads, implicit corpus skips, or external oracle claims.
An export contains inputs/outputs and provenance, never the native executable.
Exit 0 the requested check passed, 1 evidence disagreed, 2 could not run.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import grammars
import stamp

ROOT = Path(__file__).resolve().parents[1]
DEFAULT = ROOT / ".local/rust-migration/reference"
PIN = ROOT / ".local/pin/rust-reference/bin/joints"
BUILD_INPUTS = {
    "joints": ("src", "customary", "include", "test/grammar", "build.zig", "build.zig.zon",
               "grammars.toml", "research/joinery/corpus", "tool/migration.py", "tool/pin.py",
               "tool/stamp.py", "tool/still.py"),
    "irregex": ("src", "vendor", "include", "bench/apparatus/harness", "build.zig", "build.zig.zon"),
}
FIXTURES = {
    "json-valid.json": b'{"title":"caf\xc3\xa9","nested":[1,{"ok":true}],"none":null}\n',
    "json-string.json": b'"abc"\n',
    "json-escaped.json": br'{"empty":"","escape":"a\n\"b","nul":"\u0000"}' + b'\n',
    "json-whitespace.json": b' \t\r\n {"value":1} \n\t',
    "json-comments.json": b'/* before */ {"value":1} // after\n',
    "json-multiple.json": b'{} [] true\n',
    "json-missing-colon.json": b'{"answer" 42}\n',
    "json-extra-comma.json": b'{"answer":42,,"next":1}\n',
    "json-truncated.json": b'{"answer":[1,2\n',
    "json-stray.json": b'{"answer":@42}\n',
    "json-empty.json": b'',
    "json-invalid-byte.json": b'\xff',
}
STRICT_FIXTURES = {"json-valid.json", "json-string.json", "json-escaped.json", "json-whitespace.json",
                   "json-comments.json", "json-multiple.json", "json-empty.json"}


def encoded(value: object) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True, ensure_ascii=True) + "\n").encode()


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write(home: Path, rel: str, data: bytes) -> None:
    path = home / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def git(home: Path, *args: str) -> bytes:
    return subprocess.run(["git", *args], cwd=home, check=True, capture_output=True).stdout


def snapshot(name: str) -> dict:
    home = ROOT if name == "joints" else ROOT.parent / "irregex"
    names = git(home, "ls-files", "--cached", "--others", "--exclude-standard", "-z")
    files = {}
    for rel in sorted(set(os.fsdecode(p) for p in names.split(b"\0") if p)):
        if any(rel == base or rel.startswith(base + "/") for base in BUILD_INPUTS[name]):
            p = home / rel
            files[rel] = sha(p.read_bytes()) if p.is_file() else None
    if not files:
        raise ValueError(f"no build inputs for {name}")
    return {"commit": git(home, "rev-parse", "HEAD").decode().strip(),
            "dirty": git(home, "status", "--porcelain=v1").decode().splitlines(),
            "source_sha256": sha(encoded(files)), "files": files}


def stable(before: dict, after: dict) -> bool:
    return all(before[n][k] == after[n][k]
               for n in BUILD_INPUTS for k in ("commit", "source_sha256"))


def environment() -> dict:
    # An inherited experiment or explicit scanner directory changes the parser.
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("JOINTS_", "IRGX_", "IRREGEX_"))}
    env.update({"LC_ALL": "C", "TZ": "UTC", "NO_COLOR": "1"})
    return env


def run(argv: list[str], cwd: Path, timeout: int) -> dict:
    got = subprocess.run(argv, cwd=cwd, env=environment(), timeout=timeout,
                         capture_output=True)
    return {"exit": got.returncode, "stdout": got.stdout, "stderr": got.stderr}


def versions() -> dict:
    out = {"python": {"available": True, "version": platform.python_version()}}
    for tool in ("zig", "rustc", "cargo", "clang", "tree-sitter"):
        try:
            got = run([tool, "version" if tool == "zig" else "--version"], ROOT, 30)
            out[tool] = {"available": got["exit"] == 0, "exit": got["exit"],
                         "stdout": got["stdout"].decode(errors="replace"),
                         "stderr": got["stderr"].decode(errors="replace")}
        except (OSError, subprocess.TimeoutExpired) as exc:
            out[tool] = {"available": False, "reason": type(exc).__name__}
    return out


def capture_overlays(home: Path, repositories: dict) -> None:
    for name, record in repositories.items():
        source = ROOT if name == "joints" else ROOT.parent / "irregex"
        changed = set(os.fsdecode(p) for p in
                      git(source, "diff", "HEAD", "--name-only", "-z").split(b"\0") if p)
        changed.update(os.fsdecode(p) for p in git(source, "ls-files", "--others",
                       "--exclude-standard", "-z").split(b"\0") if p)
        record["overlays"] = []
        for rel in sorted(changed & record["files"].keys()):
            stored = f"provenance/{name}/{rel}" if record["files"][rel] else None
            if stored:
                write(home, stored, (source / rel).read_bytes())
            record["overlays"].append({"path": rel, "stored": stored})


def cases(home: Path, core: bool) -> list[dict]:
    pins = {p.name: p for p in grammars.load()}
    grammar = "inputs/test/grammar/json.json"
    fixture = (ROOT / "test/grammar/json.json").read_bytes()
    if sha(fixture) != pins["json"].sha256:
        raise ValueError("committed JSON grammar does not match grammars.toml")
    write(home, grammar, fixture)
    result = []
    for name, data in FIXTURES.items():
        source = f"inputs/fixtures/{name}"
        write(home, source, data)
        expectation = "strict" if name in STRICT_FIXTURES else "refused"
        for arm, flags in (("default", []), ("no-recovery", ["--mend=none", "--no-supply"])):
            result.append({"id": name[:-5] + "-" + arm,
                           "argv": ["parse", grammar, source, "--all", "--json", *flags],
                           "expectation": expectation})
    ledger = "research/joinery/corpus/ledger.json"
    write(home, "inputs/" + ledger, (ROOT / ledger).read_bytes())
    result.append({"id": "corpus-json", "argv": ["parse", grammar, "inputs/" + ledger,
                   "--all", "--json"], "expectation": "strict"})
    if core:
        import rung1
        roster = rung1.pairs()
        if len(pins) != 11 or len(roster) != 11 or {g for g, _ in roster} != set(pins):
            raise ValueError("core corpus roster differs from the eleven pinned dossier grammars")
        for language, filename in roster:
            if language == "json":
                continue
            p = pins[language]
            g = (ROOT / f"upstream/grammars/{language}.json").read_bytes()
            if sha(g) != p.sha256:
                raise ValueError(f"{language}: fetched grammar does not match its pin")
            grammar = f"inputs/upstream/grammars/{language}.json"
            source = f"inputs/research/joinery/corpus/{filename}"
            write(home, grammar, g)
            write(home, source, (ROOT / f"research/joinery/corpus/{filename}").read_bytes())
            result.append({"id": f"corpus-{language}", "argv": ["parse", grammar, source,
                           "--all", "--json"], "expectation": "observed"})
    return result


def consumer_state(package: Path) -> dict:
    package = package.resolve()
    repo = Path(git(package, "rev-parse", "--show-toplevel").decode().strip())
    paths = ("grammar_profile.py", "grammar/python314-v1.json", "grammar/LICENSE.tree-sitter-python")
    hashes = {}
    for rel in paths:
        path = package / rel
        hashes[str(path.relative_to(repo))] = sha(path.read_bytes())
    return {"repository": "billy", "commit": git(repo, "rev-parse", "HEAD").decode().strip(),
            "files": hashes, "source_sha256": sha(encoded(hashes)),
            "dirty": git(repo, "status", "--porcelain=v1", "--", str(package)).decode().splitlines(),
            "scope": "parse grammar_profile.py only; no Regulator facet equivalence"}


def consumer(home: Path, package: Path, timeout: int) -> tuple[dict, dict]:
    metadata = consumer_state(package)
    for rel in ("grammar_profile.py", "grammar/python314-v1.json", "grammar/LICENSE.tree-sitter-python"):
        write(home, "inputs/regulator/" + rel, (package / rel).read_bytes())
    base = "inputs/upstream/grammars/python.json"
    data = (ROOT / "upstream/grammars/python.json").read_bytes()
    pin = next(p for p in grammars.load() if p.name == "python")
    if sha(data) != pin.sha256:
        raise ValueError("Regulator Python base does not match its pin")
    write(home, base, data)
    recipe = "inputs/regulator/grammar/python314-v1.json"
    derived = "inputs/regulator/python314-derived.json"
    command = ["inputs/regulator/grammar_profile.py", base, "--recipe", recipe, "--output", derived]
    got = run([sys.executable, *command], home, timeout)
    if got["exit"]:
        raise ValueError(f"Regulator profile preparation failed: {got['stderr'][-500:]!r}")
    expected = json.loads((home / recipe).read_bytes())["expected_grammar_sha256"]
    if sha((home / derived).read_bytes()) != expected:
        raise ValueError("Regulator derived grammar did not match its reviewed hash")
    write(home, "provenance/regulator-prepare.json", encoded({"argv": ["{PYTHON}", *command],
          "exit": got["exit"], "derived_sha256": expected}))
    case = {"id": "regulator-python-profile", "expectation": "observed",
            "argv": ["parse", derived,
                     "inputs/regulator/grammar_profile.py", "--all", "--json"]}
    return metadata, case


def counts(value: dict, names: tuple[str, ...]) -> None:
    if any(type(value.get(k)) is not int or value[k] < 0 for k in names):
        raise ValueError("parse contains missing, negative, or noninteger counters")


def node(value: dict) -> None:
    if (not isinstance(value, dict) or not isinstance(value.get("name"), str)
            or type(value.get("named")) is not bool or not isinstance(value.get("kids"), list)
            or ("field" in value and not isinstance(value["field"], str))):
        raise ValueError("parse contains a malformed tree node")
    counts(value, ("start", "end"))
    if value["end"] < value["start"]:
        raise ValueError("parse contains a reversed node span")
    for child in value["kids"]:
        node(child)


def answer(got: dict) -> tuple[dict, bool]:
    if got["exit"] not in (0, 1):
        raise ValueError(f"parse exited {got['exit']}: {got['stderr'][-500:]!r}")
    value = json.loads(got["stdout"])
    required = {"language", "path", "stop", "roots", "tree", "scars", "survey",
                "mends", "skipped", "supplied", "spurned"}
    if not isinstance(value, dict) or not required <= value.keys():
        raise ValueError("parse omitted required tree or confidence evidence")
    if (not isinstance(value["language"], str) or not isinstance(value["path"], str)
            or not isinstance(value["stop"], dict) or not isinstance(value["tree"], list)
            or not isinstance(value["scars"], list) or not isinstance(value["survey"], dict)
            or not isinstance(value["survey"].get("sound"), bool)
            or value["stop"].get("kind") not in ("accepted", "stray", "unexpected", "truncated")):
        raise ValueError("parse omitted required tree or confidence evidence")
    counts(value, ("roots", "mends", "skipped", "supplied", "spurned"))
    counts(value["survey"], ("walked", "held", "loose", "disorder", "torn"))
    stop = value["stop"]
    if stop["kind"] in ("stray", "unexpected"):
        counts(stop, ("at",))
    if stop["kind"] == "unexpected":
        counts(stop, ("state",))
        if not isinstance(stop.get("symbol"), str):
            raise ValueError("unexpected stop omitted its terminal")
    for scar in value["scars"]:
        if not isinstance(scar, dict) or type(scar.get("felled")) is not bool:
            raise ValueError("malformed repair evidence")
        counts(scar, ("at", "over", "heads", "shifted"))
        if scar["over"] < scar["at"] or ("gave" in scar and not isinstance(scar["gave"], str)):
            raise ValueError("malformed repair span or terminal")
    for limb in value["tree"]:
        node(limb)
    if value["roots"] != len(value["tree"]):
        raise ValueError("root count and tree disagree")
    strict = (value["stop"]["kind"] == "accepted" and value["survey"]["sound"]
              and value["roots"] == 1 and not value["scars"]
              and value["mends"] == value["skipped"] == value["supplied"] == 0)
    return value, strict


def inventory(home: Path) -> dict:
    return {str(p.relative_to(home)): sha(p.read_bytes()) for p in sorted(home.rglob("*"))
            if p.is_file() and p.name != "manifest.json"}


def semantic(value: dict) -> dict:
    """LR state numbering is diagnostic; all other evidence remains compared."""
    return {**value, "stop": {k: v for k, v in value["stop"].items() if k != "state"}}


def private_pin(binary: Path, commit: str) -> dict:
    record = json.loads((binary.parents[1] / "pin.json").read_bytes())
    if record["build"] != sha(binary.read_bytes()):
        raise ValueError("binary does not match its private pin")
    if record["tree"] != stamp.survey(ROOT).digest or record["commit"] != commit:
        raise ValueError("private pin source or commit differs; freeze with --build")
    return record


def freeze(args) -> int:
    out = args.out.resolve()
    if out.exists():
        raise ValueError(f"refusing to replace existing evidence: {out}")
    before = {n: snapshot(n) for n in BUILD_INPUTS}
    tools = versions()
    if not tools["zig"]["available"]:
        raise ValueError("selected Zig is unavailable; run under the configured toolchain")
    binary = args.binary.resolve()
    build = None
    if args.build:
        if binary != PIN.resolve():
            raise ValueError("--build uses the rust-reference pin; omit --binary")
        build = run([sys.executable, "tool/pin.py", "build", "--name", "rust-reference"],
                    ROOT, args.timeout)
        if build["exit"]:
            sys.stderr.buffer.write(build["stderr"])
            raise ValueError("reference build failed; no prior binary will be used")
    after_build = {n: snapshot(n) for n in BUILD_INPUTS}
    if not stable(before, after_build):
        raise ValueError("build inputs moved while the reference was built")
    record = private_pin(binary, before["joints"]["commit"])
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".migration-", dir=out.parent) as temporary:
        home = Path(temporary)
        write(home, "binary/joints", binary.read_bytes())
        if sha((home / "binary/joints").read_bytes()) != record["build"]:
            raise ValueError("reference binary moved while it was copied")
        (home / "binary/joints").chmod(0o755)
        capture_overlays(home, before)
        for rel in ("grammars.toml", "include/jnt.h", "tool/migration.py"):
            write(home, "provenance/" + rel, (ROOT / rel).read_bytes())
        for book in sorted((ROOT / "customary").glob("*.json")):
            write(home, "provenance/customary/" + book.name, book.read_bytes())
        write(home, "provenance/pin.json", encoded({k: v for k, v in record.items() if k != "root"}))
        if build:
            for stream in ("stdout", "stderr"):
                write(home, f"provenance/build.{stream}", build[stream])
        todo = cases(home, args.core)
        consumer_record = None
        if args.regulator:
            consumer_record, case = consumer(home, args.regulator, args.timeout)
            todo.append(case)
        failures = []
        for case in todo:
            try:
                got = run([str(home / "binary/joints"), *case["argv"]], home, args.timeout)
                for stream in ("stdout", "stderr"):
                    write(home, f"outputs/{case['id']}.{stream}", got[stream])
                value, strict = answer(got)
                if value["path"] != case["argv"][2]:
                    raise ValueError("parse answered a different source path")
                case.update({"exit": got["exit"], "strict": strict,
                             "stop": value["stop"], "sound": value["survey"]["sound"]})
                expectation = case["expectation"]
                if (expectation == "strict" and not strict) or (expectation == "refused" and strict):
                    raise ValueError(f"expected {expectation}, strict={strict}")
                write(home, f"outputs/{case['id']}.json", encoded(value))
                case["status"] = "captured"
            except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
                case.update({"status": "failed", "reason": str(exc)})
                failures.append(case["id"])
        if not stable(before, {n: snapshot(n) for n in BUILD_INPUTS}):
            raise ValueError("reference inputs moved during capture")
        if args.regulator:
            observed = consumer_state(args.regulator)
            if observed != consumer_record:
                raise ValueError("Regulator inputs moved during capture")
        manifest = {"format": 1, "captured_utc": datetime.now(timezone.utc).isoformat(),
                    "status": "failed" if failures else "captured", "repositories": before,
                    "build_attestation": "before-and-after" if args.build else "observed-at-freeze-only",
                    "build_command": ["{PYTHON}", "tool/pin.py", "build", "--name", "rust-reference"]
                    if args.build else None,
                    "host": {"system": platform.system(), "machine": platform.machine(),
                             "release": platform.release()}, "tools": tools,
                    "binary": {"stored": "binary/joints", "sha256": record["build"]},
                    "environment": {"removed_prefixes": ["JOINTS_", "IRGX_", "IRREGEX_"],
                                    "LC_ALL": "C", "TZ": "UTC", "NO_COLOR": "1"},
                    "consumer": consumer_record,
                    "coverage": {"core_corpus": args.core,
                                 "regulator": "parse-only" if args.regulator else "not-captured",
                                 "independent_oracle": "not-run", "platforms": [platform.system()]},
                    "expected_cases": [c["id"] for c in todo],
                    "comparison": "exact structured JSON and exit; omit stop.state only",
                    "cases": todo, "files": inventory(home)}
        write(home, "manifest.json", encoded(manifest))
        shutil.copytree(home, out)
    print(f"migration: {len(todo)} cases, {len(failures)} capture failures; {out}")
    return 1 if failures else 0


def checked(home: Path) -> dict:
    value = json.loads((home / "manifest.json").read_bytes())
    if value.get("format") != 1 or not value.get("cases"):
        raise ValueError("unsupported or empty migration manifest")
    if value.get("status") != "captured" or any(c.get("status") != "captured" for c in value["cases"]):
        raise ValueError("bundle contains failed or missing captures")
    ids = [c["id"] for c in value["cases"]]
    if len(set(ids)) != len(ids) or ids != value.get("expected_cases"):
        raise ValueError("captured roster differs from expected cases")
    for rel, expected in value["files"].items():
        path = home / rel
        if path.resolve().is_relative_to(home.resolve()) is False:
            raise ValueError(f"bundle path escapes evidence: {rel}")
        if not path.is_file() or sha(path.read_bytes()) != expected:
            raise ValueError(f"bundle bytes missing or changed: {rel}")
    for case in value["cases"]:
        for rel in (f"outputs/{case['id']}.json", f"outputs/{case['id']}.stdout",
                    f"outputs/{case['id']}.stderr", *case["argv"][1:3]):
            if rel not in value["files"]:
                raise ValueError(f"case lacks hashed evidence: {rel}")
    return value


def replay(args) -> int:
    home = args.bundle.resolve()
    manifest = checked(home)
    binary = args.binary.resolve() if args.binary else home / (manifest["binary"]["stored"] or "MISSING")
    if not binary.is_file():
        raise ValueError("export has no executable; replay requires --binary PATH")
    binary_digest = sha(binary.read_bytes())
    manifest_digest = sha((home / "manifest.json").read_bytes())
    if args.binary is None and binary_digest != manifest["binary"]["sha256"]:
        raise ValueError("reference executable changed")
    print(f"migration: replay executable sha256 {binary_digest}")
    failed = 0
    for case in manifest["cases"]:
        try:
            got = run([str(binary), *case["argv"]], home, args.timeout)
            value, _ = answer(got)
            expected = json.loads((home / f"outputs/{case['id']}.json").read_bytes())
            if got["exit"] != case["exit"] or semantic(value) != semantic(expected):
                raise ValueError("exit or structured parse evidence differs")
            print(f"migration: {case['id']}: matched")
        except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
            failed += 1
            print(f"migration: {case['id']}: FAILED: {exc}", file=sys.stderr)
    if sha(binary.read_bytes()) != binary_digest or sha((home / "manifest.json").read_bytes()) != manifest_digest:
        raise ValueError("executable or manifest moved during replay")
    checked(home)
    print(f"migration: replayed {len(manifest['cases'])} cases, {failed} failures")
    return 1 if failed else 0


def export(args) -> int:
    home, out = args.bundle.resolve(), args.out.resolve()
    manifest = checked(home)
    if out.exists():
        raise ValueError(f"refusing to replace existing evidence: {out}")
    selected = [c for c in manifest["cases"] if c["id"].startswith("json-") or c["id"] == "corpus-json"]
    keep = {rel for rel in manifest["files"] if rel.startswith("provenance/")}
    for case in selected:
        keep.update(case["argv"][1:3])
        keep.update(f"outputs/{case['id']}.{suffix}" for suffix in ("json", "stdout", "stderr"))
    for rel in sorted(keep):
        write(out, rel, (home / rel).read_bytes())
    manifest["cases"] = selected
    manifest["expected_cases"] = [c["id"] for c in selected]
    manifest["binary"]["stored"] = None
    manifest["coverage"]["core_corpus"] = False
    manifest["coverage"]["regulator"] = "not-captured-in-subset"
    manifest["consumer"] = None
    manifest["exported_subset"] = "JSON slice; full reference remains local"
    manifest["files"] = inventory(out)
    write(out, "manifest.json", encoded(manifest))
    print(f"migration: exported {len(selected)} portable cases to {out}; executable excluded")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    for command in ("freeze", "verify", "replay", "export"):
        p = sub.add_parser(command)
        p.add_argument("--bundle", type=Path, default=DEFAULT)
        p.add_argument("--timeout", type=int, default=600)
        if command == "freeze":
            p.add_argument("--binary", type=Path, default=PIN)
            p.add_argument("--out", type=Path, default=DEFAULT)
            p.add_argument("--build", action="store_true")
            p.add_argument("--core", action="store_true", help="require all eleven pinned corpus languages")
            p.add_argument("--regulator", type=Path, help="Regulator crates/python-joints directory; parse-only baseline")
        elif command == "replay":
            p.add_argument("--binary", type=Path)
        elif command == "export":
            p.add_argument("--out", type=Path, required=True)
            p.add_argument("--suite", choices=("json",), default="json", help="portable JSON-only fixture subset")
    args = parser.parse_args(argv)
    try:
        if args.command == "verify":
            manifest = checked(args.bundle.resolve())
            print(f"migration: bundle integrity verified, {len(manifest['cases'])} captured cases; "
                  "run replay to check executable behavior")
            return 0
        return {"freeze": freeze, "replay": replay, "export": export}[args.command](args)
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print(f"migration: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

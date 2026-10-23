#!/usr/bin/env python3
"""Retain starting-Rust public API diagnostics after native source correctness."""
from pathlib import Path
import json
import shutil
import sys
import time

import rust_qualify as qualify


def benchmark_executable(stdout, name="runtime", kind="bench"):
    found = []
    for line in stdout.splitlines():
        row = json.loads(line)
        if (row.get("reason") == "compiler-artifact"
                and row.get("target", {}).get("name") == name
                and row.get("target", {}).get("kind") == [kind]
                and row.get("executable")):
            found.append(Path(row["executable"]).resolve(strict=True))
    qualify.require(len(found) == 1, "benchmark build did not identify exactly one runtime executable")
    return found[0]


def require_same_benchmark(baseline, candidate):
    qualify.require(qualify.digest(baseline) == qualify.digest(candidate),
                    "starting and candidate benchmark programs differ")


def run(root, out, baseline, chain, env, source_report, source_report_path):
    """No target verdict is used as a source-correctness or cutover verdict."""
    qualify.require(len(baseline) == 40 and all(c in "0123456789abcdef" for c in baseline),
                    "performance baseline must be an exact lowercase commit")
    home = root.parent / "joints-starting-rust"
    qualify.require(not home.exists(), "starting-Rust worktree already exists")
    out.mkdir()
    report_path = out / "report.json"
    report = {"schema": 1, "status": "running", "pass": False,
              "started": time.time(), "baseline_commit": baseline,
              "producer_sha256": qualify.digest(__file__),
              "native_archive_sha256": qualify.digest(Path(env["IRGX_LIB_DIR"]) / "libirgx.a"),
              "commands": [], "cases": [], "cutover_authorized": False,
              "scope": "15 public API workloads on four cases against starting Rust; alternating warm-process samples, no RSS or fixed Rust/Zig cutover verdict"}
    qualify.save(report_path, report)

    def command(label, argv, cwd=root, controls=env, timeout=1800):
        return qualify.command(argv, cwd, controls, out, label, timeout, report, report_path)

    try:
        command("baseline-ancestor", ["git", "merge-base", "--is-ancestor", baseline, "HEAD"])
        command("baseline-checkout", ["git", "worktree", "add", "--detach", home, baseline])
        require_same_benchmark(home / "rust/benches/runtime.rs", root / "rust/benches/runtime.rs")
        report["lockfiles"] = {name: qualify.digest(source / "rust/Cargo.lock")
                               for name, source in (("baseline", home), ("candidate", root))}
        command("fetch-baseline", [chain["cargo"]["path"], "fetch", "--manifest-path", home / "rust/Cargo.toml", "--locked"],
                cwd=home, controls=env | {"CARGO_NET_OFFLINE": "false"}, timeout=900)
        report["benchmark_sha256"] = qualify.digest(root / "rust/benches/runtime.rs")
        report["recorder_sha256"] = qualify.digest(root / "tool/rust_perf.py")
        binaries = out / "binaries"
        binaries.mkdir()
        for name, source in (("baseline", home), ("candidate", root)):
            controls = env if name == "candidate" else env | {"CARGO_TARGET_DIR": str(out / "target-baseline")}
            row = command("build-" + name,
                          qualify.cargo_command(chain, ["bench", "--bench", "runtime", "--no-run",
                                                         "--message-format=json"], source / "rust/Cargo.toml"),
                          cwd=source, controls=controls)
            executable = benchmark_executable(Path(row["stdout"]["path"]).read_text())
            shutil.copy2(executable, binaries / name)
            row = command("build-cli-" + name,
                          qualify.cargo_command(chain, ["build", "--release", "--bin", "joints-rs",
                                                         "--message-format=json"], source / "rust/Cargo.toml"),
                          cwd=source, controls=controls)
            executable = benchmark_executable(Path(row["stdout"]["path"]).read_text(), "joints-rs", "bin")
            shutil.copy2(executable, binaries / (name + "-cli"))
        command("baseline-clean", ["git", "diff", "--exit-code", "HEAD"], cwd=home)
        require_same_benchmark(home / "rust/benches/runtime.rs", root / "rust/benches/runtime.rs")
        report["binaries"] = {path.name: {"path": str(path), "sha256": qualify.digest(path)}
                              for path in sorted(binaries.iterdir())}
        artifacts = out / "artifacts"
        artifacts.mkdir()
        report["artifact_equivalence"] = []
        for name, grammar in (("json", "test/grammar/json.json"),
                              ("go", "upstream/grammars/go.json"),
                              ("python", "upstream/grammars/python.json")):
            paths = [artifacts / (name + "-" + backend + ".folio") for backend in ("baseline", "candidate")]
            for backend, path in zip(("baseline", "candidate"), paths):
                command("mint-" + name + "-" + backend,
                        [binaries / (backend + "-cli"), "mint", root / grammar, "-o", path])
            qualify.require(paths[0].read_bytes() == paths[1].read_bytes(), "starting and candidate artifact bytes differ: " + name)
            report["artifact_equivalence"].append({"case": name, "sha256": qualify.digest(paths[0]),
                                                    "bytes": paths[0].stat().st_size})
        # All own compiler jobs have finished before the first timed child.
        cases = (("json-wide", "test/grammar/json.json", None),
                 ("json-ledger", "test/grammar/json.json", "research/joinery/corpus/ledger.json"),
                 ("go-ledger", "upstream/grammars/go.json", "research/joinery/corpus/ledger.go"),
                 ("python-ledger", "upstream/grammars/python.json", "research/joinery/corpus/ledger.py"))
        for name, grammar, source in cases:
            destination = out / name
            argv = [sys.executable, "-B", root / "tool/rust_perf.py",
                    "--baseline", binaries / "baseline", "--candidate", binaries / "candidate",
                    "--output", destination, "--rounds", "3", "--samples", "15", "--iterations", "1",
                    "--entries", "4096", "--grammar", root / grammar]
            if source:
                argv.extend(["--source", root / source])
            command("measure-" + name, argv, timeout=2400)
            summary = json.loads((destination / "summary.json").read_text())
            qualify.require(summary.get("inputs_stable") is True and len(summary["operations"]) == 15,
                            "incomplete or changed public API diagnostic")
            qualify.require(all(row[backend]["samples"] == 45 for row in summary["operations"]
                                for backend in ("baseline", "candidate")),
                            "public API diagnostic sample coverage differs")
            report["cases"].append({"name": name, "summary": str(destination / "summary.json"),
                                    "summary_sha256": qualify.digest(destination / "summary.json"),
                                    "all_meet_5x": summary["all_meet_5x"]})
            qualify.save(report_path, report)
        qualify.require(all(qualify.digest(row["path"]) == row["sha256"] for row in report["binaries"].values())
                        and qualify.digest(Path(env["IRGX_LIB_DIR"]) / "libirgx.a") == report["native_archive_sha256"]
                        and qualify.digest(root / "tool/rust_perf.py") == report["recorder_sha256"],
                        "diagnostic executable, native archive or recorder changed between cases")
        require_same_benchmark(home / "rust/benches/runtime.rs", root / "rust/benches/runtime.rs")
        report.update(status="completed", **{"pass": True},
                      all_meet_5x=all(row["all_meet_5x"] for row in report["cases"]))
    except Exception as error:
        report.update(status="failed", error=f"{type(error).__name__}: {error}")
        raise
    finally:
        report["finished"] = time.time()
        qualify.save(report_path, report)
        source_report["starting_rust_diagnostics"] = {"path": str(report_path), "sha256": qualify.digest(report_path)}
        qualify.save(source_report_path, source_report)

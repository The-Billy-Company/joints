#!/usr/bin/env python3
"""Record fresh host Rust workspace qualification without changing old evidence.

First create a checked native context with tool/rust.py. Then run, for example:
  mise exec python@3.12.15 -- python -B tool/rust_qualify.py --native-context .local/rust-native/last-cargo-munch-image1.json \
    --output .local/rust-migration/current/qualification-1 --toolchain 1.96.0 --toolchain 1.85.0 \
    --sdkroot /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk --jobs 2

All targets and logs are new. The default tests remain default tests: ignored
witnesses and corpora are not silently enabled. An optional gate plan can run
separately prepared correctness or benchmark commands after workspace success.
Its JSON entries contain label, argv, cwd, input_files, and report; {output}
expands to a fresh per-gate output path. No shell is used. Each gate must publish
a positive, stable report. This recorder never establishes cutover permission.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import subprocess
import sys
import time

import rust

SOURCE = Path(__file__).resolve().parents[1]
ABI = "irgx-abi2-108-munch-image1"
SUCCESS = {"complete", "completed", "executed", "qualified"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    path = Path(path)
    require(path.is_file() and not path.is_symlink(), f"not a regular input: {path}")
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def save(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def parse_tests(stdout):
    """Reconcile every captured libtest summary with actual named outcomes."""
    tests = [{"name": name, "status": status, **({"reason": reason} if reason else {})}
             for name, status, reason in re.findall(
                 r"^test (.+?) \.\.\. (ok|FAILED|ignored)(?:, (.*))?$", stdout, re.M)]
    summaries = [list(map(int, row)) for row in re.findall(
        r"^test result: (?:ok|FAILED)\. (\d+) passed; (\d+) failed; (\d+) ignored; "
        r"(\d+) measured; (\d+) filtered out;", stdout, re.M)]
    require(summaries, "test command produced no libtest summaries")
    totals = [sum(row[index] for row in summaries) for index in range(5)]
    actual = collections.Counter(row["status"] for row in tests)
    require(totals[:3] == [actual["ok"], actual["FAILED"], actual["ignored"]],
            "named outcomes do not account for every libtest summary")
    require(totals[0] > 0 and totals[1] == totals[3] == totals[4] == 0,
            "default suite failed, measured, filtered out, or ran no tests")
    return {"tests": tests, "summaries": summaries,
            "totals": dict(zip(("passed", "failed", "ignored", "measured", "filtered"), totals))}


def roster(result):
    return collections.Counter((row["name"], row["status"], row.get("reason"))
                               for row in result["tests"])


def environment(toolchain, target, library, sdkroot):
    exact = {"RUSTC", "RUSTDOC", "RUSTFLAGS", "RUSTDOCFLAGS", "RUSTUP_TOOLCHAIN", "CARGO",
             "CARGO_ENCODED_RUSTFLAGS", "CARGO_ENCODED_RUSTDOCFLAGS", "CARGO_MAKEFLAGS",
             "CARGO_BUILD_TARGET", "CARGO_TARGET_DIR", "IRGX_LIB_DIR", "SDKROOT", "HOST", "TARGET",
             "CC", "CXX", "AR", "RANLIB", "CFLAGS", "CPPFLAGS", "CXXFLAGS", "ARFLAGS",
             "CRATE_CC_NO_DEFAULTS", "CC_FORCE_DISABLE", "CC_ENABLE_DEBUG_OUTPUT", "CROSS_COMPILE",
             "LD_PRELOAD", "LD_LIBRARY_PATH", "RUST_MIN_STACK", "LIBRARY_PATH", "CPATH",
             "C_INCLUDE_PATH", "CPLUS_INCLUDE_PATH", "OBJC_INCLUDE_PATH", "MACOSX_DEPLOYMENT_TARGET", "DEVELOPER_DIR"}
    prefixes = ("RUSTC_", "RUSTDOC_", "RUST_TEST_", "CARGO_BUILD_", "CARGO_TARGET_", "CARGO_PROFILE_",
                "CARGO_REGISTRIES_", "CARGO_REGISTRY_", "CARGO_HTTP_", "CARGO_NET_", "CARGO_ALIAS_",
                "CC_", "CXX_", "AR_", "RANLIB_", "CFLAGS_", "CPPFLAGS_", "CXXFLAGS_", "ARFLAGS_",
                "HOST_", "TARGET_", "PCRE2_", "LIBPCRE2_", "PKG_CONFIG", "CLIPPY_", "DYLD_",
                "ASAN_", "LSAN_", "TSAN_", "UBSAN_", "JOINTS_", "JNT_", "IRGX_", "IRREGEX_")
    result = {key: value for key, value in os.environ.items()
              if key not in exact and not key.startswith(prefixes)}
    result.update(RUSTC=toolchain["rustc"]["path"], RUSTDOC=toolchain["rustdoc"]["path"],
                  CARGO=toolchain["cargo"]["path"], RUSTUP_TOOLCHAIN=toolchain["version"],
                  PATH=str(Path(toolchain["cargo"]["path"]).parent) + os.pathsep + os.defpath,
                  IRGX_LIB_DIR=str(library), CARGO_TARGET_DIR=str(target), CARGO_NET_OFFLINE="true",
                  CARGO_INCREMENTAL="0", RUST_BACKTRACE="0", PYTHONDONTWRITEBYTECODE="1",
                  PCRE2_SYS_STATIC="1", LIBPCRE2_8_NO_PKG_CONFIG="1", LC_ALL="C", NO_COLOR="1")
    if sdkroot:
        result.update(SDKROOT=str(sdkroot), MACOSX_DEPLOYMENT_TARGET="13.0",
                      DEVELOPER_DIR="/Library/Developer/CommandLineTools")
        result["PATH"] += ":/Library/Developer/CommandLineTools/usr/bin"
    return result


def qualification_environment(toolchain, target, library, sdkroot, jobs):
    result = environment(toolchain, target, library, sdkroot)
    if jobs is not None:
        require(jobs > 0, "jobs must be positive")
        # Inherited CARGO_BUILD_* overrides remain scrubbed. Only this explicit
        # process-local qualification option can select Cargo parallelism.
        result["CARGO_BUILD_JOBS"] = str(jobs)
    return result


def config_inputs(crate):
    homes = {crate, *crate.parents, Path(os.environ.get("CARGO_HOME", str(Path.home() / ".cargo")))}
    paths = {home / sub for home in homes for sub in
             (".cargo/config", ".cargo/config.toml", ".clippy.toml", "clippy.toml")}
    paths.update(Path(os.environ.get("CARGO_HOME", str(Path.home() / ".cargo"))) / name
                 for name in ("config", "config.toml"))
    return {str(path): digest(path) if path.exists() or path.is_symlink() else None
            for path in sorted(paths)}


def command(argv, cwd, env, out, label, timeout, report, report_path):
    row = {"label": label, "argv": list(map(str, argv)), "cwd": str(cwd), "started": time.time(),
           "environment": {key: value for key, value in env.items() if key in
                           ("RUSTC", "RUSTDOC", "CARGO", "RUSTUP_TOOLCHAIN", "PATH", "SDKROOT", "MACOSX_DEPLOYMENT_TARGET", "DEVELOPER_DIR", "IRGX_LIB_DIR",
                            "CARGO_TARGET_DIR", "CARGO_NET_OFFLINE", "CARGO_INCREMENTAL", "CARGO_BUILD_JOBS", "PCRE2_SYS_STATIC",
                            "LIBPCRE2_8_NO_PKG_CONFIG", "HOME", "CARGO_HOME", "RUSTUP_HOME")}}
    report["commands"].append(row)
    save(report_path, report)
    stdout, stderr = out / (label + ".stdout"), out / (label + ".stderr")
    try:
        with stdout.open("wb") as so, stderr.open("wb") as se:
            process = subprocess.Popen(row["argv"], cwd=cwd, env=env, stdout=so, stderr=se,
                                       start_new_session=True)
            try:
                row["returncode"] = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
                row.update(returncode=process.returncode, timeout=True)
    except Exception as error:
        row["launch_error"] = f"{type(error).__name__}: {error}"
        raise
    finally:
        row["finished"] = time.time()
        for key, path in (("stdout", stdout), ("stderr", stderr)):
            if path.is_file():
                row[key] = {"path": str(path), "sha256": digest(path)}
        save(report_path, report)
    require(row["returncode"] == 0, f"{label} failed; remaining gates were not attempted")
    return row


def selected_toolchain(version, primary=False):
    result = {"version": version}
    names = ("cargo", "rustc", "rustdoc", "cargo-clippy", "clippy-driver") + (("rustfmt", "cargo-fmt") if primary else ())
    for tool in names:
        path = Path(subprocess.run(["rustup", "which", "--toolchain", version, tool],
                                  check=True, capture_output=True, text=True).stdout.strip()).resolve(strict=True)
        result[tool] = {"path": str(path), "sha256": digest(path)}
    for tool in ("rustc", "cargo"):
        result[tool]["version"] = subprocess.run([result[tool]["path"], "-Vv"], check=True,
                                                  capture_output=True, text=True).stdout
    return result


def cargo_command(toolchain, cargo_args, manifest):
    # Cargo searches CARGO_HOME/bin before PATH for external subcommands. Invoke
    # our pinned executable directly so rustup's default cannot choose a driver
    # from another compiler, even when the selected cargo itself is absolute.
    kind = cargo_args[0]
    executable = "cargo-" + kind if kind in ("fmt", "clippy") else "cargo"
    argv = [toolchain[executable]["path"], kind, "--manifest-path", str(manifest)]
    if kind != "fmt":
        argv.extend(["--locked", "--offline"])
    return argv + cargo_args[1:]


def package_inputs(packages):
    """Pin complete dependency packages, including C sources and include data."""
    result = {}
    for package in packages:
        home = Path(package["manifest_path"]).resolve(strict=True).parent
        for parent, directories, names in os.walk(home, followlinks=False):
            directories[:] = sorted(name for name in directories
                                    if name not in (".git", "target", ".local", ".zig-cache", "zig-out", "zig-pkg"))
            require(not any((Path(parent) / name).is_symlink() for name in directories),
                    f"dependency source directory is a symlink: {parent}")
            for name in names:
                path = Path(parent) / name
                result[str(path)] = digest(path)
    return result


def format_arguments(metadata):
    members = set(metadata["workspace_members"])
    packages = sorted(package["name"] for package in metadata["packages"] if package["id"] in members)
    require(len(packages) == len(members) and packages, "workspace format package selection is incomplete")
    return ["fmt", *(argument for name in packages for argument in ("--package", name)), "--", "--check"]


def run(args):
    out = args.output.resolve()
    require(not out.exists() and not out.is_symlink(), "output directory already exists")
    require(not out.is_relative_to(SOURCE / "rust"), "build output must be outside Rust sources")
    out.mkdir(parents=True)
    report_path = out / "report.json"
    report = {"schema": 1, "status": "running", "pass": False, "stable": False, "commands": [],
              "started": time.time(), "source": str(SOURCE), "host": platform.platform(),
              "scope": "fresh host workspace correctness; no corpus, platform-floor or cutover claim",
              "cutover_authorized": False}
    save(report_path, report)
    files = {}
    before = None
    selection = native = tools = None
    suite = None
    packages = None
    dependency_before = None
    try:
        context_path = args.native_context.resolve(strict=True)
        files[str(context_path)] = digest(context_path)
        context = json.loads(context_path.read_bytes())
        require(context.get("exit") == 0 and context.get("stable") is True, "native context is not positive/stable")
        selection, native = context["native_link"], context["native"]
        tools = selection["identity"]["tools"]
        require(selection["identity"]["abi_family"] == args.irgx_abi_family, "native ABI family differs")
        require(rust.inputs() == native["inputs"], "current native sources differ from checked context")
        rust.check_native_link(selection, native, tools, abi_family=args.irgx_abi_family)
        before = rust.rust_inputs()
        files.update({str(SOURCE / name): value for name, value in before.items()})
        files.update(rust.producer_inputs())
        files[str(Path(__file__).resolve())] = digest(__file__)
        files.update(config_inputs(SOURCE / "rust"))
        versions = args.toolchain or ["1.96.0", "1.85.0"]
        require(len(versions) == len(set(versions)), "duplicate Rust toolchain")
        toolchains = [selected_toolchain(version, index == 0) for index, version in enumerate(versions)]
        for toolchain in toolchains:
            files.update({item["path"]: item["sha256"] for item in toolchain.values() if isinstance(item, dict)})
        if args.sdkroot:
            require(args.sdkroot.is_dir(), "SDK directory unavailable")
            files[str(args.sdkroot / "SDKSettings.json")] = digest(args.sdkroot / "SDKSettings.json")
            for name in ("clang", "ld", "ar", "libtool"):
                path = Path("/Library/Developer/CommandLineTools/usr/bin") / name
                files[str(path)] = digest(path)
            for name in ("cc", "ar", "ld", "xcrun"):
                path = Path("/usr/bin") / name
                files[str(path)] = digest(path)
        elif platform.system() == "Darwin":
            raise ValueError("macOS qualification requires an explicit --sdkroot")
        else:
            for name in ("cc", "ar", "ld"):
                selected = shutil.which(name, path=os.defpath)
                require(selected, "host native tool unavailable: " + name)
                path = Path(selected).resolve(strict=True)
                files[str(path)] = digest(path)
        plan = []
        if args.gate_plan:
            plan_path = args.gate_plan.resolve(strict=True)
            files[str(plan_path)] = digest(plan_path)
            plan = json.loads(plan_path.read_bytes())
            require(isinstance(plan, list), "gate plan must be a list")
            labels = set()
            for gate in plan:
                require(re.fullmatch(r"[a-z][a-z0-9-]*", gate["label"]) and gate["label"] not in labels,
                        "invalid/duplicate gate label")
                labels.add(gate["label"])
                require(isinstance(gate["argv"], list) and gate["argv"] and gate["input_files"], "empty gate argv/input closure")
                require(not any(re.search(r"(?:^|[/_ -])(holdout|sealed)(?:$|[/_ -])", str(value), re.I)
                                for value in [*gate["argv"], gate["cwd"], *gate["input_files"]]),
                        "sealed/holdout gates require their separate policy")
                for path, expected in gate["input_files"].items():
                    require(path not in files or files[path] == expected, "conflicting gate input hash")
                    files[path] = expected
        report.update(toolchains=toolchains, rust_inputs=before, native=native, native_link=selection, build_jobs=args.jobs,
                      inputs=files, caller_homes={key: os.environ.get(key) for key in ("HOME", "CARGO_HOME", "RUSTUP_HOME")})

        def check():
            require(rust.rust_inputs() == before, "Rust sources changed during qualification")
            require(rust.inputs() == native["inputs"], "native sources changed during qualification")
            for path, expected in files.items():
                actual = digest(path) if Path(path).exists() or Path(path).is_symlink() else None
                require(actual == expected, f"input changed: {path}")
            rust.check_native_link(selection, native, tools, abi_family=args.irgx_abi_family)

        check()
        save(report_path, report)
        crate = SOURCE / "rust"
        env = qualification_environment(toolchains[0], out / ("target-" + versions[0]), selection["library_dir"], args.sdkroot, args.jobs)
        metadata = command([toolchains[0]["cargo"]["path"], "metadata", "--manifest-path", str(crate / "Cargo.toml"),
                            "--locked", "--offline", "--format-version", "1"], crate, env, out, "metadata",
                           args.timeout, report, report_path)
        metadata_value = json.loads(Path(metadata["stdout"]["path"]).read_bytes())
        packages = metadata_value["packages"]
        report["metadata_package_count"] = len(packages)
        # Workspace and source-engine inputs already have explicit compiled
        # source closures. Keep documentation outside that build identity, as
        # the standalone exporter does; pin complete external packages below.
        for package in packages:
            if package.get("source") is None:
                path = Path(package["manifest_path"]).resolve(strict=True)
                require(path.is_relative_to(SOURCE / "rust") or path.is_relative_to(rust.IRREGEX / "bindings/rust"),
                        "local Cargo dependency is outside the retained source closures")
        packages = [package for package in packages if package.get("source") is not None]
        dependency_before = package_inputs(packages)
        for path, expected in dependency_before.items():
            require(path not in files or files[path] == expected, "dependency source conflicts with workspace proof")
            files[path] = expected
        report["dependency_package_count"] = len(packages)
        report["sources"] = rust.preserve_sources(SOURCE, before, "joints")
        check()
        jobs = [(0, "fmt", format_arguments(metadata_value))]
        for index, _ in enumerate(toolchains):
            jobs.extend([(index, "check", ["check", "--workspace", "--all-targets", "--all-features"]),
                         (index, "test", ["test", "--workspace", "--", "--color=never", "--test-threads=1"]),
                         (index, "clippy", ["clippy", "--workspace", "--all-targets", "--all-features", "--", "-D", "warnings"])])
        jobs.append((0, "release", ["build", "--workspace", "--release"]))
        for index, kind, cargo_args in jobs:
            check()
            toolchain = toolchains[index]
            label = kind + "-" + versions[index]
            env = qualification_environment(toolchain, out / ("target-" + versions[index]), selection["library_dir"], args.sdkroot, args.jobs)
            argv = cargo_command(toolchain, cargo_args, crate / "Cargo.toml")
            print(label, flush=True)
            row = command(argv, crate, env, out, label, args.timeout, report, report_path)
            if kind == "test":
                row["test_results"] = parse_tests(Path(row["stdout"]["path"]).read_text())
                if suite is not None:
                    require(roster(row["test_results"]) == roster(suite), "test rosters differ between toolchains")
                suite = row["test_results"]
            check()
        release = out / ("target-" + versions[0]) / "release"
        names = ["joints-rs", "libjnt.a", "libjnt.dylib" if platform.system() == "Darwin" else "libjnt.so"]
        report["release_outputs"] = {str(release / name): digest(release / name) for name in names}
        report["workspace_qualified"] = True
        for gate in plan:
            check()
            gate_out = out / ("gate-" + gate["label"])
            argv = [value.replace("{output}", str(gate_out)) for value in gate["argv"]]
            row = command(argv, Path(gate["cwd"]), env, out, "gate-" + gate["label"],
                          gate.get("timeout", args.timeout), report, report_path)
            gate_report = Path(gate["report"].replace("{output}", str(gate_out))).resolve()
            require(gate_report.is_relative_to(gate_out), "gate report is outside fresh output")
            value = json.loads(gate_report.read_bytes())
            require(value.get("status") in SUCCESS and value.get("stable") is True and value.get("pass", True) is True,
                    "external gate report is not positive/stable")
            row["gate_report"] = {"path": str(gate_report), "sha256": digest(gate_report)}
            check()
        report.update(status="completed", **{"pass": True})
    except Exception as error:
        report.update(status="failed", error=f"{type(error).__name__}: {error}")
    finally:
        try:
            if before is not None:
                require(rust.rust_inputs() == before, "final Rust source custody differs")
            if native is not None:
                require(rust.inputs() == native["inputs"], "final native source custody differs")
            if packages is not None:
                require(package_inputs(packages) == dependency_before, "final dependency inventory differs")
            for path, expected in files.items():
                actual = digest(path) if Path(path).exists() or Path(path).is_symlink() else None
                require(actual == expected, f"final input custody differs: {path}")
            if selection is not None:
                rust.check_native_link(selection, native, tools, abi_family=args.irgx_abi_family)
            for row in report["commands"]:
                for channel in ("stdout", "stderr", "gate_report"):
                    if channel in row:
                        require(digest(row[channel]["path"]) == row[channel]["sha256"], "recorded output changed")
            for path, expected in report.get("release_outputs", {}).items():
                require(digest(path) == expected, "release output changed")
            report["stable"] = True
        except Exception as error:
            report.update(status="failed", stable=False, **{"pass": False}, custody_error=f"{type(error).__name__}: {error}")
        report["finished"] = time.time()
        save(report_path, report)
    return 0 if report["pass"] and report["stable"] else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native-context", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--toolchain", action="append", help="repeat; primary compiler first (default 1.96.0 then 1.85.0)")
    parser.add_argument("--sdkroot", type=Path)
    parser.add_argument("--irgx-abi-family", choices=("irgx-abi2-105", ABI), default=ABI)
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--jobs", type=int, help="positive process-local Cargo build job limit; inherited overrides remain scrubbed")
    parser.add_argument("--gate-plan", type=Path)
    args = parser.parse_args()
    require(args.timeout > 0, "timeout must be positive")
    require(args.jobs is None or args.jobs > 0, "jobs must be positive")
    with rust.build_lock():
        return run(args)


if __name__ == "__main__":
    raise SystemExit(main())

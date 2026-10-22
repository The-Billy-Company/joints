#!/usr/bin/env python3
"""Run source Rust correctness on native CI hosts, without packaging or cutover.

Inputs are the checked-out sources and the public grammar pins. Native108
selection and command/test accounting reuse the existing qualification tools.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import time

import grammars
import rust
import rust_qualify as qualify

ROOT = Path(__file__).resolve().parents[1]
IRGX_REVISION = "59dede3d8ac5a280ca5addc8d5ceefe3aa9917f9"
TOOLCHAINS = ("1.96.0", "1.85.0")
ZIG_VERSION = "0.16.0"
PYTHON_VERSION = (3, 12, 15)
XCODE = Path("/Applications/Xcode_15.4.app/Contents/Developer")
SDK_VERSION = "14.5"
TARGETS = {"macos-arm64": "aarch64-macos.14.0", "linux-x86_64": "x86_64-linux-gnu.2.39"}


def output(argv, *, cwd=ROOT, env=None):
    return subprocess.run(list(map(str, argv)), cwd=cwd, env=env, check=True,
                          capture_output=True, text=True).stdout.strip()


def host_identity(target):
    value = {"system": platform.system(), "machine": platform.machine(),
             "platform": platform.platform(), "libc": platform.libc_ver(),
             "runner_image": {name: os.environ.get(name) for name in ("ImageOS", "ImageVersion")}}
    if target == "macos-arm64":
        qualify.require((value["system"], value["machine"]) == ("Darwin", "arm64")
                        and platform.mac_ver()[0].split(".")[0] == "14", "actual macOS 14 ARM64 host required")
        value["macos"] = platform.mac_ver()[0]
    else:
        release = platform.freedesktop_os_release()
        qualify.require((value["system"], value["machine"]) == ("Linux", "x86_64")
                        and release.get("ID") == "ubuntu" and release.get("VERSION_ID") == "24.04"
                        and not Path("/.dockerenv").exists(), "actual Ubuntu 24.04 x86-64 host required")
        value["os_release"] = release
    return value


def check_fixture_closure(files, tracked, public):
    """Only committed inputs and exact public grammar pins can enter this CI."""
    for name, digest in files.items():
        if name in tracked:
            continue
        qualify.require(name in public and digest == public[name],
                        "uncommitted/private or changed CI fixture: " + name)


def public_grammar_inputs():
    result = {}
    for pin in grammars.load("all"):
        qualify.require(pin.reproducible, "public grammar lacks a source commit")
        result[f"upstream/grammars/{pin.name}.json"] = pin.sha256
        for companion in pin.companion:
            path = grammars.kin(pin, grammars.DEST) / companion.path
            result[str(path.relative_to(ROOT))] = companion.sha256
    return result


def run(args):
    out = args.output.resolve()
    qualify.require(not out.exists(), "CI evidence output already exists")
    out.mkdir(parents=True)
    report_path = out / "report.json"
    report = {"schema": 1, "status": "running", "pass": False, "stable": False,
              "started": time.time(), "commands": [], "target": args.target,
              "producer": {"path": str(Path(__file__).resolve()), "sha256": qualify.digest(__file__)},
              "scope": "source-built native-host correctness; release-profile default tests; no installed-package, performance, sealed, publication or cutover claim",
              "cutover_authorized": False}
    qualify.save(report_path, report)
    try:
        qualify.require(sys.version_info[:3] == PYTHON_VERSION, "Python 3.12.15 required")
        report["host"] = host_identity(args.target)
        report["source_commit"] = output(["git", "rev-parse", "HEAD"])
        qualify.require(not output(["git", "status", "--porcelain=v1", "--untracked-files=no"]),
                        "tracked joints source is dirty")
        qualify.require(output(["git", "rev-parse", "HEAD"], cwd=rust.IRREGEX) == IRGX_REVISION,
                        "native source revision differs")
        qualify.require(not output(["git", "status", "--porcelain=v1"], cwd=rust.IRREGEX),
                        "native checkout is dirty")
        tracked = set(output(["git", "ls-files", "-z"]).split("\0"))
        public = public_grammar_inputs()
        for name, expected in public.items():
            qualify.require(qualify.digest(ROOT / name) == expected, "public grammar pin differs: " + name)
        before = rust.rust_inputs()
        check_fixture_closure(before, tracked, public)
        report["rust_inputs"] = before
        report["public_grammar_inputs"] = public
        native_inputs = rust.inputs()
        zig = Path(shutil.which("zig") or "").resolve(strict=True)
        qualify.require(output([zig, "version"]) == ZIG_VERSION, "Zig 0.16.0 required")
        report["zig"] = {"path": str(zig), "sha256": qualify.digest(zig), "version": ZIG_VERSION}
        toolchains = [qualify.selected_toolchain(version, index == 0) for index, version in enumerate(TOOLCHAINS)]
        report["toolchains"] = toolchains
        sdk = None
        if args.target == "macos-arm64":
            qualify.require(XCODE.is_dir(), "pinned Xcode 15.4 is unavailable")
            sdk_env = os.environ | {"DEVELOPER_DIR": str(XCODE)}
            sdk = Path(output(["/usr/bin/xcrun", "--sdk", "macosx" + SDK_VERSION, "--show-sdk-path"], env=sdk_env)).resolve(strict=True)
            qualify.require(output(["/usr/bin/xcrun", "--sdk", "macosx" + SDK_VERSION, "--show-sdk-version"], env=sdk_env) == SDK_VERSION,
                            "pinned macOS SDK differs")
            xcode = output(["/usr/bin/xcodebuild", "-version"], env=sdk_env)
            qualify.require(xcode == "Xcode 15.4\nBuild version 15F31d", "pinned Xcode build differs")
            report["host"]["sdk"] = {"path": str(sdk), "version": SDK_VERSION,
                "settings_sha256": qualify.digest((sdk / "SDKSettings.json").resolve(strict=True)), "xcode": xcode}
        def environment(chain):
            env = qualify.qualification_environment(chain, out / ("target-" + chain["version"]), out / "unused", sdk, 2)
            if sdk:
                env.update(DEVELOPER_DIR=str(XCODE), MACOSX_DEPLOYMENT_TARGET="14.0")
            return env
        env = environment(toolchains[0])
        raw = out / "native-raw"
        native_command = [str(zig), "build", "--prefix", str(raw), "-Dtarget=" + TARGETS[args.target],
                          "-Dcpu=baseline", "-Doptimize=ReleaseFast", "-Dlib-optimize=ReleaseFast", "-Dstrip=true", "-j2"]
        qualify.command(native_command, rust.IRREGEX, env, out, "native-build", 1800, report, report_path)
        qualify.require(rust.inputs() == native_inputs, "native sources changed during build")
        archive = raw / "lib/libirgx.a"
        native = {"repository": str(rust.IRREGEX), "inputs": native_inputs, "command": native_command,
                  "archive_sha256": qualify.digest(archive), "zig": ZIG_VERSION, "sdkroot": str(sdk) if sdk else None}
        # boundary_tools invokes xcrun on macOS; keep its selected developer
        # directory identical to the SDK used by native and Cargo commands.
        if sdk:
            os.environ.update(DEVELOPER_DIR=str(XCODE), SDKROOT=str(sdk), MACOSX_DEPLOYMENT_TARGET="14.0")
        else:
            for name in ("SDKROOT", "DEVELOPER_DIR", "MACOSX_DEPLOYMENT_TARGET"):
                os.environ.pop(name, None)
        primary = toolchains[0]
        sysroot = Path(output([primary["rustc"]["path"], "--print", "sysroot"]))
        host = next(line.removeprefix("host: ") for line in primary["rustc"]["version"].splitlines() if line.startswith("host: "))
        objcopy = sysroot / "lib/rustlib" / host / "bin/llvm-objcopy"
        tools = rust.boundary_tools(objcopy=objcopy)
        with rust.build_lock():
            selected = rust.native_link(archive, native, tools, cache=out / "native-boundary", abi_family=qualify.ABI)
        report["native"] = native
        report["native_link"] = selected
        shutil.copy2(Path(selected["root"]) / "proof.json", out / "native-boundary.json")
        expected_roster = None
        for index, chain in enumerate(toolchains):
            version = chain["version"]
            env = environment(chain) | {"IRGX_LIB_DIR": selected["library_dir"]}
            manifest = ROOT / "rust/Cargo.toml"
            # Network is used only to resolve the committed Cargo.lock. Every
            # subsequent check/test uses the same lockfile offline.
            qualify.command([chain["cargo"]["path"], "fetch", "--manifest-path", str(manifest), "--locked"],
                            ROOT, env | {"CARGO_NET_OFFLINE": "false"}, out, "fetch-" + version, 900, report, report_path)
            jobs = [("check", ["check", "--workspace", "--all-targets", "--all-features"]),
                    ("clippy", ["clippy", "--workspace", "--all-targets", "--all-features", "--", "-D", "warnings"]),
                    ("test", ["test", "--workspace", "--release", "--", "--color=never", "--test-threads=1"])]
            if index == 0:
                metadata = qualify.command([chain["cargo"]["path"], "metadata", "--manifest-path", str(manifest),
                                            "--locked", "--offline", "--no-deps", "--format-version", "1"],
                                           ROOT, env, out, "metadata", 900, report, report_path)
                value = json.loads(Path(metadata["stdout"]["path"]).read_text())
                jobs.insert(0, ("fmt", qualify.format_arguments(value)))
            for label, arguments in jobs:
                row = qualify.command(qualify.cargo_command(chain, arguments, manifest), ROOT, env, out,
                                      label + "-" + version, 1800, report, report_path)
                if label == "test":
                    suite = qualify.parse_tests(Path(row["stdout"]["path"]).read_text())
                    if expected_roster is not None:
                        qualify.require(qualify.roster(suite) == expected_roster, "compiler default rosters differ")
                    expected_roster = qualify.roster(suite)
                    row["default_suite"] = suite
                qualify.require(rust.rust_inputs() == before and rust.inputs() == native_inputs,
                                "CI sources changed during checks")
                rust.check_native_link(selected, native, tools, abi_family=qualify.ABI)
        report.update(status="completed", **{"pass": True}, stable=True)
    except Exception as error:
        report.update(status="failed", error=f"{type(error).__name__}: {error}")
        raise
    finally:
        report["finished"] = time.time()
        qualify.save(report_path, report)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=TARGETS, required=True)
    parser.add_argument("--output", type=Path, required=True)
    run(parser.parse_args())


if __name__ == "__main__":
    main()

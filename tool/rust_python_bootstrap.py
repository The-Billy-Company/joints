#!/usr/bin/env python3
"""Build and attest the exact official Python on the macOS 14 ARM64 CI floor.

This stdlib-only helper also runs under the runner's bootstrap Python. It does
not select a newer host or change the pinned Xcode/SDK/compiler build recipe.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
VERSION = (3, 12, 15)
SOURCE_URL = "https://www.python.org/ftp/python/3.12.15/Python-3.12.15.tgz"
SOURCE_SHA256 = "de1a241a519e0a3374fea98988d0b52c886743f9d953f23be8269cc7b59c5fab"
BUILD_STEPS = ("sdk", "openssl-prefix", "compiler", "extract", "configure", "make", "install", "verify")
XCODE = "/Applications/Xcode_15.4.app/Contents/Developer"
SDK_VERSION = "14.5"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def checked_receipt(receipt, executable, workflow):
    """Bind the exact helper, workflow, interpreter and eight retained commands."""
    value = json.loads(Path(receipt).read_bytes())
    require(value.get("pass") is True and value["python"]["version"] == list(VERSION),
            "Python source bootstrap did not complete")
    require(value["source_url"] == SOURCE_URL
            and value["source_sha256"] == value["downloaded_source_sha256"] == SOURCE_SHA256
            and value["workflow_sha256"] == digest(workflow)
            and value["bootstrap_helper_sha256"] == digest(__file__),
            "Python source bootstrap recipe differs")
    python = Path(executable).resolve(strict=True)
    require(Path(value["python"]["path"]).resolve(strict=True) == python
            and digest(python) == value["python"]["sha256"],
            "Python source bootstrap interpreter differs")
    require([command["label"] for command in value["commands"]] == list(BUILD_STEPS),
            "Python source bootstrap command roster differs")
    for command in value["commands"]:
        require(command["exit"] == 0, "Python source bootstrap command failed")
        invocation = hashlib.sha256(json.dumps(command["argv"], separators=(",", ":")).encode()).hexdigest()
        require(invocation == command["invocation_sha256"], "Python source bootstrap invocation changed")
        for channel in ("stdout", "stderr"):
            require(digest(command[channel]["path"]) == command[channel]["sha256"],
                    "Python source bootstrap log changed")
    return {"path": str(receipt), "sha256": digest(receipt), "receipt": value}


def build(workflow, evidence, work, receipt_environment):
    require(platform.system() == "Darwin" and platform.machine() == "arm64"
            and platform.mac_ver()[0].split(".")[0] == "14", "actual macOS 14 ARM64 host required")
    require(re.fullmatch(r"[A-Z][A-Z0-9_]*", receipt_environment), "invalid receipt environment name")
    workflow = workflow.resolve(strict=True)
    require(workflow.is_file() and workflow.is_relative_to(ROOT / ".github/workflows"), "workflow is outside this checkout")
    evidence = evidence.absolute()
    work = work.absolute()
    evidence.mkdir(parents=True, exist_ok=False)
    work.mkdir(exist_ok=False)
    prefix = work / "installed"
    archive = work / "Python-3.12.15.tgz"
    receipt = {"schema": 1, "pass": False, "source_url": SOURCE_URL, "source_sha256": SOURCE_SHA256,
               "workflow_sha256": digest(workflow), "bootstrap_helper_sha256": digest(__file__),
               "bootstrap_python": {"path": sys.executable, "sha256": digest(sys.executable)},
               "host": {"system": platform.system(), "machine": platform.machine(), "macos": platform.mac_ver()[0]},
               "commands": []}

    def save():
        (evidence / "receipt.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")

    env = dict(os.environ, DEVELOPER_DIR=XCODE, MACOSX_DEPLOYMENT_TARGET="14.0", CC="/usr/bin/clang")

    def run(label, argv, cwd=work):
        row = {"label": label, "argv": list(map(str, argv)), "cwd": str(cwd),
               "environment": {key: env[key] for key in ("DEVELOPER_DIR", "MACOSX_DEPLOYMENT_TARGET", "CC", "SDKROOT") if key in env},
               "started": time.time()}
        row["invocation_sha256"] = hashlib.sha256(json.dumps(row["argv"], separators=(",", ":")).encode()).hexdigest()
        receipt["commands"].append(row)
        save()
        result = subprocess.run(row["argv"], cwd=cwd, env=env, capture_output=True)
        for channel in ("stdout", "stderr"):
            path = evidence / (label + "." + channel)
            path.write_bytes(getattr(result, channel))
            row[channel] = {"path": str(path), "sha256": digest(path)}
        row.update(exit=result.returncode, finished=time.time())
        save()
        require(result.returncode == 0, label + " failed; retained bootstrap logs contain the error")
        return result.stdout.decode().strip()

    save()
    try:
        with urllib.request.urlopen(SOURCE_URL) as response, archive.open("wb") as target:
            require(response.geturl() == SOURCE_URL, "unexpected source redirect")
            total = 0
            while True:
                block = response.read(1 << 20)
                if not block:
                    break
                total += len(block)
                require(total <= 32 << 20, "Python source exceeds byte budget")
                target.write(block)
        require(digest(archive) == SOURCE_SHA256, "official Python source SHA256 differs")
        receipt["downloaded_source_sha256"] = digest(archive)
        env["SDKROOT"] = run("sdk", ["/usr/bin/xcrun", "--sdk", "macosx" + SDK_VERSION, "--show-sdk-path"])
        openssl = run("openssl-prefix", ["brew", "--prefix", "openssl@3"])
        run("compiler", ["/usr/bin/clang", "--version"])
        run("extract", ["/usr/bin/tar", "-xzf", str(archive), "-C", str(work)])
        source = work / "Python-3.12.15"
        run("configure", [source / "configure", "--prefix=" + str(prefix), "--with-openssl=" + openssl,
                          "--with-openssl-rpath=auto", "--with-ensurepip=no"], source)
        run("make", ["/usr/bin/make", "-j2"], source)
        run("install", ["/usr/bin/make", "install"], source)
        python = prefix / "bin/python3.12"
        version = run("verify", [python, "-B", "-c", "import ctypes, ssl, sys, zlib; assert sys.version_info[:3] == (3, 12, 15); print(sys.version)"])
        (prefix / "bin/python").symlink_to("python3.12")
        require(digest(workflow) == receipt["workflow_sha256"] and digest(__file__) == receipt["bootstrap_helper_sha256"],
                "Python source bootstrap recipe changed during build")
        receipt.update(python={"path": str(python), "sha256": digest(python), "version": list(VERSION), "full_version": version},
                       openssl_libraries={str(path): digest(path) for path in sorted((Path(openssl) / "lib").glob("lib*.3.dylib"))},
                       **{"pass": True})
        save()
        checked_receipt(evidence / "receipt.json", python, workflow)
        with open(os.environ["GITHUB_PATH"], "a") as path:
            path.write(str(prefix / "bin") + "\n")
        with open(os.environ["GITHUB_ENV"], "a") as output:
            output.write(receipt_environment + "=" + str(evidence / "receipt.json") + "\n")
    except Exception as error:
        receipt.update({"pass": False, "error": f"{type(error).__name__}: {error}"})
        save()
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="verb", required=True)
    build_parser = sub.add_parser("build")
    build_parser.add_argument("--workflow", type=Path, required=True)
    build_parser.add_argument("--output", type=Path, required=True)
    build_parser.add_argument("--work", type=Path, required=True)
    build_parser.add_argument("--receipt-environment", required=True)
    check_parser = sub.add_parser("check")
    check_parser.add_argument("--workflow", type=Path, required=True)
    check_parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    if args.verb == "build":
        build(args.workflow, args.output, args.work, args.receipt_environment)
    else:
        checked_receipt(args.receipt, sys.executable, args.workflow)


if __name__ == "__main__":
    main()

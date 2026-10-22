#!/usr/bin/env python3
"""Form a fresh nonpublishable delivery bundle from a workspace qualification.

The original release static archive is retained under proof/. Only the bundle
copy receives neutral archive member names. This does not run parser tests,
publish a package, or qualify performance, target floors, or default cutover.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

import rust
import rust_archive
import rust_delivery as delivery
from rust_qualify import digest, require, save


def check_qualification(value):
    require(value.get("schema") == 1 and value.get("status") == "completed"
            and value.get("pass") is True and value.get("stable") is True
            and value.get("workspace_qualified") is True, "qualification is not completed/positive/stable")
    require(Path(value["source"]).resolve() == rust.m.ROOT.resolve(), "qualification belongs to another source root")
    require(rust.rust_inputs() == value["rust_inputs"], "qualified Rust sources differ from current source")
    require(rust.inputs() == value["native"]["inputs"], "qualified native sources differ from current source")
    for path, expected in value["inputs"].items():
        actual = digest(path) if Path(path).exists() or Path(path).is_symlink() else None
        require(actual == expected, f"qualification input changed: {path}")
    for path, expected in value["release_outputs"].items():
        require(digest(path) == expected, f"qualified release output changed: {path}")
    for row in value["commands"]:
        require(row.get("returncode") == 0, "qualification retained a failed command")
        for key in ("stdout", "stderr", "gate_report"):
            if key in row:
                require(digest(row[key]["path"]) == row[key]["sha256"], "qualification log/report changed")
    selection = value["native_link"]
    rust.check_native_link(selection, value["native"], selection["identity"]["tools"],
                           abi_family=selection["identity"]["abi_family"])


def verify_normalization(original, normalized, receipt):
    require(digest(original) == receipt["input_sha256"] and digest(normalized) == receipt["output_sha256"],
            "normalization input/output hash differs")
    before, after = rust_archive.read_archive(original), rust_archive.read_archive(normalized)
    require(len(before.members) == len(after.members) == receipt["member_count"] == len(receipt["members"])
            and len(before.members) > 0, "normalization member count differs")
    for index, (raw, chosen, proof) in enumerate(zip(before.members, after.members, receipt["members"])):
        name = f"native-{index:06d}.o"
        require(proof["position"] == index and proof["original_name_hex"] == raw.name.hex()
                and proof["normalized_name"] == name and chosen.name == name.encode()
                and before.payload(raw) == after.payload(chosen)
                and proof["sha256"] == hashlib.sha256(before.payload(raw)).hexdigest()
                and proof["bytes"] == raw.end - raw.start, "normalization altered a member or its order")


def make_bundle(qualification, output, *, zig):
    qualification = qualification.resolve(strict=True)
    output = output.resolve()
    require(not output.exists() and not output.is_symlink(), "bundle output already exists")
    require(not output.is_relative_to(rust.m.ROOT / "rust"), "bundle output is inside Rust sources")
    original_report = digest(qualification)
    value = json.loads(qualification.read_bytes())
    check_qualification(value)
    output.mkdir(parents=True)
    producer_hash = digest(__file__)
    record = {"schema": 1, "status": "running", "pass": False, "started": time.time(),
              "qualification": {"path": str(qualification), "sha256": original_report},
              "producer": {"path": str(Path(__file__).resolve()), "sha256": producer_hash},
              "scope": "local workspace-qualified bundle; compatibility/performance/platform/cutover remain separate"}
    try:
        release = value["release_outputs"]
        outputs = {Path(path).name: Path(path) for path in release}
        selection = value["native_link"]
        target = selection["identity"]["target"]
        shared = delivery.TARGETS[target][2]
        origins = {"bin/joints-rs": outputs["joints-rs"], "lib/" + shared: outputs[shared],
                   "proof/libjnt.raw.a": outputs["libjnt.a"],
                   "include/jnt.h": rust.m.ROOT / "include/jnt.h",
                   "lib/libirgx.a": Path(selection["root"]) / "original/libirgx.a"}
        origin_hashes = {name: digest(path) for name, path in origins.items()}
        require(origin_hashes["lib/libirgx.a"] == value["native"]["archive_sha256"], "raw native archive differs")
        for name, original in origins.items():
            path = output / name
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(original, path)
            require(digest(path) == origin_hashes[name], "bundle copy differs")
        shutil.copy2(qualification, output / "proof/qualification.json")
        shutil.copy2(Path(__file__).resolve(), output / "proof/rust_bundle.py")
        normalized = output / "lib/libjnt.a"
        shutil.copy2(output / "proof/libjnt.raw.a", normalized)
        normalizer = Path(rust_archive.__file__).resolve()
        normalizer_hash = digest(normalizer)
        argv = [sys.executable, "-B", str(normalizer), str(normalized), "--zig", str(zig),
                "--receipt", str(output / "proof/normalization.json")]
        record["normalization_command"] = argv
        save(output / "bundle-build.json", record)
        with (output / "proof/normalization.stdout").open("wb") as stdout, \
             (output / "proof/normalization.stderr").open("wb") as stderr:
            result = subprocess.run(argv, cwd=output, env=os.environ | {"PYTHONDONTWRITEBYTECODE": "1"},
                                    stdout=stdout, stderr=stderr, timeout=300)
        record["normalization_exit"] = result.returncode
        require(result.returncode == 0, "archive normalization failed; raw copy and logs retained")
        receipt = delivery.read_json(output / "proof/normalization.json")
        require(receipt["normalizer_sha256"] == normalizer_hash == digest(normalizer), "normalizer producer changed")
        require(receipt["archiver"]["path"] == str(zig.resolve(strict=True))
                and receipt["archiver"]["sha256"] == digest(zig), "normalization archiver identity differs")
        verify_normalization(output / "proof/libjnt.raw.a", normalized, receipt)
        identity = {"rust_inputs": value["rust_inputs"], "native": value["native"],
                    "toolchain": value["toolchains"][0], "raw_files": origin_hashes}
        build = {"schema": 1, "exit": 0, "stable": True, **identity,
                 "qualification": record["qualification"], "sources": value["sources"],
                 "native_link": selection,
                 "normalization": {"path": "proof/normalization.json", "sha256": digest(output / "proof/normalization.json")},
                 "scope": record["scope"]}
        (output / "build.json").write_bytes(delivery.encoded(build))
        check_qualification(value)
        require(digest(qualification) == original_report, "qualification changed during bundle formation")
        require(digest(__file__) == producer_hash == digest(output / "proof/rust_bundle.py"), "bundle producer changed")
        for name, original in origins.items():
            require(digest(original) == origin_hashes[name] == digest(output / name), "original or copied release changed")
        verify_normalization(output / "proof/libjnt.raw.a", normalized, receipt)
        record.update(status="completed", **{"pass": True}, finished=time.time())
        save(output / "bundle-build.json", record)
        bundle = {"schema": 1, "identity": identity,
                  "identity_sha256": hashlib.sha256(delivery.encoded(identity)).hexdigest(),
                  "files": delivery.file_map(output)}
        (output / "bundle.json").write_bytes(delivery.encoded(bundle))
        return {"bundle": str(output), "identity_sha256": bundle["identity_sha256"],
                "bundle_sha256": digest(output / "bundle.json"), "publishable": False}
    except Exception as error:
        record.update(status="failed", error=f"{type(error).__name__}: {error}", finished=time.time())
        save(output / "bundle-build.json", record)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qualification", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--zig", type=Path, required=True, help="explicit qualified Zig archiver executable")
    args = parser.parse_args()
    try:
        with rust.build_lock():
            result = make_bundle(args.qualification, args.output, zig=args.zig.resolve(strict=True))
        print(json.dumps(result, indent=2))
        return 0
    except (ValueError, OSError, KeyError, subprocess.SubprocessError) as error:
        print(f"rust bundle refused: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

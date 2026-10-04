#!/usr/bin/env python3
"""Build, prove, and resolve the separate-library experimental release."""

import argparse
import gzip
import hashlib
import io
import json
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

import registry as _registry

ROOT = Path(__file__).resolve().parents[2]
IRREGEX = "508ad3158efc8346469427e18276f01790c17229"
TARGETS = {("Linux", "x86_64"): "linux-x86_64", ("Darwin", "arm64"): "macos-arm64"}
SMOKE = Path(__file__).with_name("smoke.py")


require = _registry.require


digest = _registry.digest

encoded = _registry.encoded


def run(command, *, cwd=ROOT, env=None, capture=False):
    result = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        check=True,
        stdout=subprocess.PIPE if capture else sys.stderr,
        text=True,
    )
    return result.stdout.strip() if capture else None


def source(root=ROOT):
    head = run(["git", "rev-parse", "HEAD"], cwd=root, capture=True)
    require(re.fullmatch(r"[0-9a-f]{40}", head), "invalid source Git commit")
    dirty = bool(
        run(
            ["git", "status", "--porcelain", "--untracked-files=normal"],
            cwd=root,
            capture=True,
        )
    )
    require(not dirty, f"dirty release source: {root}")
    paths = subprocess.check_output(["git", "ls-files", "-z"], cwd=root)
    files = {}
    for name in paths.decode().split("\0"):
        if name:
            path = root / name
            require(path.is_file() and not path.is_symlink(), f"invalid source: {name}")
            files[name] = digest(path)
    return {
        "commit": head,
        "dirty": dirty,
        "files": files,
        "ledger_sha256": hashlib.sha256(encoded(files)).hexdigest(),
    }


def host():
    key = (platform.system(), platform.machine())
    require(key in TARGETS, f"unsupported release host: {key}")
    return TARGETS[key]


def shared(target):
    return "libjnt.dylib" if target == "macos-arm64" else "libjnt.so"


def native(args):
    require(args.target == host(), "native archive must be built on its named host")
    require(args.irregex_sha == IRREGEX, "unapproved irregex revision")
    require(run(["zig", "version"], capture=True) == "0.16.0", "Zig must be 0.16.0")
    before = source()
    sibling = source(ROOT.parent / "irregex")
    require(sibling["commit"] == IRREGEX, "irregex checkout revision mismatch")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f"joints-{args.version}-{args.target}.tar.gz"
    require(not archive.exists(), f"refusing to overwrite {archive}")
    with tempfile.TemporaryDirectory(prefix="joints-native-") as temporary:
        prefix = Path(temporary) / "install"
        run(["zig", "build", "--prefix", str(prefix), "-Dcpu=baseline", "-j2"])
        require(source() == before, "source changed during build")
        require(
            source(ROOT.parent / "irregex") == sibling, "irregex changed during build"
        )
        version = run([str(prefix / "bin/joints"), "--version"], capture=True)
        require(
            version in (args.version, f"joints {args.version}"), "CLI version mismatch"
        )
        payload = {
            "bin/joints": (prefix / "bin/joints").read_bytes(),
            "lib/libjnt.a": (prefix / "lib/libjnt.a").read_bytes(),
            f"lib/{shared(args.target)}": (
                prefix / "lib" / shared(args.target)
            ).read_bytes(),
            "include/jnt.h": (prefix / "include/jnt.h").read_bytes(),
            "grammar/json.json": (ROOT / "test/grammar/json.json").read_bytes(),
        }
        for name in ("LICENSE", "NOTICE", "README.md"):
            payload[name] = (ROOT / name).read_bytes()
        manifest = {
            "schema": 1,
            "version": args.version,
            "target": args.target,
            "abi": 2,
            "zig": "0.16.0",
            "cpu": "baseline",
            "build_host": _registry.build_host(),
            "command": [
                "zig",
                "build",
                "--prefix",
                "<ephemeral-staging>",
                "-Dcpu=baseline",
                "-j2",
            ],
            "source": before,
            "irregex": sibling,
            "files": {
                name: hashlib.sha256(data).hexdigest() for name, data in payload.items()
            },
        }
        payload["manifest.json"] = encoded(manifest)
        epoch = int(run(["git", "show", "-s", "--format=%ct", "HEAD"], capture=True))
        with (
            archive.open("xb") as handle,
            gzip.GzipFile(fileobj=handle, mode="wb", mtime=0) as compressed,
            tarfile.open(
                fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT
            ) as package,
        ):
            for name, data in sorted(payload.items()):
                entry = tarfile.TarInfo(f"joints-{args.version}-{args.target}/{name}")
                entry.size, entry.mtime = len(data), epoch
                entry.mode = 0o755 if name == "bin/joints" else 0o644
                package.addfile(entry, io.BytesIO(data))
    return {
        "archive": str(archive),
        "sha256": digest(archive),
        "target": args.target,
        "source": before["commit"],
    }


def unpack(archive, destination, expected_root):
    require(not destination.exists(), f"refusing to overwrite {destination}")
    destination.mkdir()
    with tarfile.open(archive, "r:gz") as package:
        members = package.getmembers()
        require(bool(members), "empty archive")
        names = set()
        total = 0
        for entry in members:
            path = PurePosixPath(entry.name)
            require(
                not path.is_absolute() and ".." not in path.parts, "archive path escape"
            )
            require(
                bool(path.parts) and path.parts[0] == expected_root,
                "unexpected archive root",
            )
            require(entry.isfile() or entry.isdir(), "archive link or special file")
            require(path.as_posix() not in names, "duplicate archive entry")
            names.add(path.as_posix())
            require(entry.size >= 0, "negative archive member size")
            total += entry.size
        require(total <= 512 * 1024 * 1024, "archive exceeds size limit")
        package.extractall(destination, members=members, filter="data")
    return destination / expected_root


def unpack_native(archive, destination, version, target=None):
    target = target or host()
    root = unpack(archive, destination, f"joints-{version}-{target}")
    manifest = json.loads((root / "manifest.json").read_bytes())
    require(
        manifest["schema"] == 1 and manifest["version"] == version,
        "native metadata version mismatch",
    )
    require(
        manifest["target"] == target
        and manifest["abi"] == 2
        and manifest["zig"] == "0.16.0"
        and manifest["cpu"] == "baseline",
        "native metadata target/ABI mismatch",
    )
    expected = {
        "bin/joints",
        "lib/libjnt.a",
        f"lib/{shared(target)}",
        "include/jnt.h",
        "grammar/json.json",
        "LICENSE",
        "NOTICE",
        "README.md",
    }
    require(set(manifest["files"]) == expected, "native member inventory mismatch")
    actual = {
        path.relative_to(root).as_posix() for path in root.rglob("*") if path.is_file()
    }
    require(actual == expected | {"manifest.json"}, "unexpected native member")
    for name, checksum in manifest["files"].items():
        require(digest(root / name) == checksum, f"native checksum mismatch: {name}")
    require(
        manifest["irregex"]["commit"] == IRREGEX, "native irregex revision mismatch"
    )
    for item in ("source", "irregex"):
        ledger = manifest[item]
        require(not ledger["dirty"], "release native built from dirty source")
        require(
            re.fullmatch(r"[0-9a-f]{40}", ledger["commit"]),
            "native source Git identity",
        )
        require(
            hashlib.sha256(encoded(ledger["files"])).hexdigest()
            == ledger["ledger_sha256"],
            "native source ledger mismatch",
        )
    return root


def cargo(args, *command, **kwargs):
    return _registry.cargo(sys.modules[__name__], args, *command, **kwargs)


def native_env(root):
    return _registry.native_env(sys.modules[__name__], root)


def packages(args):
    before = source()
    output = args.output.resolve()
    require(
        not (output / "packages.json").exists(), "refusing to overwrite package receipt"
    )
    output.mkdir(parents=True, exist_ok=True)
    for folder in ("python", "rust"):
        require(
            not (output / folder).exists(), f"refusing to overwrite {output / folder}"
        )
    with tempfile.TemporaryDirectory(prefix="joints-packages-") as temporary:
        temporary = Path(temporary)
        root = unpack_native(args.native, temporary / "native", args.version)
        require(
            json.loads((root / "manifest.json").read_bytes())["source"] == before,
            "native and package source identities differ",
        )
        env = native_env(root)
        env["SOURCE_DATE_EPOCH"] = run(
            ["git", "show", "-s", "--format=%ct", "HEAD"], capture=True
        )
        run(
            [
                "uv",
                "build",
                "--no-create-gitignore",
                "--python",
                args.python,
                "--out-dir",
                str(output / "python"),
            ],
            cwd=ROOT / "bindings/python",
            env=env,
        )
        run(
            [
                "uvx",
                "--from",
                "twine==7.0.0",
                "twine",
                "check",
                *map(str, sorted((output / "python").iterdir())),
            ]
        )
        target = temporary / "cargo-target"
        command = [
            "package",
            "--locked",
            "--manifest-path",
            "bindings/rust/Cargo.toml",
            "--target-dir",
            str(target),
        ]
        cargo(args, *command, env=native_env(root))
        destination = output / "rust"
        destination.mkdir(exist_ok=True)
        require(
            not (destination / f"joints-{args.version}.crate").exists(),
            "existing crate",
        )
        shutil.copyfile(
            target / "package" / f"joints-{args.version}.crate",
            destination / f"joints-{args.version}.crate",
        )
    require(source() == before, "source changed during packaging")
    identity = {
        "schema": 1,
        "version": args.version,
        "source": before,
        "files": package_inventory(output, args.version),
    }
    (output / "packages.json").write_bytes(encoded(identity))
    return {"packages": str(output), "files": identity["files"]}


def python_smoke(args, wheel, native_root, destination):
    run(["uv", "venv", "--python", args.python, str(destination)])
    interpreter = destination / "bin/python"
    env = native_env(native_root)
    run(
        [
            "uv",
            "pip",
            "install",
            "--python",
            str(interpreter),
            "--no-deps",
            "--no-index",
            str(wheel),
        ],
        env=env,
    )
    run(
        [
            str(interpreter),
            "-I",
            str(SMOKE),
            args.version,
            env["JOINTS_LIB"],
            str(native_root / "grammar/json.json"),
        ],
        cwd=destination.parent,
        env=env,
    )


def verify_packages(args, packages_root):
    identity = identities(packages_root, args.version)
    with tempfile.TemporaryDirectory(prefix="joints-verify-") as temporary:
        temporary = Path(temporary)
        native_root = unpack_native(args.native, temporary / "native", args.version)
        manifest = json.loads((native_root / "manifest.json").read_bytes())
        require(
            manifest["source"] == identity["source"],
            "native/package source identity mismatch",
        )
        wheel = packages_root / "python" / f"joints-{args.version}-py3-none-any.whl"
        with zipfile.ZipFile(wheel) as package:
            require(
                not any(
                    name.endswith((".so", ".dylib", ".dll", ".a"))
                    for name in package.namelist()
                ),
                "portable wheel contains native library",
            )
        python_smoke(args, wheel, native_root, temporary / "wheel-venv")
        sdist = packages_root / "python" / f"joints-{args.version}.tar.gz"
        source_root = unpack(sdist, temporary / "sdist", f"joints-{args.version}")
        run(
            [
                "uv",
                "build",
                "--wheel",
                "--no-create-gitignore",
                "--python",
                args.python,
                "--out-dir",
                str(temporary / "sdist-wheel"),
            ],
            cwd=source_root,
        )
        rebuilt = list((temporary / "sdist-wheel").glob("*.whl"))
        require(len(rebuilt) == 1, "sdist must build exactly one wheel")
        python_smoke(args, rebuilt[0], native_root, temporary / "sdist-venv")
        crate = unpack(
            packages_root / "rust" / f"joints-{args.version}.crate",
            temporary / "crate",
            f"joints-{args.version}",
        )
        env = native_env(native_root)
        env["CARGO_TARGET_DIR"] = str(temporary / "cargo-target")
        cargo(args, "test", "--locked", "--offline", cwd=crate, env=env)
        # The archive, including owner/thread compile-fail docs, is the source
        # Cargo tests; no checkout source or its target directory participates.
        require(
            digest(crate / "tests/json.json") == manifest["files"]["grammar/json.json"],
            "crate and native grammar fixtures differ",
        )
    return {
        "version": args.version,
        "target": host(),
        "installed_packages": "passed",
        "files": identity["files"],
    }


package_inventory = _registry.package_inventory
identities = _registry.identities
fetch = _registry.fetch


def resolve_registry(root, version, destination=None):
    return _registry.resolve_registry(sys.modules[__name__], root, version, destination)


def registry(args):
    return _registry.registry(sys.modules[__name__], args)


def publish_crate(args):
    return _registry.publish_crate(sys.modules[__name__], args)


def checksums(args):
    return _registry.checksums(sys.modules[__name__], args)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in (
        "native",
        "packages",
        "verify",
        "probe",
        "registry",
        "publish-crate",
        "checksums",
    ):
        command = commands.add_parser(name)
        if name != "checksums":
            command.add_argument("--version", required=True)
        if name == "native":
            command.add_argument("--target", required=True, choices=TARGETS.values())
            command.add_argument("--irregex-sha", default=IRREGEX)
            command.add_argument("--output", type=Path, required=True)
        elif name == "packages":
            command.add_argument("--output", type=Path, required=True)
        else:
            command.add_argument("--packages", type=Path, required=True)
        if name == "checksums":
            command.add_argument("--native-directory", type=Path, required=True)
            command.add_argument("--output", type=Path)
        if name in ("packages", "verify", "registry", "publish-crate"):
            command.add_argument("--native", type=Path, required=True)
            command.add_argument("--rust-toolchain", default="1.85.0")
        if name in ("packages", "verify", "registry"):
            command.add_argument("--python", default="python3.12")
    args = parser.parse_args()
    if args.command != "checksums":
        require(
            re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.version),
            "version must be X.Y.Z",
        )
    if args.command == "native":
        result = native(args)
    elif args.command == "packages":
        result = packages(args)
    elif args.command == "verify":
        result = verify_packages(args, args.packages.resolve())
    elif args.command == "probe":
        result = resolve_registry(args.packages.resolve(), args.version)
    elif args.command == "registry":
        result = registry(args)
    elif args.command == "checksums":
        result = checksums(args)
    else:
        result = publish_crate(args)
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (
        RuntimeError,
        OSError,
        ValueError,
        KeyError,
        subprocess.CalledProcessError,
    ) as error:
        print(f"release artifact error: {error}", file=sys.stderr)
        sys.exit(2)

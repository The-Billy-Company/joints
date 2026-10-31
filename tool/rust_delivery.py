#!/usr/bin/env python3
"""Export and validate a standalone local Rust candidate; never publish it.

The exported layout deliberately preserves joints/rust -> ../../irregex. The
qualified compiled-input join is narrower than the current source export: new
delivery tools and documentation are recorded without retagging a historical
whole-checkout freeze. No command builds the native engine implicitly.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
import os
import platform
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import tomllib
from pathlib import Path, PurePosixPath

import stamp

ROOT = Path(__file__).resolve().parents[1]
MAX_FILES = 100_000
MAX_BYTES = 2 << 30
SOURCE_ROOT = "joints-rust-source"
PACKAGE_ROOT = "joints-rust-local-candidate"
VERSIONS = {"engine": "0.0.0", "cli": "0.0.0", "abi": 2,
            "native_package": "0.1.0", "python_binding": "0.1.0", "rust_binding": "0.1.0"}
TARGETS = {"linux-x86_64": ("Linux", "x86_64", "libjnt.so"),
           "macos-arm64": ("Darwin", "arm64", "libjnt.dylib")}
NATIVE_FAMILIES = ("irgx-abi2-105", "irgx-abi2-108-munch-image1")
BRIGADE = "brigade-0.2.0-1n1fSbc8AQAg_nOUnefJ5uEVkoUBSeba6M6TYjjIV3I-"


def require(ok: object, message: str) -> None:
    if not ok:
        raise ValueError(message)


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def encoded(value: object) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True, ensure_ascii=True) + "\n").encode()


def read_json(path: Path) -> dict:
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, f"duplicate JSON key: {key}")
            result[key] = value
        return result
    require(path.stat().st_size <= 64 << 20, "manifest exceeds byte limit")
    result = json.loads(path.read_bytes(), object_pairs_hook=unique)
    require(isinstance(result, dict), "manifest must be an object")
    return result


def relative(name: str) -> Path:
    require(isinstance(name, str) and name and "\\" not in name and "\0" not in name,
            "invalid relative path")
    value = PurePosixPath(name)
    require(value.parts and not value.is_absolute() and all(p not in ("", ".", "..") for p in value.parts)
            and value.as_posix() == name, "path escapes its root")
    return Path(*value.parts)


def regular(root: Path, name: str) -> Path:
    path = root / relative(name)
    current = root
    require(not root.is_symlink(), "symlink root")
    for part in relative(name).parts:
        current /= part
        require(not current.is_symlink(), f"symlink source: {name}")
    require(path.is_file() and stat.S_ISREG(path.stat().st_mode), f"missing regular file: {name}")
    return path


def file_map(root: Path) -> dict[str, str]:
    paths = []
    visited = 0
    for path in root.rglob("*"):
        visited += 1
        require(visited <= MAX_FILES, "source exceeds file/directory limit")
        require(not path.is_symlink(), f"symlink source: {path.relative_to(root)}")
        if not path.is_dir():
            paths.append(path)
    total = 0
    result = {}
    for path in sorted(paths):
        name = path.relative_to(root).as_posix()
        checked = regular(root, name)
        total += checked.stat().st_size
        require(total <= MAX_BYTES, "source exceeds byte limit")
        result[name] = digest(checked)
    return result


def check_files(root: Path, files: dict[str, str], *, exact: bool = False) -> None:
    require(isinstance(files, dict) and 0 < len(files) <= MAX_FILES, "empty/oversized file map")
    for name, expected in files.items():
        require(isinstance(expected, str) and re.fullmatch(r"[0-9a-f]{64}", expected),
                f"invalid checksum: {name}")
        require(digest(regular(root, name)) == expected, f"file checksum mismatch: {name}")
    if exact:
        actual = file_map(root)
        actual.pop("source-manifest.json", None)
        require(actual == files, "source inventory differs from manifest")


def command(argv: list[str], *, cwd: Path, env: dict[str, str], logs: Path,
            records: list[dict]) -> subprocess.CompletedProcess:
    logs.mkdir(parents=True, exist_ok=True)
    number = str(len(records)).zfill(3)
    result = subprocess.run(argv, cwd=cwd, env=env, capture_output=True)
    record = {"argv": argv, "cwd": str(cwd), "exit": result.returncode}
    for channel in ("stdout", "stderr"):
        data = getattr(result, channel)
        path = logs / f"{number}.{channel}"
        path.write_bytes(data)
        record[channel] = {"path": str(path), "sha256": digest(path)}
    records.append(record)
    require(result.returncode == 0, f"command refused ({result.returncode}): {argv[0]}")
    return result


def git_files(home: Path) -> list[str]:
    raw = subprocess.check_output(["git", "ls-files", "--cached", "--others",
                                   "--exclude-standard", "-z"], cwd=home)
    return sorted({os.fsdecode(n) for n in raw.split(b"\0") if n})


def git_identity(home: Path) -> dict:
    return {"commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=home).decode().strip(),
            "dirty": bool(subprocess.check_output(["git", "status", "--porcelain=v1",
                                                   "--untracked-files=normal"], cwd=home))}


def source_selection(home: Path, native: bool) -> set[str]:
    names = set()
    for name in git_files(home):
        parts = relative(name).parts
        if parts[0] in (".git", ".local", "holdout"):
            continue
        if native and (name.startswith("bindings/rust/vendor/")
                       or "/target/" in name or "/__pycache__/" in name):
            continue  # Older bundled native APIs are deliberately not delivered.
        if not (home / name).exists() and not (home / name).is_symlink():
            continue  # A tracked deletion is retained by Git/native provenance.
        names.add(name)
    if native:
        lock = "bindings/rust/Cargo.lock"
        if (home / lock).is_file():
            names.add(lock)
    else:
        for base in ("upstream/grammars", "upstream/sources"):
            names.update(p.relative_to(home).as_posix() for p in (home / base).rglob("*") if p.is_file())
        for name in ("rust/Cargo.lock", "bindings/rust/Cargo.lock"):
            if (home / name).is_file():
                names.add(name)
    return names


def export_selection(home: Path, compiled_inputs: dict, exclusions: tuple[str, ...]) -> tuple[set[str], list[dict]]:
    names = source_selection(home, False) | set(compiled_inputs)
    records = []
    require(len(exclusions) == len(set(exclusions)), "duplicate source exclusion")
    for name in exclusions:
        relative(name)
        require(name in names and name not in compiled_inputs, "source exclusion is missing or is a qualified compiled input")
        path = regular(home, name)
        records.append({"repository": "joints", "path": name, "sha256": digest(path), "bytes": path.stat().st_size})
        names.remove(name)
    return names, records


def copy_sources(home: Path, names: set[str], destination: Path) -> dict[str, str]:
    require(len(names) <= MAX_FILES, "source exceeds file limit")
    before = {n: digest(regular(home, n)) for n in sorted(names)}
    require(sum(regular(home, n).stat().st_size for n in names) <= MAX_BYTES,
            "source exceeds byte limit")
    for name in sorted(names):
        path = destination / relative(name)
        path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(regular(home, name), path)
        require(digest(path) == before[name], f"source changed while copying: {name}")
    return before


def source_manifest(root: Path) -> dict:
    value = read_json(regular(root, "source-manifest.json"))
    require(value["schema"] == 1 and value["kind"] == "local-rust-source"
            and value["publishable"] is False and value["versions"] == VERSIONS,
            "unsupported source manifest")
    require(value["offline"]["cargo"] is True and value["offline"]["python_wheels"] is True,
            "source is not an offline dependency closure")
    check_files(root, value["files"], exact=True)
    config = tomllib.loads(regular(root, ".cargo/config.toml").read_text())
    require(config.get("net", {}).get("offline") is True
            and config.get("source", {}).get("crates-io", {}).get("replace-with") == "standalone-vendor"
            and config.get("source", {}).get("standalone-vendor", {}).get("directory") == "dependencies/cargo",
            "Cargo dependency resolution escapes the offline closure")
    require(any((root / "dependencies/cargo").glob("*/.cargo-checksum.json")), "missing Cargo source checksums")
    require(any((root / "dependencies/python").glob("hatchling-*.whl"))
            and any((root / "dependencies/python").glob("build-*.whl")), "missing Python build wheelhouse")
    compiled = value["qualified_compiled_inputs"]["files"]
    require(isinstance(compiled, dict) and compiled, "empty compiled-input join")
    for name, expected in compiled.items():
        relative(name)
        require(isinstance(expected, str) and re.fullmatch(r"[0-9a-f]{64}", expected),
                f"invalid qualified compiled checksum: {name}")
        require(value["files"].get("joints/" + name) == expected,
                f"qualified compiled input differs: {name}")
    for group in (value["native_inputs"]["native"]["files"], value["native_inputs"]["binding"]):
        require(isinstance(group, dict) and group, "empty native/binding source join")
        for name, expected in group.items():
            path = root / "irregex" / relative(name)
            if expected is None:
                require("irregex/" + name not in value["files"]
                        and not path.exists() and not path.is_symlink(),
                        f"deleted native source resurrected: {name}")
            else:
                require(value["files"].get("irregex/" + name) == expected, f"native source differs: {name}")
    return value


def export_source(root: Path, irgx: Path, output: Path, build: Path, zig_cache: Path,
                  *, cargo: str = "cargo", python: str = sys.executable,
                  offline: bool = False, wheelhouse: Path | None = None,
                  exclude_sources: tuple[str, ...] = ()) -> dict:
    """Copy sources and vendor dependencies in a new, atomically published tree.

    This performs dependency downloads/copies, never a native or Cargo build.
    All lockfile generation occurs in the staging copy, never either checkout.
    """
    root, irgx, output = root.resolve(), irgx.resolve(), output.absolute()
    require(not output.exists(), "source destination already exists")
    require(not offline or wheelhouse is not None, "offline export requires a prepared Python wheelhouse")
    proof = read_json(build)
    require(proof["exit"] == 0 and proof["stable"] is True, "unqualified compiled source proof")
    check_files(root, proof["rust_inputs"])
    output.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=".rust-source-", dir=output.parent))
    records: list[dict] = []
    try:
        jnames, exclusions = export_selection(root, proof["rust_inputs"], exclude_sources)
        inames = source_selection(irgx, True)
        before = {"joints": copy_sources(root, jnames, stage / "joints"),
                  "irregex": copy_sources(irgx, inames, stage / "irregex")}
        native = proof["native"]["inputs"]
        for group in (native["native"]["files"], native["binding"]):
            for name, expected in group.items():
                if expected is not None:
                    require(before["irregex"].get(name) == expected,
                            f"native source differs from qualified build: {name}")
        package = zig_cache / "p" / (BRIGADE + ".tar.gz")
        require(package.is_file() and not package.is_symlink(), "pinned Brigade package cache absent")
        seed = stage / "dependencies/zig-cache/p" / package.name
        seed.parent.mkdir(parents=True);shutil.copy2(package, seed)
        manifests = [stage / "joints/rust/Cargo.toml", stage / "irregex/bindings/rust/Cargo.toml",
                     stage / "joints/bindings/rust/Cargo.toml"]
        env = os.environ.copy()
        logs = stage / "delivery-logs"
        for manifest in manifests:
            if not manifest.with_name("Cargo.lock").exists():
                args = [cargo, "generate-lockfile", "--manifest-path", str(manifest)]
                command(args + (["--offline"] if offline else []), cwd=stage, env=env, logs=logs, records=records)
        vendor = stage / "dependencies/cargo"
        args = [cargo, "vendor", "--manifest-path", str(manifests[0]), "--locked", "--versioned-dirs"]
        for manifest in manifests[1:]:
            args += ["--sync", str(manifest)]
        command(args + (["--offline"] if offline else []) + [str(vendor)],
                cwd=stage, env=env, logs=logs, records=records)
        require(vendor.is_dir() and any(vendor.glob("*/.cargo-checksum.json")), "Cargo vendor produced no closure")
        config = stage / ".cargo/config.toml";config.parent.mkdir()
        config.write_text('[source.crates-io]\nreplace-with = "standalone-vendor"\n\n'
                          '[source.standalone-vendor]\ndirectory = "dependencies/cargo"\n\n[net]\noffline = true\n')
        wheels = stage / "dependencies/python";wheels.mkdir()
        if wheelhouse is not None:
            for path in sorted(wheelhouse.glob("*.whl")):
                shutil.copy2(regular(wheelhouse, path.name), wheels / path.name)
        else:
            command([python, "-m", "pip", "download", "--only-binary=:all:", "--dest", str(wheels),
                     "build", "hatchling>=1.27"], cwd=stage, env=env, logs=logs, records=records)
        require(any(wheels.glob("hatchling-*.whl")), "Python wheelhouse incomplete")
        for home, label in ((root, "joints"), (irgx, "irregex")):
            check_files(home, before[label])
        # Cargo configuration is relative to this exported workspace, not the
        # temporary name that cargo vendor printed. Logs retain the real command.
        value = {"schema": 1, "kind": "local-rust-source", "publishable": False,
                 "versions": VERSIONS, "layout": ["joints", "irregex", "dependencies"],
                 "origin": {"joints": git_identity(root), "irregex": git_identity(irgx)},
                 "source_bytes_before": before, "source_bytes_after": before,
                 "source_exclusions": exclusions,
                 "qualified_compiled_inputs": {"scope": "compiled inputs only; not a live historical whole-checkout freeze",
                    "build_sha256": digest(build), "files": proof["rust_inputs"]},
                 "native_inputs": native, "dependency_commands": records,
                 "offline": {"cargo": True, "python_wheels": True,
                    "zig_package": {"name": package.name, "sha256": digest(seed), "zig_hash": BRIGADE}},
                 "files": file_map(stage)}
        (stage / "source-manifest.json").write_bytes(encoded(value))
        source_manifest(stage)
        require(not output.exists(), "source destination appeared during export")
        os.rename(stage, output)
        return {"source": str(output), "manifest_sha256": digest(output / "source-manifest.json"),
                "files": len(value["files"]), "publishable": False}
    finally:
        if stage.exists():
            shutil.rmtree(stage)


def machine(data: bytes) -> str | None:
    if data[:4] == b"\x7fELF" and len(data) >= 20:
        require(data[4] == 2 and data[5] == 1, "unsupported ELF class/endianness")
        return {62: "linux-x86_64", 183: "linux-arm64"}.get(int.from_bytes(data[18:20], "little"), "other-ELF")
    if data[:4] == b"\xcf\xfa\xed\xfe" and len(data) >= 8:
        return {0x100000C: "macos-arm64", 0x1000007: "macos-x86_64"}.get(int.from_bytes(data[4:8], "little"), "other-MachO")
    return None


def check_machine(path: Path, target: str, archive: bool = False) -> None:
    if archive:
        import rust_archive
        value = rust_archive.read_archive(path)
        found = [machine(value.payload(member)[:64].tobytes()) for member in value.members]
        require(found and all(value == target for value in found), "archive object target mismatch")
    else:
        with path.open("rb") as stream:
            require(machine(stream.read(64)) == target, "executable/shared-library target mismatch")


def macho_metadata(data: bytes | memoryview, *, text: bool = False) -> dict:
    """Read CPU, deployment floor and actual loads; LC_ID_DYLIB is not a load."""
    require(machine(data[:64]) == "macos-arm64" and len(data) >= 32, "unsupported Mach-O metadata")
    def u32(at):
        require(at + 4 <= len(data), "truncated Mach-O command")
        return int.from_bytes(data[at:at + 4], "little")
    def version(value):
        return [value >> 16, (value >> 8) & 255, value & 255]
    count, size = u32(16), u32(20)
    require(count <= 100_000 and 32 + size <= len(data), "invalid Mach-O load commands")
    position, floors, dependencies, identity, sections = 32, [], [], None, {}
    for _ in range(count):
        require(position + 8 <= 32 + size, "truncated Mach-O load command")
        tag, length = u32(position), u32(position + 4)
        require(length >= 8 and position + length <= 32 + size, "invalid Mach-O load extent")
        if tag in (0x32, 0x24):  # LC_BUILD_VERSION / LC_VERSION_MIN_MACOSX
            require(length >= (24 if tag == 0x32 else 16), "short Mach-O version command")
            if tag == 0x24 or u32(position + 8) == 1:  # PLATFORM_MACOS
                floors.append(version(u32(position + (12 if tag == 0x32 else 8))))
        if tag in (0xc, 0xd, 0x80000018, 0x8000001f, 0x20, 0x80000023):
            require(length >= 24, "short Mach-O dependency command")
            start = u32(position + 8)
            require(24 <= start < length, "invalid Mach-O dependency name")
            raw = bytes(data[position + start:position + length])
            require(b"\0" in raw, "unterminated Mach-O dependency")
            name = raw.split(b"\0", 1)[0].decode("utf-8")
            if tag == 0xd:
                require(identity is None, "duplicate Mach-O library identity")
                identity = name
            else:
                dependencies.append(name)
        if tag == 0x19 and text:  # LC_SEGMENT_64; compare actual section payloads
            require(length >= 72, "short Mach-O segment")
            count_sections = u32(position + 64)
            require(count_sections <= (length - 72) // 80, "invalid Mach-O section table")
            for index in range(count_sections):
                at = position + 72 + index * 80
                name = bytes(data[at:at + 16]).split(b"\0", 1)[0].decode("ascii")
                segment = bytes(data[at + 16:at + 32]).split(b"\0", 1)[0]
                if segment == b"__TEXT":
                    size_section = int.from_bytes(data[at + 40:at + 48], "little")
                    offset = u32(at + 48)
                    require(offset + size_section <= len(data), "Mach-O text section outside file")
                    require(name not in sections, "duplicate Mach-O text section")
                    sections[name] = {"bytes": size_section, "sha256": hashlib.sha256(data[offset:offset + size_section]).hexdigest()}
        position += length
    require(position == 32 + size, "Mach-O load command size mismatch")
    result = {"cpu_type": u32(4), "cpu_subtype": u32(8), "minimum_macos": max(floors) if floors else None,
              "dependencies": sorted(set(dependencies)), "install_name": identity}
    if text:
        require("__text" in sections, "Mach-O code section absent")
        result["text_sections"] = sections
    return result


def platform_evidence(root: Path, target: str, output: Path) -> dict:
    """Retain binary floors, not an inference from the executing host's release."""
    result = {"target": target, "binaries": {}, "archives": {},
              "scope": "binary metadata only; target-floor host execution is a separate gate"}
    if target == "macos-arm64":
        for name in ("bin/joints-rs", "lib/libjnt.dylib"):
            metadata = macho_metadata(regular(root, name).read_bytes())
            require(all(d.startswith(("/usr/lib/", "/System/Library/")) for d in metadata["dependencies"]),
                    "Mach-O dependency escapes system libraries")
            result["binaries"][name] = metadata
        import rust_archive
        for name in ("lib/libjnt.a", "lib/libirgx.a"):
            archive = rust_archive.read_archive(regular(root, name))
            metadata = [macho_metadata(archive.payload(m)) for m in archive.members]
            floors = [m["minimum_macos"] for m in metadata if m["minimum_macos"] is not None]
            result["archives"][name] = {"objects": len(metadata),
                "cpu_subtypes": sorted({m["cpu_subtype"] for m in metadata}),
                "maximum_minimum_macos": max(floors) if floors else None,
                "objects_without_floor": sum(m["minimum_macos"] is None for m in metadata)}
    else:
        tool = shutil.which("readelf");require(tool, "readelf unavailable for ELF dependency proof")
        output.mkdir(parents=True, exist_ok=True)
        records = []
        for name in ("bin/joints-rs", "lib/libjnt.so"):
            check_machine(regular(root, name), target)
            data = command([tool, "--wide", "--file-header", "--dynamic", "--version-info", "--notes", name],
                           cwd=root, env=os.environ.copy(), logs=output, records=records).stdout.decode()
            dependencies = sorted(set(re.findall(r"\(NEEDED\).*\[([^\]]+)\]", data)))
            require(all(d in {"libc.so.6", "libgcc_s.so.1", "libm.so.6", "libdl.so.2", "libpthread.so.0",
                              "librt.so.1", "ld-linux-x86-64.so.2"} for d in dependencies),
                    "ELF dependency escapes delivered/system libraries")
            require(not re.search(r"\((?:RPATH|RUNPATH)\)", data), "ELF embeds a library search path")
            glibc = sorted({tuple(map(int, v.split("."))) for v in re.findall(r"GLIBC_([0-9]+\.[0-9]+(?:\.[0-9]+)?)", data)})
            require(not glibc or glibc[-1] <= (2, 39), "ELF requires GLIBC newer than Ubuntu 24.04")
            result["binaries"][name] = {"dependencies": dependencies,
                "glibc_needed_versions": [list(v) for v in glibc],
                "cpu_note": [line.strip() for line in data.splitlines() if "ISA needed" in line or "x86 feature" in line]}
        (output / "commands.json").write_bytes(encoded(records))
    return result


def create_archive(root: Path, output: Path, title: str) -> None:
    require(not output.exists(), "archive destination already exists")
    files = file_map(root)
    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".candidate-", dir=output.parent)
    try:
        with os.fdopen(fd, "wb") as stream, gzip.GzipFile(fileobj=stream, mode="wb", filename="", mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as package:
                for name in sorted(files):
                    path = regular(root, name)
                    entry = tarfile.TarInfo(title + "/" + name)
                    entry.size = path.stat().st_size
                    entry.mode = 0o755 if os.access(path, os.X_OK) else 0o644
                    with path.open("rb") as content:
                        package.addfile(entry, content)
        require(file_map(root) == files, "package source changed during archival")
        os.link(temporary, output)  # Atomic, refusing an output that appeared meanwhile.
    finally:
        Path(temporary).unlink(missing_ok=True)


def unpack(archive: Path, destination: Path, title: str) -> Path:
    require(not destination.exists(), "unpack destination already exists")
    with tarfile.open(archive, "r:gz") as package:
        members = []
        names = set()
        total = 0
        for member in package:
            require(len(members) < MAX_FILES and member.size >= 0, "archive resource limit")
            total += member.size
            require(total <= MAX_BYTES, "archive resource limit")
            path = relative(member.name)
            require(path.parts[0] == title and (len(path.parts) > 1 or member.isdir()), "unexpected archive root")
            require((member.isfile() or member.isdir()) and member.size >= 0,
                    "archive link/special file")
            require(member.name not in names, "duplicate archive member")
            names.add(member.name)
            members.append(member)
        require(members, "empty archive")
        destination.mkdir(parents=True)
        try:
            for member in members:
                path = destination / relative(member.name)
                if member.isdir():
                    path.mkdir(parents=True, exist_ok=True)
                    continue
                path.parent.mkdir(parents=True, exist_ok=True)
                with path.open("xb") as output, package.extractfile(member) as content:
                    shutil.copyfileobj(content, output)
                path.chmod(0o755 if member.mode & 0o111 else 0o644)
        except Exception:
            shutil.rmtree(destination)
            raise
    return destination / title


def check_bundle(source: Path, bundle: Path, irgx_archive: Path, target: str) -> tuple[dict, dict]:
    manifest = source_manifest(source)
    value = read_json(regular(bundle, "bundle.json"))
    require(value["schema"] == 1, "unsupported build bundle")
    identity = value["identity"]
    require(hashlib.sha256(encoded(identity)).hexdigest() == value["identity_sha256"], "bundle identity mismatch")
    check_files(bundle, value["files"])
    build = read_json(regular(bundle, "build.json"))
    require(build["exit"] == 0 and build["stable"] is True, "failed/unstable build")
    for key in ("rust_inputs", "native", "toolchain"):
        require(build[key] == identity[key], f"build/bundle {key} differs")
    require(build["rust_inputs"] == manifest["qualified_compiled_inputs"]["files"], "compiled source join mismatch")
    require(build["native"]["archive_sha256"] == digest(irgx_archive), "wrong source-engine archive")
    require(build["native"]["inputs"] == manifest["native_inputs"], "native source join mismatch")
    for name in ("bin/joints-rs", "lib/libjnt.a", "lib/" + TARGETS[target][2]):
        require(name in value["files"], f"missing native artifact: {name}")
        check_machine(bundle / name, target, name.endswith(".a"))
    check_machine(irgx_archive, target, True)
    return manifest, value


def library_exports(path: Path, logs: Path, records: list[dict]) -> str:
    nm = shutil.which("nm");require(nm, "nm unavailable for deployment proof")
    result = command([nm, "-gU", "-j", str(path)], cwd=path.parent, env=os.environ.copy(), logs=logs, records=records)
    require(result.stdout.strip(), "shared library has no exported symbols")
    return hashlib.sha256(result.stdout).hexdigest()


def deploy_library(original: Path, installed: Path, target: str, logs: Path) -> dict:
    """Keep original build bytes; normalize only the local package derivative."""
    before = digest(original)
    if target != "macos-arm64":
        require(before == digest(installed), "untransformed library differs")
        return {"kind": "unchanged", "before_sha256": before, "after_sha256": before}
    records = []
    previous = macho_metadata(original.read_bytes(), text=True)
    exports = library_exports(original, logs, records)
    installed.chmod(installed.stat().st_mode | stat.S_IWUSR)
    command(["install_name_tool", "-id", "@rpath/libjnt.dylib", str(installed)], cwd=installed.parent,
            env=os.environ.copy(), logs=logs, records=records)
    command(["codesign", "--force", "--sign", "-", str(installed)], cwd=installed.parent,
            env=os.environ.copy(), logs=logs, records=records)
    current = macho_metadata(installed.read_bytes(), text=True)
    require(current["install_name"] == "@rpath/libjnt.dylib", "deployment install name differs")
    require({k: v for k, v in previous.items() if k != "install_name"}
            == {k: v for k, v in current.items() if k != "install_name"}, "deployment changed code/text or dependencies")
    require(exports == library_exports(installed, logs, records), "deployment changed exports")
    return {"kind": "macho-install-name-and-adhoc-signature", "before_sha256": before,
        "after_sha256": digest(installed), "before": previous, "after": current,
        "exports_sha256": exports, "commands": records,
        "scope": "local nonpublishable package derivative; original qualified build retained unchanged"}


def check_deployment(root: Path, target: str, bundle: dict, output: Path) -> dict:
    proof = root / "proof/build"
    for name in ("bin/joints-rs", "include/jnt.h"):
        require(digest(regular(root, name)) == bundle["files"][name], "packaged artifact differs from build proof")
    name = "lib/" + TARGETS[target][2]
    original, installed = regular(proof, name), regular(root, name)
    transform = read_json(regular(root, "deployment.json"))
    require(transform["before_sha256"] == digest(original) and transform["after_sha256"] == digest(installed),
            "deployment library checksum differs")
    if target == "macos-arm64":
        require(transform["kind"] == "macho-install-name-and-adhoc-signature", "unsupported deployment transform")
        before, after = macho_metadata(original.read_bytes(), text=True), macho_metadata(installed.read_bytes(), text=True)
        require(before == transform["before"] and after == transform["after"]
                and {k: v for k, v in before.items() if k != "install_name"}
                == {k: v for k, v in after.items() if k != "install_name"}
                and after["install_name"] == "@rpath/libjnt.dylib", "deployment text/install-name proof differs")
        records = []
        require(library_exports(original, output, records) == library_exports(installed, output, records)
                == transform["exports_sha256"], "deployment exports differ")
        command(["codesign", "--verify", "--strict", str(installed)], cwd=installed.parent,
                env=os.environ.copy(), logs=output, records=records)
        (output / "commands.json").write_bytes(encoded(records))
    else:
        require(transform["kind"] == "unchanged" and digest(original) == digest(installed), "unexpected ELF transform")
    return transform


def check_static_boundary(root: Path, target: str) -> dict:
    import rust_static_boundary as boundary
    receipt = read_json(regular(root, "static-boundary.json"))
    helper = regular(root / "source/joints", "tool/rust_static_boundary.py")
    require(receipt["helper_sha256"] == digest(helper), "static boundary helper/source join differs")
    return boundary.verify_archive(regular(root / "proof/build", "lib/libjnt.a"),
        regular(root, "lib/libjnt.a"), receipt, target=target,
        exports=boundary.declared_exports(regular(root, "include/jnt.h"), target))


def source_engine_contract(source: Path) -> dict:
    """Join the selected native family and wire format to delivered source."""
    cargo = tomllib.loads(regular(source / "joints", "rust/Cargo.toml").read_text())
    irgx = cargo.get("dependencies", {}).get("irgx", {})
    require(isinstance(irgx, dict) and "source-engine" in irgx.get("features", []),
            "delivered engine omits its source-engine dependency")
    artifact = regular(source / "joints", "rust/src/artifact.rs").read_text()
    values = {}
    for name in ("VERSION", "SCHEMA"):
        found = re.findall(r"^const " + name + r": u32 = (\d+);$", artifact, re.M)
        require(len(found) == 1, "artifact source has no unique version/schema authority")
        values[name.lower()] = int(found[0])
    image = "munch-image" in irgx.get("features", [])
    expected = {"version": 3, "schema": 4} if image else {"version": 2, "schema": 3}
    require(values == expected, "source dependency and native artifact format differ")
    return {"native_abi_family": NATIVE_FAMILIES[int(image)], "artifact_format": values}


def check_native_boundary(root: Path, target: str, *, abi_family: str = "irgx-abi2-105") -> dict:
    """The build original stays raw; only this checked selection reaches Cargo."""
    import rust_static_boundary as boundary
    proof = read_json(regular(root, "native-boundary.json"))
    require(abi_family in NATIVE_FAMILIES and proof.get("abi_family", NATIVE_FAMILIES[0]) == abi_family,
            "native boundary ABI family differs")
    helpers = root / "source/joints/tool"
    require(proof["helper_sha256"] == digest(regular(helpers, "rust_static_boundary.py"))
            and proof["parser_sha256"] == digest(regular(helpers, "rust_archive.py")),
            "native boundary producer/parser source differs")
    return boundary.verify_archive(regular(root / "proof/build", "lib/libirgx.a"),
        regular(root, "lib/libirgx.a"), proof, target=target,
        exports=boundary.declared_exports(regular(root / "source/irregex", "include/irgx.h"),
                                         target, abi_family=abi_family),
        abi_family=abi_family)


def checked_native_selection(raw: Path, selected: Path, proof_path: Path, *, target: str,
                             source_inputs: dict, header: Path, producer_sha256: str) -> dict:
    """Declare a verified native108 selection for Cargo; retain the full proof.

    The caller must independently verify the archive boundary before publishing
    this declaration. Current raw/selected bytes, header and producer are bound
    here; the declaration never substitutes for transform verification.
    """
    for path in (raw, selected, proof_path, header):
        require(path.is_file() and not path.is_symlink(), "checked108 input is not a regular file")
    proof = read_json(proof_path)
    require(proof.get("schema") == 1 and proof.get("abi_family") == NATIVE_FAMILIES[1]
            and proof.get("kind") == "opaque-native-only-C-static-boundary"
            and proof.get("machine_code_only") is True and proof.get("target") == target,
            "checked108 proof contract differs")
    require(proof["before_sha256"] == digest(raw) and proof["after_sha256"] == digest(selected),
            "checked108 archive/proof bytes differ")
    require(re.fullmatch(r"[0-9a-f]{64}", producer_sha256), "checked108 producer hash differs")
    return {"schema": 1, "identity": {"abi_family": NATIVE_FAMILIES[1], "target": target,
                "raw_sha256": digest(raw), "header_sha256": digest(header), "source_inputs": source_inputs,
                "producer_sha256": producer_sha256},
            "archive_sha256": digest(selected), "proof_sha256": digest(proof_path)}


def check_native_selection(root: Path, target: str) -> dict:
    """Verify the portable Cargo declarations after full boundary verification."""
    native_proof = regular(root, "native-boundary.json")
    cargo_proof = regular(root, "proof.json")
    require(cargo_proof.read_bytes() == native_proof.read_bytes(), "checked108 Cargo/native proof differs")
    manifest = source_manifest(root / "source")
    expected = checked_native_selection(regular(root / "proof/build", "lib/libirgx.a"),
        regular(root, "lib/libirgx.a"), cargo_proof, target=target, source_inputs=manifest["native_inputs"],
        header=regular(root / "source/irregex", "include/irgx.h"),
        producer_sha256=digest(regular(root / "source/joints", "tool/rust_delivery.py")))
    selected = regular(root, "selection.json")
    require(read_json(selected) == expected, "checked108 portable selection differs")
    return {"selection_sha256": digest(selected), "proof_sha256": digest(cargo_proof),
            "archive_sha256": expected["archive_sha256"]}


def pack_candidate(source: Path, bundle: Path, irgx_archive: Path, output: Path,
                   target: str, execution_scope: str, *, objcopy: Path, indexer: Path | None = None,
                   abi_family: str = "irgx-abi2-105") -> dict:
    require(target in TARGETS and execution_scope in ("native-host", "emulated"), "unknown target/execution scope")
    manifest, build_bundle = check_bundle(source, bundle, irgx_archive, target)
    contract = source_engine_contract(source)
    require(abi_family in NATIVE_FAMILIES and abi_family == contract["native_abi_family"],
            "explicit native family differs from delivered engine source")
    with tempfile.TemporaryDirectory(prefix="joints-package-") as temporary:
        stage = Path(temporary)
        shutil.copytree(source, stage / "source")
        # Retain the bundle's full proof closure, including raw archive and
        # normalization evidence. Its file map must remain verifiable after
        # extraction, without reaching back to the original build directory.
        names = sorted(set(build_bundle["files"]) | {"bundle.json"})
        for name in names:
            path = stage / "proof/build" / relative(name);path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(regular(bundle, name), path)
        for name in ("bin/joints-rs", "lib/" + TARGETS[target][2]):
            path = stage / name;path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(regular(bundle, name), path)
        raw = stage / "proof/build/lib/libirgx.a"
        if raw.exists():
            require(digest(raw) == digest(irgx_archive), "bundle/raw native archive differs")
        else:
            raw.parent.mkdir(parents=True, exist_ok=True);shutil.copy2(irgx_archive, raw)
        for original, name in (("include/jnt.h", "include/jnt.h"), ("test/grammar/json.json", "grammar/json.json"),
                               ("LICENSE", "LICENSE"), ("NOTICE", "NOTICE")):
            path = stage / name;path.parent.mkdir(parents=True, exist_ok=True)
            original = regular(source / "joints", original)
            if path.exists():
                require(digest(path) == digest(original), "build/source header bytes differ")
            else:
                shutil.copy2(original, path)
        import rust_static_boundary as boundary
        static = boundary.transform_archive(stage / "proof/build/lib/libjnt.a", stage / "lib/libjnt.a",
            target=target, exports=boundary.declared_exports(stage / "include/jnt.h", target),
            objcopy=objcopy, indexer=indexer, work=stage / "proof/static-boundary")
        (stage / "static-boundary.json").write_bytes(encoded(static))
        require(static["helper_sha256"] == digest(regular(source / "joints", "tool/rust_static_boundary.py")),
                "packaging helper differs from exported source")
        check_static_boundary(stage, target)
        native = boundary.transform_archive(raw, stage / "lib/libirgx.a", target=target,
            exports=boundary.declared_exports(regular(source / "irregex", "include/irgx.h"),
                                             target, abi_family=abi_family),
            abi_family=abi_family, objcopy=objcopy, indexer=indexer,
            work=stage / "proof/native-boundary")
        (stage / "native-boundary.json").write_bytes(encoded(native))
        check_native_boundary(stage, target, abi_family=abi_family)
        selection = None
        if abi_family == NATIVE_FAMILIES[1]:
            producer = regular(source / "joints", "tool/rust_delivery.py")
            require(digest(producer) == digest(Path(__file__)), "checked108 delivery producer differs from source")
            shutil.copy2(stage / "native-boundary.json", stage / "proof.json")
            declaration = checked_native_selection(raw, stage / "lib/libirgx.a", stage / "proof.json",
                target=target, source_inputs=manifest["native_inputs"],
                header=regular(source / "irregex", "include/irgx.h"), producer_sha256=digest(producer))
            (stage / "selection.json").write_bytes(encoded(declaration))
            selection = check_native_selection(stage, target)
        shared = "lib/" + TARGETS[target][2]
        transform = deploy_library(stage / "proof/build" / shared, stage / shared, target, stage / "deployment-logs")
        (stage / "deployment.json").write_bytes(encoded(transform))
        (stage / "platform-proof.json").write_bytes(encoded(platform_evidence(stage, target, stage / "platform-logs")))
        metadata = {"schema": 2, "kind": "local-rust-candidate", "publishable": False,
                    "versions": VERSIONS, "target": target, "execution_scope": execution_scope, **contract,
                    "source_manifest_sha256": digest(source / "source-manifest.json"),
                    "build_identity_sha256": build_bundle["identity_sha256"],
                    "native_archive_sha256": digest(irgx_archive),
                    "selected_native_archive_sha256": digest(stage / "lib/libirgx.a"),
                    "native_boundary_sha256": digest(stage / "native-boundary.json"),
                    "static_boundary_sha256": digest(stage / "static-boundary.json"), "files": file_map(stage)}
        if selection is not None:
            metadata["checked_native_selection"] = selection
        (stage / "manifest.json").write_bytes(encoded(metadata))
        check_files(source, manifest["files"], exact=True)
        check_files(bundle, build_bundle["files"])
        create_archive(stage, output, PACKAGE_ROOT)
    return {"archive": str(output), "sha256": digest(output), "target": target,
            "execution_scope": execution_scope, "publishable": False}


C_SMOKE = r'''#define _GNU_SOURCE
#include "jnt.h"
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#define NEED(x) do { if (!(x)) return __LINE__; } while (0)
int main(int argc, char **argv) {
  NEED((argc == 2 || argc == 3) && jnt_abi_version() == 2 && strcmp(jnt_version(), "0.1.0") == 0);
  if (argc == 3) {
    Dl_info loaded; NEED(dladdr((void *)jnt_abi_version, &loaded) != 0);
    char *actual = realpath(loaded.dli_fname, NULL), *expected = realpath(argv[2], NULL);
    NEED(actual && expected && strcmp(actual, expected) == 0); free(actual); free(expected);
  }
  jnt_bank *bank = NULL; jnt_parser *parser = NULL; jnt_tree *first = NULL, *second = NULL;
  NEED(jnt_open(argv[1], &bank) == JNT_OK && bank && jnt_bank_count(bank) == 1);
  NEED(jnt_parser_new(bank, "json", &parser) == JNT_OK && parser);
  const char *bytes = "{\"key\":[1,2]}";
  char *owned = malloc(strlen(bytes) + 1); NEED(owned); strcpy(owned, bytes);
  NEED(jnt_parse(parser, owned, strlen(owned), &first) == JNT_OK && first); free(owned);
  NEED(jnt_tree_stop(first) == JNT_ACCEPTED && jnt_tree_sound(first) == 1);
  NEED(jnt_tree_mends(first) == 0 && jnt_tree_supplied(first) == 0 && jnt_tree_roots(first) == 1);
  uint32_t root = jnt_tree_root(first, 0); NEED(jnt_node_end(first, root) == strlen(bytes));
  NEED(jnt_parse(parser, "[4]", 3, &second) == JNT_OK && second);
  NEED(jnt_node_end(first, root) == strlen(bytes));
  jnt_query *query = NULL; jnt_query_result *result = NULL; const char *scm = "(number) @n";
  NEED(jnt_query_compile(parser, scm, strlen(scm), &query) == JNT_OK && query);
  NEED(jnt_query_exec(query, first, bytes, strlen(bytes), JNT_FOREIGN_REFUSE, &result) == JNT_OK && result);
  NEED(jnt_query_result_count(result) == 2);
  for (uint32_t i = 0; i < 2; ++i) {
    NEED(jnt_query_result_capture_count(result, i) == 1);
    uint32_t node = jnt_query_result_capture_node(result, i, 0);
    NEED(jnt_node_end(first, node) == jnt_node_start(first, node) + 1);
  }
  jnt_query_result_free(result); jnt_query_free(query); jnt_tree_free(second);
  NEED(jnt_parse(parser, "[1,", 3, &second) == JNT_OK && second);
  NEED(jnt_tree_stop(second) != JNT_ACCEPTED || jnt_tree_mends(second) || jnt_tree_supplied(second));
  jnt_tree_free(second); jnt_tree_free(first); jnt_parser_free(parser); jnt_close(bank);
  return 0;
}
'''


def installed_environment(scratch: Path, sdkroot: Path | None) -> dict[str, str]:
    env = os.environ.copy()
    for key in ("RUSTC", "RUSTDOC", "RUSTFLAGS", "RUSTDOCFLAGS", "CARGO_ENCODED_RUSTFLAGS", "CARGO_ENCODED_RUSTDOCFLAGS",
                "RUSTC_WRAPPER",
                "RUSTC_WORKSPACE_WRAPPER", "RUSTUP_TOOLCHAIN", "JOINTS_LIB", "JOINTS_LIB_DIR", "JOINTS_LINK_KIND",
                "IRGX_LIB_DIR", "JOINTS_CUSTOMARY", "CARGO_BUILD_RUSTC", "CARGO_BUILD_RUSTC_WRAPPER",
                "CARGO_BUILD_RUSTC_WORKSPACE_WRAPPER", "CARGO_BUILD_RUSTFLAGS",
                "PYTHONPATH", "PYTHONHOME", "SDKROOT", "MACOSX_DEPLOYMENT_TARGET",
                "DYLD_LIBRARY_PATH", "DYLD_INSERT_LIBRARIES", "LD_LIBRARY_PATH", "LD_PRELOAD",
                "CC", "CXX", "AR", "CFLAGS", "CXXFLAGS", "CPPFLAGS", "LDFLAGS"):
        env.pop(key, None)
    for key in list(env):
        if key.startswith(("CARGO_TARGET_", "CARGO_PROFILE_", "CARGO_BUILD_")):
            env.pop(key)
    env.update(CARGO_HOME=str(scratch / "cargo-home"), CARGO_TARGET_DIR=str(scratch / "cargo-target"),
               CARGO_NET_OFFLINE="true", PYTHONDONTWRITEBYTECODE="1", PIP_NO_INDEX="1",
               PCRE2_SYS_STATIC="1", LIBPCRE2_8_NO_PKG_CONFIG="1")
    if platform.system() == "Darwin":
        require(sdkroot is not None and sdkroot.is_dir(), "macOS package checks require an explicit SDK")
        env["SDKROOT"] = str(sdkroot)
    else:
        require(sdkroot is None, "Linux must not inherit a macOS SDK")
    return env


def native_api_source(compile_name: str, match_name: str, backend_version: str) -> str:
    """A small installed colink client; detailed provider research stays separate."""
    require(all(re.fullmatch(r'[_a-zA-Z][_a-zA-Z0-9]*', name) for name in (compile_name, match_name)),
            'invalid verified native diagnostic symbol')
    require(re.fullmatch(r'[0-9]+\.[0-9]+', backend_version), 'invalid source-attested PCRE version')
    text = r'''
use joints_engine::{CompiledGrammar,Query,ForeignPolicy};
unsafe extern "C" {
 #[link_name="@COMPILE@"] fn private_compile(p:*const u8,n:usize,o:u32,e:*mut i32,a:*mut usize,c:*mut pcre2_sys::pcre2_compile_context_8)->*mut pcre2_sys::pcre2_code_8;
 #[link_name="@MATCH@"] fn private_match(c:*const pcre2_sys::pcre2_code_8,s:*const u8,n:usize,a:usize,o:u32,d:*mut pcre2_sys::pcre2_match_data_8,x:*mut pcre2_sys::pcre2_match_context_8)->i32;
}
fn main(){
 assert_eq!(std::env::var("PCRE2_SYS_STATIC").unwrap(),"1");
 assert_eq!(std::env::var("LIBPCRE2_8_NO_PKG_CONFIG").unwrap(),"1");
 let mut version=[0u8;128];let n=unsafe{pcre2_sys::pcre2_config_8(pcre2_sys::PCRE2_CONFIG_VERSION,version.as_mut_ptr().cast())};
 assert!(n>1&&n<=128);assert_eq!(version[n as usize-1],0);
 let oracle=std::str::from_utf8(&version[..n as usize-1]).unwrap();assert!(oracle.starts_with("10.46 "));
 assert_eq!(irgx::pcre2_version(),"@VERSION@");
 let addresses=[(pcre2_sys::pcre2_compile_8 as *const() as usize,private_compile as *const() as usize),(pcre2_sys::pcre2_match_8 as *const() as usize,private_match as *const() as usize)];
 for (a,b) in addresses{assert_ne!(a,b);}
 let g=CompiledGrammar::compile(&std::fs::read(std::env::args().nth(1).unwrap()).unwrap()).unwrap();
 let g=CompiledGrammar::from_artifact(&g.artifact().unwrap()).unwrap();let mut p=g.session();
 let source=Vec::from(b"[1,2]".as_slice());let tree=p.parse(&source).unwrap();drop(source);
 assert!(tree.confidence().is_strict());let q=Query::compile(g,b"(number) @n").unwrap();
 let found=q.execute(&tree,ForeignPolicy::Refuse).unwrap();assert_eq!(found.len(),2);assert_eq!(found[0].captures[0].node.span().start(),1);
 let pattern=r"\G(?<=\xff)(a)(b)";let bytes=b"\xffab!";
 let mut builder=irgx::RegexBuilder::new(pattern);builder.unicode(false).pcre(true).match_limit(100000).depth_limit(1000).heap_limit_bytes(1048576);
 let re=builder.build().unwrap();let ranges=re.try_capture_ranges_at(bytes,1).unwrap().unwrap();assert_eq!(ranges,vec![Some(1..3),Some(1..2),Some(2..3)]);
 let oracle_re=pcre2::bytes::RegexBuilder::new().utf(false).ucp(false).jit(false).build(pattern).unwrap();let mut slots=oracle_re.capture_locations();
 assert!(oracle_re.captures_read_at(&mut slots,bytes,1).unwrap().is_some());assert_eq!((0..3).map(|i|slots.get(i)).collect::<Vec<_>>(),vec![Some((1,3)),Some((1,2)),Some((2,3))]);
 let mut bad=irgx::RegexBuilder::new("(");bad.unicode(false).pcre(true);assert!(bad.build().is_err());assert!(pcre2::bytes::Regex::new("(").is_err());
 println!("{}",serde_json::json!({"engine_parse_query":true,"captures":3,"invalid_both_refused":true,"oracle_runtime_config_version":oracle,"compile_match_addresses":addresses,"irgx_source_attested_version":"@VERSION@","irgx_reported_version_corroboration":irgx::pcre2_version()}));
}
'''
    return text.replace('@COMPILE@', compile_name).replace('@MATCH@', match_name).replace('@VERSION@', backend_version)


def default_test_summary(stdout: bytes, toolchain: str) -> dict:
    counts = re.findall(r"test result: ok\. (\d+) passed; (\d+) failed; (\d+) ignored; (\d+) measured; (\d+) filtered out;",
                        stdout.decode())
    require(counts and sum(int(p) for p, _, _, _, _ in counts) > 0
            and all(int(f) == 0 and int(filtered) == 0 for _, f, _, _, filtered in counts),
            "default engine workspace test summaries missing or failed")
    return {"toolchain": toolchain, "passed": sum(int(p) for p, _, _, _, _ in counts), "failed": 0,
            "ignored": sum(int(i) for _, _, i, _, _ in counts), "filtered": 0, "summaries": counts}


def check_cli_identity(stdout: bytes) -> None:
    expected = f"joints-rs {VERSIONS['cli']} (native Rust)\n".encode()
    require(stdout == expected, "candidate CLI version/backend identity differs")


def verify_candidate(archive: Path, output: Path, execution_scope: str, *, python: str = sys.executable,
                     rust_toolchain: str = "1.85.0", sdkroot: Path | None = None) -> dict:
    """Install and execute only the extracted candidate in retained scratch.

    This is an execution/ownership check, not a timing benchmark. On a Mac the
    original checkout remains OS-accessible; it is excluded from Python/Cargo
    resolution. An isolated container can additionally omit that host mount.
    """
    archive, output = archive.resolve(), output.absolute()
    require(not output.exists(), "verification output already exists")
    output.mkdir(parents=True)
    scratch = output / "scratch";scratch.mkdir()
    records: list[dict] = []
    report = {"schema": 1, "kind": "local-rust-candidate-check", "publishable": False,
              "pass": False, "execution_scope": execution_scope, "commands": records,
              "archive": {"path": str(archive.resolve()), "sha256": None}}
    try:
        report["archive"]["sha256"] = digest(archive)
        root = unpack(archive, scratch / "unpacked", PACKAGE_ROOT)
        metadata = read_json(root / "manifest.json")
        require(metadata["schema"] == 2 and metadata["kind"] == "local-rust-candidate"
                and metadata["publishable"] is False and metadata["versions"] == VERSIONS,
                "unsupported/publishable candidate metadata")
        report["package_execution_scope"] = metadata["execution_scope"]
        require(execution_scope in ("native-host", "emulated")
                and metadata["execution_scope"] in ("native-host", "emulated"), "invalid execution scope")
        target = metadata["target"];require(target in TARGETS, "unsupported candidate target")
        require((platform.system(), platform.machine()) == TARGETS[target][:2], "candidate cannot execute on this host")
        check_files(root, metadata["files"])
        require(file_map(root).keys() == metadata["files"].keys() | {"manifest.json"}, "unexpected candidate file")
        source = root / "source"
        require(digest(source / "source-manifest.json") == metadata["source_manifest_sha256"], "source manifest join differs")
        library = root / "lib" / TARGETS[target][2]
        _, bundle = check_bundle(source, root / "proof/build", root / "proof/build/lib/libirgx.a", target)
        require(bundle["identity_sha256"] == metadata["build_identity_sha256"], "packaged build identity differs")
        require(digest(root / "proof/build/lib/libirgx.a") == metadata["native_archive_sha256"],
                "packaged raw native archive identity differs")
        require(digest(root / "lib/libirgx.a") == metadata["selected_native_archive_sha256"],
                "packaged selected native archive identity differs")
        require(digest(regular(root, "native-boundary.json")) == metadata["native_boundary_sha256"],
                "native boundary receipt identity differs")
        contract = source_engine_contract(source)
        require(metadata.get("native_abi_family", NATIVE_FAMILIES[0]) == contract["native_abi_family"]
                and metadata.get("artifact_format", {"version": 2, "schema": 3}) == contract["artifact_format"],
                "package native family/artifact format differs from source")
        report.update(contract)
        report["native_boundary"] = check_native_boundary(root, target, abi_family=contract["native_abi_family"])
        if contract["native_abi_family"] == NATIVE_FAMILIES[1]:
            selection = check_native_selection(root, target)
            require(metadata.get("checked_native_selection") == selection, "checked108 package selection metadata differs")
            report["checked_native_selection"] = selection
        require(read_json(regular(root, "platform-proof.json")) == platform_evidence(root, target, output / "platform-logs"),
                "packaged platform metadata differs")
        require(digest(regular(root, "static-boundary.json")) == metadata["static_boundary_sha256"],
                "static boundary receipt identity differs")
        report["static_boundary"] = check_static_boundary(root, target)
        report["deployment_transform"] = check_deployment(root, target, bundle, output / "deployment-logs")
        env = installed_environment(scratch, sdkroot)
        env.update(JOINTS_LIB=str(library), JOINTS_LIB_DIR=str(library.parent), IRGX_LIB_DIR=str(library.parent))
        logs = output / "logs"
        def run(args, cwd=scratch):
            return command(list(map(str, args)), cwd=cwd, env=env, logs=logs, records=records)
        run(["rustup", "run", rust_toolchain, "rustc", "-Vv"])
        run([python, "--version"])
        cli = root / "bin/joints-rs";grammar = root / "grammar/json.json"
        check_cli_identity(run([cli, "--version"]).stdout)
        data = scratch / "source.json";data.write_bytes('{"café":[1,2]}'.encode())
        parsed = run([cli, "parse", grammar, data, "--all", "--json", "--mend=none", "--no-supply"])
        answer = json.loads(parsed.stdout)
        require(stamp.strict(answer), "installed CLI did not strictly parse")
        require(answer["survey"]["sound"] is True, "installed CLI returned an unsound tree")
        query = scratch / "captures.scm";query.write_text("(number) @n\n")
        found = json.loads(run([cli, "query", grammar, query, data, "--json"]).stdout)
        captures = [c for match in found["matches"] for c in match["captures"]]
        require(found["accepted"] is True and found["sound"] is True
                and len(found["matches"]) == len(captures) == 2
                and all(c["name"] == "n" for c in captures)
                and [data.read_bytes()[c["start"]:c["end"]] for c in captures] == [b"1", b"2"],
                "installed CLI query captures differ")
        minted = scratch / "grammar.jnt";run([cli, "mint", grammar, "-o", minted])
        run([cli, "parse", minted, data, "--quiet", "--mend=none", "--no-supply"])
        # Refusal commands are captured independently, since success is wrong.
        legacy = scratch / "legacy.folio";legacy.write_bytes(b"folio\0legacy draft")
        rejected = subprocess.run([str(cli), "parse", str(legacy), str(data), "--quiet"],
                                  cwd=scratch, env=env, capture_output=True)
        require(rejected.returncode == 2 and rejected.stderr, "legacy/unknown artifact was silently accepted")
        (logs / "artifact-refusal.stdout").write_bytes(rejected.stdout)
        (logs / "artifact-refusal.stderr").write_bytes(rejected.stderr)
        report["artifact_refusal"] = {"exit": rejected.returncode,
            "stdout_sha256": digest(logs / "artifact-refusal.stdout"), "stderr_sha256": digest(logs / "artifact-refusal.stderr")}
        native = minted.read_bytes()
        wire = contract["artifact_format"]
        require(native[:8] == b"JNTRART\0" and native[8:16]
                == wire["version"].to_bytes(4, "little") + wire["schema"].to_bytes(4, "little"),
                "minted native artifact format differs")
        report["old_native_refusals"] = []
        previous_formats = [("version" + str(value), 8, value) for value in range(1, wire["version"])]
        previous_formats += [("schema" + str(value), 12, value) for value in range(2, wire["schema"])]
        for label, offset, previous in previous_formats:
            old = bytearray(native);old[offset:offset + 4] = previous.to_bytes(4, "little")
            path = scratch / (label + ".jnt");path.write_bytes(old)
            refused = subprocess.run([str(cli), "parse", str(path), str(data), "--quiet"],
                                     cwd=scratch, env=env, capture_output=True)
            require(refused.returncode == 2 and b"re-mint" in refused.stderr,
                    "old native version/schema did not explicitly require re-mint")
            for channel in ("stdout", "stderr"):
                (logs / (label + "." + channel)).write_bytes(getattr(refused, channel))
            report["old_native_refusals"].append({"case": label, "input_sha256": digest(path), "exit": refused.returncode,
                **{channel + "_sha256": digest(logs / (label + "." + channel)) for channel in ("stdout", "stderr")}})
        c = scratch / "consumer.c";c.write_text(C_SMOKE)
        compiler = shutil.which("cc");require(compiler, "C compiler unavailable")
        for kind in ("static", "dynamic"):
            binary = scratch / ("c-" + kind)
            link = [root / "lib/libjnt.a"] if kind == "static" else [library]
            system = ["-lpthread", "-ldl", "-lm"] if target.startswith("linux") else []
            run([compiler, "-std=c11", "-Werror", "-I", root / "include", c, *link,
                 *system, "-Wl,-rpath," + str(library.parent), "-o", binary])
            if kind == "dynamic" and target == "macos-arm64":
                require("@rpath/libjnt.dylib" in macho_metadata(binary.read_bytes())["dependencies"],
                        "ordinary dynamic client did not select the relocatable library")
            run([binary, grammar, *([library] if kind == "dynamic" else [])])
        # Build portable packages exclusively from delivered sources/deps.
        builder = scratch / "builder";run([python, "-m", "venv", builder])
        bp = builder / "bin/python";wheelhouse = source / "dependencies/python"
        run([bp, "-m", "pip", "install", "--no-index", "--find-links", wheelhouse, "build", "hatchling"])
        packages = scratch / "packages"
        run([bp, "-m", "build", "--no-isolation", "--wheel", "--sdist", "--outdir", packages,
             source / "joints/bindings/python"])
        wheels = list(packages.glob("*.whl"));sdists = list(packages.glob("*.tar.gz"))
        require(len(wheels) == len(sdists) == 1, "portable Python package roster differs")
        smoke = source / "joints/tool/release/smoke.py"
        def installed_python(wheel: Path, name: str):
            venv = scratch / name;run([python, "-m", "venv", venv])
            interpreter = venv / "bin/python"
            run([interpreter, "-m", "pip", "install", "--no-index", "--no-deps", wheel])
            run([interpreter, "-I", smoke, "0.1.0", library, grammar])
        installed_python(wheels[0], "wheel-consumer")
        sdist = unpack(sdists[0], scratch / "sdist", "joints-0.1.0")
        rebuilt = scratch / "rebuilt-wheel"
        run([bp, "-m", "build", "--no-isolation", "--wheel", "--outdir", rebuilt, sdist])
        candidates = list(rebuilt.glob("*.whl"));require(len(candidates) == 1, "sdist wheel roster differs")
        installed_python(candidates[0], "sdist-consumer")
        cargo = ["rustup", "run", rust_toolchain, "cargo"]
        # The delivered engine itself, not only its C binding, must compile at
        # the declared floor using the extracted matching additive irgx APIs.
        run([*cargo, "check", "--manifest-path", source / "joints/rust/Cargo.toml", "--workspace",
             "--all-targets", "--locked", "--offline"], cwd=source)
        defaults = run([*cargo, "test", "--manifest-path", source / "joints/rust/Cargo.toml", "--workspace",
                        "--locked", "--offline"], cwd=source)
        report["engine_default_tests"] = default_test_summary(defaults.stdout, rust_toolchain)
        run([*cargo, "package", "--locked", "--offline", "--allow-dirty", "--no-verify",
             "--manifest-path", source / "joints/bindings/rust/Cargo.toml"], cwd=source)
        crate = scratch / "cargo-target/package/joints-0.1.0.crate"
        installed = unpack(crate, scratch / "crate", "joints-0.1.0")
        config = scratch / ".cargo/config.toml";config.parent.mkdir()
        config.write_text('[source.crates-io]\nreplace-with="candidate-vendor"\n'
                          '[source.candidate-vendor]\ndirectory=' + json.dumps(str(source / "dependencies/cargo")) + '\n')
        run([*cargo, "test", "--locked", "--offline"], cwd=installed)
        # A C static archive owns an isolated runtime. Test both floor and
        # producer compiler clients, including same-version LTO coexistence.
        import rust_static_boundary as boundary
        static = read_json(regular(root, "static-boundary.json"))
        personality = "_rust_eh_personality" if target == "macos-arm64" else "rust_eh_personality"
        raw_private = static["facts"]["mapping"][personality]
        private = raw_private[1:] if target == "macos-arm64" else raw_private
        report["rust_static_coexistence"] = []
        for version in ("1.85.0", "1.96.0"):
            tools = ["rustup", "run", version, "cargo"]
            run(["rustup", "run", version, "rustc", "-Vv"])
            for mode in ("default", "lto"):
                client = scratch / ("static-" + version + "-" + mode)
                (client / "src").mkdir(parents=True)
                (client / "Cargo.toml").write_text('[workspace]\n[package]\nname="installed-static-client"\nversion="0.0.0"\nedition="2024"\n'
                    '[dependencies]\njoints={path=' + json.dumps(str(installed)) + '}\n'
                    + ('[profile.release]\nlto=true\ncodegen-units=1\n' if mode == "lto" else ''))
                (client / "src/main.rs").write_text('unsafe extern "C" {fn rust_eh_personality();\n#[link_name="'
                    + private + '"] fn engine_personality();}\n'
                    'fn main(){assert_ne!(rust_eh_personality as *const () as usize,engine_personality as *const () as usize);'
                    'assert!(std::panic::catch_unwind(||panic!("consumer panic")).is_err());'
                    'let b=joints::Bank::open(std::env::args().nth(1).unwrap()).unwrap();let p=b.parser(None).unwrap();'
                    'let s=Vec::from(b"[1,2]".as_slice());let t=p.parse(&s).unwrap();drop(s);'
                    'assert!(t.confidence().is_strict());assert_eq!(t.source(),b"[1,2]");'
                    'assert!(p.parse(b"[4]").unwrap().confidence().is_strict());'
                    'let q=p.query("(number) @n").unwrap();assert_eq!(q.matches(&t,joints::ForeignPolicy::Refuse).unwrap().len(),2);'
                    'println!("distinct-runtime-handlers");}')
                client_env = dict(env, JOINTS_LINK_KIND="static",
                                  CARGO_TARGET_DIR=str(scratch / ("static-target-" + version + "-" + mode)))
                def static_run(args):
                    return command(list(map(str, args)), cwd=client, env=client_env, logs=logs, records=records)
                static_run([*tools, "generate-lockfile", "--offline"])
                answer = static_run([*tools, "run", *(["--release"] if mode == "lto" else []),
                                     "--locked", "--offline", "--", grammar])
                require(answer.stdout.strip() == b"distinct-runtime-handlers", "static runtime ownership evidence missing")
                report["rust_static_coexistence"].append({"toolchain": version, "mode": mode, "pass": True})
        api = scratch / "native-api-consumer";(api / "src").mkdir(parents=True)
        (api / "Cargo.toml").write_text('[workspace]\n[package]\nname="installed-native-api-consumer"\nversion="0.0.0"\nedition="2024"\n'
            '[dependencies]\njoints-engine={path=' + json.dumps(str(source / "joints/rust")) + '}\n'
            'irgx={path=' + json.dumps(str(source / "irregex/bindings/rust")) + ',features=["source-engine"]}\n'
            'pcre2="=0.2.11"\npcre2-sys="=0.2.10"\nserde_json="1"\n[profile.release]\nlto=true\ncodegen-units=1\n')
        mapping = report["native_boundary"]["mapping"]
        prefix = "_" if target == "macos-arm64" else ""
        names = [mapping[prefix + name] for name in ("pcre2_compile_8", "pcre2_match_8")]
        if prefix: names = [name[1:] for name in names]
        header = (source / "irregex/vendor/pcre2/src/pcre2.h").read_text()
        major = re.search(r"#define\s+PCRE2_MAJOR\s+(\d+)", header)
        minor = re.search(r"#define\s+PCRE2_MINOR\s+(\d+)", header)
        require(major and minor, "source-attested native PCRE version missing")
        backend_version = major[1] + "." + minor[1]
        (api / "src/main.rs").write_text(native_api_source(*names, backend_version))
        run([*cargo, "generate-lockfile", "--offline"], cwd=api)
        api_inputs = {str(path): digest(path) for path in (api / "Cargo.toml", api / "Cargo.lock", api / "src/main.rs")}
        report["native_api_coexistence"] = []
        for version in ("1.85.0", "1.96.0"):
            for mode in ("default", "lto"):
                api_env = dict(env, CARGO_TARGET_DIR=str(scratch / ("native-api-target-" + version + "-" + mode)))
                answer = command(["rustup", "run", version, "cargo", "run", *(["--release"] if mode == "lto" else []),
                                  "--locked", "--offline", "--", str(grammar)],
                                 cwd=api, env=api_env, logs=logs, records=records)
                observed = json.loads(answer.stdout)
                require(observed["engine_parse_query"] is True and observed["captures"] == 3
                        and observed["invalid_both_refused"] is True
                        and observed["oracle_runtime_config_version"].startswith("10.46 ")
                        and observed["irgx_source_attested_version"] == backend_version
                        and observed["irgx_reported_version_corroboration"] == backend_version
                        and len(observed["compile_match_addresses"]) == 2
                        and all(a != b for a, b in observed["compile_match_addresses"]),
                        "installed independent static PCRE consumer differs")
                require(all(digest(Path(path)) == expected for path, expected in api_inputs.items()),
                        "installed native API consumer changed during checks")
                report["native_api_coexistence"].append({"toolchain": version, "mode": mode,
                    "observed": observed, "source_lock_inputs": api_inputs})
        check_files(root, metadata["files"])
        require(digest(archive) == report["archive"]["sha256"], "package changed during checks")
        report.update({"pass": True, "target": target, "versions": VERSIONS,
                       "source_manifest_sha256": metadata["source_manifest_sha256"],
                       "native_archive_sha256": metadata["native_archive_sha256"],
                       "selected_native_archive_sha256": metadata["selected_native_archive_sha256"],
                       "resolution_scope": "extracted scratch, empty Cargo home/offline vendor, isolated installed Python; no original checkout path dependency",
                       "host": {"system": platform.system(), "machine": platform.machine()},
                       "sdkroot": env.get("SDKROOT")})
        return report
    except Exception as error:
        report["error"] = str(error)
        raise
    finally:
        (output / "report.json").write_bytes(encoded(report))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="verb", required=True)
    export = sub.add_parser("export", help="new standalone source tree with offline dependencies; no engine build")
    export.add_argument("--root", type=Path, default=ROOT)
    export.add_argument("--irregex", type=Path, required=True)
    export.add_argument("--compiled-proof", type=Path, required=True)
    export.add_argument("--zig-cache", type=Path, required=True)
    export.add_argument("--output", type=Path, required=True)
    export.add_argument("--cargo", default="cargo")
    export.add_argument("--python", default=sys.executable)
    export.add_argument("--offline", action="store_true")
    export.add_argument("--wheelhouse", type=Path, help="pre-downloaded Python build wheels, required for offline export")
    export.add_argument("--exclude-source", action="append", default=[], metavar="RELATIVE_FILE",
                        help="omit an explicit unrelated joints source file; compiled inputs cannot be excluded; path/hash retained")
    pack = sub.add_parser("pack", help="package a source-joined native bundle as a nonpublishable local candidate")
    pack.add_argument("--source", type=Path, required=True)
    pack.add_argument("--bundle", type=Path, required=True)
    pack.add_argument("--irgx-archive", type=Path, required=True)
    pack.add_argument("--output", type=Path, required=True)
    pack.add_argument("--target", choices=TARGETS, required=True)
    pack.add_argument("--execution-scope", choices=("native-host", "emulated"), required=True,
                      help="declared build/package context; retained without constraining later verification runs")
    pack.add_argument("--objcopy", type=Path, required=True, help="explicit LLVM objcopy for checked C static boundary")
    pack.add_argument("--indexer", type=Path, help="explicit Apple libtool when sorted BSD TOC restoration is needed")
    pack.add_argument("--irgx-abi-family", choices=NATIVE_FAMILIES, default=NATIVE_FAMILIES[0],
                      help="must match delivered source; Image1 requires explicit native108 selection")
    verify = sub.add_parser("verify", help="install and execute extracted CLI/C/Python/Rust consumers in scratch")
    verify.add_argument("--archive", type=Path, required=True)
    verify.add_argument("--output", type=Path, required=True)
    verify.add_argument("--execution-scope", choices=("native-host", "emulated"), required=True,
                        help="execution context of this verification run, recorded separately from package context")
    verify.add_argument("--python", default=sys.executable)
    verify.add_argument("--rust-toolchain", default="1.85.0")
    verify.add_argument("--sdkroot", type=Path)
    args = parser.parse_args()
    try:
        if args.verb == "export":
            value = export_source(args.root, args.irregex, args.output, args.compiled_proof, args.zig_cache,
                                  cargo=args.cargo, python=args.python, offline=args.offline,
                                  wheelhouse=args.wheelhouse, exclude_sources=tuple(args.exclude_source))
        elif args.verb == "pack":
            value = pack_candidate(args.source, args.bundle, args.irgx_archive, args.output,
                                   args.target, args.execution_scope, objcopy=args.objcopy, indexer=args.indexer,
                                   abi_family=args.irgx_abi_family)
        else:
            value = verify_candidate(args.archive, args.output, args.execution_scope, python=args.python,
                                     rust_toolchain=args.rust_toolchain, sdkroot=args.sdkroot)
        print(json.dumps(value, indent=2))
        return 0
    except (ValueError, OSError, subprocess.SubprocessError, KeyError, TypeError, tarfile.TarError) as error:
        print(f"rust delivery refused: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

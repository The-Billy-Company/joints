#!/usr/bin/env python3
"""Package a Rust staticlib as an opaque native archive for C ABI consumers.

Rust LTO recognizes *.rcgu.o members bundled inside an rlib as Rust code and
expects embedded bitcode. A Rust-produced staticlib includes object-only CGUs.
Neutral member names preserve the native boundary; payloads and order never
change. Always rebuild and verify the archive rather than trust old receipts
or already-normalized names. The selected Zig ar rebuilds its symbol index.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
from collections.abc import Iterator
from dataclasses import dataclass
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
from typing import TypedDict

MAX_ARCHIVE_BYTES = 1 << 30
MAX_MEMBERS = 100_000
MAX_NAME_BYTES = 65_536
INDEX_NAMES = {b"/", b"/SYM64/", b"__.SYMDEF", b"__.SYMDEF SORTED",
               b"__.SYMDEF_64", b"__.SYMDEF_64 SORTED"}


class MemberProof(TypedDict):
    position: int
    original_name: str
    original_name_hex: str
    normalized_name: str
    bytes: int
    sha256: str


class ArchiverProof(TypedDict):
    path: str
    sha256: str
    version: str
    command: list[str]


class NormalizationProof(TypedDict):
    schema: int
    normalizer_sha256: str
    path: str
    input_sha256: str
    output_sha256: str
    changed: bool
    member_count: int
    members: list[MemberProof]
    archiver: ArchiverProof


class Arguments(argparse.Namespace):
    archive: Path
    zig: str
    receipt: Path | None


def sha(data: bytes | memoryview) -> str:
    return hashlib.sha256(data).hexdigest()


@dataclass(frozen=True)
class Member:
    name: bytes
    start: int
    end: int


@dataclass(frozen=True)
class Archive:
    data: bytes
    members: tuple[Member, ...]

    def payload(self, member: Member) -> memoryview:
        return memoryview(self.data)[member.start:member.end]


def read_archive(path: Path) -> Archive:
    """Read regular BSD/GNU ar, keeping duplicate names and exact payloads."""
    with path.open("rb") as stream:
        data = stream.read(MAX_ARCHIVE_BYTES + 1)
    if len(data) > MAX_ARCHIVE_BYTES:
        raise ValueError("native archive exceeds the byte limit")
    if data.startswith(b"!<thin>\n"):
        raise ValueError("thin archives are not standalone native libraries")
    if not data.startswith(b"!<arch>\n"):
        raise ValueError("unrecognized native archive")
    records = []
    position = 8
    long_names = None
    while position < len(data):
        header = data[position:position + 60]
        if len(header) != 60 or header[58:] != b"`\n":
            raise ValueError("truncated or invalid archive header")
        size_text = header[48:58].strip()
        if not size_text.isdigit():
            raise ValueError("invalid archive member size")
        size = int(size_text)
        start, end = position + 60, position + 60 + size
        if end > len(data):
            raise ValueError("truncated archive member")
        name = header[:16].rstrip(b" ")
        if name.startswith(b"#1/"):
            count_text = name[3:]
            if not count_text.isdigit():
                raise ValueError("invalid BSD archive name length")
            count = int(count_text)
            if count > size or count > MAX_NAME_BYTES:
                raise ValueError("invalid BSD archive name extent")
            name = data[start:start + count].rstrip(b"\0")
            start += count
        if name == b"//":
            if long_names is not None:
                raise ValueError("duplicate GNU archive name table")
            long_names = data[start:end]
        else:
            records.append(Member(name, start, end))
        if len(records) > MAX_MEMBERS:
            raise ValueError("native archive exceeds the member limit")
        position = end
        if size % 2:
            if data[position:position + 1] != b"\n":
                raise ValueError("missing archive member padding")
            position += 1
    members = []
    for member in records:
        name = member.name
        if name in INDEX_NAMES:
            continue
        if name.startswith(b"/"):
            if not name[1:].isdigit() or long_names is None:
                raise ValueError("invalid GNU archive name reference")
            offset = int(name[1:])
            if offset >= len(long_names):
                raise ValueError("GNU archive name offset exceeds the table")
            end = long_names.find(b"/\n", offset)
            if end < 0:
                raise ValueError("unterminated GNU archive name")
            name = long_names[offset:end]
        else:
            name = name.removesuffix(b"/")
        if not name or b"\0" in name or len(name) > MAX_NAME_BYTES:
            raise ValueError("invalid archive member name")
        if name in INDEX_NAMES:
            continue
        members.append(Member(name, member.start, member.end))
    if not members:
        raise ValueError("native archive contains no object members")
    return Archive(data, tuple(members))


@contextmanager
def archive_lock(path: Path) -> Iterator[None]:
    # A stable sidecar inode serializes repeated atomic replacements as well.
    with path.with_name(f".{path.name}.normalize.lock").open("a") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        yield


def normalize(path: Path, *, zig: str = "zig") -> NormalizationProof:
    """Atomically normalize current bytes; return the complete transformation proof.

    Concurrent producers must honor the same lock (the build helper already
    serializes its own build). Source drift during the archiver run refuses
    publication. The returned receipt never substitutes for reading the input.
    """
    path = path.resolve(strict=True)
    script_hash = sha(Path(__file__).read_bytes())
    selected = shutil.which(zig)
    if selected is None:
        raise ValueError(f"Zig archiver is unavailable: {zig}")
    executable = Path(selected).resolve(strict=True)
    tool_hash = sha(executable.read_bytes())
    version = subprocess.run([str(executable), "version"], check=True,
                             capture_output=True, text=True).stdout.strip()
    if not version:
        raise ValueError("Zig archiver omitted its version")
    with archive_lock(path):
        original = read_archive(path)
        original_hash = sha(original.data)
        mode = stat.S_IMODE(path.stat().st_mode)
        with tempfile.TemporaryDirectory(prefix=".native-archive-", dir=path.parent) as directory:
            work = Path(directory)
            names = []
            for i, member in enumerate(original.members):
                name = f"native-{i:06d}.o"
                target = work / name
                target.write_bytes(original.payload(member))
                target.chmod(0o644)
                names.append(name)
            # Response entries are generated ASCII basenames, never input paths.
            (work / "members.rsp").write_text("\n".join(names) + "\n")
            command = [str(executable), "ar", "rcsD", "normalized.a", "@members.rsp"]
            subprocess.run(command, cwd=work, check=True, capture_output=True)
            output = read_archive(work / "normalized.a")
            if len(output.members) != len(original.members):
                raise ValueError("archiver changed the object member count")
            proof: list[MemberProof] = []
            for i, (before, after) in enumerate(zip(original.members, output.members)):
                if after.name != names[i].encode() or original.payload(before) != output.payload(after):
                    raise ValueError("archiver changed object bytes or order")
                proof.append({"position": i,
                              "original_name": before.name.decode("utf-8", errors="replace"),
                              "original_name_hex": before.name.hex(),
                              "normalized_name": names[i],
                              "bytes": before.end - before.start,
                              "sha256": sha(original.payload(before))})
            if sha(path.read_bytes()) != original_hash:
                raise ValueError("native archive changed during normalization; replacement refused")
            if sha(Path(__file__).read_bytes()) != script_hash:
                raise ValueError("archive normalizer changed during normalization")
            if sha(executable.read_bytes()) != tool_hash:
                raise ValueError("Zig archiver changed during normalization")
            output_hash = sha(output.data)
            changed = original_hash != output_hash
            if changed:
                temporary = work / "normalized.a"
                temporary.chmod(mode)
                with temporary.open("rb") as stream:
                    os.fsync(stream.fileno())
                os.replace(temporary, path)
                descriptor = os.open(path.parent, os.O_RDONLY)
                try:
                    os.fsync(descriptor)
                finally:
                    os.close(descriptor)
            if sha(path.read_bytes()) != output_hash:
                raise ValueError("normalized native archive changed before proof publication")
            return {"schema": 1, "normalizer_sha256": script_hash, "path": str(path), "input_sha256": original_hash,
                    "output_sha256": output_hash, "changed": changed,
                    "member_count": len(proof), "members": proof,
                    "archiver": {"path": str(executable), "sha256": tool_hash,
                                 "version": version, "command": command}}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--zig", default=os.environ.get("ZIG", "zig"))
    parser.add_argument("--receipt", type=Path)
    args = parser.parse_args(namespace=Arguments())
    try:
        if args.receipt and args.receipt.resolve() == args.archive.resolve():
            raise ValueError("receipt cannot replace its native archive")
        proof = normalize(args.archive, zig=args.zig)
        text = json.dumps(proof, indent=2) + "\n"
        if args.receipt:
            args.receipt.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(mode="w", dir=args.receipt.parent, delete=False) as stream:
                temporary = Path(stream.name)
                stream.write(text)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, args.receipt)
        else:
            print(text, end="")
        return 0
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"native archive normalization failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

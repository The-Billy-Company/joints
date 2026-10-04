"""Prove downloaded payloads are the original authenticated build artifacts."""

import hashlib
import io
import json
from pathlib import PurePosixPath
import stat
import subprocess
import tarfile
import urllib.error
import urllib.parse
import urllib.request
import zipfile

import context

require = context.require
LIMIT = 512 * 1024 * 1024
TARGETS = {"linux-x86_64", "macos-arm64"}


def encoded(value):
    return (json.dumps(value, sort_keys=True, indent=2) + "\n").encode()


def checksum(data):
    return hashlib.sha256(data).hexdigest()


def read_limited(response):
    result = io.BytesIO()
    while chunk := response.read(1024 * 1024):
        require(result.tell() + len(chunk) <= LIMIT, "artifact ZIP exceeds size limit")
        result.write(chunk)
    return result.getvalue()


def transport(url, headers):
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None

    try:
        opener = urllib.request.build_opener(NoRedirect())
        with opener.open(
            urllib.request.Request(url, headers=headers), timeout=30
        ) as response:
            return response.status, read_limited(response), None
    except urllib.error.HTTPError as error:
        # Signed storage URLs and response bodies must never reach error logs.
        return error.code, b"", error.headers.get("Location")
    except (urllib.error.URLError, OSError, TimeoutError):
        raise context.ContextError("artifact download did not answer") from None


def storage_location(location):
    try:
        parsed = urllib.parse.urlsplit(location or "")
        port = parsed.port
    except ValueError:
        raise context.ContextError("artifact storage redirect is malformed") from None
    host = parsed.hostname or ""
    require(
        parsed.scheme == "https"
        and (
            host.endswith(".blob.core.windows.net")
            or host.endswith(".actions.githubusercontent.com")
            or host == "objects.githubusercontent.com"
        )
        and port in (None, 443)
        and parsed.username is None
        and parsed.password is None
        and not parsed.fragment,
        "artifact storage redirect is unexpected",
    )
    return location


def fetch(record, token, download=transport):
    require(bool(token), "artifact integrity verification needs a GitHub token")
    endpoint = (
        f"https://api.github.com/repos/{context.REPOSITORY}/actions/artifacts/"
        f"{record['id']}/zip"
    )
    status, data, location = download(
        endpoint,
        {"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json"},
    )
    if status in (302, 307):
        # Start a fresh unauthenticated request; never forward the GitHub token.
        status, data, _redirect = download(storage_location(location), {})
    require(status == 200, f"artifact ZIP download failed (HTTP {status})")
    require(len(data) <= LIMIT, "artifact ZIP exceeds size limit")
    require(
        "sha256:" + checksum(data) == record["digest"],
        "original artifact ZIP digest mismatch",
    )
    return data


def safe_name(name):
    path = PurePosixPath(name)
    require(
        bool(path.parts)
        and not path.is_absolute()
        and ".." not in path.parts
        and "\\" not in name
        and "\x00" not in name
        and path.as_posix() == name.rstrip("/"),
        "artifact member path is unsafe",
    )
    return path


def members(data, expected):
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            rows = archive.infolist()
            require(len(rows) <= 20, "artifact ZIP has unexpected member count")
            names, files, total = set(), {}, 0
            for row in rows:
                path = safe_name(row.filename)
                name = path.as_posix()
                require(name not in names, "artifact ZIP has duplicate members")
                names.add(name)
                mode = stat.S_IFMT(row.external_attr >> 16)
                require(
                    mode in (0, stat.S_IFREG, stat.S_IFDIR) and not row.flag_bits & 1,
                    "artifact ZIP has a link, special or encrypted member",
                )
                total += row.file_size
                require(0 <= total <= LIMIT, "artifact ZIP expands beyond size limit")
                if row.is_dir():
                    require(
                        name in {str(PurePosixPath(item).parent) for item in expected},
                        "artifact ZIP has an unexpected directory",
                    )
                else:
                    require(name in expected, "artifact ZIP has an unexpected file")
                    files[name] = archive.read(row)
            require(set(files) == expected, "artifact ZIP inventory mismatch")
            return files
    except (zipfile.BadZipFile, OSError, ValueError):
        raise context.ContextError("artifact ZIP is malformed") from None


def source_ledger(root, sha):
    require(context.git(root, "rev-parse", "HEAD") == sha, "source checkout moved")
    require(
        not context.git(root, "status", "--porcelain", "--untracked-files=normal"),
        "source checkout is dirty",
    )
    try:
        paths = subprocess.check_output(
            ["git", "ls-files", "-z"], cwd=root, stderr=subprocess.PIPE
        ).decode()
        files = {}
        for name in paths.split("\0"):
            if name:
                safe_name(name)
                path = root / name
                require(
                    path.is_file()
                    and not path.is_symlink()
                    and path.resolve() == root.resolve() / name,
                    "source checkout contains a link or missing tracked file",
                )
                files[name] = checksum(path.read_bytes())
    except (OSError, UnicodeError, subprocess.CalledProcessError):
        raise context.ContextError(
            "could not hash the release source checkout"
        ) from None
    return {
        "commit": sha,
        "dirty": False,
        "files": files,
        "ledger_sha256": checksum(encoded(files)),
    }


def native_manifest(data, version, target):
    prefix = f"joints-{version}-{target}"
    try:
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
            names, total, manifest = set(), 0, None
            for row in archive:
                path = safe_name(row.name)
                require(
                    path.parts[0] == prefix and (row.isfile() or row.isdir()),
                    "original native archive has unsafe members",
                )
                require(row.name not in names, "original native archive has duplicates")
                names.add(row.name)
                total += row.size
                require(0 <= total <= LIMIT, "native archive expands beyond size limit")
                if row.name == f"{prefix}/manifest.json":
                    require(
                        row.isfile() and row.size < 8 * 1024 * 1024, "invalid manifest"
                    )
                    manifest = json.loads(archive.extractfile(row).read())
            require(isinstance(manifest, dict), "original native manifest is missing")
            require(
                manifest.get("schema") == 1
                and manifest.get("version") == version
                and manifest.get("target") == target,
                "original native manifest identity mismatch",
            )
            return manifest
    except (tarfile.TarError, OSError, ValueError):
        raise context.ContextError("original native archive is malformed") from None


def compare_local(root, files, native_target):
    expected = dict(files["packages"])
    targets = (
        TARGETS
        if native_target == "all"
        else {native_target}
        if native_target
        else set()
    )
    for target in targets:
        expected.update(
            {"native/" + name: data for name, data in files["native-" + target].items()}
        )
    if native_target == "all" and (root / "SHA256SUMS").exists():
        sums = {
            PurePosixPath(name).name: checksum(data) for name, data in expected.items()
        }
        expected["SHA256SUMS"] = "".join(
            f"{value}  {name}\n" for name, value in sorted(sums.items())
        ).encode()
    actual = set()
    for path in root.rglob("*"):
        require(not path.is_symlink(), "downloaded artifact contains a link")
        if path.is_file():
            actual.add(path.relative_to(root).as_posix())
    require(
        actual == set(expected),
        "downloaded artifact inventory differs from original ZIPs",
    )
    for name, data in expected.items():
        path = root / name
        require(
            path.is_file()
            and path.resolve() == root.resolve() / name
            and checksum(path.read_bytes()) == checksum(data),
            "downloaded artifact bytes differ from original ZIPs",
        )


def verify(
    root,
    source_root,
    environ,
    tag,
    sha,
    run_id,
    api,
    token,
    target=None,
    download=transport,
):
    context.assert_context(source_root, environ, tag, sha, run_id, api)
    context.source(source_root, environ, tag, sha)
    ledger = source_ledger(source_root, sha)
    version = context.TAG.fullmatch(tag).group(1)
    package_names = {
        "packages.json",
        f"python/joints-{version}-py3-none-any.whl",
        f"python/joints-{version}.tar.gz",
        f"rust/joints-{version}.crate",
    }
    payloads = {}
    for record in context.artifact_records(run_id, tag, sha, api):
        name = record["name"]
        expected = (
            package_names
            if name == "packages"
            else {f"joints-{version}-{name.removeprefix('native-')}.tar.gz"}
        )
        payloads[name] = members(fetch(record, token, download), expected)
    try:
        package = json.loads(payloads["packages"]["packages.json"])
        require(
            package.get("schema") == 1
            and package.get("version") == version
            and package.get("source") == ledger,
            "original package source ledger differs from tagged checkout",
        )
        require(
            package.get("files")
            == {
                name: checksum(data)
                for name, data in payloads["packages"].items()
                if name != "packages.json"
            },
            "original package receipt differs from ZIP payload",
        )
        for native_target in TARGETS:
            data = payloads["native-" + native_target][
                f"joints-{version}-{native_target}.tar.gz"
            ]
            require(
                native_manifest(data, version, native_target).get("source") == ledger,
                "original native source ledger differs from tagged checkout",
            )
    except (KeyError, ValueError, TypeError, AttributeError):
        raise context.ContextError("original artifact receipt is malformed") from None
    compare_local(root, payloads, target)
    require(
        source_ledger(source_root, sha) == ledger,
        "source changed during artifact proof",
    )
    return {"artifact_run": run_id, "source_sha": sha, "original_artifacts": "verified"}

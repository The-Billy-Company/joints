#!/usr/bin/env python3
"""Attach verified original-tag assets and publish their curated GitHub notes."""

import argparse
import hashlib
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPOSITORY = "The-Billy-Company/joints"
NOT_FOUND = object()
MAX_RELEASE_PAGES = 20


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def run(*command, cwd=None):
    subprocess.run(command, cwd=cwd, check=True)


def release_command(*arguments):
    run("gh", "release", *arguments, "--repo", REPOSITORY)


def assert_context(args):
    run(
        sys.executable,
        str(Path(__file__).with_name("publisher.py")),
        "verify-artifacts",
        "--release-tag",
        args.tag,
        "--source-sha",
        args.source_sha,
        "--artifact-run",
        args.artifact_run,
        "--artifact-root",
        str(args.packages),
        "--source-root",
        str(args.source_root),
        "--native-target",
        "all",
    )


def release_json(endpoint, *, allow_missing=False):
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, request, response, code, message, headers, url):
            raise RuntimeError("unexpected release API redirect")

    request = urllib.request.Request(
        endpoint,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": "Bearer " + os.environ["GH_TOKEN"],
        },
    )
    try:
        with urllib.request.build_opener(NoRedirect).open(
            request, timeout=30
        ) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        if error.code == 404 and allow_missing:
            return NOT_FOUND
        raise RuntimeError(f"release API refused lookup: HTTP {error.code}") from error


def release_record(record):
    require(
        isinstance(record, dict)
        and type(record.get("id")) is int
        and record["id"] > 0
        and record.get("url")
        == f"https://api.github.com/repos/{REPOSITORY}/releases/{record['id']}"
        and isinstance(record.get("tag_name"), str)
        and bool(record["tag_name"])
        and type(record.get("draft")) is bool
        and isinstance(record.get("assets"), list),
        "malformed release API record",
    )


def release(tag):
    base = f"https://api.github.com/repos/{REPOSITORY}/releases"
    record = release_json(
        base + "/tags/" + urllib.parse.quote(tag, safe=""), allow_missing=True
    )
    if record is not NOT_FOUND:
        release_record(record)
        require(record["tag_name"] == tag, "wrong release tag")
        return record
    match = None
    seen = set()
    # Drafts can be absent from the tag endpoint. Scan through an empty page
    # before choosing a match, including after short pages or a matching draft.
    for page in range(1, MAX_RELEASE_PAGES + 1):
        records = release_json(f"{base}?per_page=100&page={page}")
        require(
            isinstance(records, list) and len(records) <= 100,
            "malformed release API page",
        )
        if not records:
            return match
        for record in records:
            release_record(record)
            require(record["id"] not in seen, "duplicate release API record")
            seen.add(record["id"])
            if record["tag_name"] == tag:
                require(match is None, "ambiguous matching releases")
                match = record
    raise RuntimeError("release API pagination bound reached before complete inventory")


def assets(record):
    values = record["assets"]
    result = {asset["name"]: asset for asset in values}
    require(len(result) == len(values), "duplicate release asset names")
    return result


def verify_assets(record, expected, *, complete):
    attached = assets(record)
    require(not (set(attached) - set(expected)), "release has unexpected assets")
    if complete:
        require(set(attached) == set(expected), "uploaded asset inventory differs")
    for name, asset in attached.items():
        path = expected[name]
        require(
            asset["state"] == "uploaded" and asset["size"] == path.stat().st_size,
            f"release asset upload is incomplete: {name}",
        )
        data = subprocess.check_output(
            [
                "gh",
                "api",
                "-H",
                "Accept: application/octet-stream",
                f"repos/{REPOSITORY}/releases/assets/{asset['id']}",
            ]
        )
        require(
            hashlib.sha256(data).digest() == hashlib.sha256(path.read_bytes()).digest(),
            f"published release asset differs: {name}",
        )
    return attached


def finalize(args):
    require(os.environ.get("GITHUB_REPOSITORY") == REPOSITORY, "unexpected repository")
    require(args.notes.is_file(), "curated release notes are missing")
    require(args.tag == f"v{args.version}", "release tag and title version differ")
    require(
        args.native_directory == args.packages / "native",
        "unexpected native asset directory",
    )
    head = subprocess.check_output(
        ["git", "-C", str(args.source_root), "rev-parse", "HEAD"], text=True
    ).strip()
    require(head == args.source_sha, "finalization source checkout differs")
    dirty = subprocess.check_output(
        ["git", "-C", str(args.source_root), "status", "--porcelain"], text=True
    ).strip()
    require(not dirty, "finalization source checkout is dirty")
    assert_context(args)
    run(
        sys.executable,
        str(args.source_root / "tool/release/artifacts.py"),
        "checksums",
        "--packages",
        str(args.packages),
        "--native-directory",
        str(args.native_directory),
        cwd=args.source_root,
    )
    files = sorted(args.native_directory.glob("*.tar.gz"))
    files += sorted((args.packages / "python").iterdir())
    files += sorted((args.packages / "rust").iterdir())
    files += [args.packages / "packages.json", args.packages / "SHA256SUMS"]
    expected = {path.name: path for path in files}
    require(len(expected) == len(files), "release asset filenames collide")
    existing = release(args.tag)
    if existing is None:
        assert_context(args)
        release_command(
            "create",
            args.tag,
            "--verify-tag",
            "--draft",
            "--prerelease",
            "--title",
            f"Joints {args.version} (experimental)",
            "--notes-file",
            str(args.notes),
        )
        existing = release(args.tag)
    require(
        existing is not None and existing["tag_name"] == args.tag, "wrong release tag"
    )
    attached = verify_assets(existing, expected, complete=False)
    missing = [str(path) for name, path in expected.items() if name not in attached]
    if missing:
        assert_context(args)
        release_command("upload", args.tag, *missing)
    attached = release(args.tag)
    require(
        attached is not None and attached["tag_name"] == args.tag, "release disappeared"
    )
    verify_assets(attached, expected, complete=True)
    assert_context(args)
    release_command(
        "edit",
        args.tag,
        "--notes-file",
        str(args.notes),
        "--prerelease",
        "--draft=false",
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("tag", "source-sha", "artifact-run", "version"):
        parser.add_argument("--" + name, required=True)
    for name in ("source-root", "packages", "native-directory", "notes"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    for name in ("source_root", "packages", "native_directory", "notes"):
        setattr(args, name, getattr(args, name).resolve())
    finalize(args)


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
        print(f"release finalization error: {error}", file=sys.stderr)
        sys.exit(2)

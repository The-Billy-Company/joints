#!/usr/bin/env python3
"""Download one exact unpublished Joints draft asset using GET requests only."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

REPOSITORY = "The-Billy-Company/joints"
API = "https://api.github.com/repos/" + REPOSITORY
LIMIT = 2 * 1024 * 1024 * 1024
METADATA_LIMIT = 8 * 1024 * 1024
STORAGE_HOSTS = {"release-assets.githubusercontent.com", "objects.githubusercontent.com"}


class DownloadError(ValueError):
    """A refused identity, response or transfer; messages never include tokens."""


def require(condition, message):
    if not condition:
        raise DownloadError(message)


def sha(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as stream:
        while block := stream.read(1024 * 1024):
            value.update(block)
    return value.hexdigest()


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def response(url, token=None, binary=False):
    """No automatic redirect can forward an authenticated request."""
    headers = {"User-Agent": "Joints-rust-candidate/1",
               "Accept": "application/octet-stream" if binary else "application/vnd.github+json"}
    if token:
        require(url.startswith(API + "/"), "authentication requires the fixed repository API")
        headers.update({"Authorization": "Bearer " + token,
                        "X-GitHub-Api-Version": "2022-11-28"})
    request = urllib.request.Request(url, headers=headers, method="GET")
    try:
        return urllib.request.build_opener(NoRedirect()).open(request, timeout=60)
    except urllib.error.HTTPError as error:
        if error.code == 302:
            return error
        status = error.code
        error.close()
        raise DownloadError(f"candidate request failed (HTTP {status})") from None
    except (urllib.error.URLError, OSError, TimeoutError):
        # Network errors may contain signed URLs, so retain only this message.
        raise DownloadError("candidate request did not answer") from None


def metadata(url, token):
    with response(url, token) as stream:
        require(stream.status == 200 and stream.geturl() == url,
                "candidate metadata response or redirect is unexpected")
        data = stream.read(METADATA_LIMIT + 1)
    require(len(data) <= METADATA_LIMIT, "candidate metadata exceeds size limit")
    try:
        value = json.loads(data)
    except (ValueError, UnicodeError):
        raise DownloadError("candidate metadata is not JSON") from None
    require(isinstance(value, dict), "candidate metadata must be an object")
    return value


def asset_identity(asset, selection):
    require(isinstance(asset, dict), "candidate asset metadata is absent")
    expected = {"id": selection["asset_id"], "name": selection["asset_name"],
                "url": f"{API}/releases/assets/{selection['asset_id']}",
                "state": "uploaded", "digest": "sha256:" + selection["sha256"]}
    require(all(asset.get(key) == value for key, value in expected.items())
            and type(asset.get("id")) is int, "candidate asset identity differs")
    size = asset.get("size")
    require(type(size) is int and 0 < size <= LIMIT, "candidate asset size is unsupported")
    return expected | {"size": size, "created_at": asset.get("created_at"),
                       "updated_at": asset.get("updated_at")}


def snapshot(selection, token):
    release_url = f"{API}/releases/{selection['release_id']}"
    release = metadata(release_url, token)
    require(type(release.get("id")) is int and release["id"] == selection["release_id"]
            and release.get("url") == release_url
            and release.get("assets_url") == release_url + "/assets",
            "candidate release identity differs")
    require(release.get("draft") is True and "published_at" in release
            and release["published_at"] is None, "candidate release must remain an unpublished draft")
    require(release.get("target_commitish") == selection["target_commit"],
            "candidate release target commit differs")
    assets = release.get("assets")
    require(isinstance(assets, list), "candidate release asset inventory is absent")
    members = [asset for asset in assets if isinstance(asset, dict)
               and asset.get("id") == selection["asset_id"]]
    require(len(members) == 1, "candidate asset is not a unique member of the release")
    member = asset_identity(members[0], selection)
    asset = asset_identity(metadata(member["url"], token), selection)
    require(asset == member, "candidate release and asset metadata disagree")
    identity = {key: release.get(key) for key in
                ("id", "url", "assets_url", "draft", "published_at", "target_commitish",
                 "tag_name", "created_at", "updated_at")}
    return {"release": identity, "asset": asset}


def storage_location(location):
    try:
        parsed = urllib.parse.urlsplit(location or "")
        port = parsed.port
    except ValueError:
        raise DownloadError("candidate asset redirect is malformed") from None
    require(parsed.scheme == "https" and parsed.hostname in STORAGE_HOSTS
            and port in (None, 443) and parsed.username is None and parsed.password is None
            and not parsed.fragment, "candidate asset redirect is unexpected")
    return location


def transfer(asset, token, target):
    stream = response(asset["url"], token, binary=True)
    try:
        require(stream.geturl() == asset["url"], "candidate asset response URL differs")
        if stream.status == 302:
            location = storage_location(stream.headers.get("Location"))
            stream.close()
            # A fresh request has no GitHub bearer token or API headers.
            stream = response(location, binary=True)
            require(stream.geturl() == location, "candidate storage response URL differs")
        require(stream.status == 200, "candidate asset download must return HTTP 200")
        length = stream.headers.get("Content-Length")
        require(length is None or (length.isdecimal() and int(length) == asset["size"]),
                "candidate asset content length differs")
        digest, size = hashlib.sha256(), 0
        while block := stream.read(1024 * 1024):
            size += len(block)
            require(size <= asset["size"] and size <= LIMIT, "candidate asset exceeds expected size")
            target.write(block)
            digest.update(block)
        require(size == asset["size"], "candidate asset download is truncated")
        require("sha256:" + digest.hexdigest() == asset["digest"], "candidate asset SHA256 differs")
        return {"bytes": size, "sha256": digest.hexdigest()}
    finally:
        stream.close()


def download(selection, out, receipt, token, metadata_only=False):
    require(type(selection["release_id"]) is int and selection["release_id"] > 0
            and type(selection["asset_id"]) is int and selection["asset_id"] > 0,
            "release and asset IDs must be positive integers")
    require(re.fullmatch("[0-9a-f]{40}", selection["target_commit"]) is not None,
            "target commit must be an exact lowercase SHA1")
    require(re.fullmatch("[0-9a-f]{64}", selection["sha256"]) is not None,
            "asset SHA256 must be exact lowercase hex")
    name = selection["asset_name"]
    require(bool(name) and len(name) <= 255 and name not in (".", "..")
            and not any(c in name for c in ("/", "\\"))
            and all(ord(c) >= 32 and ord(c) != 127 for c in name), "asset name must be one safe filename")
    require((out is None) == metadata_only, "metadata-only mode omits --out; downloads require --out")
    out = Path(out).absolute() if out is not None else None
    receipt = Path(receipt).absolute()
    require(out is None or out.resolve() != receipt.resolve(), "asset and receipt paths must differ")
    require(out is None or (not out.exists() and not out.is_symlink()), "candidate output already exists")
    require(not receipt.exists() and not receipt.is_symlink(), "candidate receipt already exists")
    if out is not None:
        out.parent.mkdir(parents=True, exist_ok=True)
    receipt.parent.mkdir(parents=True, exist_ok=True)
    report = {"schema": 1, "status": "running", "pass": False, "repository": REPOSITORY,
              "selection": dict(selection), "started": time.time(),
              "producer_sha256": sha(__file__), "method": "GET",
              "mode": "metadata-only" if metadata_only else "download-only",
              "transport_only": True, "installed_qualified": False, "cutover_authorized": False,
              "scope": "exact unpublished draft asset transport; no release or qualification verdict"}
    with receipt.open("xb") as stream:
        stream.write(encoded(report))
    temporary = None
    try:
        require(bool(token) and not any(c.isspace() for c in token), "GH_TOKEN is required")
        report["before"] = snapshot(selection, token)
        if not metadata_only:
            with tempfile.NamedTemporaryFile(dir=out.parent, prefix=".candidate-", delete=False) as target:
                temporary = Path(target.name)
                report["download"] = transfer(report["before"]["asset"], token, target)
        report["after"] = snapshot(selection, token)
        require(report["before"] == report["after"], "candidate metadata changed during download")
        if not metadata_only:
            require(sha(temporary) == selection["sha256"], "candidate staged bytes changed")
            os.link(temporary, out)
            output_sha = sha(out)
            require(output_sha == selection["sha256"], "candidate final bytes changed")
            report["output"] = {"path": str(out), "sha256": output_sha, "bytes": out.stat().st_size}
        report.update(status="complete", **{"pass": True})
    except Exception as error:
        # Arbitrary transport exceptions can embed signed URLs or tokens.
        message = str(error) if isinstance(error, DownloadError) else f"candidate transport failed ({type(error).__name__})"
        report.update(status="failed", error=message)
        raise DownloadError(message) from None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
        report["finished"] = time.time()
        receipt.write_bytes(encoded(report))
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release-id", type=int, required=True)
    parser.add_argument("--asset-id", type=int, required=True)
    parser.add_argument("--target-commit", required=True)
    parser.add_argument("--asset-name", required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--receipt", type=Path, required=True)
    parser.add_argument("--metadata-only", action="store_true")
    args = parser.parse_args(argv)
    selection = {key: getattr(args, key) for key in
                 ("release_id", "asset_id", "target_commit", "asset_name", "sha256")}
    try:
        report = download(selection, args.out, args.receipt, os.environ.get("GH_TOKEN", ""), args.metadata_only)
    except (DownloadError, OSError):
        print("draft candidate download refused; inspect the retained receipt", file=sys.stderr)
        return 1
    print(json.dumps({"receipt": str(args.receipt.absolute()), "sha256": sha(args.receipt),
                      "mode": report["mode"], "output": report.get("output")}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

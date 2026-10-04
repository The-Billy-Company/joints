#!/usr/bin/env python3
"""Prove PyPI accepts this tag's publishing identity without uploading a file.

Run only after the tag's artifact and CI gates and crates.io authentication
succeed. Exchanging a pending publisher creates its PyPI project, so this is
an authorized release step, not a read-only dry run. The temporary credential
stays in memory and is immediately submitted to PyPI's burn endpoint.

    python3 tool/publisher.py pypi-readiness
    python3 tool/publisher.py --selftest

The exchange and burn APIs are PyPI implementation details. The actual upload
uses the supported PyPA publishing action. No token, JWT or response body is
printed or written to a file; errors report the stage and HTTP status only.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, str(Path(__file__).with_suffix("")))
import context  # noqa: E402
import controls  # noqa: E402
import artifacts  # noqa: E402
import artifact_controls  # noqa: E402

ReadinessError = context.ContextError
REPOSITORY = context.REPOSITORY
ISSUER = "https://token.actions.githubusercontent.com"
INDEX = "https://pypi.org"
AUTH = "https://upload.pypi.org"
TOKEN = re.compile(r"pypi-[A-Za-z0-9_-]{16,}={0,2}\Z")


def live_transport(request: urllib.request.Request) -> tuple[int, bytes]:
    """Keep all raw remote data out of exception text and console output."""

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            # Never forward the runner's authorization header or a token payload.
            return None

    try:
        # Fixed registry hosts and the runner-provided GitHub OIDC HTTPS endpoint.
        opener = urllib.request.build_opener(NoRedirect())
        with opener.open(request, timeout=20) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as exc:
        # Failure bodies can contain identity tokens. They are never rendered.
        return exc.code, b""
    except (urllib.error.URLError, TimeoutError, OSError):
        raise ReadinessError("publishing identity endpoint did not answer") from None


def request_json(
    url: str, stage: str, transport, *, headers=None, payload=None
) -> dict:
    request_headers = {"Accept": "application/json", **(headers or {})}
    data = None
    if payload is not None:
        data = json.dumps(payload).encode()
        request_headers["Content-Type"] = "application/json"
    status, body = transport(
        urllib.request.Request(url, data=data, headers=request_headers)
    )
    if status != 200:
        raise ReadinessError(f"{stage} failed (HTTP {status})")
    try:
        decoded = json.loads(body)
    except (ValueError, UnicodeError):
        raise ReadinessError(f"{stage} returned malformed JSON") from None
    if not isinstance(decoded, dict):
        raise ReadinessError(f"{stage} returned an unexpected response")
    return decoded


def check_claims(jwt: str, ref: str, sha: str, now: int) -> None:
    """Check the requested identity before sending it to a registry for verification."""
    try:
        _header, encoded, signature = jwt.split(".")
        if not signature:
            raise ValueError
        payload = base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4))
        claims = json.loads(payload)
        if not isinstance(claims, dict):
            raise ValueError
    except (ValueError, UnicodeError):
        raise ReadinessError("GitHub returned a malformed identity token") from None
    expected = {
        "iss": ISSUER,
        "aud": "pypi",
        "repository": REPOSITORY,
        "ref": ref,
        "sha": sha,
        "environment": "pypi",
        "repository_owner_id": context.OWNER_ID,
        "repository_id": context.REPOSITORY_ID,
        "sub": context.SUBJECT,
        "workflow_ref": f"{REPOSITORY}/.github/workflows/release.yml@{ref}",
    }
    mismatches = [key for key, value in expected.items() if claims.get(key) != value]
    if mismatches:
        raise ReadinessError(
            "GitHub publishing identity mismatch: " + ", ".join(mismatches)
        )
    job_ref = claims.get("job_workflow_ref")
    if job_ref is not None and job_ref != expected["workflow_ref"]:
        raise ReadinessError("PyPI readiness refuses a reusable publishing workflow")
    expires, issued = claims.get("exp"), claims.get("iat")
    not_before = claims.get("nbf", issued)
    if (
        type(expires) is not int
        or type(issued) is not int
        or type(not_before) is not int
        or not (issued <= now < expires and not_before <= now)
    ):
        raise ReadinessError(
            "GitHub publishing identity is missing valid timing claims"
        )


def pypi_readiness(
    root: Path,
    environ: dict[str, str],
    transport=live_transport,
    now=None,
    *,
    release_tag=None,
    source_sha=None,
) -> str:
    """Mint and burn a credential; never upload, persist or return that credential."""
    ref, sha, version = context.source(root, environ, release_tag, source_sha)
    identity_url = environ.get("ACTIONS_ID_TOKEN_REQUEST_URL", "")
    request_token = environ.get("ACTIONS_ID_TOKEN_REQUEST_TOKEN", "")
    try:
        parsed = urllib.parse.urlsplit(identity_url)
        port = parsed.port
    except ValueError:
        raise ReadinessError("GitHub OIDC request endpoint is malformed") from None
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or not parsed.hostname.endswith(".actions.githubusercontent.com")
        or parsed.username is not None
        or parsed.password is not None
        or parsed.fragment
        or port not in (None, 443)
        or not request_token
    ):
        raise ReadinessError(
            "GitHub OIDC request credentials are missing or unexpected"
        )
    audience = request_json(
        f"{INDEX}/_/oidc/audience", "PyPI audience lookup", transport
    )
    if audience.get("audience") != "pypi":
        raise ReadinessError("PyPI returned an unexpected publishing audience")
    query = urllib.parse.parse_qsl(parsed.query, keep_blank_values=True)
    query = [(key, value) for key, value in query if key != "audience"]
    query.append(("audience", "pypi"))
    identity_url = urllib.parse.urlunsplit(
        parsed._replace(query=urllib.parse.urlencode(query))
    )
    identity = request_json(
        identity_url,
        "GitHub identity request",
        transport,
        headers={"Authorization": f"Bearer {request_token}"},
    )
    jwt = identity.get("value")
    if not isinstance(jwt, str):
        raise ReadinessError("GitHub returned no publishing identity token")
    current = int(time.time()) if now is None else now
    check_claims(jwt, ref, sha, current)
    minted = request_json(
        f"{AUTH}/_/oidc/mint-token",
        "PyPI identity exchange",
        transport,
        payload={"token": jwt},
    )
    token = minted.get("token")
    if not isinstance(token, str) or TOKEN.fullmatch(token) is None:
        raise ReadinessError("PyPI returned no valid temporary credential")
    try:
        expires = minted.get("expires")
        if (
            minted.get("success") is not True
            or type(expires) is not int
            or expires <= current
        ):
            raise ReadinessError(
                "PyPI returned an invalid temporary credential receipt"
            )
    finally:
        burn = urllib.request.Request(
            f"{AUTH}/_/oidc/burn-token",
            data=json.dumps({"token": token}).encode(),
            headers={"Content-Type": "application/json"},
        )
        status, _body = transport(burn)
        if status != 202:
            raise ReadinessError(
                f"PyPI temporary credential burn failed (HTTP {status})"
            )
    return f"PyPI OIDC readiness passed for joints {version}; credential burn accepted"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "command",
        choices=[
            "pypi-readiness",
            "release-context",
            "assert-context",
            "verify-artifacts",
        ],
        nargs="?",
    )
    parser.add_argument("--source-root", type=Path)
    parser.add_argument("--release-tag", default="")
    parser.add_argument("--source-sha", default="")
    parser.add_argument("--artifact-run", default="")
    parser.add_argument("--artifact-root", type=Path)
    parser.add_argument(
        "--native-target", choices=["linux-x86_64", "macos-arm64", "all"]
    )
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args(argv)
    try:
        if args.selftest:
            controls.selftest(sys.modules[__name__])
            artifact_controls.selftest(sys.modules[__name__])
            return 0
        if args.command is None:
            parser.error("choose pypi-readiness or --selftest")
        root = Path(__file__).resolve().parent.parent
        environ = dict(os.environ)
        if args.command == "pypi-readiness":
            print(
                pypi_readiness(
                    args.source_root or root,
                    environ,
                    release_tag=args.release_tag or None,
                    source_sha=args.source_sha or None,
                )
            )
        else:
            token = environ.get("GITHUB_TOKEN", "")

            def api(path):
                return request_json(
                    f"https://api.github.com/repos/{REPOSITORY}/{path}",
                    "release context lookup",
                    live_transport,
                    headers={"Authorization": f"Bearer {token}"} if token else {},
                )

            if args.command == "release-context":
                result = context.release_context(
                    root, environ, args.release_tag, args.artifact_run, api
                )
                context.emit(result, environ.get("GITHUB_OUTPUT"))
            elif args.command == "verify-artifacts":
                if args.artifact_root is None or args.source_root is None:
                    parser.error(
                        "artifact proof requires --artifact-root and --source-root"
                    )
                result = artifacts.verify(
                    args.artifact_root,
                    args.source_root,
                    environ,
                    args.release_tag,
                    args.source_sha,
                    args.artifact_run,
                    api,
                    token,
                    args.native_target,
                )
                print(json.dumps(result, sort_keys=True))
            else:
                result = context.assert_context(
                    root,
                    environ,
                    args.release_tag,
                    args.source_sha,
                    args.artifact_run,
                    api,
                )
                print(json.dumps(result, sort_keys=True))
        return 0
    except ReadinessError as error:
        print(f"publisher: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

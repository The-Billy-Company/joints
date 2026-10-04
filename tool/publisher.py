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
import tempfile
import time
import tomllib
import urllib.error
import urllib.parse
import urllib.request

REPOSITORY = "The-Billy-Company/joints"
ISSUER = "https://token.actions.githubusercontent.com"
INDEX = "https://pypi.org"
AUTH = "https://upload.pypi.org"
TAG = re.compile(r"refs/tags/v(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)\Z")
TOKEN = re.compile(r"pypi-[A-Za-z0-9_-]{16,}={0,2}\Z")


class ReadinessError(Exception):
    """A deliberately credential-free explanation of a failed readiness gate."""


def declared_context(root: Path, environ: dict[str, str]) -> tuple[str, str, str]:
    """Require the authorized repository, a version tag and all four mirrors."""
    if environ.get("GITHUB_REPOSITORY") != REPOSITORY:
        raise ReadinessError("publishing repository does not match joints")
    ref = environ.get("GITHUB_REF", "")
    tagged = TAG.fullmatch(ref)
    if tagged is None:
        raise ReadinessError("PyPI readiness requires a version tag")
    version = tagged.group(1)
    sha = environ.get("GITHUB_SHA", "")
    if re.fullmatch(r"[0-9a-f]{40}", sha) is None:
        raise ReadinessError("publishing commit is missing or malformed")
    try:
        python = tomllib.loads((root / "bindings/python/pyproject.toml").read_text())
        rust = tomllib.loads((root / "bindings/rust/Cargo.toml").read_text())
        zig = re.search(
            r'\.version\s*=\s*"([^"]+)"', (root / "build.zig.zon").read_text()
        )
        binding = re.search(
            r'^__version__\s*=\s*"([^"]+)"',
            (root / "bindings/python/joints/__init__.py").read_text(),
            re.MULTILINE,
        )
        names = (python["project"]["name"], rust["package"]["name"])
        mirrors = (
            python["project"]["version"],
            rust["package"]["version"],
            zig.group(1) if zig else None,
            binding.group(1) if binding else None,
        )
    except (OSError, KeyError, TypeError, tomllib.TOMLDecodeError):
        raise ReadinessError(
            "could not read the publishing package declarations"
        ) from None
    if names != ("joints", "joints"):
        raise ReadinessError("publishing package names do not match joints")
    if any(value != version for value in mirrors):
        raise ReadinessError("publishing tag and version mirrors disagree")
    return ref, sha, version


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
        "sub": f"repo:{REPOSITORY}:environment:pypi",
        "workflow_ref": f"{REPOSITORY}/.github/workflows/release.yml@{ref}",
    }
    if any(claims.get(key) != value for key, value in expected.items()):
        raise ReadinessError(
            "GitHub publishing identity claims do not match this release"
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
    root: Path, environ: dict[str, str], transport=live_transport, now=None
) -> str:
    """Mint and burn a credential; never upload, persist or return that credential."""
    ref, sha, version = declared_context(root, environ)
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


def selftest() -> int:
    """Exercise the real gate with fixed adverse remote responses, without credentials."""
    current = 2_000_000_000
    sha = "a" * 40
    ref = "refs/tags/v0.1.0"
    claims = {
        "iss": ISSUER,
        "aud": "pypi",
        "repository": REPOSITORY,
        "ref": ref,
        "sha": sha,
        "environment": "pypi",
        "sub": f"repo:{REPOSITORY}:environment:pypi",
        "workflow_ref": f"{REPOSITORY}/.github/workflows/release.yml@{ref}",
        "iat": current - 10,
        "nbf": current - 10,
        "exp": current + 300,
    }
    environ = {
        "GITHUB_REPOSITORY": REPOSITORY,
        "GITHUB_REF": ref,
        "GITHUB_SHA": sha,
        "ACTIONS_ID_TOKEN_REQUEST_URL": "https://run.actions.githubusercontent.com/id?api-version=2",
        "ACTIONS_ID_TOKEN_REQUEST_TOKEN": "offline-test-only",
    }

    def jwt_for(values):
        encoded = (
            base64.urlsafe_b64encode(json.dumps(values).encode()).decode().rstrip("=")
        )
        return "offline." + encoded + ".not-a-signature"

    class Exchange:
        def __init__(
            self, *, identity=None, audience=None, mint=None, fail=None, burn_status=202
        ):
            self.identity = jwt_for(claims) if identity is None else identity
            self.audience = {"audience": "pypi"} if audience is None else audience
            self.mint = (
                {
                    "success": True,
                    "token": "pypi-offline_test_credential",
                    "expires": current + 900,
                }
                if mint is None
                else mint
            )
            self.fail = fail
            self.burn_status = burn_status
            self.seen = []

        def __call__(self, request):
            path = urllib.parse.urlsplit(request.full_url).path
            self.seen.append(path)
            if path == self.fail:
                return 503, b"untrusted secret-containing body"
            if path == "/_/oidc/audience":
                value = self.audience
            elif path == "/id":
                value = {"value": self.identity}
            elif path == "/_/oidc/mint-token":
                value = self.mint
            elif path == "/_/oidc/burn-token":
                return self.burn_status, b""
            else:
                raise AssertionError(
                    "the readiness gate attempted an unexpected endpoint"
                )
            return 200, value if isinstance(value, bytes) else json.dumps(
                value
            ).encode()

    count = 0
    with tempfile.TemporaryDirectory(prefix="joints-publisher-controls-") as directory:
        root = Path(directory)
        (root / "bindings/python/joints").mkdir(parents=True)
        (root / "bindings/rust").mkdir(parents=True)
        (root / "build.zig.zon").write_text('.{ .version = "0.1.0" }')
        (root / "bindings/python/pyproject.toml").write_text(
            '[project]\nname = "joints"\nversion = "0.1.0"\n'
        )
        (root / "bindings/rust/Cargo.toml").write_text(
            '[package]\nname = "joints"\nversion = "0.1.0"\n'
        )
        (root / "bindings/python/joints/__init__.py").write_text(
            '__version__ = "0.1.0"\n'
        )
        good = Exchange()
        pypi_readiness(root, environ, good, current)
        if good.seen != [
            "/_/oidc/audience",
            "/id",
            "/_/oidc/mint-token",
            "/_/oidc/burn-token",
        ]:
            raise AssertionError("the positive control did not exchange and burn")
        count += 1

        def refuses(exchange, env=None, *, burns=False):
            nonlocal count
            try:
                pypi_readiness(root, environ if env is None else env, exchange, current)
            except ReadinessError as error:
                if "offline_test_credential" in str(
                    error
                ) or "secret-containing" in str(error):
                    raise AssertionError(
                        "a refusal exposed a credential or remote body"
                    ) from None
                if burns and "/_/oidc/burn-token" not in exchange.seen:
                    raise AssertionError(
                        "a refused temporary credential was not burned"
                    )
                count += 1
            else:
                raise AssertionError("an adverse publishing control was accepted")

        refuses(Exchange(), {**environ, "GITHUB_REF": "refs/heads/main"})
        refuses(Exchange(), {**environ, "GITHUB_REPOSITORY": "someone/else"})
        refuses(Exchange(), {**environ, "GITHUB_SHA": "missing"})
        refuses(Exchange(), {**environ, "ACTIONS_ID_TOKEN_REQUEST_TOKEN": ""})
        refuses(
            Exchange(),
            {**environ, "ACTIONS_ID_TOKEN_REQUEST_URL": "https://attacker.example/id"},
        )
        refuses(
            Exchange(),
            {
                **environ,
                "ACTIONS_ID_TOKEN_REQUEST_URL": "http://run.actions.githubusercontent.com/id",
            },
        )
        refuses(
            Exchange(),
            {
                **environ,
                "ACTIONS_ID_TOKEN_REQUEST_URL": "https://run.actions.githubusercontent.com:not-a-port/id",
            },
        )
        for path in ("/_/oidc/audience", "/id", "/_/oidc/mint-token"):
            refuses(Exchange(fail=path))
        refuses(Exchange(audience={"audience": "testpypi"}))
        refuses(Exchange(audience=b"not JSON"))
        refuses(Exchange(identity="malformed"))
        for key, value in (
            ("iss", "https://attacker.example"),
            ("aud", "testpypi"),
            ("repository", "someone/else"),
            ("ref", "refs/heads/main"),
            ("sha", "b" * 40),
            ("environment", "production"),
            ("workflow_ref", f"{REPOSITORY}/.github/workflows/another.yml@{ref}"),
            ("job_workflow_ref", f"someone/else/.github/workflows/reusable.yml@{ref}"),
            ("exp", current),
            ("nbf", current + 1),
            ("iat", True),
        ):
            refuses(Exchange(identity=jwt_for({**claims, key: value})))
        refuses(Exchange(mint=b"not JSON"))
        refuses(Exchange(mint={"success": True, "expires": current + 900}))
        refuses(
            Exchange(
                mint={"success": True, "token": "wrong-token", "expires": current + 900}
            )
        )
        refuses(
            Exchange(
                mint={
                    "success": False,
                    "token": "pypi-offline_test_credential",
                    "expires": current + 900,
                }
            ),
            burns=True,
        )
        refuses(
            Exchange(
                mint={
                    "success": True,
                    "token": "pypi-offline_test_credential",
                    "expires": current,
                }
            ),
            burns=True,
        )
        refuses(Exchange(burn_status=503), burns=True)
        (root / "bindings/rust/Cargo.toml").write_text(
            '[package]\nname = "joints"\nversion = "0.0.0"\n'
        )
        refuses(Exchange())
        (root / "bindings/rust/Cargo.toml").write_text(
            '[package]\nname = "someone-else"\nversion = "0.1.0"\n'
        )
        refuses(Exchange())
    print(f"publisher: {count} offline identity/exchange/refusal controls passed")
    return 0


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("command", choices=["pypi-readiness"], nargs="?")
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args(argv)
    try:
        if args.selftest:
            return selftest()
        if args.command is None:
            parser.error("choose pypi-readiness or --selftest")
        root = Path(__file__).resolve().parent.parent
        print(pypi_readiness(root, dict(os.environ)))
        return 0
    except ReadinessError as error:
        print(f"publisher: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

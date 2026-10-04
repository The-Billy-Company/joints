"""Offline controls for publishing identities and immutable release recovery."""

import base64
import json
from pathlib import Path
import subprocess
import tempfile
import urllib.parse


def context_controls(core):
    context = core.context
    original, execution = "c" * 40, "b" * 40
    tag, run_id = "v0.1.0", "777777"
    environ = {
        "GITHUB_REPOSITORY": core.REPOSITORY,
        "GITHUB_REF": "refs/heads/main",
        "GITHUB_SHA": execution,
        "GITHUB_RUN_ID": "999999999",
        "GITHUB_EVENT_NAME": "workflow_dispatch",
    }
    run = {
        "id": int(run_id),
        "name": "release",
        "path": ".github/workflows/release.yml",
        "event": "push",
        "status": "completed",
        "conclusion": "failure",
        "head_branch": tag,
        "head_sha": original,
        "repository": {"id": 1327241679},
        "head_repository": {"id": 1327241679},
    }
    names = [
        "preflight",
        "native (linux-x86_64)",
        "native (macos-arm64)",
        "packages",
        "installed packages (linux-x86_64)",
        "installed packages (macos-arm64)",
        "registry-probes",
    ]
    jobs = {
        "total_count": len(names),
        "jobs": [
            {"name": name, "status": "completed", "conclusion": "success"}
            for name in names
        ],
    }
    artifacts = {
        "total_count": 3,
        "artifacts": [
            {
                "id": index + 1,
                "name": name,
                "expired": False,
                "digest": "sha256:" + "a" * 64,
                "workflow_run": {
                    "id": int(run_id),
                    "head_sha": original,
                    "head_branch": tag,
                    "repository_id": 1327241679,
                    "head_repository_id": 1327241679,
                },
            }
            for index, name in enumerate(
                ["packages", "native-linux-x86_64", "native-macos-arm64"]
            )
        ],
    }
    endpoints = {
        "git/ref/tags/v0.1.0": {"object": {"type": "tag", "sha": "d" * 40}},
        "git/tags/" + "d" * 40: {
            "tag": tag,
            "verification": {"verified": True},
            "object": {"type": "commit", "sha": original},
        },
        "actions/runs/777777": run,
        "actions/runs/777777/jobs?per_page=100&filter=latest": jobs,
        "actions/runs/777777/artifacts?per_page=100": artifacts,
    }
    count = 0

    def api(records):
        def read(path):
            if path not in records:
                raise AssertionError("context requested an unexpected endpoint")
            return records[path]

        return read

    def refusal(
        records=None, env=None, *, selected_tag=tag, selected_run=run_id, asserted=None
    ):
        nonlocal count
        try:
            if asserted is None:
                context.release_context(
                    Path("."),
                    environ if env is None else env,
                    selected_tag,
                    selected_run,
                    api(endpoints if records is None else records),
                )
            else:
                context.assert_context(
                    Path("."),
                    environ,
                    tag,
                    asserted,
                    run_id,
                    api(endpoints if records is None else records),
                )
        except core.ReadinessError:
            count += 1
        else:
            raise AssertionError("an adverse release recovery context was accepted")

    resolved = context.release_context(Path("."), environ, tag, run_id, api(endpoints))
    if resolved != {
        "tag": tag,
        "version": "0.1.0",
        "source_sha": original,
        "artifact_run": run_id,
        "publish": "true",
    }:
        raise AssertionError(
            "recovery rebound original artifacts to the automation commit"
        )
    context.assert_context(Path("."), environ, tag, original, run_id, api(endpoints))
    count += 2
    refusal(selected_tag="", selected_run=run_id)
    refusal(selected_tag=tag, selected_run="")
    refusal(selected_tag="v0.1.0\nforged-output=true")
    refusal(selected_run=environ["GITHUB_RUN_ID"])
    refusal(env={**environ, "GITHUB_REF": "refs/heads/another"})
    refusal(env={**environ, "GITHUB_EVENT_NAME": "push"})
    for key, value in [
        ("path", ".github/workflows/another.yml"),
        ("event", "workflow_dispatch"),
        ("head_branch", "v0.2.0"),
        ("head_sha", execution),
        ("status", "in_progress"),
        ("conclusion", "cancelled"),
        ("repository", {"id": 999}),
        ("head_repository", {"id": 999}),
    ]:
        altered = json.loads(json.dumps(endpoints))
        altered["actions/runs/777777"][key] = value
        refusal(altered)
    for name in names:
        altered = json.loads(json.dumps(endpoints))
        altered["actions/runs/777777/jobs?per_page=100&filter=latest"]["jobs"] = [
            job for job in jobs["jobs"] if job["name"] != name
        ]
        altered["actions/runs/777777/jobs?per_page=100&filter=latest"][
            "total_count"
        ] -= 1
        refusal(altered)
    altered = json.loads(json.dumps(endpoints))
    altered["actions/runs/777777/jobs?per_page=100&filter=latest"]["jobs"][0][
        "conclusion"
    ] = "failure"
    refusal(altered)
    for field, value in [
        ("expired", True),
        ("digest", "not-a-digest"),
        ("name", "native-other"),
    ]:
        altered = json.loads(json.dumps(endpoints))
        altered["actions/runs/777777/artifacts?per_page=100"]["artifacts"][0][field] = (
            value
        )
        refusal(altered)
    altered = json.loads(json.dumps(endpoints))
    altered["actions/runs/777777/artifacts?per_page=100"]["artifacts"][0][
        "workflow_run"
    ]["head_sha"] = execution
    refusal(altered)
    altered = json.loads(json.dumps(endpoints))
    altered["actions/runs/777777/artifacts?per_page=100"]["artifacts"][0]["name"] = (
        "native-linux-x86_64"
    )
    refusal(altered)
    altered = json.loads(json.dumps(endpoints))
    altered["git/tags/" + "d" * 40]["verification"]["verified"] = False
    refusal(altered)
    altered = json.loads(json.dumps(endpoints))
    altered["git/ref/tags/v0.1.0"]["object"]["type"] = "commit"
    refusal(altered)
    refusal(asserted=execution)
    return count


def selftest(core) -> int:
    """Exercise the real gate with fixed adverse remote responses, without credentials."""
    ReadinessError = core.ReadinessError
    pypi_readiness = core.pypi_readiness
    REPOSITORY, ISSUER = core.REPOSITORY, core.ISSUER
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
        "repository_owner_id": core.context.OWNER_ID,
        "repository_id": core.context.REPOSITORY_ID,
        "sub": core.context.SUBJECT,
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

        def git(*args):
            return subprocess.check_output(
                ["git", *args], cwd=root, stderr=subprocess.PIPE, text=True
            ).strip()

        git("init", "-q")
        git("add", ".")
        git(
            "-c",
            "user.name=Publisher controls",
            "-c",
            "user.email=publisher@example.invalid",
            "-c",
            "commit.gpgsign=false",
            "commit",
            "-qm",
            "original source",
        )
        original_sha = git("rev-parse", "HEAD")
        environ["GITHUB_SHA"] = original_sha
        claims["sha"] = original_sha
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
            ("repository_owner_id", "999"),
            ("repository_id", "999"),
            ("sub", f"repo:{REPOSITORY}:environment:pypi"),
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
        dispatch = {
            **environ,
            "GITHUB_REF": "refs/heads/main",
            "GITHUB_SHA": "b" * 40,
            "GITHUB_EVENT_NAME": "workflow_dispatch",
        }
        recovery_claims = {
            **claims,
            "ref": dispatch["GITHUB_REF"],
            "sha": dispatch["GITHUB_SHA"],
            "workflow_ref": f"{REPOSITORY}/.github/workflows/release.yml@refs/heads/main",
        }
        pypi_readiness(
            root,
            dispatch,
            Exchange(identity=jwt_for(recovery_claims)),
            current,
            release_tag="v0.1.0",
            source_sha=original_sha,
        )
        count += 1
        try:
            pypi_readiness(
                root,
                dispatch,
                Exchange(identity=jwt_for(recovery_claims)),
                current,
                release_tag="v0.1.0",
                source_sha="c" * 40,
            )
        except ReadinessError:
            count += 1
        else:
            raise AssertionError("recovery accepted a different source checkout")
        (root / "README.md").write_text("untracked drift")
        refuses(Exchange())
        (root / "bindings/rust/Cargo.toml").write_text(
            '[package]\nname = "joints"\nversion = "0.0.0"\n'
        )
        refuses(Exchange())
        (root / "bindings/rust/Cargo.toml").write_text(
            '[package]\nname = "someone-else"\nversion = "0.1.0"\n'
        )
        refuses(Exchange())
    count += context_controls(core)
    print(
        f"publisher: {count} offline identity/source/recovery/refusal controls passed"
    )
    return 0

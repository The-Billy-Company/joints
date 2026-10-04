"""Bind original release bytes to a signed tag and a proven artifact run."""

import json
import re
import subprocess
import tomllib
import urllib.parse

REPOSITORY = "The-Billy-Company/joints"
OWNER_ID = "220528595"
REPOSITORY_ID = "1327241679"
SUBJECT = f"repo:The-Billy-Company@{OWNER_ID}/joints@{REPOSITORY_ID}:environment:pypi"
TAG = re.compile(r"v(\d+\.\d+\.\d+)\Z")
SHA = re.compile(r"[0-9a-f]{40}\Z")
REQUIRED_JOBS = {
    "preflight",
    "native (linux-x86_64)",
    "native (macos-arm64)",
    "packages",
    "installed packages (linux-x86_64)",
    "installed packages (macos-arm64)",
    "registry-probes",
}
ARTIFACTS = {"packages", "native-linux-x86_64", "native-macos-arm64"}


class ContextError(Exception):
    """A context rejection whose message contains no credential or remote body."""


def require(value, message):
    if not value:
        raise ContextError(message)


def execution(environ):
    require(
        environ.get("GITHUB_REPOSITORY") == REPOSITORY,
        "publishing repository does not match joints",
    )
    ref, sha = environ.get("GITHUB_REF", ""), environ.get("GITHUB_SHA", "")
    require(SHA.fullmatch(sha), "publishing commit is missing or malformed")
    require(
        ref == "refs/heads/main"
        or (ref.startswith("refs/tags/") and TAG.fullmatch(ref[10:])),
        "unexpected publishing workflow ref",
    )
    return ref, sha


def package_version(root):
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
        versions = (
            python["project"]["version"],
            rust["package"]["version"],
            zig.group(1) if zig else None,
            binding.group(1) if binding else None,
        )
    except (OSError, KeyError, TypeError, tomllib.TOMLDecodeError):
        raise ContextError(
            "could not read the publishing package declarations"
        ) from None
    require(
        names == ("joints", "joints"), "publishing package names do not match joints"
    )
    require(
        all(version == versions[0] for version in versions)
        and isinstance(versions[0], str),
        "publishing version mirrors disagree",
    )
    return versions[0]


def git(root, *args):
    try:
        return subprocess.check_output(
            ["git", *args], cwd=root, stderr=subprocess.PIPE, text=True
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        raise ContextError("could not verify the release source checkout") from None


def source(root, environ, release_tag=None, source_sha=None):
    ref, execution_sha = execution(environ)
    require(
        bool(release_tag) == bool(source_sha),
        "release source context must include both tag and commit",
    )
    tag = release_tag or ref.removeprefix("refs/tags/")
    matched = TAG.fullmatch(tag)
    require(matched, "PyPI readiness requires a version tag")
    sha = source_sha or execution_sha
    require(SHA.fullmatch(sha), "release source commit is malformed")
    if ref != "refs/heads/main":
        require(
            ref == "refs/tags/" + tag and execution_sha == sha,
            "tag execution and release source disagree",
        )
    else:
        require(
            release_tag and environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch",
            "main readiness requires explicit dispatched release source",
        )
    require(
        package_version(root) == matched.group(1),
        "publishing tag and version mirrors disagree",
    )
    require(
        git(root, "rev-parse", "HEAD") == sha,
        "release source checkout is not the resolved tag commit",
    )
    require(
        not git(root, "status", "--porcelain", "--untracked-files=normal"),
        "release source checkout is dirty",
    )
    return ref, execution_sha, matched.group(1)


def resolve_tag(tag, api):
    require(TAG.fullmatch(tag), "release tag must be vX.Y.Z")
    record = api("git/ref/tags/" + urllib.parse.quote(tag, safe=""))
    object = record.get("object", {})
    require(
        object.get("type") == "tag" and SHA.fullmatch(object.get("sha", "")),
        "release recovery requires an annotated tag",
    )
    signed = api("git/tags/" + object["sha"])
    require(
        signed.get("tag") == tag
        and signed.get("verification", {}).get("verified") is True,
        "release tag signature was not verified",
    )
    commit = signed.get("object", {})
    require(
        commit.get("type") == "commit" and SHA.fullmatch(commit.get("sha", "")),
        "release tag does not resolve directly to a commit",
    )
    return commit["sha"]


def proven_run(run_id, tag, sha, api):
    require(
        re.fullmatch(r"[1-9][0-9]*", run_id), "artifact run must be a positive run ID"
    )
    run = api("actions/runs/" + run_id)
    expected = {
        "id": int(run_id),
        "name": "release",
        "path": ".github/workflows/release.yml",
        "event": "push",
        "status": "completed",
        "head_branch": tag,
        "head_sha": sha,
    }
    require(
        all(run.get(key) == value for key, value in expected.items()),
        "artifact run does not match the original tag release",
    )
    require(
        run.get("conclusion") in ("failure", "success"),
        "artifact run did not complete normally",
    )
    require(
        str(run.get("repository", {}).get("id")) == REPOSITORY_ID
        and str(run.get("head_repository", {}).get("id")) == REPOSITORY_ID,
        "artifact run repository identity mismatch",
    )
    jobs = api(f"actions/runs/{run_id}/jobs?per_page=100&filter=latest")
    rows = jobs.get("jobs", [])
    require(
        jobs.get("total_count") == len(rows) and len(rows) <= 100,
        "artifact run job inventory is incomplete",
    )
    named = {row.get("name"): row for row in rows}
    require(len(named) == len(rows), "artifact run has ambiguous job names")
    require(
        all(
            name in named
            and named[name].get("status") == "completed"
            and named[name].get("conclusion") == "success"
            for name in REQUIRED_JOBS
        ),
        "original release build and installed proof did not all pass",
    )
    return artifact_records(run_id, tag, sha, api)


def artifact_records(run_id, tag, sha, api):
    artifacts = api(f"actions/runs/{run_id}/artifacts?per_page=100")
    rows = artifacts.get("artifacts", [])
    require(
        artifacts.get("total_count") == len(rows) == len(ARTIFACTS)
        and {row.get("name") for row in rows} == ARTIFACTS,
        "original artifact inventory is incomplete or unexpected",
    )
    for artifact in rows:
        require(
            artifact.get("expired") is False
            and type(artifact.get("id")) is int
            and artifact["id"] > 0
            and re.fullmatch(r"sha256:[0-9a-f]{64}", artifact.get("digest", "")),
            "original artifact expired or has no verified digest",
        )
        provenance = artifact.get("workflow_run", {})
        require(
            provenance.get("id") == int(run_id)
            and provenance.get("head_sha") == sha
            and provenance.get("head_branch") == tag
            and str(provenance.get("repository_id")) == REPOSITORY_ID
            and str(provenance.get("head_repository_id")) == REPOSITORY_ID,
            "original artifact source identity mismatch",
        )
    require(
        len({row["id"] for row in rows}) == len(rows),
        "original artifact IDs are ambiguous",
    )
    return rows


def release_context(root, environ, release_tag, artifact_run, api):
    ref, execution_sha = execution(environ)
    current_run = environ.get("GITHUB_RUN_ID", "")
    require(
        re.fullmatch(r"[1-9][0-9]*", current_run), "current workflow run ID is missing"
    )
    require(
        bool(release_tag) == bool(artifact_run),
        "recovery requires both release_tag and artifact_run",
    )
    if release_tag:
        require(
            ref == "refs/heads/main"
            and environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch",
            "release recovery must dispatch the main workflow",
        )
        require(
            artifact_run != current_run, "recovery cannot use its own incomplete run"
        )
        sha = resolve_tag(release_tag, api)
        proven_run(artifact_run, release_tag, sha, api)
        return {
            "tag": release_tag,
            "version": TAG.fullmatch(release_tag).group(1),
            "source_sha": sha,
            "artifact_run": artifact_run,
            "publish": "true",
        }
    version = package_version(root)
    tag = "v" + version
    if ref.startswith("refs/tags/"):
        require(
            ref == "refs/tags/" + tag, "publishing tag and version mirrors disagree"
        )
        require(
            resolve_tag(tag, api) == execution_sha,
            "publishing tag and execution commit disagree",
        )
        publish = "true"
    else:
        publish = "false"
    return {
        "tag": tag,
        "version": version,
        "source_sha": execution_sha,
        "artifact_run": current_run,
        "publish": publish,
    }


def assert_context(root, environ, release_tag, source_sha, artifact_run, api):
    ref, execution_sha = execution(environ)
    require(SHA.fullmatch(source_sha), "expected release source commit is malformed")
    require(
        resolve_tag(release_tag, api) == source_sha,
        "release tag moved from its verified source",
    )
    if artifact_run == environ.get("GITHUB_RUN_ID"):
        require(
            ref == "refs/tags/" + release_tag and execution_sha == source_sha,
            "ordinary release context does not match tag execution",
        )
    else:
        resolved = release_context(root, environ, release_tag, artifact_run, api)
        require(resolved["source_sha"] == source_sha, "recovery source commit changed")
    return {
        "tag": release_tag,
        "source_sha": source_sha,
        "artifact_run": artifact_run,
        "context": "verified",
    }


def emit(values, output):
    if output:
        with open(output, "a") as handle:
            for key, value in values.items():
                require(
                    "\n" not in value and "\r" not in value,
                    "invalid workflow context output",
                )
                print(f"{key}={value}", file=handle)
    print(json.dumps(values, sort_keys=True))

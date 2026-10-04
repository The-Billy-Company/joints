"""Adverse controls for authenticated artifact bytes and source closure."""

import io
from pathlib import Path
import stat
import subprocess
import tarfile
import tempfile
import urllib.parse
import zipfile


def zip_bytes(files):
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w") as archive:
        for name, data in files.items():
            archive.writestr(name, data)
    return output.getvalue()


def native_bytes(artifact, ledger, target):
    output = io.BytesIO()
    manifest = {
        "schema": 1,
        "version": "0.1.0",
        "target": target,
        "source": ledger,
    }
    data = artifact.encoded(manifest)
    with tarfile.open(fileobj=output, mode="w:gz") as archive:
        row = tarfile.TarInfo(f"joints-0.1.0-{target}/manifest.json")
        row.size = len(data)
        archive.addfile(row, io.BytesIO(data))
    return output.getvalue()


def selftest(core):
    artifact, context = core.artifacts, core.context
    count = 0

    def refuses(action):
        nonlocal count
        try:
            action()
        except context.ContextError as error:
            if "offline_secret" in str(error):
                raise AssertionError(
                    "artifact refusal leaked authorization or signed URL"
                )
            count += 1
        else:
            raise AssertionError("an adverse artifact integrity control was accepted")

    for location in (
        "http://storage.blob.core.windows.net/blob",
        "https://attacker.example/blob?offline_secret=1",
        "https://blob.core.windows.net/blob",
        "https://storage.blob.core.windows.net:444/blob",
        "https://user:offline_secret@storage.blob.core.windows.net/blob",
        "https://storage.blob.core.windows.net/blob#offline_secret",
    ):
        refuses(lambda value=location: artifact.storage_location(value))
    record = {"id": 1, "digest": "sha256:" + artifact.checksum(b"ZIP")}
    refuses(
        lambda: artifact.fetch(record, "", lambda url, headers: (200, b"ZIP", None))
    )
    for status in (401, 404, 500):
        refuses(
            lambda value=status: artifact.fetch(
                record, "offline_secret", lambda url, headers: (value, b"", None)
            )
        )
    refuses(
        lambda: artifact.fetch(
            record,
            "offline_secret",
            lambda url, headers: (
                302,
                b"",
                "https://attacker.example/?offline_secret=1",
            ),
        )
    )
    refuses(
        lambda: artifact.fetch(
            record, "offline_secret", lambda url, headers: (200, b"changed", None)
        )
    )
    for name in (
        "../escape",
        "/absolute",
        "python/../escape",
        "python\\escape",
        "./wheel",
    ):
        refuses(
            lambda value=name: artifact.members(zip_bytes({value: b"x"}), {"wheel"})
        )
    refuses(lambda: artifact.members(b"not a ZIP", {"wheel"}))
    refuses(lambda: artifact.members(zip_bytes({"extra": b"x"}), {"wheel"}))
    duplicate = io.BytesIO()
    with zipfile.ZipFile(duplicate, "w") as archive:
        archive.writestr("wheel", b"x")
        # Suppress zipfile's expected duplicate warning; refusal itself is checked.
        import warnings

        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            archive.writestr("wheel", b"y")
    refuses(lambda: artifact.members(duplicate.getvalue(), {"wheel"}))
    link = io.BytesIO()
    with zipfile.ZipFile(link, "w") as archive:
        row = zipfile.ZipInfo("wheel")
        row.external_attr = (stat.S_IFLNK | 0o777) << 16
        archive.writestr(row, b"target")
    refuses(lambda: artifact.members(link.getvalue(), {"wheel"}))
    with tempfile.TemporaryDirectory(prefix="joints-artifact-controls-") as temporary:
        root = Path(temporary)
        source, output = root / "source", root / "dist"
        source.mkdir()
        declarations = {
            "build.zig.zon": '.{ .version = "0.1.0" }\n',
            "bindings/python/pyproject.toml": '[project]\nname = "joints"\nversion = "0.1.0"\n',
            "bindings/rust/Cargo.toml": '[package]\nname = "joints"\nversion = "0.1.0"\n',
            "bindings/python/joints/__init__.py": '__version__ = "0.1.0"\n',
        }
        for name, data in declarations.items():
            path = source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(data)

        def git(*args):
            return subprocess.check_output(
                ["git", *args], cwd=source, stderr=subprocess.PIPE, text=True
            ).strip()

        git("init", "-q")
        git("add", ".")
        git(
            "-c",
            "commit.gpgsign=false",
            "-c",
            "user.name=Artifact controls",
            "-c",
            "user.email=controls@example.invalid",
            "commit",
            "-qm",
            "source",
        )
        sha = git("rev-parse", "HEAD")
        ledger = artifact.source_ledger(source, sha)
        portable = {
            "python/joints-0.1.0-py3-none-any.whl": b"wheel",
            "python/joints-0.1.0.tar.gz": b"sdist",
            "rust/joints-0.1.0.crate": b"crate",
        }
        receipt = {
            "schema": 1,
            "version": "0.1.0",
            "source": ledger,
            "files": {name: artifact.checksum(data) for name, data in portable.items()},
        }
        payloads = {
            "packages": {**portable, "packages.json": artifact.encoded(receipt)}
        }
        for target in artifact.TARGETS:
            payloads["native-" + target] = {
                f"joints-0.1.0-{target}.tar.gz": native_bytes(artifact, ledger, target)
            }
        archives = {
            index: zip_bytes(payloads[name])
            for index, name in enumerate(sorted(payloads), 1)
        }
        rows = [
            {
                "id": index,
                "name": name,
                "expired": False,
                "digest": "sha256:" + artifact.checksum(archives[index]),
                "workflow_run": {
                    "id": 777777,
                    "head_sha": sha,
                    "head_branch": "v0.1.0",
                    "repository_id": 1327241679,
                    "head_repository_id": 1327241679,
                },
            }
            for index, name in enumerate(sorted(payloads), 1)
        ]
        records = {
            "git/ref/tags/v0.1.0": {"object": {"type": "tag", "sha": "d" * 40}},
            "git/tags/" + "d" * 40: {
                "tag": "v0.1.0",
                "verification": {"verified": True},
                "object": {"type": "commit", "sha": sha},
            },
            "actions/runs/777777": {
                "id": 777777,
                "name": "release",
                "path": ".github/workflows/release.yml",
                "event": "push",
                "status": "completed",
                "conclusion": "failure",
                "head_branch": "v0.1.0",
                "head_sha": sha,
                "repository": {"id": 1327241679},
                "head_repository": {"id": 1327241679},
            },
            "actions/runs/777777/jobs?per_page=100&filter=latest": {
                "total_count": len(context.REQUIRED_JOBS),
                "jobs": [
                    {"name": name, "status": "completed", "conclusion": "success"}
                    for name in context.REQUIRED_JOBS
                ],
            },
            "actions/runs/777777/artifacts?per_page=100": {
                "total_count": 3,
                "artifacts": rows,
            },
        }
        environ = {
            "GITHUB_REPOSITORY": context.REPOSITORY,
            "GITHUB_REF": "refs/heads/main",
            "GITHUB_SHA": "b" * 40,
            "GITHUB_EVENT_NAME": "workflow_dispatch",
            "GITHUB_RUN_ID": "999999999",
        }
        for name, data in payloads["packages"].items():
            path = output / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        calls = []

        def download(url, headers):
            calls.append((url, headers))
            parsed = urllib.parse.urlsplit(url)
            if parsed.hostname == "api.github.com":
                if headers.get("Authorization") != "Bearer offline_secret":
                    raise AssertionError("GitHub artifact lookup was not authenticated")
                index = int(parsed.path.split("/")[-2])
                return (
                    302,
                    b"",
                    f"https://storage.blob.core.windows.net/{index}?offline_secret=1",
                )
            if headers:
                raise AssertionError("GitHub authorization reached signed storage")
            return 200, archives[int(parsed.path[1:])], None

        def verify():
            return artifact.verify(
                output,
                source,
                environ,
                "v0.1.0",
                sha,
                "777777",
                records.__getitem__,
                "offline_secret",
                download=download,
            )

        verify()
        if len(calls) != 6:
            raise AssertionError("artifact proof did not authenticate all three ZIPs")
        count += 1
        wheel = output / "python/joints-0.1.0-py3-none-any.whl"
        wheel.write_bytes(b"changed")
        refuses(verify)
        wheel.write_bytes(b"wheel")
        (output / "extra").write_bytes(b"unexpected")
        refuses(verify)
        (output / "extra").unlink()
        wheel.unlink()
        wheel.symlink_to(output / "rust/joints-0.1.0.crate")
        refuses(verify)
        wheel.unlink()
        wheel.write_bytes(b"wheel")
        saved = rows[0]["digest"]
        rows[0]["digest"] = "sha256:" + "0" * 64
        refuses(verify)
        rows[0]["digest"] = saved
        path = source / "build.zig.zon"
        path.write_text(declarations["build.zig.zon"] + "// drift\n")
        refuses(verify)
        path.write_text(declarations["build.zig.zon"])
        changed = {**ledger, "commit": "a" * 40}
        bad_receipt = {**receipt, "source": changed}
        index = next(row["id"] for row in rows if row["name"] == "packages")
        original = archives[index]
        archives[index] = zip_bytes(
            {**portable, "packages.json": artifact.encoded(bad_receipt)}
        )
        saved = rows[index - 1]["digest"]
        rows[index - 1]["digest"] = "sha256:" + artifact.checksum(archives[index])
        refuses(verify)
        archives[index], rows[index - 1]["digest"] = original, saved
        for target in artifact.TARGETS:
            for name, data in payloads["native-" + target].items():
                path = output / "native" / name
                path.parent.mkdir(exist_ok=True)
                path.write_bytes(data)
        artifact.verify(
            output,
            source,
            environ,
            "v0.1.0",
            sha,
            "777777",
            records.__getitem__,
            "offline_secret",
            "all",
            download,
        )
        count += 1
        all_files = {
            Path(name).name: data for name, data in payloads["packages"].items()
        }
        for target in artifact.TARGETS:
            all_files.update(payloads["native-" + target])
        sums = "".join(
            f"{artifact.checksum(data)}  {name}\n"
            for name, data in sorted(all_files.items())
        )
        (output / "SHA256SUMS").write_text(sums)
        artifact.compare_local(output, payloads, "all")
        count += 1
        (output / "SHA256SUMS").write_text(sums + "drift\n")
        refuses(lambda: artifact.compare_local(output, payloads, "all"))
    print(
        f"publisher: {count} offline ZIP/redirect/source/byte-integrity controls passed"
    )
    return 0

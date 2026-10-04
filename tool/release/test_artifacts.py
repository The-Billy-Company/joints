"""Adverse controls for archive boundaries and immutable registry identities."""

import hashlib
import io
import json
import tarfile
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import patch

import artifacts


class ArtifactGuards(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def archive(self, entries):
        path = self.root / "archive.tar.gz"
        with tarfile.open(path, "w:gz") as archive:
            for name, kind in entries:
                member = tarfile.TarInfo(name)
                if kind == "link":
                    member.type = tarfile.SYMTYPE
                    member.linkname = "/tmp/escape"
                    archive.addfile(member)
                else:
                    member.size = 1
                    archive.addfile(member, io.BytesIO(b"x"))
        return path

    def test_archive_parent_escape_refused(self):
        path = self.archive([("joints-0.1.0/../escape", "file")])
        with self.assertRaisesRegex(RuntimeError, "path escape"):
            artifacts.unpack(path, self.root / "extract", "joints-0.1.0")
        self.assertFalse((self.root / "extract/escape").exists())

    def test_archive_links_refused(self):
        path = self.archive([("joints-0.1.0/library", "link")])
        with self.assertRaisesRegex(RuntimeError, "link or special"):
            artifacts.unpack(path, self.root / "extract", "joints-0.1.0")

    def test_archive_duplicates_refused(self):
        path = self.archive([("joints-0.1.0/a", "file")] * 2)
        with self.assertRaisesRegex(RuntimeError, "duplicate"):
            artifacts.unpack(path, self.root / "extract", "joints-0.1.0")

    def test_archive_wrong_platform_root_refused(self):
        path = self.archive([("joints-0.1.0-other/lib", "file")])
        with self.assertRaisesRegex(RuntimeError, "unexpected archive root"):
            artifacts.unpack(path, self.root / "extract", "joints-0.1.0-this")

    def test_native_cross_build_claim_refused_before_build(self):
        class Args:
            target = "linux-x86_64"

        with (
            patch.object(artifacts, "host", return_value="macos-arm64"),
            self.assertRaisesRegex(RuntimeError, "named host"),
        ):
            artifacts.native(Args())

    def test_registry_404_is_absent_but_service_failure_is_error(self):
        url = "https://pypi.org/pypi/joints/0.1.0/json"
        for code, absent in ((404, True), (503, False), (429, False)):
            error = urllib.error.HTTPError(url, code, "control", {}, None)
            with patch.object(
                artifacts._registry.urllib.request, "urlopen", side_effect=error
            ):
                if absent:
                    self.assertIsNone(artifacts.fetch(url, absent=True))
                else:
                    with self.assertRaisesRegex(RuntimeError, f"HTTP {code}"):
                        artifacts.fetch(url, absent=True)
        with (
            patch.object(
                artifacts._registry.urllib.request,
                "urlopen",
                side_effect=urllib.error.URLError("control timeout"),
            ),
            self.assertRaisesRegex(RuntimeError, "did not answer"),
        ):
            artifacts.fetch(url, absent=True)

    def pypi(self, data=b"wheel", checksum=None):
        wheel = "joints-0.1.0-py3-none-any.whl"
        sdist = "joints-0.1.0.tar.gz"
        checksum = checksum or hashlib.sha256(data).hexdigest()
        identity = {
            "files": {
                f"python/{wheel}": hashlib.sha256(b"wheel").hexdigest(),
                f"python/{sdist}": hashlib.sha256(b"sdist").hexdigest(),
            }
        }
        index = json.dumps(
            {
                "info": {"version": "0.1.0"},
                "urls": [
                    {
                        "filename": wheel,
                        "digests": {"sha256": checksum},
                        "url": "wheel",
                    },
                    {
                        "filename": sdist,
                        "digests": {"sha256": identity["files"][f"python/{sdist}"]},
                        "url": "sdist",
                    },
                ],
            }
        ).encode()
        return identity, index

    def test_same_version_different_index_checksum_refuses_before_download(self):
        identity, index = self.pypi(checksum="0" * 64)
        with (
            patch.object(artifacts, "identities", return_value=identity),
            patch.object(artifacts, "fetch", return_value=index) as fetch,
        ):
            with self.assertRaisesRegex(RuntimeError, "index checksum mismatch"):
                artifacts.resolve_registry(self.root, "0.1.0")
            self.assertEqual(fetch.call_count, 1)

    def test_index_checksum_does_not_substitute_for_downloaded_bytes(self):
        identity, index = self.pypi()
        with (
            patch.object(artifacts, "identities", return_value=identity),
            patch.object(artifacts, "fetch", side_effect=[index, b"forged bytes"]),
            self.assertRaisesRegex(RuntimeError, "bytes mismatch"),
        ):
            artifacts.resolve_registry(self.root, "0.1.0")

    def test_identical_present_python_and_absent_crate_are_distinct(self):
        identity, index = self.pypi()
        with (
            patch.object(artifacts, "identities", return_value=identity),
            patch.object(
                artifacts, "fetch", side_effect=[index, b"wheel", b"sdist", None]
            ),
        ):
            self.assertEqual(
                artifacts.resolve_registry(self.root, "0.1.0"),
                {"pypi": "present", "crates": "absent"},
            )

    def test_crate_checksum_collision_refuses_before_download(self):
        identity = {"files": {"rust/joints-0.1.0.crate": "a" * 64}}
        index = json.dumps(
            {
                "version": {
                    "num": "0.1.0",
                    "crate": "joints",
                    "checksum": "b" * 64,
                    "yanked": False,
                }
            }
        ).encode()
        with (
            patch.object(artifacts, "identities", return_value=identity),
            patch.object(artifacts, "fetch", side_effect=[None, index]) as fetch,
            self.assertRaisesRegex(RuntimeError, "crates index checksum mismatch"),
        ):
            artifacts.resolve_registry(self.root, "0.1.0")
        self.assertEqual(fetch.call_count, 2)

    def test_crate_download_must_match_index(self):
        identity = {"files": {"rust/joints-0.1.0.crate": "a" * 64}}
        index = json.dumps(
            {
                "version": {
                    "num": "0.1.0",
                    "crate": "joints",
                    "checksum": "a" * 64,
                    "yanked": False,
                }
            }
        ).encode()
        with (
            patch.object(artifacts, "identities", return_value=identity),
            patch.object(
                artifacts, "fetch", side_effect=[None, index, b"forged crate"]
            ),
            self.assertRaisesRegex(RuntimeError, "crate bytes mismatch"),
        ):
            artifacts.resolve_registry(self.root, "0.1.0")

    def test_repacked_crate_collision_never_reaches_publish(self):
        class Args:
            packages = self.root
            version = "0.1.0"
            native = self.root / "native.tar.gz"

        source = {"commit": "c" * 40, "dirty": False}
        identity = {"source": source, "files": {"rust/joints-0.1.0.crate": "a" * 64}}
        commands = []

        def cargo(args, *command, env):
            commands.append(command[0])
            target = Path(command[command.index("--target-dir") + 1]) / "package"
            target.mkdir(parents=True)
            (target / "joints-0.1.0.crate").write_bytes(b"different repack")

        with (
            patch.object(artifacts, "identities", return_value=identity),
            patch.object(artifacts, "source", return_value=source),
            patch.object(artifacts, "unpack_native", return_value=self.root),
            patch.object(artifacts, "cargo", side_effect=cargo),
            self.assertRaisesRegex(RuntimeError, "refusing publication"),
        ):
            artifacts.publish_crate(Args())
        self.assertEqual(commands, ["package"])


if __name__ == "__main__":
    unittest.main()

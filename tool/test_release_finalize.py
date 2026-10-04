"""Offline controls for immutable release assets and finalization order."""

import argparse
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import release_finalize as finalizer


class FinalizationControls(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.payload = self.root / "native.tar.gz"
        self.payload.write_bytes(b"tested native bytes")
        self.asset = {
            "name": self.payload.name,
            "id": 1,
            "state": "uploaded",
            "size": self.payload.stat().st_size,
        }
        self.record = {"tag_name": "v0.1.0", "assets": [self.asset]}

    def test_matching_asset_is_accepted_by_downloaded_bytes(self):
        with patch.object(
            finalizer.subprocess, "check_output", return_value=self.payload.read_bytes()
        ):
            self.assertEqual(
                finalizer.verify_assets(
                    self.record, {self.payload.name: self.payload}, complete=True
                ),
                {self.payload.name: self.asset},
            )

    def test_existing_asset_collision_refuses_without_any_write(self):
        with (
            patch.object(
                finalizer.subprocess,
                "check_output",
                return_value=b"different native bytes",
            ),
            patch.object(finalizer, "run") as write,
            self.assertRaisesRegex(RuntimeError, "published release asset differs"),
        ):
            finalizer.verify_assets(
                self.record, {self.payload.name: self.payload}, complete=True
            )
        write.assert_not_called()

    def test_unexpected_asset_refuses_before_download(self):
        with (
            patch.object(finalizer.subprocess, "check_output") as download,
            self.assertRaisesRegex(RuntimeError, "unexpected assets"),
        ):
            finalizer.verify_assets(self.record, {}, complete=False)
        download.assert_not_called()

    def test_missing_asset_cannot_finalize(self):
        with self.assertRaisesRegex(RuntimeError, "inventory differs"):
            finalizer.verify_assets(
                {"assets": []}, {self.payload.name: self.payload}, complete=True
            )

    def test_duplicate_asset_names_refuse(self):
        with self.assertRaisesRegex(RuntimeError, "duplicate release asset"):
            finalizer.assets({"assets": [self.asset, self.asset]})

    def test_incomplete_upload_refuses_before_download(self):
        for change in ({"state": "starter"}, {"size": 1}):
            with (
                patch.object(finalizer.subprocess, "check_output") as download,
                self.assertRaisesRegex(RuntimeError, "upload is incomplete"),
            ):
                finalizer.verify_assets(
                    {"assets": [self.asset | change]},
                    {self.payload.name: self.payload},
                    complete=True,
                )
            download.assert_not_called()

    def test_original_tag_and_payload_context_are_propagated(self):
        args = argparse.Namespace(
            tag="v0.1.0",
            source_sha="e" * 40,
            artifact_run="123",
            packages=self.root / "dist",
            source_root=self.root / "source",
        )
        with patch.object(finalizer, "run") as command:
            finalizer.assert_context(args)
        argv = command.call_args.args
        self.assertIn("verify-artifacts", argv)
        for option, value in (
            ("--release-tag", args.tag),
            ("--source-sha", args.source_sha),
            ("--artifact-run", args.artifact_run),
            ("--artifact-root", str(args.packages)),
            ("--source-root", str(args.source_root)),
            ("--native-target", "all"),
        ):
            self.assertEqual(argv[argv.index(option) + 1], value)

    def test_moved_tag_never_creates_a_release(self):
        args = argparse.Namespace(
            tag="v0.1.0",
            version="0.1.0",
            source_sha="e" * 40,
            artifact_run="123",
            packages=self.root / "dist",
            native_directory=self.root / "dist/native",
            source_root=self.root / "source",
            notes=self.root / "notes.md",
        )
        args.notes.write_text("Curated original release notes")
        with (
            patch.dict(os.environ, {"GITHUB_REPOSITORY": finalizer.REPOSITORY}),
            patch.object(
                finalizer.subprocess,
                "check_output",
                side_effect=[args.source_sha + "\n", ""],
            ),
            patch.object(
                finalizer,
                "assert_context",
                side_effect=RuntimeError("original tag moved"),
            ),
            patch.object(finalizer, "run") as write,
            self.assertRaisesRegex(RuntimeError, "original tag moved"),
        ):
            finalizer.finalize(args)
        write.assert_not_called()

    def test_dirty_original_checkout_never_checks_credentials_or_writes(self):
        args = argparse.Namespace(
            tag="v0.1.0",
            version="0.1.0",
            source_sha="e" * 40,
            artifact_run="123",
            packages=self.root / "dist",
            native_directory=self.root / "dist/native",
            source_root=self.root / "source",
            notes=self.root / "notes.md",
        )
        args.notes.write_text("Curated original release notes")
        with (
            patch.dict(os.environ, {"GITHUB_REPOSITORY": finalizer.REPOSITORY}),
            patch.object(
                finalizer.subprocess,
                "check_output",
                side_effect=[args.source_sha + "\n", " M README.md\n"],
            ),
            patch.object(finalizer, "assert_context") as context,
            patch.object(finalizer, "run") as write,
            self.assertRaisesRegex(RuntimeError, "checkout is dirty"),
        ):
            finalizer.finalize(args)
        context.assert_not_called()
        write.assert_not_called()

    def test_tag_change_after_upload_keeps_the_release_unpublished(self):
        packages = self.root / "dist"
        for directory in ("python", "rust", "native"):
            (packages / directory).mkdir(parents=True)
        names = (
            "python/joints-0.1.0.whl",
            "python/joints-0.1.0.tar.gz",
            "rust/joints-0.1.0.crate",
            "native/joints-0.1.0-linux-x86_64.tar.gz",
            "native/joints-0.1.0-macos-arm64.tar.gz",
            "packages.json",
        )
        files = {}
        for name in names:
            path = packages / name
            path.write_bytes(name.encode())
            files[path.name] = path
        notes = self.root / "notes.md"
        notes.write_text("Original curated release notes")
        args = argparse.Namespace(
            tag="v0.1.0",
            version="0.1.0",
            source_sha="e" * 40,
            artifact_run="123",
            packages=packages,
            native_directory=packages / "native",
            source_root=self.root / "source",
            notes=notes,
        )
        mutations = []

        def execute(*command, **kwargs):
            if command[0] == "gh":
                mutations.append(command[2])
            else:
                checksum = packages / "SHA256SUMS"
                checksum.write_text("controlled original checksums")
                files[checksum.name] = checksum

        def record():
            uploaded = "upload" in mutations
            return {
                "tag_name": args.tag,
                "assets": [
                    {
                        "name": name,
                        "id": index,
                        "state": "uploaded",
                        "size": path.stat().st_size,
                    }
                    for index, (name, path) in enumerate(files.items())
                ]
                if uploaded
                else [],
            }

        def output(command, **kwargs):
            if command[0] == "git":
                return args.source_sha + "\n" if "rev-parse" in command else ""
            index = int(command[-1].rsplit("/", 1)[1])
            return list(files.values())[index].read_bytes()

        with (
            patch.dict(os.environ, {"GITHUB_REPOSITORY": finalizer.REPOSITORY}),
            patch.object(finalizer.subprocess, "check_output", side_effect=output),
            patch.object(finalizer, "run", side_effect=execute),
            patch.object(
                finalizer,
                "release",
                side_effect=lambda tag: None if not mutations else record(),
            ),
            patch.object(
                finalizer,
                "assert_context",
                side_effect=[None, None, None, RuntimeError("original tag moved")],
            ),
            self.assertRaisesRegex(RuntimeError, "original tag moved"),
        ):
            finalizer.finalize(args)
        self.assertEqual(mutations, ["create", "upload"])


if __name__ == "__main__":
    unittest.main()

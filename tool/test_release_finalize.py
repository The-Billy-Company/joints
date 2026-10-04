"""Offline controls for immutable release assets and finalization order."""

import argparse
import io
import json
import os
import sys
import tempfile
import unittest
import urllib.error
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

    def test_release_commands_bind_repository_without_a_git_workspace(self):
        packages = self.root / "dist"
        for directory in ("python", "rust", "native"):
            (packages / directory).mkdir(parents=True)
        files = {}
        for name in (
            "python/joints-0.1.0.whl",
            "python/joints-0.1.0.tar.gz",
            "rust/joints-0.1.0.crate",
            "native/joints-0.1.0-linux-x86_64.tar.gz",
            "native/joints-0.1.0-macos-arm64.tar.gz",
            "packages.json",
        ):
            path = packages / name
            path.write_bytes(name.encode())
            files[path.name] = path
        (self.root / "control").mkdir()
        source = self.root / "joints"
        source.mkdir()
        notes = self.root / "notes.md"
        notes.write_text("Original curated release notes")
        args = argparse.Namespace(
            tag="v0.1.0",
            version="0.1.0",
            source_sha="e" * 40,
            artifact_run="123",
            packages=packages,
            native_directory=packages / "native",
            source_root=source,
            notes=notes,
        )
        command_log = self.root / "commands.jsonl"
        executable = self.root / "gh"
        executable.write_text(
            f"#!{sys.executable}\n"
            "import json, sys\n"
            "from pathlib import Path\n"
            "arguments = sys.argv[1:]\n"
            "if any((path / '.git').exists() for path in "
            "(Path.cwd(), *Path.cwd().parents)):\n"
            "    sys.exit('test workspace unexpectedly has a Git root')\n"
            "if '--repo' not in arguments or "
            f"arguments[arguments.index('--repo') + 1] != {finalizer.REPOSITORY!r}:\n"
            "    sys.exit('fatal: not a git repository')\n"
            f"with Path({str(command_log)!r}).open('a') as output:\n"
            "    output.write(json.dumps(arguments) + '\\n')\n"
        )
        executable.chmod(0o700)
        original_run = finalizer.subprocess.run

        def commands():
            if not command_log.exists():
                return []
            return [json.loads(line) for line in command_log.read_text().splitlines()]

        def execute(command, *, cwd=None, check=False):
            if command[0] == "gh":
                return original_run(
                    [str(executable), *command[1:]], cwd=self.root, check=check
                )
            checksum = packages / "SHA256SUMS"
            checksum.write_text("controlled original checksums")
            files[checksum.name] = checksum
            return None

        def lookup(request, **kwargs):
            if "/tags/" in request.full_url:
                raise urllib.error.HTTPError(
                    request.full_url, 404, "Not Found", {}, None
                )
            if request.full_url.endswith("page=2"):
                return io.BytesIO(b"[]")
            mutations = [command[1] for command in commands()]
            if not resume and "create" not in mutations:
                return io.BytesIO(b"[]")
            record = {
                "id": 402814282,
                "url": f"https://api.github.com/repos/{finalizer.REPOSITORY}/releases/402814282",
                "tag_name": args.tag,
                "draft": True,
                "assets": [
                    {
                        "name": name,
                        "id": index,
                        "state": "uploaded",
                        "size": path.stat().st_size,
                    }
                    for index, (name, path) in enumerate(files.items())
                ]
                if "upload" in mutations
                else [],
            }
            return io.BytesIO(json.dumps([record]).encode())

        def output(command, **kwargs):
            if command[0] == "git":
                return args.source_sha + "\n" if "rev-parse" in command else ""
            index = int(command[-1].rsplit("/", 1)[1])
            return list(files.values())[index].read_bytes()

        for resume in (False, True):
            command_log.unlink(missing_ok=True)
            with (
                self.subTest(existing_draft=resume),
                patch.dict(
                    os.environ,
                    {
                        "GITHUB_REPOSITORY": finalizer.REPOSITORY,
                        "GH_TOKEN": "fixture-token",
                    },
                ),
                patch.object(finalizer.subprocess, "check_output", side_effect=output),
                patch.object(finalizer.subprocess, "run", side_effect=execute),
                patch.object(finalizer.urllib.request, "build_opener") as opener,
                patch.object(finalizer, "assert_context") as context,
            ):
                opener.return_value.open.side_effect = lookup
                finalizer.finalize(args)
            expected = ["upload", "edit"] if resume else ["create", "upload", "edit"]
            self.assertEqual([command[1] for command in commands()], expected)
            self.assertEqual(context.call_count, 3 if resume else 4)
            if not resume:
                self.assertIn("--draft", commands()[0])
            self.assertIn("--draft=false", commands()[-1])


class ReleaseLookupControls(unittest.TestCase):
    @staticmethod
    def record(identity=1, tag="v0.1.0", *, draft=True):
        return {
            "id": identity,
            "url": f"https://api.github.com/repos/{finalizer.REPOSITORY}/releases/{identity}",
            "tag_name": tag,
            "draft": draft,
            "assets": [],
        }

    def lookup(self, responses):
        def opened(request, **kwargs):
            self.assertEqual(
                request.get_header("Authorization"), "Bearer fixture-token"
            )
            self.assertTrue(
                request.full_url.startswith(
                    f"https://api.github.com/repos/{finalizer.REPOSITORY}/releases"
                )
            )
            self.assertEqual(kwargs["timeout"], 30)
            response = next(responses)
            if isinstance(response, int):
                raise urllib.error.HTTPError(
                    request.full_url, response, "fixture", {}, None
                )
            return io.BytesIO(json.dumps(response).encode())

        with (
            patch.dict(os.environ, {"GH_TOKEN": "fixture-token"}),
            patch.object(finalizer.urllib.request, "build_opener") as factory,
        ):
            factory.return_value.open.side_effect = opened
            result = finalizer.release("v0.1.0")
            return result, factory

    def test_tag_404_resolves_unique_existing_draft_across_short_pages(self):
        draft = self.record(402814282)
        other = self.record(2, "v0.0.0", draft=False)
        result, factory = self.lookup(iter([404, [other], [draft], []]))
        self.assertEqual(result, draft)
        self.assertEqual(factory.return_value.open.call_count, 4)

    def test_clean_empty_inventory_is_absent(self):
        result, factory = self.lookup(iter([404, []]))
        self.assertIsNone(result)
        self.assertEqual(factory.return_value.open.call_count, 2)

    def test_tag_success_does_not_list_releases(self):
        published = self.record(draft=False)
        result, factory = self.lookup(iter([published]))
        self.assertEqual(result, published)
        self.assertEqual(factory.return_value.open.call_count, 1)

    def test_duplicate_matching_drafts_and_repeated_page_records_refuse(self):
        draft = self.record()
        for duplicate in (draft, self.record(2)):
            with (
                self.subTest(duplicate=duplicate),
                self.assertRaisesRegex(RuntimeError, "duplicate|ambiguous"),
            ):
                self.lookup(iter([404, [draft], [duplicate], []]))

    def test_malformed_responses_and_other_http_errors_refuse(self):
        draft = self.record()
        for responses in (
            [None],
            [403],
            [429],
            [500],
            [404, 404],
            [404, 500],
            [404, [draft], 500],
            [404, [draft], {}],
            [404, {}],
            [404, [None]],
            [404, [draft | {"id": True}]],
            [404, [draft | {"draft": "true"}]],
            [404, [draft | {"assets": {}}]],
            [404, [draft] * 101],
            [404, [draft | {"url": "https://example.org/1"}]],
            [draft | {"tag_name": "v0.0.0"}],
        ):
            with self.subTest(responses=responses), self.assertRaises(RuntimeError):
                self.lookup(iter(responses))

    def test_incomplete_bounded_inventory_refuses_even_after_matching_draft(self):
        draft = self.record()
        with (
            patch.object(finalizer, "MAX_RELEASE_PAGES", 1),
            self.assertRaisesRegex(RuntimeError, "pagination bound"),
        ):
            self.lookup(iter([404, [draft]]))

    def test_release_requests_refuse_redirects(self):
        _, factory = self.lookup(iter([404, []]))
        handler = factory.call_args.args[0]
        with self.assertRaisesRegex(RuntimeError, "redirect"):
            handler().redirect_request(
                None, None, 302, "fixture", {}, "https://example.org"
            )


if __name__ == "__main__":
    unittest.main()

"""Offline source-CI admission controls; no builds, downloads or native calls."""
import platform
from pathlib import Path
import hashlib
import json
import tempfile
import unittest
from unittest.mock import patch

import rust_engine_ci as ci


class SourceCI(unittest.TestCase):
    def test_source_python_bootstrap_refuses_failed_or_changed_interpreters_and_logs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            python = root / "python";python.write_bytes(b"authored interpreter")
            log = root / "build.log";log.write_bytes(b"authored successful build")
            channel = {"path": str(log), "sha256": ci.qualify.digest(log)}
            argv = ["authored-command"]
            command = {"argv": argv, "invocation_sha256": hashlib.sha256(json.dumps(argv, separators=(",", ":")).encode()).hexdigest(),
                       "exit": 0, "stdout": channel, "stderr": channel}
            value = {"pass": True, "python": {"version": list(ci.PYTHON_VERSION), "path": str(python),
                     "sha256": ci.qualify.digest(python)}, "commands": [command | {"label": label} for label in ci.PYTHON_BUILD_STEPS],
                     "source_url": ci.PYTHON_SOURCE_URL, "source_sha256": ci.PYTHON_SOURCE_SHA256,
                     "downloaded_source_sha256": ci.PYTHON_SOURCE_SHA256,
                     "workflow_sha256": ci.qualify.digest(ci.ROOT / ".github/workflows/rust-engine.yml"),
                     "bootstrap_helper_sha256": ci.qualify.digest(ci.python_bootstrap.__file__)}
            receipt = root / "receipt.json"
            receipt.write_text(json.dumps(value))
            self.assertEqual(ci.checked_python_bootstrap(receipt, python)["receipt"], value)
            changed_invocation = value["commands"][0] | {"argv": ["changed-command"]}
            for changed, error in [
                (value | {"source_sha256": "0" * 64}, "recipe differs"),
                (value | {"bootstrap_helper_sha256": "0" * 64}, "recipe differs"),
                (value | {"workflow_sha256": "0" * 64}, "recipe differs"),
                (value | {"commands": value["commands"][:-1]}, "command roster differs"),
                (value | {"commands": [changed_invocation, *value["commands"][1:]]}, "invocation changed"),
                (value | {"commands": [value["commands"][0] | {"exit": 1}, *value["commands"][1:]]}, "command failed"),
            ]:
                receipt.write_text(json.dumps(changed))
                with self.subTest(error=error), self.assertRaisesRegex(ValueError, error):
                    ci.checked_python_bootstrap(receipt, python)
            receipt.write_text(json.dumps(value | {"pass": False}))
            with self.assertRaisesRegex(ValueError, "did not complete"):
                ci.checked_python_bootstrap(receipt, python)
            receipt.write_text(json.dumps(value))
            python.write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "interpreter differs"):
                ci.checked_python_bootstrap(receipt, python)
            python.write_bytes(b"authored interpreter")
            log.write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "log changed"):
                ci.checked_python_bootstrap(receipt, python)
    def test_private_missing_and_changed_untracked_fixtures_refuse(self):
        public = {"upstream/grammars/go.json": "pinned"}
        tracked = {"rust/src/lib.rs", "test/migration/reference/manifest.json"}
        files = {"rust/src/lib.rs": "source", "upstream/grammars/go.json": "pinned"}
        ci.check_fixture_closure(files, tracked, public)
        for extra in [{".local/private.json": "secret"}, {"upstream/grammars/go.json": "changed"},
                      {"upstream/grammars/unpinned.json": "other"}]:
            with self.subTest(extra=extra), self.assertRaisesRegex(ValueError, "CI fixture"):
                ci.check_fixture_closure(files | extra, tracked, public)

    def test_newer_mac_or_wrong_machine_cannot_claim_the_mac14_floor(self):
        for system, machine, version in [("Darwin", "arm64", "26.6"),
                                         ("Darwin", "x86_64", "14.8"),
                                         ("Linux", "arm64", "14.8")]:
            with patch.object(platform, "system", return_value=system), \
                 patch.object(platform, "machine", return_value=machine), \
                 patch.object(platform, "mac_ver", return_value=(version, (), "")), \
                 self.assertRaisesRegex(ValueError, "actual macOS 14"):
                ci.host_identity("macos-arm64")

    def test_workflow_pins_the_same_source_toolchains_and_has_read_only_permissions(self):
        workflow = (ci.ROOT / ".github/workflows/rust-engine.yml").read_text()
        self.assertIn("ref: " + ci.IRGX_REVISION, workflow)
        self.assertIn("version: " + ci.ZIG_VERSION, workflow)
        self.assertIn("python-version: '" + ".".join(map(str, ci.PYTHON_VERSION)) + "'", workflow)
        self.assertIn("python3 -B tool/rust_python_bootstrap.py build", workflow)
        self.assertIn("--workflow .github/workflows/rust-engine.yml", workflow)
        self.assertIn("--receipt-environment ENGINE_CI_PYTHON_BOOTSTRAP", workflow)
        self.assertIn("for version in " + " ".join(ci.TOOLCHAINS), workflow)
        self.assertIn("contents: read", workflow)
        self.assertNotIn("pull_request_target", workflow)
        self.assertNotIn("secrets.", workflow)
        self.assertIn("runner: macos-14", workflow)
        self.assertIn("runner: ubuntu-24.04", workflow)

    def test_public_fixture_inventory_has_only_reproducible_grammar_paths(self):
        public = ci.public_grammar_inputs()
        self.assertGreaterEqual(len(public), 31)
        self.assertTrue(all(name.startswith("upstream/grammars/") and ".local" not in name for name in public))
        self.assertEqual(public["upstream/grammars/json.json"],
                         "6a823bbabc1bbf85f4d7bedfff359e1751011294ac670bd51788c9aff0d68637")


if __name__ == "__main__":
    unittest.main()

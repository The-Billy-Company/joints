"""Offline source-CI admission controls; no builds, downloads or native calls."""
import platform
import unittest
from unittest.mock import patch

import rust_engine_ci as ci


class SourceCI(unittest.TestCase):
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

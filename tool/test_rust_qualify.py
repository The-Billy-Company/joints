"""Qualification must reject incomplete observations and retain failed commands."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import rust_qualify as qualify


class Qualification(unittest.TestCase):
    def test_dynamic_roster_preserves_duplicates_ignores_and_doctest_names(self):
        output = """test repeated ... ok
test repeated ... ok
test expensive ... ignored, explicit corpus gate
test result: ok. 2 passed; 0 failed; 1 ignored; 0 measured; 0 filtered out; finished in 0s
test src/lib.rs - Example (line 12) ... ok
test result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0s
"""
        parsed = qualify.parse_tests(output)
        self.assertEqual(parsed["totals"], {"passed": 3, "failed": 0, "ignored": 1, "measured": 0, "filtered": 0})
        self.assertEqual(qualify.roster(parsed)[("repeated", "ok", None)], 2)
        self.assertIn(("src/lib.rs - Example (line 12)", "ok", None), qualify.roster(parsed))

    def test_summary_cannot_hide_missing_failed_or_filtered_tests(self):
        for output in (
            "test result: ok. 2 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out;",
            "test broken ... FAILED\ntest result: FAILED. 0 passed; 1 failed; 0 ignored; 0 measured; 0 filtered out;",
            "test kept ... ok\ntest result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 1 filtered out;",
        ):
            with self.subTest(output=output), self.assertRaises(ValueError):
                qualify.parse_tests(output)

    def test_compiler_and_loader_overrides_are_scrubbed_and_homes_preserved(self):
        chain = {"rustc": {"path": "/compiler/bin/rustc"}, "rustdoc": {"path": "/compiler/bin/rustdoc"},
                 "cargo": {"path": "/compiler/bin/cargo"}}
        with patch.dict(os.environ, {"HOME": "/chosen/home", "RUSTFLAGS": "unsafe", "RUSTC_WRAPPER": "wrapper",
                                     "JOINTS_CUSTOMARY": "changed", "DYLD_INSERT_LIBRARIES": "other", "CARGO_BUILD_TARGET": "other"}, clear=True):
            env = qualify.environment(chain, Path("/fresh/target"), Path("/checked/lib"), Path("/sdk"))
        self.assertEqual(env["HOME"], "/chosen/home")
        self.assertEqual(env["RUSTC"], "/compiler/bin/rustc")
        self.assertEqual(env["IRGX_LIB_DIR"], "/checked/lib")
        for key in ("RUSTFLAGS", "RUSTC_WRAPPER", "JOINTS_CUSTOMARY", "DYLD_INSERT_LIBRARIES", "CARGO_BUILD_TARGET"):
            self.assertNotIn(key, env)

    def test_failed_command_keeps_raw_logs_and_failure_status(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            report = {"commands": []}
            with self.assertRaisesRegex(ValueError, "remaining gates"):
                qualify.command([sys.executable, "-c", "import sys; print('failed output'); sys.exit(7)"],
                                out, os.environ.copy(), out, "failed", 10, report, out / "report.json")
            kept = json.loads((out / "report.json").read_text())["commands"][0]
            self.assertEqual(kept["returncode"], 7)
            self.assertEqual((out / "failed.stdout").read_text(), "failed output\n")
            self.assertEqual(qualify.digest(out / "failed.stdout"), kept["stdout"]["sha256"])

    def test_dependency_inventory_includes_nonrust_input_and_detects_new_files(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory).resolve()
            (home / "Cargo.toml").write_text("manifest")
            (home / "table.bin").write_bytes(b"included by a build script")
            (home / "target").mkdir()
            (home / "target/generated").write_text("not source")
            packages = [{"manifest_path": str(home / "Cargo.toml")}]
            before = qualify.package_inputs(packages)
            self.assertIn(str(home / "table.bin"), before)
            self.assertNotIn(str(home / "target/generated"), before)
            (home / "new.h").write_text("new native input")
            self.assertNotEqual(qualify.package_inputs(packages), before)

    def test_formatting_selects_workspace_packages_without_reformatting_path_dependencies(self):
        graph = {"workspace_members": ["engine", "adapter"], "packages": [
            {"id": "engine", "name": "joints-engine"}, {"id": "adapter", "name": "jnt-c"},
            {"id": "native", "name": "irgx"}]}
        args = qualify.format_arguments(graph)
        self.assertEqual(args, ["fmt", "--package", "jnt-c", "--package", "joints-engine", "--", "--check"])
        self.assertNotIn("irgx", args)
        with self.assertRaisesRegex(ValueError, "selection is incomplete"):
            qualify.format_arguments(graph | {"workspace_members": ["unknown"]})


if __name__ == "__main__":
    unittest.main()

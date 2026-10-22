"""Anti-vacuity controls for frozen migration evidence; no native build needed."""

import argparse
import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import migration as m


class MigrationEvidence(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name) / "bundle"
        self.answer = {
            "language": "json", "path": "inputs/source.json", "stop": {"kind": "accepted"},
            "roots": 1, "tree": [{"name": "document", "named": True, "start": 0, "end": 2, "kids": []}],
            "scars": [], "survey": {"sound": True, "walked": 1, "held": 1,
                                     "loose": 0, "disorder": 0, "torn": 0}, "mends": 0, "skipped": 0,
            "supplied": 0, "spurned": 0,
        }
        self.got = {"exit": 0, "stdout": m.encoded(self.answer), "stderr": b""}

    def bundle(self):
        for rel, data in {"inputs/grammar.json": b"{}", "inputs/source.json": b"{}",
                          "outputs/json-control.stdout": self.got["stdout"],
                          "outputs/json-control.stderr": b"",
                          "outputs/json-control.json": m.encoded(self.answer)}.items():
            m.write(self.home, rel, data)
        case = {"id": "json-control", "status": "captured", "exit": 0,
                "argv": ["parse", "inputs/grammar.json", "inputs/source.json", "--json"]}
        manifest = {"format": 1, "status": "captured", "cases": [case],
                    "expected_cases": [case["id"]],
                    "binary": {"stored": None, "sha256": "reference"},
                    "coverage": {"core_corpus": False, "regulator": "not-captured"},
                    "files": m.inventory(self.home)}
        m.write(self.home, "manifest.json", m.encoded(manifest))
        return manifest

    def test_exit_zero_without_confidence_is_not_success(self):
        for value in ({}, [], {**self.answer, "survey": {}}):
            with self.subTest(value=value), self.assertRaises(ValueError):
                m.answer({**self.got, "stdout": m.encoded(value)})
        with self.assertRaises(ValueError):
            m.answer({**self.got, "exit": 2})

    def test_selected_zig_version_is_detected(self):
        version = m.versions()["zig"]
        self.assertTrue(version["available"], version)
        self.assertEqual(version["exit"], 0)
        self.assertRegex(version["stdout"], r"^0\.16\.")

    def test_accepted_repaired_or_unsound_parse_is_not_strict(self):
        self.assertTrue(m.answer(self.got)[1])
        for changes in ({"scars": [{"at": 1, "over": 2, "felled": False, "heads": 1, "shifted": 0}]},
                        {"supplied": 1}, {"survey": {**self.answer["survey"], "sound": False}},
                        {"roots": 0, "tree": []}):
            with self.subTest(changes=changes):
                got = {**self.got, "stdout": m.encoded({**self.answer, **changes})}
                self.assertFalse(m.answer(got)[1])

    def test_malformed_success_shapes_are_rejected(self):
        changes = [{"roots": True}, {"mends": -1}, {"skipped": 0.0}, {"tree": {}},
                   {"scars": {}}, {"stop": []}, {"language": 1}, {"path": None},
                   {"survey": {**self.answer["survey"], "walked": False}},
                   {"tree": [{**self.answer["tree"][0], "kids": [None]}]},
                   {"tree": [{**self.answer["tree"][0], "end": -1}]},
                   {"tree": [{**self.answer["tree"][0], "start": 3}]}]
        for change in changes:
            with self.subTest(change=change), self.assertRaises(ValueError):
                m.answer({**self.got, "stdout": m.encoded({**self.answer, **change})})

    def test_missing_or_changed_fixture_fails_integrity(self):
        self.bundle()
        self.assertEqual(len(m.checked(self.home)["cases"]), 1)
        (self.home / "inputs/source.json").write_bytes(b"different")
        with self.assertRaisesRegex(ValueError, "bytes missing or changed"):
            m.checked(self.home)
        (self.home / "inputs/source.json").unlink()
        with self.assertRaisesRegex(ValueError, "bytes missing or changed"):
            m.checked(self.home)

    def test_omitted_output_is_not_a_pass(self):
        manifest = self.bundle()
        del manifest["files"]["outputs/json-control.json"]
        m.write(self.home, "manifest.json", m.encoded(manifest))
        with self.assertRaisesRegex(ValueError, "lacks hashed evidence"):
            m.checked(self.home)

    def test_replay_catches_wrong_successful_answer_and_never_skips_missing_binary(self):
        self.bundle()
        args = argparse.Namespace(bundle=self.home, binary=None, timeout=5)
        with self.assertRaisesRegex(ValueError, "requires --binary"):
            m.replay(args)
        binary = self.home.parent / "candidate"
        binary.write_bytes(b"an explicitly selected candidate")
        args.binary = binary
        with patch.object(m, "run", return_value=self.got), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(m.replay(args), 0)
        wrong = {**self.got, "stdout": m.encoded({**self.answer, "supplied": 1})}
        with (patch.object(m, "run", return_value=wrong), contextlib.redirect_stdout(io.StringIO()),
              contextlib.redirect_stderr(io.StringIO())):
            self.assertEqual(m.replay(args), 1)

    def test_export_is_relocatable_and_excludes_executable(self):
        self.bundle()
        out = self.home.parent / "elsewhere" / "goldens"
        with contextlib.redirect_stdout(io.StringIO()):
            m.export(argparse.Namespace(bundle=self.home, out=out))
        value = m.checked(out)
        self.assertIsNone(value["binary"]["stored"])
        self.assertFalse((out / "binary").exists())
        self.assertNotIn(str(self.home), (out / "manifest.json").read_text())

    def test_internal_state_number_and_arena_occupancy_are_normalized(self):
        left = {**self.answer, "stop": {"kind": "unexpected", "at": 1, "state": 12}}
        right = {**left, "stop": {"kind": "unexpected", "at": 1, "state": 99}}
        self.assertEqual(m.semantic(left), m.semantic(right))
        right["stop"]["at"] = 2
        self.assertNotEqual(m.semantic(left), m.semantic(right))
        right = {**left, "survey": {**left["survey"], "held": 99}}
        self.assertEqual(m.semantic(left), m.semantic(right))
        for key, changed in (("walked", 2), ("sound", False), ("loose", 1),
                             ("disorder", 1), ("torn", 1)):
            altered = {**right, "survey": {**right["survey"], key: changed}}
            self.assertNotEqual(m.semantic(left), m.semantic(altered), key)

    def test_sibling_source_change_invalidates_build_attestation(self):
        before = {name: {"commit": "abc", "source_sha256": "same", "dirty": []}
                  for name in m.BUILD_INPUTS}
        after = json.loads(json.dumps(before))
        after["irregex"]["source_sha256"] = "different dirty source bytes"
        self.assertFalse(m.stable(before, after))

    def test_old_private_pin_cannot_claim_current_sources(self):
        binary = self.home / "bin/joints"
        m.write(self.home, "bin/joints", b"private binary")
        record = {"build": m.sha(binary.read_bytes()), "tree": "old-tree", "commit": "old-commit"}
        m.write(self.home, "pin.json", m.encoded(record))
        with (patch.object(m.stamp, "survey", return_value=SimpleNamespace(digest="new-tree")),
              self.assertRaisesRegex(ValueError, "source or commit differs")):
            m.private_pin(binary, "new-commit")

    def test_core_roster_cannot_silently_shrink(self):
        import rung1
        with (patch.object(rung1, "pairs", return_value=[]),
              self.assertRaisesRegex(ValueError, "eleven pinned")):
            m.cases(self.home, True)

    def test_explicit_candidate_moving_during_replay_is_rejected(self):
        self.bundle()
        binary = self.home.parent / "candidate"
        binary.write_bytes(b"before")
        def replaced(*args):
            binary.write_bytes(b"after")
            return self.got
        with (patch.object(m, "run", side_effect=replaced), contextlib.redirect_stdout(io.StringIO()),
              self.assertRaisesRegex(ValueError, "moved during replay")):
            m.replay(argparse.Namespace(bundle=self.home, binary=binary, timeout=5))

    def test_core_parser_replay_requires_thirteen_explicit_cases(self):
        home = m.ROOT / "test/migration/reference"
        manifest = m.checked(home)
        selected = m.replay_cases(manifest, "core-parser")
        self.assertEqual(len(selected), 13)
        self.assertEqual(len(m.replay_cases(manifest, "all")), 25)
        self.assertTrue(all(c["id"].endswith("-no-recovery") or c["id"] == "corpus-json"
                            for c in selected))
        shortened = {**manifest, "cases": manifest["cases"][2:]}
        with self.assertRaisesRegex(ValueError, "requires all 13"):
            m.replay_cases(shortened, "core-parser")
        broken = json.loads(json.dumps(manifest))
        next(c for c in broken["cases"] if c["id"].endswith("-no-recovery"))["argv"].remove("--no-supply")
        with self.assertRaisesRegex(ValueError, "explicit no-recovery"):
            m.replay_cases(broken, "core-parser")

    def test_core_replay_executes_only_selected_cases_and_reports_scope(self):
        home = m.ROOT / "test/migration/reference"
        binary = self.home.parent / "candidate"
        binary.write_bytes(b"explicit candidate")
        def captured(argv, cwd, timeout):
            case = next(c for c in m.checked(home)["cases"] if c["argv"] == argv[1:])
            return {"exit": case["exit"],
                    "stdout": (home / f"outputs/{case['id']}.stdout").read_bytes(), "stderr": b""}
        output = io.StringIO()
        with patch.object(m, "run", side_effect=captured) as executed, contextlib.redirect_stdout(output):
            self.assertEqual(m.replay(argparse.Namespace(bundle=home, binary=binary,
                             timeout=5, suite="core-parser")), 0)
        self.assertEqual(executed.call_count, 13)
        self.assertIn("selected 13 of 25", output.getvalue())
        self.assertIn("12 out-of-scope (not executed or counted as successes)", output.getvalue())


if __name__ == "__main__":
    unittest.main()

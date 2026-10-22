"""Admission controls for the native-host starting-Rust diagnostic."""
from pathlib import Path
import json
import tempfile
import unittest

import rust_perf_ci as ci


class PerformanceCI(unittest.TestCase):
    def test_changed_reference_benchmark_refuses(self):
        with tempfile.TemporaryDirectory() as directory:
            baseline, candidate = (Path(directory) / name for name in ("baseline", "candidate"))
            baseline.write_bytes(b"same benchmark")
            candidate.write_bytes(b"same benchmark")
            ci.require_same_benchmark(baseline, candidate)
            candidate.write_bytes(b"changed timing region")
            with self.assertRaisesRegex(ValueError, "programs differ"):
                ci.require_same_benchmark(baseline, candidate)

    def test_missing_or_ambiguous_built_executable_refuses(self):
        with tempfile.NamedTemporaryFile() as executable:
            row = {"reason": "compiler-artifact", "target": {"name": "runtime", "kind": ["bench"]},
                   "executable": executable.name}
            wire = json.dumps(row)
            self.assertEqual(ci.benchmark_executable(wire), Path(executable.name).resolve())
            for invalid in ("", wire + "\n" + wire, json.dumps(row | {"executable": None}),
                            json.dumps(row | {"target": {"name": "other", "kind": ["bench"]}})):
                with self.subTest(invalid=invalid), self.assertRaisesRegex(ValueError, "exactly one"):
                    ci.benchmark_executable(invalid)


if __name__ == "__main__":
    unittest.main()

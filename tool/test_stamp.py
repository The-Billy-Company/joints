"""Structured parse confidence belongs to the same owner as text verdicts."""

from __future__ import annotations

import copy
import unittest

import stamp


class StructuredConfidenceTests(unittest.TestCase):
    def setUp(self):
        self.answer = {
            "stop": {"kind": "accepted"},
            "roots": 1,
            "mends": 0,
            "skipped": 0,
            "supplied": 0,
            "survey": {"sound": True},
        }

    def test_every_confidence_failure_refuses_strict_credit(self):
        self.assertTrue(stamp.strict(self.answer))
        for field, bad in (("roots", 0), ("roots", 2), ("mends", 1),
                           ("skipped", 1), ("supplied", 1)):
            with self.subTest(field=field, value=bad):
                answer = copy.deepcopy(self.answer)
                answer[field] = bad
                self.assertFalse(stamp.strict(answer))
        for stop in ("stray", "unexpected", "truncated"):
            with self.subTest(stop=stop):
                answer = copy.deepcopy(self.answer)
                answer["stop"]["kind"] = stop
                self.assertFalse(stamp.strict(answer))
        self.answer["survey"]["sound"] = False
        self.assertFalse(stamp.strict(self.answer))

    def test_omitted_evidence_cannot_become_an_empty_success(self):
        for field in self.answer:
            with self.subTest(field=field):
                answer = copy.deepcopy(self.answer)
                del answer[field]
                with self.assertRaises(KeyError):
                    stamp.strict(answer)


if __name__ == "__main__":
    unittest.main()

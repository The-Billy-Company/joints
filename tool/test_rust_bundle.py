"""A fresh delivery bundle must retain and prove the original member payloads."""
import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import rust_bundle as bundle
import rust_archive
from test_rust_static_boundary import archive_bytes, elf_object


class Bundle(unittest.TestCase):
    def test_incomplete_qualification_refuses_before_reading_source_or_build_outputs(self):
        for value in ({}, {"schema": 1, "status": "completed", "pass": True, "stable": False,
                          "workspace_qualified": True}):
            with patch.object(bundle.rust, "rust_inputs") as inputs, self.assertRaisesRegex(ValueError, "positive/stable"):
                bundle.check_qualification(value)
            inputs.assert_not_called()

    def test_member_payload_order_names_and_receipt_are_all_required(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            first, second = elf_object(), elf_object(private_names={"owned": "private_other"})
            original = root / "raw.a";normalized = root / "selected.a"
            original.write_bytes(archive_bytes([("original.rcgu.o", first), ("second.o", second)], [], bsd=False))
            normalized.write_bytes(archive_bytes([("native-000000.o", first), ("native-000001.o", second)], [], bsd=False))
            raw = rust_archive.read_archive(original)
            receipt = {"input_sha256": bundle.digest(original), "output_sha256": bundle.digest(normalized),
                       "member_count": 2, "members": [
                           {"position": index, "original_name_hex": member.name.hex(),
                            "normalized_name": f"native-{index:06d}.o", "bytes": member.end - member.start,
                            "sha256": hashlib.sha256(raw.payload(member)).hexdigest()}
                           for index, member in enumerate(raw.members)]}
            bundle.verify_normalization(original, normalized, receipt)
            receipt["members"][1]["original_name_hex"] = "wrong"
            with self.assertRaisesRegex(ValueError, "member or its order"):
                bundle.verify_normalization(original, normalized, receipt)
            receipt["members"][1]["original_name_hex"] = raw.members[1].name.hex()
            normalized.write_bytes(archive_bytes([("native-000000.o", second), ("native-000001.o", first)], [], bsd=False))
            receipt["output_sha256"] = bundle.digest(normalized)
            with self.assertRaisesRegex(ValueError, "member or its order"):
                bundle.verify_normalization(original, normalized, receipt)

    def test_existing_bundle_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report = root / "report.json";report.write_text("{}")
            output = root / "bundle";output.mkdir()
            marker = output / "original";marker.write_text("keep me")
            with self.assertRaisesRegex(ValueError, "already exists"):
                bundle.make_bundle(report, output, zig=root / "unused-zig")
            self.assertEqual(marker.read_text(), "keep me")


if __name__ == "__main__":
    unittest.main()

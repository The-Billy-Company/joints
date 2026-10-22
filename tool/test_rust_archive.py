"""Native archive packaging preserves bytes and refuses incomplete transforms."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import rust_archive as archive


def record(name, payload):
    header = (name.ljust(16, b" ") + b"0".ljust(12) + b"0".ljust(6)
              + b"0".ljust(6) + b"100644".ljust(8)
              + str(len(payload)).encode().ljust(10) + b"`\n")
    assert len(header) == 60
    return header + payload + (b"\n" if len(payload) % 2 else b"")


def image(members):
    out = bytearray(b"!<arch>\n")
    for name, payload in members:
        if len(name) > 15 or b" " in name:
            out.extend(record(b"#1/" + str(len(name)).encode(), name + payload))
        else:
            out.extend(record(name + b"/", payload))
    return bytes(out)


FAKE_ZIG = '''#!/usr/bin/env python3
import os,sys,pathlib
if sys.argv[1:] == ["version"]:
 print("0.16.0-fixture");sys.exit(0)
assert sys.argv[1:3]==["ar","rcsD"]
mode=os.environ.get("ARCHIVE_TEST_MODE","")
if mode=="fail": sys.exit(17)
if mode=="missing": sys.exit(0)
files=pathlib.Path(sys.argv[4][1:]).read_text().splitlines()
out=bytearray(b"!<arch>\\n")
for i,name in enumerate(files):
 if mode=="omit" and i==0:continue
 data=pathlib.Path(name).read_bytes()
 if mode=="change" and i==0:data+=b"changed"
 header=(name+"/").ljust(16)+"0".ljust(12)+"0".ljust(6)+"0".ljust(6)+"100644".ljust(8)+str(len(data)).ljust(10)+"`\\n"
 out.extend(header.encode());out.extend(data)
 if len(data)%2:out.extend(b"\\n")
pathlib.Path(sys.argv[3]).write_bytes(out)
'''


class NativeArchive(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="native archive tests ")
        self.root = Path(self.directory.name)
        self.zig = self.root / "fake zig"
        self.zig.write_text(FAKE_ZIG)
        self.zig.chmod(0o755)
        self.path = self.root / "libjnt.a"

    def tearDown(self):
        self.directory.cleanup()

    def normalize(self):
        return archive.normalize(self.path, zig=str(self.zig))

    def test_duplicate_unsafe_and_non_utf8_names_preserve_payload_order(self):
        source = [(b"crate.hash.rcgu.o", b"first\0object"),
                  (b"../../escape.rcgu.o", b"second"),
                  (b"crate.hash.rcgu.o", b"third"),
                  (b"nonutf8-\xff.o", b"fourth")]
        self.path.write_bytes(image(source))
        proof = self.normalize()
        got = archive.read_archive(self.path)
        self.assertEqual([bytes(got.payload(m)) for m in got.members], [p for _, p in source])
        self.assertEqual([m.name for m in got.members], [f"native-{i:06d}.o".encode() for i in range(4)])
        self.assertEqual([m["original_name_hex"] for m in proof["members"]], [n.hex() for n, _ in source])
        self.assertEqual([m["sha256"] for m in proof["members"]], [archive.sha(p) for _, p in source])
        self.assertFalse((self.root.parent / "escape.rcgu.o").exists())

    def test_gnu_long_names_and_symbol_index_are_not_object_members(self):
        long_name = b"long-nested-directory/file.hash.rcgu.o"
        source = (b"!<arch>\n" + record(b"/", b"symbol index")
                  + record(b"//", long_name + b"/\n") + record(b"/0", b"object"))
        self.path.write_bytes(source)
        proof = self.normalize()
        self.assertEqual(proof["member_count"], 1)
        self.assertEqual(proof["members"][0]["original_name_hex"], long_name.hex())
        self.assertEqual(proof["members"][0]["sha256"], archive.sha(b"object"))

    def test_deterministic_idempotent_rebuild_does_not_trust_old_member_names(self):
        self.path.write_bytes(image([(b"one.rcgu.o", b"abc"), (b"two.rcgu.o", b"defg")]))
        first = self.normalize()
        packed = self.path.read_bytes()
        second = self.normalize()
        self.assertTrue(first["changed"])
        self.assertFalse(second["changed"])
        self.assertEqual(self.path.read_bytes(), packed)
        self.assertEqual(first["output_sha256"], second["input_sha256"])
        # Names alone cannot bypass rebuilding and validating the current objects.
        with patch.dict(os.environ, {"ARCHIVE_TEST_MODE": "change"}):
            with self.assertRaisesRegex(ValueError, "changed object bytes"):
                self.normalize()
        self.assertEqual(self.path.read_bytes(), packed)

    def test_truncated_malformed_empty_and_thin_inputs_are_never_replaced(self):
        inputs = [b"", b"not-ar", b"!<thin>\n", b"!<arch>\n", b"!<arch>\nshort",
                  image([(b"x.o", b"odd")])[:-1],
                  b"!<arch>\n" + record(b"#1/999", b"name")]
        for source in inputs:
            with self.subTest(source=source):
                self.path.write_bytes(source)
                with self.assertRaises(ValueError):
                    self.normalize()
                self.assertEqual(self.path.read_bytes(), source)

    def test_archiver_failure_missing_output_and_incomplete_transform_are_not_published(self):
        source = image([(b"x.rcgu.o", b"one"), (b"y.rcgu.o", b"two")])
        for mode in ("fail", "missing", "omit", "change"):
            with self.subTest(mode=mode), patch.dict(os.environ, {"ARCHIVE_TEST_MODE": mode}):
                self.path.write_bytes(source)
                with self.assertRaises((ValueError, OSError, subprocess.CalledProcessError)):
                    self.normalize()
                self.assertEqual(self.path.read_bytes(), source)
                self.assertEqual(list(self.root.glob(".native-archive-*")), [])

    def test_input_mutation_during_archiver_run_refuses_without_overwriting_the_new_input(self):
        self.path.write_bytes(image([(b"x.rcgu.o", b"original")]))
        changed = image([(b"x.rcgu.o", b"new producer output")])
        real_run = subprocess.run
        def mutate(command, **kwargs):
            result = real_run(command, **kwargs)
            if command[1] == "ar":
                self.path.write_bytes(changed)
            return result
        with patch.object(archive.subprocess, "run", side_effect=mutate):
            with self.assertRaisesRegex(ValueError, "changed during normalization"):
                self.normalize()
        self.assertEqual(self.path.read_bytes(), changed)

    def test_missing_archiver_refuses_even_for_previously_normalized_input(self):
        self.path.write_bytes(image([(b"native-000000.o", b"current object")]))
        before = self.path.read_bytes()
        with self.assertRaisesRegex(ValueError, "unavailable"):
            archive.normalize(self.path, zig=str(self.root / "missing-zig"))
        self.assertEqual(self.path.read_bytes(), before)

    def test_byte_member_and_name_extents_are_checked(self):
        self.path.write_bytes(image([(b"x.rcgu.o", b"a"), (b"y.rcgu.o", b"b")]))
        with patch.object(archive, "MAX_ARCHIVE_BYTES", 8):
            with self.assertRaisesRegex(ValueError, "byte limit"):
                archive.read_archive(self.path)
        with patch.object(archive, "MAX_MEMBERS", 1):
            with self.assertRaisesRegex(ValueError, "member limit"):
                archive.read_archive(self.path)
        self.path.write_bytes(b"!<arch>\n" + record(b"//", b"long.o/\n") + record(b"/999", b"data"))
        with self.assertRaisesRegex(ValueError, "offset exceeds"):
            archive.read_archive(self.path)

    def test_receipt_cannot_overwrite_its_archive(self):
        self.path.write_bytes(image([(b"x.o", b"object")]))
        before = self.path.read_bytes()
        with patch.object(archive.sys, "argv", ["rust_archive.py", str(self.path), "--receipt", str(self.path)]):
            self.assertEqual(archive.main(), 2)
        self.assertEqual(self.path.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()

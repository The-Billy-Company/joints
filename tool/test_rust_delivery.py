"""Offline controls; no native/Cargo build, vendor, install, or network activity."""
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import tarfile
import tempfile
import unittest
from unittest import mock

import rust_delivery as delivery


def put(root, name, data=b"source"):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return path


def source(root):
    put(root, "joints/rust/src/lib.rs", b"qualified core")
    put(root, "joints/rust/Cargo.toml", b'[dependencies]\nirgx={features=["source-engine"]}\n')
    put(root, "joints/rust/src/artifact.rs", b"const VERSION: u32 = 2;\nconst SCHEMA: u32 = 3;\n")
    put(root, "joints/README.md", b"current source documentation")
    put(root, ".cargo/config.toml", b'[source.crates-io]\nreplace-with="standalone-vendor"\n'
        b'[source.standalone-vendor]\ndirectory="dependencies/cargo"\n[net]\noffline=true\n')
    put(root, "dependencies/cargo/serde-1/.cargo-checksum.json", b'{"files":{},"package":null}')
    put(root, "dependencies/python/hatchling-1-py3-none-any.whl")
    put(root, "dependencies/python/build-1-py3-none-any.whl")
    native = put(root, "irregex/src/native.zig", b"native source")
    binding = put(root, "irregex/bindings/rust/src/lib.rs", b"additive source-engine API")
    value = {"schema": 1, "kind": "local-rust-source", "publishable": False,
             "versions": delivery.VERSIONS, "offline": {"cargo": True, "python_wheels": True},
             "qualified_compiled_inputs": {"files": {"rust/src/lib.rs": delivery.digest(root / "joints/rust/src/lib.rs")}},
             "native_inputs": {"native": {"files": {"src/native.zig": delivery.digest(native)}},
                               "binding": {"bindings/rust/src/lib.rs": delivery.digest(binding)}},
             "files": delivery.file_map(root)}
    (root / "source-manifest.json").write_bytes(delivery.encoded(value))
    return value


def refresh(root, value):
    paths = delivery.file_map(root)
    paths.pop("source-manifest.json", None)
    value["files"] = paths
    (root / "source-manifest.json").write_bytes(delivery.encoded(value))


def elf(machine=62):
    data = bytearray(64)
    data[:6] = b"\x7fELF\x02\x01"
    data[18:20] = machine.to_bytes(2, "little")
    return bytes(data)


def macho(*commands):
    header = bytearray(32)
    header[:8] = b"\xcf\xfa\xed\xfe\x0c\x00\x00\x01"
    header[16:20] = len(commands).to_bytes(4, "little")
    header[20:24] = sum(map(len, commands)).to_bytes(4, "little")
    return bytes(header) + b"".join(commands)


def archive(root, entries):
    """Build small corrupt/valid tar fixtures without invoking an archiver."""
    path = root / "fixture.tar.gz"
    with tarfile.open(path, "w:gz") as stream:
        for name, kind, body in entries:
            info = tarfile.TarInfo(name)
            info.type = kind
            info.size = len(body)
            if kind == tarfile.SYMTYPE:
                info.linkname = "../../escape"
            stream.addfile(info, io.BytesIO(body) if kind == tarfile.REGTYPE else None)
    return path


def bundle(root, source_value, native_archive):
    identity = {"rust_inputs": source_value["qualified_compiled_inputs"]["files"],
                "native": {"archive_sha256": delivery.digest(native_archive),
                           "inputs": source_value["native_inputs"]},
                "toolchain": {"rustc": "test fixture; never executed", "cargo": "test fixture"}}
    put(root, "bin/joints-rs", elf())
    put(root, "lib/libjnt.a", b"fake archive; machine check mocked separately")
    put(root, "lib/libjnt.so", elf())
    put(root, "include/jnt.h")
    proof = {"exit": 0, "stable": True, **identity}
    put(root, "build.json", delivery.encoded(proof))
    value = {"schema": 1, "identity": identity,
             "identity_sha256": hashlib.sha256(delivery.encoded(identity)).hexdigest(),
             "files": delivery.file_map(root)}
    put(root, "bundle.json", delivery.encoded(value))
    return value


class DeliveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_candidate_workflow_pins_match_shipped_verifier_bootstrap(self):
        root = Path(__file__).resolve().parents[1]
        workflow = (root / ".github/workflows/rust-candidate.yml").read_text()
        bootstrap = workflow.split("name: Pin the shipped verifier bootstrap", 1)[1]
        bootstrap = bootstrap.split("name: Verify actual host floor", 1)[0]
        pairs = re.findall(r"'(tool/rust_[^']+\.py)': '([0-9a-f]{64})'", bootstrap)
        expected = {"tool/rust_delivery.py", "tool/rust_archive.py", "tool/rust_static_boundary.py"}
        self.assertEqual(len(pairs), len(expected), "duplicate or missing verifier pins")
        self.assertEqual({name for name, _ in pairs}, expected)
        for name, pinned in pairs:
            self.assertEqual(delivery.digest(root / name), pinned, f"stale candidate bootstrap: {name}")

    def checked108_fixture(self, root):
        home = root / "source";manifest = source(home)
        header = put(home, "irregex/include/irgx.h", b"authoritative native108 header")
        producer = put(home, "joints/tool/rust_delivery.py", b"delivery producer")
        refresh(home, manifest)
        raw = put(root, "proof/build/lib/libirgx.a", b"raw archive")
        selected = put(root, "lib/libirgx.a", b"verified opaque derivative")
        proof = {"schema": 1, "abi_family": "irgx-abi2-108-munch-image1", "target": "macos-arm64",
                 "kind": "opaque-native-only-C-static-boundary", "machine_code_only": True,
                 "before_sha256": delivery.digest(raw), "after_sha256": delivery.digest(selected)}
        native = put(root, "native-boundary.json", delivery.encoded(proof))
        cargo = put(root, "proof.json", native.read_bytes())
        declaration = delivery.checked_native_selection(raw, selected, cargo, target="macos-arm64",
            source_inputs=manifest["native_inputs"], header=header, producer_sha256=delivery.digest(producer))
        put(root, "selection.json", delivery.encoded(declaration))
        return declaration

    def test_checked108_cargo_pair_is_portable_and_missing_pair_is_refused(self):
        home = self.root / "package";declaration = self.checked108_fixture(home)
        observed = delivery.check_native_selection(home, "macos-arm64")
        moved = self.root / "relocated";shutil.copytree(home, moved)
        self.assertEqual(delivery.check_native_selection(moved, "macos-arm64"), observed)
        self.assertEqual(observed["archive_sha256"], declaration["archive_sha256"])
        for name in ("selection.json", "proof.json"):
            path = moved / name;data = path.read_bytes();path.unlink()
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, "missing regular"):
                delivery.check_native_selection(moved, "macos-arm64")
            path.write_bytes(data)

    def test_checked108_pair_refuses_changed_bytes_target_family_and_declarations(self):
        home = self.root / "package";self.checked108_fixture(home)
        for name in ("lib/libirgx.a", "proof/build/lib/libirgx.a", "proof.json"):
            path = home / name;data = path.read_bytes();path.write_bytes(data + b" ")
            with self.subTest(name=name), self.assertRaises(ValueError):
                delivery.check_native_selection(home, "macos-arm64")
            path.write_bytes(data)
        path = home / "selection.json";data = path.read_bytes();declaration = delivery.read_json(path)
        declaration["archive_sha256"] = "0" * 64;path.write_bytes(delivery.encoded(declaration))
        with self.assertRaisesRegex(ValueError, "selection differs"):
            delivery.check_native_selection(home, "macos-arm64")
        path.write_bytes(data)
        with self.assertRaisesRegex(ValueError, "contract differs"):
            delivery.check_native_selection(home, "linux-x86_64")
        proof = delivery.read_json(home / "proof.json");proof["abi_family"] = "irgx-abi2-105"
        for name in ("proof.json", "native-boundary.json"):
            (home / name).write_bytes(delivery.encoded(proof))
        with self.assertRaisesRegex(ValueError, "contract differs"):
            delivery.check_native_selection(home, "macos-arm64")

    def test_relative_paths_have_no_alternate_escape_spelling(self):
        for name in ("", ".", "..", "../x", "/tmp/x", "a/../b", "a//b", "a/./b", "a\\b", "a\0b"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                delivery.relative(name)
        self.assertEqual(delivery.relative("joints/café.rs"), Path("joints/café.rs"))

    def test_explicit_unrelated_asset_exclusion_preserves_file_and_compiled_inputs(self):
        asset = put(self.root, "user image.png", b"unrelated user image")
        compiled = put(self.root, "rust/src/lib.rs", b"qualified source")
        files = {"user image.png", "rust/src/lib.rs"}
        proof = {"rust/src/lib.rs": delivery.digest(compiled)}
        with mock.patch.object(delivery, "source_selection", return_value=files):
            names, records = delivery.export_selection(self.root, proof, ("user image.png",))
            self.assertEqual(names, {"rust/src/lib.rs"})
            self.assertEqual(records, [{"repository": "joints", "path": "user image.png",
                                        "sha256": delivery.digest(asset), "bytes": asset.stat().st_size}])
            self.assertEqual(asset.read_bytes(), b"unrelated user image")
            for excluded in (("rust/src/lib.rs",), ("missing.png",), ("user image.png", "user image.png")):
                with self.subTest(excluded=excluded), self.assertRaises(ValueError):
                    delivery.export_selection(self.root, proof, excluded)

    def test_duplicate_json_is_not_silently_overwritten(self):
        path = put(self.root, "bad.json", b'{"schema":1,"schema":2}')
        with self.assertRaisesRegex(ValueError, "duplicate"):
            delivery.read_json(path)

    def test_source_symlink_and_symlink_parent_are_refused(self):
        actual = put(self.root, "private/data")
        (self.root / "alias").symlink_to(actual)
        (self.root / "parent").symlink_to(actual.parent, target_is_directory=True)
        for name in ("alias", "parent/data"):
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, "symlink"):
                delivery.regular(self.root, name)

    def test_unlisted_directory_symlink_cannot_hide_from_inventory(self):
        home = self.root / "source";source(home)
        outside = self.root / "outside";put(outside, "private")
        (home / "hidden-directory").symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlink"):
            delivery.source_manifest(home)

    def test_copied_source_bytes_are_unchanged_and_extras_refuse(self):
        home = self.root / "original";put(home, "src/a", b"exact\nbytes")
        copied = self.root / "copy"
        files = delivery.copy_sources(home, {"src/a"}, copied)
        self.assertEqual((copied / "src/a").read_bytes(), b"exact\nbytes")
        delivery.check_files(copied, files, exact=True)
        put(copied, "accidental", b"unlisted")
        with self.assertRaisesRegex(ValueError, "inventory"):
            delivery.check_files(copied, files, exact=True)

    def test_changed_source_checksum_is_refused(self):
        home = self.root / "source";value = source(home)
        put(home, "joints/README.md", b"changed after export")
        with self.assertRaisesRegex(ValueError, "checksum"):
            delivery.source_manifest(home)
        self.assertNotEqual(delivery.digest(home / "joints/README.md"), value["files"]["joints/README.md"])

    def test_current_docs_and_historical_compiled_join_are_separate(self):
        home = self.root / "source";value = source(home)
        put(home, "joints/README.md", b"new explicitly snapshotted docs")
        refresh(home, value)
        result = delivery.source_manifest(home)
        self.assertEqual(result["qualified_compiled_inputs"], value["qualified_compiled_inputs"])

    def test_changed_core_cannot_be_retagged_as_same_compiled_join(self):
        home = self.root / "source";value = source(home)
        put(home, "joints/rust/src/lib.rs", b"different core")
        refresh(home, value)
        with self.assertRaisesRegex(ValueError, "qualified compiled input"):
            delivery.source_manifest(home)

    def test_qualified_compiled_pin_cannot_use_none_for_a_missing_input(self):
        home = self.root / "source";value = source(home)
        value["qualified_compiled_inputs"]["files"] = {"missing.rs": None}
        refresh(home, value)
        with self.assertRaisesRegex(ValueError, "invalid qualified compiled checksum"):
            delivery.source_manifest(home)

    def test_qualified_compiled_pin_path_is_checked_independently(self):
        home = self.root / "source";value = source(home)
        value["qualified_compiled_inputs"]["files"] = {"../outside.rs": None}
        refresh(home, value)
        with self.assertRaisesRegex(ValueError, "path"):
            delivery.source_manifest(home)

    def test_deleted_native_inputs_cannot_be_resurrected_in_a_coherent_manifest(self):
        for group in ("native", "binding"):
            with self.subTest(group=group):
                home = self.root / group;value = source(home)
                pin = value["native_inputs"]["native"]["files"] if group == "native" else value["native_inputs"]["binding"]
                pin["src/deleted-input.zig"] = None
                refresh(home, value)
                delivery.source_manifest(home)
                put(home, "irregex/src/deleted-input.zig", b"resurrected tracked deletion")
                refresh(home, value)  # All archive/file hashes agree; the independent None pin still governs.
                with self.assertRaisesRegex(ValueError, "deleted native source resurrected"):
                    delivery.source_manifest(home)

    def test_offline_config_cannot_escape_export(self):
        home = self.root / "source";value = source(home)
        path = home / ".cargo/config.toml"
        path.write_text(path.read_text().replace('"dependencies/cargo"', '"/original/checkout/vendor"'))
        refresh(home, value)
        with self.assertRaisesRegex(ValueError, "escapes"):
            delivery.source_manifest(home)

    def test_deleted_native_path_cannot_be_resurrected_as_an_empty_directory(self):
        home = self.root / "source";value = source(home)
        value["native_inputs"]["native"]["files"]["src/deleted.zig"] = None
        (home / "irregex/src/deleted.zig").mkdir()
        refresh(home, value)
        with self.assertRaisesRegex(ValueError, "deleted native source resurrected"):
            delivery.source_manifest(home)

    def test_deleted_native_pin_paths_are_checked_even_without_a_payload(self):
        for name in ("../outside.zig", "/outside.zig", "src//deleted.zig", "src/./deleted.zig"):
            with self.subTest(name=name):
                home = self.root / ("source-" + str(len(list(self.root.iterdir()))));value = source(home)
                value["native_inputs"]["binding"][name] = None
                refresh(home, value)
                with self.assertRaisesRegex(ValueError, "path|relative"):
                    delivery.source_manifest(home)

    def test_vendor_and_python_closures_are_required(self):
        for name in ("dependencies/cargo/serde-1/.cargo-checksum.json",
                     "dependencies/python/build-1-py3-none-any.whl"):
            with self.subTest(name=name):
                home = self.root / ("source-" + str(len(list(self.root.iterdir()))))
                value = source(home);(home / name).unlink();refresh(home, value)
                with self.assertRaises(ValueError):
                    delivery.source_manifest(home)

    def test_candidate_is_explicitly_not_a_release_version(self):
        home = self.root / "source";value = source(home)
        self.assertEqual(value["versions"]["engine"], "0.0.0")
        self.assertEqual(value["versions"]["native_package"], "0.1.0")
        value["publishable"] = True
        (home / "source-manifest.json").write_bytes(delivery.encoded(value))
        with self.assertRaisesRegex(ValueError, "unsupported"):
            delivery.source_manifest(home)

    def test_offline_export_without_wheels_refuses_before_commands_or_copy(self):
        with mock.patch.object(delivery, "command") as command:
            with self.assertRaisesRegex(ValueError, "prepared Python wheelhouse"):
                delivery.export_source(self.root, self.root, self.root / "output", self.root / "missing-proof",
                                       self.root / "cache", offline=True)
            command.assert_not_called()
        self.assertFalse((self.root / "output").exists())

    def test_invalid_compiled_export_proof_leaves_no_output(self):
        proof = put(self.root, "proof.json", delivery.encoded({"exit": 1, "stable": True}))
        with mock.patch.object(delivery, "command") as command:
            with self.assertRaisesRegex(ValueError, "unqualified"):
                delivery.export_source(self.root, self.root, self.root / "output", proof, self.root / "cache")
            command.assert_not_called()
        self.assertFalse((self.root / "output").exists())

    def test_archive_is_deterministic_and_preserves_executable_mode(self):
        home = self.root / "payload";binary = put(home, "bin/tool", b"executable")
        binary.chmod(0o755);put(home, "LICENSE", b"license")
        one, two = self.root / "one.tar.gz", self.root / "two.tar.gz"
        delivery.create_archive(home, one, delivery.PACKAGE_ROOT)
        os.utime(binary, (123, 456))
        delivery.create_archive(home, two, delivery.PACKAGE_ROOT)
        self.assertEqual(delivery.digest(one), delivery.digest(two))
        extracted = delivery.unpack(one, self.root / "extracted", delivery.PACKAGE_ROOT)
        self.assertEqual((extracted / "bin/tool").read_bytes(), b"executable")
        self.assertTrue((extracted / "bin/tool").stat().st_mode & 0o111)
        with self.assertRaisesRegex(ValueError, "already exists"):
            delivery.create_archive(home, one, delivery.PACKAGE_ROOT)

    def test_archive_path_link_and_duplicate_controls_precede_extraction(self):
        cases = [[("../escape", tarfile.REGTYPE, b"bad")],
                 [(delivery.PACKAGE_ROOT + "/link", tarfile.SYMTYPE, b"")],
                 [(delivery.PACKAGE_ROOT + "/x", tarfile.REGTYPE, b"a"),
                  (delivery.PACKAGE_ROOT + "/x", tarfile.REGTYPE, b"b")]]
        for i, entries in enumerate(cases):
            with self.subTest(i=i):
                fixture = self.root / str(i);fixture.mkdir()
                packed = archive(fixture, entries);out = fixture / "out"
                with self.assertRaises(ValueError):
                    delivery.unpack(packed, out, delivery.PACKAGE_ROOT)
                self.assertFalse(out.exists())

    def test_archive_byte_and_member_budgets_refuse_before_output(self):
        packed = archive(self.root, [(delivery.PACKAGE_ROOT + "/x", tarfile.REGTYPE, b"1234")])
        for setting in ("MAX_BYTES", "MAX_FILES"):
            with self.subTest(setting=setting), mock.patch.object(delivery, setting, 0):
                with self.assertRaisesRegex(ValueError, "resource"):
                    delivery.unpack(packed, self.root / setting, delivery.PACKAGE_ROOT)
                self.assertFalse((self.root / setting).exists())

    def test_target_is_measured_from_executable_bytes(self):
        path = put(self.root, "binary", elf())
        delivery.check_machine(path, "linux-x86_64")
        with self.assertRaisesRegex(ValueError, "target mismatch"):
            delivery.check_machine(path, "macos-arm64")
        self.assertEqual(delivery.machine(b"\xcf\xfa\xed\xfe\x0c\x00\x00\x01"), "macos-arm64")
        self.assertEqual(delivery.machine(elf(183)), "linux-arm64")
        with self.assertRaisesRegex(ValueError, "endianness"):
            delivery.machine(b"\x7fELF\x02\x02" + bytes(58))

    def test_bundle_joins_exact_compiled_and_native_sources(self):
        home = self.root / "source";value = source(home)
        native = put(self.root, "libirgx.a", b"input native archive")
        built = self.root / "bundle";metadata = bundle(built, value, native)
        with mock.patch.object(delivery, "check_machine") as machine:
            delivery.check_bundle(home, built, native, "linux-x86_64")
            self.assertEqual(machine.call_count, 4)
        # Re-hashing the bundle's own modified metadata cannot change the
        # independent source manifest's historical compiled-input identity.
        metadata["identity"]["rust_inputs"]["rust/src/lib.rs"] = "0" * 64
        metadata["identity_sha256"] = hashlib.sha256(delivery.encoded(metadata["identity"])).hexdigest()
        proof = {"exit": 0, "stable": True, **metadata["identity"]}
        put(built, "build.json", delivery.encoded(proof))
        metadata["files"]["build.json"] = delivery.digest(built / "build.json")
        put(built, "bundle.json", delivery.encoded(metadata))
        with mock.patch.object(delivery, "check_machine"), self.assertRaisesRegex(ValueError, "compiled source join"):
            delivery.check_bundle(home, built, native, "linux-x86_64")

    def test_an_older_native_archive_cannot_substitute_for_source_engine(self):
        home = self.root / "source";value = source(home)
        native = put(self.root, "libirgx.a", b"matching native archive")
        built = self.root / "bundle";bundle(built, value, native)
        put(self.root, "libirgx.a", b"older same target, missing additive exports")
        with mock.patch.object(delivery, "check_machine"), self.assertRaisesRegex(ValueError, "source-engine archive"):
            delivery.check_bundle(home, built, native, "linux-x86_64")

    def test_selected_native_proof_joins_exported_producers_and_full_header(self):
        import rust_static_boundary as boundary
        repository = next(parent for parent in Path(__file__).resolve().parents
                          if (parent / "rust/Cargo.toml").is_file())
        header = (Path(__file__).parent / "testdata/irgx-abi2-105.h").read_bytes()
        helper = put(self.root, "source/joints/tool/rust_static_boundary.py", b"retained helper")
        parser = put(self.root, "source/joints/tool/rust_archive.py", b"retained parser")
        put(self.root, "source/irregex/include/irgx.h", header)
        raw = put(self.root, "proof/build/lib/libirgx.a", b"raw original")
        selected = put(self.root, "lib/libirgx.a", b"selected native boundary")
        proof = {"helper_sha256": delivery.digest(helper), "parser_sha256": delivery.digest(parser)}
        put(self.root, "native-boundary.json", delivery.encoded(proof))
        with mock.patch.object(boundary, "verify_archive", return_value={"verified": True}) as verify:
            self.assertEqual(delivery.check_native_boundary(self.root, "linux-x86_64"), {"verified": True})
            args, kwargs = verify.call_args
            self.assertEqual(args[:2], (raw, selected))
            self.assertEqual(kwargs["abi_family"], boundary.IRGX_ABI2)
            self.assertEqual(len(kwargs["exports"]), 105)
        for field in ("helper_sha256", "parser_sha256"):
            put(self.root, "native-boundary.json", delivery.encoded(proof | {field: "0" * 64}))
            with self.subTest(field=field), mock.patch.object(boundary, "verify_archive") as verify:
                with self.assertRaisesRegex(ValueError, "producer/parser source"):
                    delivery.check_native_boundary(self.root, "linux-x86_64")
                verify.assert_not_called()

    def test_image_source_requires_matching_native_family_and_wire_authorities(self):
        home = self.root / "source";source(home)
        self.assertEqual(delivery.source_engine_contract(home),
                         {"native_abi_family": "irgx-abi2-105", "artifact_format": {"version": 2, "schema": 3}})
        put(home, "joints/rust/Cargo.toml", b'[dependencies]\nirgx={features=["source-engine","munch-image"]}\n')
        with self.assertRaisesRegex(ValueError, "dependency and native artifact"):
            delivery.source_engine_contract(home)
        put(home, "joints/rust/src/artifact.rs", b"const VERSION: u32 = 3;\nconst SCHEMA: u32 = 4;\n")
        self.assertEqual(delivery.source_engine_contract(home),
                         {"native_abi_family": "irgx-abi2-108-munch-image1", "artifact_format": {"version": 3, "schema": 4}})
        with mock.patch.object(delivery, "check_bundle", return_value=({}, {})), \
             self.assertRaisesRegex(ValueError, "explicit native family"):
            delivery.pack_candidate(home, self.root / "unused", self.root / "unused.a", self.root / "out.tar.gz",
                                    "linux-x86_64", "native-host", objcopy=self.root / "unused-tool")
        self.assertFalse((self.root / "out.tar.gz").exists())

    def test_image_native_boundary_uses_all108_header_exports_and_refuses105_proof(self):
        import rust_static_boundary as boundary
        header = (delivery.ROOT.parent / "irregex/include/irgx.h").read_bytes()
        helper = put(self.root, "source/joints/tool/rust_static_boundary.py", b"retained helper")
        parser = put(self.root, "source/joints/tool/rust_archive.py", b"retained parser")
        put(self.root, "source/irregex/include/irgx.h", header)
        put(self.root, "proof/build/lib/libirgx.a", b"raw")
        put(self.root, "lib/libirgx.a", b"selected")
        proof = {"helper_sha256": delivery.digest(helper), "parser_sha256": delivery.digest(parser),
                 "abi_family": boundary.IRGX_MUNCH_IMAGE1}
        put(self.root, "native-boundary.json", delivery.encoded(proof))
        with mock.patch.object(boundary, "verify_archive", return_value={"verified": True}) as verify:
            delivery.check_native_boundary(self.root, "linux-x86_64", abi_family=boundary.IRGX_MUNCH_IMAGE1)
            self.assertEqual(len(verify.call_args.kwargs["exports"]), 108)
            self.assertEqual(verify.call_args.kwargs["abi_family"], boundary.IRGX_MUNCH_IMAGE1)
        put(self.root, "native-boundary.json", delivery.encoded(proof | {"abi_family": boundary.IRGX_ABI2}))
        with mock.patch.object(boundary, "verify_archive") as verify, self.assertRaisesRegex(ValueError, "ABI family"):
            delivery.check_native_boundary(self.root, "linux-x86_64", abi_family=boundary.IRGX_MUNCH_IMAGE1)
        verify.assert_not_called()

    def test_extracted_package_rejoins_build_identity_and_actual_native_before_consumers(self):
        home = self.root / "source";value = source(home)
        for name in ("LICENSE", "NOTICE", "include/jnt.h", "test/grammar/json.json"):
            put(home, "joints/" + name)
        refresh(home, value)
        native = put(self.root, "libirgx.a", b"matching native archive")
        built = self.root / "bundle";bundle(built, value, native)
        put(built, "ancillary-proof.json", b"retained build proof")
        original = delivery.read_json(built / "bundle.json")
        original["files"]["ancillary-proof.json"] = delivery.digest(built / "ancillary-proof.json")
        put(built, "bundle.json", delivery.encoded(original))
        packed = self.root / "candidate.tar.gz"
        import rust_static_boundary as boundary
        helper = put(home, "joints/tool/rust_static_boundary.py", b"fixture helper")
        parser = put(home, "joints/tool/rust_archive.py", b"fixture parser")
        put(home, "irregex/include/irgx.h", b"authoritative fixture header")
        refresh(home, value)
        def static(original, output, **kwargs):
            output.write_bytes(original.read_bytes() + (b"isolated native" if kwargs.get("abi_family") == boundary.IRGX_ABI2 else b""))
            return {"helper_sha256": delivery.digest(helper), "parser_sha256": delivery.digest(parser)}
        with mock.patch.object(delivery, "check_machine"), mock.patch.object(delivery, "platform_evidence", return_value={"test": True}), \
             mock.patch.object(boundary, "declared_exports", return_value=("jnt_fixture",)), \
             mock.patch.object(boundary, "transform_archive", side_effect=static), \
             mock.patch.object(delivery, "check_static_boundary", return_value={"test": True}), \
             mock.patch.object(delivery, "check_native_boundary", return_value={"test": True}):
            delivery.pack_candidate(home, built, native, packed, "linux-x86_64", "native-host", objcopy=self.root / "fake-tool")
        extracted = delivery.unpack(packed, self.root / "unpacked", delivery.PACKAGE_ROOT)
        self.assertTrue((extracted / "proof/build/ancillary-proof.json").is_file())
        self.assertEqual((extracted / "proof/build/lib/libirgx.a").read_bytes(), native.read_bytes())
        self.assertNotEqual((extracted / "lib/libirgx.a").read_bytes(), native.read_bytes())
        initial = delivery.read_json(extracted / "manifest.json")
        for field, message in (("build_identity_sha256", "build identity"), ("native_archive_sha256", "raw native archive identity"),
                               ("selected_native_archive_sha256", "selected native archive identity"),
                               ("native_boundary_sha256", "native boundary receipt identity")):
            metadata = dict(initial);metadata[field] = "0" * 64
            put(extracted, "manifest.json", delivery.encoded(metadata))
            path = self.root / (field + ".tar.gz")
            delivery.create_archive(extracted, path, delivery.PACKAGE_ROOT)
            with mock.patch.object(delivery.platform, "system", return_value="Linux"), \
                 mock.patch.object(delivery.platform, "machine", return_value="x86_64"), \
                 mock.patch.object(delivery, "check_machine"), mock.patch.object(delivery, "command") as command:
                with self.assertRaisesRegex(ValueError, message):
                    delivery.verify_candidate(path, self.root / field, "native-host")
                command.assert_not_called()
            self.assertIs(delivery.read_json(self.root / field / "report.json")["pass"], False)

    def test_macho_floor_and_real_dependencies_ignore_dylib_identity(self):
        floor = (0x32).to_bytes(4, "little") + (24).to_bytes(4, "little") + (1).to_bytes(4, "little") \
            + (0x000e0000).to_bytes(4, "little") + bytes(8)
        def load(tag, name):
            body = name.encode() + b"\0"
            return tag.to_bytes(4, "little") + (24 + len(body)).to_bytes(4, "little") + (24).to_bytes(4, "little") + bytes(12) + body
        data = macho(floor, load(0xd, "/private/original/libjnt.dylib"), load(0xc, "/usr/lib/libSystem.B.dylib"))
        result = delivery.macho_metadata(data)
        self.assertEqual(result["minimum_macos"], [14, 0, 0])
        self.assertEqual(result["dependencies"], ["/usr/lib/libSystem.B.dylib"])
        for damaged in (data[:-1], data[:32] + bytes(8)):
            with self.assertRaises(ValueError):
                delivery.macho_metadata(damaged)

    def test_elf_newer_glibc_and_original_search_paths_refuse(self):
        import subprocess
        put(self.root, "bin/joints-rs", elf());put(self.root, "lib/libjnt.so", elf())
        for output, message in ((b"Name: GLIBC_2.40", "GLIBC newer"),
                                (b"(RUNPATH) Library runpath: [/original/checkout]", "search path"),
                                (b"(NEEDED) Shared library: [libfromoriginal.so]", "dependency escapes")):
            with mock.patch.object(delivery.shutil, "which", return_value="readelf"), \
                 mock.patch.object(delivery, "command", return_value=subprocess.CompletedProcess([], 0, output, b"")):
                with self.assertRaisesRegex(ValueError, message):
                    delivery.platform_evidence(self.root, "linux-x86_64", self.root / "logs")

    def test_deployment_never_relabels_changed_elf_or_copied_artifacts(self):
        original = put(self.root, "before.so", elf())
        installed = put(self.root, "after.so", elf() + b"changed")
        with self.assertRaisesRegex(ValueError, "untransformed library"):
            delivery.deploy_library(original, installed, "linux-x86_64", self.root / "logs")
        files = {}
        for name in ("bin/joints-rs", "lib/libjnt.a", "include/jnt.h"):
            files[name] = delivery.digest(put(self.root, name))
        put(self.root, "bin/joints-rs", b"unjoined executable")
        with self.assertRaisesRegex(ValueError, "differs from build proof"):
            delivery.check_deployment(self.root, "linux-x86_64", {"files": files}, self.root / "logs")

    def test_macho_text_section_extent_is_checked_before_hash(self):
        segment = bytearray(152)
        segment[:4] = (0x19).to_bytes(4, "little")
        segment[4:8] = len(segment).to_bytes(4, "little")
        segment[64:68] = (1).to_bytes(4, "little")
        segment[72:78], segment[88:94] = b"__text", b"__TEXT"
        segment[112:120] = (4).to_bytes(8, "little")
        segment[120:124] = (184).to_bytes(4, "little")
        data = macho(bytes(segment)) + b"code"
        measured = delivery.macho_metadata(data, text=True)
        self.assertEqual(measured["text_sections"]["__text"]["sha256"], hashlib.sha256(b"code").hexdigest())
        with self.assertRaisesRegex(ValueError, "section outside"):
            delivery.macho_metadata(data[:-1], text=True)

    def test_failed_installed_check_records_failure_and_runs_no_consumer(self):
        payload = self.root / "payload"
        put(payload, "manifest.json", delivery.encoded({"schema": 2, "kind": "local-rust-candidate",
            "publishable": True, "versions": delivery.VERSIONS}))
        packed = self.root / "candidate.tar.gz"
        delivery.create_archive(payload, packed, delivery.PACKAGE_ROOT)
        out = self.root / "result"
        with mock.patch.object(delivery, "command") as command:
            with self.assertRaisesRegex(ValueError, "publishable"):
                delivery.verify_candidate(packed, out, "native-host")
            command.assert_not_called()
        receipt = json.loads((out / "report.json").read_text())
        self.assertIs(receipt["pass"], False)
        self.assertEqual(receipt["commands"], [])
        self.assertEqual(receipt["archive"]["sha256"], delivery.digest(packed))

    def test_old_package_envelope_is_explicitly_refused_before_consumers(self):
        payload = self.root / "old-package"
        put(payload, "manifest.json", delivery.encoded({"schema": 1, "kind": "local-rust-candidate",
            "publishable": False, "versions": delivery.VERSIONS}))
        packed = self.root / "old.tar.gz"
        delivery.create_archive(payload, packed, delivery.PACKAGE_ROOT)
        output = self.root / "old-check"
        with mock.patch.object(delivery, "command") as command:
            with self.assertRaisesRegex(ValueError, "unsupported"):
                delivery.verify_candidate(packed, output, "native-host")
            command.assert_not_called()
        self.assertIs(delivery.read_json(output / "report.json")["pass"], False)

    def test_default_workspace_summary_requires_positive_unfiltered_execution(self):
        rows = (b"test result: ok. 12 passed; 0 failed; 2 ignored; 0 measured; 0 filtered out; finished in 0.01s\n"
                b"Doc-tests engine\ntest result: ok. 3 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.01s\n")
        summary = delivery.default_test_summary(rows, "1.85.0")
        self.assertEqual((summary["passed"], summary["ignored"], summary["filtered"]), (15, 2, 0))
        self.assertEqual(summary["toolchain"], "1.85.0")
        for text in (b"", rows.replace(b"12 passed", b"0 passed").replace(b"3 passed", b"0 passed"),
                     rows.replace(b"0 failed", b"1 failed", 1),
                     rows.replace(b"0 filtered out", b"1 filtered out", 1)):
            with self.subTest(text=text), self.assertRaisesRegex(ValueError, "missing or failed"):
                delivery.default_test_summary(text, "1.85.0")

    def test_generated_native_client_rejects_unverified_symbol_and_version_spelling(self):
        for compile_name, match_name, version in (("bad\";panic!()", "match", "10.49"),
                                                  ("compile", "../match", "10.49"),
                                                  ("compile", "match", '10.49"')):
            with self.subTest(compile=compile_name, match=match_name, version=version), self.assertRaises(ValueError):
                delivery.native_api_source(compile_name, match_name, version)

    def test_foreign_package_target_refuses_before_compiler_or_install(self):
        payload = self.root / "payload"
        put(payload, "manifest.json", delivery.encoded({"schema": 2, "kind": "local-rust-candidate",
            "publishable": False, "versions": delivery.VERSIONS, "target": "macos-arm64",
            "execution_scope": "native-host"}))
        packed = self.root / "candidate.tar.gz"
        delivery.create_archive(payload, packed, delivery.PACKAGE_ROOT)
        with mock.patch.object(delivery.platform, "system", return_value="Linux"), \
             mock.patch.object(delivery.platform, "machine", return_value="x86_64"), \
             mock.patch.object(delivery, "command") as command:
            with self.assertRaisesRegex(ValueError, "cannot execute"):
                delivery.verify_candidate(packed, self.root / "result", "native-host")
            command.assert_not_called()

    def test_linux_never_inherits_mac_sdk_or_source_resolution(self):
        overrides = {key: "/original/override" for key in ("RUSTC", "RUSTDOC", "CARGO_BUILD_RUSTC",
            "CARGO_BUILD_RUSTDOC", "CARGO_BUILD_TARGET", "CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER",
            "LD_PRELOAD", "DYLD_INSERT_LIBRARIES", "JOINTS_CUSTOMARY", "CARGO_ENCODED_RUSTDOCFLAGS")}
        with mock.patch.object(delivery.platform, "system", return_value="Linux"), \
             mock.patch.dict(os.environ, {"SDKROOT": "/private/MacOSX27.sdk", "PYTHONPATH": "/original/source",
                                          "RUSTFLAGS": "caller flags", **overrides}):
            env = delivery.installed_environment(self.root, None)
            self.assertNotIn("SDKROOT", env)
            self.assertNotIn("PYTHONPATH", env)
            self.assertNotIn("RUSTFLAGS", env)
            for key in overrides:
                self.assertNotIn(key, env)
            self.assertEqual(env["CARGO_NET_OFFLINE"], "true")
            self.assertEqual(env["PCRE2_SYS_STATIC"], "1")
            self.assertEqual(env["LIBPCRE2_8_NO_PKG_CONFIG"], "1")
            self.assertEqual(env["CARGO_HOME"], str(self.root / "cargo-home"))
            with self.assertRaisesRegex(ValueError, "must not inherit"):
                delivery.installed_environment(self.root, self.root)

    def test_one_archive_can_be_checked_in_emulated_and_native_execution_contexts(self):
        payload = self.root / "payload"
        put(payload, "manifest.json", delivery.encoded({"schema": 2, "kind": "local-rust-candidate",
            "publishable": False, "versions": delivery.VERSIONS, "target": "linux-x86_64",
            "execution_scope": "emulated", "files": {}}))
        packed = self.root / "candidate.tar.gz"
        delivery.create_archive(payload, packed, delivery.PACKAGE_ROOT)
        original = delivery.digest(packed)
        for mode in ("emulated", "native-host"):
            output = self.root / mode
            with mock.patch.object(delivery.platform, "system", return_value="Linux"), \
                 mock.patch.object(delivery.platform, "machine", return_value="x86_64"), \
                 mock.patch.object(delivery, "command") as command:
                # This intentionally incomplete fixture gets past both valid
                # scope checks, then refuses its missing payload. It can never
                # claim a successful installed verification.
                with self.assertRaisesRegex(ValueError, "empty/oversized"):
                    delivery.verify_candidate(packed, output, mode)
                command.assert_not_called()
            receipt = delivery.read_json(output / "report.json")
            self.assertEqual(receipt["package_execution_scope"], "emulated")
            self.assertEqual(receipt["execution_scope"], mode)
            self.assertEqual(receipt["archive"]["sha256"], original)
            self.assertIs(receipt["pass"], False)
        self.assertEqual(delivery.digest(packed), original)

    def test_declared_and_actual_execution_modes_are_both_validated(self):
        for i, (declared, actual) in enumerate((("unknown", "native-host"), ("native-host", "unknown"))):
            payload = self.root / ("payload-" + str(i))
            put(payload, "manifest.json", delivery.encoded({"schema": 2, "kind": "local-rust-candidate",
                "publishable": False, "versions": delivery.VERSIONS, "target": "linux-x86_64",
                "execution_scope": declared, "files": {}}))
            packed = self.root / ("candidate-" + str(i) + ".tar.gz")
            delivery.create_archive(payload, packed, delivery.PACKAGE_ROOT)
            with self.subTest(declared=declared, actual=actual), mock.patch.object(delivery, "command") as command:
                with self.assertRaisesRegex(ValueError, "invalid execution scope"):
                    delivery.verify_candidate(packed, self.root / ("check-" + str(i)), actual)
                command.assert_not_called()

    def test_cli_identity_requires_exact_declared_version_backend_and_complete_output(self):
        expected = f"joints-rs {delivery.VERSIONS['cli']} (native Rust)\n".encode()
        delivery.check_cli_identity(expected)
        for output in (
            b"joints-rs 10.0.0 (native Rust)\n",
            b"joints-rs 0.0.01 (native Rust)\n",
            b"joints-rs 0.1.0 (native Rust)\n",
            b"joints 0.0.0 (native Rust)\n",
            b"joints-rs 0.0.0 (native Zig)\n",
            expected.rstrip(b"\n"),
            b"error: selected another runtime\n" + expected,
            expected + b"another runtime followed\n",
            b"\xff" + expected,
        ):
            with self.subTest(output=output), self.assertRaisesRegex(ValueError, "version/backend identity"):
                delivery.check_cli_identity(output)


if __name__ == "__main__":
    unittest.main()

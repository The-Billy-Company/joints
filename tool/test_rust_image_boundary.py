"""Prospective pure controls for the explicit Image1 static boundary family.

All archive bytes and transform commands below are authored or mocked. Native
execution requires a separate gate; importing this module does not run it.
"""
import copy
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

import rust
import rust_static_boundary as boundary
from test_rust import selection_fixture
from test_rust_static_boundary import archive_bytes, elf_object, macho_object


FAMILY = 'irgx-abi2-108-munch-image1'
ADDITIONS = ('irgx_munch_clone_worker', 'irgx_munch_load', 'irgx_munch_save')


def declarations(header):
    text = re.sub(r'/\*.*?\*/|//[^\n]*', '', header.read_text(), flags=re.S)
    return tuple(sorted(re.findall(r'\b(irgx_[a-zA-Z0-9_]+)\s*\(', text)))


class ImageFamily(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.old_header = Path(__file__).parent / 'testdata/irgx-abi2-105.h'
        self.assertEqual(hashlib.sha256(self.old_header.read_bytes()).hexdigest(),
                         '0909688d9a22c752483031c7781feb2965926eaf773b40d298ea9b39e7fbdf74')
        self.old = declarations(self.old_header)
        self.assertEqual(len(self.old), 105)
        repository = next(p for p in Path(__file__).resolve().parents
                          if (p / 'rust/Cargo.toml').is_file())
        self.header = repository.parent / 'irregex/include/irgx.h'
        self.names = tuple(sorted(self.old + ADDITIONS))
        self.assertEqual(len(set(self.names)), 108)

    def put(self, name, data):
        path = self.root / name;path.write_bytes(data);return path

    def proof(self, target, names=None):
        bsd = target == 'macos-arm64'
        exports = self.names if not bsd else tuple('_' + n for n in self.names)
        chosen = exports if names is None else names
        private = {'owned': 'pcre2_compile_8'} if not bsd else {'_owned': '_pcre2_compile_8'}
        make = macho_object if bsd else elf_object
        data = make(public_names=chosen, private_names=private)
        rows = [(n, 0) for n in chosen]
        original = self.put(target + '-raw.a', archive_bytes([('native.o', data)], rows,
                            bsd=bsd, sorted_toc=bsd))
        planner = boundary._plan_macho if bsd else boundary._plan_elf
        _, _, plan = planner(original, exports, abi_family=FAMILY)
        changed = make(plan['mapping'], public_names=chosen, private_names=private)
        derivative = self.put(target + '-selected.a', archive_bytes([('native.o', changed)], rows,
                              bsd=bsd, sorted_toc=bsd))
        facts = boundary._facts(original, derivative, target, exports, abi_family=FAMILY)
        receipt = {'schema': 1, 'kind': 'opaque-native-only-C-static-boundary',
                   'target': target, 'abi_family': FAMILY, 'machine_code_only': True,
                   'before_sha256': facts['before_sha256'], 'after_sha256': facts['after_sha256'],
                   'facts': facts}
        return original, derivative, exports, plan, receipt

    def test_authoritative108_is_exact_old105_plus_three_and_never_auto_upgrades(self):
        self.assertEqual(boundary.IRGX_MUNCH_IMAGE1, FAMILY)
        self.assertEqual(declarations(self.header), self.names)
        for target in ('linux-x86_64', 'macos-arm64'):
            prefix = '_' if target == 'macos-arm64' else ''
            self.assertEqual(boundary.declared_exports(self.header, target, abi_family=FAMILY),
                             tuple(prefix + n for n in self.names))
            self.assertEqual(boundary.declared_exports(self.old_header, target, abi_family=boundary.IRGX_ABI2),
                             tuple(prefix + n for n in self.old))
            for header, family in ((self.header, boundary.IRGX_ABI2), (self.old_header, FAMILY)):
                with self.subTest(target=target, family=family), self.assertRaisesRegex(ValueError, 'roster'):
                    boundary.declared_exports(header, target, abi_family=family)

    def test_missing_duplicate_extra_or_substituted_image_declarations_refuse(self):
        source = self.header.read_text()
        for i, text in enumerate((source.replace('irgx_munch_load(', 'not_image_load('),
                                  source + '\nint irgx_munch_save(void);\n',
                                  source + '\nint irgx_future(void);\n',
                                  source.replace('irgx_munch_save(', 'irgx_substitute('))):
            with self.subTest(i=i), self.assertRaisesRegex(ValueError, 'roster'):
                boundary.declared_exports(self.put(str(i) + '.h', text.encode()),
                                          'linux-x86_64', abi_family=FAMILY)

    def test_both_formats_preserve_all108_and_namespace_private_backend(self):
        for target in ('linux-x86_64', 'macos-arm64'):
            with self.subTest(target=target):
                original, selected, exports, plan, receipt = self.proof(target)
                self.assertEqual(len(plan['c_exports']), 108)
                private = '_pcre2_compile_8' if target == 'macos-arm64' else 'pcre2_compile_8'
                self.assertIn(private, plan['mapping'])
                self.assertTrue(set(exports).isdisjoint(plan['mapping']))
                boundary.verify_archive(original, selected, receipt, target=target,
                                        exports=exports, abi_family=FAMILY)
                for family in (boundary.IRGX_ABI2, boundary.JNT_ABI2):
                    with self.assertRaisesRegex(ValueError, 'family'):
                        boundary.verify_archive(original, selected, receipt, target=target,
                                                exports=exports, abi_family=family)

    def test_missing_image_object_export_refuses_for_both_formats(self):
        for target in ('linux-x86_64', 'macos-arm64'):
            names = self.names if target == 'linux-x86_64' else tuple('_' + n for n in self.names)
            with self.subTest(target=target), self.assertRaises(ValueError):
                self.proof(target, tuple(n for n in names if not n.endswith('irgx_munch_load')))

    def test_image_producer_parser_drift_never_publishes(self):
        original, selected, exports, _, _ = self.proof('linux-x86_64')
        tool = self.put('objcopy', b'authored tool; never executed')
        parser = Path(boundary.rust_archive.__file__).resolve()
        digest = boundary._digest;reads = []
        def transform(_original, staged, *_args, **_kwargs):
            staged.write_bytes(selected.read_bytes())
            return {'tool': {'version': 'LLVM authored', 'sha256': digest(tool)}}
        def question(path):
            if Path(path).resolve() == parser:
                reads.append(path)
                if len(reads) > 1:return '0' * 64
            return digest(path)
        output = self.root / 'must-not-publish.a'
        with mock.patch.object(boundary, '_transform_elf', side_effect=transform), \
                mock.patch.object(boundary, '_digest', side_effect=question):
            with self.assertRaisesRegex(ValueError, 'parser source drift'):
                boundary.transform_archive(original, output, target='linux-x86_64',
                    exports=exports, objcopy=tool, work=self.root / 'work', abi_family=FAMILY)
        self.assertEqual(len(reads), 2)
        self.assertFalse(output.exists())


class ImageNativeSelection(unittest.TestCase):
    def test_cold_warm_image_cache_is_disjoint_and_default105_stays_default(self):
        with selection_fixture() as f:
            old = rust.native_link(f['raw'], f['native'], f['tools'])
            image = rust.native_link(f['raw'], f['native'], f['tools'], abi_family=FAMILY)
            warm = rust.native_link(f['raw'], f['native'], f['tools'], abi_family=FAMILY)
            self.assertEqual(old['identity']['abi_family'], boundary.IRGX_ABI2)
            self.assertEqual(image['identity']['abi_family'], FAMILY)
            self.assertNotEqual(old['root'], image['root'])
            self.assertNotEqual(old['cache_key'], image['cache_key'])
            self.assertEqual(Path(image['root']).parent.name, 'native-boundary-munch-image1')
            self.assertFalse(image['cache_hit']);self.assertTrue(warm['cache_hit'])
            self.assertEqual(f['transform'].call_count, 2)
            self.assertEqual(f['verify'].call_args.kwargs['abi_family'], FAMILY)
            for selection, family in ((old, FAMILY), (image, boundary.IRGX_ABI2)):
                with self.assertRaisesRegex(ValueError, 'identity'):
                    rust.check_native_link(selection, f['native'], f['tools'], abi_family=family)

    def test_image_proof_cannot_relabel_the_selected_family(self):
        with selection_fixture() as f:
            image = rust.native_link(f['raw'], f['native'], f['tools'], abi_family=FAMILY)
            proof = Path(image['root']) / 'proof.json'
            value = json.loads(proof.read_bytes());value['abi_family'] = boundary.IRGX_ABI2
            proof.write_bytes(rust.m.encoded(value))
            changed = dict(image, proof_sha256=rust.m.sha(proof.read_bytes()))
            with self.assertRaisesRegex(ValueError, 'proof ABI family'):
                rust.check_native_link(changed, f['native'], f['tools'], abi_family=FAMILY)

    def test_actual_image_cargo_selection_has_isolated_raw_and_receipt(self):
        with selection_fixture() as f:
            image_raw = f['prefix'].parent / 'source-irgx-munch-image1'
            (image_raw / 'lib').mkdir(parents=True)
            shutil.copy2(f['raw'], image_raw / 'lib/libirgx.a')
            (image_raw / 'provenance.json').write_bytes(rust.m.encoded(f['native']))
            seen = []
            def cargo(argv, **kwargs):
                seen.append(copy.deepcopy(kwargs['env']))
                self.assertIn('irgx/munch-image', argv)
                self.assertNotEqual(Path(kwargs['env']['IRGX_LIB_DIR']), image_raw / 'lib')
                return subprocess.CompletedProcess(argv, 0)
            with mock.patch.object(rust.subprocess, 'run', side_effect=cargo):
                self.assertEqual(rust.run('test', ['--features', 'irgx/munch-image'], abi_family=FAMILY), 0)
            receipt = f['prefix'].parent / 'last-cargo-munch-image1.json'
            value = json.loads(receipt.read_bytes())
            self.assertTrue(value['stable'])
            self.assertEqual(value['native_link']['identity']['abi_family'], FAMILY)
            self.assertEqual(seen[0]['IRGX_LIB_DIR'], value['native_link']['library_dir'])
            self.assertFalse(f['last'].exists())
            self.assertEqual(f['raw'].read_bytes(), b'fresh raw native fixture')
            self.assertEqual(f['historical'].read_bytes(), b'historical original stays unchanged')

    def test_unknown_or_jnt_family_refuses_before_native_selection(self):
        for family in ('irgx-abi2-109', boundary.JNT_ABI2):
            with self.subTest(family=family), mock.patch.object(rust, 'boundary_tools') as tools:
                with self.assertRaisesRegex(ValueError, 'family'):
                    rust.run('check', [], abi_family=family)
                tools.assert_not_called()

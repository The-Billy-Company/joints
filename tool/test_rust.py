"""The native build may not launder a stale archive into a successful Cargo run."""
import subprocess
from contextlib import nullcontext, contextmanager, ExitStack
import json
import copy
import inspect
import re
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import rust
import rust_archive
import rust_static_boundary as boundary


class NativeBuild(unittest.TestCase):
    def test_every_workspace_member_and_header_is_retained_but_build_outputs_are_not(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "rust/ffi/src").mkdir(parents=True)
            (root / "rust/ffi/tests").mkdir()
            (root / "rust/target").mkdir()
            (root / "include").mkdir()
            files = {
                "rust/Cargo.toml": '[workspace]\nmembers=[".","ffi"]\n',
                "rust/Cargo.lock": "lock",
                "grammars.toml": "pins",
                "rust/ffi/Cargo.toml": "member",
                "rust/ffi/src/lib.rs": 'include_bytes!("../../../upstream/grammars/working.json");',
                "rust/ffi/tests/abi.c": "caller",
                "include/jnt.h": "ABI",
                "upstream/grammars/working.json": "pinned grammar",
                "rust/target/generated.rs": "must not enter the source snapshot",
            }
            for relative, content in files.items():
                (root / relative).parent.mkdir(parents=True, exist_ok=True)
                (root / relative).write_text(content)
            with patch.object(rust.m, "ROOT", root):
                got = rust.rust_inputs()
                self.assertEqual(set(got), set(files) - {"rust/target/generated.rs"})
                (root / "rust/ffi/src/lib.rs").write_text("changed boundary")
                self.assertNotEqual(got, rust.rust_inputs())

    def test_every_literal_compile_time_include_is_retained(self):
        files = rust.rust_inputs()
        includes = 0
        for relative in files:
            if not relative.endswith(".rs"):
                continue
            source = rust.m.ROOT / relative
            for match in re.finditer(r'include_(?:str|bytes)!\(\s*"([^"]+)"', source.read_text()):
                target = (source.parent / match[1]).resolve().relative_to(rust.m.ROOT)
                self.assertIn(str(target), files, f"unretained compile input in {relative}")
                includes += 1
        self.assertGreater(includes, 0, "the include coverage check inspected no inputs")

    def test_toolchain_records_selected_compiler_and_only_compile_controls(self):
        environment = {"RUSTC":"selected-rustc", "RUSTFLAGS":"-C opt-level=2",
                       "UNRELATED_SECRET":"must not be retained"}
        with (patch.dict(rust.os.environ, environment, clear=True),
              patch.object(rust.subprocess, "run", side_effect=[
                  subprocess.CompletedProcess([], 0, stdout="rustc identity\n"),
                  subprocess.CompletedProcess([], 0, stdout="cargo identity\n"),
              ]) as run):
            record = rust.rust_toolchain()
        self.assertEqual(run.call_args_list[0].args[0],
                         ["selected-rustc", "--version", "--verbose"])
        self.assertEqual(record, {"rustc":"rustc identity", "cargo":"cargo identity",
                                  "environment":{"RUSTC":"selected-rustc",
                                                 "RUSTFLAGS":"-C opt-level=2"}})

    def test_source_snapshots_preserve_uncommitted_revisions_without_overwriting(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory) / "source"
            home.mkdir()
            path = home / "engine.rs"
            path.write_bytes(b"first revision")
            with patch.object(rust, "PREFIX", Path(directory) / "build/irgx"):
                first = rust.preserve_sources(home, {"engine.rs": rust.m.sha(path.read_bytes())}, "joints")
                path.write_bytes(b"second revision")
                second = rust.preserve_sources(home, {"engine.rs": rust.m.sha(path.read_bytes())}, "joints")
            self.assertNotEqual(first, second)
            self.assertEqual((Path(first) / "engine.rs").read_bytes(), b"first revision")
            self.assertEqual((Path(second) / "engine.rs").read_bytes(), b"second revision")

    def test_source_drift_or_modified_snapshot_refuses_attribution(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory) / "source"
            home.mkdir()
            path = home / "engine.rs"
            path.write_bytes(b"original")
            files = {"engine.rs": rust.m.sha(path.read_bytes()), "deleted.rs": None}
            with patch.object(rust, "PREFIX", Path(directory) / "build/irgx"):
                retained = Path(rust.preserve_sources(home, files, "joints"))
                path.write_bytes(b"changed during capture")
                with self.assertRaisesRegex(ValueError, "source changed"):
                    rust.preserve_sources(home, files, "joints")
                path.write_bytes(b"original")
                (retained / "engine.rs").write_bytes(b"tampered snapshot")
                with self.assertRaisesRegex(ValueError, "retained source was modified"):
                    rust.preserve_sources(home, files, "joints")

    def test_failed_source_build_never_executes_cargo(self):
        with (patch.object(rust, "inputs", return_value={}),
              patch.object(rust, "boundary_tools", return_value={}),
              patch.object(rust, "build_lock", return_value=nullcontext()),
              patch.object(rust.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "zig")) as run):
            with self.assertRaises(subprocess.CalledProcessError):
                rust.run("test", [])
            self.assertEqual(run.call_count, 1)
            self.assertEqual(run.call_args.args[0][0], "zig")

    def test_changed_sources_refuse_even_with_an_existing_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            prefix = Path(directory)
            (prefix / "lib").mkdir()
            (prefix / "lib/libirgx.a").write_bytes(b"old archive")
            with (patch.object(rust, "inputs", side_effect=[{"source":1}, {"source":2}]),
                  patch.object(rust.subprocess, "run")):
                with self.assertRaisesRegex(ValueError, "sources changed"):
                    rust.native_environment(prefix)
            self.assertFalse((prefix / "provenance.json").exists())

    def test_missing_output_is_not_a_successful_build(self):
        with tempfile.TemporaryDirectory() as directory:
            with (patch.object(rust, "inputs", return_value={}),
                  patch.object(rust.subprocess, "run")):
                with self.assertRaisesRegex(ValueError, "omitted"):
                    rust.native_environment(Path(directory))

    def test_formatting_does_not_build_native_code(self):
        with (patch.object(rust, "native_environment") as native,
              patch.object(rust, "boundary_tools", side_effect=AssertionError("fmt discovered native tools")),
              patch.object(rust, "build_lock", side_effect=AssertionError("fmt acquired native lock")),
              patch.object(rust.subprocess, "run", return_value=subprocess.CompletedProcess([], 0))):
            self.assertEqual(rust.run("fmt", ["--check"]), 0)
            native.assert_not_called()

    def test_mutation_during_a_successful_cargo_run_refuses_gate_attribution(self):
        for change in ('source', 'raw', 'selected', 'proof', 'header', 'objcopy', 'producer', 'producer_log'):
            with self.subTest(change=change), selection_fixture() as f:
                def cargo(*args, **kwargs):
                    if change == 'source': f['inputs'].return_value = {'changed': True}
                    elif change == 'raw': f['raw'].write_bytes(b'replaced raw archive')
                    elif change == 'selected': Path(kwargs['env']['IRGX_LIB_DIR'], 'libirgx.a').write_bytes(b'replaced selected archive')
                    elif change == 'proof': next(f['cache'].glob('*/proof.json')).write_bytes(b'changed proof')
                    elif change == 'header': f['header'].write_bytes(b'changed authoritative header')
                    elif change == 'objcopy': f['objcopy'].write_bytes(b'changed selected tool')
                    elif change == 'producer': f['producer'].return_value = {'changed producer': '0' * 64}
                    elif change == 'producer_log': next(f['cache'].glob('*/proof-work/logs/000.stdout')).write_bytes(b'changed producer log')
                    return subprocess.CompletedProcess([], 0)
                with patch.object(rust.subprocess, 'run', side_effect=cargo):
                    with self.assertRaisesRegex(ValueError, 'gate attribution refused'):
                        rust.run('test', [])
                record = json.loads(f['last'].read_bytes())
                self.assertEqual(record['exit'], 0)
                self.assertFalse(record['stable'])
                self.assertTrue(record['native_link_error'])
                self.assertIn('native_link', record)
                self.assertEqual(record['toolchain'], {'rustc': 'fixture'})


@contextmanager
def selection_fixture():
    """Mock ONLY the native producer/semantic verifier; exercise actual cache/run custody.

    Codec correctness belongs to the authored ELF/Mach-O tests. These fixture
    archives deliberately are not native objects and no process can execute.
    """
    with tempfile.TemporaryDirectory() as directory, ExitStack() as stack:
        home = Path(directory);source = home / 'source';source.mkdir()
        (source / 'engine.rs').write_bytes(b'fixture runtime source')
        native_home = home / 'irregex';header = native_home / 'include/irgx.h'
        header.parent.mkdir(parents=True);header.write_bytes(b'fixture authoritative header')
        prefix = home / 'build/irgx';(prefix / 'lib').mkdir(parents=True)
        historical = prefix / 'lib/libirgx.a';historical.write_bytes(b'historical original stays unchanged')
        raw_prefix = home / 'build/source-irgx';raw = raw_prefix / 'lib/libirgx.a';raw.parent.mkdir(parents=True)
        raw.write_bytes(b'fresh raw native fixture')
        objcopy = home / 'llvm-objcopy';objcopy.write_bytes(b'fixture selected LLVM tool')
        tools = {'target': 'linux-x86_64', 'objcopy': {'path': str(objcopy),
            'sha256': rust.m.sha(objcopy.read_bytes()), 'version': 'LLVM fixture'}}
        native_inputs = {'native': {'commit': 'fixture commit', 'source_sha256': '1' * 64,
            'files': {'include/irgx.h': rust.m.sha(header.read_bytes())}}, 'binding': {}}
        native = {'inputs': native_inputs, 'archive_sha256': rust.m.sha(raw.read_bytes()),
            'command': ['fixture native producer'], 'sources': 'fixture retained raw source'}
        (raw_prefix / 'provenance.json').write_bytes(rust.m.encoded(native))
        producer_inputs = {str(Path(p).resolve()): rust.m.sha(Path(p).read_bytes())
            for p in (rust.__file__, boundary.__file__, rust_archive.__file__)}
        def transform(original, output, **kwargs):
            output.parent.mkdir(parents=True, exist_ok=True);output.write_bytes(b'checked native boundary fixture')
            # Retained fixture logs model the producer contract without executing a tool.
            logs = kwargs['work'] / 'logs';logs.mkdir(parents=True)
            stdout = logs / '000.stdout';stderr = logs / '000.stderr'
            stdout.write_bytes(b'fixture namespace output');stderr.write_bytes(b'')
            command = {'argv': [tools['objcopy']['path'], '--fixture-only'], 'cwd': str(kwargs['work']), 'exit': 0,
                'stdout': {'path': str(stdout), 'sha256': rust.m.sha(stdout.read_bytes())},
                'stderr': {'path': str(stderr), 'sha256': rust.m.sha(stderr.read_bytes())}}
            return {'schema': 1, 'abi_family': kwargs['abi_family'],
                'helper_sha256': producer_inputs[str(Path(boundary.__file__).resolve())],
                'parser_sha256': producer_inputs[str(Path(rust_archive.__file__).resolve())],
                'transform': {'tool': copy.deepcopy(tools['objcopy']), 'commands': [command]},
                'before_sha256': rust.m.sha(original.read_bytes()),
                'after_sha256': rust.m.sha(output.read_bytes())}
        stack.enter_context(patch.object(rust, 'PREFIX', prefix))
        stack.enter_context(patch.object(rust, 'RAW_PREFIX', raw_prefix))
        stack.enter_context(patch.object(rust, 'IRREGEX', native_home))
        stack.enter_context(patch.object(rust.m, 'ROOT', source))
        stack.enter_context(patch.object(rust, 'build_lock', return_value=nullcontext()))
        stack.enter_context(patch.object(rust, 'boundary_tools', return_value=tools))
        native_env = stack.enter_context(patch.object(rust, 'native_environment', return_value={'IRGX_LIB_DIR': str(raw.parent)}))
        input_mock = stack.enter_context(patch.object(rust, 'inputs', return_value=copy.deepcopy(native_inputs)))
        runtime_mock = stack.enter_context(patch.object(rust, 'rust_inputs', return_value={'engine.rs': rust.m.sha((source / 'engine.rs').read_bytes())}))
        producer_mock = stack.enter_context(patch.object(rust, 'producer_inputs', return_value=producer_inputs))
        stack.enter_context(patch.object(rust, 'rust_toolchain', return_value={'rustc': 'fixture'}))
        transform_mock = stack.enter_context(patch.object(boundary, 'transform_archive', side_effect=transform))
        verify_mock = stack.enter_context(patch.object(boundary, 'verify_archive', return_value={}))
        stack.enter_context(patch.object(boundary, 'declared_exports', return_value=('irgx_fixture',)))
        yield {'home': home, 'source': source, 'prefix': prefix, 'historical': historical, 'raw_prefix': raw_prefix,
            'raw': raw, 'native': native, 'tools': tools, 'header': header, 'objcopy': objcopy,
            'cache': prefix.parent / 'native-boundary', 'last': prefix.parent / 'last-cargo.json',
            'inputs': input_mock, 'runtime': runtime_mock, 'producer': producer_mock, 'native_env': native_env,
            'transform': transform_mock, 'transform_function': transform, 'verify': verify_mock}


class NativeSelection(unittest.TestCase):
    def test_direct_native_build_default_never_targets_historical_archive(self):
        actual = inspect.signature(rust.native_environment).parameters['prefix'].default
        self.assertEqual(actual, rust.RAW_PREFIX)
        self.assertNotEqual(actual, rust.PREFIX)

    def test_cold_and_warm_cache_recompute_proof_keep_original_and_historical_producer(self):
        with selection_fixture() as f:
            original = f['historical'].read_bytes()
            first = rust.native_link(f['raw'], f['native'], f['tools'])
            self.assertFalse(first['cache_hit'])
            self.assertNotEqual(Path(first['library_dir']), f['raw'].parent)
            self.assertEqual(Path(first['root'], 'original/libirgx.a').read_bytes(), f['raw'].read_bytes())
            second_native = f['native'] | {'command': ['later raw producer with identical bytes']}
            second = rust.native_link(f['raw'], second_native, f['tools'])
            self.assertTrue(second['cache_hit'])
            self.assertEqual(first['cache_key'], second['cache_key'])
            self.assertEqual(second['raw_provenance']['command'], f['native']['command'])
            self.assertEqual(f['transform'].call_count, 1)
            self.assertGreaterEqual(f['verify'].call_count, 3)
            self.assertEqual(f['historical'].read_bytes(), original)

    def test_cache_publication_preserves_relocatable_producer_log_custody(self):
        with selection_fixture() as f:
            first = rust.native_link(f['raw'], f['native'], f['tools'])
            root = Path(first['root']);produced = Path(first['production_root'])
            self.assertNotEqual(root, produced);self.assertFalse(produced.exists())
            proof = json.loads((root / 'proof.json').read_bytes())
            record = proof['transform']['commands'][0]
            for channel in ('stdout', 'stderr'):
                log = record[channel];relative = Path(log['path']).relative_to(produced)
                retained = root / relative
                self.assertEqual(rust.m.sha(retained.read_bytes()), log['sha256'])
                self.assertEqual(first['proof_files'][str(relative)], log['sha256'])
            second = rust.native_link(f['raw'], f['native'], f['tools'])
            self.assertTrue(second['cache_hit']);self.assertEqual(second['proof_files'], first['proof_files'])
            self.assertEqual(f['transform'].call_count, 1)

    def test_missing_or_corrupt_cached_producer_log_refuses_before_cargo(self):
        for damage in ('missing', 'corrupt'):
            with self.subTest(damage=damage), selection_fixture() as f:
                selected = rust.native_link(f['raw'], f['native'], f['tools'])
                raw = f['raw'].read_bytes();path = Path(selected['root']) / 'proof-work/logs/000.stdout'
                if damage == 'missing': path.unlink()
                else: path.write_bytes(b'corrupt retained producer log')
                with patch.object(rust.subprocess, 'run') as cargo:
                    with self.assertRaisesRegex(ValueError, 'proof payload|producer log'):
                        rust.run('test', [])
                cargo.assert_not_called();self.assertEqual(f['raw'].read_bytes(), raw)
                self.assertEqual(f['transform'].call_count, 1)
                if damage == 'missing': self.assertFalse(path.exists())
                else: self.assertEqual(path.read_bytes(), b'corrupt retained producer log')

    def test_actual_cargo_environment_and_record_select_verified_derivative(self):
        with selection_fixture() as f:
            seen = []
            def cargo(command, **kwargs):
                seen.append(copy.deepcopy(kwargs['env']))
                return subprocess.CompletedProcess(command, 0)
            with patch.object(rust.subprocess, 'run', side_effect=cargo):
                self.assertEqual(rust.run('test', ['--workspace', '--locked']), 0)
            record = json.loads(f['last'].read_bytes())
            self.assertTrue(record['stable'])
            self.assertEqual(record['native'], f['native'])
            self.assertEqual(seen[0]['IRGX_LIB_DIR'], record['native_link']['library_dir'])
            self.assertEqual(record['native_link_environment']['IRGX_LIB_DIR'], seen[0]['IRGX_LIB_DIR'])
            self.assertNotEqual(Path(seen[0]['IRGX_LIB_DIR']), f['raw'].parent)
            self.assertEqual(f['historical'].read_bytes(), b'historical original stays unchanged')
            f['native_env'].assert_called_once_with(f['raw_prefix'])

    def test_partial_and_corrupt_cache_refuse_without_overwrite_or_raw_fallback(self):
        for change in ('selected', 'proof', 'selection', 'raw_copy', 'header_copy'):
            for damage in ('missing', 'corrupt'):
                with self.subTest(change=change, damage=damage), selection_fixture() as f:
                    selected = rust.native_link(f['raw'], f['native'], f['tools']);root = Path(selected['root'])
                    path = {'selected': root / 'lib/libirgx.a', 'proof': root / 'proof.json',
                        'selection': root / 'selection.json', 'raw_copy': root / 'original/libirgx.a',
                        'header_copy': root / 'original/irgx.h'}[change]
                    if damage == 'missing': path.unlink()
                    else: path.write_bytes(b'corrupt retained cache artifact')
                    with self.assertRaises((ValueError, OSError)):
                        rust.native_link(f['raw'], f['native'], f['tools'])
                    if damage == 'missing': self.assertFalse(path.exists())
                    else: self.assertEqual(path.read_bytes(), b'corrupt retained cache artifact')
                    self.assertEqual(f['transform'].call_count, 1)

    def test_unchecked_raw_directory_cannot_replace_verified_link_selection(self):
        with selection_fixture() as f:
            selected = rust.native_link(f['raw'], f['native'], f['tools'])
            wrong = selected | {'library_dir': str(f['raw'].parent)}
            with (patch.object(rust, 'native_link', return_value=wrong),
                  patch.object(rust.subprocess, 'run') as cargo):
                with self.assertRaisesRegex(ValueError, 'IRGX_LIB_DIR'):
                    rust.run('test', [])
            cargo.assert_not_called()

    def test_coherent_wrong_actual_tool_or_parser_receipt_refuses(self):
        for change in ('tool', 'parser'):
            with self.subTest(change=change), selection_fixture() as f:
                selected = rust.native_link(f['raw'], f['native'], f['tools']);root = Path(selected['root'])
                proof = json.loads((root / 'proof.json').read_bytes())
                if change == 'tool': proof['transform']['tool']['sha256'] = '0' * 64
                else: proof['parser_sha256'] = '0' * 64
                (root / 'proof.json').write_bytes(rust.m.encoded(proof))
                stored = json.loads((root / 'selection.json').read_bytes())
                stored['proof_sha256'] = rust.m.sha((root / 'proof.json').read_bytes())
                (root / 'selection.json').write_bytes(rust.m.encoded(stored))
                with self.assertRaisesRegex(ValueError, 'producer|parser|tool'):
                    rust.native_link(f['raw'], f['native'], f['tools'])
                self.assertEqual(f['transform'].call_count, 1)

    def test_failed_transform_preserves_attempt_and_never_runs_cargo(self):
        with selection_fixture() as f:
            f['transform'].side_effect = ValueError('fixture transform refused')
            with patch.object(rust.subprocess, 'run') as cargo:
                with self.assertRaisesRegex(ValueError, 'transform refused'):
                    rust.run('test', [])
            cargo.assert_not_called()
            failures = list(f['cache'].glob('attempt-*/failure.json'))
            self.assertEqual(len(failures), 1)
            self.assertFalse(json.loads(failures[0].read_bytes())['pass'])
            self.assertEqual(list(f['cache'].glob('*/selection.json')), [])

    def test_cargo_failure_stays_failed_with_stable_provenance(self):
        with selection_fixture() as f, patch.object(rust.subprocess, 'run', return_value=subprocess.CompletedProcess([], 7)):
            self.assertEqual(rust.run('test', []), 7)
            record = json.loads(f['last'].read_bytes())
            self.assertEqual(record['exit'], 7)
            self.assertTrue(record['stable'])

    def test_postcargo_read_errors_and_same_bytes_metadata_symlink_record_unstable(self):
        for change in ('deleted_raw', 'runtime_error', 'metadata_symlink'):
            with self.subTest(change=change), selection_fixture() as f:
                def cargo(command, **kwargs):
                    if change == 'deleted_raw': f['raw'].unlink()
                    elif change == 'runtime_error': f['runtime'].side_effect = OSError('runtime source disappeared')
                    else:
                        path = next(f['cache'].glob('*/selection.json'))
                        copy = path.with_name('metadata-copy.json');copy.write_bytes(path.read_bytes())
                        path.unlink();path.symlink_to(copy.name)
                    return subprocess.CompletedProcess(command, 0)
                with patch.object(rust.subprocess, 'run', side_effect=cargo):
                    with self.assertRaisesRegex(ValueError, 'gate attribution refused'):
                        rust.run('test', [])
                record = json.loads(f['last'].read_bytes())
                self.assertFalse(record['stable']);self.assertEqual(record['exit'], 0)
                self.assertTrue(record['native_link_error'])

    def test_discovery_uses_selected_rustc_sysroot_and_refuses_gnu_or_changed_tool(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory);host = 'x86_64-unknown-linux-gnu'
            tool = root / 'lib/rustlib' / host / 'bin/llvm-objcopy';tool.parent.mkdir(parents=True)
            tool.write_bytes(b'fixture LLVM executable')
            answers = [subprocess.CompletedProcess([], 0, stdout=str(root) + '\n'),
                subprocess.CompletedProcess([], 0, stdout='rustc fixture\nhost: ' + host + '\n'),
                subprocess.CompletedProcess([], 0, stdout='LLVM fixture\n')]
            with (patch.object(rust.platform, 'system', return_value='Linux'),
                  patch.object(rust.platform, 'machine', return_value='x86_64'),
                  patch.object(rust.shutil, 'which', return_value=None),
                  patch.dict(rust.os.environ, {'RUSTC': 'explicit-rustc'}, clear=True),
                  patch.object(rust.subprocess, 'run', side_effect=answers) as run):
                selected = rust.boundary_tools()
            self.assertEqual(selected['objcopy']['path'], str(tool.resolve()))
            self.assertEqual([c.args[0] for c in run.call_args_list],
                [['explicit-rustc', '--print', 'sysroot'], ['explicit-rustc', '-Vv'], [str(tool.resolve()), '--version']])
            for kind in ('gnu', 'mutation'):
                with self.subTest(kind=kind):
                    def identity(*args, **kwargs):
                        if kind == 'mutation': tool.write_bytes(tool.read_bytes() + b'changed')
                        return subprocess.CompletedProcess([], 0, stdout='GNU objcopy' if kind == 'gnu' else 'LLVM fixture')
                    with (patch.object(rust.platform, 'system', return_value='Linux'),
                          patch.object(rust.platform, 'machine', return_value='x86_64'),
                          patch.object(rust.subprocess, 'run', side_effect=identity)):
                        with self.assertRaisesRegex(ValueError, 'LLVM|changed during discovery'):
                            rust.boundary_tools(objcopy=tool)

    def test_build_lock_spans_production_cargo_and_final_attestation(self):
        with selection_fixture() as f:
            active = [];events = []
            @contextmanager
            def lock():
                active.append(True);events.append('enter')
                try: yield
                finally: active.pop();events.append('exit')
            def native(*args):
                self.assertTrue(active);events.append('native')
                return {'IRGX_LIB_DIR': str(f['raw'].parent)}
            def transform(*args, **kwargs):
                self.assertTrue(active);events.append('transform')
                return f['transform_function'](*args, **kwargs)
            def cargo(command, **kwargs):
                self.assertTrue(active);events.append('cargo')
                return subprocess.CompletedProcess(command, 0)
            write = rust.m.write
            def written(root, relative, data):
                if relative == 'last-cargo.json':
                    self.assertTrue(active);events.append('attest')
                return write(root, relative, data)
            f['native_env'].side_effect = native;f['transform'].side_effect = transform
            with (patch.object(rust, 'build_lock', lock), patch.object(rust.subprocess, 'run', side_effect=cargo),
                  patch.object(rust.m, 'write', side_effect=written)):
                self.assertEqual(rust.run('test', []), 0)
            self.assertEqual(events, ['enter', 'native', 'transform', 'cargo', 'attest', 'exit'])

    def test_tombstones_reject_files_directories_and_dangling_symlinks(self):
        for kind in ('file', 'directory', 'dangling_symlink'):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as directory:
                root = Path(directory);home = root / 'source';home.mkdir();deleted = home / 'deleted.rs'
                if kind == 'file': deleted.write_bytes(b'resurrected')
                elif kind == 'directory': deleted.mkdir()
                else: deleted.symlink_to('absent-target')
                with patch.object(rust, 'PREFIX', root / 'build/irgx'):
                    with self.assertRaisesRegex(ValueError, 'deleted source reappeared'):
                        rust.preserve_sources(home, {'deleted.rs': None}, 'irgx')

    def test_retained_tombstones_refuse_resurrection_even_when_live_source_stays_absent(self):
        for kind in ('file', 'directory', 'dangling_symlink'):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as directory:
                root = Path(directory);home = root / 'source';home.mkdir()
                (home / 'engine.rs').write_bytes(b'captured source')
                files = {'engine.rs': rust.m.sha((home / 'engine.rs').read_bytes()), 'deleted.rs': None}
                with patch.object(rust, 'PREFIX', root / 'build/irgx'):
                    retained = Path(rust.preserve_sources(home, files, 'irgx'));resurrected = retained / 'deleted.rs'
                    if kind == 'file': resurrected.write_bytes(b'unlisted resurrected source')
                    elif kind == 'directory': resurrected.mkdir()
                    else: resurrected.symlink_to('absent-target')
                    self.assertFalse((home / 'deleted.rs').exists())
                    with self.assertRaisesRegex(ValueError, 'deleted|resurrect|retained'):
                        rust.preserve_sources(home, files, 'irgx')

    def test_retained_sources_are_selfcontained_regular_files_with_real_parents(self):
        for kind in ('same_bytes_file_symlink', 'escaping_parent_symlink', 'manifest_symlink', 'file_directory'):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as directory:
                root = Path(directory);home = root / 'source';(home / 'nested').mkdir(parents=True)
                original = b'exact captured source';(home / 'nested/engine.rs').write_bytes(original)
                files = {'nested/engine.rs': rust.m.sha(original)}
                with patch.object(rust, 'PREFIX', root / 'build/irgx'):
                    retained = Path(rust.preserve_sources(home, files, 'irgx'))
                    external = root / 'external';external.mkdir();(external / 'engine.rs').write_bytes(original)
                    if kind == 'same_bytes_file_symlink':
                        path = retained / 'nested/engine.rs';path.unlink();path.symlink_to(external / 'engine.rs')
                    elif kind == 'escaping_parent_symlink':
                        (retained / 'nested/engine.rs').unlink();(retained / 'nested').rmdir()
                        (retained / 'nested').symlink_to(external, target_is_directory=True)
                    elif kind == 'manifest_symlink':
                        path = retained / 'manifest.json';copy = external / 'manifest.json';copy.write_bytes(path.read_bytes())
                        path.unlink();path.symlink_to(copy)
                    else:
                        path = retained / 'nested/engine.rs';path.unlink();path.mkdir()
                    with self.assertRaisesRegex(ValueError, 'retained source'):
                        rust.preserve_sources(home, files, 'irgx')
                    self.assertEqual((home / 'nested/engine.rs').read_bytes(), original)
                    self.assertEqual((external / 'engine.rs').read_bytes(), original)

    def test_retained_source_paths_cannot_escape_or_normalize_silently(self):
        for relative in ('', '.', '../escape', '/absolute', 'a/../b', 'a//b'):
            with self.subTest(relative=relative), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                with patch.object(rust, 'PREFIX', root / 'build/irgx'):
                    with self.assertRaisesRegex(ValueError, 'invalid retained source path'):
                        rust.preserve_sources(root, {relative: None}, 'irgx')


if __name__ == "__main__":
    unittest.main()

"""Authored object/archive controls for the shipped boundary verifier.

Default discovery uses only bounded in-memory object bytes and temporary files.
Explicit --native additionally builds competing cross-member C state on the
current supported host. It never imports a private prototype or its fixtures.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

import rust_static_boundary as boundary


def ar_header(name, size):
    return (name.encode().ljust(16) + b'0'.ljust(12) + b'0'.ljust(6) + b'0'.ljust(6)
            + b'100644'.ljust(8) + str(size).encode().ljust(10) + b'`\n')


def archive_bytes(objects, rows, *, bsd=False, sorted_toc=False):
    """Independently encode offsets, including duplicate weak index rows."""
    if sorted_toc:
        rows = sorted(rows, key=lambda row: row[0])
    strings = b''.join(name.encode() + b'\0' for name, _ in rows)
    toc_name = '__.SYMDEF SORTED' if sorted_toc else '__.SYMDEF'
    extended = (toc_name.encode() + b'\0') if bsd else b''
    length = (8 + 8 * len(rows) if bsd else 4 + 4 * len(rows)) + len(strings)
    first = 8 + 60 + len(extended) + length + ((len(extended) + length) & 1)
    offsets = []
    position = first
    for name, payload in objects:
        offsets.append(position)
        position += 60 + len(payload) + (len(payload) & 1)
    if bsd:
        at, entries = 0, []
        for name, member in rows:
            entries.append(struct.pack('<II', at, offsets[member]));at += len(name.encode()) + 1
        payload = struct.pack('<I', 8 * len(rows)) + b''.join(entries) + struct.pack('<I', len(strings)) + strings
        toc = extended + payload
        raw = ar_header('#1/' + str(len(extended)), len(toc)) + toc
    else:
        payload = struct.pack('>I', len(rows)) + b''.join(struct.pack('>I', offsets[i]) for _, i in rows) + strings
        raw = ar_header('/', len(payload)) + payload
    raw += b'\n' if len(raw) & 1 else b''
    for name, payload in objects:
        raw += ar_header(name + '/', len(payload)) + payload + (b'\n' if len(payload) & 1 else b'')
    return b'!<arch>\n' + raw


def elf_object(mapping=None, *, metadata=False, split_strings=False, group_first=False,
               reverse_runtime=False, weak_info=0x21, alias_value=0, data_byte=42,
               import_name='system_call', group_target='.data', active_addrsig=True,
               public_names=None, private_names=None):
    """ELF symbols, RELA, COMDAT and addrsig are authored independently."""
    mapping = mapping or {}
    names = ['.text', '.data', '.tdata', '.eh_frame']
    if reverse_runtime:
        names[0], names[1] = names[1], names[0]
    if metadata:
        names += ['.llvmbc', '.llvmcmd']
    names += ['.strtab', '.symtab', '.rela.text', '.group', '.llvm_addrsig']
    if group_first:
        names.remove('.group');names.insert(0, '.group')
    if split_strings:
        names += ['.shstrtab']
    indices = {name: i + 1 for i, name in enumerate(names)}
    symbols = [('', 0, 0, 0, 0, 0), ('jnt_read', 0x12, 0, indices['.text'], 0, 8),
               ('owned', 0x11, 0, indices['.data'], 0, 8), ('weak', weak_info, 2, indices['.data'], 8, 8),
               ('alias', 0x12, 0, indices['.text'], alias_value, 8), ('tls', 0x16, 0, indices['.tdata'], 0, 8),
               ('descriptor', 0x21, 2, indices['.data'], 16, 8), (import_name, 0x12, 0, 0, 0, 0)]
    if public_names is not None:
        symbols[1] = (public_names[0], *symbols[1][1:])
        symbols.extend((name, 0x12, 0, indices['.text'], 0, 8) for name in public_names[1:])
    if private_names:
        symbols = [(private_names.get(n, n), *rest) for n, *rest in symbols]
    strings = bytearray(b'\0');offsets = {'': 0}
    def add(text):
        if text not in offsets:
            offsets[text] = len(strings);strings.extend(text.encode() + b'\0')
        return offsets[text]
    for name in names:
        add(name)
    for name, *_ in symbols:
        add(mapping.get(name, name))
    symtab = b''.join(struct.pack('<IBBHQQ', offsets[mapping.get(n, n)], info, other, section, value, size)
                      for n, info, other, section, value, size in symbols)
    sections = [(0,) * 10];bodies = [b'']
    for name in names:
        typ, flags, link, info, alignment, entry = 1, 0, 0, 0, 8, 0
        body = b''
        if name == '.text': flags, body = 6, b'\x90' * 16
        elif name == '.data': flags, body = 3, bytes([data_byte]) + bytes(23)
        elif name == '.tdata': flags, body = 0x403, bytes(8)
        elif name == '.eh_frame': flags, body = 2, b'preserved-EH-record'
        elif name == '.llvmbc': body = b'compiler-only-bitcode'
        elif name == '.llvmcmd': body = b'compiler-command'
        elif name in ('.strtab', '.shstrtab'): typ, alignment, body = 3, 1, bytes(strings)
        elif name == '.symtab': typ, link, info, entry, body = 2, indices['.strtab'], 1, 24, symtab
        elif name == '.rela.text':
            typ, link, info, entry = 4, indices['.symtab'], indices['.text'], 24
            body = struct.pack('<QQq', 0, (2 << 32) | 1, 0) + struct.pack('<QQq', 8, (7 << 32) | 1, -4)
        elif name == '.group':
            typ, link, info, alignment, entry = 17, indices['.symtab'], 6, 4, 4
            body = struct.pack('<II', 1, indices[group_target])
        elif name == '.llvm_addrsig':
            typ, link, alignment, body = 0x6fff4c03, indices['.symtab'] if active_addrsig else 0, 1, b'\x02\x04'
        sections.append((add(name), typ, flags, 0, 0, len(body), link, info, alignment, entry));bodies.append(body)
    raw = bytearray(64)
    for i in range(1, len(sections)):
        while len(raw) % sections[i][8]: raw.append(0)
        values = list(sections[i]);values[4] = len(raw);sections[i] = tuple(values);raw.extend(bodies[i])
    while len(raw) % 8: raw.append(0)
    section_start = len(raw)
    raw.extend(b''.join(struct.pack('<IIQQQQIIQQ', *s) for s in sections))
    ident = b'\x7fELF\x02\x01\x01' + bytes(9)
    raw[:64] = struct.pack('<16sHHIQQQIHHHHHH', ident, 1, 62, 1, 0, 0, section_start, 0, 64, 0, 0, 64,
                           len(sections), indices['.shstrtab' if split_strings else '.strtab'])
    return bytes(raw)


def macho_object(mapping=None, *, metadata=False, weak_desc=0x80, alias_value=0x1000,
                 data_byte=42, local_indirect=False, bad_metadata_reference=False,
                 nonempty_dice=False, reverse_runtime=False, second_segment=False,
                 public_names=None, private_names=None):
    """ARM64 ADDEND is payload; SUBTRACTOR/UNSIGNED keep their paired order."""
    mapping = mapping or {}
    section_names = [('__TEXT', '__text'), ('__DATA', '__data'), ('__TEXT', '__eh_frame')]
    if reverse_runtime: section_names[0], section_names[1] = section_names[1], section_names[0]
    if metadata: section_names += [('__LLVM', '__bitcode'), ('__LLVM', '__cmdline')]
    indices = {key: i + 1 for i, key in enumerate(section_names)}
    symbols = []
    if metadata:
        symbols = [('metadata_label', 10 if local_indirect else 14, indices['__LLVM', '__bitcode'], 0, 0x4000)]
    locals_count = len(symbols)
    symbols += [('_jnt_read', 15, indices['__TEXT', '__text'], 0, 0x1000),
                ('_owned', 15, indices['__DATA', '__data'], 0, 0x2000),
                ('_weak', 15, indices['__DATA', '__data'], weak_desc, 0x2008),
                ('_alias', 15, indices['__TEXT', '__text'], 0, alias_value), ('_system_call', 1, 0, 0, 0)]
    if public_names is not None:
        symbols[locals_count] = (public_names[0], *symbols[locals_count][1:])
        symbols[locals_count + 4:locals_count + 4] = [(name, 15, indices['__TEXT', '__text'], 0, 0x1000) for name in public_names[1:]]
    if private_names:
        symbols = [(private_names.get(n, n), *rest) for n, *rest in symbols]
    global_count = 4 + (len(public_names) - 1 if public_names is not None else 0)
    strings = bytearray(b'\0');rows = []
    for name, kind, section, desc, value in symbols:
        at = len(strings);strings.extend(mapping.get(name, name).encode() + b'\0')
        rows.append(struct.pack('<IBBHQ', at, kind, section, desc, value))
    size = 72 + len(section_names) * 80
    command_bytes = size + 24 + 80 + 24 + 16 + (72 if second_segment else 0)
    raw = bytearray(32 + command_bytes)
    sections = []
    for segment, name in section_names:
        while len(raw) % 8: raw.append(0)
        address = {('__TEXT', '__text'): 0x1000, ('__DATA', '__data'): 0x2000,
                   ('__TEXT', '__eh_frame'): 0x3000, ('__LLVM', '__bitcode'): 0x4000,
                   ('__LLVM', '__cmdline'): 0x5000}[segment, name]
        payload = b'\x1f\x20\x03\xd5' * 4 if name == '__text' else bytes([data_byte]) + bytes(23) if name == '__data' else b'unwind-payload' if name == '__eh_frame' else b'compiler-metadata'
        offset = len(raw);raw.extend(payload)
        relocations = []
        if name == '__text':
            target = 0 if bad_metadata_reference else locals_count + 1
            relocations = [(0, (3 << 25) | (1 << 27) | target),
                           (4, (10 << 28) | 4096),
                           (8, (1 << 28) | (3 << 25) | (1 << 27) | (locals_count + 1)),
                           (8, (3 << 25) | (1 << 27) | (locals_count + 2))]
        relocation_offset = len(raw) if relocations else 0
        for row in relocations: raw.extend(struct.pack('<II', *row))
        flags = 0x80000400 if name == '__text' else 0
        sections.append(struct.pack('<16s16sQQIIIIIIII', name.encode(), segment.encode(), address, len(payload), offset,
                                    3, relocation_offset, len(relocations), flags, 0, 0, 0))
    symoff = len(raw);raw.extend(b''.join(rows));stroff = len(raw);raw.extend(strings)
    segment = struct.pack('<II16sQQQQiiII', 25, size, b'', 0, 0x6000, 32 + command_bytes,
                          symoff - (32 + command_bytes), 7, 7, len(sections), 0) + b''.join(sections)
    symtab = struct.pack('<IIIIII', 2, 24, symoff, len(symbols), stroff, len(strings))
    dysymtab = struct.pack('<20I', 11, 80, 0, locals_count, locals_count, global_count, locals_count + global_count, 1, *([0] * 12))
    version = struct.pack('<6I', 50, 24, 1, 0x000d0000, 0x001a0500, 0)
    dice = struct.pack('<4I', 41, 16, 0, 8 if nonempty_dice else 0)
    extra = struct.pack('<II16sQQQQiiII', 25, 72, b'', 0, 0, 0, 0, 0, 0, 0, 0) if second_segment else b''
    raw[32:32 + command_bytes] = segment + symtab + dysymtab + version + dice + extra
    raw[:32] = struct.pack('<IiiIIIII', 0xfeedfacf, 0x100000c, 0, 1, 6 if second_segment else 5, command_bytes, 0x2000, 0)
    return bytes(raw)


class StaticBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def write(self, name, data):
        path = self.root / name;path.parent.mkdir(parents=True, exist_ok=True);path.write_bytes(data);return path

    def test_elf_metadata_namespace_and_string_split_group_move(self):
        mapping = {'owned': 'private_owned', 'weak': 'private_weak', 'alias': 'private_alias',
                   'descriptor': 'private_descriptor', 'tls': 'private_tls'}
        before = elf_object(metadata=True)
        after = elf_object(mapping, split_strings=True, group_first=True)
        proof = boundary.compare_elf(before, after, mapping, removed=('.llvmbc', '.llvmcmd'))
        self.assertEqual((proof['relocations'], proof['groups'], proof['address_significance_targets']), (2, 1, 2))
        self.assertTrue(proof['string_table_split']);self.assertTrue(proof['group_headers_moved'])
        self.assertEqual(boundary.ElfObject(after).symbols[7][0], 'system_call')

    def test_elf_runtime_attributes_alias_and_linkage_corruptions_refuse(self):
        before = elf_object(metadata=True)
        variants = [{'weak_info': 0x11}, {'alias_value': 1}, {'data_byte': 43},
                    {'import_name': 'other_system'}, {'group_target': '.text'}, {'active_addrsig': False},
                    {'reverse_runtime': True}]
        for options in variants:
            with self.subTest(options=options), self.assertRaises(ValueError):
                boundary.compare_elf(before, elf_object(**options), {}, removed=('.llvmbc', '.llvmcmd'))

    def test_elf_address_significance_target_and_runtime_relocation_refuse(self):
        before = elf_object();obj = boundary.ElfObject(before)
        for section, offset in (('.llvm_addrsig', 0), ('.rela.text', 12)):
            data = bytearray(before);at = obj.sections[obj.names.index(section)][4] + offset;data[at] ^= 1
            with self.subTest(section=section), self.assertRaises(ValueError):
                boundary.compare_elf(before, data, {})

    def test_elf_closed_map_excludes_only_declared_exports_and_preserves_imports(self):
        path = self.write('input.a', archive_bytes([('a.o', elf_object())], [('jnt_read', 0), ('weak', 0)]))
        _, _, policy = boundary._plan_elf(path, ('jnt_read',))
        self.assertEqual(set(policy['mapping']), {'owned', 'weak', 'alias', 'tls', 'descriptor'})
        self.assertEqual(policy['unresolved_imports'], ['system_call'])
        self.assertTrue(all(n.startswith('__jnt_opaque_elf_' + hashlib.sha256(path.read_bytes()).hexdigest() + '_')
                            for n in policy['mapping'].values()))
        with self.assertRaisesRegex(ValueError, 'export'):
            boundary._plan_elf(path, ('jnt_missing',))

    def test_elf_linker_special_or_unsupported_binding_refuses(self):
        data = elf_object({'owned': '__dso_handle'})
        path = self.write('special.a', archive_bytes([('a.o', data)], [('jnt_read', 0)]))
        with self.assertRaisesRegex(ValueError, 'linker/CRT'):
            boundary._plan_elf(path, ('jnt_read',))
        data = bytearray(elf_object());obj = boundary.ElfObject(data)
        data[obj.sections[obj.table][4] + 2 * 24 + 4] = 0xa1
        path = self.write('unique.a', archive_bytes([('a.o', data)], [('jnt_read', 0)]))
        with self.assertRaisesRegex(ValueError, 'binding'):
            boundary._plan_elf(path, ('jnt_read',))

    def test_gnu_index_full_order_and_duplicate_weak_priority(self):
        objects = [('a.o', elf_object()), ('b.o', elf_object())]
        rows = [('jnt_read', 0), ('weak', 0), ('alias', 1), ('weak', 1)]
        old = self.write('old.a', archive_bytes(objects, rows))
        same = self.write('same.a', archive_bytes(objects, rows))
        boundary.compare_elf_index(old, same, {})
        for label, changed in [('weak', [rows[0], rows[3], rows[2], rows[1]]),
                               ('cross-name', [rows[1], rows[0], rows[2], rows[3]])]:
            other = self.write(label + '.a', archive_bytes(objects, changed))
            if label == 'cross-name':
                self.assertEqual(boundary.elf_index(old)['member_selection'], boundary.elf_index(other)['member_selection'])
            with self.subTest(label=label), self.assertRaisesRegex(ValueError, 'order'):
                boundary.compare_elf_index(old, other, {})

    def test_macho_metadata_locals_and_arm64_relocation_semantics(self):
        mapping = {'_owned': 'private_owned', '_weak': 'private_weak', '_alias': 'private_alias'}
        before, after = macho_object(metadata=True), macho_object(mapping)
        proof = boundary.compare_macho(before, after, mapping, remove=True)
        self.assertEqual((proof['removed_local_metadata_symbols'], proof['relocations']), (1, 4))
        kinds = {attrs >> 4 for s in boundary.MachObject(before).sections for _, attrs, _ in s['relocations']}
        self.assertEqual(kinds, {0, 1, 10})

    def test_macho_weak_alias_data_and_runtime_order_refuse(self):
        before = macho_object(metadata=True)
        for options in ({'weak_desc': 0}, {'alias_value': 0x1004}, {'data_byte': 43}, {'reverse_runtime': True}):
            with self.subTest(options=options), self.assertRaises(ValueError):
                boundary.compare_macho(before, macho_object(**options), {}, remove=True)

    def test_macho_indirect_nonempty_dice_and_removed_label_reference_refuse(self):
        for options in ({'local_indirect': True}, {'nonempty_dice': True}):
            with self.subTest(options=options), self.assertRaises(ValueError):
                boundary.MachObject(macho_object(metadata=True, **options))
        with self.assertRaisesRegex(ValueError, 'removed metadata'):
            boundary.compare_macho(macho_object(metadata=True, bad_metadata_reference=True), macho_object(), {}, remove=True)

    def test_macho_relocation_retarget_and_addend_payload_refuse(self):
        data = macho_object();obj = boundary.MachObject(data);section = obj.sections[0]
        for ordinal in (0, 1):
            changed = bytearray(data);changed[section['row'][6] + ordinal * 8 + 4] ^= 1
            with self.subTest(ordinal=ordinal), self.assertRaises(ValueError):
                boundary.compare_macho(data, changed, {})

    def test_macho_single_segment_scope_refuses_second_segment(self):
        with self.assertRaisesRegex(ValueError, 'multiple Mach-O segments'):
            boundary.MachObject(macho_object(second_segment=True))

    def test_bsd_sorted_index_remaps_names_but_preserves_duplicate_priority(self):
        objects = [('a.o', macho_object()), ('b.o', macho_object())]
        rows = [('_alias', 0), ('_jnt_read', 0), ('_weak', 0), ('_weak', 1)]
        mapping = {'_alias': 'zz_private_alias', '_weak': 'zz_private_weak'}
        old = self.write('old.a', archive_bytes(objects, rows, bsd=True, sorted_toc=True))
        mapped = [(mapping.get(n, n), i) for n, i in rows]
        good = self.write('good.a', archive_bytes(objects, mapped, bsd=True, sorted_toc=True))
        boundary.compare_macho_index(old, good, mapping)
        mapped[-1], mapped[-2] = mapped[-2], mapped[-1]
        bad = self.write('bad.a', archive_bytes(objects, mapped, bsd=True, sorted_toc=True))
        with self.assertRaisesRegex(ValueError, 'selection'):
            boundary.compare_macho_index(old, bad, mapping)

    def test_bounded_decoders_refuse_invalid_object_and_toc_extents(self):
        for create, parse in ((elf_object, boundary.ElfObject), (macho_object, boundary.MachObject)):
            for data in (b'', create()[:63], create()[:-20]):
                with self.subTest(parse=parse.__name__, size=len(data)), self.assertRaises((ValueError, struct.error)):
                    parse(data)
        path = self.write('bad.a', archive_bytes([('a.o', elf_object())], [('weak', 0)])[:-4])
        with self.assertRaises(ValueError): boundary.elf_index(path)

    def test_receipt_must_match_recomputed_closed_byte_proof(self):
        objects = [('a.o', elf_object())]
        original = self.write('old.a', archive_bytes(objects, [('jnt_read', 0), ('weak', 0)]))
        _, _, plan = boundary._plan_elf(original, ('jnt_read',))
        changed = [('a.o', elf_object(plan['mapping']))]
        derivative = self.write('new.a', archive_bytes(changed, [('jnt_read', 0), (plan['mapping']['weak'], 0)]))
        facts = boundary._facts(original, derivative, 'linux-x86_64', ('jnt_read',))
        receipt = {'schema': 1, 'kind': 'opaque-native-only-C-static-boundary', 'target': 'linux-x86_64',
                   'machine_code_only': True, 'before_sha256': facts['before_sha256'],
                   'after_sha256': facts['after_sha256'], 'facts': facts}
        boundary.verify_archive(original, derivative, receipt, target='linux-x86_64', exports=('jnt_read',))
        receipt['facts'] = {**facts, 'unresolved_imports': []}
        with self.assertRaisesRegex(ValueError, 'byte proof'):
            boundary.verify_archive(original, derivative, receipt, target='linux-x86_64', exports=('jnt_read',))

    def test_tool_failure_never_publishes_derivative(self):
        path = self.write('input.a', archive_bytes([('a.o', elf_object())], [('jnt_read', 0)]))
        tool = self.write('objcopy', b'not executed; command mocked')
        output = self.root / 'output.a'
        with mock.patch.object(boundary, '_command', side_effect=ValueError('controlled tool failure')):
            with self.assertRaisesRegex(ValueError, 'controlled'):
                boundary.transform_archive(path, output, target='linux-x86_64', exports=('jnt_read',),
                                           objcopy=tool, work=self.root / 'proof')
        self.assertFalse(output.exists())


class IrgxBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        repository = next(parent for parent in Path(__file__).resolve().parents
                          if (parent / 'rust/Cargo.toml').is_file())
        self.header = Path(__file__).parent / 'testdata/irgx-abi2-105.h'
        header = re.sub(r'/\*.*?\*/|//[^\n]*', '', self.header.read_text(), flags=re.S)
        self.names = tuple(sorted(re.findall(r'\b(irgx_[a-zA-Z0-9_]+)\s*\(', header)))
        # Frozen independently parsed full-header roster, not the helper's table.
        self.assertEqual(hashlib.sha256(json.dumps(self.names, separators=(',', ':')).encode()).hexdigest(),
                         'd4f8b0d9001cfa53e8cc0b8dfbebc561127c44dffb3c254f5eb5df6840c690ec')
        self.assertEqual(len(self.names), 105)
        self.assertEqual(len(set(self.names)), 105)

    def put(self, name, data):
        path = self.root / name;path.write_bytes(data);return path

    def make(self, target, *, public_names=None, mapping=None, extra_export=False):
        names = self.names if target == 'linux-x86_64' else tuple('_' + n for n in self.names)
        public_names = names if public_names is None else public_names
        private = {'owned': 'pcre2_compile_8', 'weak': '_pcre2_tables_8'} if target == 'linux-x86_64' else {'_owned': '_pcre2_compile_8', '_weak': '__pcre2_tables_8'}
        make = elf_object if target == 'linux-x86_64' else macho_object
        if extra_export:
            private = {**private, 'alias' if target == 'linux-x86_64' else '_alias': 'irgx_extra' if target == 'linux-x86_64' else '_irgx_extra'}
        data = make(mapping, public_names=public_names, private_names=private)
        rows = [(n, 0) for n in public_names]
        return names, data, rows

    def proof(self, target):
        exports, data, rows = self.make(target)
        original = self.put(target + '-original.a', archive_bytes([('native.o', data)], rows,
            bsd=target == 'macos-arm64', sorted_toc=target == 'macos-arm64'))
        planner = boundary._plan_elf if target == 'linux-x86_64' else boundary._plan_macho
        _, _, plan = planner(original, exports, abi_family=boundary.IRGX_ABI2)
        _, changed, _ = self.make(target, mapping=plan['mapping'])
        derivative = self.put(target + '-derivative.a', archive_bytes([('native.o', changed)], rows,
            bsd=target == 'macos-arm64', sorted_toc=target == 'macos-arm64'))
        facts = boundary._facts(original, derivative, target, exports, abi_family=boundary.IRGX_ABI2)
        receipt = {'schema': 1, 'kind': 'opaque-native-only-C-static-boundary', 'target': target,
            'abi_family': boundary.IRGX_ABI2, 'machine_code_only': True, 'facts': facts,
            'before_sha256': facts['before_sha256'], 'after_sha256': facts['after_sha256']}
        return original, derivative, exports, plan, receipt

    def test_authoritative_header_is_full105_not_binding_subset(self):
        header = self.header
        self.assertEqual(hashlib.sha256(header.read_bytes()).hexdigest(),
            '0909688d9a22c752483031c7781feb2965926eaf773b40d298ea9b39e7fbdf74')
        for target in ('linux-x86_64', 'macos-arm64'):
            got = boundary.declared_exports(header, target, abi_family=boundary.IRGX_ABI2)
            expected = self.names if target == 'linux-x86_64' else tuple('_' + n for n in self.names)
            self.assertEqual(got, expected)
        # A binding's smaller surface cannot substitute for the authoritative ABI.
        with self.assertRaisesRegex(ValueError, 'roster'):
            boundary._family_exports(self.names[:28], 'linux-x86_64', boundary.IRGX_ABI2)

    def test_header_missing_extra_duplicate_substitution_and_badname_refuse(self):
        text = self.header.read_text()
        variants = [text.replace('irgx_abi_version(void)', 'other_abi_version(void)'),
            text + '\nint irgx_surprise(void);\n', text + '\nint irgx_version(void);\n',
            text.replace('irgx_abi_version(void)', 'irgx_substitute(void)'),
            text.replace('irgx_abi_version(void)', 'irgx_bad$name(void)')]
        for at, variant in enumerate(variants):
            with self.subTest(at=at), self.assertRaisesRegex(ValueError, 'roster'):
                boundary.declared_exports(self.put(str(at) + '.h', variant.encode()),
                    'linux-x86_64', abi_family=boundary.IRGX_ABI2)
        comments = self.put('comments.h', (text + '\n/* int irgx_extra(void); */\n// int irgx_extra2(void);\n').encode())
        self.assertEqual(boundary.declared_exports(comments, 'linux-x86_64', abi_family=boundary.IRGX_ABI2), self.names)

    def test_family_argument_and_exact_roster_refuse_before_object_use(self):
        for target in ('linux-x86_64', 'macos-arm64'):
            names = self.names if target == 'linux-x86_64' else tuple('_' + n for n in self.names)
            for bad in (names[:-1], names + ('irgx_extra',), names + names[:1],
                        names[:-1] + ('irgx_bad$',), (None,)):
                with self.subTest(target=target, bad=bad[-1:]), self.assertRaises(ValueError):
                    boundary._family_exports(bad, target, boundary.IRGX_ABI2)
        for bad in (None, 'irgx', 'jnt-abi3', 1):
            with self.subTest(bad=bad), self.assertRaisesRegex(ValueError, 'family'):
                boundary.declared_exports(self.header, 'linux-x86_64', abi_family=bad)

    def test_elf_full_public_private_pcre_reference_proof_and_family_receipt(self):
        self.check_proof('linux-x86_64')

    def test_macho_full_public_private_pcre_reference_proof_and_family_receipt(self):
        self.check_proof('macos-arm64')

    def check_proof(self, target):
        original, derivative, exports, plan, receipt = self.proof(target)
        self.assertEqual(len(plan['c_exports']), 105)
        private_pcre = 'pcre2_compile_8' if target == 'linux-x86_64' else '_pcre2_compile_8'
        self.assertIn(private_pcre, plan['mapping'])
        self.assertTrue(all(n not in plan['mapping'] for n in exports))
        self.assertEqual(plan['unresolved_imports'], ['system_call' if target == 'linux-x86_64' else '_system_call'])
        boundary.verify_archive(original, derivative, receipt, target=target, exports=exports, abi_family=boundary.IRGX_ABI2)
        with self.assertRaisesRegex(ValueError, 'family'):
            boundary.verify_archive(original, derivative, receipt, target=target, exports=exports)
        for field, value in (('abi_family', boundary.JNT_ABI2), ('abi_family', 'unknown')):
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, 'family'):
                boundary.verify_archive(original, derivative, {**receipt, field: value}, target=target, exports=exports, abi_family=boundary.IRGX_ABI2)
        # A backend reference/definition left at the consumer-visible name refuses.
        mapping = dict(plan['mapping']);mapping.pop(private_pcre)
        _, changed, rows = self.make(target, mapping=mapping)
        stale = self.put(target + '-leaked.a', archive_bytes([('native.o', changed)], rows,
            bsd=target == 'macos-arm64', sorted_toc=target == 'macos-arm64'))
        with self.assertRaises(ValueError):
            boundary.verify_archive(original, stale, receipt, target=target, exports=exports, abi_family=boundary.IRGX_ABI2)

    def test_object_missing_extra_duplicate_or_weak_public_export_refuses(self):
        for target in ('linux-x86_64', 'macos-arm64'):
            names, _, _ = self.make(target)
            planner = boundary._plan_elf if target == 'linux-x86_64' else boundary._plan_macho
            cases = [('missing', names[:-1], False), ('duplicate', names + names[:1], False),
                     ('extra', names, True)]
            for label, chosen, extra in cases:
                _, data, rows = self.make(target, public_names=chosen, extra_export=extra)
                path = self.put(target + label + '.a', archive_bytes([('native.o', data)], rows,
                    bsd=target == 'macos-arm64'))
                with self.subTest(target=target, label=label), self.assertRaises(ValueError):
                    planner(path, names, abi_family=boundary.IRGX_ABI2)
            # Export presence/count is insufficient: weak or nonfunction definitions refuse.
            _, data, rows = self.make(target)
            if target == 'linux-x86_64':
                obj = boundary.ElfObject(data)
                offset = obj.sections[obj.table][4] + 24 + 4  # first public st_info
                corruptions = [(offset, 0x22), (offset, 0x11)]
            else:
                obj = boundary.MachObject(data)
                offset = obj.symtab[0] + 6  # first public n_desc
                corruptions = [(offset, 0x80)]
            for at, (offset, value) in enumerate(corruptions):
                changed = bytearray(data);changed[offset] = value
                path = self.put(target + 'badpublic' + str(at) + '.a', archive_bytes([('native.o', changed)], rows,
                    bsd=target == 'macos-arm64'))
                with self.subTest(target=target, corruption=at), self.assertRaisesRegex(ValueError, 'strong'):
                    planner(path, names, abi_family=boundary.IRGX_ABI2)
            # Two complete members must not masquerade as one strong public surface.
            path = self.put(target + 'twodefs.a', archive_bytes([('a.o', data), ('b.o', data)], rows,
                bsd=target == 'macos-arm64'))
            with self.assertRaisesRegex(ValueError, 'strong'):
                planner(path, names, abi_family=boundary.IRGX_ABI2)

    def test_irgx_producer_pins_parser_before_and_after_without_jnt_shape_change(self):
        original, derivative, exports, _, _ = self.proof('linux-x86_64')
        tool = self.put('objcopy', b'authored tool identity; never executed')
        parser = Path(boundary.rust_archive.__file__).resolve()
        digest = boundary._digest
        parser_hash = digest(parser)
        def transform(_original, staged, *_args, **_kwargs):
            staged.write_bytes(derivative.read_bytes())
            return {'tool': {'version': 'LLVM authored fixture', 'sha256': digest(tool)}}
        for drift in (False, True):
            with self.subTest(drift=drift):
                parser_reads = []
                def question(path):
                    if Path(path).resolve() == parser:
                        parser_reads.append(path)
                        return '0' * 64 if drift and len(parser_reads) > 1 else parser_hash
                    return digest(path)
                output = self.root / ('published-' + str(drift) + '.a')
                with mock.patch.object(boundary, '_transform_elf', side_effect=transform), \
                        mock.patch.object(boundary, '_digest', side_effect=question):
                    if drift:
                        with self.assertRaisesRegex(ValueError, 'parser source drift'):
                            boundary.transform_archive(original, output, target='linux-x86_64',
                                exports=exports, objcopy=tool, work=self.root / ('work-' + str(drift)),
                                abi_family=boundary.IRGX_ABI2)
                        self.assertFalse(output.exists())
                    else:
                        receipt = boundary.transform_archive(original, output, target='linux-x86_64',
                            exports=exports, objcopy=tool, work=self.root / ('work-' + str(drift)),
                            abi_family=boundary.IRGX_ABI2)
                        self.assertEqual(receipt['parser_sha256'], parser_hash)
                        boundary.verify_archive(original, output, receipt, target='linux-x86_64',
                                                exports=exports, abi_family=boundary.IRGX_ABI2)
                self.assertEqual(len(parser_reads), 2)

    def test_default_jnt_plan_facts_and_old_receipts_are_byte_exact(self):
        # Captured from shipped pre-family helper 3b435751ae3d269ea0c454760104c88df
        # 000e6cd38092e00f60cbaba6373ac8d. Never import today's module as "old".
        golden = {
            'linux-x86_64': (
                'f895936830b2ff25cc5a527276e137013ebfedf73c623448e84e455de561b545',
                'a7d79310b3e8ff7e964b7970b4ec46ab9f6be2ef98063c914f90f4ef8167ce01'),
            'macos-arm64': (
                '40d19683fc35aff7abbddf2496adade7645ae025d8d01690fecff0a3adbdea69',
                'a30a536806507f28a710ac1e8613fc0513c9deaf2d7cc7ceda03740ae31f53ba'),
        }
        for target, make, exported in (('linux-x86_64', elf_object, ('jnt_read',)),
                                      ('macos-arm64', macho_object, ('_jnt_read',))):
            bsd = target == 'macos-arm64'
            original = self.put(target + '-jnt.a', archive_bytes([('a.o', make())],
                [(exported[0], 0)], bsd=bsd, sorted_toc=bsd))
            plan = (boundary._plan_macho if bsd else boundary._plan_elf)(original, exported)[2]
            self.assertEqual(hashlib.sha256(boundary._encoded(plan)).hexdigest(), golden[target][0])
            derivative = self.put(target + '-jnt-new.a', archive_bytes(
                [('a.o', make(plan['mapping']))], [(exported[0], 0)], bsd=bsd, sorted_toc=bsd))
            facts = boundary._facts(original, derivative, target, exported)
            self.assertEqual(hashlib.sha256(boundary._encoded(facts)).hexdigest(), golden[target][1])
            self.assertNotIn('abi_family', facts)
            receipt = {'schema': 1, 'kind': 'opaque-native-only-C-static-boundary', 'target': target,
                'machine_code_only': True, 'before_sha256': facts['before_sha256'],
                'after_sha256': facts['after_sha256'], 'facts': facts}
            boundary.verify_archive(original, derivative, receipt, target=target, exports=exported)
            boundary.verify_archive(original, derivative, receipt, target=target, exports=exported,
                                    abi_family=boundary.JNT_ABI2)


class MacIndexProducerTests(unittest.TestCase):
    """Authored archives and mocked commands exercise the actual producer path."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.objcopy = (self.root / 'llvm-objcopy').resolve()
        self.indexer = (self.root / 'libtool').resolve()
        self.objcopy.write_bytes(b'authored LLVM tool identity; never executed')
        self.indexer.write_bytes(b'authored Apple indexer identity; never executed')
        self.exports = ('_jnt_first', '_jnt_second')
        self.rows = [(name, i) for i, export in enumerate(self.exports)
                     for name in (export, '_owned_' + str(i), '_weak_' + str(i), '_alias_' + str(i))]
        self.calls = []

    def objects(self, mapping=None):
        return [(str(i) + '.o', macho_object(mapping, public_names=(export,),
                    private_names={name: name + '_' + str(i)
                                   for name in ('_owned', '_weak', '_alias')}))
                for i, export in enumerate(self.exports)]

    def original(self, *, sorted_toc=True):
        path = self.root / 'original.a'
        path.write_bytes(archive_bytes(self.objects(), self.rows, bsd=True, sorted_toc=sorted_toc))
        return path

    def command(self, mode='good'):
        def run(argv, *, cwd, env, logs, records):
            argv = [str(x) for x in argv]
            self.calls.append((argv, dict(env)))
            records.append({'argv': argv, 'returncode': 0})
            if argv == [str(self.objcopy), '--version']:
                stdout = b'LLVM authored fixture\n'
            elif argv[0] == str(self.objcopy) and argv[1].startswith('--redefine-syms='):
                mapping = dict(line.split() for line in Path(argv[1].split('=', 1)[1]).read_text().splitlines())
                self.mapped_rows = [(mapping.get(name, name), member) for name, member in self.rows]
                Path(argv[-1]).write_bytes(archive_bytes(self.objects(mapping), self.mapped_rows, bsd=True))
                stdout = b''
            elif argv == [str(self.indexer), '-V']:
                stdout = b'GNU libtool fixture\n' if mode == 'wrong-tool' else b'Apple Inc. version cctools_fixture\n'
            elif argv[:5] == [str(self.indexer), '-static', '-s', '-D', '-o']:
                self.assertEqual(env['ZERO_AR_DATE'], '1')
                source = boundary.rust_archive.read_archive(Path(argv[-1]))
                objects = [(member.name.decode(), source.payload(member)) for member in source.members]
                rows = list(self.mapped_rows)
                if mode == 'payload':
                    # Alter an actual runtime byte while keeping a parseable object.
                    payload = bytearray(objects[0][1])
                    section = boundary.MachObject(payload).sections[1]
                    payload[section['row'][4]] ^= 1
                    objects[0] = (objects[0][0], bytes(payload))
                elif mode == 'members':
                    objects.reverse()
                elif mode == 'selection':
                    rows = [(name, 1 - member if name == self.exports[0] else member)
                            for name, member in rows]
                if mode == 'indexer-drift':
                    self.indexer.write_bytes(b'changed indexer')
                Path(argv[-2]).write_bytes(archive_bytes(objects, rows, bsd=True,
                                                        sorted_toc=mode != 'unsorted'))
                stdout = b''
            else:
                self.fail('unexpected mocked command: ' + repr(argv))
            return subprocess.CompletedProcess(argv, 0, stdout, b'')
        return run

    def produce(self, original, *, mode='good', indexer=True):
        output = self.root / 'published.a'
        with mock.patch.object(boundary, '_command', side_effect=self.command(mode)):
            receipt = boundary.transform_archive(original, output, target='macos-arm64',
                exports=self.exports, objcopy=self.objcopy, indexer=self.indexer if indexer else None,
                work=self.root / 'work')
        return output, receipt

    def test_sorted_index_is_restored_with_exact_member_bytes_and_full_proof(self):
        original = self.original()
        before = original.read_bytes()
        output, receipt = self.produce(original)
        self.assertEqual(original.read_bytes(), before)
        self.assertTrue(boundary.macho_index(output)['sorted'])
        restoration = receipt['transform']['index_restoration']
        self.assertEqual(restoration['ZERO_AR_DATE'], '1')
        self.assertTrue(restoration['exact_member_payloads'])
        self.assertEqual(restoration['sha256'], hashlib.sha256(self.indexer.read_bytes()).hexdigest())
        intermediate = boundary.rust_archive.read_archive(self.root / 'work/derivative.unsorted.a')
        after = boundary.rust_archive.read_archive(output)
        self.assertEqual([(m.name, intermediate.payload(m)) for m in intermediate.members],
                         [(m.name, after.payload(m)) for m in after.members])
        boundary.verify_archive(original, output, receipt, target='macos-arm64', exports=self.exports)
        self.assertEqual([argv[1] for argv, _ in self.calls],
                         ['--version', '--redefine-syms=' + str(self.root / 'work/mapping.txt'), '-V', '-static'])
        self.assertNotIn('abi_family', receipt)
        self.assertNotIn('parser_sha256', receipt)

    def test_sorted_index_requires_explicit_identified_tool(self):
        for mode, has_indexer, message in (('good', False, 'explicit Apple'),
                                          ('wrong-tool', True, 'identified Apple')):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as temp:
                previous = self.root
                self.root = Path(temp)
                original = self.original()
                with self.assertRaisesRegex(ValueError, message):
                    self.produce(original, mode=mode, indexer=has_indexer)
                self.assertFalse((self.root / 'published.a').exists())
                self.root = previous

    def test_indexer_payload_member_order_selection_and_tool_drift_never_publish(self):
        cases = (('payload', 'object payload'), ('members', 'member order'),
                 ('selection', 'selection'), ('unsorted', 'kind'), ('indexer-drift', 'indexer changed'))
        for mode, message in cases:
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as temp:
                previous = self.root
                self.root = Path(temp)
                original = self.original()
                with self.assertRaisesRegex(ValueError, message):
                    self.produce(original, mode=mode)
                self.assertFalse((self.root / 'published.a').exists())
                self.root = previous
                self.indexer.write_bytes(b'authored Apple indexer identity; never executed')

    def test_unsorted_jnt_producer_does_not_use_indexer_or_change_legacy_receipt(self):
        output, receipt = self.produce(self.original(sorted_toc=False), indexer=False)
        self.assertFalse(boundary.macho_index(output)['sorted'])
        self.assertNotIn('index_restoration', receipt['transform'])
        self.assertNotIn('abi_family', receipt)
        self.assertEqual(len(self.calls), 2)

    def test_indexer_mutating_both_input_and_output_cannot_hide_input_drift(self):
        for mutate_on_version in (False, True):
            with self.subTest(mutate_on_version=mutate_on_version), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                renamed, output = root / 'renamed.a', root / 'restored.a'
                renamed.write_bytes(archive_bytes(self.objects(), self.rows, bsd=True))
                def mutate():
                    changed = self.objects()
                    payload = bytearray(changed[0][1])
                    section = boundary.MachObject(payload).sections[1]
                    payload[section['row'][4]] ^= 1
                    changed[0] = (changed[0][0], bytes(payload))
                    renamed.write_bytes(archive_bytes(changed, self.rows, bsd=True))
                def run(argv, **kwargs):
                    if str(argv[1]) == '-V':
                        if mutate_on_version:
                            mutate()
                        return subprocess.CompletedProcess(argv, 0, b'Apple Inc. version cctools_fixture\n', b'')
                    if not mutate_on_version:
                        mutate()
                    current = boundary.rust_archive.read_archive(renamed)
                    output.write_bytes(archive_bytes(
                        [(m.name.decode(), current.payload(m)) for m in current.members],
                        self.rows, bsd=True, sorted_toc=True))
                    return subprocess.CompletedProcess(argv, 0, b'', b'')
                with mock.patch.object(boundary, '_command', side_effect=run):
                    with self.assertRaisesRegex(ValueError, 'input archive'):
                        boundary._restore_macho_index(renamed, output, self.indexer,
                                                       logs=root / 'logs', records=[])


def native_controls(target, objcopy, output, sdkroot=None):
    """Explicit current-host observable isolation control, with retained sources."""
    expected = ('Linux', 'x86_64') if target == 'linux-x86_64' else ('Darwin', 'arm64')
    boundary._require((platform.system(), platform.machine()) == expected, 'native control requires matching host')
    boundary._require(not output.exists(), 'native control output exists');output.mkdir(parents=True)
    env = boundary._tool_environment()
    for name in ('CFLAGS', 'CPPFLAGS', 'LDFLAGS', 'CPATH', 'LIBRARY_PATH', 'MACOSX_DEPLOYMENT_TARGET', 'SDKROOT'):
        env.pop(name, None)
    if target == 'macos-arm64':
        boundary._require(sdkroot is not None and sdkroot.is_dir(), 'explicit macOS SDK required');env['SDKROOT'] = str(sdkroot)
    sources = {
        'state.c': 'int shared_state=10;__attribute__((weak))int shared_weak=4;_Thread_local int shared_tls=5;int same_runtime(void){return 7;}\n'
                   'int jnt_fixture_read(void){return shared_state+shared_weak+same_runtime()+ ++shared_tls;}\n',
        'user.c': 'extern int shared_state;int jnt_fixture_set(void){shared_state+=3;return shared_state;}\n',
        'weak.c': '__attribute__((weak))int shared_weak=400;\n',
        'consumer.c': 'int shared_state=100;__attribute__((weak))int shared_weak=40;_Thread_local int shared_tls=100;int same_runtime(void){return 41;}\n'
                      'extern int jnt_fixture_read(void),jnt_fixture_set(void);int main(void){if(jnt_fixture_read()!=27||jnt_fixture_set()!=13||jnt_fixture_read()!=31)return 1;'
                      'return shared_state!=100||shared_weak!=40||shared_tls!=100||same_runtime()!=41;}\n'}
    records = []
    def run(argv): return boundary._command(argv, cwd=output, env=env, logs=output / 'logs', records=records)
    for name, text in sources.items():
        (output / name).write_text(text)
        run(['cc', '-O0', '-fno-builtin', '-c', name, '-o', name.removesuffix('.c') + '.o'])
    run(['ar', 'crs', 'original.a', 'state.o', 'user.o', 'weak.o'])
    raw = subprocess.run(['cc', 'consumer.o', 'original.a', '-o', 'raw-must-fail'], cwd=output, env=env, capture_output=True)
    (output / 'raw.stderr').write_bytes(raw.stderr)
    boundary._require(raw.returncode != 0 and any(message in raw.stderr.lower()
                     for message in (b'duplicate', b'multiple definition')),
                     'competing original ownership was not exercised')
    exports = ('jnt_fixture_read', 'jnt_fixture_set')
    if target == 'macos-arm64': exports = tuple('_' + x for x in exports)
    proof = boundary.transform_archive(output / 'original.a', output / 'isolated.a', target=target,
        exports=exports, objcopy=objcopy, work=output / 'transform')
    run(['cc', 'consumer.o', 'isolated.a', '-o', 'isolated']);run([str(output / 'isolated')])
    (output / 'report.json').write_bytes(boundary._encoded({'pass': True, 'target': target, 'transform': proof,
        'commands': records, 'sources': {n: hashlib.sha256(s.encode()).hexdigest() for n, s in sources.items()},
        'scope': 'authored current-host correctness; no timing or target-floor claim'}))


if __name__ == '__main__':
    if '--native' in sys.argv:
        parser = argparse.ArgumentParser();parser.add_argument('--native', choices=('linux-x86_64', 'macos-arm64'), required=True)
        parser.add_argument('--objcopy', type=Path, required=True);parser.add_argument('--output', type=Path, required=True)
        parser.add_argument('--sdkroot', type=Path);args = parser.parse_args()
        native_controls(args.native, args.objcopy, args.output.absolute(), args.sdkroot)
    else:
        unittest.main()

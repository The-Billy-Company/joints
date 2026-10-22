#!/usr/bin/env python3
"""Checked opaque native C static-archive packaging derivatives.

The input archive remains immutable. Only approved compiler-only LLVM metadata
is removed. Every defined GLOBAL/WEAK symbol except the declared C exports gets
an archive-hash namespace; undefined references to owned names follow the same
map. Runtime/code/data/EH bytes and order, symbol attributes, relocation targets,
COMDAT/addrsig roles and archive member selection are checked after rewriting.
This C ABI derivative deliberately excludes embedded Rust LTO metadata. Native
Rust users should depend on joints-engine instead of this opaque C archive.

Supported objects are ELF64 little-endian x86_64 ET_REL and single-segment ARM64
MH_OBJECT. Unsupported linkage metadata refuses before publication; this is not
a generic object-file rewriter. rust_archive.py remains payload preserving.
"""
from __future__ import annotations

import hashlib
from collections.abc import Callable, Iterable, Mapping, Sequence
from functools import wraps
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile
from typing import TYPE_CHECKING, Literal, ParamSpec, TypeVar, cast

if TYPE_CHECKING:
    import rust_boundary_types as bt

import rust_archive

P = ParamSpec("P")
R = TypeVar("R")

SCHEMA = 1

# Explicit boundary families. JNT remains the default with identical proof shape.
# The additive IRGX ABI2 surface is the exact independently joined 105-function
# header/source/archive roster, not the narrower 28-function Rust binding subset.
JNT_ABI2 = 'jnt-abi2'
IRGX_ABI2 = 'irgx-abi2-105'
IRGX_MUNCH_IMAGE1 = 'irgx-abi2-108-munch-image1'
_IRGX_EXPORTS: tuple[str, ...] = (
    'irgx_abi_version',
    'irgx_cancel_free',
    'irgx_cancel_new',
    'irgx_cancel_request',
    'irgx_captures',
    'irgx_codex_build',
    'irgx_codex_count',
    'irgx_codex_extract',
    'irgx_codex_free',
    'irgx_codex_len',
    'irgx_codex_load',
    'irgx_codex_locate',
    'irgx_codex_max_text_len',
    'irgx_codex_measure',
    'irgx_codex_position',
    'irgx_codex_rows_extend',
    'irgx_codex_rows_whole',
    'irgx_codex_save',
    'irgx_compile',
    'irgx_compile_limited',
    'irgx_engine_close',
    'irgx_engine_open',
    'irgx_find_all',
    'irgx_find_all_in',
    'irgx_find_first',
    'irgx_find_first_in',
    'irgx_find_upto_in',
    'irgx_fold_orbit',
    'irgx_free',
    'irgx_group_count',
    'irgx_group_index',
    'irgx_group_name',
    'irgx_is_match',
    'irgx_is_match_in',
    'irgx_last_fault',
    'irgx_lines_context',
    'irgx_lines_count',
    'irgx_lines_split',
    'irgx_literals_free',
    'irgx_literals_open',
    'irgx_literals_promise',
    'irgx_literals_set',
    'irgx_matches_close',
    'irgx_matches_count',
    'irgx_matches_next',
    'irgx_matches_next_batch',
    'irgx_munch_compile',
    'irgx_munch_declined',
    'irgx_munch_free',
    'irgx_munch_len',
    'irgx_munch_scan',
    'irgx_munch_scan_metered',
    'irgx_needles_compile',
    'irgx_needles_describe',
    'irgx_needles_find_all',
    'irgx_needles_free',
    'irgx_needles_is_match',
    'irgx_needles_len',
    'irgx_needles_which',
    'irgx_pattern_earliest',
    'irgx_pattern_windows',
    'irgx_pcre2_version',
    'irgx_property_has',
    'irgx_property_ranges',
    'irgx_rows_close',
    'irgx_rows_next',
    'irgx_rows_next_batch',
    'irgx_rows_stats',
    'irgx_schema_count',
    'irgx_schema_digest',
    'irgx_schema_get',
    'irgx_sieve_alternation',
    'irgx_sieve_candidates',
    'irgx_sieve_close',
    'irgx_sieve_describe',
    'irgx_sieve_doc_path',
    'irgx_sieve_freshness',
    'irgx_sieve_literal',
    'irgx_sieve_open',
    'irgx_sieve_reading_list',
    'irgx_sieve_root',
    'irgx_sieve_stale_count',
    'irgx_slate_compile',
    'irgx_slate_free',
    'irgx_slate_is_match',
    'irgx_slate_len',
    'irgx_slate_which',
    'irgx_status_message',
    'irgx_tree_search',
    'irgx_unicode_version',
    'irgx_version',
    'irgx_walk_binary',
    'irgx_walk_close',
    'irgx_walk_count',
    'irgx_walk_gapped',
    'irgx_walk_genus',
    'irgx_walk_holds',
    'irgx_walk_limits',
    'irgx_walk_next',
    'irgx_walk_next_batch',
    'irgx_walk_open',
    'irgx_walk_rewind',
    'irgx_winnow_describe',
    'irgx_winnow_free',
    'irgx_winnow_of',
 )


# Image1 is an explicit additive family, never inferred from archive/header size.
_IRGX_IMAGE1_EXPORTS = tuple(sorted(_IRGX_EXPORTS + (
    'irgx_munch_clone_worker', 'irgx_munch_load', 'irgx_munch_save',
)))


def _family(abi_family: str) -> str:
    _require(abi_family in (JNT_ABI2, IRGX_ABI2, IRGX_MUNCH_IMAGE1), 'unsupported static C ABI family')
    return 'jnt_' if abi_family == JNT_ABI2 else 'irgx_'


def _valid_export(name: object) -> bool:
    return isinstance(name, str) and re.fullmatch(r'[_a-zA-Z][_a-zA-Z0-9]*', name) is not None


def _family_exports(exports: Iterable[str], target: str, abi_family: str) -> str:
    stem = _family(abi_family)
    _require(target in ('linux-x86_64', 'macos-arm64'), 'unsupported static boundary target')
    prefix = '_' if target == 'macos-arm64' else ''
    values = tuple(exports)
    _require(len(values) <= 4096 and all(_valid_export(n) for n in values),
             'malformed declared export')
    _require(len(values) == len(set(values)), 'duplicate declared export')
    values = tuple(sorted(values))
    if abi_family == IRGX_ABI2:
        _require(values == tuple(prefix + name for name in _IRGX_EXPORTS),
                 'IRGX ABI2 105-function export roster differs')
    elif abi_family == IRGX_MUNCH_IMAGE1:
        _require(values == tuple(prefix + name for name in _IRGX_IMAGE1_EXPORTS),
                 'IRGX ABI2 Image1 108-function export roster differs')
    return prefix + stem


def _family_fields(abi_family: str) -> bt.FamilyFields:
    # Historical JNT receipts/facts must retain their exact representation.
    return {} if abi_family == JNT_ABI2 else {'abi_family': abi_family}


def _checked_decode(function: Callable[P, R]) -> Callable[P, R]:
    @wraps(function)
    def checked(*args: P.args, **kwargs: P.kwargs) -> R:
        try:
            return function(*args, **kwargs)
        except (struct.error, UnicodeError, IndexError, KeyError, OverflowError) as error:
            raise ValueError('malformed static boundary data: ' + str(error)) from error
    return checked


def _require(ok: object, message: str) -> None:
    if not ok:
        raise ValueError(message)


def _digest(path: str | Path) -> str:
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for part in iter(lambda: stream.read(1 << 20), b''):
            h.update(part)
    return h.hexdigest()


def _encoded(value: object) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True, ensure_ascii=True) + '\n').encode()


def _command(argv: Sequence[str | Path], *, cwd: Path, env: Mapping[str, str],
             logs: Path, records: list[bt.CommandProof]) -> subprocess.CompletedProcess[bytes]:
    logs.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(list(map(str, argv)), cwd=cwd, env=env, capture_output=True)
    number = str(len(records)).zfill(3)
    channels: dict[str, bt.FileProof] = {}
    for channel, data in (('stdout', result.stdout), ('stderr', result.stderr)):
        path = logs / (number + '.' + channel)
        path.write_bytes(data)
        channels[channel] = {'path': str(path), 'sha256': _digest(path)}
    records.append({'argv': list(map(str, argv)), 'cwd': str(cwd),
                    'exit': result.returncode, 'stdout': channels['stdout'],
                    'stderr': channels['stderr']})
    _require(result.returncode == 0, 'static boundary tool refused: ' + str(argv[0]))
    return result


def _tool_environment() -> dict[str, str]:
    env = os.environ.copy()
    for key in ('LD_PRELOAD', 'LD_LIBRARY_PATH', 'DYLD_INSERT_LIBRARIES',
                'DYLD_LIBRARY_PATH', 'LLVM_PROFILE_FILE'):
        env.pop(key, None)
    return env



class ElfBudget:

    def __init__(self) -> None:
        (self.sections, self.symbols, self.relocations, self.name_bytes) = (0, 0, 0, 0)

    def add(self, key: Literal["sections", "symbols", "relocations", "name_bytes"],
            count: int, limit: int) -> None:
        total = cast(int, getattr(self, key)) + count
        _require(total <= limit, 'ELF proof resource limit: ' + key)
        setattr(self, key, total)

class ElfObject:

    def __init__(self, data: bt.Buffer, budget: ElfBudget | None = None) -> None:
        _require(len(data) <= 256 << 20 and len(data) >= 64, 'ELF object byte extent')
        _require(bytes(data[:6]) == b'\x7fELF\x02\x01', 'not ELF64 little endian')
        self.data = data
        self.budget = budget or ElfBudget()
        self.string_tables: dict[int, bytes] = {}
        self.string_cache: dict[tuple[int, int], str] = {}
        budget = self.budget
        self.header = cast("bt.ElfHeader", struct.unpack_from('<16sHHIQQQIHHHHHH', data))
        _require((self.header[1], self.header[2]) == (1, 62), 'not an x86-64 relocatable object')
        (start, width, count, names) = (self.header[6], self.header[11], self.header[12], self.header[13])
        _require(width == 64 and 0 < count < 65280 and (names < count) and (start + width * count <= len(data)), 'ELF section table outside object')
        budget.add('sections', count, 400000)
        self.sections = [cast("bt.ElfSection", struct.unpack_from('<IIQQQQIIQQ', data, start + i * width)) for i in range(count)]
        for section in self.sections:
            _require(section[1] == 8 or section[4] + section[5] <= len(data), 'ELF section outside object')
        self.names = [self.string(names, s[0]) for s in self.sections]
        tables = [i for (i, s) in enumerate(self.sections) if s[1] == 2]
        _require(len(tables) == 1, 'ELF must have one ordinary symbol table')
        self.table = tables[0]
        symbols = self.sections[self.table]
        _require(symbols[9] == 24 and symbols[5] % 24 == 0 and (symbols[6] < count) and (self.sections[symbols[6]][1] == 3), 'invalid ELF symbol table')
        number = symbols[5] // 24
        budget.add('symbols', number, 2000000)
        body = self.payload(self.table)
        self.symbols: list[bt.ElfSymbol] = []
        for at in range(0, symbols[5], 24):
            (name, info, other, index, value, size) = cast("tuple[int, int, int, int, int, int]", struct.unpack_from('<IBBHQQ', body, at))
            _require(index < count or index >= 65280, 'ELF symbol section index outside table')
            _require(index != 65535, 'extended ELF symbol indices unsupported')
            self.symbols.append((self.string(symbols[6], name), info, other, index, value, size))
        self.references: list[tuple[int, int, int, int | None, str]] = []
        self.groups: list[tuple[int, str, tuple[int, ...]]] = []
        self.address_significance: list[tuple[int, int, str]] = []
        self.address_significance_tables: list[tuple[int, bool]] = []
        for (i, section) in enumerate(self.sections):
            if section[1] in (4, 9):
                width = 24 if section[1] == 4 else 16
                _require(section[9] == width and section[5] % width == 0 and (section[6] == self.table), 'invalid ELF relocation table')
                budget.add('relocations', section[5] // width, 4000000)
                for at in range(0, section[5], width):
                    (offset, info) = cast("tuple[int, int]", struct.unpack_from('<QQ', self.payload(i), at))
                    (symbol, kind) = (info >> 32, info & 4294967295)
                    _require(symbol < number, 'ELF relocation symbol outside table')
                    addend = cast("tuple[int]", struct.unpack_from('<q', self.payload(i), at + 16))[0] if width == 24 else None
                    self.references.append((i, offset, kind, addend, self.symbols[symbol][0]))
            elif section[1] == 17:
                _require(section[6] == self.table and section[7] < number and (section[5] >= 4) and (section[5] % 4 == 0), 'invalid ELF COMDAT group')
                members = cast("tuple[int, ...]", struct.unpack_from('<' + 'I' * (section[5] // 4), self.payload(i)))
                _require(all((0 < member < count for member in members[1:])), 'ELF group section outside table')
                self.groups.append((i, self.symbols[section[7]][0], members))
            elif self.names[i] == '.llvm_addrsig':
                _require(section[6] in (0, self.table), 'LLVM address-significance symbol-table mismatch')
                self.address_significance_tables.append((i, section[6] != 0))
                if section[6] == 0:
                    continue
                (value, shift) = (0, 0)
                for byte in self.payload(i):
                    _require(shift < 64 and (shift < 63 or byte < 2), 'LLVM address-significance ULEB overflow')
                    value |= (byte & 127) << shift
                    if byte & 128:
                        shift += 7
                    else:
                        _require(value < number, 'LLVM address-significance symbol outside table')
                        budget.add('relocations', 1, 4000000)
                        self.address_significance.append((i, value, self.symbols[value][0]))
                        (value, shift) = (0, 0)
                _require(shift == 0, 'truncated LLVM address-significance index')

    def string(self, table: int, offset: int) -> str:
        key = (table, offset)
        if key in self.string_cache:
            return self.string_cache[key]
        if table not in self.string_tables:
            self.string_tables[table] = bytes(self.payload(table))
        data = self.string_tables[table]
        _require(offset < len(data), 'ELF string offset outside table')
        end = data.find(b'\x00', offset, offset + 65536)
        _require(end >= 0, 'unterminated ELF string')
        self.budget.add('name_bytes', end - offset, 64 << 20)
        value = data[offset:end].decode('utf-8', 'surrogateescape')
        self.string_cache[key] = value
        return value

    def payload(self, index: int) -> memoryview:
        section = self.sections[index]
        return memoryview(self.data)[section[4]:section[4] + section[5]] if section[1] != 8 else memoryview(b'')

def compare_elf(before: bt.Buffer, after: bt.Buffer, mapping: Mapping[str, str],
                *, removed: Sequence[str] = ()) -> bt.ElfProof:
    (a, b) = (ElfObject(before, ElfBudget()), ElfObject(after, ElfBudget()))
    deleted = {i for (i, name) in enumerate(a.names) if name in removed}
    for i in deleted:
        _require(a.names[i] in ('.llvmbc', '.llvmcmd') and a.sections[i][1] == 1 and (a.sections[i][2] & 2 == 0), 'cannot remove allocated/nonmetadata ELF payload')

    def string_roles(elf: ElfObject) -> tuple[dict[str, int], set[int]]:
        roles = {'sections': elf.header[13], 'symbols': elf.sections[elf.table][6]}
        indices = set(roles.values())
        _require({i for (i, section) in enumerate(elf.sections) if section[1] == 3} == indices, 'orphan/additional ELF string table')
        for index in indices:
            section = elf.sections[index]
            _require(index > 0 and (section[1], section[2], section[3]) == (3, 0, 0) and ((section[6], section[7], section[8], section[9]) == (0, 0, 1, 0)), 'ELF linkage string-table attributes changed')
            payload = elf.payload(index)
            _require(len(payload) > 0 and payload[0] == payload[-1] == 0, 'ELF linkage string-table encoding invalid')
            _require(not any((symbol[3] == index for symbol in elf.symbols)), 'ELF symbol points into linkage string table')
            for (other, consumer) in enumerate(elf.sections):
                if consumer[6] == index:
                    _require(other == elf.table, 'unapproved ELF string-table consumer')
                if consumer[7] == index and (consumer[1] in (4, 9) or consumer[2] & 64):
                    _require(False, 'ELF relocation/info consumes linkage string table')
        return (roles, indices)
    (roles_a, strings_a) = string_roles(a)
    (roles_b, strings_b) = string_roles(b)
    split = len(strings_a) == 1 and len(strings_b) == 2
    _require(len(strings_a) == len(strings_b) or split, 'ELF string-table role topology changed')
    retained = [i for i in range(len(a.sections)) if i not in deleted]
    groups_a = {i for (i, _, _) in a.groups}
    groups_b = {i for (i, _, _) in b.groups}
    ordinary_a = [i for i in retained if i not in strings_a | groups_a]
    ordinary_b = [i for i in range(len(b.sections)) if i not in strings_b | groups_b]
    _require([a.names[i] for i in ordinary_a] == [b.names[i] for i in ordinary_b], 'ELF non-string section identity/order changed')
    positions = dict(zip(ordinary_a, ordinary_b))
    _require(len(a.groups) == len(b.groups), 'ELF COMDAT group count changed')
    expected_groups = []
    for (index, signature, members) in a.groups:
        _require(all((member in positions for member in members[1:])), 'ELF group member not an ordinary surviving section')
        expected_groups.append((mapping.get(signature, signature), members[0], tuple((positions[m] for m in members[1:]))))
    actual_groups = [(signature, members[0], tuple(members[1:])) for (_, signature, members) in b.groups]
    _require(expected_groups == actual_groups and len(set(expected_groups)) == len(expected_groups), 'ELF COMDAT ordered identity/membership changed')
    positions.update(((left[0], right[0]) for (left, right) in zip(a.groups, b.groups)))
    positions[roles_a['symbols']] = roles_b['symbols']
    if not split:
        positions[roles_a['sections']] = roles_b['sections']
    else:
        _require(a.names[roles_a['sections']] == b.names[roles_b['symbols']] == '.strtab' and b.names[roles_b['sections']] == '.shstrtab', 'unapproved ELF string-table split')
    _require(all((a.names[i] == b.names[positions[i]] for i in retained)), 'ELF section rename beyond name-table split')
    (header_a, header_b) = (list(a.header), list(b.header))
    for row in (header_a, header_b):
        row[6] = row[12] = row[13] = 0
    _require(header_a == header_b, 'ELF nonlayout header changed')
    _require(len(a.symbols) == len(b.symbols), 'ELF symbol count changed')

    def adjusted(symbol: bt.ElfSymbol) -> bt.ElfSymbol:
        (name, info, other, section, value, size) = symbol
        if 0 < section < 65280:
            _require(section not in deleted, 'ELF symbol depends on removed metadata')
            section = positions[section]
        return (mapping.get(name, name), info, other, section, value, size)
    for (old_symbol, new_symbol) in zip(a.symbols, b.symbols):
        _require(adjusted(old_symbol) == new_symbol, 'ELF symbol/index/attribute changed beyond mapping')
    section_hash = hashlib.sha256()
    for i in retained:
        j = positions[i]
        (old, new) = (a.sections[i], b.sections[j])
        (left, right) = (list(old), list(new))
        for value in (left, right):
            value[0] = value[4] = 0
            if old[1] == 3:
                value[5] = 0
        if old[6]:
            _require(old[6] not in deleted, 'ELF section link depends on removed metadata')
            left[6] = positions[old[6]]
        if old[7] and (old[1] in (4, 9) or old[2] & 64):
            _require(old[7] not in deleted, 'ELF section info depends on removed metadata')
            left[7] = positions[old[7]]
        _require(left == right, 'ELF section attributes changed')
        if old[1] == 17:
            values = cast("tuple[int, ...]", struct.unpack_from('<' + 'I' * (old[5] // 4), a.payload(i)))
            _require(all((index not in deleted for index in values[1:])), 'ELF group depends on removed metadata')
            expected = struct.pack('<' + 'I' * len(values), values[0], *(positions[index] for index in values[1:]))
            _require(expected == b.payload(j), 'ELF COMDAT membership changed')
        elif old[1] not in (2, 3):
            _require(a.payload(i) == b.payload(j), 'ELF nonlinkage section payload changed')
            section_hash.update(_encoded([i, a.names[i], old[1], hashlib.sha256(a.payload(i)).hexdigest()]))
    _require([(positions[i], o, k, addend, mapping.get(n, n)) for (i, o, k, addend, n) in a.references] == b.references, 'ELF relocation reference changed beyond mapping')
    _require([(positions[i], mapping.get(n, n), (m[0], *(positions[index] for index in m[1:]))) for (i, n, m) in a.groups] == b.groups, 'ELF COMDAT signature changed beyond mapping')
    _require([(positions[i], active) for (i, active) in a.address_significance_tables] == b.address_significance_tables, 'LLVM address-significance active/inactive semantics changed')
    _require([(positions[i], index, mapping.get(name, name)) for (i, index, name) in a.address_significance] == b.address_significance, 'LLVM address-significance semantic target changed')
    globals_before = [adjusted(s) for s in a.symbols if s[1] >> 4 in (1, 2, 10) and s[3] != 0 and (s[0] not in mapping)]
    mapped_names = set(mapping.values())
    globals_after = [s for s in b.symbols if s[1] >> 4 in (1, 2, 10) and s[3] != 0 and (s[0] not in mapped_names)]
    _require(globals_before == globals_after, 'other ELF globals/exports changed')
    return {'symbols': len(a.symbols), 'sections': len(a.sections), 'relocations': len(a.references), 'groups': len(a.groups), 'string_table_split': split, 'group_headers_moved': any((positions[i] != i for i in groups_a)), 'address_significance_targets': len(a.address_significance), 'address_significance_tables': [{'section': a.names[i], 'active': active, 'payload_sha256': hashlib.sha256(a.payload(i)).hexdigest()} for (i, active) in a.address_significance_tables], 'unchanged_nonlinkage_sections_sha256': section_hash.hexdigest(), 'other_globals_sha256': hashlib.sha256(_encoded(globals_before)).hexdigest()}

class MachBudget:

    def __init__(self) -> None:
        self.sections = 0
        self.symbols = 0
        self.relocations = 0
        self.names = 0

    def add(self, key: Literal["sections", "symbols", "relocations", "names"],
            n: int, limit: int) -> None:
        value = cast(int, getattr(self, key)) + n
        _require(value <= limit, 'Mach-O proof resource limit: ' + key)
        setattr(self, key, value)

class MachObject:

    def __init__(self, data: bt.Buffer, budget: MachBudget | None = None) -> None:
        self.data = data
        self.budget = budget or MachBudget()
        b = self.budget
        _require(32 <= len(data) <= 256 << 20, 'Mach-O object extent')
        self.header = cast("bt.MachHeader", struct.unpack_from('<IiiIIIII', data))
        h = self.header
        _require(h[0] == 4277009103 and h[1] == 16777228 and (h[3] == 1), 'not ARM64 Mach-O object')
        _require(h[4] <= 65536 and h[5] <= len(data) - 32, 'Mach-O load-command extent')
        self.commands: list[bt.MachCommand] = []
        self.sections: list[bt.MachSection] = []
        self.symtab: tuple[int, int, int, int] | None = None
        self.dysymtab: tuple[int, ...] | None = None
        self.linkedit: list[bt.MachCommand] = []
        pos = 32
        for _ in range(h[4]):
            (tag, size) = cast("tuple[int, int]", struct.unpack_from('<II', data, pos))
            _require(size >= 8 and size % 8 == 0 and (pos + size <= 32 + h[5]), 'Mach-O command outside table')
            row: bt.MachCommand = {'tag': tag, 'size': size, 'raw': bytes(data[pos:pos + size])}
            if tag == 25:
                _require(size >= 72, 'short Mach-O segment')
                segment = cast("bt.MachSegment", struct.unpack_from('<II16sQQQQiiII', data, pos))
                n = segment[-2]
                _require(size == 72 + 80 * n, 'Mach-O segment section table extent')
                b.add('sections', n, 400000)
                _require(segment[5] + segment[6] <= len(data), 'Mach-O segment file extent')
                row['segment'] = segment
                row['sections'] = []
                for i in range(n):
                    s = cast("bt.MachSectionRow", struct.unpack_from('<16s16sQQIIIIIIII', data, pos + 72 + 80 * i))
                    (name, seg) = (v.rstrip(b'\x00').decode('ascii') for v in (s[0], s[1]))
                    kind = s[8] & 255
                    _require(s[5] <= 63 and (kind in (1, 12, 18) or s[4] + s[3] <= len(data)), 'Mach-O section extent/alignment')
                    _require(s[6] + 8 * s[7] <= len(data), 'Mach-O relocations outside object')
                    b.add('relocations', s[7], 4000000)
                    sec: bt.MachSection = {'row': s, 'name': name, 'segment': seg, 'key': (seg, name), 'ordinal': len(self.sections) + 1, 'payload': bytes(data[s[4]:s[4] + s[3]]) if kind not in (1, 12, 18) else b'', 'relocations': []}
                    for j in range(s[7]):
                        (address, info) = cast("tuple[int, int]", struct.unpack_from('<II', data, s[6] + 8 * j))
                        _require(address < 2147483648 and address < s[3], 'Mach-O scattered/outside-section relocation')
                        symbol = info & 16777215
                        external = info >> 27 & 1
                        typ = info >> 28
                        _require(typ <= 11 and (not (typ == 10 and external)), 'unsupported ARM64 relocation')
                        sec['relocations'].append((address, info >> 24, symbol))
                    self.sections.append(sec)
                    row['sections'].append(sec)
            elif tag == 2:
                _require(size == 24 and self.symtab is None, 'invalid/duplicate Mach-O symtab')
                self.symtab = cast("tuple[int, int, int, int]", struct.unpack_from('<IIII', data, pos + 8))
            elif tag == 11:
                _require(size == 80 and self.dysymtab is None, 'invalid/duplicate Mach-O dysymtab')
                self.dysymtab = cast("tuple[int, ...]", struct.unpack_from('<18I', data, pos + 8))
            elif tag in (41, 46):
                _require(size == 16, 'Mach-O linkedit command size')
                (off, n) = cast("tuple[int, int]", struct.unpack_from('<II', data, pos + 8))
                _require(off + n <= len(data), 'Mach-O linkedit payload outside object')
                _require(tag != 41 or n == 0, 'nonempty data-in-code requires semantic file-range proof')
                row['payload'] = bytes(data[off:off + n])
                self.linkedit.append(row)
            elif tag == 50:
                _require(size >= 24 and size == 24 + 8 * cast("tuple[int]", struct.unpack_from('<I', data, pos + 20))[0], 'Mach-O build-version size')
            else:
                raise ValueError('unsupported Mach-O object load command')
            self.commands.append(row)
            pos += size
        _require(pos == 32 + h[5], 'Mach-O command coverage/symbol roles')
        if self.symtab is None or self.dysymtab is None:
            raise ValueError('Mach-O command coverage/symbol roles')
        _require(sum((c['tag'] == 25 for c in self.commands)) == 1, 'multiple Mach-O segments require separate membership proof')
        (so, count, st, n) = self.symtab
        _require(so + 16 * count <= len(data) and st + n <= len(data), 'Mach-O symbols/strings outside object')
        b.add('symbols', count, 2000000)
        strings = bytes(data[st:st + n])
        self.symbols: list[bt.MachSymbol] = []
        for i in range(count):
            (at, t, se, de, v) = cast("tuple[int, int, int, int, int]", struct.unpack_from('<IBBHQ', data, so + 16 * i))
            _require(at < len(strings), 'Mach-O symbol string outside table')
            end = strings.find(b'\x00', at, min(len(strings), at + 65536))
            _require(end >= 0, 'Mach-O unterminated symbol')
            b.add('names', end - at, 64 << 20)
            name = strings[at:end].decode('ascii')
            _require(se <= len(self.sections), 'Mach-O symbol section outside table')
            _require(t & 14 != 10 or t & 224, 'Mach-O indirect alias requires semantic target proof')
            self.symbols.append((name, t, se, de, v))
        for sec in self.sections:
            for (address, attrs, index) in sec['relocations']:
                external = attrs >> 3 & 1
                typ = attrs >> 4
                if external:
                    _require(index < count, 'Mach-O relocation symbol outside table')
                elif typ != 10:
                    _require(index <= len(self.sections), 'Mach-O local relocation section outside table')
        dy = self.dysymtab
        _require(all((x == 0 for x in dy[6:])), 'Mach-O auxiliary dysymtab tables require separate proof')
        _require(dy[0] == 0 and dy[0] + dy[1] == dy[2] and (dy[2] + dy[3] == dy[4]) and (dy[4] + dy[5] == count), 'Mach-O dysymtab windows incomplete')
        for (start, n, role) in ((dy[0], dy[1], 'local'), (dy[2], dy[3], 'defined'), (dy[4], dy[5], 'undefined')):
            for (name, t, se, de, v) in self.symbols[start:start + n]:
                if role == 'local':
                    _require(not t & 1 or t & 224, 'global symbol in local Mach-O window')
                elif role == 'defined':
                    _require(t & 1 and t & 14 != 0, 'non-definition in Mach-O defined window')
                else:
                    _require(t & 1 and t & 14 == 0 and (v == 0), 'non-import in Mach-O undefined window')

    def section(self, ordinal: int) -> bt.MachSection:
        return self.sections[ordinal - 1]

def compare_macho(before: bt.Buffer, after: bt.Buffer, mapping: Mapping[str, str],
                  remove: bool = False) -> bt.MachProof:
    (a, b) = (MachObject(before), MachObject(after))
    deleted = {s['ordinal'] for s in a.sections if remove and s['key'] in (('__LLVM', '__bitcode'), ('__LLVM', '__cmdline'))}
    for index in deleted:
        s = a.section(index)
        _require(s['row'][8] == 0 and (not s['relocations']), 'metadata has runtime attributes/relocations')
    _require(all((s['segment'] != '__LLVM' or s['ordinal'] in deleted for s in a.sections)) if remove else True, 'unapproved LLVM metadata')
    kept = [s for s in a.sections if s['ordinal'] not in deleted]
    _require([s['key'] for s in kept] == [s['key'] for s in b.sections], 'Mach-O runtime section identity/order changed')
    secmap = {old_section['ordinal']: new_section['ordinal'] for (old_section, new_section) in zip(kept, b.sections)}
    gone = set()
    for (i, (name, t, se, de, v)) in enumerate(a.symbols):
        if se in deleted:
            _require(t == 14 and de == 0, 'removed metadata owns nonlocal/aliased symbol')
            _require(a.section(se)['row'][2] <= v <= a.section(se)['row'][2] + a.section(se)['row'][3], 'metadata local label outside section')
            gone.add(i)
    retained = [i for i in range(len(a.symbols)) if i not in gone]
    _require(len(retained) == len(b.symbols), 'Mach-O surviving symbol count changed')
    symmap = {old: new for (new, old) in enumerate(retained)}
    for (old, new) in symmap.items():
        (name, t, se, de, v) = a.symbols[old]
        expected_symbol = (mapping.get(name, name), t, secmap[se] if se else 0, de, v)
        _require(expected_symbol == b.symbols[new], 'Mach-O symbol name/attribute/address changed')
    runtime: list[bt.RuntimeSection] = []
    for (old_section, new_section) in zip(kept, b.sections):
        (x, y) = (list(old_section['row']), list(new_section['row']))
        for row in (x, y):
            row[4] = row[6] = 0
        _require(x == y, 'Mach-O runtime section virtual address/role/alignment changed')
        _require(old_section['payload'] == new_section['payload'], 'Mach-O runtime/code/data/EH payload changed')
        expected_relocations: list[bt.Relocation] = []
        for (address, attrs, index) in old_section['relocations']:
            if attrs >> 3 & 1:
                _require(index in symmap, 'runtime relocation references removed metadata symbol')
                index = symmap[index]
            elif attrs >> 4 != 10 and index:
                _require(index in secmap, 'runtime relocation references removed metadata section')
                index = secmap[index]
            expected_relocations.append((address, attrs, index))
        _require(expected_relocations == new_section['relocations'], 'Mach-O relocation semantic target/attributes/order changed')
        runtime.append({'section': old_section['key'], 'address': old_section['row'][2], 'bytes': old_section['row'][3], 'payload_sha256': hashlib.sha256(old_section['payload']).hexdigest(), 'relocations': len(expected_relocations)})
    (ah, bh) = (list(a.header), list(b.header))
    ah[5] = bh[5] = 0
    _require(ah == bh and b.header[5] == a.header[5] - 80 * len(deleted), 'Mach-O nonlayout header changed')
    _require(len(a.commands) == len(b.commands), 'Mach-O load-command count changed')
    for (left, right) in zip(a.commands, b.commands):
        _require(left['tag'] == right['tag'], 'Mach-O command order changed')
        tag = left['tag']
        if tag == 25:
            (x, y) = (list(left['segment']), list(right['segment']))
            for row in (x, y):
                row[1] = row[5] = row[6] = row[9] = 0
            _require(x == y, 'Mach-O segment virtual extent/protection changed')
        elif tag == 2:
            pass
        elif tag == 11:
            expected_windows: list[int] = []
            assert a.dysymtab is not None and b.dysymtab is not None
            for (start, n) in zip(a.dysymtab[0:6:2], a.dysymtab[1:6:2]):
                expected_windows.extend((sum((i < start for i in retained)), sum((start <= i < start + n for i in retained))))
            _require(tuple(expected_windows) == b.dysymtab[:6] and a.dysymtab[6:] == b.dysymtab[6:], 'Mach-O dysymtab roles changed')
        elif tag in (41, 46):
            _require(left['payload'] == right['payload'], 'Mach-O linkedit semantic payload changed')
        else:
            _require(left['raw'] == right['raw'], 'Mach-O version/load-command payload changed')
    return {'sections': len(a.sections), 'surviving_sections': len(kept), 'symbols': len(a.symbols), 'surviving_symbols': len(retained), 'removed_local_metadata_symbols': len(gone), 'runtime': runtime, 'relocations': sum((len(s['relocations']) for s in kept))}

def elf_index(path: Path) -> bt.Index:
    archive = rust_archive.read_archive(path)
    data = archive.data
    member_ends = {m.end: i for (i, m) in enumerate(archive.members)}
    headers = {}
    table = None
    position = 8
    while position < len(data):
        header = data[position:position + 60]
        _require(len(header) == 60 and header[58:] == b'`\n', 'invalid armap header')
        field = header[48:58].strip()
        _require(field.isdigit(), 'invalid armap member extent')
        size = int(field)
        start = position + 60
        end = start + size
        _require(end <= len(data), 'armap member outside archive')
        name = header[:16].rstrip(b' ')
        if name in (b'/', b'/SYM64/'):
            _require(table is None, 'duplicate ar symbol index')
            table = (8 if name == b'/SYM64/' else 4, data[start:end])
        elif name.startswith(b'__.SYMDEF'):
            raise ValueError('BSD archive index requires separate proof')
        if end in member_ends:
            i = member_ends[end]
            _require(start <= archive.members[i].start < end, 'armap object payload mismatch')
            headers[position] = i
        position = end + (size & 1)
    if table is None or len(headers) != len(archive.members):
        raise ValueError('missing GNU armap/object index')
    (width, payload) = table
    _require(len(payload) >= width, 'truncated armap count')
    count = int.from_bytes(payload[:width], 'big')
    _require(count <= 2000000 and width * (count + 1) <= len(payload) <= 128 << 20, 'armap resource/offset extent')
    at = width * (count + 1)
    rows: list[tuple[str, int]] = []
    by_name: dict[str, list[int]] = {}
    for i in range(count):
        offset = int.from_bytes(payload[width * (i + 1):width * (i + 2)], 'big')
        _require(offset in headers, 'armap references non-object header')
        end = payload.find(b'\x00', at, min(len(payload), at + 65536))
        _require(end >= 0, 'unterminated armap symbol')
        symbol_name = payload[at:end].decode('ascii')
        _require(symbol_name, 'empty armap symbol')
        at = end + 1
        member = headers[offset]
        rows.append((symbol_name, member))
        by_name.setdefault(symbol_name, []).append(member)
    _require(len(payload) - at <= 7 and (not any(payload[at:])), 'unexpected armap trailing bytes')
    return {'entries': rows, 'member_selection': by_name, 'member_selection_sha256': hashlib.sha256(_encoded(by_name)).hexdigest(), 'archive_sha256': _digest(path)}

def compare_elf_index(before: Path, after: Path, mapping: Mapping[str, str]) -> bt.IndexProof:
    (a, b) = (elf_index(before), elf_index(after))
    _require([(mapping.get(name, name), member) for (name, member) in a['entries']] == b['entries'], 'archive symbol-index complete entry order changed beyond namespace')
    expected = {mapping.get(name, name): members for (name, members) in a['member_selection'].items()}
    _require(len(expected) == len(a['member_selection']) and expected == b['member_selection'], 'archive symbol-index/member-selection changed beyond namespace')
    return {'before': a, 'after': b}

def macho_index(path: Path) -> bt.MachIndex:
    a = rust_archive.read_archive(path)
    data = a.data
    ends = {m.end: i for (i, m) in enumerate(a.members)}
    headers = {}
    table = None
    pos = 8
    while pos < len(data):
        h = data[pos:pos + 60]
        _require(len(h) == 60 and h[58:] == b'`\n', 'invalid BSD ar header')
        field = h[48:58].strip()
        _require(field.isdigit(), 'invalid BSD ar extent')
        size = int(field)
        start = pos + 60
        end = start + size
        _require(end <= len(data), 'BSD ar member outside file')
        name = h[:16].rstrip(b' ')
        body = start
        if name.startswith(b'#1/'):
            _require(name[3:].isdigit(), 'invalid BSD name extent')
            n = int(name[3:])
            _require(n <= size and n <= 65536, 'BSD name outside member')
            name = data[start:start + n].rstrip(b'\x00')
            body += n
        if name in (b'__.SYMDEF', b'__.SYMDEF SORTED'):
            _require(table is None, 'duplicate BSD armap')
            table = (name, data[body:end])
        elif name.startswith(b'__.SYMDEF') or name in (b'/', b'/SYM64/'):
            raise ValueError('unsupported mixed/64-bit BSD TOC')
        if end in ends:
            i = ends[end]
            _require(body <= a.members[i].start < end, 'BSD object payload mismatch')
            headers[pos] = i
        pos = end + (size & 1)
    if table is None or len(headers) != len(a.members):
        raise ValueError('missing BSD TOC/object index')
    (name, payload) = table
    _require(len(payload) >= 8, 'truncated BSD TOC')
    n = int.from_bytes(payload[:4], 'little')
    _require(n % 8 == 0 and n // 8 <= 2000000 and (n + 8 <= len(payload) <= 128 << 20), 'BSD TOC resource/extent')
    count = n // 8
    length = int.from_bytes(payload[4 + n:8 + n], 'little')
    strings = payload[8 + n:8 + n + length]
    _require(8 + n + length <= len(payload) and len(payload) - (8 + n + length) <= 7 and (not any(payload[8 + n + length:])), 'BSD TOC strings/trailing extent')
    rows: list[tuple[str, int]] = []
    by: dict[str, list[int]] = {}
    for i in range(count):
        at = int.from_bytes(payload[4 + 8 * i:8 + 8 * i], 'little')
        offset = int.from_bytes(payload[8 + 8 * i:12 + 8 * i], 'little')
        _require(at < len(strings) and offset in headers, 'BSD TOC invalid symbol/member')
        end = strings.find(b'\x00', at, min(len(strings), at + 65536))
        _require(end >= 0, 'BSD TOC unterminated symbol')
        symbol = strings[at:end].decode('ascii')
        _require(symbol, 'BSD TOC empty symbol')
        member = headers[offset]
        rows.append((symbol, member))
        by.setdefault(symbol, []).append(member)
    sorted_toc = name.endswith(b' SORTED')
    if sorted_toc:
        _require([n for (n, _) in rows] == sorted((n for (n, _) in rows)), 'invalid SORTED BSD TOC')
    return {'kind': name.decode(), 'sorted': sorted_toc, 'entries': rows, 'member_selection': by, 'archive_sha256': _digest(path), 'member_selection_sha256': hashlib.sha256(_encoded(by)).hexdigest()}

def _index_entry_name(row: tuple[str, int]) -> str:
    return row[0]

def compare_macho_index(before: Path, after: Path, mapping: Mapping[str, str]) -> bt.MachIndexProof:
    (a, b) = (macho_index(before), macho_index(after))
    _require(a['kind'] == b['kind'], 'BSD TOC kind changed')
    expected = [(mapping.get(name, name), member) for (name, member) in a['entries']]
    if a['sorted']:
        expected.sort(key=_index_entry_name)
    _require(expected == b['entries'], 'BSD TOC row/member selection changed beyond namespace/sort')
    by = {mapping.get(name, name): members for (name, members) in a['member_selection'].items()}
    _require(len(by) == len(a['member_selection']) and by == b['member_selection'], 'BSD TOC duplicate member priority changed')
    return {'before': a, 'after': b, 'sorted_reorder': a['sorted'] and a['entries'] != expected}

ELF_SPECIAL = {'_GLOBAL_OFFSET_TABLE_', '__ehdr_start', '__dso_handle', '__TMC_END__', '_DYNAMIC', '_init', '_fini', '__bss_start', '_end', '_edata', '__data_start', 'data_start', '__init_array_start', '__init_array_end', '__fini_array_start', '__fini_array_end', '__preinit_array_start', '__preinit_array_end', '__executable_start'}

def _plan_elf(path: Path, exports: Sequence[str], *, abi_family: str = JNT_ABI2
              ) -> tuple[rust_archive.Archive, list[ElfObject], bt.Policy]:
    public_prefix = _family_exports(exports, 'linux-x86_64', abi_family)
    archive = rust_archive.read_archive(path)
    budget = ElfBudget()
    elves: list[ElfObject] = []
    defined: dict[str, list[tuple[str, bt.ElfSymbol]]] = {}
    undefined: set[str] = set()
    names = set()
    exports = tuple(sorted(exports))
    _require(len(set(exports)) == len(exports), 'duplicate declared export')
    for member in archive.members:
        elf = ElfObject(archive.payload(member), budget)
        elves.append(elf)
        for symbol in elf.symbols:
            (name, info, other, section, value, size) = symbol
            (binding, kind) = (info >> 4, info & 15)
            names.add(name)
            if binding == 0:
                continue
            _require(binding in (1, 2), 'unapproved global ELF binding')
            if not section:
                undefined.add(name)
                continue
            _require(section < 65280 and kind in (0, 1, 2, 6), 'special defined ELF symbol')
            _require(name not in ELF_SPECIAL and (not name.startswith(('__start_', '__stop_', '__wrap_', '__real_'))) and ('@' not in name), 'linker/CRT defined symbol needs review')
            _require(name and name.isascii() and (not any((c.isspace() for c in name))) and ('=' not in name), 'unrepresentable closed-map symbol')
            defined.setdefault(name, []).append((member.name.decode(), symbol))
    _require(set(exports) <= defined.keys() and {n for n in defined if n.startswith(public_prefix)} == set(exports), 'declared C export roster mismatch')
    for name in exports:
        rows = defined[name]
        _require(len(rows) == 1 and rows[0][1][1] == 18, 'C export needs one strong function definition')
    prefix = '__' + _family(abi_family).removesuffix('_') + '_opaque_elf_' + _digest(path) + '_'
    mapping = {name: prefix + name for name in sorted(set(defined) - set(exports))}
    _require(not set(mapping.values()) & names, 'opaque namespace collision')
    policy: bt.Policy = {'before_sha256': _digest(path), 'prefix': prefix, 'mapping': mapping, 'c_exports': list(exports), 'unresolved_imports': sorted(undefined - set(defined)), 'defined_names': len(defined), 'global_weak_definitions': sum((len(x) for x in defined.values()))}
    if abi_family != JNT_ABI2:
        policy['abi_family'] = abi_family
    return (archive, elves, policy)

def _transform_elf(original: Path, output: Path, logs: Path, exports: Sequence[str],
                   objcopy: Path, expected_plan: Mapping[str, object] | None = None,
                   *, abi_family: str = JNT_ABI2) -> bt.Transform:
    _require(not output.exists(), 'opaque derivative exists')
    (source, inventory, policy) = _plan_elf(original, exports, abi_family=abi_family)
    if expected_plan is not None:
        _require(policy['before_sha256'] == expected_plan['before_archive_sha256']
                 and policy['mapping'] == expected_plan['mapping']
                 and policy['c_exports'] == expected_plan['declared_exports']
                 and policy['unresolved_imports'] == expected_plan['unresolved_imports'],
                 'frozen inventory/map mismatch')
    output.parent.mkdir(parents=True, exist_ok=True)
    logs.mkdir(parents=True, exist_ok=True)
    mapfile = logs.parent / 'mapping.txt'
    _require(not mapfile.exists(), 'mapping file exists')
    mapfile.write_text(''.join((a + ' ' + b + '\n' for (a, b) in policy['mapping'].items())))
    records: list[bt.CommandProof] = []
    env = _tool_environment()
    version = _command([str(objcopy), '--version'], cwd=logs.parent, env=env, logs=logs, records=records).stdout.decode()
    mapping = policy['mapping']
    removed: list[bt.ElfRemoval] = []
    for (member, elf) in zip(source.members, inventory):
        for (i, name) in enumerate(elf.names):
            if name in ('.llvm.lto', '.llvm_bc', '__bitcode') or name.startswith('.gnu.lto_'):
                raise ValueError('unapproved embedded LTO payload')
            if name in ('.llvmbc', '.llvmcmd'):
                section = elf.sections[i]
                _require(section[1] == 1 and section[2] & 2 == 0, 'allocated/nonmetadata LLVM removal refused')
                removed.append({'member': member.name.decode(), 'section': name, 'index': i, 'bytes': section[5], 'flags': section[2], 'sha256': hashlib.sha256(elf.payload(i)).hexdigest()})
    machine_path = output.with_suffix('.machine-code.a')
    machine = source
    removal_proofs: list[bt.ElfMemberProof] = []
    if removed:
        _require(not machine_path.exists(), 'machine-code intermediate exists')
        _command([str(objcopy), '--remove-section=.llvmbc', '--remove-section=.llvmcmd', str(original), str(machine_path)], cwd=logs.parent, env=env, logs=logs, records=records)
        machine = rust_archive.read_archive(machine_path)
        _require([m.name for m in source.members] == [m.name for m in machine.members], 'metadata removal changed member order')
        for (old, new) in zip(source.members, machine.members):
            proof = compare_elf(source.payload(old), machine.payload(new), {}, removed=('.llvmbc', '.llvmcmd'))
            elf = ElfObject(machine.payload(new), ElfBudget())
            _require(not any((n in ('.llvmbc', '.llvmcmd') for n in elf.names)), 'LLVM metadata remains')
            removal_proofs.append({'member': old.name.decode(), 'before_sha256': hashlib.sha256(source.payload(old)).hexdigest(), 'after_sha256': hashlib.sha256(machine.payload(new)).hexdigest(), **proof})
    else:
        machine_path = original
    _command([str(objcopy), '--redefine-syms=' + str(mapfile), str(machine_path), str(output)], cwd=logs.parent, env=env, logs=logs, records=records)
    index_proof = compare_elf_index(original, output, mapping)
    after = rust_archive.read_archive(output)
    _require([m.name for m in source.members] == [m.name for m in after.members], 'namespace changed member order')
    proofs: list[bt.ElfMemberProof] = []
    after_defined: set[str] = set()
    after_undefined: set[str] = set()
    after_names: set[str] = set()
    for (old, new) in zip(machine.members, after.members):
        proof = compare_elf(machine.payload(old), after.payload(new), mapping)
        elf = ElfObject(after.payload(new), ElfBudget())
        after_names.update((s[0] for s in elf.symbols))
        for (name, info, other, symbol_section, value, size) in elf.symbols:
            if info >> 4 in (1, 2):
                (after_defined if symbol_section else after_undefined).add(name)
        proofs.append({'member': old.name.decode(), 'before_sha256': hashlib.sha256(machine.payload(old)).hexdigest(), 'after_sha256': hashlib.sha256(after.payload(new)).hexdigest(), **proof})
    _require(not set(mapping) & after_names, 'old private definition/reference remains')
    _require(after_defined == set(exports) | set(mapping.values()), 'public/private defined-symbol closure changed')
    imports = sorted(after_undefined - after_defined)
    _require(imports == policy['unresolved_imports'], 'unresolved system-import closure changed')
    _require(_digest(original) == policy['before_sha256'], 'original archive changed')
    result: bt.Transform = {'schema': 1, 'kind': 'opaque-C-static-boundary', 'machine_code_only': True, 'before_sha256': policy['before_sha256'], 'prefix': policy['prefix'], 'mapping': policy['mapping'], 'c_exports': policy['c_exports'], 'unresolved_imports': policy['unresolved_imports'], 'defined_names': policy['defined_names'], 'after_sha256': _digest(output), 'unresolved_imports_sha256': hashlib.sha256(_encoded(imports)).hexdigest(), 'mapping_file_sha256': _digest(mapfile), 'tool': {'path': str(objcopy), 'sha256': _digest(objcopy), 'version': version}, 'archive_index': index_proof, 'commands': records, 'removed_sections': removed, 'metadata_removal_members': removal_proofs, 'members': proofs, 'machine_archive_sha256': _digest(machine_path), 'proof_sources': {'rust_static_boundary.py': _digest(Path(__file__))}}
    if abi_family != JNT_ABI2:
        result['abi_family'] = abi_family
    if 'global_weak_definitions' in policy:
        result['global_weak_definitions'] = policy['global_weak_definitions']
    if 'global_definitions' in policy:
        result['global_definitions'] = policy['global_definitions']
    return result

MACHO_SPECIAL = {'___dso_handle', '__mh_execute_header', '__mh_dylib_header', 'dyld_stub_binder'}

def _plan_macho(path: Path, exports: Sequence[str], *, abi_family: str = JNT_ABI2
                ) -> tuple[rust_archive.Archive, list[MachObject], bt.Policy]:
    public_prefix = _family_exports(exports, 'macos-arm64', abi_family)
    a = rust_archive.read_archive(path)
    b = MachBudget()
    objects: list[MachObject] = []
    defined: dict[str, list[tuple[str, bt.MachSymbol, bt.SectionKey]]] = {}
    undefined: set[str] = set()
    names = set()
    for member in a.members:
        obj = MachObject(a.payload(member), b)
        objects.append(obj)
        for sym in obj.symbols:
            (name, t, se, de, value) = sym
            names.add(name)
            if t & 224 or not t & 1:
                continue
            if t & 14 == 0 and value == 0:
                undefined.add(name)
                continue
            _require(t & 14 == 14 and se, 'Mach-O indirect/absolute/common definition')
            _require(name not in MACHO_SPECIAL and (not name.startswith(('section$', 'segment$', 'start$', 'end$'))), 'Mach-O defined linker sentinel')
            _require(name and name.isascii() and (not any((c.isspace() for c in name))) and ('=' not in name) and ('@' not in name), 'unrepresentable Mach-O mapping symbol')
            defined.setdefault(name, []).append((member.name.decode(), sym, obj.section(se)['key']))
    exports = tuple(sorted(exports))
    _require(len(set(exports)) == len(exports) and set(exports) <= defined.keys(), 'Mac declared C exports missing/duplicate')
    _require({n for n in defined if n.startswith(public_prefix)} == set(exports), 'Mac unexpected C export')
    for name in exports:
        rows = defined[name]
        _require(len(rows) == 1 and rows[0][1][1] == 15 and (not rows[0][1][3] & 128) and (rows[0][2] == ('__TEXT', '__text')), 'Mac C export not one strong text definition')
    prefix = '__' + _family(abi_family).removesuffix('_') + '_opaque_macho_' + _digest(path) + '_'
    mapping = {name: prefix + name for name in sorted(set(defined) - set(exports))}
    _require(not set(mapping.values()) & names, 'Mac opaque namespace collision')
    policy: bt.Policy = {'before_sha256': _digest(path), 'prefix': prefix, 'mapping': mapping, 'c_exports': list(exports), 'defined_names': len(defined), 'global_definitions': sum((len(x) for x in defined.values())), 'unresolved_imports': sorted(undefined - set(defined))}
    if abi_family != JNT_ABI2:
        policy['abi_family'] = abi_family
    return (a, objects, policy)

def _restore_macho_index(renamed: Path, output: Path, indexer: Path | None, *,
                         logs: Path, records: list[bt.CommandProof]) -> bt.IndexRestoration:
    """Restore a sorted BSD TOC without changing any object or its position."""
    if indexer is None:
        raise ValueError('sorted Mac archive needs an explicit Apple libtool indexer')
    indexer = Path(indexer).resolve(strict=True)
    _require(indexer.is_file(), 'explicit regular Apple libtool required')
    before = _digest(indexer)
    left = rust_archive.read_archive(renamed)
    renamed_before = hashlib.sha256(left.data).hexdigest()
    env = _tool_environment();env['ZERO_AR_DATE'] = '1'
    version = _command([indexer, '-V'], cwd=logs.parent, env=env, logs=logs, records=records).stdout.decode().strip()
    _require(version.startswith('Apple Inc. version cctools'), 'indexer is not an identified Apple cctools libtool')
    _command([indexer, '-static', '-s', '-D', '-o', output, renamed],
             cwd=logs.parent, env=env, logs=logs, records=records)
    right = rust_archive.read_archive(output)
    _require(renamed_before == _digest(renamed), 'Mac index restoration changed its input archive')
    _require([m.name for m in left.members] == [m.name for m in right.members],
             'Mac index restoration changed member order/names')
    _require(all(left.payload(a) == right.payload(b) for a, b in zip(left.members, right.members)),
             'Mac index restoration changed object payload')
    _require(before == _digest(indexer), 'Mac indexer changed during restoration')
    return {'path': str(indexer), 'sha256': before, 'version': version,
            'ZERO_AR_DATE': '1', 'intermediate_sha256': _digest(renamed),
            'exact_member_payloads': True}


def _transform_macho(original: Path, output: Path, logs: Path, exports: Sequence[str],
                     objcopy: Path, expected_plan: Mapping[str, object] | None = None, *,
                     abi_family: str = JNT_ABI2, indexer: Path | None = None) -> bt.Transform:
    _require(not output.exists(), 'Mac derivative exists')
    (source, objects, policy) = _plan_macho(original, exports, abi_family=abi_family)
    if expected_plan is not None:
        _require(policy['before_sha256'] == expected_plan['archive_sha256']
                 and policy['mapping'] == expected_plan['mapping']
                 and policy['c_exports'] == expected_plan['declared_exports']
                 and policy['unresolved_imports'] == expected_plan['unresolved_imports'],
                 'frozen Mac inventory/map mismatch')
    output.parent.mkdir(parents=True, exist_ok=True)
    logs.mkdir(parents=True, exist_ok=True)
    mapfile = logs.parent / 'mapping.txt'
    _require(not mapfile.exists(), 'Mac mapping exists')
    mapfile.write_text(''.join((a + ' ' + b + '\n' for (a, b) in policy['mapping'].items())))
    records: list[bt.CommandProof] = []
    env = _tool_environment()
    version = _command([str(objcopy), '--version'], cwd=logs.parent, env=env, logs=logs, records=records).stdout.decode()
    removed: list[bt.MachRemoval] = []
    for (member, obj) in zip(source.members, objects):
        for s in obj.sections:
            if s['segment'] == '__LLVM':
                _require(s['name'] in ('__bitcode', '__cmdline') and s['row'][8] == 0 and (not s['relocations']), 'unapproved Mach-O compiler metadata')
                removed.append({'member': member.name.decode(), 'section': s['key'], 'bytes': s['row'][3], 'payload_sha256': hashlib.sha256(s['payload']).hexdigest()})
    machine_path = original
    machine = source
    removed_members: list[bt.MachMemberProof] = []
    if removed:
        machine_path = output.with_suffix('.machine-code.a')
        _require(not machine_path.exists(), 'Mac intermediate exists')
        _command([str(objcopy), '--remove-section=__LLVM,__bitcode', '--remove-section=__LLVM,__cmdline', str(original), str(machine_path)], cwd=logs.parent, env=env, logs=logs, records=records)
        machine = rust_archive.read_archive(machine_path)
        _require([m.name for m in source.members] == [m.name for m in machine.members], 'Mac metadata member order changed')
        for (old, new) in zip(source.members, machine.members):
            proof = compare_macho(source.payload(old), machine.payload(new), {}, remove=True)
            _require(not any((s['segment'] == '__LLVM' for s in MachObject(machine.payload(new)).sections)), 'Mac metadata remains')
            removed_members.append({'member': old.name.decode(), 'before_sha256': hashlib.sha256(source.payload(old)).hexdigest(), 'after_sha256': hashlib.sha256(machine.payload(new)).hexdigest(), **proof})
    _command([str(objcopy), '--redefine-syms=' + str(mapfile), str(machine_path), str(output)], cwd=logs.parent, env=env, logs=logs, records=records)
    restored = None
    if macho_index(original)['sorted'] and not macho_index(output)['sorted']:
        renamed = output.with_suffix('.unsorted.a')
        _require(not renamed.exists(), 'Mac namespace intermediate exists')
        output.rename(renamed)
        restored = _restore_macho_index(renamed, output, indexer, logs=logs, records=records)
    after = rust_archive.read_archive(output)
    _require([m.name for m in source.members] == [m.name for m in after.members], 'Mac opaque member order changed')
    toc = compare_macho_index(original, output, policy['mapping'])
    proofs: list[bt.MachMemberProof] = []
    defined: set[str] = set()
    undefined: set[str] = set()
    names = set()
    for (old, new) in zip(machine.members, after.members):
        proof = compare_macho(machine.payload(old), after.payload(new), policy['mapping'])
        for (name, t, se, de, v) in MachObject(after.payload(new)).symbols:
            names.add(name)
            if not t & 224 and t & 1:
                (undefined if t & 14 == 0 else defined).add(name)
        proofs.append({'member': old.name.decode(), 'before_sha256': hashlib.sha256(machine.payload(old)).hexdigest(), 'after_sha256': hashlib.sha256(after.payload(new)).hexdigest(), **proof})
    _require(not set(policy['mapping']) & names, 'Mac old private symbol remains')
    _require(defined == set(exports) | set(policy['mapping'].values()), 'Mac global definition closure changed')
    _require(sorted(undefined - defined) == policy['unresolved_imports'], 'Mac unresolved system imports changed')
    _require(_digest(original) == policy['before_sha256'], 'Mac original archive changed')
    result: bt.Transform = {'schema': 1, 'kind': 'opaque-Mach-O-native-only-C-static-boundary', 'before_sha256': policy['before_sha256'], 'prefix': policy['prefix'], 'mapping': policy['mapping'], 'c_exports': policy['c_exports'], 'unresolved_imports': policy['unresolved_imports'], 'defined_names': policy['defined_names'], 'after_sha256': _digest(output), 'tool': {'path': str(objcopy), 'sha256': _digest(objcopy), 'version': version}, 'commands': records, 'removed_sections': removed, 'metadata_removal_members': removed_members, 'members': proofs, 'archive_index': toc, 'mapping_file_sha256': _digest(mapfile), 'machine_archive_sha256': _digest(machine_path), 'proof_sources': {'rust_static_boundary.py': _digest(Path(__file__))}}
    if abi_family != JNT_ABI2:
        result['abi_family'] = abi_family
    if 'global_weak_definitions' in policy:
        result['global_weak_definitions'] = policy['global_weak_definitions']
    if 'global_definitions' in policy:
        result['global_definitions'] = policy['global_definitions']
    if restored is not None:
        result['index_restoration'] = restored
    return result

def declared_exports(header: Path, target: str, *, abi_family: str = JNT_ABI2) -> tuple[str, ...]:
    """Derive a closed family roster from its packaged authoritative header."""
    stem = _family(abi_family)
    _require(header.stat().st_size <= 1 << 20, 'C header exceeds byte limit')
    text = header.read_text()
    text = re.sub(r'/\*.*?\*/|//[^\n]*', '', text, flags=re.S)
    names: list[str] = re.findall(r'\b(' + re.escape(stem) + r'[a-zA-Z0-9_]+)\s*\(', text)
    if abi_family == JNT_ABI2:
        _require(len(names) == len(set(names)) == 62, 'ABI2 C declaration roster differs')
    elif abi_family == IRGX_ABI2:
        _require(len(names) == len(set(names)) and tuple(sorted(names)) == _IRGX_EXPORTS,
                 'IRGX ABI2 105-function declaration roster differs')
    if abi_family == IRGX_MUNCH_IMAGE1:
        _require(len(names) == len(set(names)) and tuple(sorted(names)) == _IRGX_IMAGE1_EXPORTS,
                 'IRGX ABI2 Image1 108-function declaration roster differs')
    _require(target in ('linux-x86_64', 'macos-arm64'), 'unsupported static boundary target')
    prefix = '_' if target == 'macos-arm64' else ''
    return tuple(sorted(prefix + name for name in names))


def _facts(original: Path, derivative: Path, target: str, exports: Sequence[str],
           *, abi_family: str = JNT_ABI2) -> bt.Facts:
    """Recompute the proof from bytes, including references and archive lookup."""
    _require(target in ('linux-x86_64', 'macos-arm64'), 'unsupported static boundary target')
    is_elf = target == 'linux-x86_64'
    objects: Sequence[ElfObject | MachObject]
    if is_elf:
        source, elf_objects, policy = _plan_elf(original, exports, abi_family=abi_family)
        objects = elf_objects
    else:
        source, mach_objects, policy = _plan_macho(original, exports, abi_family=abi_family)
        objects = mach_objects
    after = rust_archive.read_archive(derivative)
    _require([m.name for m in source.members] == [m.name for m in after.members],
             'static boundary archive member order changed')
    mapping = policy['mapping']
    members: list[bt.MemberProof] = []
    removed: list[bt.RemovedSection] = []
    defined: set[str] = set()
    undefined: set[str] = set()
    names: set[str] = set()
    elf_budget = ElfBudget()
    mach_budget = MachBudget()
    for old, new, before in zip(source.members, after.members, objects):
        proof: bt.ElfProof | bt.MachProof
        if isinstance(before, ElfObject):
            for i, name in enumerate(before.names):
                _require(name not in ('.llvm.lto', '.llvm_bc', '__bitcode')
                         and not name.startswith('.gnu.lto_'), 'unapproved embedded LTO payload')
                if name in ('.llvmbc', '.llvmcmd'):
                    section = before.sections[i]
                    _require(section[1] == 1 and not section[2] & 2,
                             'allocated/nonmetadata LLVM removal refused')
                    removed.append({'member': old.name.decode(), 'section': name,
                                    'payload_sha256': hashlib.sha256(before.payload(i)).hexdigest()})
            proof = compare_elf(source.payload(old), after.payload(new), mapping,
                                removed=('.llvmbc', '.llvmcmd'))
            elf = ElfObject(after.payload(new), elf_budget)
            _require(not any(n in ('.llvmbc', '.llvmcmd', '.llvm.lto', '.llvm_bc', '__bitcode')
                             or n.startswith('.gnu.lto_') for n in elf.names), 'embedded LTO payload remains')
            for name, info, _, symbol_section, _, _ in elf.symbols:
                names.add(name)
                if info >> 4 in (1, 2):
                    (defined if symbol_section else undefined).add(name)
        else:
            assert isinstance(before, MachObject)
            for mach_section in before.sections:
                if mach_section['segment'] == '__LLVM':
                    _require(mach_section['name'] in ('__bitcode', '__cmdline'), 'unapproved Mach-O compiler metadata')
                    removed.append({'member': old.name.decode(), 'section': mach_section['key'],
                                    'payload_sha256': hashlib.sha256(mach_section['payload']).hexdigest()})
            proof = compare_macho(source.payload(old), after.payload(new), mapping, remove=True)
            obj = MachObject(after.payload(new), mach_budget)
            _require(not any(s['segment'] == '__LLVM' for s in obj.sections), 'Mach-O compiler metadata remains')
            for name, kind, symbol_section, _, value in obj.symbols:
                names.add(name)
                if not kind & 0xe0 and kind & 1:
                    (undefined if kind & 14 == 0 and value == 0 else defined).add(name)
        members.append({'member': old.name.decode(),
                        'before_sha256': hashlib.sha256(source.payload(old)).hexdigest(),
                        'after_sha256': hashlib.sha256(after.payload(new)).hexdigest(), 'proof': proof})
    _require(not set(mapping) & names, 'old private symbol definition/reference remains')
    _require(defined == set(exports) | set(mapping.values()), 'static defined-symbol closure changed')
    _require(sorted(undefined - defined) == policy['unresolved_imports'], 'unresolved system imports changed')
    index = (compare_elf_index if is_elf else compare_macho_index)(original, derivative, mapping)
    _require(_digest(original) == policy['before_sha256'], 'original archive changed during proof')
    result: bt.Facts = {'schema': SCHEMA, 'kind': 'opaque-native-only-C-static-boundary', 'target': target,
            'before_sha256': policy['before_sha256'], 'prefix': policy['prefix'], 'mapping': policy['mapping'], 'c_exports': policy['c_exports'], 'unresolved_imports': policy['unresolved_imports'], 'defined_names': policy['defined_names'], 'after_sha256': _digest(derivative), 'members': members,
            'removed_sections': removed, 'archive_index': index}
    if abi_family != JNT_ABI2:
        result['abi_family'] = abi_family
    if 'global_weak_definitions' in policy:
        result['global_weak_definitions'] = policy['global_weak_definitions']
    if 'global_definitions' in policy:
        result['global_definitions'] = policy['global_definitions']
    return result

@_checked_decode
def verify_archive(original: Path, derivative: Path, receipt: Mapping[str, object], *,
                   target: str, exports: Sequence[str], abi_family: str = JNT_ABI2) -> bt.Facts:
    """Verify an extracted derivative without executing an object tool or client."""
    _require(receipt.get('schema') == SCHEMA and receipt.get('target') == target
             and receipt.get('kind') == 'opaque-native-only-C-static-boundary'
             and receipt.get('machine_code_only') is True, 'unsupported static boundary receipt')
    _require(receipt.get('abi_family', JNT_ABI2) == abi_family, 'static boundary ABI family differs')
    facts = _facts(original, derivative, target, exports, abi_family=abi_family)
    _require(_encoded(facts) == _encoded(receipt.get('facts')), 'static boundary byte proof differs')
    _require(receipt.get('before_sha256') == facts['before_sha256']
             and receipt.get('after_sha256') == facts['after_sha256'], 'static boundary checksum differs')
    return facts


@_checked_decode
def transform_archive(original: Path, output: Path, *, target: str, exports: Sequence[str],
                      objcopy: Path, work: Path, abi_family: str = JNT_ABI2,
                      indexer: Path | None = None) -> bt.Receipt:
    """Create an atomic derivative and retain every tool command and proof input.

    The caller packages ``work`` beside the immutable input. The selected LLVM
    objcopy is explicit; unsupported tool behavior is rejected by the byte proof.
    The intermediate is retained for the two-stage metadata/namespace receipt.
    """
    original, output, objcopy = Path(original), Path(output), Path(objcopy).resolve(strict=True)
    _require(target in ('linux-x86_64', 'macos-arm64'), 'unsupported static boundary target')
    _family_exports(exports, target, abi_family)
    _require(not output.exists() and not work.exists(), 'static boundary output/work already exists')
    _require(objcopy.is_file() and not objcopy.is_symlink(), 'explicit regular LLVM objcopy required')
    work.mkdir(parents=True)
    staged = work / 'derivative.a'
    before, helper, tool = _digest(original), _digest(Path(__file__)), _digest(objcopy)
    parser = _digest(Path(rust_archive.__file__)) if abi_family in (IRGX_ABI2, IRGX_MUNCH_IMAGE1) else None
    if target == 'linux-x86_64':
        transform = _transform_elf(original, staged, work / 'commands', exports, objcopy,
                                   abi_family=abi_family)
    else:
        transform = _transform_macho(original, staged, work / 'commands', exports, objcopy,
                                     abi_family=abi_family, indexer=indexer)
    _require('LLVM' in transform['tool']['version'], 'LLVM objcopy required')
    _require(transform['tool']['sha256'] == tool == _digest(objcopy), 'static boundary tool changed')
    facts = _facts(original, staged, target, exports, abi_family=abi_family)
    receipt: bt.Receipt = {'schema': SCHEMA, 'kind': 'opaque-native-only-C-static-boundary', 'target': target,
               'machine_code_only': True, 'before_sha256': before, 'after_sha256': _digest(staged),
               'helper_sha256': helper, 'transform': transform, 'facts': facts}
    if abi_family != JNT_ABI2:
        receipt['abi_family'] = abi_family
    if parser is not None:
        receipt['parser_sha256'] = parser
        _require(parser == _digest(Path(rust_archive.__file__)), 'static boundary parser source drift')
    _require(before == _digest(original) and helper == _digest(Path(__file__)), 'static boundary source drift')
    output.parent.mkdir(parents=True, exist_ok=True)
    os.link(staged, output)  # Refuses a destination that appeared during proof.
    return receipt

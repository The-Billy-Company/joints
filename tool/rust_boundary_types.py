"""Record and binary-layout types for the native Rust archive boundary proof.

The records preserve the receipt's existing JSON representation. Binary tuples
describe the exact struct layouts decoded by rust_static_boundary.py.
"""
from __future__ import annotations

from typing import NotRequired, TypeAlias, TypedDict

Buffer: TypeAlias = bytes | memoryview
ElfHeader: TypeAlias = tuple[bytes, int, int, int, int, int, int, int, int, int, int, int, int, int]
ElfSection: TypeAlias = tuple[int, int, int, int, int, int, int, int, int, int]
ElfSymbol: TypeAlias = tuple[str, int, int, int, int, int]
MachHeader: TypeAlias = tuple[int, int, int, int, int, int, int, int]
MachSegment: TypeAlias = tuple[int, int, bytes, int, int, int, int, int, int, int, int]
MachSectionRow: TypeAlias = tuple[bytes, bytes, int, int, int, int, int, int, int, int, int, int]
MachSymbol: TypeAlias = tuple[str, int, int, int, int]
SectionKey: TypeAlias = tuple[str, str]
Relocation: TypeAlias = tuple[int, int, int]


class MachSection(TypedDict):
    row: MachSectionRow
    name: str
    segment: str
    key: SectionKey
    ordinal: int
    payload: bytes
    relocations: list[Relocation]


class MachCommand(TypedDict):
    tag: int
    size: int
    raw: bytes
    segment: NotRequired[MachSegment]
    sections: NotRequired[list[MachSection]]
    payload: NotRequired[bytes]


class FileProof(TypedDict):
    path: str
    sha256: str


class ToolProof(FileProof):
    version: str


class CommandProof(TypedDict):
    argv: list[str]
    cwd: str
    exit: int
    stdout: FileProof
    stderr: FileProof


class FamilyFields(TypedDict):
    abi_family: NotRequired[str]


class Policy(FamilyFields):
    before_sha256: str
    prefix: str
    mapping: dict[str, str]
    c_exports: list[str]
    unresolved_imports: list[str]
    defined_names: int
    global_weak_definitions: NotRequired[int]
    global_definitions: NotRequired[int]


class AddressSignificance(TypedDict):
    section: str
    active: bool
    payload_sha256: str


class ElfProof(TypedDict):
    symbols: int
    sections: int
    relocations: int
    groups: int
    string_table_split: bool
    group_headers_moved: bool
    address_significance_targets: int
    address_significance_tables: list[AddressSignificance]
    unchanged_nonlinkage_sections_sha256: str
    other_globals_sha256: str


class RuntimeSection(TypedDict):
    section: SectionKey
    address: int
    bytes: int
    payload_sha256: str
    relocations: int


class MachProof(TypedDict):
    sections: int
    surviving_sections: int
    symbols: int
    surviving_symbols: int
    removed_local_metadata_symbols: int
    runtime: list[RuntimeSection]
    relocations: int


class Index(TypedDict):
    entries: list[tuple[str, int]]
    member_selection: dict[str, list[int]]
    archive_sha256: str
    member_selection_sha256: str


class MachIndex(Index):
    kind: str
    sorted: bool


class IndexProof(TypedDict):
    before: Index
    after: Index


class MachIndexProof(TypedDict):
    before: MachIndex
    after: MachIndex
    sorted_reorder: bool


class MemberIdentity(TypedDict):
    member: str
    before_sha256: str
    after_sha256: str


class ElfMemberProof(MemberIdentity, ElfProof):
    pass


class MachMemberProof(MemberIdentity, MachProof):
    pass


class MemberProof(MemberIdentity):
    proof: ElfProof | MachProof


class RemovedSection(TypedDict):
    member: str
    section: str | SectionKey
    payload_sha256: str


class ElfRemoval(TypedDict):
    member: str
    section: str
    index: int
    bytes: int
    flags: int
    sha256: str


class MachRemoval(RemovedSection):
    bytes: int


class IndexRestoration(ToolProof):
    ZERO_AR_DATE: str
    intermediate_sha256: str
    exact_member_payloads: bool


class Transform(Policy):
    schema: int
    kind: str
    machine_code_only: NotRequired[bool]
    after_sha256: str
    unresolved_imports_sha256: NotRequired[str]
    mapping_file_sha256: str
    tool: ToolProof
    archive_index: IndexProof | MachIndexProof
    commands: list[CommandProof]
    removed_sections: list[ElfRemoval] | list[MachRemoval]
    metadata_removal_members: list[ElfMemberProof] | list[MachMemberProof]
    members: list[ElfMemberProof] | list[MachMemberProof]
    machine_archive_sha256: str
    proof_sources: dict[str, str]
    index_restoration: NotRequired[IndexRestoration]


class Facts(Policy):
    schema: int
    kind: str
    target: str
    after_sha256: str
    members: list[MemberProof]
    removed_sections: list[RemovedSection]
    archive_index: IndexProof | MachIndexProof


class Receipt(FamilyFields):
    schema: int
    kind: str
    target: str
    machine_code_only: bool
    before_sha256: str
    after_sha256: str
    helper_sha256: str
    transform: Transform
    facts: Facts
    parser_sha256: NotRequired[str]

"""Owned parser handles and borrowed nodes over the native C ABI."""

from __future__ import annotations

from bisect import bisect_right
import ctypes as c
from dataclasses import dataclass
from functools import cached_property
import os
import threading
from weakref import WeakSet

from ._native import NativeScar, native

NONE = 0xFFFFFFFF


class JointsError(RuntimeError):
    """A native operation could not run."""


class ParseError(JointsError):
    """A strict parse produced a partial, repaired, or unsound tree."""


@dataclass(frozen=True)
class Repair:
    """A deletion over [at, over), or a zero-width supplied token."""

    at: int
    over: int
    supplied: bool
    word: str | None
    stop: str
    heads: int
    shifted: int
    felled: int


def _z(value: str | os.PathLike[str]) -> bytes:
    result = os.fsencode(value)
    if b"\0" in result:
        raise ValueError("paths and language names cannot contain NUL")
    return result


def _bytes(value: str | bytes) -> bytes:
    if isinstance(value, str):
        return value.encode("utf-8")
    if not isinstance(value, bytes):
        raise TypeError("source must be str or bytes")
    return value


def _check(lib, status: int) -> None:
    if status < 0:
        message = lib.jnt_last_error().decode("utf-8", errors="replace")
        raise JointsError(message or f"libjnt failed with status {status}")


def _string(fn, *args) -> str | None:
    length = c.c_size_t()
    address = fn(*args, c.byref(length))
    return c.string_at(address, length.value).decode("utf-8") if address else None


class _Handle:
    def _init(self, lib, pointer, owner=None) -> None:
        self._lib, self._handle, self._owner = lib, pointer, owner
        self._thread = threading.get_ident()
        self._children: WeakSet = WeakSet()
        if owner is not None:
            owner._children.add(self)

    @property
    def _ptr(self):
        if not self._handle:
            raise JointsError(f"{type(self).__name__} is closed")
        if self._thread != threading.get_ident():
            raise JointsError("use one bank and parser per thread")
        if self._owner is not None:
            self._owner._ptr
        return self._handle

    def close(self) -> None:
        """Release this handle after its dependent handles have closed."""
        if not getattr(self, "_handle", None):
            return
        if any(child._handle for child in self._children):
            raise JointsError(f"close dependent handles before {type(self).__name__}")
        self._ptr
        getattr(self._lib, self._free)(self._handle)
        self._handle = None
        if self._owner is not None:
            self._owner._children.discard(self)
            self._owner = None

    def __enter__(self):
        self._ptr
        return self

    def __exit__(self, *exc) -> None:
        self.close()

    def __del__(self) -> None:
        try:
            self.close()
        except Exception:
            # Explicit close reports misuse; finalization must not raise.
            pass


class Bank(_Handle):
    """An opened folio, multi-language codex, or grammar.json."""

    _free = "jnt_close"

    def __init__(self, path: str | os.PathLike[str], *, library=None):
        lib = native(library)
        pointer = c.c_void_p()
        _check(lib, lib.jnt_open(_z(path), c.byref(pointer)))
        self._init(lib, pointer)

    @property
    def languages(self) -> tuple[str, ...]:
        pointer = self._ptr
        return tuple(
            _string(self._lib.jnt_bank_title, pointer, i)
            for i in range(self._lib.jnt_bank_count(pointer))
        )

    def parser(self, language: str | None = None) -> Parser:
        """Bind one language; unnamed selection requires a single-language bank."""
        return Parser(self, language)


class Parser(_Handle):
    """One language with reusable scratch, used from its creating thread."""

    _free = "jnt_parser_free"

    def __init__(self, bank: Bank, language: str | None = None):
        pointer = c.c_void_p()
        _check(
            bank._lib,
            bank._lib.jnt_parser_new(
                bank._ptr,
                _z(language) if language is not None else None,
                c.byref(pointer),
            ),
        )
        self._init(bank._lib, pointer, bank)

    @property
    def language(self) -> str:
        return _string(self._lib.jnt_parser_language, self._ptr)

    @property
    def blind(self) -> int:
        """External terminals without a scanner rule in this grammar."""
        return self._lib.jnt_parser_blind(self._ptr)

    def parse(self, source: str | bytes, *, strict: bool = True) -> Tree:
        """Parse bytes, rejecting partial or repaired trees unless explicitly allowed."""
        data = _bytes(source)
        pointer = c.c_void_p()
        _check(
            self._lib, self._lib.jnt_parse(self._ptr, data, len(data), c.byref(pointer))
        )
        tree = Tree(self, pointer, data)
        try:
            if strict:
                tree.require_complete()
            return tree
        except Exception:
            tree.close()
            raise

    def query(self, source: str | bytes) -> Query:
        """Compile a tree-sitter structural query for this parser's grammar."""
        return Query(self, source)


class Tree(_Handle):
    """A forest plus its parse verdict and original source bytes."""

    _free = "jnt_tree_free"

    def __init__(self, parser: Parser, pointer, source: bytes):
        self._init(parser._lib, pointer, parser)
        self._source = source

    @property
    def source(self) -> bytes:
        return self._source

    @property
    def stop(self) -> str:
        return ("accepted", "stray", "unexpected", "truncated")[
            self._lib.jnt_tree_stop(self._ptr)
        ]

    @property
    def stop_at(self) -> int:
        return self._lib.jnt_tree_stop_at(self._ptr)

    @property
    def mends(self) -> int:
        return self._lib.jnt_tree_mends(self._ptr)

    @property
    def skipped(self) -> int:
        return self._lib.jnt_tree_skipped(self._ptr)

    @property
    def supplied(self) -> int:
        return self._lib.jnt_tree_supplied(self._ptr)

    @property
    def repairs(self) -> tuple[Repair, ...]:
        pointer = self._ptr
        repairs = []
        for i in range(self._lib.jnt_tree_scars(pointer)):
            scar = NativeScar()
            _check(self._lib, self._lib.jnt_tree_scar(pointer, i, c.byref(scar)))
            repairs.append(
                Repair(
                    scar.at,
                    scar.over,
                    bool(scar.supplied),
                    _string(self._lib.jnt_tree_scar_word, pointer, i),
                    ("accepted", "stray", "unexpected", "truncated")[scar.stop],
                    scar.heads,
                    scar.shifted,
                    scar.felled,
                )
            )
        return tuple(repairs)

    @property
    def sound(self) -> bool:
        status = self._lib.jnt_tree_sound(self._ptr)
        _check(self._lib, status)
        return bool(status)

    @property
    def roots(self) -> tuple[Node, ...]:
        pointer = self._ptr
        return tuple(
            Node(self, self._lib.jnt_tree_root(pointer, i))
            for i in range(self._lib.jnt_tree_roots(pointer))
        )

    @property
    def root_node(self) -> Node:
        roots = self.roots
        if len(roots) != 1:
            raise ParseError(f"expected one root, found {len(roots)}")
        return roots[0]

    def require_complete(self) -> None:
        """Require a whole, unrepaired, structurally sound tree for CI use."""
        roots = self._lib.jnt_tree_roots(self._ptr)
        if (
            self.stop != "accepted"
            or self.mends
            or self.skipped
            or self.supplied
            or roots != 1
        ):
            raise ParseError(
                f"{self._owner.language}: {self.stop} at byte {self.stop_at}; "
                f"{roots} roots, {self.mends} repairs, "
                f"{self.skipped} skipped bytes, {self.supplied} supplied tokens"
            )
        if not self.sound:
            raise ParseError("the parsed forest is structurally unsound")

    def sexp(self, *, all: bool = False) -> str:
        result = _string(self._lib.jnt_tree_sexp, self._ptr, int(all))
        if result is None:
            raise JointsError("could not render tree")
        return result

    @cached_property
    def _lines(self) -> tuple[int, ...]:
        return (0, *(i + 1 for i, byte in enumerate(self.source) if byte == 10))

    def _point(self, offset: int) -> tuple[int, int]:
        row = bisect_right(self._lines, offset) - 1
        return row, offset - self._lines[row]


class Node:
    """A node reference borrowed from a tree."""

    def __init__(self, tree: Tree, ref: int):
        self._tree, self.id = tree, ref

    def __eq__(self, other) -> bool:
        return (
            isinstance(other, Node)
            and self._tree is other._tree
            and self.id == other.id
        )

    def __hash__(self) -> int:
        return hash((id(self._tree), self.id))

    def _get(self, name, *args):
        return getattr(self._tree._lib, name)(self._tree._ptr, self.id, *args)

    def _node(self, ref: int) -> Node | None:
        return None if ref == NONE else Node(self._tree, ref)

    @property
    def type(self) -> str:
        return _string(self._tree._lib.jnt_node_name, self._tree._ptr, self.id)

    @property
    def is_named(self) -> bool:
        return bool(self._get("jnt_node_named"))

    @property
    def start_byte(self) -> int:
        return self._get("jnt_node_start")

    @property
    def end_byte(self) -> int:
        return self._get("jnt_node_end")

    @property
    def text(self) -> bytes:
        return self._tree.source[self.start_byte : self.end_byte]

    @property
    def start_point(self) -> tuple[int, int]:
        return self._tree._point(self.start_byte)

    @property
    def end_point(self) -> tuple[int, int]:
        return self._tree._point(self.end_byte)

    @property
    def child_count(self) -> int:
        return self._get("jnt_node_kids")

    @property
    def children(self) -> list[Node]:
        return [self.child(i) for i in range(self.child_count)]

    @property
    def named_children(self) -> list[Node]:
        return [node for node in self.children if node.is_named]

    @property
    def parent(self) -> Node | None:
        return self._node(self._get("jnt_node_parent"))

    @property
    def next_sibling(self) -> Node | None:
        return self._node(self._get("jnt_node_next"))

    @property
    def prev_sibling(self) -> Node | None:
        return self._node(self._get("jnt_node_prev"))

    @property
    def next_named_sibling(self) -> Node | None:
        return self._node(self._get("jnt_node_next_named"))

    @property
    def prev_named_sibling(self) -> Node | None:
        return self._node(self._get("jnt_node_prev_named"))

    def child(self, index: int) -> Node | None:
        if index < 0:
            return None
        return self._node(self._get("jnt_node_kid", index))

    def child_by_field_name(self, name: str) -> Node | None:
        field = name.encode("utf-8")
        return self._node(self._get("jnt_node_by_field", field, len(field)))

    def field_name_for_child(self, index: int) -> str | None:
        child = self.child(index)
        return (
            _string(self._tree._lib.jnt_node_field, self._tree._ptr, child.id)
            if child is not None
            else None
        )


@dataclass(frozen=True)
class Capture:
    """A query capture and the node it names."""

    name: str
    node: Node


@dataclass(frozen=True)
class Match:
    """One matched pattern, retaining capture order and multiplicity."""

    pattern_index: int
    captures: tuple[Capture, ...]


class Query(_Handle):
    """A compiled query bound to one parser's grammar."""

    _free = "jnt_query_free"

    def __init__(self, parser: Parser, source: str | bytes):
        data = _bytes(source)
        pointer = c.c_void_p()
        _check(
            parser._lib,
            parser._lib.jnt_query_compile(
                parser._ptr, data, len(data), c.byref(pointer)
            ),
        )
        self._init(parser._lib, pointer, parser)

    @property
    def capture_names(self) -> tuple[str, ...]:
        pointer = self._ptr
        return tuple(
            _string(self._lib.jnt_query_capture_name, pointer, i)
            for i in range(self._lib.jnt_query_capture_count(pointer))
        )

    def matches(self, tree: Tree, *, foreign: str = "refuse") -> list[Match]:
        """Match a tree; unknown predicates are refused unless explicitly configured."""
        policies = {"refuse": 0, "admit": 1, "deny": 2}
        if foreign not in policies:
            raise ValueError("foreign must be refuse, admit, or deny")
        if tree._owner is not self._owner:
            raise JointsError("query and tree must belong to the same parser")
        result = c.c_void_p()
        _check(
            self._lib,
            self._lib.jnt_query_exec(
                self._ptr,
                tree._ptr,
                tree.source,
                len(tree.source),
                policies[foreign],
                c.byref(result),
            ),
        )
        try:
            names = self.capture_names
            return [
                Match(
                    self._lib.jnt_query_result_pattern(result, i),
                    tuple(
                        Capture(
                            names[self._lib.jnt_query_result_capture_id(result, i, j)],
                            Node(
                                tree,
                                self._lib.jnt_query_result_capture_node(result, i, j),
                            ),
                        )
                        for j in range(
                            self._lib.jnt_query_result_capture_count(result, i)
                        )
                    ),
                )
                for i in range(self._lib.jnt_query_result_count(result))
            ]
        finally:
            self._lib.jnt_query_result_free(result)

    def captures(self, tree: Tree, *, foreign: str = "refuse") -> dict[str, list[Node]]:
        """Group distinct captured nodes by name in source order."""
        captured: dict[str, list[Node]] = {}
        seen: dict[str, set[int]] = {}
        for match in self.matches(tree, foreign=foreign):
            for capture in match.captures:
                ids = seen.setdefault(capture.name, set())
                if capture.node.id not in ids:
                    ids.add(capture.node.id)
                    captured.setdefault(capture.name, []).append(capture.node)
        for nodes in captured.values():
            nodes.sort(key=lambda node: (node.start_byte, node.end_byte, node.id))
        return captured

"""Load and type libjnt lazily; importing joints needs no native library."""

from __future__ import annotations

from collections.abc import Callable, Sequence
import ctypes as c
from ctypes.util import find_library
from functools import lru_cache
import os
from pathlib import Path
import sys
from typing import Protocol, cast

P, U, INT, Z, S = c.c_void_p, c.c_uint32, c.c_int32, c.c_size_t, c.c_char_p
OUT, LEN = c.POINTER(P), c.POINTER(Z)


class NativeScar(c.Structure):
    # ctypes creates descriptors from _fields_; annotations describe the Python
    # values read through those descriptors, not the storage wrapper classes.
    at: int
    over: int
    supplied: int
    heads: int
    shifted: int
    felled: int
    stop: int

    _fields_ = [
        (name, U) for name in ("at", "over", "supplied", "heads", "shifted", "felled")
    ] + [("stop", INT)]


class NativeLibrary(Protocol):
    """The Python values accepted and returned by the configured ABI 2 symbols.

    ctypes converts scalar results to Python values; output pointers retain
    their pointed-to type so a tree handle cannot be used as a length buffer.
    """

    jnt_abi_version: Callable[[], int]
    jnt_last_error: Callable[[], bytes | None]
    jnt_open: Callable[[bytes, c._Pointer[c.c_void_p]], int]
    jnt_close: Callable[[c.c_void_p], None]
    jnt_bank_count: Callable[[c.c_void_p], int]
    jnt_bank_title: Callable[[c.c_void_p, int, c._Pointer[c.c_size_t]], int | None]
    jnt_parser_new: Callable[[c.c_void_p, bytes | None, c._Pointer[c.c_void_p]], int]
    jnt_parser_free: Callable[[c.c_void_p], None]
    jnt_parser_language: Callable[[c.c_void_p, c._Pointer[c.c_size_t]], int | None]
    jnt_parser_blind: Callable[[c.c_void_p], int]
    jnt_parse: Callable[[c.c_void_p, bytes, int, c._Pointer[c.c_void_p]], int]
    jnt_tree_free: Callable[[c.c_void_p], None]
    jnt_tree_stop: Callable[[c.c_void_p], int]
    jnt_tree_stop_at: Callable[[c.c_void_p], int]
    jnt_tree_mends: Callable[[c.c_void_p], int]
    jnt_tree_skipped: Callable[[c.c_void_p], int]
    jnt_tree_supplied: Callable[[c.c_void_p], int]
    jnt_tree_scars: Callable[[c.c_void_p], int]
    jnt_tree_scar: Callable[[c.c_void_p, int, c._Pointer[NativeScar]], int]
    jnt_tree_scar_word: Callable[[c.c_void_p, int, c._Pointer[c.c_size_t]], int | None]
    jnt_tree_sound: Callable[[c.c_void_p], int]
    jnt_tree_roots: Callable[[c.c_void_p], int]
    jnt_tree_root: Callable[[c.c_void_p, int], int]
    jnt_tree_sexp: Callable[[c.c_void_p, int, c._Pointer[c.c_size_t]], int | None]
    jnt_node_name: Callable[[c.c_void_p, int, c._Pointer[c.c_size_t]], int | None]
    jnt_node_field: Callable[[c.c_void_p, int, c._Pointer[c.c_size_t]], int | None]
    jnt_node_named: Callable[[c.c_void_p, int], int]
    jnt_node_kid: Callable[[c.c_void_p, int, int], int]
    jnt_node_by_field: Callable[[c.c_void_p, int, bytes, int], int]
    jnt_query_compile: Callable[[c.c_void_p, bytes, int, c._Pointer[c.c_void_p]], int]
    jnt_query_free: Callable[[c.c_void_p], None]
    jnt_query_pattern_count: Callable[[c.c_void_p], int]
    jnt_query_capture_count: Callable[[c.c_void_p], int]
    jnt_query_capture_name: Callable[[c.c_void_p, int, c._Pointer[c.c_size_t]], int | None]
    jnt_query_exec: Callable[
        [c.c_void_p, c.c_void_p, bytes, int, int, c._Pointer[c.c_void_p]], int
    ]
    jnt_query_result_free: Callable[[c.c_void_p], None]
    jnt_query_result_count: Callable[[c.c_void_p], int]
    jnt_query_result_pattern: Callable[[c.c_void_p, int], int]
    jnt_query_result_capture_count: Callable[[c.c_void_p, int], int]
    jnt_query_result_capture_id: Callable[[c.c_void_p, int, int], int]
    jnt_query_result_capture_node: Callable[[c.c_void_p, int, int], int]
    jnt_node_start: Callable[[c.c_void_p, int], int]
    jnt_node_end: Callable[[c.c_void_p, int], int]
    jnt_node_kids: Callable[[c.c_void_p, int], int]
    jnt_node_parent: Callable[[c.c_void_p, int], int]
    jnt_node_next: Callable[[c.c_void_p, int], int]
    jnt_node_prev: Callable[[c.c_void_p, int], int]
    jnt_node_next_named: Callable[[c.c_void_p, int], int]
    jnt_node_prev_named: Callable[[c.c_void_p, int], int]


class _NativeFunction(Protocol):
    """Only the configurable metadata of a dynamically loaded C function."""

    restype: object
    argtypes: Sequence[object]


type _NativeLoader = Callable[[str | None], NativeLibrary]


def native(path: str | os.PathLike[str] | None = None) -> NativeLibrary:
    # Normalize PathLike before caching: the filesystem protocol does not
    # promise hashability, whereas the cache's string keys do.
    return _cached_native(os.fspath(path) if path is not None else None)


# functools' stub erases parameter types. Preserve this specific loader's
# signature at the decorator boundary instead of exposing Callable[..., ...].
@cast(Callable[[_NativeLoader], _NativeLoader], lru_cache(maxsize=None))
def _cached_native(path: str | None) -> NativeLibrary:
    name = (
        "jnt.dll"
        if sys.platform == "win32"
        else ("libjnt.dylib" if sys.platform == "darwin" else "libjnt.so")
    )
    explicit = path or os.environ.get("JOINTS_LIB")
    if explicit:
        candidates = [os.fspath(explicit)]
    else:
        package = Path(__file__).resolve().parent
        candidates = [
            str(package / "_native" / name),
            str(package.parents[2] / "zig-out" / "lib" / name),
        ]
        if found := find_library("jnt"):
            candidates.append(found)
    failures = []
    for candidate in candidates:
        try:
            lib = c.CDLL(candidate)
            break
        except OSError as error:
            failures.append(str(error))
    else:
        raise OSError(
            "libjnt is unavailable; build joints and set JOINTS_LIB. "
            + "; ".join(failures)
        )
    signatures: dict[str, tuple[object, list[object]]] = {
        "jnt_abi_version": (U, []),
        "jnt_last_error": (S, []),
        "jnt_open": (INT, [S, OUT]),
        "jnt_close": (None, [P]),
        "jnt_bank_count": (U, [P]),
        "jnt_bank_title": (P, [P, U, LEN]),
        "jnt_parser_new": (INT, [P, S, OUT]),
        "jnt_parser_free": (None, [P]),
        "jnt_parser_language": (P, [P, LEN]),
        "jnt_parser_blind": (U, [P]),
        "jnt_parse": (INT, [P, S, Z, OUT]),
        "jnt_tree_free": (None, [P]),
        "jnt_tree_stop": (INT, [P]),
        "jnt_tree_stop_at": (U, [P]),
        "jnt_tree_mends": (U, [P]),
        "jnt_tree_skipped": (U, [P]),
        "jnt_tree_supplied": (U, [P]),
        "jnt_tree_scars": (U, [P]),
        # Only the ctypes metaclass consumes this class object; its dynamic
        # descriptor annotations do not describe callable Python arguments.
        "jnt_tree_scar": (INT, [P, U, c.POINTER(cast(type[c.Structure], NativeScar))]),
        "jnt_tree_scar_word": (P, [P, U, LEN]),
        "jnt_tree_sound": (INT, [P]),
        "jnt_tree_roots": (U, [P]),
        "jnt_tree_root": (U, [P, U]),
        "jnt_tree_sexp": (P, [P, INT, LEN]),
        "jnt_node_name": (P, [P, U, LEN]),
        "jnt_node_field": (P, [P, U, LEN]),
        "jnt_node_named": (INT, [P, U]),
        "jnt_node_kid": (U, [P, U, U]),
        "jnt_node_by_field": (U, [P, U, S, Z]),
        "jnt_query_compile": (INT, [P, S, Z, OUT]),
        "jnt_query_free": (None, [P]),
        "jnt_query_pattern_count": (U, [P]),
        "jnt_query_capture_count": (U, [P]),
        "jnt_query_capture_name": (P, [P, U, LEN]),
        "jnt_query_exec": (INT, [P, P, S, Z, INT, OUT]),
        "jnt_query_result_free": (None, [P]),
        "jnt_query_result_count": (U, [P]),
        "jnt_query_result_pattern": (U, [P, U]),
        "jnt_query_result_capture_count": (U, [P, U]),
        "jnt_query_result_capture_id": (U, [P, U, U]),
        "jnt_query_result_capture_node": (U, [P, U, U]),
    }
    for suffix in (
        "start",
        "end",
        "kids",
        "parent",
        "next",
        "prev",
        "next_named",
        "prev_named",
    ):
        signatures[f"jnt_node_{suffix}"] = (U, [P, U])
    for symbol, (result, args) in signatures.items():
        try:
            fn = cast(_NativeFunction, getattr(lib, symbol))
        except AttributeError as error:
            raise OSError(
                f"libjnt lacks {symbol}; rebuild it with query support"
            ) from error
        fn.restype, fn.argtypes = result, args
    # ctypes exposes symbols dynamically. All symbols above have been resolved
    # and configured before this single cast establishes the typed ABI surface.
    typed_lib = cast(NativeLibrary, lib)
    if typed_lib.jnt_abi_version() != 2:
        raise OSError("this binding requires libjnt ABI version 2")
    return typed_lib

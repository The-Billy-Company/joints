"""Load and type libjnt lazily; importing joints needs no native library."""

import ctypes as c
from ctypes.util import find_library
from functools import lru_cache
import os
from pathlib import Path
import sys

P, U, INT, Z, S = c.c_void_p, c.c_uint32, c.c_int32, c.c_size_t, c.c_char_p
OUT, LEN = c.POINTER(P), c.POINTER(Z)


class NativeScar(c.Structure):
    _fields_ = [
        (name, U) for name in ("at", "over", "supplied", "heads", "shifted", "felled")
    ] + [("stop", INT)]


@lru_cache(maxsize=None)
def native(path=None):
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
    signatures = {
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
        "jnt_tree_scar": (INT, [P, U, c.POINTER(NativeScar)]),
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
            fn = getattr(lib, symbol)
        except AttributeError as error:
            raise OSError(
                f"libjnt lacks {symbol}; rebuild it with query support"
            ) from error
        fn.restype, fn.argtypes = result, args
    if lib.jnt_abi_version() != 2:
        raise OSError("this binding requires libjnt ABI version 2")
    return lib

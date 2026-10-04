#!/usr/bin/env python3
"""Exercise an installed binding with the exact release native library."""

import ctypes
import importlib.metadata
import json
import sys
from pathlib import Path


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def main():
    version, library, grammar = sys.argv[1:]
    import joints

    installed = Path(joints.__file__).resolve()
    require(installed.is_relative_to(Path(sys.prefix).resolve()), "source import")
    require(importlib.metadata.version("joints") == version, "package version")
    require(joints.__version__ == version, "binding version")
    require(sys.version_info[:2] == (3, 12), "release Python floor is 3.12")
    native = ctypes.CDLL(library)
    native.jnt_version.restype = ctypes.c_char_p
    native.jnt_abi_version.restype = ctypes.c_uint32
    require(native.jnt_version().decode() == version, "native version")
    require(native.jnt_abi_version() == 2, "native ABI")
    source = '{"café": [1, 2, 3]}'.encode()
    with joints.Bank(grammar, library=library) as bank, bank.parser() as parser:
        require(bank.languages == ("json",), "grammar language")
        with parser.parse(source) as tree:
            require(tree.sound and tree.stop == "accepted", "strict tree")
            require(tree.root_node.text == source, "original source bytes")
            with parser.query("(number) @n") as query:
                require(
                    [node.text for node in query.captures(tree)["n"]]
                    == [b"1", b"2", b"3"],
                    "ordered numeric captures",
                )
            with parser.query("(pair key: (string) @key)") as query:
                key = query.captures(tree)["key"][0]
                require(key.text == '"café"'.encode(), "Unicode capture bytes")
                require(source[key.start_byte : key.end_byte] == key.text, "byte span")
        for malformed in (b"[1,", b'{"a": @ 2}', b'{"a" 2}'):
            try:
                parser.parse(malformed)
            except joints.ParseError:
                pass
            else:
                raise RuntimeError("strict parser accepted malformed input")
        with parser.parse(b"[4]") as tree, parser.query("(number) @n") as query:
            require(tree.sound, "parser reuse after refusal")
            require(query.captures(tree)["n"][0].text == b"4", "reused query")
    print(
        json.dumps(
            {
                "version": version,
                "python": sys.version.split()[0],
                "installed": str(installed),
                "strict_parse_query_refusal": "passed",
            }
        )
    )


if __name__ == "__main__":
    main()

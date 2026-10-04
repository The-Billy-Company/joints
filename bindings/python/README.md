# joints for Python

Open a grammar folio, parse source, and run structural queries through `libjnt`.
The 0.1.0 binding is experimental and requires a separately supplied native
library with ABI 2.

```sh
zig build
export PYTHONPATH="$PWD/bindings/python"
export JOINTS_LIB="$PWD/zig-out/lib/libjnt.so"  # libjnt.dylib on macOS
```

```python
from joints import Bank

with Bank("python.folio") as bank, bank.parser() as parser:
    with parser.parse(source_bytes) as tree:
        with parser.query("(function_definition name: (identifier) @name)") as query:
            for node in query.captures(tree).get("name", []):
                print(node.text, node.start_point)
```

`Bank` accepts a single folio, a multi-language codex, or a tree-sitter
`grammar.json`. Select a codex language with `bank.parser("python")`.
Minting once avoids rebuilding grammar tables when a process opens the bank.

A strict parse requires one root, acceptance, no deleted or supplied tokens,
and a structurally sound tree. It raises `ParseError` when that evidence is
missing. `parser.parse(source, strict=False)` exposes a partial forest together
with `stop`, `mends`, `skipped`, `supplied`, `repairs`, and `roots`
for callers that can use recovery. A sound forest alone does not establish that
source was understood.

Nodes expose byte spans, source text, byte-based row/column positions, children,
fields, parents, and siblings. Queries return ordered matches or captures grouped
by name. Unknown predicates are refused unless the caller explicitly passes
`foreign="admit"` or `foreign="deny"`.

Use one bank and parser per thread. Close trees and queries before their parser,
then close the bank; context managers enforce that order. Accessing nodes after
their tree closes raises an error. Importing the package does not load native code.
`JOINTS_LIB` selects a library explicitly; otherwise a bundled library, the local
checkout's build, or the system library is tried.

Run the native integration checks after building:

```sh
PYTHONPATH=bindings/python python3 -m unittest discover -s bindings/python/tests
```

The Python wheel and sdist contain the interface; no native library or grammar
bank is bundled. Install the package and download the matching native archive
from [Joints releases](https://github.com/The-Billy-Company/joints/releases):
`joints-0.1.0-linux-x86_64.tar.gz` or `joints-0.1.0-macos-arm64.tar.gz`.
Set `JOINTS_LIB` to the extracted archive's `lib/libjnt.so` or
`lib/libjnt.dylib`. Its `grammar/json.json` is a reproducible starting bank;
compile other grammars with the included CLI. The native archives are tested
on Ubuntu 24.04 (glibc 2.39) and macOS 14. Other targets require a source build.
The [Rust binding](../rust/README.md) uses the same native archives.

Apache-2.0; see `LICENSE` and `NOTICE`.

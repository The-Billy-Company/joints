`attest.survey` seated the Tree-sitter oracle by digesting everything under a
grammar's `src/`, generated files included. `parser.c`, `node-types.json` and
`src/tree_sitter/*.h` are what `tree-sitter generate` lowers *from* the
`grammar.json` sitting beside them, so their presence is a fact about **when**
this tree was last built, and the digest was reading it as a fact about **what
language this is**. Building a parser therefore renamed it. That reported 28 of
29 grammars as several different parsers at once, css differing in 62.3% of its
bytes, and it cost two lanes an investigation and a sealed-holdout scare before
somebody measured the sources and found **zero divergent authored bytes over 159
trees**.

Generated files now ride the mtime and not the digest. `lowered()` names them
from the CLI's own output contract - `parser.c`, `node-types.json`, `grammar.js`,
and the whole of `src/tree_sitter/` - and everything else defaults to authored,
so a file this rule has never heard of stays in the identity rather than falling
out of it silently.

Two things came out of doing it properly. `sources()` follows each scanner's
`#include` closure, so the shim scanners in the three monorepo grammars - ocaml,
php and typescript, whose entire body is `#include "../../common/scanner.h"` -
now carry the header they include. Those three had **no authored C in their
identity at all** before, because the file lives above the `src/` the old walk
started at; php's identity moves on a one-byte edit to that header now and did
not before. And `built()` keeps a separate digest over exactly the generated
files, so the question the old rule was conflating - *is this parser stale
against its own grammar* - still has an answer, on its own field, where
`holdout.py` reads it.

Measured over every oracle tree on this machine, both rules in one pass: 206
trees over 77 grammars, **2 grammars split under the old rule and 0 under the
new one**, and the file listing beside each split names the cause - `parser.c`
present in one arm and absent in the other. `attest.py verify` drives fourteen
rows against a scratch copy: the identity moves on a byte of `scanner.c`, a byte
of `grammar.json`, an added file, a deleted file and a byte of php's included
header; it holds across the five-file deletion a scanner refresh used to leave
and across a real `tree-sitter generate`; and it holds while `built()` moves when
a `parser.c` is torn away from the grammar it was lowered from. Every row prints
what the retired rule says beside it, so the change is visible biting rather than
asserted.

# joints

Experimental 0.1.0 Rust access to the separately supplied `libjnt`. The crate
provides grammar banks, parsers, immutable trees, byte positions, repair
evidence, and in-process tree-sitter notation queries. It has no Rust
dependencies and does not invoke Zig during a consumer's Cargo build.

## Build and link

Use the matching native archive from
[Joints releases](https://github.com/The-Billy-Company/joints/releases), or
build from source with Zig 0.16 and the sibling `irregex` checkout described
in the repository's `CONTRIBUTING.md`:

```sh
zig build
cargo test --manifest-path bindings/rust/Cargo.toml
```

Within this checkout, `build.rs` finds `zig-out/lib`. For another checkout or a
packaged crate, point at a native build for the same target as Cargo:

```sh
JOINTS_LIB_DIR=/absolute/path/to/joints/zig-out/lib cargo build
```

Release archives are `joints-0.1.0-linux-x86_64.tar.gz` and
`joints-0.1.0-macos-arm64.tar.gz`. Set `JOINTS_LIB_DIR` to the extracted
archive's `lib/` directory. The included `grammar/json.json` is a reproducible
starting bank. Native archives are tested on Ubuntu 24.04 (glibc 2.39) and
macOS 14; other targets require a source build.

The default links the standalone `libjnt.a`. The build script copies that
archive into Cargo's output directory, so a sibling shared library cannot
silently change the selection on macOS. Missing artifacts fail with a command
to build them; the crate does not download or manufacture a replacement.

`JOINTS_LINK_KIND=dynamic` selects `libjnt.dylib` on macOS or `libjnt.so` on
Linux. Crate test executables receive its explicit runtime directory; a
downstream application must arrange its own runtime search path and deploy the
shared library. The binding requires ABI 2 and the query/repair symbols in the
current native library. No native library or grammar bank is bundled in the
crate package.

## Parse and query

```rust,no_run
use joints::{Bank, ForeignPolicy};

let bank = Bank::open("languages.codex")?;
let parser = bank.parser(Some("json"))?;
let tree = parser.parse(br#"{"a": [1, 2, 3]}"#)?;
let query = parser.query("(number) @value")?;
for matched in query.matches(&tree, ForeignPolicy::Refuse)? {
    for capture in matched.captures {
        assert_eq!(capture.name, b"value");
        let original_bytes = capture.node.text().expect("valid source span");
        println!("{:?}: {:?}", capture.node.byte_range(), original_bytes);
    }
}
# Ok::<(), joints::Error>(())
```

Banks accept a single-language folio, a codex, or a tree-sitter `grammar.json`.
Opening JSON imports and presses the grammar; production workers should reuse
a parser or open a prebuilt artifact. A language may be omitted only for a bank
with one unambiguous member.

`parse` is strict: accepted, sound, exactly one root, and no deleted or supplied
tokens. Acceptance can follow repair, so it is insufficient by itself. A
strict refusal returns `ErrorKind::ParseRefused` with `Confidence` evidence.
`parse_partial` explicitly keeps the forest for diagnostics. Its `repairs()`
returns the native deletion spans `[start, end)` and zero-width insertions,
including their inserted terminal spellings and refusal context.

`Node` provides all/named children, fields, parent and siblings, byte spans,
and zero-based row/byte-column positions. Names and source text are exact byte
views; callers can apply their own UTF-8 policy. A tree keeps an immutable copy
of its original source, so later parses and dropped input buffers do not change
node text or query predicates.

Queries retain the native pattern and capture order, including repeated
captures. Text predicates run against that retained source. Foreign filters
require `Refuse`, `Admit`, or `Deny`; `Refuse` is the appropriate choice for CI
findings. Unsupported query branches and invalid regular expressions return
an error instead of an incomplete successful result. Not every tree-sitter
query construct is implemented yet.

## Ownership and workers

`Bank::parser` borrows its bank. `Bank::into_parser` transfers the bank into the
parser, allowing a worker to retain it without borrowing a stack frame:

```rust,no_run
use joints::{Bank, Parser};

fn worker_parser() -> joints::Result<Parser<'static>> {
    Bank::open("python.folio")?.into_parser(Some("python"))
}
```

Both forms preserve the ownership chain `Bank → Parser → Tree/Query → Node/Match`.
Rust prevents dropping an owner while a dependent handle or borrowed view
remains live.
An owned parser frees its native parser before closing its bank. Its `'static`
parameter means it borrows no external bank; trees and queries still borrow it.
Native match arrays are freed after eager conversion to Rust captures; their
nodes and capture names continue to borrow the tree and query.

All handles remain `!Send` and `!Sync`, including an owned `Parser<'static>`.
Create the bank/parser inside each worker; a `Send + Sync` frontend can hold
artifact paths and retain an owned parser in thread-local state. The Rust surface
currently exposes immutable parses, so there is no
edit operation that could invalidate a borrowed node. The native incremental
weave API has not been wrapped here yet.

This is an experimental `0.1.0` API. Parse correctness must be demonstrated on
the consumer's corpus before replacing an existing CI parser; structural
soundness alone does not prove language coverage or finding parity.

## Verify

```sh
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test
cargo doc --no-deps
```

Native integration cases use the packaged, pinned JSON grammar. Compile-fail
documentation checks owner lifetimes and thread confinement. Tests retain
earlier trees across subsequent parses and compare original bytes, fields,
neighbours, exact repair spans, nested captures, and predicate refusals.

Apache-2.0. See `LICENSE` and `NOTICE`.

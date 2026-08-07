"The C ABI is `libjnt`, symbols prefixed `jnt_`" has been a sentence in the
README since the day the package was pitched, and the sentence was the entire
implementation. Every consumer that is not a Zig program - which is every
consumer this package was pitched at: editors, agents, other languages' FFI -
had no door.

The door exists now: **32 `jnt_*` exports** behind `include/jnt.h`, built as
both `libjnt.dylib`/`.so` (which owns the header install, for the dlopen and
cffi crowd) and a `libjnt.a` that **links standing alone** - the archive is
assembled from a partial-linked object so irregex's C floor rides inside it,
the exact lesson the sibling package's build carries in a forty-line comment,
inherited here rather than relearned by shipping an archive with undefined
symbols first.

The surface is three handles in a strict lifetime order - a `jnt_bank` (a
folio, a codex, or a `grammar.json` pressed on open), an `jnt_parser` lent out
of it for one language, `jnt_tree`s handed back - plus node accessors that
bounds-check every ref, so a stale or invented node reads as absence rather
than as memory. Every entry returns a status instead of aborting, and
`jnt_last_error()` holds the sentence the CLI would have printed, per thread.
A parse returns a tree on **every** success, accepted or not: `jnt_tree_stop`
names how it ended, the mend counters say what recovery did, and a truncated
file is a partial tree plus a reason rather than an error with no prefix.

Proved from the outside, not asserted: a plain C program compiled with `cc`
against the header and the static archive opens the committed JSON grammar,
is refused (`JNT_LANGUAGE`) for a language the bank does not hold, parses,
walks the tree, renders the same s-expression the CLI prints, gets
`JNT_TRUNCATED` with a tree attached for a cut-off file, and gets `JNT_IO`
plus a sentence for a path that is not there. The same program runs unchanged
against the dylib. The bodies live in `src/surface/abi/bank.zig` and are
tested as plain Zig; the export shims are one-liners, so what the C boundary
can still get wrong is a signature, and the test build compiles them all.

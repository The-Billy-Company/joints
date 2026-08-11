# abi - `libjnt`, and the two doors on it

Everything else in this package is Zig talking to Zig. This is the one place
where somebody else's language asks the question, and the whole reason the
grammar is a *file* rather than a generated C program: there is no shared
library per language and no ABI window to keep matched, so an embedder links
one `libjnt` and opens whatever file they were handed.

[`include/jnt.h`](../../../include/jnt.h) is the normative statement of every
signature. This directory is its bodies.

| | What it owns |
|---|---|
| `exports.zig` | The `export fn` root, and nothing else. Every symbol is a one-liner over a body below. |
| `bank.zig` | Open a file of languages, lend a parser out of it, hand trees back - and the node vocabulary both doors answer through. |
| `loom.zig` | The edit door: a file held open across keystrokes, and what one of them cost. |

`exports.zig` is a separate root from `src/root.zig` for a linker reason rather
than a taste one: a Zig `export fn` is emitted by *every* compilation that
reaches it, so a shim living in the library module would be duplicated into
every downstream artifact importing it, and a host linking two would get
duplicate symbols for one it asked for once. Keeping them here means the symbols
exist exactly where the `.a`/`.dylib` named after them is. It also makes the
artifact root a *consumer* of `joints`, so nothing the CLI needs can quietly
become something an embedder must link.

## Two doors, one tree

`jnt_parse` answers *what is this file*. A **weave** answers *what is it now,
given that it was that a moment ago* - the question an editor asks a thousand
times an hour, and the only question an incremental parser exists for. Until
`loom.zig` the whole weave was reachable from the CLI alone, so an embedder's
only way to follow a keystroke was to re-parse the file: exactly the cost the
package was built to avoid.

Both answer through the same `jnt_tree` and the same `jnt_node_*` vocabulary,
and a highlighter cannot tell which door its tree came through. That is the one
design decision in here worth defending, because the alternative - a second
`jnt_weave_node_*` family - was two of everything forever.

**The weave handle is the FILE, not the parse.** `jnt_weave_tree` lends back a
tree the weave owns and refreshes in place: the pointer stays valid and stays
correct across every edit, and freeing it is a no-op. What does *not* survive an
edit is a `uint32_t` node ref taken before it, because the arena those index
into is rebuilt. Refs are per parse; the handle is per file. tree-sitter draws
the line in the same place and pays for it with an owned tree per edit.

**A weave carries its own scanner, and that is not a duplicate.** The scanner
holds the *ruling* - the file's line structure - and a ruling is a fact about
one document's bytes. Sharing the parser's would leave a `jnt_parse` on that
parser reading through a ruling that describes some other file. One scanner
compile per file opened, paid once, against a wrong answer per parse.

## Rules a host has to keep, and what happens when it doesn't

**Lifetimes are a chain.** A tree or a weave borrows its parser; a parser
borrows its bank. Free trees and weaves, then parsers, then the bank. A parser
owns the scratch its parses run in, so use one per thread - two parsers on two
threads are fine, one parser on two is not.

**Strings cross two ways, on purpose.** Titles, node names, fields and renders
are borrowed pointer + length views into the handle that answered, because a
folio's names are mmap-ed bytes and a copy per call is the allocation this
format exists to avoid. They are not NUL-terminated. Only `jnt_version`,
`jnt_last_error` and `jnt_tree_sexp` are.

**Nothing aborts.** Every entry returns a status, so a malformed file, a wrong
language, or a host that miscounted an edit span can never terminate the
process. The kernel is allowed to assert what a C caller must not: `Weave.amend`
asserts its span and `jnt_weave_amend` checks and refuses it. On a negative
status `jnt_last_error()` holds the sentence the CLI would have printed, per
thread, valid until that thread's next `jnt_*` call.

**A ref is bounds-checked, always.** A node is a `u32` index into the tree's
arena and `JNT_NONE` is the answer that is not a node, so a stale or invented
ref reads as absence rather than as memory. The kernel's own accessors assume
what a C caller must not.

## What is not here, and why

**No cursor type.** tree-sitter ships one because its `TSNode` is a struct whose
parent costs a walk from the root, which makes a stateful cursor the only
affordable way down a tree. Here a node is an index and its parent is a field
read, so a cursor would be a struct holding the two integers the host is already
holding. `jnt_node_parent` / `_next` / `_prev` / `_next_named` / `_prev_named` /
`_by_field` / `_depth` / `_covering` are what it would have been made of.

**No query door yet.** `kernel/gloss` compiles a `.scm` against a pressed
grammar and runs it against a tree, and neither half is reachable from here.
That is the largest thing still missing from this directory, and the top-level
README says so in the same words.

**No `jnt_weave` knob for the deliberate breaks.** `weave.Bend` exists so the
fuzz can prove itself able to fail. A door that let a host ask for a known-wrong
parse would be a door for filing bugs against.

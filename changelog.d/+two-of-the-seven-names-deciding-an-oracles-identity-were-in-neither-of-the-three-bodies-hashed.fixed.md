`attest.rule()` stamps every oracle digest with the version of the code that
computed it, so a digest taken under one rule is never silently compared against
one taken under another. It computed that version by hashing the source text of
three functions - `survey`, `sources`, `lowered` - and the lane that shipped it
named it as the thing it trusted least, in the exact shape of the bug it had
just fixed: *a constant moved outside those three functions would change the
identity while the digest held.*

It is not hypothetical and it was not one constant. `survey` calls `split` to
decide what a grammar's root actually is; `sources` filters through
`differential.INCLUDE`, in another module, which decides which files the scanner
closure even reaches. Both were live inputs to the identity. Neither was in any
of the three bodies. **The whole include half of an oracle's identity could have
been rewritten under a digest that never moved.**

`rule()` now digests the transitive closure. `reads()` walks the AST of the
three seeds, collects every module-level name they cite - `module.attr` too, so
a constant in another module is reached - recurs through the functions it finds,
and renders data values through `spell()` so a compiled pattern, a `Path` or a
`set` hashes by what it means rather than by its `repr` and its address. Seven
names, 6,310 bytes, up from three bodies.

The bound is now in the tool rather than in a dossier. `attest.py rule` prints
what is covered and, beside it, what is **not**: seven boundary names, each with
the reason it cannot be. Six are the standard library, pinned by the interpreter
and not by this repo; one is a module named on the way through whose contents are
folded in above. The output states the claim in one line - *the 7 names above have
not changed* - and states in the next what it is not, because a rule digest is one
of four things making two oracle digests comparable and `Oracle.cli`, `tree` and
`lower` carry the other three. Nothing in the closure renders opaque, and `verify`
asserts that: an unrenderable value would be read and not digested, which is the
same bug with a different door.

Three new verify rows, each an edit to a dependency the old rule could not see:
`differential.INCLUDE`, `split`, and `LOWERED` as the control that both rules
always did read. Each row is asserted twice - the new rule moves, and the rule it
replaced is asserted to *hold*, still reachable as `narrow()` so the fix has
something to be a fix of. Two of the three hold under the old rule. That is the
falsifier and it is the two-of-three the report should have had.

`Oracle.cli` and `rule` are also the two fields of `attest` the new
`tool/budge.py` sweep reads `flat/thin` - one tree-sitter version and one rule
version have ever been on disk here - which is the correct verdict for both and
becomes a finding the moment either moves.

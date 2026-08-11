`gloss` could read a `.scm` file, resolve every kind and field and capture name
against the grammar, refuse the ones that could never match, and lower the whole
thing to a `stencil.Program` it could store in the folio as bytes. Then it
stopped. There was no code anywhere in the package that took one of those
programs and a parsed tree and produced a match, which meant the compiler was
being tested against its own output and nothing else - the strongest possible
guarantee that a query compiles, and no guarantee at all that it finds anything.
The README said `gloss` "does not exist", which was the wrong half: half of it
had existed for a while and could not be asked a question.

`scribe.zig` is the other half. A pattern is tried at a
node, never at a file. Every pattern's root kind goes in a sieve up front, so
walking the tree costs one lookup per node and most nodes match nothing and are
dropped without touching a pattern body. Sequences run on an explicit frame
stack rather than the Zig call stack, because a query is data read from a file
and a deeply nested one should be a slow query and not a crashed process.

Quantifiers are greedy with backtracking, which is the choice worth writing
down, because the lazy version passes a surprising number of tests. `(a)* @c` on
three sibling `a`s should capture three, and a lazy matcher captures zero and
still reports a match - the pattern is satisfied, the captures are empty, and
nothing in a highlighting test necessarily notices. It shows up the moment a
capture is on the repeated node instead of beside it.

Anchors constrain against *named* siblings, matching tree-sitter, which reads
backwards until you try it on source with comments in it: `(a) . (b)` should hold
when a comment sits between them, because the anchor is a claim about the shape
of the tree and a comment is not part of that shape. Predicates that `joints`
can evaluate itself (`#eq?`, `#match?`, `#any-of?`) run inline against the
source bytes; the ones it can't are handed back to the host as opaque filters
rather than silently dropped, since a query that quietly ignores the predicate
that made it correct is worse than one that refuses.

On its own this buys a matcher with tests and not a feature, and worse, a
matcher whose tests and whose implementation were written from the same reading
of the notation. The CLI verb that gives it a door - and, being the same
question tree-sitter's own CLI answers, an oracle - is the next fragment. There
is still no query door on the C ABI.

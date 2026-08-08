A query matcher asks a tree nine things and `Quire` answered five of them, none
of which were the nine: `name`, `isNamed`, `isExtra`, `field`, `children`.
`parent` was a stored field with no accessor at all. Siblings, named siblings,
child-by-field, deepest-cover-of-a-byte-range, depth and subtree size existed
nowhere in production - they existed as private helpers inside
`src/kernel/vellum/sheet_test.zig`, written the slow obviously-correct way in
order to check the settled tree's clever way.

So the floor for `.scm` queries was going to be written a fifth time, from
memory, by whoever built the matcher. `src/kernel/quire/reach.zig` is those
walks, moved: `parent`, `among`, `nextSibling`, `prevSibling`,
`nextNamedSibling`, `prevNamedSibling`, `childByFieldName`,
`descendantForByteRange`, `depth`, `subtreeSize`. `Quire` aliases each one, so a
caller writes `q.nextSibling(ref)` and never names the file, and the oracles stay
exactly where they were because they are still `Sheet`'s check. `sheet_test.zig`
now runs both arms of five of them on every node of every corpus file.

The two things worth getting wrong are both about absence, not speed.

**The top of the tree is a run, not a node.** `root()` is null unless the parse
left exactly one, because a parse that stopped early hands back the forest of
everything it completed and this package refuses to crown a fake `program` over
it. So the roots are a sibling run like any other - `nextSibling` of a root is
the next root, `parent` of a root is absence, `depth` of every root is zero, and
a byte range inside a stretch a mend walked past is covered by **nothing**,
where tree-sitter's single root would claim it. A clean single-root parse
exercises none of that, so `reach_test.zig` builds the forest by hand.

**An extra is a child that does not count structurally.** A comment is in the
tree, has a name, and is matched by a `(comment)` pattern - so both sibling walks
step onto one, because tree-sitter's named walk tests visible-and-named and a
comment is both. I checked that against `tree-sitter query` rather than
reasoning about it, since a guess here yields a matcher that disagrees with the
incumbent on comment-adjacent patterns and nowhere else. The one place an extra
is skipped is the field map, and `gather` skips it there: a spliced extra is
refused the step's field on the way in, so `childByFieldName` cannot answer with
one regardless of what it does.

`descendantForByteRange` is the one that matters more than it looks. It is how
an editor highlights the viewport instead of the file, and it is the only
accessor here that is not total: it bisects each sibling run, which needs the
runs sorted and disjoint, and `survey`'s `order` treats that as checkable rather
than given. Its doc comment says so.

A highlighter resolves two captures on one byte by which arrived last, so the
order a matcher hands its answers over in is part of the answer and not a
presentation detail. Ours was the order the search happened to find them in,
which is a fact about the search: a pattern rooted on a `declaration_list` has
answered for every function inside it before the walk has descended to the first
one, and a pattern rooted on the function itself arrives long after.

Two layers, both found by differentiating against tree-sitter's `query` verb:

- **Inside a match**, a node's own capture was bound on the way back up from its
  children, so `(struct_item name: (type_identifier) @name) @definition.class`
  reported the name before the struct. It is now bound before the descent, which
  is the order the pattern was written in. Nothing needs unwinding for it -
  every failing path already truncates the capture list to its mark.
- **Between matches**, a match is now held until the walk reaches where it
  *finishes* - not where it begins, which is the reading a position sort would
  want and is the wrong one. `["<" ">"] @punctuation.bracket` binds both
  brackets in one match and is not settled until the closing one, so a
  `(primitive_type) @type.builtin` between them is answered first even though it
  starts later. Ties go to the match that opened higher up, then to the earlier
  pattern. The buffer holds only the patterns open at an ancestor of where the
  walk stands and recycles its capture lists, so the reordering costs an
  allocation per outstanding match rather than one per match.

Of the twenty-six differential pairs, sixteen now agree as sequences where eight
did; the residue is pairs of captures landing on the same byte.

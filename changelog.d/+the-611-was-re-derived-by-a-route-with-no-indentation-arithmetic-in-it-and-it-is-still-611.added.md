The lane that made verilog and sql adjudicable named `indents()` as the thing it
trusted least and said so in its own result: five of the twenty-three fixtures
that cleared it were written after the diagnosis, and the other eighteen are
clean javascript, which cannot reach a defect that only exists inside an error
subtree. So the headline was quoted with a request not to trust it.

`research/joinery/unjudged/rederive.py` re-derives it by a route that reads no
column. `indents()` decides exactly one thing — **parentage**; every name, every
`named` flag and both offsets come from a row's own text and range prefix. So
parentage is taken from somewhere else instead:

| face | what it gives | columns in it |
|---|---|---|
| `parse -x` | every **named** node, nested unambiguously, with `srow/scol/erow/ecol` | none |
| `query` over every anonymous type in `node-types.json` | every **anonymous** node's span | none |

Anonymous nodes are tokens, so they are always leaves, and a leaf's parent is
the narrowest named node containing it. Nothing is guessed. **The XML has
carried ranges all along**, which is the fact that made this an afternoon rather
than a week — and it means `indents()`'s real freedom was never the named half
at all, only where anonymous nodes attach, which is precisely what a query
settles from the outside.

```text
verilog        CST reader   XML + query   moves
nodes             48,883        48,883      —
of width > 0      48,804        48,804      0 either way
square               611           611      0
racked            12,112        12,102    −10
unjudged           4,182         4,193    +11
```

**611 survives, exactly.** The eleven bytes are the 67 zero-width `MISSING`
tokens and nothing else: a token of no width has no extent to be placed by, so
the column-free route attaches it by the only rule available. Neither route
paints a byte for an empty span, so neither can reach `square`; what moves is
`Node.leaf` on the node that adopted one, which is one of the two channels the
prediction named in advance. Corpus-wide, 29 rows read both ways, **0 node
multiset mismatches, `square` identical on all 29**, and 28 of 29 identical in
every column.

The other half is the population. Eighteen fixtures could not reach the defect,
and **the corpus is barely better — it puts an error subtree in the oracle's
tree on two rows out of thirty.** `rederive.py mutants` manufactures the
population instead of choosing it: each corpus file truncated, then a 24-byte
excision and a hostile insertion at each of six offsets a seeded LCG picks.
Whatever error subtrees come out are the shapes that grammar's own recovery
makes.

```text
390 mutants over 30 grammars · 349 read · 222 error-bearing over 27 grammars
shipped reader vs the column-free tree:  0 disagreements, 0 refusals
the same mutants read by tool/differential.py at git HEAD, which predates the fix:
    78 mutants · 6 grammars  →  21 refused
    26 mutants · 2 grammars  →  15 refused
```

**Javascript is the sharp one.** The eighteen fixtures that could not touch this
defect are javascript, and javascript mutants break the pre-fix reader on 2 of
13. The fixtures were not the wrong language; they were the wrong *state* — not
one of them had a syntax error in it.

`mutants --was <rev>` refuses to be a decoration: when the named revision
answers exactly as this one does on every mutant it prints **`VACUOUS` and exits
1** rather than passing, so once the fix is committed the gate says on its own
face that HEAD has stopped being a falsifier.

One route was tried and abandoned, and it is worth writing down because it looks
ideal: **`parse --dot` is not a witness.** Explicit `parent -> child` edges,
byte ranges in the tooltips, no columns — and it renders tree-sitter's
*internal* subtree tree, with hidden rules, unresolved aliases
(`simple_identifier` where the CST has `parameter_identifier` over it) and
differently padded offsets. Reconstructing the visible tree from it means
reimplementing tree-sitter's own alias and visibility resolution: a third reader
with a third set of defects.

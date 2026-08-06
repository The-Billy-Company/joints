# Result 3 — the html case

The Swift case again, in the grammar the brief calls genuinely clean, and
harder: **no other instrument in this tree can see it, including `rack`, and
including `rack` run against the specimen itself.**

Pin `spec2`, tree `fa7fcaee5`.

## The nine bytes

`research/joinery/specimen/html/erroneous-end-tag.html`:

```html
<p>x</q>
```

tree-sitter reads one element:

```
element [0, 8)
  start_tag [0, 3)
  text [3, 4)
  erroneous_end_tag [4, 8)
    erroneous_end_tag_name [6, 7)
```

outliner produces three roots and no `element` at all:

```
start_tag [0, 3)
text [3, 4)
erroneous_end_tag [4, 8)
  erroneous_end_tag_name [6, 7)
truncated, 3 roots
html: unclosed: input ended before the start symbol closed; nothing refused a token
```

**Every leaf is identical, at identical extents**, including the external the
specimen was written for. Only the parent is missing. Four of the six claims
hold - the lexing is right and nothing was repaired. `roots 1` and
`holds element` fail, and they are the entire defect.

`_erroneous_end_tag_name` is declared external precisely so that a mismatched
close is a *named thing* rather than damage. outliner names it correctly and
then cannot close the element over it.

## Why nothing else sees it

**The board.** html is 72,288 bytes, 72,288 built, 100.0% standing, zero
damage, zero orphan, zero rubble, zero spoil.

**The corpus cannot present it.** tree-sitter over `viewer.html` builds 13,972
nodes: 531 `element`, 506 `end_tag`, 0 `ERROR`, and **0 `erroneous_end_tag`**.
The file has 34 unmatched opens and 511 closes and not one mismatched pair. A
construct with zero occurrences cannot move a corpus instrument in either
direction, which is the Swift case's mechanism exactly.

**`plumb`.** Every leaf agrees, so a byte-indexed leaf comparison files all
seven built bytes plumb.

**`rack`, and this is the part worth reporting upward.** rack is the most
sensitive instrument here and it compares derivations, not bytes. Run against
this specimen it reports:

| | size | built | square | askew | racked | brackets | frames |
|---|---|---|---|---|---|---|---|
| corpus `viewer.html` | 72,288 | 72,288 | 72,288 | 0 | 0 | 13,971 / 13,971 | 1 |
| specimen `<p>x</q>` | 9 | 7 | 7 | 0 | 0 | 6 / 6 | 2 |

**Zero askew, zero racked, six of six brackets shared - on the specimen.** The
Swift case at least moved rack when rack was pointed at a specimen; this one
does not.

The mechanism: rack compares spines *inside built windows*, and a parent that
was never built is inside no window. Its `frames` column does notice 2 frames
where the oracle has 1, but `framed` only charges a frame whose **name**
disagrees with the oracle's, so a parse that fragments into more frames than
the oracle costs nothing in any scored column. A wrong shape over right leaves
was rack's founding example against `plumb`; a **missing** shape over right
leaves is the same blind spot one level further out.

I have not changed `rack` - its owner has left and it is shared. This is the
report, and the fix I would suggest is a column that charges frame-count
disagreement, not a change to `framed`, which measures something else
correctly.

## The instrument count

For these nine bytes: board blind, `plumb` blind, `rack` blind, corpus
structurally incapable. **One instrument in the tree sees it**, and it sees it
because the input was built to contain the construct rather than found to.

## The honest limits

- One defect, one grammar. It does not make html broken; 93.8% of html's
  spellings *are* present in `viewer.html`, the highest of the twelve `whole`
  grammars. The claim is narrower and worse: even the best-sampled grammar in
  this tree has a declared construct its corpus never presents, and that
  construct is mishandled.
- I have not fixed it. Diagnosing why the element cannot close over an
  `erroneous_end_tag` is a parser change and belongs to whoever owns that seam;
  this is the witness, reduced to nine bytes and adjudicated against the
  oracle.
- The `roots 1` claim would have passed against a binary that refused html
  outright, until the `stop()` repair recorded in `RESULT-2-absence.md`. It
  passes now because the binary genuinely reports three roots.

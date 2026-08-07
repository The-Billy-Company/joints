Fifteen specimens across thirteen new grammars, authored against the coverage
gate's unexercised externals and with every claim derived from tree-sitter's
own parse rather than from joints's. The tier is **37 specimens over 20
grammars, 28 sound**, up from 22 over 7 with 15 sound. Witnessable externals
exercised went **22 of 36 to 35 of 36**; the holdout is yaml's, which no
specimen can reach because joints refuses to lex yaml at all.

The finding is html. The board calls it genuinely clean - 72,288 bytes, 100.0%
standing, zero damage - and `rack` scores `viewer.html` 13,971 labeled brackets
shared of 13,971, zero askew, zero racked. Both stay true. Nine authored bytes
say something else:

```html
<p>x</q>
```

tree-sitter reads one `element [0, 8)` over a start tag, a text node and an
`erroneous_end_tag`. joints produces **three roots and no `element` at all**,
then `input ended before the start symbol closed`. Every leaf is identical at
identical extents, including `erroneous_end_tag_name`, the external this
specimen was written for. Only the parent is missing.

tree-sitter over `viewer.html` builds 531 `element`, 506 `end_tag` and **zero
`erroneous_end_tag`** - the corpus never presents a mismatched close, so no
corpus instrument can have an opinion about one. That is the Swift
`multiline_comment` mechanism exactly, in the grammar with the *best* sampling
of the twelve (93.8% of html's spellings are present in `viewer.html`, the
highest score in the tree).

`rack` cannot see it either, and that is the part worth passing to whoever
picks rack up. Against the specimen it reports 7 built, 7 square, **0 askew, 0
racked, 6 of 6 brackets shared** - clean. It compares spines inside built
windows and a parent that was never built is inside no window. Its `frames`
column does see 2 frames where the oracle has 1, but `framed` only charges a
frame whose *name* disagrees, so fragmenting into more frames than the oracle
costs nothing in any scored column. A wrong shape over right leaves was rack's
founding argument against `plumb`; a missing shape over right leaves is the
same blind spot one level further out. rack is unchanged here - its owner has
left and it is shared - so this is a report, not a patch.

Two of the fifteen are not defects and are recorded as such rather than
deleted: rust's `string_close` and `raw_string_literal_content` are aliased
away by their own grammar and can never appear under their own names, which is
what corrected the gate's denominator. Thirteen of the fifteen hold every
claim on first authorship - 13% guilty - and that ratio is the reason the two
are worth believing.

One specimen was wrong rather than the parser: the first C++ raw-string draft
was `R"tag(a)b"tag"`, which has no closing delimiter at all, and tree-sitter
ERRORed on it. An oracle that refuses is how an authored input gets checked.

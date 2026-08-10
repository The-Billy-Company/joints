The README's ceiling section is a status now, not a confession, and the title is
one that is true.

It was `joints: One Binary, One File, Every Language`, and the section closing
the case against it said so out loud: "'Supports every language' would be a lie,
and the title of this README is a goal rather than a status line." A title that
needs a paragraph downstream retracting it should just be a different title. It
is `joints: a grammar is data - and so is its scanner`, which is the actual
difference from tree-sitter and is true of the tree it describes.

The same section ended on a prediction this rung falsified:

> No reader that refuses to understand C is going to lower those. I am not going
> to pretend otherwise.

"Those" was 310 of 382 externals - the ones whose C keeps state between calls.
Books claim **198 of the 310** now. That sentence has been kept in the section
and marked wrong rather than quietly deleted, because it was wrong in the
flattering direction: it bought credit for candour instead of measuring, and
being publicly resigned to a limit is not evidence of one.

Numbers refreshed off `bf8e0ad` (2026-08-09), which moved several that were
stated as of `7eb9bb9`:

| | was | now |
|---|---|---|
| corpus standing | 78.12% | **79.55%** |
| of that, misread | 0.48% | **0.39%** |
| grammars at 100% | 18 | **20** |
| read to whole with repair | 19 | **20** |

The two new 100% rows are yaml (0.0%) and markdown (5.4%), and the section now
says why those two are *not* equal evidence - which the old prose had no vocabulary
for. markdown is judged against tree-sitter's tree (516 agree, 6 misread). yaml's
18,935 bytes are **unjudged**, all of them, because tree-sitter's own yaml scanner
does not compile here, so there is no oracle. A tree where there was no tree is
worth having and is not a claim the tree is right. html carries the real proof
instead: 47,047 judged bytes, zero misread.

Also corrected: M1's row in the monoid table still read "still missing the
externally-scanned terminals", stale by 198 terminals; the layout tree never
mentioned `customary/`; and this section was the only `##` in the file missing
from its own table of contents.

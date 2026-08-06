`multiline_comment/.marrow/.swift_block` was priced at zero alone, zero beside
its partner and zero in the pair, and written up as **a seated row that changes
nothing in any combination available to it** - with a standing rule that an
inert implementation is deleted rather than left in place.

It is not inert. Against `aud-r3`, the arm that is today's tree with exactly
that row removed:

| specimen | row in | row out |
|---|---|---|
| `swift/multiline-comment.swift` | ok 4/4 | **FAIL 2/4** - `holds multiline_comment` → absent |
| `swift/nested-comment.swift` | ok 4/4 | **FAIL 2/4** - `holds multiline_comment` → absent |

Two bound falsifiers, green with the row and red without it, and both were
written before the pair sweep ran. The zero is a fact about the corpus:
`Chunked.swift` contains **zero** `/*` and zero `*/`, so no board arm - single,
pair, or the fourteen-row union - could ever have moved on this construct. Not
misdiagnosed and not shadowed by another row; the target is not in the file.

The seating's *motivation* was wrong, though, and that is worth separating from
the seating. Both `.expect` headers justify it with swift's "3,997 orphan
bytes". Split by node name off the control's own parse, those 3,997 bytes are
**3,997 of `comment`** - the `//` line comment - and **0 of
`multiline_comment`**. Right construct, wrong number: swift block comments nest,
`nested-comment.swift` shows a stateless reader closing at byte 21 where the
answer is 27, and the row is what makes that right. The two headers are
corrected; every `roots`/`mends`/`holds`/`spans` claim is untouched and both
specimens still pass 4/4.

Also visible from the same run and left for whoever takes swift next: on the
**control** arm `raw-string.swift` scores 1/5 and `raw-delimiter-in-body.swift`
scores 0/4, both on `holds raw_string_literal` → absent.

`research/joinery/consort/RESULT-2-swift.md`.

Swift's `raw_string_literal` was unseated: `#"…"#` and `##"…"##` have a close as
wide as the opener, and nothing in this lexer answered it. Both of the
construct's specimens failed on the control - `raw-string.swift` and
`raw-delimiter-in-body.swift` - and the coverage gate read swift `blind to 11
externally scanned terminal(s)`.

It fits `marrow`, on the same ground `swift_block` does: the run *is* the token,
delimiters included, and its width is read off the bytes at the offset rather
than remembered. So the row seats `raw_str_end_part` as a `close` and
`marrow.shut` walks it - count the hashes, require a `"`, then run to the `"`
followed by exactly that many hashes. `##"a "# b"##` is one literal because the
`"#` in its middle is a hash short, which is the entire claim of the second
specimen and one no assertion about node *presence* can make: both readings
build a `raw_string_literal`, and only the extent says which.

**Half of it is declined, and that half is the finding.** The grammar is

    raw_string_literal := (raw_str_part raw_str_interpolation ...)* raw_str_end_part

so a literal with no `\#(` is `raw_str_end_part` alone and needs nothing else.
An interpolating one resumes after the interpolation's `)`, at an offset whose
bytes cannot say how wide the delimiter was. C++'s raw strings recover theirs by
walking back, because the standard caps the tag at sixteen identifier bytes and
the `(` is immediately behind the content; swift's resume point has a whole
expression behind it - parens, strings and comments of its own - so there is no
bounded walk back and the count would have to be *remembered*. Remembering is
`fence`'s job and `fence` cannot hold this either: its cast is `open`/`body`/
`close` as three tokens and swift's opener has no token of its own to push a
span on. tree-sitter-swift agrees, and pays for it - `ongoing_raw_str_hash_count`
is the only field in its `ScannerState`. So the interpolating literal gets
silence and today's parse, rather than a `raw_str_part` answered over a
delimiter nothing checked.

Measured on `swift-raw` against `swiftlane-ctl`: specimens **6/8 → 8/8** and
blind terminals 11 → 10. The forests over `Chunked.swift` are **byte-identical**,
88,831 bytes of printed tree on each side, which is the right result and not a
null one: the fixture contains no `#` at all, and a walk that requires one at the
offset cannot fire. `built`, `square`, `damage`, `roots` and `orphan` all move by
exactly nothing. The board could never have priced this row; only the specimens
can.

**The audit split moves anyway, and that is not about this row.** Same fixture,
same folio, same oracle (`99aa15e95ec4/tree-sitter 0.26.11`), identical forests -
and the control reads `8754 crooked · 913 soft · 1179 unframed · 14 unaudited`
where the arm reads `8740 · 927 · 1193 · 0`. Both total `built`, and `square` is
14,419 on each, so the metric the board is judged on is stable. But four columns
moved by exactly fourteen bytes over two trees that are the same tree, so the
split is not a function of the forest and the oracle alone; something in the
arm's own state reaches the auditor. The obvious suspect is the blind-terminal
list - seating `raw_str_end_part` takes it 11 → 10, and if verdicts are withheld
per *terminal* rather than per byte, then seating a terminal the file never uses
still unlocks coverage. That is a hypothesis and it is written here as one; it
lives in the adjudication lane, not this one. What it means for anybody reading
`crooked` across two arms is that a delta this small can be a seating artifact
rather than a parse, and `square` is the column that held still.

**It also took the fifteenth seat, and `witnessed.py` keys on the number.** That
tool pairs live row *i* off `ablate.py guests` with a retained pin named
`aud-r<i>` under `.local/aud-iso/`, and this row lands at index 4, so every row
from 4 up now answers against the pin for the row below it and row 14 - elixir's
caesura - falls off the end with no pin at all. It reports this row
`unwitnessed`, which is the one verdict it is structurally unable to reach here:
both its control and its arm were built before the row existed, so the two
specimens fail on each side and nothing can flip. Run against `aud-base` and a
pin of today's tree they flip 0/4 → 4/4 and 1/5 → 5/5. The pins want re-minting
against live indices, or the join wants keying on the seat string rather than
its ordinal; until then a `guests` list that grew is enough to make that table
wrong without making it look wrong.

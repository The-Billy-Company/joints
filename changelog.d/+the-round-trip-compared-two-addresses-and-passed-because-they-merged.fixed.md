The folio round trip compared `@tagName(gr.shapeOf(s))` to `@tagName(f.shapeOf(s))`
with `expectEqual`. Those are two enum types, so each `@tagName` is a pointer into
its own name table - and `expectEqual` on a slice compares the pointer, not the
text. Whether two identical literals end up at one address is the backend's
decision about constant merging, so the assertion was green on macOS and red on
Linux, having never once asked about the spelling it was written to check. It uses
`expectEqualStrings` now.

That pair, `press.Shape` and `leaf.ShapeKind`, also turned out to be the one
ordinal pair on the format's boundary carrying no comptime proof - the address
comparison had been standing in for one. It joins the other four under `concurs`,
which then found the fifth and sixth hand-written conversion switches still
restating what the proof establishes, in `impose` and `bind`. All thirty grammars
in the corpus mint byte-identical folios across the change.

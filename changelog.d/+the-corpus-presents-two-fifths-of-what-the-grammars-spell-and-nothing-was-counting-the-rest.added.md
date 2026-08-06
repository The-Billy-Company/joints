`tool/absent.py` - the inverse of the coverage gate. Every number in this
project is bounded above by what thirty found files happen to contain, and
until now nothing measured that bound.

It reads every `STRING` and `PATTERN` leaf out of all thirty `grammar.json`
files and asks whether the corpus file that grades that grammar contains the
bytes. **2,050 of 5,198 judgeable spellings are present - 39.4%. 3,148
spellings the grammars write down never occur in the file that grades them.**

The error direction is declared and is the opposite of `exercised`'s: a
spelling counts PRESENT if its bytes occur anywhere, including inside a comment
or a string, so ABSENT is a **floor** - the tool cannot invent an absence, only
miss one. 54 patterns it cannot compile as a Python regex and 32 that match the
empty string are counted present for the same reason, and reported separately
rather than folded in.

The calibration is the Swift case, which is the one absence in this tree whose
consequence is already known: the pattern `[\/]+[*]+` is absent from
`Chunked.swift`, and the file contains no `/*` at all. An instrument that
cannot reproduce that on its first assertion is not worth reading, so it is
assertion one of ten in `absent.py verify`.

What it found beyond the ratio: **four of the twelve grammars the board reads
at 100.0% standing sit below the 51.1% median presence** - latex at 9.1%, c at
30.3%, python at 45.3%, javascript at 49.3%. latex reads perfect off a file
that presents one spelling in eleven of what latex declares. That is not
evidence in either direction about latex; it is the size of the thing the board
cannot distinguish from correctness.

Where it is blind, said on every run: **456 of the 461 declared externals have
no body in `grammar.json`** - their spelling lives in a C scanner - so this
reader cannot judge them at all. That half belongs to `specimen.py coverage`,
which witnesses 36 of 461. Neither instrument covers the other's, and the run
prints both denominators rather than a ratio over the part it can see. yaml
spells zero literals and is reported as outside every number rather than
counted clean.

The structural half (`--oracle`: which named rules the oracle's own parse never
yields) is built and calibrated, but needs tree-sitter and is therefore absent
on exactly the 34,687 bytes where tree-sitter ERRORs - the bytes where the
lexical half is the only reading available and is the weaker of the two.

Where the number goes the wrong way, measured rather than hedged: over twelve
grammars, **34 of 211 multi-byte string spellings called PRESENT never occur
outside a comment or a string** - 16.1%, and 45.5% for css, 40.0% for latex,
31.7% for scala. `ledger.scala` contains `true` 17 times and `false` 16 times
and not one is a `boolean_literal`. So 39.4% is an overcount and the real
absence is *larger* than 3,148, which is the direction the floor claim promises
but a good deal further than "floor" suggested on its own. Intersecting with the
oracle would fix it and would also destroy the reason this reading exists, since
it is the only one available where tree-sitter ERRORs; both numbers are reported
instead.

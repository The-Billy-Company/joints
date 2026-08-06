Scala handed newline inference and its indentation regions to an external
scanner, and outliner seated none of the three. So `Option.scala` parsed as 314
top-level roots: every statement boundary the file did not spell with a `;` was
a place the parse could not continue, and the scaladoc above each definition —
recognised, lexed, reachable — sat as its own root because nothing was open for
it to belong to. 10,415 of the file's 20,107 bytes were `orphan` and standing
was 40.8%.

Scala 3's optional braces are the offside rule, not haskell's inversion of it,
and the two are indistinguishable from `grammar.json`. The scanner settles it:
`tree-sitter-scala` emits `INDENT` only where `newline_count > 0` and the
measured width exceeds the frame's, so it *detects* the region and
`valid_symbols[INDENT]` is only permission. Haskell's order is granted with
nothing measured at all, which is why that one needed `.writ`. `serialize`
agrees — a width stack plus five scalars of recent lexical context, which is
`offside.Columns`. So scala is a `.offside` troupe on `_indent` / `_outdent` /
`_automatic_semicolon`, and `offside.lead` learned a second comment spelling
(`//`, and a `/* */` that nests, because scala's does and C's does not).

`built` 8,204 → 15,957, `orphan` 10,415 → 4,046, `unbound` 1,488 → 104, roots
314 → 26, bare leaves 179 → 19, standing 40.8% → 79.4%. Rubble and spoil both
fell (476 → 62, 1,012 → 42): with `covered` already at 94.97% the parse was
reaching these bytes and failing to structure them, which is swift's case and
not haskell's, where seating brought bytes into reach for the first time.
Describes: 1,571 → 1,772 nodes, +12.8% for +94.5% `built` — the shape of
re-parenting rather than of reading more. Board: standing 64.83% → 66.30%,
unbound 121,918 → 120,534. No other grammar moved.

Where it goes the wrong way. The indentation stack — the organ this change was
briefed to build — is worth **21 nodes and zero bytes** on the corpus. All
7,753 came from the separator, which I predicted would be worth under 1,000
because the C runs its `AUTOMATIC_SEMICOLON` arm behind both `OUTDENT` arms. I
built the separator-only treatment as its own measurement because I had named
that as the falsifier, and it drained the identical amount. The comment rule
too: `.hash` and `.slashes` give byte-identical trees here, because a file with
almost no indentation region has nothing for a wrong column to be wrong about.
Both are seated and both are correct against the C; neither is what paid, and
the corpus cannot currently tell if either regresses. `offside.zig` carries four
unit tests that can.

The instrument that lied was sequencing read as competition. The `INDENT`,
`OUTDENT` and `AUTOMATIC_SEMICOLON` arms are ordered in one C function, and I
read that order as the terminals contending for the same offsets. The parse
table had already said otherwise and I had the number in hand before I built
anything: `_indent` and `_automatic_semicolon` are co-admitted by shift in 2 of
11,602 states, `_outdent` and `_automatic_semicolon` in 2, and the separator is
the sole shift in 209 of its 493. An arm's position in a `switch` is a fact
about the function, not about the alphabet.

`research/joinery/scars/against.py` puts our repair surface beside tree-sitter's
`ERROR`/`MISSING` nodes over the corpus - 29 of 30 grammars with a readable
oracle, yaml's parser will not compile in this seat - so "we are trying to beat
tree-sitter here" is a table rather than a claim.

| | tree-sitter | outliner |
|---|---|---|
| enumerate every repair site | `ERROR` nodes in the tree, `MISSING` on the CST | `--scars`, one line each - **level, and only as of this lane** |
| what each site carries | a span | byte range · refused terminal · refusing state · felled/kept · live heads · tokens since the last repair - **ahead** |
| repair by insertion | 70 `MISSING` nodes corpus-wide | none - **behind** |

**Ahead on localization, and verilog is the exhibit.** On the same 94,657 B
file, tree-sitter's 266 `ERROR` nodes between them cover **100% of the file** -
its recovery lets an `ERROR` reach the root, which is legal under its own
contract and useless to a consumer asking which bytes not to trust. Our scars
cover **34%**. On sql the counts nearly agree - 16 `ERROR` nodes against 14
refusals that shifted ground - and our spans are tighter, **245 B against
554 B**.

**Behind on a runtime capability, not on reporting.** Every mend this parser
performs deletes: drop the token, or put the stack down and stand it up in state
zero. Tree-sitter also *inserts*, materialising the token the grammar wanted at
zero width and reporting it `MISSING`. A scar never reports an insertion because
`mended()` never makes one. That is now a visible gap with a named owner rather
than an invisible one.

**The row that is ours and not the corpus's**: twelve grammars where we repaired
and the oracle derived clean - c, cpp, ruby, bash, haskell, julia, kotlin,
markdown, ocaml, scala, swift, zig - **1,929 scars over 2,169 B of files
tree-sitter found nothing wrong with**. Before `--scars` the only sign of it
anywhere was a `mended N` count on a verdict line with no location attached. A
repair surface that only ever reports the input's faults cannot find its owner's;
this one found 1,929 of them on the first run.

Outliner has always been described as beating tree-sitter and nothing measured
whether it does. `tool/collate.py` and `research/collate/` are the scoreboard:
thirty grammars, against tree-sitter 0.26.11 generated from the same
`grammar.json` the press reads, every difference labelled gap, improvement or
neutral, and an improvement required to say what a consumer can now do
correctly.

The wins are size and build. The folio is 0.34x the dylib at the median across
28 of 28 measurable grammars - 14.3 MB against 75.6 MB - and 22 of those
grammars ship a hand-written external scanner totalling 486,301 bytes of C that
must be compiled per grammar, where no folio needs a compiler at all. Minting is
19.6x faster than `tree-sitter generate` plus the C compile, 8.6s against 212.1s
for the slate. Inside tree-sitter's root `ERROR` on `picorv32.v`, eight
hand-adjudicated spans read correctly where tree-sitter has no node: the second
module's header, its parameter port list, its ports, a task declaration, a
`define body that stops at the newline instead of swallowing the following
`endif`, and 610 bytes of keyword that tree-sitter's recovery lexes as
identifiers.

The losses are worse than the wins are good, and one of them is a category
rather than a ratio. Cold parse is 2.9x slower at the median and latex is 31.7x.
The keystroke is 5.6x slower at the median, but the number that matters is the
gain over re-opening the file: tree-sitter's is 8x and **outliner's is 1x**, so
on 17 of 29 grammars typing one character costs what opening the file costs -
30,740 microseconds per keystroke on a 28 KB Swift file against tree-sitter's
73. php is the one row that beats it, 138 microseconds at a 65x gain, which
proves the machinery works and the rest is a re-mint policy. Outliner's tree
also cannot mark its own misreadings at all: misread bytes lie inside `built`,
`damage` is everything outside `built`, so flag recall is 0.00 as an identity.
php misreads 25,338 bytes, flags none of them, and reports 87.2% standing.

Three predictions of sixteen failed and each carried a finding. tree-sitter
`ERROR`s on two files of thirty rather than the five predicted, so the inherited
"34,687 candidate bytes" is 30,959 and 99.4% of it is one file. The hand
adjudication came out better than predicted by count (8 of 14) and worse by
bytes (49.3%), because the two widest disputed spans are ones where both parsers
are confidently wrong - both call a module instantiation a class type. And no
grammar has a bigger folio than its dylib, though the prediction's reason held:
the per-grammar ratio omits a fixed cost, and adding it back makes tree-sitter
smaller at one language, with the crossover at two.

Two instruments lied in the flattering direction and both were caught on their
first numeric run, which is what the predictions existed for. The first speed
harness timed a process over the real file against one over an empty file and
subtracted, and reported go at 400x faster than tree-sitter on a machine where
tree-sitter's own clock says it parses 4 MB/s; both terms were process-start
jitter and the sign of the noise picked the winner. The replacement takes a
slope over repeated paths on our side and reads `--stat` on theirs, because the
same slope over tree-sitter's CLI reads 219 ms for a 5 KB file - it re-resolves
the language per path. The second is this lane's own byte comparison: over the
1,188-byte module instantiation that both parsers call a class type, it scores
57.7% agreement and 0% disagreement, because a deepest-node comparison inside a
recovery region measures two lexers rather than two trees. A third was caught
before it printed anything: `outliner grammar`'s "cannot be lexed here" note
lists all 33 of swift's externals while 22 are in fact seated, so reading it as
a seating census would have reported zero seated everywhere.

Correctness claims are tracked rather than written down. Each is a span in
`research/collate/verdicts.toml` carrying what both trees said; `collate.py
adjudicated` re-derives both from the live binary and the live oracle, excludes
any drifted row from every total and exits 1. `collate.py prove` corrupts a
verdict in memory and requires the drift check to catch it, seven checks, each
watched failing before it was trusted passing.

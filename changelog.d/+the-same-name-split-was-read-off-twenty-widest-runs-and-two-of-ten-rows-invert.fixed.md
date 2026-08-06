The corpus's racked bytes were split in two by asking whether our node's name
matches the oracle's — swift/ruby/kotlin at 100% same-name (an extent slip),
elixir/verilog/ocaml/sql/julia at 0% (a different parent). That was read off
`rack.py show`'s `worst` list, which prints the **twenty widest runs of each
kind**, and a three-byte extent gap is a small run by construction.

Asked over **every** run instead, two of the ten rows invert: **elixir 0% →
37.6%** and **scala 5% → 86.1%**, a seventeen-fold error and the largest row the
split misclassifies. The mechanism is not noise — it is a byte-weighted sample
being read as a run-weighted statistic. Where a grammar's crooked *bytes*
concentrate in a few enormous different-name runs and its crooked *count* in
many small same-name ones, sorting by width and taking twenty returns only the
first population. Swift and ruby are immune because their bytes and their counts
agree.

Restated as a claim about **bytes** it survives intact — elixir 8.9% same-name,
verilog/ocaml/sql/julia 0.0%, swift 99.6%, ruby 100.0% — and it draws the same
grouping, so the implied-statement-terminator reading is undamaged. But
"elixir's crooked bytes are 0% same-name" was being repeated as a fact about
elixir's runs, and 53 of its 141 racked runs are `arguments` under `arguments`.

The complement is worth more than the correction: **every same-name run carries
`Run.edge` and no different-name run does**, in elixir and in the corpus at
large. `edge` is `rack`'s own flag for *same start, different end*, so the two
classifications are the same classification and the split needs no new
instrument at all — it is already there, per run, for free. Elixir's same-name
runs are not a second defect; they are the left edge of the same `do_block`
construct, and repairing the 20,126 different-name bytes takes the 1,963
same-name ones with it.

`research/joinery/elixir/every.py` is how that was found, reusing `rack.bucket`
and `rack.widest` rather than re-deriving either, so it can only disagree with
`rack` about which runs get printed. Written up in
`research/joinery/elixir/RESULT-1-split.md`.

`customary check swift` asks about 43 files instead of printing `no files for swift`. It
found two real disagreements on the first run, which is the point.

The suffix table had no `.swift` row, so `corpus_for` returned nothing, so the checker
exited having compared zero answers. It did not say so as a failure. A grammar with a
book, a cohort of five, and no corpus reads the same on the page as a grammar that agreed
about everything, and swift had been sitting in the second column while belonging in
neither.

This is the shape worth naming, because the same silence is still standing for three
others: scala's and haskell's cohorts are hidden terminals, which wear no name in the
tree, so `oracle_leaves` filters them out and the differential compares zero answers and
reports `held`. yaml has no oracle installed here at all and says `oracle unavailable`,
then totals zero and reports `held` too. Those books are gated by the board (whole, one
root, a sound survey over every node) and not by this tool, and the distinction between
"agreed" and "never asked" should be legible on the page rather than reconstructed from a
count of zero.

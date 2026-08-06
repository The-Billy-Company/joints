Nobody had the number that bounds what a binary fork can ever recover.
`research/joinery/arity/arity.py` is it: per grammar, how many contested cells
drop more than one reading, and how many readings those cells hold.

    5,614 of 85,786 contested cells (6.54%) drop more than one reading,
    and carry 7,584 reading(s) a binary fork could not.

Twelve of thirty grammars have any. Verilog holds 5,241 of the cells and 7,199 of
the readings — 93% and 95% — which makes every other row a rounding error and
verilog the only grammar where cell arity is a *structural* fact rather than a
handful of sites. C++ has 27, all of them exactly ternary, and that is the whole
of its worst-row-on-the-board defect. PHP is the only grammar whose cells go
*deeper* than one extra reading in bulk: 8 cells at three readings dropped and 2
at four, in 172 conflicts.

The distribution is the point. `1:3891 2:935 3:311 4:15 5:89` for verilog says the
tail is real but thin, and a fork widened to carry three readings recovers most of
what a fork widened to carry nine would.

It reads the folio directly rather than asking the binary, because every
instrument that reports a table's shape reports it after a parse has spent it.
`mint` already prints the `rival` section's size, which counts *readings*; only
the folio says how those readings distribute over cells, and one cell holding
three losers and three cells holding one are the same number there and different
facts. Section ordinals are read off the directory by name and `Kind` is parsed
out of `leaf.zig`, so appending a section upstream cannot silently shift what this
is reading.

It closes with a check rather than a number: a column keeps `column.spares_max`
spares, so it can report at most `spares_max + 1` dropped readings, and a corpus
that reaches that number is one this survey can no longer measure — every wider
cell would come back wearing the ceiling's value and the total would be a floor.
The check fails there instead of printing it.

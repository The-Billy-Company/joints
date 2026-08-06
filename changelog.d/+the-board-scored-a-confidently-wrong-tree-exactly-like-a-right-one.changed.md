`standing` is `built / size`, and `built` means *placed under a root that has at
least one child*. It has never meant *placed correctly*. So the board's headline
counted 60,138 bytes of wrong structure as success, and no column on it could
see one of them: misread bytes live inside `built`, and `damage` is everything
outside `built`, so the two load-bearing numbers were structurally incapable of
pointing at a region the parser built confidently and wrongly.

`tool/standing.py` now consumes `tool/rack.py`'s derivation comparison against
tree-sitter 0.26.11 and splits `built` four ways — `square + crooked + soft +
unaudited`, asserted to total `built` on every audited row. The headline reads:

    was  73.0% standing   built / size
    now  50.4% trued      square / size, bytes whose derivation the oracle defends
         61.6% at most    everything not proven wrong

Both are printed, on the same line, old first. **The 22.6-point fall is a
correction, not a regression** — no parse changed, and those bytes were always
wrong. Do not subtract it from the 69.09% quoted in older reports; that number
is from a generation before another lane mended seventeen grammars, and
`standing` went *up* over the same window `trued` was not being measured. Both
numbers above come from one run of one binary.

Three new columns (`trued`, `crooked`, `graded`), a `--crooked` sort order that
is now the default, and an `--audit` sweep writing `.local/standing/audit.json`.
Nothing was removed; `standing`, `covered`, `built`, `orphan`, `rubble`, `spoil`
and `damage` all read exactly what they read before. A board run with no cache
still runs — the audited columns read `—`.

Where it goes the wrong way. The board now depends on a cached file it did not
compute, on an oracle that is unavailable at runtime, and on 27 of 30 rows.
verilog and sql get no verdict at all (34,687 bytes) because tree-sitter's own
parse of them has errors in it; they read `graded=none`, and they are the reason
the headline is a floor and a ceiling rather than a number. 23,031 further
crooked bytes are extras placement and are **not** charged — where a comment
hangs is a parser's choice. The defended figure is 60,138, never 83,169.

The finding that surprised me most is not the drop. It is that `crooked` exceeds
`damage` on eight rows — php 25,394 vs 8,699, elixir 17,660 vs 1,559 — so
`--damage`, the work order every lane has used all day, was ranking those rows
by the smaller of their two defects. elixir sat 11th at 96.6% standing while
holding the second-largest pile of wrong structure in the corpus.

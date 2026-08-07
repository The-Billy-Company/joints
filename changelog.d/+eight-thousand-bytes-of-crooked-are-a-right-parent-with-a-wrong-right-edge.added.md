Added `research/joinery/tenon/extent.py`, which re-sorts `rack`'s crooked bytes
into `span` — every rung agreeing on name, order and left edge, with some rung's
right edge moved — and `shape`, a parent genuinely in dispute. It changes no
total: it calls `rack`'s own `survey` functions by name over the same windows,
and its `crooked` column equals `rack`'s row for row on all 27 adjudicable
grammars.

`rack`'s spine rung is `(name, named, start, end)` and two rungs differing in
any of the four part the spines. Three of those four are derivation and the
fourth is not, so a parent that adopts the right child and stops short of it is
charged as a misread parent for every byte underneath. **8,334 of 83,169 crooked
bytes (10.0%) are that.** toml is 62% span, latex 96%, zig 80%, swift 41%.
`rack soft` structurally cannot catch it, and its own docstring says why: the
charged bytes are not the extra's, they are the siblings'.

Correcting the headline: `rack` defends 60,138 bytes after subtracting extras
placement, and **7,699 of those (12.8%) are a right parent whose right edge
moved**. The defensible figure is 52,439 bytes — 13.63% of `built`, 15.0% of the
349,928 adjudicable bytes, 10.0% of corpus. 34,687 bytes over verilog and sql
still have no oracle verdict at all.

Where it goes the wrong way: the first cut of this file was itself wrong in the
flattering direction and shipped a summary line claiming 38,636. `rack soft`
asks its question per merged run; the first cut asked per cut, so every space
inside a 1,815-byte racked run counted soft and elixir read 4,879 soft where
`rack soft` reads 74 — 66× too soft on the largest row on the board, with the
one assertion I had built (`crooked` must match) passing the whole time. Runs
are now accumulated on `survey`'s own key with the span/shape class appended, and
the soft total is 23,050 against `rack soft`'s 23,031.

The instrument that lied, and it is still lying: `rack` stamps fourteen fields
and all fourteen are about joints — binary, tree, commit, dirty, drift. The
oracle is half of every number it prints and is **unattributed**: no tree-sitter
version, no grammar revision, no dylib hash, no seat. Three oracle libraries
under `.local/differential/` were rebuilt by other lanes mid-session while this
lane measured, and scala's crooked count read 1,278 in one run and 9,087 in the
next from the same pinned binary and the same unedited script, with the stamp
byte-identical across both.

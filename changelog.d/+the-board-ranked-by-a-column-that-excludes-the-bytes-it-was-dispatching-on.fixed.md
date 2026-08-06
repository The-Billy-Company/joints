The board ranked the corpus by `unbound = rubble + spoil`, which excludes
`orphan`. The exclusion is defensible as a *definition* - an orphan byte is a
declared extra that got demoted, not an unparsed byte - and catastrophic as a
**work order**, because an orphan byte is still a byte the tree failed to place,
and orphans are produced *by* walls rather than instead of them. So the board
printed one number as the headline and a different, smaller one as the priority,
and they disagreed about who was worst by seven places.

`damage = size - built = orphan + rubble + spoil` is now a column and a sort.
It **redefines nothing**: it is a rollup of three of the four buckets, not a
fifth bucket, and `damage / size` is exactly `1 - standing` to the eighth digit.
`unbound` keeps meaning `rubble + spoil` and `standing` keeps reading 67.37%,
because a headline that silently redefines itself is the same crime one bucket
lower. Everything `damage` says, `standing` was already saying as a share -
nobody had spelled it in bytes, so nobody could sort by it.

Measured 2026-08-05 over the thirty, pinned binary `kdocA`. Ranking by `damage`
instead of `unbound` moves scala **15 -> 8**, kotlin **8 -> 3**, php **10 -> 6**,
zig **16 -> 13**, and demotes elixir **7 -> 12** and markdown **5 -> 9**. scala
is the exhibit: **104 bytes of `unbound` standing in front of 4,150 bytes of
damage, a 40x flattery**, on a grammar no work order would ever have reached.

Where it goes the wrong way: the re-ranking **wins nothing**. The corpus is
exactly as damaged as it was this morning and the headline says so; all this
buys is that effort goes to kotlin's 20,974 bytes instead of past them. And at
the very top the new order barely differs from the board's default `standing`
sort - four of five shared, where a prediction written first said at most two.
The default view was never the broken half. `unbound`, the column the dispatches
came off, was.

`most` names what the damage is made of - the bucket holding more than half, or
`mixed` when none does - and it is arithmetic on three columns, never a reading
of the verdict, because `inquest`'s stand-in name is a guess that has been wrong
twice and a family computed from a guessed name manufactures families. It
refuses a plurality that is not one: haskell is 36/32/32 and reads `mixed`.
Grouped, it prints the pattern a lane had to find by hand - the four widest
`orphan` rows are kotlin, php, swift and scala, all four stopped on a blind
external, 37,575 orphan bytes across the seven such rows. **No grammar in thirty
has `rubble` as the plurality of its damage**, so `--rubble` sorts by a bucket
that is nobody's, and the tally prints that empty group rather than omitting it.

Three instruments lied on the way here, and two are still lying.

`stamp.ask().mends` reads **0 on all 17 rows that mend** - kotlin 142, verilog
2,109, php 1 all come back zero - because `verdict()` takes the last non-blank
stderr line and a walled grammar's last line is `inquest`'s, not the stop line
carrying `mended` and `roots`. `BLIND` and `UNSOUND` search the whole stderr and
stay correct, so the field is right on every quiet row and wrong on every
interesting one. `tool/walls.py`'s `voice` divides by it and reads **0.0 for
every walled grammar** - every tail all depth, no repetition, the exact
inversion. `tool/stamp.py` is another lane's today; the fix is one line. The
board consequently states the gate in `roots` and `leaves`, off the same tree as
`built`, and prints no mend count at all.

And one lie was this change's own. The check reporting how far a `roots` ranking
moves a grammar printed **10 places under the default sort and 9 under
`--damage`** - a stable sort inheriting the display order as its tiebreak, so
the check was reading its own presentation back as a fact about the corpus. Both
checks now break ties on the name and print 10 under every sort. No test caught
it; two terminal outputs side by side did.

`damage` is also exactly as corruptible as the `built` it is made of, which was
predicted and then measured rather than assumed. On `picorv32.v`, `--mend=keep`
against `fell` moves `damage` 63,937 -> 38,480 and `standing` 32.5% -> 59.3%
while `describes` falls 22,222 -> 12,672 nodes: **25,457 bytes of work order
bought by describing 43% less.** Every guard on the board except one clears it -
`covered` rises, `spoil` falls, `rubble` collapses 14,057 -> 8, bare leaves fall
2,481 -> 48. **Only `describes` catches it**, so sorting by `--damage` prints
that measurement beside the order it produced.

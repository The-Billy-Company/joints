# `reach` is a watermark, and a watermark cannot see a hole

Handoff to the bench lane, which owns the board and the `reach` column.
**Nothing here edits the report.** The raw measurement is checked in beside this
file as `reach-audit.json`, thirty grammars measured twice - once with the
shipped naming and once with the naming it replaced.

## The question, and why the answer is not the one that was asked for

The rename survey closed with a sentence worth checking rather than quoting:
*an absorbed wide token puts a node over its whole span, so the widest
misreading earned the most coverage.* If that were the mechanism, the inflation
would live in the tokens `Gather.blame` mints and the fix would already have
removed it.

It is not the mechanism. Measured over the corpus, under the old naming
**zero** blame-minted tokens were absorbed anywhere - 16,468 of them were
minted and every one was refused. That is not an accident of the corpus, it is
what `blame` is for: a token is minted there precisely because no live state
had a cell for anything, so it goes on to be refused through the ordinary path
and `mended` steps past `tok.end()`.

So the wide naming did not put nodes over 177,460 bytes. It **deleted** them,
which is worse, and the reported number went *up* anyway. That is the finding.

## Why the number went up while the file was being deleted

`reach` is `tool/stamp.furthest`: the largest end offset of any root. It is a
watermark, and `covered` is that watermark over the file size. Neither notices
that the forest between offset 0 and the watermark is mostly holes.

A mend leaves a hole by design - the bytes under no root are the bytes no
reading could place - so on any grammar that mends, `covered` answers a
question nobody asked. The honest measure is the union of the root spans:

| grammar | size | old naming: reach / under a root | shipped: reach / under a root |
|---|---:|---|---|
| swift | 28,468 | **100.0% / 6.5%** | 100.0% / 49.9% |
| julia | 27,360 | **100.0% / 11.2%** | 89.2% / 19.7% |
| verilog | 94,657 | **100.0% / 15.1%** | 100.0% / 50.4% |
| scala | 20,107 | **100.0% / 17.6%** | 100.0% / 76.0% |
| haskell | 34,240 | **100.0% / 23.8%** | 73.5% / 18.3% |
| ruby | 1,020 | 100.0% / 34.4% | 100.0% / 85.5% |
| go | 1,189 | 100.0% / 45.8% | 99.9% / 59.9% |
| ocaml | 16,878 | 100.0% / 48.2% | 100.0% / 93.1% |
| elixir | 46,089 | 100.0% / 73.8% | 100.0% / 74.0% |
| php | 67,845 | 100.0% / 74.5% | 100.0% / 78.9% |
| kotlin | 35,815 | 100.0% / 90.0% | 100.0% / 91.5% |

Eleven grammars report 100% while a tenth to three quarters of the file is
under no root at all. **Swift's headline number was 100% over a file the parse
had placed 6.5% of.** Nine grammars are honest because they never mend, and
those rows are unaffected either way: java, javascript, typescript, rust, json,
css, embedded-template, html, lua, toml all read 100% and cover 100%.

## The fix recovers real source, not just the names

Because the deletion was the wide token's span, naming the byte with the
shortest reading gives most of the file back:

| grammar | bytes stepped past, old | shipped | change in bytes under a root |
|---|---:|---:|---|
| scala | 15,657 (77.9%) | 502 (2.5%) | 3,534 -> **15,285** |
| ocaml | 8,500 (50.4%) | 509 (3.0%) | 8,135 -> **15,714** |
| verilog | 62,866 (66.4%) | 1,858 (2.0%) | 14,248 -> **47,661** |
| swift | 26,473 (93.0%) | 11,434 (40.2%) | 1,857 -> **14,208** |
| ruby | 664 (65.1%) | 29 (2.8%) | 351 -> **872** |
| go | 626 (52.6%) | 9 (0.8%) | 544 -> **712** |
| php | 2,995 (4.4%) | 1 (0.0%) | 50,517 -> **53,511** |

Total bytes stepped past across the corpus falls **177,460 -> 48,386**, and
47,858 of the 48,386 are single-byte steps.

## The one row that got worse, and why it is a unit rather than a regression

**haskell** is the only grammar whose reach fell: 100.0% -> 73.5%, and its
bytes under a root fell with it. It is the only grammar that hit the mend cap.

The cap is `ceiling` in `src/kernel/quire/gather.zig`, read once in
`Gather.mended` as `x.mends >= ceiling`. It counts *attempts*, which stood in
for damage only while every attempt ate about the same amount. Once a mend
deletes a byte where it used to delete a kilobyte, the same repair work costs
sixty times the budget: haskell steps past **16,514 bytes** in 16,073 mends off
a refused token, where the old naming stepped past **33,337 bytes** in a total
of 4,940 mends. Twice the damage, a quarter of the budget, and only the cheaper
one was cut off.

The count cap is also not load-bearing as a fuse. `mended`'s own docstring
states the invariant that makes it redundant - *`over` is the first byte after
whatever is being stepped past, and it is always past `x.at`, so a file cannot
be mended forever* - which bounds the mend count at the file length already.
What the fuse is actually for, per the same docstring, is *a byte-by-byte walk
through a megabyte of the wrong language*, and that case is not "many mends",
it is "the file was skipped".

So denominate it in bytes stepped past, as a share of the file: accumulate
`over - x.at` in `mended`, gate on that against the length `run` was handed,
and keep `x.mends` as the reported statistic it already is. Calibrated against
this corpus the way `crowd` and `skeins` are - above the high-water mark rather
than at it - the shipped naming's worst rows are julia 59.3%, haskell 48.2% and
swift 40.2%, with every other grammar at or under 4.3%. The wrong-language case
approaches 100%. A fuse at three quarters of the file separates those cleanly
and lets every row here finish.

**Not done here.** `gather.zig` is a file the weave lane is mid-change in, and
a second uncommitted edit in it is how a real fix disappears. The change is two
lines and a field; it belongs to whoever owns quire next.

## Two rows that are not about naming at all

- **markdown** reports 100% and covers **17.2%** in both regimes, on 79 mends.
  Nothing here explains that one; it is a grammar-shaped finding for whoever
  owns markdown.
- **yaml** is 0/0 in both, which is the known all-external limit case.

## What to quote instead

Two numbers, not one, on any grammar that mends: the watermark and the union.
`under / size` is the one that answers "did we read the file". A row quoting
only `covered` on a mending grammar is quoting a watermark, and the eleven rows
above are how far apart the two can be.

Reproduce with `reach-audit.json`, or re-measure: the instrument is a probe on
`Gather`'s absorb path recording every token `blame` minted and whether it was
absorbed or refused, plus the union of the top-level spans in `--ranges --all`.
It lived in a throwaway worktree and was never committed, for the same reason
the survey did not edit the board.

## The fourth instrument bias, and the first one that was not found by accident

The other three tonight - the peel stepping `reach` rather than `at`, the 58
state-0 restarts, and the blame-minted terminal names - were each found by
asking whether the instrument or the thing was at fault. This one was found by
checking a sentence in the writeup of the third, and it turned out the sentence
was wrong about the mechanism while being right that the number was flattered.

Worth keeping: **the claim survived because it was directionally right.** A
plausible mechanism for a real effect is the hardest kind of wrong thing to
catch, and the only reason it was caught is that it was cheap to measure and
somebody measured it instead of quoting it.

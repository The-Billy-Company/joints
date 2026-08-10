`hand/lineage.zig` is gone - 505 lines of html element ancestry, the first
hand-written scanner a customary has replaced outright. With it: html's two
`outside.troupes` rows, the `.lineage` kind, `marrow`'s `html_comment` vein, the
`Carry.tags` stack, and the four step functions that drove them. `outside.zig`
goes 3004 → 2821 lines.

It could go because `customary/html.json` claims all eight of html's externals
and the books now ship in the binary. Both halves matter and the second is the
one that was missing: while a book needed a path typed, an html document could be
reached with no book, so the hand was reachable and the transcription bought
nothing it could be deleted for.

Proof it is behaviour-preserving, not a regression traded for line count:
`viewer.html` at 72,288 bytes parses to **13,972 nodes, 1 root, accepted** with
no environment set - the tree-sitter oracle's exact node count, and the
differential reports *no differences at all*. The nine-byte
`erroneous-end-tag.html` specimen still produces the three roots and the
identical leaves at identical extents its `.expect` file documents, including
`erroneous_end_tag_name` at [6, 7). That specimen's known defect (a missing
`element` parent) is a tree-building shortfall and was never the scanner's; it is
unchanged, neither fixed nor worsened.

Dead by the same stroke, and removed rather than left standing: the `stray`,
`implied` and singular `shut` parts of `Troupe` and `Cast`, plus their
`provision`, `seated` and `claimed` plumbing. html was the only grammar that ever
set them and the two deleted functions were their only readers. `Carry.shape`
loses the tag depth it packed into its low sixteen bits - those closes are the
customary's marks now and fold in through `Organs.shape` - and the bits stay free
rather than being reclaimed, so the two remaining stacks keep the exact bits they
had.

**The other six hands stay, and the measurement says why.** 22 of 30 grammars
have no book at all, and a book covering part of a grammar retires nothing:
haskell has one and still answers 18 layout terminals by hand, because its book
claims eight terminals and none of them is `_cmd_layout_*`. `writ.zig` is
haskell's alone and is still load-bearing for exactly that reason. Retirement is
mechanical from here - a hand goes when nothing can reach an offset without the
book that supersedes it - but it is earned per grammar, not declared.

`joints lex` now names the terminals in each roster instead of counting two of
them, which is how the above was measured: "2 by hand" is a number nobody can
act on, and *which* two is the difference between reading a hand and reading a
rule.

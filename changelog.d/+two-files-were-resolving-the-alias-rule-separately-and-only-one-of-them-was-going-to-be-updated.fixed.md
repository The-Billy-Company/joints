`Quire.name` and `Sheet.name` each resolved alias-vs-symbol against the grammar
themselves. Same for `isNamed`, same for `field`. Two spellings of one rule, in
two files, and the rule is not obvious: a renamed kind reads its name and its
namedness out of `gr.aliases[index]` while an ordinary one reads `gr.nameOf` and
`gr.shapeOf`, so getting it wrong in one place gives you a tree that is
structurally right and spelled wrong, which is worthless to every
`highlights.scm` in the world.

The vellum lane filed this rather than fixed it, because quire was not its to
edit. Three free functions now - `quire.nameOf`, `quire.named`,
`quire.fieldName`, all `(grammar, kind)` - and both types forward.

It cost nothing, which is what makes it worth doing rather than a trade to weigh:
`bench/rungs/cursor`'s `lift` section spells a `name`+`isNamed` pair the old
inline way against the forwarded way and reads 1.00x, 1.00x, 1.03x, 0.99x on the
four slate files. They inline as the two lines they replaced did.
(`repo f3d3b84bc+21`, M-series laptop, a sibling lane compiling, min-of-7.)

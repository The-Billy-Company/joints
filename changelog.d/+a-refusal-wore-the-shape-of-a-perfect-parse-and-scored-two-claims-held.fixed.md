`specimen.py`'s `stop()` read roots and mends off the binary's own stop line
and defaulted a missing line to **one root and no mends** - which is exactly
what a perfect parse looks like. So a grammar the binary refuses to lex scored
`roots 1` and `mends 0` as claims HELD.

yaml is the case. `outliner parse upstream/grammars/yaml.json` exits 2 with
`yaml has no lexable terminal at all` - the grammar is 113 externals and zero
literals, so there is nothing for a lexer to be built out of - and
`yaml/comment.yml` reported **2 of 4 held against a binary that had not read a
byte of it.** The two that held were the structural claims, the ones a specimen
author is least likely to re-derive by hand, so the failure mode was silent in
the direction a reader would trust.

A refusal is now its own outcome. `stop()` returns the refusal text as a third
field, `judge` fails every claim in the specimen named with it, and `run`
prints `REFUSED` rather than `FAIL` so a grammar that was never parsed is not
read as one that parsed wrongly. yaml/comment.yml went 2 of 4 to 0 of 4
refused; nothing else in the tier moved.

The first version of the condition was too strong and was live for one run:
treating any nonzero exit as a refusal swept up seven honest parses that mend,
truncate or return many roots. A parse that mends is still a parse. The test is
now "the binary named no root count at all", which is the thing that actually
distinguishes no-tree from a bad tree.

`specimen.py verify` gained a sixth assertion that performs this rather than
asserting it. It finds a grammar the binary refuses, judges a probe asserting
`roots 1` and `mends 0` against it - those two precisely, because they are the
pair a defaulted read makes true for free - and requires zero held. If no
grammar refuses anything it reports that it proved nothing, rather than
passing. 6 of 6 assertions hold as of tree `fa7fcaee5`.

This is the thirtieth instrument in this tree caught reporting a number a
report then repeated, and it was in the tier written to catch that.

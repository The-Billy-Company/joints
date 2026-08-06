Three lanes measured three different populations and read them as one dispute
about whether this machine holds several tree-sitter parsers. It does not.

| who | population | measured |
|---|---|---|
| the board lane | `upstream/grammars/*.json` vs the live `lang/*/src/grammar.json` | byte-identical |
| `attest.verify` | compiled `.dylib` across `seat/*/lib/` **and** the legacy `lib/` | 28 of 29 have ≥2 distinct files; css 62.3% apart |
| the holdout lane | oracle *source trees* under every `…/lang/<name>/` | 14 of 27 corpus rows have ≥2 |

All three are correct about what they looked at. Across **159 source trees over
30 grammars**, zero authored oracle sources diverge.

**The 62.3% library is inert.** `attest.verify` lists `[every seat] + [WORK]`
and compares the first against the last, so its worst pair is one current seat
against `.local/differential/lib/` — the pre-seat library directory, last
written 2026-08-04, that nothing writes to since `TREE_SITTER_LIBDIR` went
per-lane. Planted as a scratch seat's library and asked one question, that exact
orphan (`05ec353b4c86`) came back as `a01e997efe11`: **rebuilt before it could
answer**, landing 53 of 151,080 bytes from its seat's own — the Mach-O build id,
the same 0.03% two fresh seats differ by. The CLI's staleness criterion, which
is `attest`'s own fourth claim, fires first every time.

**The divergent source tree converges on use.** Two real fork trees with two
different `attest` identities, audited one after the other, returned identical
values in all 14 columns and 794 oracle nodes each — because measuring the first
regenerated its `parser.c` and its identity became the second's. The two oracles
became one by being asked.

So `attest.verify`'s third row should stop reading *"the tree really is holding
two oracles at once."* The number is right; the tree is holding one oracle and
one file the next question overwrites.

**Recommended, and deliberately not done here**: take `parser.c` and
`tree_sitter/*.h` out of `attest.survey`'s digest and leave them in its mtime.
They are outputs of `tree-sitter generate` over inputs the digest already
covers, so they add no identity and subtract stability — their presence is a
cache state that any measurement creates and any scanner refresh used to
destroy. Measured, that collapses css's and toml's two identities to one and
leaves the other 28 grammars bit-for-bit unchanged. The mtime side should keep
them: *"is the library older than what it was built from"* is a different
question and wants the whole tree.

The board keeps keying its oracle guard on `attest`'s digest exactly as it
stands, because a second definition of "which oracle" is how this project ended
up calling both 9,087 and 1,938 *crooked*. Its failure direction is the safe
one — it refuses a valid verdict and costs a re-audit rather than accepting an
invalid one — and the window that made it fire spuriously was a scanner refresh
deleting a `parser.c` between an audit and a read, which is now closed.

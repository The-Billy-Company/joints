A category called `stranded` held 22,179 bytes of work. 116 of them stand.

`tool/walls.py`'s cold peel hands the parser `text[cut:]` after each wall, so every
round past the first parses a fragment whose openers it left behind, and every
`}` in it is refused correctly and priced as damage. `Wall.real` excluded `state
0`, which caught the fragment that refuses its own first token and missed the
same fragment with one statement in front of it -
`research/joinery/strand/witness/sw-cut-*.swift` reproduces one orphan closer at
states 0, 681 and **1166**, because a state number is a count of the statements
before it. No predicate over state numbers can separate those, so the peel now
carries `Priced.turn` - the earliest round that met a wall - and `Wall.real` reads
provenance instead of arithmetic. The rule had a second copy in `owners.py`
(`w.endswith(" in state 0")`) and only one of the two had ever been fixed; both are
gone, and `research/joinery/owners/cut.py` is now the only place the taxonomy is
decided.

The clearing evidence was a warm peel that never restarts, and **it was
manufacturing walls of its own.** Three parses of `Chunked.swift` under one pinned
binary: as written it refuses `)` at 1492; blank that `)` and it refuses `}` at
1498 in the same state 141, with the same 308 roots and the same reach; blank the
`}` alone and the wall is back at 1492. So `}` at 1498 is not a wall in the file -
it is the 1492 refusal re-reported against the next token, and warm's first six
blanks are six of those. **1,812 of 1,983 priced warm rounds bought the parse
nothing** - 91.4%, and 98.5% on verilog. `Warm.bought` asks each round whether
blanking closed a root or read a byte the parse could not before, both numbers
already on the parse it was doing, and `cut.stand` splits a byte-join match into
`witnessed` (paid) and `alias` (barren). The `witnessed` population fell from
15,527 B to **at most 2 B** - two one-byte walls on scala and zig, which a second
warm run under the same pin calls `alias` while agreeing on every other byte in
the table. So the warm peel contributes nothing dependable to the standing side,
and the canopy carries it.

The board, re-priced over all thirty grammars: of 120,832 priced bytes,
**4,751 B (3.9%) stands**, 97,935 B (81.1%) is one of the two instruments, and
18,146 B (15.0%) is `untested` - past the furthest byte any warm round reached.
`stranded` alone: 116 B stands, 39.9% demonstrably instrument, **59.6% untested**.

The inherited headline was 96.3% on two grammars, and it could only get stronger:
folding "warm never reached this byte" into "warm cleared this byte" means a run
that stalls earlier acquits more. Widened to thirty with the frontier carved out,
the claim is **weaker**, and the number that grew is the one admitting what nobody
can say. The 13,056 B sold as construct damage is swift's `} in state 681` and
`} in state 1166`; both stand past byte 10,989 and swift's warm run reached 2,904
of 28,467, so they re-price to `untested` rather than to zero.

Verilog's 63,937 B damage figure does not move by one byte - `standing.py` measures
it off a single whole-file parse and `behind` is a peel partition, so 6,591 peel
bytes were never inside it. What moves is verilog's peel worklist: 11,070 B to
**21 B**. Its eight `_identifier` walls no longer exist on this tree at all; a
lexer fix renamed them, and the three `macro_text` walls that replaced them total
**6,477 B** - exactly the sub-figure the strand lane measured as the `macro_text`
share of 6,591, corroborated to the byte by an independent run, and every byte of
it `alias` or `torn`.

Measured under one pinned binary with separate `OUTLINER_WORK` for the two arms;
predictions and scores in `research/joinery/reprice/`, eight of eleven, and the
miss that mattered was the join I had built and would have published before
asking what it was matching.

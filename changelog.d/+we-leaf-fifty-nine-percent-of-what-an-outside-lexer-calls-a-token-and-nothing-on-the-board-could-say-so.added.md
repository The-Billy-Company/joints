Every column on the board is computed from our own forest. `standing` and
`damage` read top-level root spans; `square` reads agreement with an oracle that
had gone blind over the whole of `picorv32.v`; `spoil` reads whether a byte was
reached. **Not one of them can see a token nobody stood on**, which is why
verilog spent the project at 32.5% standing without anybody being able to say
what fraction of the file we actually lex.

An outside lexer can. `verible-verilog-syntax --printrawtokens` hands back every
token's byte range and needs no parse tree to agree with. Against it:

```text
                     token bytes leafed   share
outliner                        44,018   59.3%
tree-sitter                     73,357   98.8%
verible names                   74,194
```

Our leaf set is a strict **subset** of tree-sitter's — zero bytes we leaf that
they do not — so there is no divergence here to defend as an improvement.

**Where the 30,127 missing bytes are is not where the tag histogram points.**
590 of them are inside a node we built with no leaf on them. **29,537 are under
no node of ours at all**, and recovery stepped over 31,792 bytes in 1,981 mends
— 108% of that, since some bytes are stepped over twice. The deficit *is* the
mend trail, and it is shaped like one: 4,693 contiguous runs, **median two
bytes**, widest forty-five in a 94 KB file. Nothing is missing in a block.

By Verible's own tags the top row is plain `SymbolIdentifier` at 17,345 bytes,
misses are spread across 49 of 72 tags, and twenty-three tags — both comment
shapes, every declaration keyword — are leafed to the byte. There is no lexical
category we cannot stand on. The histogram is a photograph of where recovery
landed.

**The externals are not starved; verilog declares none.** `398 literal, 46
regex, 0 external`. Haskell's win came from seating a declared-but-unseated
layout protocol; verilog has no protocol to seat, and six of the twenty grammars
in the differential checkout are in the same position. What verilog has instead
is **181 declared conflicts**, the most on the board, and 18,710 contested cells
the author explicitly asked to be forked.

**And the ranking of verilog's two defects inverts once you leave the one file
the whole grammar's reputation rests on.** Three further real sources, measured
the same way:

```text
                      as written   lone selects parenthesised   first wall
picorv32.v    94,657      59.3%              59.7%   (+0.4)     ` in 3438
picosoc.v      6,891      92.2%              92.2%   (+0.0)     macro_text in 176
simpleuart.v   3,563      86.7%             100.0%  (+13.3)     ; in 701
spimemio.v    13,474      95.0%             100.0%   (+5.0)     ; in 701
```

`{a[3]}` — a concatenation element that is exactly one selected identifier — is
the wall in **state 701 on two independent files** and, parenthesised away,
accounts for **their entire deficit**. The folder's record prices the directive
defect at 21,535 bytes and the concatenation defect at 19,928, both read off
`picorv32.v`; on a leaf yardstick and outside that file the directive half is
worth +6.0 points and **nothing at all elsewhere** — 119 directive lines in one
formally-verified core — while the concatenation half is general verilog.

It has a 56-byte witness, and `OUTLINER_TRACE=quire` over it is three lines
long. The cell that chooses is not the one the earlier chapters hunted in 1701
and 1184:

```text
split: state 2979 on ] at 729 rank 0 - keeps fold constant_primary #4021,
                                       casts fold primary #4043
refuted: state 701 on ; at 731 rank 0 - keeps nothing, casts nothing
```

At the `]` closing the bit-select the parse keeps `constant_primary` — a cast's
operand, whose state accepts **one terminal of 444** — over `primary`, which is
what a concatenation needs, with **rank 0 on both sides**. Nothing in the
grammar breaks that tie and the tie is broken anyway. `grammar.json` declares
`['primary', 'variable_lvalue']` outright, so this is a cell the author asked to
be adjudicated at runtime.

**No parser change ships here.** That seam is `Reading.beats`, a lane is inside
it tonight, and an earlier attempt at the same repair in `column.zig` and
`bench.zig` moved the contested count by zero and was reverted. What ships is
the measurement, `research/joinery/verilog/RESULT-7-leaf.md`, and a permanent
floor: `leaf.py --check`, four sources with the tree each was read on, sha256 on
every second-corpus file, and the two witnesses carrying their verdicts written
down — so that *repairing* the refused one fails the check and has to be
acknowledged, rather than going quietly green.

Two instrument corrections went with it, both of which had been flattering us.
`share` was our leaf bytes over their token bytes, which is not a coverage
number — a leaf span may cover trivia the lexer calls blank, and one ablated arm
read **100.2%**; it is now the intersection. And the counterfactual was
parenthesising concatenations in **lvalue** position, where a parenthesis is not
legal verilog: it manufactured a wall of its own at
`{(mem_rdata_q[31:25]), …} <= …` that was one edit away from being reported as a
third defect.

A spared cell now says *why* it was spared. `Conflict.Class` gains `sided`
beside `unwritten`, because `bench.decide` had two arms that spare a reading
for opposite reasons and recorded both under one name.

    unwritten  nobody wrote the other half of the comparison, so the parse has
               no authored guidance and the reading it passed over is all it has
    sided      precedence declined in both directions and a side declared over
               the whole rule ordered the pair, and did no more than order it

Both still fork, so this is byte-identical on every instrument: all 30 rows of
`tool/standing.py` are unchanged against the same tree with the class collapsed
(only the cache lines move, because a new binary re-mints the folios).
What changes is that `outliner state` can now tell two cells apart that used to
print the same word, and that is the whole reason the rest of this is writable.

**verilog `[89368,89412)` is attributed to a cell.** The witness is 193 bytes at
`research/joinery/parameter/parameter-port-list.v`: a module whose port list
carries an `ifdef`, then `module b #(parameter [0:0] P0 = 1, parameter [31:0] P1
= 32'h 0000_0000)`. Byte 128 is the second `parameter`, and it comes back
`simple_identifier [128,137)` where byte 96 is a keyword.

The cell is `(324, ",")`:

    , fold list_of_param_assignments -> param_assignment [prec 0 left]
      [sided shift_reduce, over read on]

The author wrapped `list_of_param_assignments` in `prec.left(0)`; the read
facing it across the comma is ranked by nobody. `Ladder.sided` fires and the
read is spared, correctly on that rung's terms. What costs is not the fork, it
is what the fork inherits: the comma refutes the fold on the same token that
opened the split, so the spared read is orphaned at birth and is the only
reading left. It shifts into state 819, whose entire shift row is
`simple_identifier` and `\`. `offer` unions one reading, the scanner gets a
two-symbol slate, `parameter`'s automaton never runs, and by surviving the
orphan also suppresses the mend that used to rebuild the declaration whole.
Under `OUTLINER_TRACE=quire` it is two lines: `split: state 324 on , at 125`
and `refuted: state 126 on , at 125`.

`[80096,80105)` is the same word in the same file and has never drifted,
because the parse reaches it holding the reading the table chose. The
difference between the sites is not lexical and not the word.

**Three repairs priced, none shipped.** The first two were measured against pin
`coverlane`; the third by gating one line behind an env var so a single binary
is both arms, which is the only clean A/B available while other lanes have
uncommitted work in this tree.

*A spared reading may not outlive its keeper.* Seats the row; verilog square
3,472 -> 668, kotlin loses exactly the +735 `sided` was worth, and go's harness
goes `accepted` -> `unexpected {`. So the `unwritten` change is **not** wrong,
and its inheritance is load-bearing on three grammars.

*Keyword extraction should not consult the slate*, which is what tree-sitter's
second lex does. Seats the row better than the original adjudication, at
`parameter_port_declaration/parameter_declaration`, and verilog gains +4,798
built. Unshippable at that breadth: php square 67,697 -> 662, scala 6,739 ->
201, and haskell, julia, ocaml, ruby, bash all move the same way. Twenty-one of
thirty grammars name a `word` and their literals are not all reserved; go's
`make` and `new` are the counter-example.

*Only a `sided` orphan dies, and only as sole survivor* - the repair the new
class makes expressible, and the reason the class is worth having even though
the behaviour is not. It is exactly right on both known cells: verilog's
`(324, ",")` is `sided` and go's `&T{}` at `(181, "{")` is `unwritten`, and the
two have otherwise identical shape - keeper folds, keeper refuted on the same
token, orphan promoted. It repairs the row with no collateral outside verilog:
29 of 30 grammars byte-identical, `collate.py adjudicated` goes **ours 7
verdicts 1,299B -> 8 verdicts 1,343B**, the delta being exactly this row.

It still loses. Inside verilog it costs 1,460 bytes of `built` and 1,024 nodes,
and the loss is not near the repair: at `[78013,78454)` the baseline builds a
441-byte `statement` over `if (resetn && pcpi_valid …) begin` and the repair
shreds it into loose top-level `simple_identifier` tokens. That is the same
defect being fixed, moved. Narrowing from "dies with its keeper" to "dies only
as sole survivor" changed nothing, which is its own finding: wherever a `sided`
orphan's keeper died, the orphan already *was* the only survivor.

So class is not the discriminator either. A `sided` orphan is fatal at 89368
and load-bearing at 78013, same grammar, same class, same shape. Whatever
separates them is finer than anything the cell carries, and naming it is the
open question this leaves.

The row stays red. `collate.py adjudicated` still reports it, which is the
check that should have caught it in the first place and the one thing here that
needed no building.

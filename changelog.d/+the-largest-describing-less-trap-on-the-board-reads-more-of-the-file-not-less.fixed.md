`--mend=keep` on `picorv32.v` is carried as *"the largest describing-less trap on
the board"* - **+25,457 bytes of `built` for 9,550 fewer nodes**. Both halves
reproduce exactly. The rule the tree uses to decide whether that is a trap does
not, and the rule is the thing that was wrong.

The rule an earlier lane earned reads: *falling node counts are only
reading-less when `covered` falls or `spoil` rises alongside them.* Measured
with each policy actually passed to the parse, neither fires:

```
policy   built    Δ built  describes   Δ desc  covered   spoil  rubble  leaves
fell    30,720        +0     22,222       +0    50.8%  43,346  17,324   2,481
keep    56,177   +25,457     12,672   -9,550    62.6%  32,274   3,107      48
none     2,045   -28,675      1,513  -20,709     3.8%  89,546   1,546      44
```

`covered` **rises** 11.8 points and `spoil` **falls** 11,072 bytes, so by that
rule `keep` is a genuine improvement, and I wrote that down as a contradiction
of the brief before checking what the two witnesses are made of.

**They are made of the thing they are witnessing.** `covered` is the union of
top-level spans over the file size and `spoil` is what is left after `built`,
`rubble` and `orphan` are taken out of it - all three derived from the same
spans as `built`. One root stretched across a hole raises `built`, raises
`covered` and lowers `spoil` in a single stroke. The rule asks two questions
that cannot disagree with the answer.

The independent column is `stretch`: bytes a top-level construct claims with **no
token, at any depth, standing on them**.

```
policy   built  tokens in built  stretch  stretched   honest built
fell    30,720           26,538    4,182      13.6%         26,538
keep    56,177           16,128   40,049      71.3%         16,128
none     2,045            1,682      363      17.8%          1,682
```

**71.3% of `keep`'s `built` has nothing on it.** Netted out, `keep` stands over
**10,410 fewer real bytes** than `fell` does. The board's warning was right, the
trap is larger than the headline says, and the +11.8 points of `covered` is the
same 40,049 bytes of hole counted a second time.

Two instruments to distrust from this, in the same breath as the win. The
`covered`/`spoil` rule cannot detect the class of defect it was written for and
should be replaced by `stretch` wherever it is used as a guard. And the first
version of this measurement scored all three policies through `standing.ask`,
which runs one fixed `--ranges --all` parse and drops any `--mend=` flag handed
to it - so it printed three identical rows and a delta line reading `+0 bytes`,
an instrument reporting a comparison it had not made.
`research/joinery/verilog/ladder.py` now builds its own argv while still
computing the row from `standing`'s own `rows`/`tops`/`union`/`extras`.

One column should go while someone is in here: at top level `rubble` and the
bare-leaf byte count are the **same number** in every row above, because the
only non-`built` top-level spans are the childless ones. Printing both as if
they were independent evidence is how one fact gets counted twice - which is
exactly the failure this note is about.

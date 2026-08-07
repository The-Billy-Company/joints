`tool/rack.py` compares derivations instead of byte membership. For every built
byte it takes the ordered spine of `(name, named, start, end)` from the framing
root down, on both sides, so a right leaf under a wrong parent counts as the
error it is. `plumb` indexed each byte to the deepest node covering it, and the
deepest nodes are mostly right, so a wrong shape over right leaves was nearly
invisible - the blind spot `built` has over wrong trees, reproduced one level up
in the instrument built to catch it.

The number: **83,169 of 384,715 built bytes**, where `plumb` saw 33,634. That is
21.62% of `built`, 23.84% of the 348,819 bytes the oracle can adjudicate, 15.79%
of the corpus; without php, 13.22% / 14.86% / 8.17%. 39,110 of those bytes are
`racked` - the deepest node agrees and something above it does not - and that
class is essentially all of the non-php total. The corpus number roughly
doubled; the non-php number went up nineteen-fold, because php's defect is a
leaf a leaf-indexed comparison could already see and everyone else's is not.
34,687 bytes over verilog and sql still have no verdict at all, because
tree-sitter's own tree has errors there, and the first denominator reads them as
clean.

**Where it goes the wrong way, measured rather than hedged: 27.7% of that number
is soft.** An extra - a comment, a blank line - attaches wherever a parser
chooses, and the walk charges every byte of it to whichever spine it isn't on.
tree-sitter swallows a leading scaladoc into the `function_definition` it
precedes; joints keeps it a sibling; neither has misread anything. Scala is
78.7% soft, which moves it from third-worst to behind ocaml. `rack.py soft`
prints the subtraction so the headline cannot be quoted without meeting it: the
defensible number is **60,138 bytes, 15.63% of `built`**. On toml's 29 bytes I
think this instrument decides wrong and report them anyway, because that is what
the measurement says.

Of the twelve grammars the board reads at 100.0% standing, **three carry a wrong
shape** - go (`type_conversion_expression` for a call), python
(`print_statement` for `print(x)`, a live ambiguity in `python.json` resolved the
other way), and toml. This contradicts the brief and two of this lane's own
predictions: html is 72,288 bytes and **13,971 of 13,971 brackets are shared**.
Five predictions held, three failed.

`rack.py guard` replaces the retired `covered`/`spoil` falsifier, which failed
because both witnesses are built from the same top-level spans as `built`.
`square` is not - it is agreement with a second parser - and across
`--mend=` policies **8 changes on 7 grammars buy `built` and pay `square`**,
swift's `keep` most loudly at +2,696 and -11,582. It prints `THE GUARD CANNOT
RUN HERE` for verilog, sql and yaml rather than reading its own silence as
agreement.

**The instruments that lied, both of them mine.** A containment rule that
dropped tree-sitter's root for reaching past joints's charged **11,914 bytes,
81.3% of zig**, to a spine that was otherwise identical rung for rung - while
the bracket-recall column beside it read 99.9%, which is what a byte number
driven by one wide node looks like. And `inorder` broke same-extent ties
alphabetically, so tree-sitter's `expression_statement [23, 35)` sorted below its
own child `call_expression [23, 35)`; that moved **340 bytes** between `askew`
and `racked` - the two buckets this file exists to tell apart - and left the
total, every per-grammar row and all nine tripwires untouched. There is now a
tenth tripwire, watched red on the old ordering before it was trusted green on
the new one.

The board was not touched. `rack.py board` reprints `standing.py`'s rows
unmodified, walks `standing.tops` rather than restating the scope, and closes on
four checks it would fail: the buckets still total 526,798, the split totals
`built` on every judged row, it judged 384,715 of 384,715, and `square` is
neither zero nor all of them.

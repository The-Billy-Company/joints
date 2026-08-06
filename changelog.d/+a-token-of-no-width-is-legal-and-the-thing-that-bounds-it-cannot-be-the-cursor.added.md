Julia writes `f(x)` and means a call, writes `f (x)` and means something else,
and spells the difference as five zero-width externals sitting between the callee
and its bracket - `call_expression` is literally `_primary _immediate_paren
tuple_expression`. An external hand that consumes no input and moves no memory
had no shape here, so those five were julia's last blind terminals. They are
seated now, on a `.abut` kind that answers `fresh` plus one byte test, and julia
goes **59.6% -> 92.9% standing**, covered 80.3% -> 99.2%, unbound 8,912 -> 241,
roots 1,591 -> 138, bare leaves 897 -> 30, blind 5 -> 0. Board 67.4% -> 69.1%,
unbound 115,139 -> 106,468, `describes` up 2,445 nodes - fewer roots holding more
nodes is a tree getting deeper, not a policy reading less. Twenty-nine of thirty
grammars are tree-identical; julia is the thirtieth, and its wall moved from
`lexer` to `press` at `_delimiter_str_1 in state 136`.

**The pin that seemed to forbid this was not forbidding it, and that is worse.**
`step` refuses a zero-width answer only when it exactly repeats the last
`(offset, symbol, shape)`, against a single slot. So a memoryless hand's first
answer was always fine and nothing needed relaxing - but one slot cannot see a
cycle longer than one, and `A` then `B` then `A` at one offset with nothing
moving walked straight through it, because `B` overwrote the slot that would have
refused the second `A`. Nothing in the tree reached that, since every zero-width
hand seated before now either moves a stack (python's dedents pop a column,
html's implied closes pop a tag) or is the only member who can answer at its
offset. Five memoryless markers are the first arrival for which one slot is not
enough. The slot is now a per-offset ledger with a stated termination argument:
the offset is monotone, a hit with extent advances it and never consults the
ledger, and a hit without extent is counted against a ceiling - so a file of `n`
bytes admits at most `ceiling * (n + 1)` zero-width answers whatever the grammar
does. Ledger alone, before the hand: 30 of 30 trees identical, which is the right
bar for a change that may only refuse more.

Where it is weaker than it looks: **the ceiling is untestable from this corpus.**
Lowered from 256 to 16 and then to 4, every grammar is still byte-identical; at 2
python moves and at 1 scala joins it, so the deepest run of zero-width answers at
one offset anywhere in the thirty is three. The bound that terminates the loop is
exercised by exactly one unit test and by nothing else, and `offside.Columns.max`
at 96 - the run it was sized for - never happens here. The same is true of the
hand's `at > 0` veto: removed, the whole board is identical, so it is a field
guard and is now labelled as one rather than presented as measured.

The census lied, in the direction censuses lie here. By shift, no `_immediate_*`
is co-admitted with any string-interior terminal - 28 pairs of `shift 0`. In the
permission set a hand actually reads they sit together in state 1, where 103
terminals fold to `_word_identifier`, and `_immediate_string_start` shares its
`"` with `_end_str`. The hand was placed last on that evidence; then the
prediction was measured by placing it *first*, and julia did not move by a byte,
because the parser never stands in state 1 at a quote. The census was right about
the table and told us nothing about the file. The hand stayed last for the rule
this file already applies - a hand that moves nothing outranks nothing - and the
comment now says so instead of crediting the phase.

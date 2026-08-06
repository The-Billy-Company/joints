C++ read **411 bytes of damage over 36 roots** - one of the healthiest columns on
the board - and **59.5% crooked with 29.4% bracket recall** against the oracle,
the worst row on it. Nobody had looked at it. Both numbers are one token.

`void g() { f(y); }` is nineteen bytes, parses **whole, one root, zero damage**,
and produces `declaration -> type_identifier + parenthesized_declarator` where
tree-sitter produces `expression_statement -> call_expression + argument_list`.
Same spans to the leaf, every parent different. We read every unqualified call
as a declaration of a variable whose type is the callee.

**The mechanism is arity, not ranking, and that is the finding.** In state 2572
three readings of a bare `identifier` complete at once - `_declarator`,
`type_specifier` and `expression` - and `settle.Conflict.other` is a single
`Action`, documented as *"One of the readings that lost. There may have been
more."* So `Forks.Split` can hand one rival back, the runtime forks correctly
into two *declaration* readings, and the reading tree-sitter takes was never a
strand. The runtime is doing its job: `OUTLINER_TRACE=quire` shows the split at
2572 and both strands refuted on `"`, with no `denied` line, so no budget bound
either. cpp's author declared `['expression', '_declarator', 'type_specifier']`
- three-way - where c declared `['type_specifier', 'expression']`, which a binary
fork covers exactly. That is why the same twenty-line program is 88% square in c
and 19% in cpp.

It also retires a puzzle: the lane that made the runtime consult dynamic
precedence moved cpp **zero bytes** because precedence orders the readings that
are *on the table*, and both of cpp's are declarations.

`ledger.cpp` holds exactly one call with a bare-identifier callee, at byte 685.
**Every square byte in the file lies before byte 690; of the 698 judged bytes
after it, 698 are charged** - on both arms measured, so it is a property of the
parse and not of one recovery strategy. Recoverable square is 883 to 1,197 of
1,408 against today's 185.

And it names what `damage` cannot see. **cpp has less damage than c (411 against
572) and one quarter the square (185 against 767)** on the same program, so a
board sorted by `damage` puts cpp ahead. Three more rows carry the signature -
scala, swift, and elixir at **zero damage with 48% of its adjudicable bytes
crooked**.

Diagnosis only; no parser behaviour changed. The recommended repair - let a
contested cell carry more than one dropped reading - is written down with its
blast radius (17 of 30 rows provably bit-identical, thirteen able to move at all)
and the two things to measure first, for whoever owns `settle.Conflict`.
`research/joinery/cpp/` carries the dossier and three read-only probes:
`vexing.py` (fourteen minimal pairs), `confuse.py` (confusion matrix, unbuilt
frames, charge split at a byte, what the fork is worth) and `blind.py` (every
grammar's `damage` and `square` side by side).

Predictions scored **4 of 9**, and the misses are the useful half: two of them
were one wrong fact - I predicted from the dynamic-precedence non-result that the
runtime never sees a fork here, and it sees one whose two members are both wrong.
The third miss is `damage` catching me the same way it caught the board: I argued
that 411 bytes of damage meant the leaves were largely right, so `racked` had to
beat `askew`. It is 589 askew to 2, because the pre-supply recovery reads 700
bytes as one runaway `string_literal` and `damage` counted that as built.

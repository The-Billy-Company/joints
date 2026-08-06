`bench.decide` had to tell two `.fold` verdicts apart that look identical from
the outside, and did not. A fold that wins on precedence wins on a comparison
the author wrote *about these two readings*, and a rank that speaks deletes the
reading it outranks - there is nothing left to fork on. A fold that wins one
rung down wins on a side declared over the whole rule. Ordering the pair is all
a side may do; it was never a statement that the other reading is wrong. Both
came out of the ladder as `.fold`, both silently deleted the read, and with the
read gone `standing` came to 1 and the cell returned before it was ever
recorded. No conflict, and no fork to find afterwards.

`Ladder.sided` names the second case - precedence said nothing consistent in
either direction, no reading is the fold's own production continuing, and the
folds declared left and only left - and `spared` now records those cells and
leaves their read standing.

The canonical expression grammar is the clean separator, and it is worth
stating because it is the whole argument that this discriminates rather than
over-reaches. With `+` at 1 and `*` at 2, both left, there are four contested
cells: `E+E.` on `*` and `E*E.` on `+` are ordered by a rank about that very
pair, while `E+E.` on `+` and `E*E.` on `*` tie and are broken only by the
declared side. `sided` fires on exactly the second pair and neither of the
first, and every action in the table is what it always was.

That moved `press.lalr`'s test "precedence settles a shift-reduce silently and
leaves no conflict behind", which expected zero conflicts and found two - the
two above. The test encoded the old contract and its name conflated the rungs;
it is now "…and associativity settles one aloud", and it was **strengthened
rather than relaxed**. It asserts the two addresses that must be recorded and
the two that must not, and checks the count last, because `conflicts.len == 2`
is also true if the recorder fires on the precedence pair and skips the
associativity pair - the exact over-reach worth catching, and one the old
`== 0` could not distinguish.

Worth **+735 square bytes on kotlin** (crooked 979 -> 247, so these are wrong
parents becoming right ones rather than new bytes) and **+171 on sql**, and it
seats verilog's W5 and W6: 7 failing witness constructs drop to 5 with all 17
controls standing and none relaxed. Verilog's own +1,573 square bytes are
reported and withheld from every total claimed, because its oracle was being
repaired by another lane while this ran.

It is only shippable together with the capacity fix in the sibling fragment.
Alone it costs 27,623 square bytes, because the forks it correctly opens are
then refused for want of a slot.

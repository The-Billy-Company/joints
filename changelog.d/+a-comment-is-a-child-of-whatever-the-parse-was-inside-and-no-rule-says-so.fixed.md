Two compiler faults, both found by running the query differential and neither
visible to a test written from the notation.

**A pattern over an extra was being proved dead.** `lemma.admits` answers
whether one symbol can stand under another by reading the grammar's productions,
and an extra appears on no right-hand side - a comment is not a child of
`program` in any rule, it goes between any two tokens. So `(program (comment)
@c)` was refused as a pattern that can never fire, on a file full of comments
sitting exactly there. The extras list is now asked directly rather than folded
into the `kids` bitset, because that bitset is also the supertype membership
relation and a comment is a member of nothing.

**A refusal could not name what it refused.** `Fault.name` borrows from the
rubric's arena, which `compile` frees on its way out, so a caller printing the
fault got whatever had been written over it - the corpus surfaced this as an
error message with a blank where the literal should be. The name is now re-cut
from the caller's own source when it would otherwise dangle, which it can be
because the fault already carries the byte it was at.

`wobble.py` kept its own copy of the folio section roster, and the copy went
stale the day `rival` was added: twenty-seven names against twenty-eight
sections, so the run died on an index error the moment it reached the last
directory row. That is the step CI runs to prove a grammar presses to the same
bytes twice, and it had been failing on the tuple rather than on any press since.

The copy is gone. The roster is read from `leaf.zig`, which is where it lives,
and a folio whose section count disagrees with what `leaf.Kind` names now says
so instead of indexing past the end. This is the argument `impose.ledger` makes
on the Zig side, where the compiler can enforce it; here nothing could, which is
exactly why the second copy had nobody to check it.

Thirty of thirty grammars press byte-identically over six mints each.

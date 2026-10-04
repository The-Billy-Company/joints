An outline query rooted on a Rust impl returned only its first method: the
matcher resumed at the impl's children after that answer, stepping past the sole
body instead of asking the body's next function. Child matching now continues
through the parent's remaining steps before it finishes an assignment, so
nested sibling alternatives retain their shared captures and produce every
match in the existing capture order. Greedy quantifiers still commit their run.
Regex preparation and execution failures also refuse the query instead of
dropping a filter or satisfying a negative predicate; allocation failures keep
their own error.

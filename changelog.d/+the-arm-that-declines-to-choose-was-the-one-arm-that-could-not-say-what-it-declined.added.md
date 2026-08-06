`spurned` can now say what it spurned. Clause 3 declines when two literals both
resume the parse, and the arm implementing it returned the instant it found the
second one - so it never reached the `unsure` line below it, and a decline
carried no untellable count. The residue-closure lane named that hole and its
warrant forbade closing it, because closing it meant changing behaviour.

The candidate loop runs to the end now. **No decision moves**: two candidates
declined before and decline now, and `give` is still the first literal that said
yes. What is gained is the size of the thing being declined, and it is not what
the clause's wording suggests:

- **71 spurned refusals** under `--mend=fell`, and **40 of them have more than
  two candidates**. `spurned` is "two or more", and the majority are more, so a
  ranking rule would be choosing among three-plus rather than breaking a tie.
- **3 of the 71 carry an untellable rival** - a candidate whose walk gave up
  rather than answering. Those were structurally invisible before: the arm
  returned above the line that reports them. Even the *decline* there rests on a
  set the walk did not establish.

The existing `spurned:` line is byte-identical and the new count is a separate
`rivals:` line, deliberately. `research/joinery/supply/residue.py` already
parses the first one with an anchored regex, and widening it would have dropped
every spurned row out of a pattern that cannot report its own miss - the exact
failure the `adrift` column was just caught in, where three added words silently
lost 50 of bash's 90 deletions.

Clause 3's justification is also now measured rather than assumed. The predicate
underneath it is "exactly one *said yes*", which is weaker than "exactly one
exists" - a supply made while some rival was untellable is the only literal that
said yes rather than provably the only one that would. Across the corpus under
`--mend=fell`, **none of the 164 supplies has an untellable rival**, on either
side of the confirmed/unconfirmed split (0% and 0%). The clause does not hold by
construction and it holds everywhere it is currently exercised, which are
different statements and both worth having.

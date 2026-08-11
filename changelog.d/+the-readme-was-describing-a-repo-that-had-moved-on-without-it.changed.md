The repository head is rewritten. The old one was accurate when it was written
and had stopped being accurate since, which is the worse of the two failures a
README has, because a stale document reads exactly like a current one.

Every measured figure in it is re-measured rather than copied forward, and each
one now carries the tree it was read off, so the record gate can call it stale
the next time it goes stale instead of leaving that to whoever notices. The
scanner census was the biggest correction: six grammars keep state between
calls, not the eight the old text claimed.

Three claims came out for cause rather than for length. `freestanding-capable`
is gone because the build links libc, so it was a promise the artifact no longer
keeps. The plumb board is now the standing board, under the name it actually
ships with. The Paige-Tarjan attribution moved to `research/LANDSCAPE.md`, where
the refinement is argued rather than asserted, and the head keeps the measured
result instead - a quotient that merges nought to nineteen states out of
thousands, which is a negative result and reads like one now.

The shape is the house one: no tables, one idea to a paragraph, and a first
sentence per section that carries the section, so the first sentences read end
to end are the document in miniature. Reach in particular stopped being a
paragraph that opened in bold pretending not to be a heading.

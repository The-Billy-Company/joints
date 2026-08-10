`Ask.phases` now walks each phase's own rules and derives the offset's facts
once, instead of walking every rule eight times and deriving the same facts
eight times.

A no-inline build settled the question the last fragment left open. Marking
`Engine.step` `noinline` and re-sampling says the block attributed to
`Scanner.read` was indeed inlined engine work: **910 of html's 1051 samples are
`Engine.step`, 87% of the parse**, and 769 of those are the engine's own code
rather than PCRE2 (7%) or guard dispatch. So the customary was not a modest
overhead on a slow lexer; it was the lexer.

Three things were repeated per offset, none of which had to be:

- **`stand` per phase.** Only `layout` stands anywhere but the offset it is
  handed - it soaks the leading whitespace first - so the other seven phases
  were deriving one offset's facts seven times, and `organs.facts` walks back to
  the line start to do it.
- **Every rule per phase.** The loop was `for (rules) if (r.phase != phase)
  continue`, so html asked 8 x 33 questions to reach 33 rules. `Engine.bind` now
  groups rule indices by phase once, preserving each phase's own order, since
  order inside a phase is load-bearing: a rule behind another must not answer at
  an offset the one in front already accounted for.
- **Phases holding no rule at all.** Those now cost nothing rather than a
  `stand`. `sealed` moved behind the same test, because only `layout` reads it.

Measured against tree-sitter with its real C scanner compiled in, over the same
board files:

| | before rung 5 | after the pre-filter | now |
|---|---|---|---|
| markdown | 954.1 ns/byte | 475.6 | **295.8** |
| html | 234.6 ns/byte | 184.1 | **83.7** |
| scala | 162.5 ns/byte | 166.6 | **125.2** |
| elixir | 568.5 ns/byte | 519.1 | **426.3** |

markdown is 3.2x faster than it was and html 2.8x, which moves html from 5.3x
tree-sitter to 1.93x and markdown from 4.8x to 1.54x.

**Nothing observable changes.** The differential against the tree-sitter oracle
is identical to the byte at the same commit: html reports no differences at all,
markdown 124 unexplained, elixir 12, scala 17 extras + 63 unexplained - the same
rung 3 residue, neither fixed nor moved by this. The nine committed throughput
rows all held within 2.4%.

elixir is the one that barely moves, and its profile already said why: 41% of
its samples are in `Gather.run`/`absorb`/`fold` against 1,298 GLR forks, so what
is left there is re-lexing after a fork rather than the sweep. That is a parser
question, not a scanner-as-data one.

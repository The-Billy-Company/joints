`Ask.phases` now asks whether the parse state would take a rule's answer
*before* running that rule's guard, rather than after.

The opening line of every `scanner.c` in the held-out set is a `valid_symbols`
test, and it is there for a reason: at a given offset the parser usually admits
one or two of a grammar's externals, so the cheapest possible question is which
rules are eligible at all. `attempt` asked it in `admits` - correctly, and
exactly one PCRE2 match too late:

```zig
if (!a.guarded(r, o, at, f, b)) return null;   // ran the probe
if (!a.admits(r, at, b)) return null;          // then asked if anyone wanted it
```

So markdown scored 44 rules at every offset, ran the probes of all of them that
could match, and threw away the matches for the 40-odd whose terminal no state
admitted. `Engine.bind` now flattens each rule's possible answers once - the
emit's own symbol, plus every arm of a classifier that could rename it, plus the
name `classify` falls back to when no arm matches - and the sweep rejects a rule
with bitset tests over that set and no bytes read.

It is an over-approximation on purpose: the exact test still runs in `admits`, so
a symbol too many costs one wasted match, and a symbol too few would lose an
answer.

Measured on the four grammars that reach a throughput row, against tree-sitter
with its real C scanner compiled in:

| | was | now |
|---|---|---|
| markdown | 954.1 ns/byte | **475.6** |
| html | 234.6 ns/byte | **184.1** |
| elixir | 568.5 ns/byte | **519.1** |
| scala | 162.5 ns/byte | 166.6 |

markdown halves. scala does not move and should not: its book is one rule, so
there is nothing to filter, and the 0.03x is noise on a 2% spread.

**Nothing observable changes, and that is checkable rather than asserted.** A
guard never writes an organ - there is no assignment to one anywhere in
`guard.zig` - and `abstain` is an action, so it is reached only past `admits`.
The rules this passes over are therefore exactly the rules that returned null.
Built both ways at the same commit: html reports *no differences at all* against
the tree-sitter oracle either way, and markdown's 124, elixir's 12 and scala's
17 extras + 63 unexplained are identical to the byte with the filter disabled.
Those differences are rung 3 residue and this rung neither fixed nor moved them.

The remaining gap is not this, and it is not one thing. scala runs **one** rule
and is still 3.46x, so an interpreter loop cannot be the whole account, and node
density refutes the next guess: latex and toml are the densest trees measured
(4.8 bytes/node) and joints beats tree-sitter on both, at 0.52x and 0.56x.

Sampled profiles say the two worst rows fail for different reasons, which is why
no single fix was going to land here. html spends 94% of its samples under
`Scanner.nextKeeping` and almost nothing building the tree; elixir splits 48%
lexing against 41% in `Gather.run`/`absorb`/`fold`, matching its 1,298 forks.
`pcre2_match_8` - a real call, not an inlined one - is 9% of html and 5% of
elixir, so probe matching is no longer the story it was before this change.

Both booked grammars also carry a large block of samples attributed to
`Scanner.read` itself (71% of html, 29% of elixir) that latex does not have, and
under ReleaseFast that block can hold inlined callees - so it was a lead rather
than a finding at this point. A no-inline build settled it in the next change,
and the lead was right: that block is the engine, inlined. Read the two
paragraphs above as "the identifiable customary cost is *at least* 16% of html",
not as a total.

The guess this paragraph replaced - that `outside.Carry` embedding
`customary.Organs` was costing a copy per fork - is not supported either way:
the copy shows up as a 3% memset, not as the gap.

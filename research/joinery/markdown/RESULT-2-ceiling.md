# Result 2 - the corpus now declines nothing, and markdown builds 2.85x faster

`RESULT-1-stack.md` closed with one pattern standing between this corpus and
every terminal in it being buildable: markdown's `entity_reference`, the only
`declined` row over thirty grammars. It is closed. **The declined population is
zero**, and the fix turned out to pay at build time as well, for a reason nobody
was looking for.

The interesting part is not the ceiling. It is that a refusal is not free.

## What it actually needed

RESULT-1 bisected the entity list and concluded the ceiling was on DFA states
rather than on how many alternatives were written. That was right, and it can now
be replaced with the number. Instrumenting `powerset.build` to report `nstates`
for every automaton the corpus compiles:

| grammar | largest terminal | states | classes | table |
|---|---|---:|---:|---:|
| **markdown** | `entity_reference` | **5,991** | 110 | 5.3 MiB |
| scala | | 2,945 | 147 | 3.5 MiB |
| swift | | 2,175 | 172 | 3.0 MiB |
| elixir | | 2,081 | 172 | 2.9 MiB |
| haskell | | 1,938 | 179 | 2.8 MiB |

The ceiling was 4,096. So `entity_reference` needed **1.46x** it - not an
exponential blow-up, and not a pattern that deserved refusing. It is also the
*only* automaton in the corpus past 4,096, and second place is at 72% of the
bound. **4,096 was right for twenty-nine grammars and wrong for one**, which is a
ceiling set against the wrong population rather than a limit anyone reached.

## Two caps wearing one word

`powerset.Budget` was `enum { budgeted, unbudgeted }`, and the lexer already
passed `.unbudgeted` with a comment arguing its case at length:

> `max_visits` is a COST policy calibrated for a pattern the user typed a second
> ago and will run against one haystack; a lexer slate is compiled once and then
> amortized over every byte of every file for the life of the process

That argument is correct and it is *also* an argument about `max_states`, which
the same comment then waves through as "the SAFETY bound [that] still applies".
Two different questions - the TIME to discover an automaton and the MEMORY to
hold it - had one word for both, so waiving one silently inherited the other.
That is the whole defect. `entity_reference` was refused by a number chosen for
the differential oracles, reaching a caller those oracles know nothing about.

`Budget` is now a struct carrying both axes, with the three seats named:

```zig
pub const budgeted: Budget = .{};                                  // a typed query
pub const unbudgeted: Budget = .{ .visits = false };               // force_dfa
pub const slate: Budget = .{ .visits = false, .states = slate_states };
```

Decl literals mean all three existing call sites are unchanged. `slate_states` is
8,192 - calibrated the way `max_visits` documents itself, as the smallest round
value admitting every automaton measured to need it, with the memory stated: a
state-maxed automaton at the corpus's widest alphabet (179 classes) is 11.7 MiB.
**Raised, not waived** - the powerset is still bounded and the build still
terminates.

## The board did not move, and that is the finding

Two arms, same joints tree (`41ff3dca6a06`), same oracle (`d85e736fa`), 30 of
30 verdicts live on each, differing only in the irregex ceiling:

```
$ diff board-slatectl board-slate
107c107  < stamp: joints 7c480a089 ...
         > stamp: joints 5f5c551fa ...
```

**Every one of the thirty rows is byte-identical.** No regression anywhere - and
no improvement either. The terminal now lexes and the board cannot tell.

That is not a null result, because the arms provably differ where it counts:

```
control  &amp;  ->  &  ·  amp  ·  ;        (3 tokens)
subject  &amp;  ->  entity_reference        (1 token)
```

`main.zig` already says why a declined terminal is invisible in a stream: "the
terminal simply never wins, so the row it should have owned is either a wider
neighbour's or a stray". Here `&` and `;` win as themselves and `amp` falls to
the text run. The fix is real at the lexer and worth nothing at the board,
because markdown's cost is the 47 blind externals RESULT-1 measured, not this
terminal. **The declined row was never the 3,284 bytes**; it was the other,
smaller half of markdown's report, and closing it does not touch the first half.

## A refusal costs more than the thing refused

The unlooked-for result. Slate build time, three runs each, same machine:

| grammar | control | subject | |
|---|---:|---:|---|
| python | 50 ms | 52 ms | flat |
| scala | 645 ms | 666 ms | flat |
| **markdown** | **1,060 ms** | **372 ms** | **2.85x faster** |

Grammars that never declined are flat within noise, so the delta is markdown's.
Admitting a *bigger* automaton made the build nearly three times faster, and the
mechanism is `admit`:

```zig
.refused => |why| if (ordinals.len == 1) { ...record... }
// otherwise fall through and halve
```

A group that declines is bisected to find who is responsible. `per_automaton` is
64, so isolating one bad pattern costs **six levels of re-determinization** -
each rebuilding a group that still contains `entity_reference`, each running the
subset construction up to the 4,096-state bail, each thrown away. Then the 63
innocent group-mates end up scattered across many small automata instead of one
64-wide one.

So the refusal was paying twice: once in speculative builds discarded, once in a
worse slate shape. The bisection is right - it is what lets a refusal name a
pattern instead of losing the slate - but it prices refusals at roughly `log2` of
the group width, and that is the real argument for setting the ceiling where the
patterns are rather than where a different caller left it.

## What the instrument could not see

Worth recording against the apparatus rather than the fix. `pin.py` digests
joints's own tree, and irregex is a **path dependency**. Both arms pinned as
`tree 41ff3dca6a06` - identical - while the binaries are `7c480a089` and
`5f5c551fa`. `still.py against` would call these arms comparable on a tree digest
that cannot see the variable under test.

It was harmless here, and by accident: holding the joints tree constant made
this a clean single-variable experiment. But a pin that names a tree it did not
fully observe is a citation that could outlive its truth, and the binary digest
is the only field that noticed.

## Provenance

```
control  joints 7c480a089 · irregex 2a4488d (pristine)
subject  joints 5f5c551fa · irregex 2a4488d + this change
both     tree 41ff3dca6a06 · repo fdda15a2a+31 · oracle d85e736fa · 30 of 30 live
```

State counts from a temporary `nstates` probe in `powerset.build`, removed. The
declined census is `joints lex` over all thirty grammars, falsified by putting
the ceiling back: at 4,096 it reports `markdown: 1 pattern(s) the engine would
not build: entity_reference`, at 8,192 it reports nothing.

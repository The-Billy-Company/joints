# bench — the rungs

A **rung** measures a trade. It is not a test and it is not in `zig build test`:
a test asserts an invariant and fails when the code is wrong, where a rung prints
a table and is useful even when everything is right. The two are kept apart so
that neither has to pretend to be the other.

One directory per rung under `rungs/`, each with a `bench.zig` whose `main`
prints its table, and a `README.md` saying what the table means. Each gets one
step in `build.zig`, ReleaseFast unconditionally - a Debug timing table is a
table of Zig's safety checks - with the working directory at the repository root
so a rung can read the committed corpus by its path.

| rung | question | step |
|---|---|---|
| `vellum` | What does settling a tree into parentheses cost, and what does it buy? | `zig build bench-vellum` |
| `quotient` | Which states, columns and spellings does no parse tell apart - and is the payload smaller as one automaton? | `zig build bench-quotient` |
| `grain` | Does reading bytes a block at a time beat reading them one at a time, and does an index over the lines repay building it? | `zig build bench-grain` |

## House rules

- **Print the half that loses.** A rung whose every row favours the new thing is
  a rung with a bug in it. `vellum` loses `parent` by 29x and says so in its
  first table.
- **Both arms over the same input, interleaved.** A shuffled visit order drawn
  once and read by both walks; the arms alternate within a round rather than
  running in blocks, so a thermal drift halfway through lands on both.
- **Min-of-N.** Interference from the other agents on this box only ever *slows*
  a trial, so the minimum is the cleanest estimate of the true per-core cost.
- **Consume the answer.** A walk whose result is discarded is a walk the
  optimizer deletes. Every row carries a checksum out.
- **Assert what is deterministic; print what is not.** A size floor is a real
  ratchet and belongs in the rung as an error return. A wall-clock floor on a
  shared laptop cries wolf, and a gate that cries wolf teaches you to stop
  reading it - so timings are printed and judged by a person.
- **Skip a missing fixture, fail a wrong answer.** `upstream/` is fetched rather
  than committed, so a row whose corpus is not underfoot prints `skipped` and the
  rung goes on. A row that ran and got the wrong answer exits nonzero.

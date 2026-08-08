# rung: grain

> `zig build bench-grain`

Is one pass over the raw material cheaper than the walk it replaces? Three arms
and four sections, and two of the sections say no.

The arms all answer the same question - `grain.lead`, the leading-run
measurement every layout-sensitive grammar is built on - and they differ only
in what they are allowed to use:

- **`walk`** — the control. The byte-at-a-time measurement `lex/hand/offside.zig`
  carried before this area existed, transcribed into the board. It is not
  reachable from the library, and it is not a second implementation kept in
  step: if it drifts, `agree` fails the run before a single trial is timed, at
  every offset of every file rather than at the offsets the tour draws.
- **`sweep`** — the same measurement with its scans vectorized and no index at
  all. This is what every caller gets for free.
- **`ruled`** — the same measurement again, reading a `grain.Ruling`.

## `lead` — the two tables, and the order is the finding

The same asks appear twice: **in order**, line after line, which is how a
scanner asks; and **jumbled**, which is how an editor jumping around asks. The
byte arms cannot tell the difference. The ruling can, because its line lookup
is a bisection behind a one-line memo, and a memo is exactly a bet on the next
question resembling the last one.

Read in order, the vectorized arm wins on real source (1.0-1.6x) and the ruling
adds another 1.15-1.5x on the two large files. Read jumbled, the ruling is
**three to ten times worse than the byte walk** on every shape - the memo misses
every time and every ask pays a full bisection on top of a walk it barely
shortened.

So the ruling is a scanner's index, not an editor's random-access index. That
is a real limit and not a tuning knob: it is worth having in `weave`, where the
parse sweeps forward, and it would be worth nothing behind a "go to line" box.

## Where the vectorized arm loses

Three shapes, and all three are the same shape:

- **`prose`** (a comment line, and nothing else) — ~0.5-0.9x. The measurement
  returns almost immediately, so the whole cost is the block load, and there is
  no run for it to skip.
- **`bounded`** and **`blank`** — ~0.9-1.0x. Same reason.
- **`go`, `ruby`, `shell`** — ~0.8-1.0x on the jumbled table. Kilobyte files
  with four-space indents: a 64-lane compare answering a four-byte question.

The general rule the board keeps demonstrating: **a vector wins on runs and
loses on decisions.** Which is why `sweep.zig` peels a handful of bytes
scalar before it loads a block at all - without that peel every corpus row was
behind the control, because extracting a 64-lane comparison into a `u64` is a
shift-and-narrow sequence on NEON rather than the single `movemask` x86 has.

## `build` — and the break-even that says `never`

What the index costs to raise, per byte, and how many in-order asks repay it.
Most rows say `never`, and that is the honest answer: a file whose measurement
the index does not shorten never repays the pre-pass however long you wait.
The rows that do repay are the large real files, at tens of thousands of asks -
far more than one parse of one file. **The pre-pass does not pay for itself
inside a single cold parse.** It pays across an editing session, which is the
next section.

## `edit` — microseconds a keystroke

Splicing the ruling against rebuilding it: ~100x on the large files, ~12-25x on
the kilobyte ones. This is the section that decides whether the index survives
an editing session, and it is the reason `weave` keeps one at all.

## The floors

One, and deliberately the loose one: **`VectorizedWalkLostEverywhere`**, if the
vectorized arm is more than 4x behind the control on any shape. That means the
block size or the load is wrong. Losing on one narrow shape is a fact about the
shape, not a regression.

`SpliceStoppedBeingCheaperThanRebuild` is the other, and it is not a timing
judgement so much as a claim about the algorithm: a local splice that has
stopped beating a global rebuild is not local any more.

The `ruled`-against-`sweep` ratio gets **no** floor. Whether an index repays
itself depends on how many times the file is asked and in what order, and a
wall-clock gate on a laptop ten agents are working in cries wolf.

## The slate

Eight joinery corpus fixtures, the package's own two largest source files
(`src/kernel/lex/outside.zig` and `tool/standing.py`, under both comment
spellings), and five generated shapes chosen so that each arm has something to
lose to. The fixtures are a kilobyte apiece, which is below the size at which
any index can repay its own lookup - a board carrying only those would report a
loss that is really a fact about the fixture. A file that is not underfoot
prints `skipped` and the rung goes on.

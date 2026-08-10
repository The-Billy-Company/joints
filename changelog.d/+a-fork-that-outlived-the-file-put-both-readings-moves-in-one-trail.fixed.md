`Gather.close` now folds each surviving reading down onto that reading's own
strand, and the trail is welded from the reading that actually won.

`error.TrailRefused` killed `joints amend` outright on markdown and scala - both
of them, at era 0, on the *open*, so neither grammar had an incremental path at
all. Six bytes of markdown reach it:

    printf '[a]: \n' > t.md && joints amend markdown.folio t.md '0..0= '
    → error: TrailRefused

The trail is the parse's own account of its moves, and `Move` says what makes
that account a lie: two readings appending into one sequence. Round 15 gave each
live reading its own strand for exactly that reason and welds the survivor's in
when the fork collapses. Every writer into the trail learned this except the last
one. `close` folds *each* live reading to a root at the end column, and it did
that with the pen back on `sole`, so a fork that was still standing when the
bytes ran out appended both readings' closing folds to the flat trail. `distil`
then met two folds of one production under two different states, refused the
composition - correctly; they were never adjacent - and raised.

Two lines and a returned field:

- `close` sets `pen` to each reading's strand while it folds that reading, the
  way `absorb` already does.
- it returns the winner's strand, and the `.end` path welds *that*. `finish` was
  welding `first()`, which ranks on the heft a reading arrived with - and the
  end column's own folds change the ranking, so the trail could come from one
  reading and the tree from another.

Why no test caught it: the amend fuzz runs on json, which declares no conflict,
and the two forking fuzzes run on rust and java, whose forks collapse before EOF.
A fork *outliving the file* was the one shape nothing covered. There is now a
27-line grammar in `amend_test.zig` whose two readings can never reconcile, and
three bytes of it fail on the unfixed parser at `Run.init`.

The two grammars this was costing:

| | before | after |
|---|---|---|
| markdown | `error: TrailRefused` | 9x gain, 10 lifts, 146 tokens read of 1,478 |
| scala | `error: TrailRefused` | 2x gain, 8 lifts, prefix 1.00 → 0.83 |

Across the corpus, `research/keystroke/probe.py` moves from 18 grammars opening
cleanly to 20, median lifts 1 → 2, median gain 7x → 8x.

**And it is a correctness fix, not only a crash fix.** `abide.py` compares the
amended tree against a cold parse of the same bytes after all 24 keystrokes, on
every grammar. Against a binary that is this tree with only this change backed
out: 28 of 30 grammars are identical, and the two that move are the two that were
dying - scala 0 → 24 of 24, markdown 0 → 21. Nothing regressed, and the count of
grammars where every amended tree equals a cold one goes 14 → 15.

yaml and html are untouched by this and still take 0 lifts and re-read the whole
file; that one is the `holds` slate in `research/keystroke/`, which is a separate
defect with its own write-up.

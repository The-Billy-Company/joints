# press — what the table press does that nobody had checked

Two questions, each written down before it was measured.

| file | question | verdict |
| --- | --- | --- |
| `PREDICTION-1-scope.md` · `RESULT-1-scope.md` | is the same grammar pressed twice the same press? | **no**, and the cause is uninitialized memory in a persisted artifact. Fixed. |
| `PREDICTION-2-splice.md` · `RESULT-2-splice.md` | may a rank on a one-step body keep its scope through a fold? | **no**. 517 residual conflicts to 53, and a verilog statement changes category. Reverted. |
| `wobble.py` | the instrument for question 1, and now the corpus gate | — |

## Question 1 — reproducibility

A folio is only worth caching, diffing or content-addressing if pressing the
same grammar with the same binary gives the same bytes. It did not. Eleven of
thirty grammars minted twice, seconds apart, to different files.

The answer is representational, and the cause is **uninitialized memory
reaching a persisted artifact**: two record types were handed to
`std.mem.asBytes`, and both have bytes no field owns. Four bytes of stack per
automaton and four of heap per pattern run went into every folio on disk.

## Question 2 — the splice mark

Rust presses to 176 residual conflicts against `TESTING.md`'s claim of zero for
all eleven pinned grammars, because a rank the author wrote is marked `spliced`
when a fold carries it through an inline and the ladder then refuses to use it.
Declining the mark for a body of exactly one step takes rust and scala to zero
and leaves the corpus damage board byte-identical - but it also turns verilog's
`c[i] <= 0;` from a `nonblocking_assignment` into a `clocking_drive`, which is
the exact failure `Step.spliced`'s own comment predicts.

Expansion runs to fixpoint, so a body that is one step *now* may be the residue
of a region the author wrote around three. The width test reads a derived fact as
an authored one. The repair is to record the rank's authored width at import and
carry it through folding; that is a front-end provenance change, and rust's 176
stand until it lands.

## The instrument

```sh
python3 research/press/wobble.py                   # every grammar, twice each
python3 research/press/wobble.py --reps 6 --audit  # the gate, as CI runs it
python3 research/press/wobble.py --against BIN     # two builds, not two runs
python3 research/press/wobble.py cpp verilog       # just these
```

`JOINTS_BIN` points it at a binary of your own. Ten agents share one
`zig-out`, and during this work a sibling rebuilt it mid-measurement twice - so
a lane measuring its own fix should `zig build -p` into a private prefix and
name it here. A path is not a version.

It compares folios **section by section**, cut by the sealed directory rather
than by a header constant and a slack, so it names the section that moved
instead of an offset. For the one section that does move it inflates the block
on both sides, because a deflate stream can differ for reasons that are not in
its input and its inflation cannot. Then it attributes each differing byte of
the decompressed image to a record's padding or to a field a reader reads,
which is the whole measurement - only the second is semantic.

`--audit` additionally places **every** differing byte of the whole file by
name, against a map built from each mint's own directory: a section, a
directory row, a header field, the alignment slack before the seal, or the seal.
Anything it cannot place is reported as unplaced rather than passed over.

Exit **0** every grammar byte-identical, **1** a table section or a read field
moved, **2** reproducible tables written down two ways.

`--reps` is a sampling knob, not a detail. Against the writer this dossier
fixed, two mints called nine of thirty unstable and six called fourteen; the
population was never a fixed set, only whichever grammars' garbage happened to
differ across the runs taken. A gate should not economise here.

## The guards this leaves behind

- `wobble.py --reps 6 --audit` in the `press` job of `.github/workflows/ci.yml`,
  beside the rung-1 sweep that already fetches the grammars.
- two reflective tests in `src/kernel/lex/lexicon.zig`: every byte of a written
  record is assigned, and at least one of those records still has padding to get
  wrong - so the first cannot pass by having nothing to check.
- `folio_test.zig`'s *"the same grammar pressed twice packs to the same bytes"*,
  which presses from the grammar twice rather than packing one result twice.
  The older test did the latter and was green for the whole life of this bug.

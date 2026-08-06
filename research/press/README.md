# press — is the same grammar pressed twice the same press?

A folio is only worth caching, diffing or content-addressing if pressing the
same grammar with the same binary gives the same bytes. It did not. Eleven of
thirty grammars minted twice, seconds apart, to different files.

This dossier asks the one question that decides how much that matters - whether
those are **different tables** or **the same tables written down differently** -
and then fixes the cause.

The answer is representational, and the cause is **uninitialized memory
reaching a persisted artifact**: two record types were handed to
`std.mem.asBytes`, and both have bytes no field owns. Four bytes of stack per
automaton and four of heap per pattern run went into every folio on disk.

| file | what |
| --- | --- |
| `PREDICTION-1-scope.md` | written first, each claim with its falsifier |
| `RESULT-1-scope.md` | the verdict, the attribution ruling, the fix |
| `wobble.py` | the instrument, and now the corpus gate |

## The instrument

```sh
python3 research/press/wobble.py                   # every grammar, twice each
python3 research/press/wobble.py --reps 6 --audit  # the gate, as CI runs it
python3 research/press/wobble.py --against BIN     # two builds, not two runs
python3 research/press/wobble.py cpp verilog       # just these
```

`OUTLINER_BIN` points it at a binary of your own. Ten agents share one
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

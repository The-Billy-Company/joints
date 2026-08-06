# Prediction 2 — is there a fifth, and how would I know

Four instruments have been caught writing into the thing they were about to
compare. The question is whether that is four bugs or a population. Written
before running anything; suspects named here are named off `tool/README.md`,
which I have read end to end, and off no measurement.

## The method, stated before it finds anything

A clean sweep is only a result if the net is described first, so here is the
net and here is what falls through it.

**The shape, as three conditions that must all hold.** A write is an instance
when:

1. **Target.** It lands inside the *compared artifact set* — the shared oracle
   trees under `lang/<name>/`, the folio cache under `OUTLINER_WORK`, the binary
   named by `OUTLINER_BIN`, the seat's `lib/`, or a committed fixture that is
   itself an arm of the comparison. A write to an instrument's own report file
   is not this defect and must not be counted as one, or the sweep will report
   thirty findings and mean none of them.
2. **Path.** The same run that writes then reads that artifact to reach a
   verdict. Setup and measurement in one process, or in one `make`-shaped
   sequence a lane runs as a unit.
3. **Direction.** The effect is to make the arms *more alike*, or to make one
   arm's provenance unrecoverable. This is the condition that makes the defect
   dangerous rather than merely untidy, and it is a judgment rather than a
   predicate — so the sweep reports it as prose beside each finding rather than
   pretending to compute it.

**Two detectors, because neither is sufficient and they are blind to different
things.**

- **Static (`still.py sweep`).** Read every `tool/*.py` and every `research/**`
  harness with `ast`. Find every call to a *mutating primitive* — the set is
  taken from the standard library's own surface (`Path.write_bytes`,
  `write_text`, `open`/`Path.open` in a writing mode, `os.replace`, `os.remove`,
  `unlink`, `mkdir`, `rename`, `shutil.copy*`, `copytree`, `rmtree`,
  `move`, `NamedTemporaryFile(delete=False)`), never from a list of functions in
  this repository. Resolve each target back to a root by propagating module
  constants and parameters within the function. Then ask which of those writes
  are reachable from a verb that prints a verdict.
  **Blind to:** anything a child process writes. `tree-sitter generate` and
  `outliner mint` are exactly that, and `oracle_build` — one of the four — would
  be only half visible here.
- **Dynamic (`still.sealed`).** Run the instrument's own read verb inside a
  window that snapshots the artifact set on entry and re-reads it before the
  verdict, with the in-process write primitives interposed for the duration.
  **Blind to:** a code path this machine's data does not take. A write guarded
  by `if not exists()` is invisible on a warm tree and is the whole defect on a
  cold one.

Running only the static half would have reported `oracle_build` as a `copyfile`
and missed the `generate` that follows it. Running only the dynamic half on a
warm tree would have reported nothing at all, because every one of the four is a
cold-path or first-run write. So the sweep is both, and a grep is neither.

**What still falls through, and I will say so rather than discover it later.**
`specimen.py`'s defaulted stop line — one of the four — is *not a write*. It is
a missing observation defaulted to the shape of a perfect answer. The two
defects share the lane's second property, a fact about *when* standing in for a
fact about *what*, but only three of the four are writes, and a gate built on
writes catches three of four by construction. I would rather ship a gate that
names the quarter it cannot see than one that quietly redefines the shape down
to what it happens to catch.

## P6 — there is at least one more, and it is in this order

**Predicted:** the sweep finds **at least one** further instrument satisfying
all three conditions. Ranked before looking:

1. **`walls.py warm`.** The README says it "parses the whole file every round
   and blanks the offending byte with a space", holding offsets stable across
   rounds. Peeling forty rounds means forty mutations of the text under
   measurement, and the whole method is a diff of warm against cold. If the
   blanked text is written anywhere the cold arm can read, the two arms converge
   by construction and the cold peel it diffs against is the one being changed.
2. **`bench.py`.** It builds its own binary into `.local/bench/build` and, when
   the tree does not compile, "falls back to the last good build in that
   prefix". A comparison arm that is a *path in a prefix this run also writes*
   is the `pin.py` lesson one directory over.
3. **`order.py build` / `verify`.** `build` rewrites the committed pair from the
   construction and `verify` re-derives the committed pair from the same
   construction. A run that does both is comparing a file against the function
   that just wrote it.
4. **`amend.py` / `bench.py verify` against their committed baselines.** A
   frozen artifact refreshed inside the run that judges it is the same shape
   wearing the ratchet's clothes.

**Kills it:** all four coming back clean under both detectors, in which case the
result is *four bugs, not a population* — and that is a real finding provided
the net above is what caught nothing, rather than a net I narrowed until it
did.

## P7 — the static half will over-report, and the ratio matters

**Predicted:** the static pass raises **more candidates than there are
defects**, because condition 3 is a judgment and condition 1 is only
approximately decidable from an AST. I predict between one and three genuine
findings against ten or more raw candidates.

That ratio is the thing to report honestly. A sweep that prints ten findings and
means one has the same disease as an instrument that flatters: it trains its
reader to scroll. So every raised candidate gets a disposition in the result —
*instance*, *own output*, *before the window*, or *unreachable from a verdict* —
and the count of each is the sweep's real output.

**Kills it:** zero raw candidates, which would mean the detector is not looking;
or every raw candidate being genuine, which would mean I got lucky rather than
thorough.

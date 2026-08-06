Five instruments in this tree have now produced a comparison whose two arms were
not comparable, every one of them coming back clean twice, every one of them
erring toward agreement. Four share a mechanism - *the setup writes to the thing
being compared* - and the obvious gate is a write detector.

**That is the wrong target, and the fifth case is the proof.** A lane pinned a
baseline, worked for eight minutes, pinned its arm, and read `latex -1,185`; the
lex lane had landed a latex fix inside those eight minutes. Nothing wrote to
anything being compared. Both arms were internally honest. The event happened in
the gap *between* two runs, so there is no window either run could have opened
that contains it, and the discipline everyone had been taught - a work directory
per arm, folio shas checked, all of which that lane did - is precisely the check
that cannot see it.

So `tool/still.py` gates the **failure** rather than the mechanism, in two
detectors that are deliberately not merged because each one's blind spot is the
other's population.

**`witness`** records what world one arm was taken against: the binary's bytes,
a per-file manifest of the tree it was built from, the oracle identity of every
grammar read, the digest of every artifact read, and the `OUTLINER_*` variables
that say whether the arm owned its own workspace. `still against A B --mine
<file>` compares two of them and refuses when they differ anywhere outside what
the lane claims. It catches all five, and it catches the fifth on the subject
manifest alone - not *your two arms differ*, which is true of every before/after
all day, but **in which files**, against the ones you named. `pin.py build`
writes that manifest beside its own record, because a pin is a frozen build and
the tree it came from is only knowable while it is still the live tree.

**`seal`** interposes the write primitives, brackets child processes over the
directory they were handed, and hooks `stamp.fed`, so a read of an artifact this
run mutated raises **at the instant of the read** - strictly before any verdict
derived from it, with the file, line and function that wrote it. A write into
the arm's own `OUTLINER_WORK`, or into shared state under a lock the writer
holds, is a mint and passes; that exemption is what keeps the gate off the
repairs the last lane made rather than firing on them.

Nothing in either detector names an instrument or a call site. The seal's
population is whatever the process writes; the witness's is whatever the arm
reads. `still.py verify` restores all five and prints which detector bit each -
the seal catches two and is honestly reported blind on three - then drives the
seal against defects three and four **performed** in a scratch tree, from a
module of their own so the attribution column names a real file. Fourteen rows,
including the ones that must pass: an honest before/after, a null arm, and a
folio pressed into an arm's own cache.

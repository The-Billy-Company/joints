Two control boards taken four minutes apart were each **930-for-930 identical
across three separate processes**, passed `--twice` twice, and **disagreed by 63
standing points on scala**. A third, ten minutes later, agreed with the first.
All three were solid by every check this repo had, and any one quoted alone was
a different claim about the corpus. `--twice` asks *is this binary's board
reproducible*; on a tree ten lanes are editing, that is not *is this board's
tree the tree I think it is*.

So `standing.py` now takes a **witness** on every run - `still.take` after the
survey - and prints it in the footer, embeds it under a `witness` key in
`--json`, and keeps it at `.local/still/witness/<lane>.json` unbidden. It carries
the per-file manifest of the tree the binary was built from, folded to one
digest, plus the artifacts and oracle grammars the run actually read. `--against`
and `--twice` then compare the two **trees** before the numbers, and refuse at a
new **exit 4** when they differ in a file the lane has not claimed:

```
before.json vs this tree: REFUSE - subject: the two arms were built from trees
    differing in 1 file(s), 1 of which you have not claimed and could move the binary
    src/kernel/quire/gather.zig  NOT YOURS
```

That is the file separating the two controls' trees, named without rebuilding
anything - `pin.py` has been writing the manifest beside every pin all along, so
the three pins that motivated this are judgeable today. What could not be
recovered is the tree a *saved board* read, and that is what is now recorded.

It is also not the cause of the 63 points, and the gate is what makes that
sayable. Re-boarded now, each arm in its own folio cache and oracle seat, those
two binaries agree on scala **to the byte**, move 3 of 930 numbers between them,
and press thirty byte-identical folios. The tree difference is real and the
refusal is right; the swing came from a fourth input the board never recorded.
Two of my own board runs eighteen seconds apart already carry different `live`
digests, which is the shape of the answer. One field would have replaced one
unattributable number with a different one - the witness carries binary,
subject tree, live tree, artifacts and oracles separately for exactly this.

Nothing on disk records who wrote a file, so two facts that are on disk draw the
line. **Claimed** by `--mine` is an arm doing its job. **Unclaimed and unable to
reach a product binary** - a `*_test.zig`, by `stamp.builds`, which already
draws that line for `STALE` - is a note. **Unclaimed and build-bearing** is the
case above and sinks the comparison. Two boards that ran the *same bytes* also
get a note rather than a refusal: a source tree that moved under a fixed binary
cannot have moved a number on that board. Erring stricter would refuse nearly
every unpinned `--twice` here, and a gate that fires most of the time is one
people pass with `--mine '*'`.

`--mine` takes a file, a directory or a glob, repeatable and comma-separable,
because a lane's change is `src/press/` and a flag that makes you enumerate
fourteen paths is a flag whose list stays empty.

24 ms on a 946 ms board and 14.5 KB of JSON, which is the design constraint: a
check anyone is tempted to skip is a check that does not exist. Boards saved
before this carry no witness and diff exactly as they did, with one line saying
the tree question could not be asked - so the gate arrives switched off for
everything already on disk and switches itself on as boards are saved. Six new
rows in `still.py verify` hold the distinction from both sides; all 25 hold.

It earned itself the same hour: a retained union arm disagreed with a fresh
family of arms by 226-296 bytes on four grammars, which read as a refutation of
the argument bounding `attribute.py pairs`. The witness said the arm had been
pinned from a tree carrying three of another lane's files. Rebuilt from one
snapshot, byte-identical on all five.

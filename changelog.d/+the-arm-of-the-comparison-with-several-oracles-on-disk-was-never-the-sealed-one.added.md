`attest.py` seats an oracle on its sources rather than its built library, and
found that most grammars exist as several source trees at once on this machine —
css's two differing in 62.3% of their bytes. For a sealed holdout that is the
specific fatality sealing exists to prevent: unsealing later against a different
copy would read as generalization failure or success with no way to tell which.

Measured over the 47 rows the generalization gate reads, the multiplicity is
entirely on the arm nobody was worried about:

    holdout   20 of 20 grammars have exactly ONE oracle source tree on disk
    corpus    14 of 27 measured rows have two or more (toml has three)

It has to be. The holdout's oracle is generated from `holdout/vendor/`, which
this lane alone writes to; the corpus comparator reads the shared `.local` trees
ten agents rebuild. The number at risk was never 23.8%. It was 50.5%.

`holdout.py forked <grammar>` then reads one source file against each copy in
turn, each in its own seat, with `oracle_build` stood down so the copies are
read as they stand. Of 14 forked grammars and 29 distinct source trees, exactly
one copy per grammar can answer at all — the others carry no generated
`parser.c` and will not compile. So the digests are right that the bytes differ,
and the reading that 28 grammars exist as several different *parsers* is one
step further than they support, at least for these 47. The mechanism underneath
is that `oracle_build` normalises a tree to the `grammar.json` it is handed, so
the oracle is a function of that file plus the CLI version rather than of which
directory was found — and both arms' `grammar.json` are digest-pinned.

What is recorded now: `holdout/oracle.json`, tracked in git and written by every
gate run, carrying per row the oracle's `src/` tree digest, its home, and how
many distinct copies exist here, beside the run's court digest, CLI version,
seat and binary. The gate prints a `FORKED` line naming the multi-copy rows and
stating that the digest above is the copy that answered. `told()` digests each
row's oracle at the instant that row is read and again at the foot of the run,
so a sibling rebuilding something mid-run produces `MOVED MID-RUN` and the row
names rather than a two-parser aggregate wearing one identity. Tier A's 320 rows
carry repo, revision and path beside each `grammar.json` sha256, and its footer
says it consults no oracle rather than leaving that to be inferred.

The residual hazard neither survey closes is a `parser.c` generated from
something other than the `grammar.json` beside it, since `oracle_build` compares
only the grammar digests. `attest.survey` covers `parser.c`, so the recorded
digest moves — and `prove` now asserts that by moving one byte of a scratch copy,
with an untouched-copy control, rather than assuming it. 12/12 hold.

The holdout count does not change. It is still twenty.

Pressing the same grammar twice with the same binary gave two different folios,
for fourteen of thirty grammars, seconds apart. `swift`'s `lexicon` section
ranged 66 bytes across eight mints while deciding exactly the same tokens.

The cause was uninitialized memory reaching a persisted artifact, which is a
worse class than the unstable iteration order everyone including me went
looking for first. `src/kernel/lex/lexicon.zig`'s `freeze` handed two record
types straight to `std.mem.asBytes` / `sliceAsBytes`, and both have bytes no
field owns: `lexicon.Head` is sixty bytes of fields in a type `@sizeOf` rounds
to sixty-four, and irregex's `Dfa.PatRun` is `struct { hi: u32, mask: u64 }`
under auto layout, twelve bytes of fields rounded to sixteen. So every
automaton put four bytes of this process's stack into the file and every
pattern run four bytes of its heap, the deflater encoded that garbage
differently each run, and the section's length moved.

Now `freeze` goes through `flat`, which splats a buffer to zero and assigns
each field into it by name, so padding is zero by construction. It refuses at
compile time to take a struct with a non-integer field, because assigning such
a field whole would copy *its* padding and put the same bug back one level
down where nobody would look for it.

Thirty of thirty grammars now press byte-identical over six mints, against
fourteen of thirty for a pinned pre-fix binary. It is a pure win on bytes and
costs nothing on behaviour or time: comparing pre-fix against fixed across all
thirty, twenty folios are byte-identical (their padding happened to already be
zero) and the other ten differ only inside record padding - the inflated
lexicon images are the same length in every case, with zero differing bytes in
any field a reader reads. All 540 board cells are unmoved.

What this was **not** is worth recording, because a day of other lanes' work
was resting on it. The nondeterminism was representational: no table section
ever differed, so no parse ever differed, and the three attribution controls
that reported *28 of 30 byte-identical*, *29 of 30*, and *only two rows moved*
all stand. They compared board output rather than folio digests, which is what
saved them.

Two instruments lied, in opposite directions. `folio_test.zig`'s *"the same
pressing packs to the same bytes"* was green for the entire life of this bug -
it held one `press.Result` and packed it twice, and a second `asBytes` of the
same literal in the same process lands on the same stack slot and reads back
the same garbage, so it could not see anything that varies between *pressings*.
It now has a twin that presses from the grammar twice. And the population
itself lies about its size: two mints called nine of thirty unstable, six
called fourteen, and there was never a stable set - only whichever grammars'
garbage happened to differ across the runs sampled. Any determinism gate that
economises on repetitions understates the damage by a third.

The sweep is `research/press/wobble.py --reps 6 --audit`, now in CI's `press`
job. It compares section by section against the sealed directory, inflates the
one section that moves, and places every differing byte of the whole file by
name - a digest over a folio never was an oracle for a press change.

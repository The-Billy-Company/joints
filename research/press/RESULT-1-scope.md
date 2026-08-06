# Result 1 — representational, and the cause is uninitialized memory

Measured after `PREDICTION-1-scope.md` next door, which was written first and is
not edited here. Three of its five predictions held, one held for the wrong
reason, and one failed outright - and the one that failed is the one worth
reading.

## The verdict

**Representational.** Eleven of thirty grammars press to different bytes twice
running, and not one of those differences is a table. The parse is unaffected,
and the three attribution claims that rest on board output all survive.

**The cause is uninitialized memory reaching a persisted artifact.** Not
iteration order, not an unstable sort. `src/kernel/lex/lexicon.zig`'s `freeze`
handed two record types to `std.mem.asBytes` / `sliceAsBytes`, and both have
bytes no field owns:

| record | fields | `@sizeOf` | unassigned | written per |
| --- | --- | --- | --- | --- |
| `lexicon.Head` | 60 B | 64 | **4 B** | automaton |
| `irregex`'s `Dfa.PatRun` | 12 B | 16 | **4 B** | pattern run |

`PatRun` is `struct { hi: u32, mask: u64 }` under Zig's auto layout, so the
`u64` is seated first and the `u32` after it, and the type rounds to sixteen.
Every automaton contributed four bytes of stack and every pattern run four
bytes of heap. The deflater then encoded that garbage differently run to run,
which is why the *length* of the section moved - swift's `lexicon` ranged 66
bytes across eight mints while deciding exactly the same tokens.

This is the more serious class. The same mechanism that made the file
unreproducible was also writing arbitrary process memory into an artifact meant
to be copied between machines.

## Confirming the sibling lane's localization

Their claim was that every differing byte run sits at or past the lexicon's
start offset, plus two header fields describing it. **Confirmed, and with no
residue.** Rather than skipping a header and comparing a truncated span, every
differing byte of the whole file is placed by name against a map built from
*each* mint's own sealed directory (`wobble.py --audit`). Across all fourteen
wobbling grammars, at six mints each, every differing byte lands in exactly one
of five places:

- `section lexicon`
- `directory[lexicon].count`
- `header.file_len`
- the eight-alignment slack between the last section and the seal
- the seal

**Zero bytes unplaced. No grammar differs below the lexicon's start offset.**
The semantic question is closed for the press.

Two notes on that list, because both were mysteries before they were facts. The
slack is not a leak: those bytes are `00` in every mint, and they read as
differing only because a section whose length moves moves the slack with it, so
one file's payload offset is another's padding. And the first version of the
audit reported five to seventy-five unplaced bytes per grammar - that was the
instrument, not the press. It built its map from the *first* mint's directory,
which cannot describe the tail of a longer twin.

Then the stronger test, which is the one that decides semantics. A deflate
stream may differ for reasons that are not in its input, so both blocks are
inflated and compared as the bytes the deflater was actually given:

- the inflated images are always **the same length** - for every grammar, every
  mint. An automaton with one more state, class, or transition would move
  `trans_in` and every offset after it.
- every differing byte inside them is **in record padding nothing assigns**.
- **in a field a reader reads: zero.** Every grammar, every mint.

## The attribution verdict, stated rather than inferred

All three claims **survive**, and for a stronger reason than "they happened to
measure something else".

| claim | survives | why |
| --- | --- | --- |
| precedence fix, *28 of 30 byte-identical* | **yes** | compared board output |
| layout seating, *29 of 30* | **yes** | compared board output |
| separator seating, *only two rows moved* | **yes** | compared board output |

The board is parse results and node counts. A lexicon whose deflated length
moves but whose automata are identical cannot change a token, so it cannot
change a cell. That is not an argument from where the numbers came from - it is
the measurement above: zero differing bytes in any field any reader reads, over
thirty grammars.

The claim that would **not** have survived is any control comparing folio
digests. None of the three did. A digest over a whole folio was never an oracle
for a press change, and that is the finding worth carrying forward.

## Where the sibling lane's reading needs correcting

They located the bug correctly and diagnosed its home wrongly, which is worth
saying plainly because it points a fix at the wrong repository.

> *"the cause is not in outliner's press at all"* … *"irregex's compiled
> program"*

**The compiled program is fine. Outliner's serializer of it was not.** The
evidence is that the fix is twelve lines in `src/kernel/lex/lexicon.zig`, this
repository, and it takes the corpus to thirty of thirty. If irregex's
determinization were itself nondeterministic - different state numbering,
different transitions - zeroing padding could not have changed anything.

Nothing in irregex needed to change, and its own persisted artifacts already
apply the discipline this file was missing: `corpus/index/phantom/treemap.zig`
writes its records with `sliceAsBytes` too, and its `Ent` carries an explicit
`_pad: u8 = 0` so that there is nothing unassigned to write. That is the idiom;
the lexicon writer just wasn't holding it.

Their `11 of 30` and the identity lane's `9 of 30` are both right, and so is
`14 of 30`. See the scorecard below.

## Prediction scorecard

**1a — the wobble is confined to one section. HELD.** Only `lexicon` ever
differs; every table section is byte-identical across every mint.

**1b — the differing section is `lexicon`, and the inflated images are the same
length with scattered differences. HELD.**

**1c — the cause is uninitialized padding in `Head`. HELD, and incomplete.**
`Head` is a real site, but it is the smaller one. The prediction never
considered that a record defined in *another package* and written by the slice
would have padding of its own, and `PatRun` contributes four bytes per pattern
run against `Head`'s four per automaton. Predicting a mechanism and then
finding only the instance you predicted is how a fix ships half done; the fix
below is reflective for exactly that reason.

**1d — the nine are the grammars with the most voices. FAILED**, and this is
the useful one. There is no stable population. Whether a grammar wobbles is
whether its garbage happened to differ across the runs you sampled, so the count
is a property of the measurement:

| sample | binary | wobbled |
| --- | --- | --- |
| 2 mints | shared, 11:53 | 9 of 30 |
| 6 mints | shared, 11:53 | 11 of 30 |
| 6 mints | pinned control, 12:26 | 14 of 30 |

That reconciles the identity lane's nine, the sibling lane's eleven, and this
dossier's fourteen without any of them being wrong. It also means **`--reps` is
not a tuning detail**: a two-mint gate understates the damage by a third.

**1e — the three attribution claims survive. HELD.**

## The fix

`freeze` no longer hands a struct to `asBytes`. `flat(T, v)` splats a buffer to
zero, assigns each field into it by name, and returns the bytes - so padding is
zero by construction rather than by luck. It refuses at compile time to accept a
struct with a non-integer field, because assigning such a field whole would copy
*its* padding and reintroduce the same bug one level down, invisibly.

Two tests in `lexicon.zig` hold it. The first is reflective on both sides: which
bytes a field owns comes from `@offsetOf`, and every field is set to all-ones so
that an owned byte reading zero is a failure rather than a coincidence. It was
watched to fail - deleting only the zero-splat, in a scratch copy, reddens it.
The second asserts that at least one of the three records still *has* padding to
get wrong, so the first cannot pass by having nothing to check.

`folio_test.zig` gained the sweep-level twin. The existing *"the same pressing
packs to the same bytes"* held one `press.Result` and packed it twice, which is
weaker than it reads: the tables are the same objects both times, so it never
saw anything that varies between pressings. It was green for the entire life of
this bug, because a second `asBytes` of the same literal in the same process
lands on the same stack slot and reads back the same garbage. The new *"the same
grammar pressed twice"* presses from the grammar twice - fresh determinization,
fresh allocations - which is what two processes minting the same grammar
actually do.

## Result

| | wobbled at 6 mints |
| --- | --- |
| pinned pre-fix binary | 14 of 30 |
| fixed | **0 of 30** |

Cross-binary, pre-fix against fixed over all thirty: twenty grammars are
byte-identical (their padding happened to be zero already), ten differ, and in
every one of those ten the inflated images are the same length with **every**
differing byte in record padding and **none** in a field a reader reads. The fix
changed padding and nothing else.

The corpus gate is `research/press/wobble.py --reps 6 --audit`, wired into the
`press` job of `.github/workflows/ci.yml` beside the rung-1 sweep that already
fetches the grammars. It exits 0 clean, **1** if a table section or a read field
moved, **2** if reproducible tables were merely written down two ways - graded,
because those are different news and a gate that spells them the same way
invites the wrong repair.

## The instrument I trust least

**`wobble.py`'s own `padding()` walk**, and it is not close.

Everything above rests on one claim: *this differing byte is padding, not
payload*. That claim is produced by a Python cursor re-walking the inflated
image the way `thaw` walks it, and it is the only part of this dossier that
would report exactly what I hoped to see if it were wrong. A walk that drifts
out of step lands inside a table and calls a real difference padding - the
finding inverts, silently, and reads as "representational".

So it is built to trip rather than to excuse. It re-checks the two invariants
`thaw` re-checks at every voice (`0 < ncls <= 256`, `trans_in == nstates * ncls
== trans_fin`), and it asserts that the walk lands exactly on the end of the
image. Those assertions fired repeatedly while the walk was being written - both
padding sites were *found* by them - and they are the reason to believe the
final run. But they are self-consistency checks, not an oracle. Nothing here
cross-checks the walk against `thaw`'s own cursor except my reading of it.

Second place: the shared `zig-out`. Twice during this work a sibling rebuilt it
under me - once transiently breaking the tree, once silently rebuilding *with my
own fix in it*, which turned my pre-fix reference into a post-fix one and made a
before/after comparison read 30 of 30 for the wrong reason. Every number in this
dossier was retaken against binaries in a private prefix, plus a real pinned
older binary as the poison. In a tree ten agents share, a path is not a version.

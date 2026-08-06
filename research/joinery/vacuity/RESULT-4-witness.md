# Result 4 - the board now says which tree it read, and refuses across two

Scores the first half of `PREDICTION-2-witness.md`. Three of four predictions
held; one held on the axis that mattered and missed on the axis that did not.

## What the board carries now

`standing.py` takes a `still` witness after the survey - the per-file manifest
of the tree its binary was built from, folded to one digest, plus the artifacts
and oracles the run read - prints it in the footer, embeds it under a `witness`
key in `--json`, and keeps it at `.local/still/witness/<lane>.json` without being
asked. `--against` and `--twice` then compare the two **trees** before they
compare the numbers.

```
witness aud-live2: binary 6fa340df4 · subject c27a23e15 (87 file(s), pin)
  · live c79d47c8d · 0 oracle(s) · 31 artifact(s) · work …/pin/aud-live2/work
  · lane pin-aud-live2
```

## The three controls, judged

The lane before me could not do this: *"`still against` needs a witness recorded
at measurement time and none of the historical pins has one, so re-establishing
four clearances meant rebuilding the arms rather than re-judging the pairs."*

That is true of **boards** and false of **pins**, which is the gap P2 predicted.
`pin.py build` has been writing `world.json` beside every record since before
today, so a witness for a pin can be reconstructed at read time from what is
already on disk. All three of the controls that motivated this lane carry one:

```sh
eval "$(python3 tool/pin.py arm aud-live)";  python3 tool/still.py witness aud-live
eval "$(python3 tool/pin.py arm aud-live2)"; python3 tool/still.py witness aud-live2
python3 tool/still.py against aud-live aud-live2
```

```
still: REFUSE - subject: the two arms were built from trees differing in
    1 file(s), 1 of which you have not claimed and could move the binary
    src/kernel/quire/gather.zig  NOT YOURS
```

| pair | scala agreed, on the day? | trees differ in |
|---|---|---|
| `aud-live` vs `aud-live2` | no, by 63 standing points | `src/kernel/quire/gather.zig` |
| `aud-live` vs `aud-now` | yes | `gather.zig`, `src/press/bench.zig`, `src/press/ladder.zig` |
| `aud-live2` vs `aud-now` | no | the same three |

**One file separated the two controls that disagreed**, and it belongs to the
fork-selection lane. The previous lane remembered two, from reading the two
manifests by hand; the diff of the two manifests is one, and the pair that
differs by *three* is `aud-live` vs `aud-now`, which is probably the pair that
memory merged. The count is now something the tool prints rather than something
a person reconstructs afterward. The pair that *agreed* differs in three files,
which is the more useful row: agreement between two arms that were never
comparable is luck, and the gate refuses it for the same reason it refuses the
disagreement. Nothing was rebuilt to produce this table - it is four seconds of
reading manifests that were already written.

So P2 is **held, and the brief's "historical pins can't be retrofitted" is half
right**: what cannot be recovered is the tree a *saved board* read, because the
numbers do not encode it. That is now recorded going forward and there is nothing
to retrofit.

## And `gather.zig` did not move scala

Naming a file is not naming a cause, and the honest way to find that out is to
run the arm. Both control binaries re-boarded now, each in its own folio cache
and its own oracle seat:

| | |
|---|---|
| scala, `aud-live` | damage 4,150 · standing **79.36%** · built 15,957 |
| scala, `aud-live2` | damage 4,150 · standing **79.36%** · built 15,957 |
| the whole board | **3 of 930** numbers move: `cpp.nodes` 183→184, `go.nodes` 437→438, `swift.nodes` 6084→6041 |
| the thirty folios | byte-identical; the only artifact that differs is the binary |

So the two arms *were* incomparable and the refusal is right - but the tree
difference is not what produced 63 standing points, and quoting it as the cause
would have been the same error one level up: a true fact adjacent to the number,
presented as its explanation. My own first draft of this file said exactly that,
and this section is what the arm said back.

The remaining suspect is the input the board never had a field for at all, and
the witness now has four of them. The two board runs above, **eighteen seconds
apart**, already carry different `live` digests - a lane landed something while
I measured. That is not proof of what moved scala in a reading taken hours ago,
and nothing recorded then can be, which is the whole reason for recording now:
the fields are separate so a future swing is attributable to `binary`, `subject`,
`live`, `artifacts` or `oracles` rather than to whichever one somebody
remembered to check.

## The crux: which differences sink a comparison

P3's rule, unchanged from the prediction. Nothing on disk records *who* wrote a
file, so the line is drawn by two things that are on disk:

| the file | verdict |
|---|---|
| claimed by `--mine` | declared - that is what an arm is |
| unclaimed, and `stamp.builds` says it cannot reach a product binary | a note |
| unclaimed, and it could have moved a number | **refuse**, exit 4 |

`--mine` takes a **file, a directory, or a glob**, repeatable and
comma-separable. That is not a convenience: a real lane's change is `src/press/`,
and a flag that makes you enumerate fourteen paths is a flag whose list stays
empty, after which everything is unclaimed and everyone turns the gate off. The
test-file exclusion is the same argument from the other side - with ten lanes
editing tests continuously, a gate that fired on a sibling's `*_test.zig` would
fire most of the time, and `stamp.builds` already draws exactly that line for
`STALE` for exactly that reason.

One more looseness, decided after the prediction and worth naming as a change of
mind: **two boards that ran the same bytes get a note rather than a refusal.**
`--twice` is one binary in N processes, and a source tree that moved under a
fixed binary cannot have moved a number on this board. Refusing there would
refuse nearly every unpinned `--twice` on this tree, which is precisely the
strict failure the brief warns about. The note still prints.

Six new rows in `still.py verify` hold the line from both sides - the test-file
note, the same arms with a source file instead (must refuse), a claimed
directory, a claimed glob, and the `--twice` shape. All 25 rows hold.

## Nothing on disk broke

P4 held, and it needed no flag. Every board saved before today carries no
witness, so `--against` against one degrades to:

```
⚠ 1 of these boards carries no witness (.local/aud-iso/live-board.json), so
  nothing below can say whether the two trees were the same one. Boards saved
  from here on do.
```

and exits as it always did. Measured on the previous lane's own retained board:
exit 0, `STABLE`, one extra line. The gate arrives switched off for everything
that already exists and switches itself on as boards are saved. Exit 4 is new and
sits beside the four codes that were already load-bearing, so a script telling
*your numbers moved* (1) from *there is no comparison here* (4) does not have to
guess.

## What it cost

| | |
|---|---:|
| board run, pinned binary | 946 ms |
| `still.take` on it | **23.9 ms** (2.5%) |
| ...of which the live manifest, when the binary is the tree's own | 4.8 ms, 87 files |
| `still.keep` | 0.3 ms |
| board `--json`, before | 24,036 B |
| board `--json`, with the witness | 38,534 B (**+14.5 KB**) |

P1 held on time and **missed on size**: I said under 10 KB and it is 14.5. The
manifest is 87 paths and 87 sha256s and that is most of it. It could be halved by
truncating the digests, and it is not, because the manifest's whole job is to be
byte-comparable against the `world.json` a pin already wrote - a second,
shorter encoding of the same fact is how two instruments come to disagree about
what a tree is. 14.5 KB is not the thing that makes anyone skip a check.

## The finding that was not predicted, and it is the best one

While scoring the *other* half of this lane, the gate refused a comparison I had
already drawn a conclusion from. `RESULT-5` needed the union arm - all fourteen
seatings removed at once - to check a shortcut, and the union arm disagreed with
the freshly-built pair arms on four of five grammars:

| grammar | pair arm | `aud-iso` union arm |
|---|---:|---:|
| elixir | 21,354 | 21,058 |
| julia | 16,681 | 16,681 |
| kotlin | 19,922 | 19,899 |
| scala | 7,087 | 6,832 |
| swift | 16,250 | 16,024 |

Read alone, that is a 226-to-296-byte refutation of the argument that lets the
subset question stay finite. It is not. The two arms' manifests differ:

```
aud-iso   4 file(s) differ from aud-base: outside.zig, quire/gather.zig,
                                          press/bench.zig, press/ladder.zig
aud-r0-4  1 file(s) differ from aud-base: outside.zig
```

The union arm was pinned earlier in the day, from a tree carrying three files the
per-row and per-pair arms do not have - **the same three files as the control
pairs above**. Rebuilt from the same snapshot, the union arm matches every pair
arm **to the byte on all five grammars**, and the shortcut is sound after all.

That is this lane's whole thesis arriving unbidden: a difference that reads as a
result, in a family of arms built by a lane that was being careful, found by a
check nobody had to remember to run.

A 38-byte version of the same thing sits in `RESULT-2-arms.md`: its haskell row
reads `34,240 | 25,048 | −9,192`, and re-derived from the retained pins the
control is **25,086** and the worth **9,154**. 9,192 is haskell's `built` on the
*live* tree - the value `plumb/RESULT-1-askew.md` and the day's changelog quote,
so the published inventory is right - and 9,154 is the same quantity on the
snapshot the arm was actually built from. One row, one column from each of two
trees. Nothing downstream turns on 38 bytes; the mechanism is the same one that
cost 296 above.

## Score

| prediction | outcome |
|---|---|
| P1 cost under 5% and under 10 KB | **half.** 2.5% of a board, and 14.5 KB - over by 45%, kept anyway |
| P2 the retained pins are judgeable today | **held**, and it names the one file separating the two controls |
| P3 claimed / build-bearing / test-only, with prefixes and globs | **held**, plus one loosening I did not predict (same bytes -> note) |
| P4 nothing already on disk breaks, no flag | **held** - the previous lane's board diffs to exit 0 with a note |

## What I still would not trust

The witness's `oracles` field reads **0 oracle(s)** on every board above, because
an unaudited board never feeds a `grammar.json` and `seen_oracles` has nothing to
walk. So the tree half of the comparison is real and the oracle half is
structurally untested on this path. A board taken with `--audit` populates it;
none of mine were, so I am reporting a field I have not exercised, which is the
kind of sentence this dossier exists to make people write.

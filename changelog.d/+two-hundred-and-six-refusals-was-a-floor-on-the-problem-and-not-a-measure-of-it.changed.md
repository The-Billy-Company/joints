The attribution gate shipped advisory with 206 refusals and no idea how many of
them were wrong. A gate whose false-refusal rate is unknown cannot honestly be
argued into blocking, because the argument has no denominator - and "206" is a
count of the accusation rather than of the offence.

`sighting.py --rate` is that denominator, and it splits the gate in half.

```sh
python3 research/joinery/consort/sighting.py --sample 15 --seed 11   # the worklist
python3 research/joinery/consort/sighting.py --rate                  # the reading
```

| axis | refused | judged | false | rate (95% Wilson) |
|---|---:|---:|---:|---|
| blind only | 30 | 15 | 9 | **60.0%** [35.7%, 80.2%] |
| both | 80 | 15 | 2 | 13.3% [3.7%, 37.9%] |
| stamp only | 108 | 14 | 0 | 0.0% [0.0%, 21.5%] |
| stamp axis | 188 | 29 | 2 | **6.9%** [1.9%, 22.0%] |

The draw is **stratified** because the three axes are three different questions
and the rarest of them is the half the gate was least sure of - a proportional
sample of 45 would put four pages in `blind only` and report its rate to ±40
points. It is seeded so somebody else can redraw the same worklist and disagree
with the adjudications rather than with the sample. All 45 were read in full,
and the verdicts are committed at `sighting.adjudicated.json`.

Intervals are Wilson score rather than the normal approximation, which gives ±0
at 0 of 14, and 0 of 14 is not certainty.

So **the stamp axis blocks and the blind axis reports**. Nine of the fifteen
`blind only` refusals are pages that did ask a second parser and said so in a
word the vocabulary has no entry for - *the oracle defends 611*, *median 2.9x
tree-sitter's time*, *4,300 unjudged where the oracle had nothing to say*. A
closed word list cannot be completed by trying harder at it, which is the same
finding `STAMP`'s comment already records about anchoring a digest to a keyword.
An axis wrong three times in five is not a gate, it is a tax on being right, so
it prints `note:` and returns 0. `--strict` runs it blocking for anyone
measuring whether it is ready.

Its promotion criterion is a number and not a mood: `--rate` under 10% false for
`blind only` on a fresh seed. The way there is not a longer word list - it is
that the oracle's identity is already on the board as `still.Witness.asked`, so
a page carrying a `--cite` line needs no vocabulary for "asked a second parser"
at all. That makes the blind axis a consequence of adoption rather than a
competitor to it.

Every axis is re-derived live and joined to the adjudications by path, so a page
somebody stamps this morning leaves the stratum it was judged in and stops
counting. Correct arithmetic, and also how a measurement decays quietly into a
smaller sample while still printing a number, so `--rate` closes by saying how
much of itself it has lost.

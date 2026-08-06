# felled — what a policy does with a hypothesis

`../supply/` added the second move: at a refusal the runtime can supply a
missing anonymous terminal and re-read the same token. It landed with a result
that split by mend policy on the same rule and the same grammar — a pure
reclassification under `--mend=keep`, and 284 bytes of new wrong structure under
`--mend=fell`, the default.

This directory is the lane that found why, and it was not in the rule.

| file | what it is |
|---|---|
| `RESULT-1-unproven.md` | the mechanism, the two hypotheses that died, the repair, and the priced default |
| `board.py` | arm against control across every row and policy; `--price` asks what a new default costs |
| `founded.py` | what a supply's stack was founded on — the author's text, or the last mend |
| `untellable.py` | whether the damage sits on supplies whose rival was untellable (it does not) |

## The one-line answer

A supply is a hypothesis with a **one-token warrant** — clause 2 proves the
refused token shifts next and nothing more. `keep` leaves it under test for the
rest of the file; `fell`'s next refusal calls `unwind`, which publishes the
whole standing chain as finished structure, **ghost included**. The defect has a
countable shape: a zero-width node at depth 0, covering no bytes and standing
under no parent. There were **127** of them under `fell` and **1** under `keep`.
`unwind` now stops publishing at the first unconfirmed supply, and the default's
regression goes from **+688 crooked to +112** while `keep`'s **+3,124 square**
does not move.

## The two negatives, which are the point

Neither surviving explanation was the first one this lane believed.

**Depth is not provenance, and cannot be made into it.** The `ground` guard
refuses at depth 0 because "an omission is only a thing relative to something
the author began" — and after a `fell` the stack is a stump a mend erected, so
85% of supplies stand on eight tokens or fewer where `keep`'s median is 4,302.
Real, and it repairs into nothing: `bare()` makes the mend's perch index 0, so
the segment floor *is* the ground, and the only remaining lever is a depth
threshold — a new constant of exactly the kind under audit here.

**Clause 3's untellable rivals explain none of it.** The predicate is "exactly
one *said yes*", which is weaker than the clause reads. Of 164 supplies under
`fell`, **zero** have an untellable rival — on both sides of the
confirmed/unconfirmed split. Every one of verilog's 1,139 `unsure` lines sits at
a refusal that supplied nothing. So clause 3 does not hold by construction and
holds everywhere it is exercised, and those are different claims.

## Running it

```sh
eval "$(python3 tool/pin.py arm <name>)"
python3 research/joinery/felled/board.py --mend fell --mend keep
python3 research/joinery/felled/board.py --price
```

Both arms are one executable a single `--no-supply` flag apart. Check the arm
says *30 of 30 verdicts live* first — an unsighted arm reports `square=0`, which
is also what a perfect grammar reports.

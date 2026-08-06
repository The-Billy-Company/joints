# reprice — the peel's own scissors, priced twice and confessed once

A category called `stranded` held 22,179 bytes and a lane proved 96.3% of it was
the cold peel restarting in state 0. It deliberately did not re-price the board.
This is the re-price, and it turned into two findings rather than one, because the
instrument that cleared the first artifact was manufacturing a second.

Read in this order:

| file | what it is |
|---|---|
| `PREDICTION-1-provenance.md` | six predictions about the join, the frontier and verilog, written before anything ran |
| `PREDICTION-2-alias.md` | five more, written after one three-parse probe on swift said the *warm* peel was inventing walls |
| `RESULT-1-provenance.md` | the re-price, the three design decisions argued, P1–P6 scored |
| `RESULT-2-alias.md` | the alias cascade, the canopy falsifier, P7–P11 scored, and the instrument I trust least |
| `RESULT-3-verilog.md` | the answer for the lane holding verilog's 63,937 B baseline |

## The headline, stated so it cannot get stronger by accident

Of the 120,832 bytes `tool/walls.py` prices across the corpus:

- **4,749–4,751 B (3.9%) stands** — 14 walls a whole-file parse met on the file
  as written, plus at most 2 walls a whole-file parse refused at the same byte
  *and paid a root or a byte to clear*. The range is not rounding: those last two
  bytes are `witnessed` on one warm run and `alias` on another under the same pin,
  and that non-reproducibility is itself a result — see the replicate in
  `RESULT-2-alias.md`.
- **97,935 B (81.1%) is an instrument** — 37,433 B refused only in a severed
  suffix, 60,502 B where a whole-file peel refused the same byte but blanking it
  bought nothing, so it was re-reporting its own last refusal against the next
  token.
- **18,146 B (15.0%) is `untested`** — past the furthest byte any warm round
  reached. Neither claimed nor dismissed.

For the `stranded` column alone: 22,033 B on this pin → **116 B stands (0.5%)**,
39.9% demonstrably instrument, **59.6% untested**.

**That is not 96.3%, and it should not be.** The inherited claim rested on two
grammars and folded "warm never reached this byte" into "warm cleared this byte",
so a warm run that stalled earlier would have produced a *higher* percentage. The
honest form of the widened claim is weaker than the narrow one, and the number
that grew is the one admitting what nobody can say.

## The two things the peels do wrong, which are the same thing twice

**Cold cuts.** After a wall it hands the parser `text[cut:]`, so every round past
the first parses a fragment whose openers it left behind. The discriminator is not
the state number — `../strand/witness/sw-cut-*.swift` reproduces one orphan `}` at
states 0, 681 and 1166, because a state number is a count of the statements before
it. It is the **round**, carried forward by the instrument that knows it
(`Priced.turn`).

**Warm blanks.** Blank swift's `)` at 1492 and the `}` at 1498 becomes a wall in
the same state, with the same roots and the same reach — and it is not a wall in
the file at all. **91.4% of warm's 1,983 priced rounds bought the parse nothing.**
The discriminator is `Warm.paid`: did blanking this wall close a root or read a
byte the parse could not before.

Both are cases of one rule: **a wall found in a document the instrument made is a
statement about that document.** `research/joinery/owners/cut.py` is the one place
the five stands are decided, so there is no second copy of it to fix separately —
the state-0 rule had exactly that problem and had only been fixed in one of its two
homes.

## The falsifier that is a presence, and the number that is missing

`Cold.canopy` asks whether round 1 built a node over the byte. That is evidence a
short run can fail to find but cannot fabricate, which is the opposite shape from
warm's absence. It convicts four walls and **abstains on the big ones**, and the
abstention is the result: round 1's forest on `Chunked.swift` has a fifteen-byte
hole over exactly the four bytes the cold peel walls on, because the whole-file
parse *mended* there and `stamp.outcome` reports a mended parse's first stop and
nothing more.

So the cold peel is not inventing wall **locations**; it is inventing wall
**attributions** — the terminal, the state, and therefore the owner and the price.
Settling the remaining 18,146 B needs one capability no binary here has: **a
whole-file parse that enumerates its mend sites.** That belongs to `src/`, it is
not in this lane, and until it lands the honest bucket is `untested`.

## Reproducing

    eval "$(python3 tool/pin.py arm strandprice)"
    OUTLINER_WORK=.local/reprice/coldwork python3 tool/walls.py run  --json > .local/owners/priced.json
    OUTLINER_WORK=.local/reprice/warmwork python3 tool/walls.py warm --json > .local/reprice/warm2.json
    python3 research/joinery/owners/owners.py --warm .local/reprice/warm2.json --json > .local/owners/labelled.json
    python3 research/joinery/owners/cut.py --owner "" --warm .local/reprice/warm2.json

Give the two arms different `OUTLINER_WORK` directories. Two runs sharing one work
directory both read whichever folio was written last, and that error is always
flattering, because two runs of the same table always agree.

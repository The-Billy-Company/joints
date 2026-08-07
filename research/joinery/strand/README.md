# strand — who owns the walls that a wall's own state cannot own

`owners.py` labels a wall **`stranded`** when its state holds a completed item:
a fold could have left the state, so the refusal may be several constructs
downstream of the mistake, and nothing in the state can say which. That verdict
is a report of what the instrument cannot own, not an owner.

This lane took the 22,179 stranded bytes, built the two queries the label had
been waiting for, and used them. **The population turned out to be 96.3% the
measuring instrument's own scissors.**

| dossier | what it settles |
|---|---|
| [`PREDICTION-1-attribution.md`](PREDICTION-1-attribution.md) → [`RESULT-1-attribution.md`](RESULT-1-attribution.md) | the three fold bodies (88% of the population), owned and priced |
| [`PREDICTION-2-instrument.md`](PREDICTION-2-instrument.md) → [`RESULT-3-instrument.md`](RESULT-3-instrument.md) | what `--holding` and `--chain` can and cannot claim |
| [`RESULT-2-verilog.md`](RESULT-2-verilog.md) | the verilog `_identifier` eight: not one reduce-reduce family |
| [`RESULT-4-externals.md`](RESULT-4-externals.md) | the `closure.py` external-declaration census, re-measured |
| `witness/` | hand-built fragments, one construct each |

## The headline

| population | bytes | share |
|---|---:|---:|
| the cold peel's own cut — text that is not a program | 21,350 | 96.3% |
| survives a peel that keeps its prefix | 611 | 2.8% |
| in grammars nobody warm-peeled — neither claimed nor dismissed | 218 | 1.0% |

`tool/walls.py`'s cold peel restarts every round **in state 0**, by design and in
its own documentation. So after the first wall it parses a *fragment*, and a
fragment cut out of a brace body has closers with no openers. The parser refuses
them, correctly, and the peel prices the refusal as damage. Swift's
`Chunked.swift` walls at byte 1,492 with three braces still open; the tail begins
`)`, `}`, `}`, `}`.

Of the 611 B that stands, 516 B is verilog's state 701 — already one of the
verilog lane's four hand verdicts, already `conflict`. The genuinely new suspect
is swift's **`) in state 141`, 95 B**.

## The two verbs

```sh
joints state <grammar.json> --holding '<item>'   # which states hold this reading?
joints state <grammar.json> --chain <n>          # how a parse reaches n, and where
                                                   # a fold there goes
```

`--holding` matches structurally — left-hand side, whole body, dot position — so
a completed item is never confused with the same item one position earlier. It
reports **every** matching kernel item in a state. `--chain` reports arrivals and
their sources, each fold's pop depth, the states it uncovers, the goto it lands
on, and a **frayed** flag when a fold's handle origin is wider than one state.

The backward walk under `--chain` is **`press.retrace`, which already existed**.
This lane wrote a second copy of it before finding the first and deleted the
copy; the swap is byte-identical on verilog with a separate `JOINTS_WORK` per
arm. What was kept is one test donated to `src/press/retrace.zig`, asserting over
every completed item of a pressed grammar that an uncovered origin can read its
body forward and land where it started — the property its two hand-picked toy
tests could not distinguish from a walk that ignores the edge symbols. See
[`RESULT-3-instrument.md`](RESULT-3-instrument.md).

They are navigation and falsification instruments. They killed both of this
lane's structural hypotheses in one query each. **Neither attributes** — nothing
about a state says how the parse got its bytes, which is why the population
needed a second peel to settle.

## The discriminator

[`../owners/cut.py`](../owners/cut.py) splits any labelled survey against a
`walls.py warm --json` run. Warm never restarts, so it always has the real
accumulated prefix; a wall it never reaches in hundreds of rounds needs the
state-0 restart to exist.

```sh
python3 tool/walls.py warm --grammar swift --json > .local/strand/swift-warm.json
python3 research/joinery/owners/owners.py --json > .local/owners/labelled.json
python3 research/joinery/owners/cut.py --warm .local/strand/swift-warm.json
```

It prints its own anti-vacuity column: a grammar whose warm set shares no wall
with its cold set is a broken reader, not a finding. The test can say no — three
walls survive it.

**Give any comparison arm its own `JOINTS_WORK`.** Two pinned binaries sharing
one work directory both read whichever folio was written last, and the error is
always flattering, because two runs of the same table always agree. (The
`grammar.json` paths used here press fresh and never touch a folio, which was
checked rather than assumed: the work directory stayed empty.)

## The instrument I trust least

**`cut.py`'s warm peel — specifically its round budget — and passing its own
anti-vacuity check does not clear it.**

The verdict it produces is an *absence*: a wall the warm peel never reached in
400 rounds needs the state-0 restart to exist. Absence from a bounded run is the
one kind of evidence that looks **stronger** the weaker the run is, and the
failure mode runs the same direction as my headline. Warm does not restart — it
blanks the offending bytes and carries on — so it can stall or saturate on a file
the cold peel chews all the way through. Every wall living past where warm
stopped is scored "cold-only artifact" whether it is one or not, and each such
miss inflates 96.3%.

The anti-vacuity column checks that warm and cold share *some* wall per grammar.
That proves the reader is wired up. It cannot see a warm peel that is
systematically shallower than the cold one, because a shallow-but-working reader
passes it comfortably. **The check and the failure mode are orthogonal**, which is
the whole reason passing it is not reassurance.

Two things would settle it and neither is done: re-run warm with a much larger
budget and confirm the cold-only set does not shrink, and compare warm's byte
coverage per file against cold's rather than comparing wall sets. Until then the
honest form of the claim is *at most* 96.3%, on two grammars of thirty.

Runner-up, for a different reason: the corpus board shards (`15/32`, `27/32`)
flap. They were green with this lane's Zig source byte-identical to its current
form, then red twice, while `src/kernel/lex/outside.zig` and
`src/kernel/quire/gather.zig` were being edited by other lanes. Nothing here
depends on the board, but no number read off it right now should be quoted
without checking what else moved.

## What this lane did not do

- **Did not re-price the board.** Re-pricing another lane's instrument on my own
  verdict is the failure this dossier is about. The finding is reproducible; the
  decision is `tool/`'s owners'.
- **Did not touch `src/kernel/quire/`.** The attribution never landed there — no
  handover is owed.
- **Did not warm-peel 28 of 30 grammars.** 218 B of the stranded population and
  all 73.7% of the unowned population are untested against this discriminator.
  `Wall.real` uses the same too-narrow predicate everywhere, so the same question
  is open for the much larger population.

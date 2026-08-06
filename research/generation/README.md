# Generation — can a measurement state its own identity?

Every number this project reports comes off one board, and roughly ten agents
rebuild the tree underneath it continuously. The board reports what the folio
cache **decided** (`cache: kept 30`) and that decision is separated from what
the instrument then **read** by the entire measurement.

On 2026-08-05 a sibling's `zig build` landed at 11:43:49 and something re-minted
every folio in the cache between 11:43:55 and 11:44:04 *while the board was
running and printing `cache: kept 30`*. The atomic publish (`os.replace`) makes
that invisible by construction: every reader gets a whole, individually valid
folio, so a board can assemble a table out of two generations with no torn byte
anywhere to give it away.

`kept 30` means *"nothing needed re-minting when I looked"*, which is weaker
than it reads.

This dossier is the fix: **stamp each artifact's identity at read time and
reconcile at the end**, so a board can say "every row in this table was measured
against the artifact this tree holds now", or name exactly which rows were not.

## Files

| File | What |
|---|---|
| `PREDICTION-1-identity.md` | is a re-mint by the same binary a new generation at all? |
| `PREDICTION-2-race.md` | can the mixed-generation board be provoked, and is today's board quiet through it? |
| `PREDICTION-3-cost.md` | what read-time digesting costs, measured with the process included |
| `RESULT-1-identity.md` | measured — the press is **not** reproducible for at least 14 of 30 grammars, and no detector sees a binary swap |
| `RESULT-2-race.md` | measured — the same event read by both rules at once: `kept 30`, exit 0 against `SPLIT`, exit 3 |
| `RESULT-3-cost.md` | measured — **+68 ms whole process, +8.3% of a board** |
| `stage.py` | the reproduction: `mint`, `blind`, `race`, `control`, `binary`, `settle` |
| `cost.py` | the price, with the old rule restored explicitly rather than subtracted |

Predictions were written before any of them were run. **Three failed**: minting
is not deterministic, the flagged rows are not a prefix, and the cost is 8.3%
rather than under 5%.

## Running it

```sh
python3 research/generation/stage.py          # every trial, ~60s
python3 research/generation/stage.py blind    # just the two-rules-one-event one
python3 research/generation/cost.py 7         # the price, seven runs an arm
```

Nothing here writes to `.local/standing`; every trial presses into a scratch
cache of its own, because nine other agents read the shared one.

## The instrument I trust least

`tool/sole.py`, the gate that exists to catch a rule spelled twice. It printed
`10 rules, one copy each` through every hour of this lane, and its corpus is
seventeen `tool/*.py` files — the seventy-four `.zig` files under `src/` are
outside it, which it says out loud on every run. Result 1 is the bill for that
blindness arriving: **the press produces a different folio for the same grammar
on consecutive runs of one binary**, for at least fourteen of thirty grammars,
with the *length* varying for half of those. Whatever is unstable in there is
Zig, and no gate in this tree can see it. A green board from a gate that cannot
reach the thing that just moved reads exactly like a green board from a gate
that checked it.

Second least: `reconcile` itself. It digests each artifact microseconds *before*
the exec that reads it, so a publish inside that window is invisible, and it
cannot see A→B→A within one run. Both are stated in the docstring rather than
defended against, which is the honest posture and not a fix. Closing the first
one properly needs the binary to print the digest of the bytes it mapped —
`src/folio`'s to say, not Python's to infer.

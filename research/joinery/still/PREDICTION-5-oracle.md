# Prediction 5 — the oracle half of the witness, which has never moved

Written before the gate is built. The lane before me shipped the tree half of
`still`, exercised it end to end, and named its own harness as the instrument it
trusts least, for one reason:

> every row hands `differ` a `Witness` I constructed by hand … the `oracles`
> field read **0 oracle(s)** on every board I took.

So the predicate is proven and the filler is not, and the one field nobody has
moved is the field that stands for the *other parser* — the only input on this
board whose drift would change every correctness number silently.

## One measurement taken before any prediction, and I am saying so

The brief's fourth question — *has the oracle drifted today* — is four seconds of
reading five `pin.json` files that were already on disk. I took it first, before
writing a line of this file, because inventing a prediction after seeing an
answer is worse than admitting the order. It is scored as **unpredicted** in the
result and it leads the report. Everything below was written before it was
implemented or measured.

## P15 — what actually determines a verdict, and what merely differs

`attest` already answers this and it is the reason not to invent a second rule
here. A verdict is a function of the **authored bytes the oracle was lowered
from** (`survey`) and the **CLI that lowered them** (`oracle_cli`). It is not a
function of the seat, the library path, the library's bytes (two of scala's four
differ in 52 bytes of Mach-O UUID), or which pin tag the copy came out of.

**Predicted:** the witness carries four things and no more — the per-grammar
authored digest, the CLI string, the generated digest per grammar (`attest.built`,
*not* part of identity and kept for exactly one question), and the fold `attest.
Court.digest` already computes. Everything else on an `Oracle` row is a fact
about this machine rather than about the judge.

**Kills it:** finding an input that moves a verdict and is in none of the four.
The candidate I expect to be argued is the compiled library, and the argument
against it is already measured in `attest verify`.

## P16 — the field is empty today because nothing publishes what it consulted

**Predicted:** `seen_oracles` reads `0` not because no oracle answered but
because it looks in the wrong place: it takes the *stem of every `.json` the run
was fed* and asks `oracle_home` about it, so a run that fed
`lang/latex/src/grammar.json` looks up a grammar called **`grammar`**, and a run
that fed nothing named after a language looks up nothing at all. Meanwhile
`attest.SEATED` — the court, recorded at consult time by the two instruments that
really ask tree-sitter — is sitting in memory unread.

**Predicted:** switching the population to `attest.SEATED`, falling back to the
oracle sources the run actually fed, moves a `rack --audit` witness from 0 to 30
and leaves an unaudited board at 0, *honestly* — because that board asked no
oracle. I expect to have to make `0` say which of the two it means, since the
whole hole survived twenty-five green rows by being indistinguishable.

**Kills it:** `attest.SEATED` turning out not to be set on the paths that
actually consult an oracle, which would mean the record is somewhere else again.

## P17 — a board reading a cached verdict IS resting on an oracle

The subtle case, and the one I expect to be wrong about in some detail. A board
with no `--audit` still prints `crooked`, out of `audit.json`, and only accepts a
cached row when `Held.matches` says the four digests hold — one of which is
`bench()`, an oracle identity per grammar. So the board's numbers rest on a judge
it never asked.

**Predicted:** the honest population for a board's witness is *the court its
cached verdicts were attributed to*, which is `bench()`, which the board already
computes and memoises. Recording it costs nothing it does not already pay, and a
board with no audit cache never computes it and records nothing — which is right,
because no number on that page came from an oracle.

**Kills it:** the recording costing measurable time on a board that has a cache
(I predict under 5 ms, since `_BENCH` is already built), or a board with no cache
suddenly paying for thirty surveys.

## P18 — which oracle differences are fatal

The tree half's three-way rule is claimed / unclaimed-and-harmless /
unclaimed-and-load-bearing. The oracle's analogue, predicted before writing it:

| the difference | verdict |
|---|---|
| a grammar the lane claims it is varying (`--judge`) | declared — that is what an oracle arm is |
| the authored identity of a grammar **both arms consulted** | **refuse** |
| the CLI version | **refuse**, once, not thirty times |
| same identity, different *generated* parser | **refuse** — a torn tree, which is defect 4 |
| a grammar one arm consulted and the other did not | warn — the shared set is still a comparison |
| one arm judged and the other never asked an oracle | warn — fewer fields, like `unrecorded` |
| seat, library path, pin tag | silent — none of them can change a verdict |

**Predicted:** the last row is the one that makes this livable, and without it the
gate refuses every honest before/after on this machine, because `pin.py arm` gives
each arm its own seat **by design** and 28 of 29 grammars therefore exist as
several library files at once.

**Kills it:** two honest arms taken minutes apart refusing on the oracle field
with nobody having touched a grammar.

## P19 — the falsifier that would have caught `0 oracle(s)`

Twenty-five rows hold and the hole survived all of them, so the new rows have to
be a different *kind* of row: a real run, its fields read back, each one caused.

**Predicted:** a scratch grammar tree, a real `attest.consult` over it, a real
`still.take`, and one row per field asserting the field moved *because* the
cause was applied — the tree digest when a source byte changes, `work`/`lane`
when the environment says so, `artifacts` when something is fed, `oracles` when
an oracle is consulted, `lowered` when a generated parser is torn while its
identity holds.

**Predicted, and this is the row that matters:** the retired rule is kept beside
the new one — the idiom `attest.was` and `stamp.py --verdicts` already use — and
the proof requires the old rule to **disagree** on the caused run. A row that
only shows the new rule working proves the new rule is self-consistent, which
every rule is. I expect the old rule to read 0 where the new one reads 1, on the
same run, in the same process.

**Kills it:** the old rule also reading 1, which would mean I have misdiagnosed
the hole and the field was empty for some other reason.

## P20 — cost

**Predicted:** under 10 ms added to `still.take` on a board that already has a
court, because it is a dictionary comprehension over rows already in memory;
under 5% of a `rack --audit`, which already pays `attest.read` per grammar; and
under 2 KB of JSON per witness, since it is thirty short digests and a version
string against the 14.5 KB the manifest already costs.

**Kills it:** the generated-digest half being expensive, which it might be —
scala's `parser.c` is 28 MB and `attest.built` reads it whole. If it is, the
honest move is to record it only where a run already paid for it and to say the
field is absent rather than to record a cheap proxy for it.

## What I will not do

Pin a number. The `oracles` field is empty today; the way to make it non-empty is
to record what a run consulted, not to sweep the disk for thirty grammars a board
never asked about. A witness that reports thirty oracles for a run that consulted
none would turn `0 oracle(s)` into a comfortable-looking `30 oracle(s)` and be
strictly further from the truth than the hole it replaced.

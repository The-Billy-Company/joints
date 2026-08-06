# Result 5 — the oracle did not drift, and nothing here could have told you

`tool/still.py`, `tool/attest.py`, `tool/standing.py`'s witness path.
`still.py verify` drives 39 rows, all hold. `attest.py verify` holds.

## The finding, first

**The oracle's authored bytes did not move today.** Five pins were frozen between
00:55Z and 04:16Z; re-digest all five against the live tree, each under the rule
it was minted with, and **150 of 150 rows agree**. The generated half agrees too:
the newest pin's thirty `parser.c`/`node-types.json` sets are byte-identical to
the live ones. Every audit cache on disk that carries an oracle column — five of
six, 150 attributed rows — attributes to a digest that still reproduces. The CLI
has been `tree-sitter 0.26.11` throughout.

So **no published number was measured against a different oracle than its
control.** That is the answer to the brief's fourth question, and it is the good
one.

It is also luck rather than evidence, and that is the finding. The instrument
that was supposed to say so was reading `0 oracle(s)` on every board, including
the two boards that really did shell out to `tree-sitter`. Four lanes write the
shared vendored tree, `oracle_build` mutates it, 28 of 29 grammars exist as
multiple divergent copies. The conditions held all day and the detector was
returning a constant.

### What did move: the ruler

Point the three older pins at the live tree and all thirty rows of each refuse —
`bash: pin moved`, `c: pin moved`, thirty times, three pins, ninety reports of
the oracle drifting. Every one of them is false.

`attest.survey` stopped folding generated files into the identity somewhere
between **02:14Z and 03:49Z**. That was correct — a `parser.c` is an output of
inputs the digest already holds, and its presence is a cache state any
measurement creates — and it silently split every pin on the machine into two
incomparable eras:

| pin | frozen | rule | rows agreeing with live |
|---|---|---|---|
| `frame` | 00:55Z | retired | 30/30 |
| `encapsed` | 01:19Z | retired | 30/30 |
| `seat3` | 02:14Z | retired | 30/30 |
| `c7-compose` | 03:49Z | current | 30/30 |
| `limb` | 04:16Z | current | 30/30 |

The audit caches split on the same seam: `.local/lane-seat3/before` (19:14 local)
and `.local/twice/work` (19:19) carry retired-rule marks, `.local/pin/unjudged`
(21:36), `.local/pin/scars-arm` (22:33) and `.local/scars/cwork2` (22:35) carry
current-rule marks, and `.local/standing` (17:37) predates the oracle column
entirely. A cached row from either side is *valid*; a comparison across the seam
would have read as thirty grammars changing parser.

**A drift detector that cannot tell "the parser moved" from "I measure parsers
differently now" produces false positives at exactly the rate the rule changes,
and today that rate was once.** So `attest.rule()` now digests the code that
computes an oracle digest — the three functions the identity is made of, and the
two constants they partition on. It rides `pin.json`, it rides the witness, and a
rule mismatch is one refusal that says so instead of thirty that do not.

## The hole, and why every green row kept it

`seen_oracles` populated the field from **the stem of every `.json` the run was
fed**, then asked `oracle_home` about it. A grammar's file is always called
`grammar.json`. So the stem is always `grammar`, so the lookup always misses, so
the answer is always zero — for every input, on every board, for the life of the
field. `attest.SEATED`, the court the two consulting instruments record at
consult time, was sitting in memory unread.

Every row of `verify` held over this, because every one of them hands `differ`
a `Witness` somebody typed. They prove the predicate and never call the filler.

## What is there now

**`attest.attribute`** — seat the court a run's numbers are *attributed* to,
without asking it. `consult` minus its two side effects: no feeding the oracle's
sources to the generation ledger, no digesting scala's 28 MB `parser.c`. A board
reading a cached verdict opens neither and should pay for neither, but its
numbers rest on the judge that decided which cached rows it would accept.
`Oracle.asked` keeps the two apart, so `lowers == 0` can never mean both *never
generated* and *not measured*.

**Five new witness fields** — `cli`, `court`, `rule`, `asked`, `lowered`. The
first four are scalars; `lowered` is the generated digest per grammar, recorded
only where a run already paid to read it. All five default, so a witness written
this morning still revives and reads as *did not say* rather than as agreement.

**`still.judged`** — the refusal, with the same three-way care the tree half took:

* **rule**, checked first and returned on, because every row below would
  otherwise fire for a reason that has nothing to do with any parser;
* **CLI**, once, not thirty times;
* **authored identity** of any grammar both arms consulted;
* **torn tree** — one identity, two generated parsers;
* *warn* for a grammar only one arm consulted, and for one arm having asked where
  the other only cited;
* *silent* for the seat, library path, library bytes and pin tag — and silent by
  **not being recorded at all**, which is stronger than remembering not to
  compare them. `pin.py arm` gives every arm its own seat by design; a gate that
  read one would refuse every honest before/after on this machine.

The oracle is deliberately not demoted the way `subject` is when two runs share a
binary. One binary means the source tree could not have moved a number here; it
does not mean the oracle could not, because `crooked` comes out of a cache whose
rows survive only while the identity that produced them holds.

**Seventeen end-to-end rows** in `verify`, driving `take` over a real grammar tree
with each field *caused*. The first two are the hole restored: one fed ledger,
one process, the retired population rule reading `0 oracle(s)` and the current
one reading `1`. Keeping the retired rule beside the new one is the `attest.was`
idiom, for the reason that idiom exists — a row showing only the new rule work
proves the new rule is self-consistent, which every rule is.

**Broken on purpose to check it bites:** delete the fallback, restore the shipped
bug, and exactly two rows go red while all twenty-two hand-built rows stay green.

**One latent crash fixed on the way past.** `Divergence.line` looked its verdict
up in a three-entry dict with a bare `[]`, and `vacuous` — the fourth verdict,
added with the sixth case — was not in it. Every path that *printed* a vacuous
finding raised `KeyError`. `verify` never saw it because its table reads the
fields directly.

## Predictions, scored

**P15 — what determines a verdict (authored bytes + CLI, not the seat, library
or pin): HELD.** Nothing turned up that moves a verdict and is outside the four
recorded things. The library was the candidate to argue for and `attest verify`
already measures it: a rebuild of the same parser changes the library and not the
answer.

**P16 — the field reads 0 because of the `.json` stem: HELD, and stronger than
predicted.** I predicted a lookup that misses; it is a lookup that *cannot hit*.
There is no grammar for which `Path("…/grammar.json").stem` is the grammar's
name, so the function returned `{}` for every input it has ever had.

**P17 — a board reading a cached verdict IS resting on an oracle, and `bench()`
is the honest population: HELD on the design, HALF on the cost claim.** `bench()`
now goes through `attest.attribute` and its output is byte-identical to the loop
it replaced, at 154.5 ms against 154.6 ms — no measurable cost, as predicted. But
I predicted a board *with no audit cache* would record nothing, and what actually
happens is that a board with a *stale* cache still computes `bench` to discover
the cache is stale, and records thirty attributed oracles under a board whose
`crooked` column is empty. That is defensible — those identities are what decided
the cache would be rejected, so they are a real input — but it is not what I
said, and the honest reading of the footer is "the judge this board would
attribute to", not "the judge that answered".

**P18 — which oracle differences are fatal: HELD.** The seven-way table shipped
as written. The row I flagged as load-bearing — seat and library silent — is the
one that makes it livable, and the `--twice` and `--against` runs against real
boards confirm it: no honest pair refuses on the oracle field.

**P19 — the falsifier, with the retired rule beside the new one: HELD.** Two rows
red on the break, twenty-two green, and the retired rule reads `0` where the
current one reads `1` in the same process.

**P20 — cost: HALF.** `take` is 10.6 ms with a thirty-row court seated against
11.8 ms without — the oracle half is free, because it reads rows already in
memory, and the difference is noise. `bench` is unchanged. But I predicted under
2 KB of JSON per witness and it is **2,584 B**, +28% on a 9.3 KB witness. Over,
by a quarter.

**Unpredicted, and scored as such: the rule drift.** The measurement that leads
this report was taken before a line of Prediction 5 was written, because it was
four seconds of reading five files that were already on disk, and inventing a
prediction after seeing the answer is worse than admitting the order.

Five held, two half, none wrong, one taken out of order and declared.

## The instrument I trust least

**`attest.rule()`, the thing this whole report leans on.**

It digests the source of three functions and two constants. Every claim above of
the form *no drift* is really the claim *the two digests were minted by the same
ruler*, and the only witness to that is a hash of some code that says so about
itself.

Three ways it is weaker than it reads:

1. **It cannot see the rule change that has already happened.** The three pins
   from this morning say `rule: unrecorded`, and `attest.py list` classifies them
   by *measuring* — re-deriving three of their rows under each rule and seeing
   which reproduces. That works because exactly two rules have ever existed. A
   third would need `attest.was2`, and nobody adds one of those on the way past.
2. **`inspect.getsource` is not the rule.** It is the text of three functions.
   Move a constant, change something in `differential.INCLUDE` that `sources`
   reaches through, upgrade Python's `rglob` symlink behaviour — and the identity
   moves while the digest holds. The rule digest catches the change I made
   because I made it inside those three functions. It has nothing to say about
   the next one that is made outside them.
3. **It passes its own check by construction.** `still.py verify`'s rule row
   swaps `attest.LOWERED` and watches the digest move. That proves the digest
   reads the constant. It does not prove the constant is the rule, and the whole
   class of bug I spent today on is exactly that: a field that reads something
   real, faithfully, which is not the thing it is named after.

The honest bound on this lane's headline is therefore narrower than the headline:
*the oracle's authored bytes reproduce across every pin and every audit cache on
this disk, under whichever of the two known rules each was minted with.* If a
third rule ran today and left nothing behind, this report cannot see it.

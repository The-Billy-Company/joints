# Result 2 — where the untested bytes fell, who else was blind, and tree-sitter

The re-price named the capability it was missing and refused to guess without
it. This is the answer, and it is not the one that flatters anybody: the
untested bytes fall overwhelmingly toward *instrument*, which is the direction
that makes the re-price's headline bigger — so the first job below is to bound
that answer on both sides rather than publish it.

P5–P11 scored. Reproduce with:

```
eval "$(python3 tool/pin.py arm scars-arm)"
python3 tool/walls.py run --json                 > .local/scars/fresh/priced.json
python3 research/joinery/owners/owners.py --from-json .local/scars/fresh/priced.json --json \
                                                 > .local/scars/fresh/labelled.json
python3 research/joinery/scars/seat.py  --from-json .local/scars/fresh/labelled.json \
                                        --warm .local/reprice/warm2.json
python3 research/joinery/scars/blind.py
python3 research/joinery/scars/against.py
```

## The number I could not resolve, and why I did not map it across

**The re-price's published 18,146 B cannot be resolved on today's tree, and
saying otherwise would be the error this dossier is about.** Its labelling puts
swift's round-1 wall at byte 1492. A sibling has since landed a lexer fix and
today's binary reads to **24,582** before it refuses at all, so every swift wall
in that file is a wall that no longer exists. `seat.py`'s self-check catches this
and exits 1 rather than printing a table:

```
seat: the round-1 walls this seat must reproduce, it does not:
  swift: round-1 wall at 1492 but first scar at 24582
```

So the resolution below is against a **freshly derived board on the arm pin** —
same instrument, same corpus, today's binary — where the same instrument, given
no warm survey, prices **88,975 B as `untested`** out of 97,742 B. That is the
population I hand the capability to, and it is *larger* than the one I was sent
to resolve, not a cherry-picked subset of it.

## Where they fell · **badly for the flattering reading, and bounded**

| provenance | was | now | delta |
|---|---|---|---|
| `document` | 4,857 B | **11,211 B** | +6,354 B |
| `witnessed` | 0 B | 0 B | — |
| `alias` | 0 B | **48,124 B** | +48,124 B |
| `torn` | 3,910 B | **38,407 B** | +34,497 B |
| `untested` | 88,975 B | **0 B** | −88,975 B |

**86,531 B (88.5%) is an instrument. 11,211 B (11.5%) stands. 0 B remains
untested.** The capability closed the category outright: every wall the peel
prices is now either a byte the whole file refuses at with its own context
standing, or one it does not.

Two bounds, printed by the same run, because the single judgement this
instrument makes is worth more scepticism than a headline:

- **If the cascade call is wrong the standing floor is 59,335 B, not 11,211 B.**
  48,124 B is bytes the whole-file parse genuinely refused at, having shifted
  nothing since its previous refusal. Credit them and the instrument share falls
  from 88.5% to 39.3%. They are not credited for the same reason the re-price
  deleted warm's `witnessed` column — applied here to my own evidence rather
  than only to the evidence I inherited.
- **The felling policy is the control, and it is the flattering arm.** Ask the
  same question of a `--mend=fell` parse — where every segment after the first
  reads a suffix from state zero, which is the peel's own resume — and it calls
  **70,330 B** `document` against this seat's 11,211 B. That +59,119 B is what a
  lane would have claimed by asking a parse that had already thrown the context
  away.

So the honest statement is a floor of 11,211 B with a disputed ceiling of
59,335 B, and an arm that would have said 70,330 B if I had picked the
convenient policy.

### The hole, measured

`Cold.canopy` asks "does a node cover this byte". Under `--mend=keep`,
**51,108 B of the 258,877 B under a node (19.7%) was deleted by a repair
anyway** — covered by a node *and* walked past. That is the size of the hole,
measured rather than argued, and it is why the seat's bound is canopy **minus**
those bytes rather than canopy.

---

## P5 — the majority resolves as instrument · **HELD**

Predicted over 60%; measured **88.5%**, consistent with the re-price's 81.1% on
the bytes it could test. The falsifier was under 40%.

## P6 — but the standing floor goes up · **FAILED, in the direction that costs us**

Predicted 1,500–6,000 B landing on a real refusal. Measured **+6,354 B** —
outside the band by 354 B, and outside it upward, so the parser owns slightly
more damage than I guessed rather than less. The floor is now **11,211 B**
against the re-price's 4,749–4,751 B, a 2.4x increase.

## P7 — a result of "essentially all instrument" should be disbelieved · **not triggered**

The trigger was over 95% instrument with under 900 B standing. Measured 88.5%
and 11,211 B. I would rather record that the trap was set and not sprung than
quietly drop the clause.

## P8 — swift dominates and verilog does not · **FAILED, and backwards**

Predicted swift over half the population. Measured: **verilog is 48,967 B of the
51,108 B papered (95.8%)** and 185 of the credited refusals; **swift is 490 B**
and 11. I reasoned from warm's frontiers, which are a fact about how far a
400-round budget got, not about how much file there is past it — and verilog's
file is 94,657 B where swift's is 28,468 B. Reading an instrument's own budget
as a property of the corpus is the same class of mistake this dossier is about.

---

## Who else was blind · P9, P10

### P9 — the board · **FAILED as stated; the hole is real and half the size I said**

Predicted over half of `built` downstream of the first repair. Measured
**111,557 B of 399,871 B (27.9%)** corpus-wide, and **61.9% across the fourteen
grammars that mend at all**. The falsifier was under 20%, so this is not
falsified either — it lands between, and the prediction was simply wrong about
the magnitude. `built` never claimed context; what changed is that the question
can now be asked.

**The board does not paper, and that is a result about its policy.** `papered`
reads **0 B** on every row — because `standing.py` parses `--mend=fell`, and
felling puts the stack down at a break so no construct root can reach across
one. That zero is a measurement rather than a silence, because the other policy
makes it enormous: re-read under `--mend=keep`, the same corpus builds
**+62,990 B** more, and **51,108 B (81%) of the gain is over bytes a repair
deleted anyway** — verilog alone is +61,445 B of it. Any lane tempted to switch
the default because `built` reads higher under `keep` is reading that.

### P10 — `tool/rack.py` · **FAILED, same direction**

Predicted over 30% of squared bytes downstream of a mend. rack indeed has **no
scar-aware column at all**, but the exposure is smaller than I said. `square` is
a subset of `built` and this lane knows which built bytes are downstream, so the
share is *bounded* rather than guessed: **between 61,942 B (19.9%) and 71,514 B
(23.0%)** of the corpus's 311,540 B of `square`. The falsifier was under 10%.

96 B of it is provably out of context by arithmetic alone — ruby, haskell and
markdown build nothing before their first repair. The walk that would close the
interval to a number is rack's, and this lane is not racing it: the finding is
that `square` wants a companion column, not that rack is wrong. Its docstring's
argument — that `square` is the one column a stretched root cannot buy — is
still true. A repair is not a stretched root, and this is the other question.

---

## P11 — against tree-sitter · **HELD, and the localization result is stronger than predicted**

`research/joinery/scars/against.py`, 29 of 30 grammars with a readable oracle
(yaml's parser will not compile in this seat).

| | tree-sitter | joints |
|---|---|---|
| enumerate every repair site | `ERROR` nodes in the tree, `MISSING` on the CST render | `--scars`, one line each — **level, after this lane; before it, we could not** |
| what each site carries | a span | byte range · refused terminal · refusing state · felled/kept · live heads · tokens since the last repair — **ahead** |
| repair by insertion | 70 `MISSING` nodes across the corpus | none — **behind**, and behind the *runtime*, not the reporting |

**Where we are ahead is localization, and verilog is the exhibit.** On the same
94,657 B file, tree-sitter marks 266 `ERROR` nodes that between them cover
**100% of the file** — its recovery lets an `ERROR` reach the root, which is
legal under its own contract and useless to a consumer asking "which bytes
should I not trust". Our scars cover **34%**. On sql the two surfaces nearly
agree on count — 16 `ERROR` nodes against 14 refusals that shifted ground — and
our spans are tighter, 245 B against 554 B.

**Where we are behind is a runtime capability, not a report.** Every mend here
deletes: drop the token, or put the stack down and stand it up in state zero.
Tree-sitter also *inserts* — materialising the token the grammar wanted,
zero-width — and reports it as `MISSING`. A `scar` never reports an insertion
because the runtime never makes one. Closing that is a change to `mended()`,
out of this lane's scope, and it is now a visible gap rather than an invisible
one.

### The row for the competitive scoreboard

**Twelve grammars we repaired and tree-sitter derived clean**: c, cpp, ruby,
bash, haskell, julia, kotlin, markdown, ocaml, scala, swift, zig — **1,929
scars over 2,169 B of files the oracle had no `ERROR` in**. That is our gap and
not the file's, and before `--scars` the only sign of it anywhere was a
`mended N` count in a verdict line with no location attached. A repair surface
that only ever reports the input's faults cannot find its owner's; this one
found 1,929 of them on the first run.

---

## The instrument I trust least

**`Seat.credited` — the rule that a repair which shifted no tokens since the
previous one is that one re-reported, and is not credited.** It decides
48,124 B, the single largest movement in the table, and it is the difference
between an 11,211 B standing floor and a 59,335 B one.

It passes its own check. `seat.py` refuses to print anything until every wall
the board already reached without this capability reproduces as the *first*
credited repair of its grammar, at the same byte — fourteen of fourteen, and it
is what caught the stale swift labelling above.

**That check cannot clear the cascade rule, and the reason is structural: the
first scar is credited by definition** (`i == 0 or s.since > 0`), so the one
population the self-check exercises is the one population the rule never
judges. Every byte the rule actually decides is a byte the check does not look
at. It is a presence rather than an absence, which is exactly why I gave it
precedence — and it is precedence over a different question than the one it
answers.

What I did instead of trusting it: printed the disputed answer beside the
undisputed one (59,335 B against 11,211 B), and printed the flattering policy's
answer beside both (70,330 B). A reader who thinks the cascade call is wrong can
read their own number off the same table without re-running anything.

Second on the list is my own `heads` field, which read **0 on every scar of
every grammar** for the whole of the first measurement pass and passed
everything, because a constant agrees with itself. It is fixed and reported in
`RESULT-1-surface.md`; what it cost me was the reminder that a field nobody has
plotted is a field nobody has tested.

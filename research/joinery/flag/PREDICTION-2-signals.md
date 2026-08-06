# Prediction 2 — does outliner already know which bytes it got wrong?

Written **before running `spans.py score` even once.** What I have run at this
point: `spans.py check` (81 of 81 tripwires held, so the walk is rack's walk),
and the totals off its cache — 384,715 built, 265,650 square, **60,138 hard
crooked**, 23,031 soft, 35,896 unaudited. I have not scored a single signal.

The populations the scoring will use:

    guilty     60,138 bytes  hard crooked        rack defends these as misread
    innocent  265,650 bytes  square + renamed    rack defends these as RIGHT
    excluded   58,927 bytes  soft + unaudited    the oracle said nothing usable

**Prevalence is 60,138 / 325,788 = 18.5%.** That is the number every precision
below has to beat to have said anything at all, and it is why the table reports
`lift` — precision over prevalence. A signal at 1.00 lift is a coin that happens
to fire a lot.

## The slate, and why each one is on it

Six signals, and **two of them are innocent controls I expect to fail.** The
brief asked for signals that would predict misreading; a slate made only of
suspects cannot tell a real hit from a corpus that is 18.5% guilty everywhere.

| signal | what it reads | suspect or control |
|---|---|---|
| `external` | a node on the spine is a terminal the grammar hands to a scanner | **suspect** |
| `mend0/16/64` | within N bytes of a boundary between two top-level roots | **suspect** |
| `forest` | the parse handed back more than one root, at all | **suspect** |
| `broad` | the deepest node is >= 64 bytes wide | **suspect** |
| `shallow` | the derivation over this byte is <= 3 rungs deep | control |
| `anon` | the deepest node is an anonymous token | control |
| `declared` | a node here is in a conflict the grammar's author declared | control |

`declared` is the sharpest control I have. It is the author saying *this
construct is ambiguous* — the thing a GLR parser exists for. If flagging it
predicted misreading, what I would have measured is "this grammar is hard",
not "this parse went wrong here", and the whole rung would be uninterpretable.

## What is NOT on the slate, and why — this is the honest half

The brief named five candidates. **Three of them I cannot measure from outside
`src/`, and saying so is part of the answer**:

- **GLR fork survivor counts, and forks that died late.** Nothing emits them.
  `OUTLINER_TRACE` has no lens for the weave, and the folio carries the press's
  conflict table, not a per-parse fork history. Unmeasurable offline.
- **A conflict resolved under duress** — an unranked fold that ordered an
  authored reading. `settle.zig` classifies these at press time
  (`residual` / `unwritten`), but the classification lives per LR *state*, and
  nothing in the parse output says which state reduced over which byte. I can
  see which *symbols* the grammar declares ambiguous (`declared`, above) and
  that is a much weaker thing.
- **A reduction where `inquest` would have named a wall one byte later.**
  Requires re-parsing every prefix of every file. Not offline; not this lane.

So the slate is what the tree itself carries plus the grammar's own
declarations. **If the answer is no, it is a no about these six**, and the three
above stay open — but they stay open behind an emitter another lane has to
build, which is exactly the cost the brief was trying to find out about first.

## P1 — `external` beats prevalence by 1.5x or better

The four widest `orphan` rows all stop on a blind external, and php's 25,394
crooked bytes are the largest single number in the corpus. A terminal outliner
seats with a stand-in rather than a real scanner match is a token whose extent
is a guess, and a wrong extent is a wrong parent.

**Falsifier:** precision below 27.8% (lift < 1.5).

## P2 — `mend0` has high precision and useless recall

Byte-for-byte, the region right at a fell boundary should be the worst-parsed
in the file. But a mend boundary is a *point*, and 60,138 bytes cannot live
next to one. I expect precision well above prevalence and recall in the low
single digits.

**Falsifier:** recall above 15% (then it is a real signal and I underrated it),
or precision below prevalence (then the boundary is not even locally bad).

## P3 — `forest` is worthless: high recall, lift near 1.00

"This file mended somewhere" is a per-FILE fact applied to every byte in it,
and 17 of 30 grammars mend. This is the exact shape the brief warns about — a
signal that fires on most of the corpus and catches everything.

**Falsifier:** lift above 1.3. That would mean mending files are so much worse
than non-mending ones that the file-level fact carries real information, which
would itself be worth reporting.

## P4 — at least two of the three controls stay quiet (lift <= 1.2)

This is the credibility test for everything above it. If `anon`, `shallow` and
`declared` all light up, my flag extractor is measuring "is this byte in php"
and nothing else.

**Falsifier:** two or more controls above 1.2 lift.

## P5 — no single signal reaches precision 0.50 at recall 0.20

The bar for "outliner can emit a calibrated untrustworthy span" — half of what
it flags is really wrong, and it catches a fifth of the damage. I predict
nothing on this slate clears it, and that the honest deliverable is a
specification for the three signals I *cannot* see rather than a claim about
the ones I can.

**Falsifier:** any signal at >= 0.50 precision and >= 0.20 recall. Then rung 2
is a yes on already-emitted data and the specification is much cheaper than I
think.

## P6 — the corpus-wide numbers are carried by php and elixir, and per-grammar
## they collapse

php (25,394) and elixir (17,660) are 71.6% of all guilty bytes. A signal that
happens to be common in those two languages will score well corpus-wide and
mean nothing. I predict at least one signal whose corpus lift is above 1.4 and
whose *median per-grammar* lift is below 1.1.

**Falsifier:** the corpus ranking and the per-grammar median ranking agree on
the top signal.

## What I most expect to be wrong about

P1. `external` is the signal the brief's own evidence points at hardest, and I
have written it down as a suspect while privately expecting it to fail — php's
crooked bytes may be one enormous `text` node that happens not to be external
at all. If it fails, the honest read is that the blind-external story explains
`orphan` (bytes never placed) and says nothing about `crooked` (bytes placed
wrong), and those are two different defects that have been sharing one
explanation.

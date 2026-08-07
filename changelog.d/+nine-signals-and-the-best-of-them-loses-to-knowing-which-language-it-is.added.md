A board that reads an oracle is not a parser that knows it is wrong. So the
question after the split was whether joints's own internal signals correlate
with the regions rack calls misread — if any did, joints could emit a
calibrated *untrustworthy* span, which is tree-sitter's `ERROR` except graded,
and covering the case tree-sitter has no node for: a region that parses cleanly
and is wrong.

`research/joinery/flag/spans.py` files every built byte by what the oracle said
and by what joints knew, and scores nine signals over 325,788 adjudicated
bytes with an 18.46% base rate. **The answer is no.** Best precision on the
slate is 29.0% (`declared` — a node in a conflict the grammar's author
declared). A control that reads *nothing about the parse at all* — whether the
byte is in php or elixir — scores 48.5% precision and 71.6% recall, 1.7x and
2.1x the best real signal. php and elixir hold 71.6% of all misread bytes, so
every apparent hit on the table is the corpus's composition wearing a parser's
clothes.

The per-grammar median lift column is what makes that legible: `declared` is
1.57 corpus-wide and **0.51** per grammar; `shallow` is 1.37 and 0.10; `forest`
is 1.44 and 1.00 on 0 of 16 grammars.

`check` proves the six buckets equal `rack.survey`'s own on every grammar
(81/81), but that is a claim about totals where every precision is a claim about
which bytes - and an attribution scrambled inside a grammar would pass all 81
tripwires while failing in the direction of the conclusion. So `score` closes
with a null: keep each grammar's guilty byte budget, spend it on a shuffled cut
order, re-score, five seeds. The doubt cleared and the table got worse.
`mend0` moves 1.32 away from its null, so the labelling is not noise - but
`forest` moves **0.00**, and `declared`, the best number on the page, scores
**1.70 scrambled against 1.57 real**. The two highest-scoring signals contain no
per-byte information at all; their lift is composition and nothing else.

Two results are worth more than the negative.

**`external` is empty, not weak.** 30,955 bytes sit under a terminal the grammar
hands to a scanner. 62 of them are misread — 0.2% precision, lift 0.01, roughly
90x *safer* than the corpus average. The evidence for this suspect was that the
four widest `orphan` rows all stop on a blind external. That is true and it
explains `orphan`, bytes never placed. It says nothing about `crooked`, bytes
placed wrong. Two different defects had been sharing one explanation.

**The mend signals are inverted.** Precision within 0/16/64 bytes of a root
boundary is 4.9%, 8.6%, 14.2% against 18.46% prevalence — monotonically
approaching the base rate from below. Mends do not mark bad regions; they mark
where joints *noticed*, and misreadings are by definition where it did not. A
flag built by widening the mend radius moves away from the target.

Three of the brief's five candidates could not be measured from outside `src/`
and stay open: GLR fork survivor counts, a conflict resolved under duress (an
unranked fold that ordered rather than erased an authored reading — `settle.zig`
classifies these per LR state, and nothing in the parse output says which state
reduced over which byte), and a reduction where `inquest` would have named a
wall one byte later. `spans.py` will score any of them on arrival. The bar is
2.63 lift, not 1.00: a signal that cannot beat "which language is this" has not
found anything about the parse.

Four of the six predictions written before the sweep failed, including the two
innocent controls that were supposed to stay quiet. That is what prompted the
identity control, and it is the reason nothing on the table can be read as a
hit. `check` asserts the per-byte walk reproduces `rack.survey`'s own six
buckets on every grammar (81/81); `prove` corrupts the scorer six ways,
including the one that matters — a flag firing on every byte scores 100% recall
at 1.00 lift, which is the exact shape a report would repeat as a success.

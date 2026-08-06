# stretch — the largest column on the board rested on one sentence

`stretch` and `airy` arrived carrying 79,628 bytes between them, **63% larger
than `damage` itself**, and both rested on a sentence the lane that shipped them
chose and could not check:

> *a leaf is a token, so whitespace between two tokens is under no leaf and is
> not a defect.*

Its own closing words were **"nothing in the repository adjudicates the
sentence."** Nothing in the repository does. The two prices it left standing were
**77,000 bytes apart** in the corpus headline, and three lanes were already
optimising verilog against one of them.

This lane asks the second parser instead. Tree-sitter's answer is **yes, and it
is my rule too**: a parent inherits its first child's padding and swallows every
later child's, each child's node starts *after* its own padding, and a node ends
at `start + size` - so on tree-sitter's own tree the space between two tokens is
inside every ancestor and inside no leaf. Outliner's `quire` says the same thing
in its own comment and implements it by refusing to let a child that consumed
nothing set the start.

**So the sentence survives and the column resting on it does not.** `airy` asks
whether a byte is a *space*; the sentence asks whether a *token* stands on it.
`survey` now asks the oracle: `warp` (a token they built and we did not), `slack`
(bare on both trees), `veiled` (the oracle declines), and `padding` (their own
hole, measured by the walk that measures ours). The adjudicated price is
**`owed = damage + warp`**, and the 77,000-byte swing closes at **163 bytes**.

| file | what it is |
|---|---|
| [`PREDICTION-1-adjudicate.md`](PREDICTION-1-adjudicate.md) | written before any of it was measured, including the two predictions that failed |
| [`RESULT-1-adjudicate.md`](RESULT-1-adjudicate.md) | the adjudication: tree-sitter's source, its output on real corpus bytes, `quire`'s own claim, the cross-tab, the corrected prices, the tripwires, and what I trust least |
| [`witness.py`](witness.py) | the cross-tab `rack` reports only as totals — per grammar, whose bare bytes they are and where the byte class and the oracle part company |

```text
eval "$(python3 tool/pin.py arm <name>)"     a sighted arm, or the oracle is absent and every row lies
python3 tool/rack.py run                     the board, with the STRETCH reconciliation under it
python3 tool/rack.py verify                  the tripwires, `adjudged()` among them
python3 research/joinery/stretch/witness.py  the per-grammar cross-tab and the tokens we owe
```

The third house rule in [`../TESTING.md`](../TESTING.md) is the one this lane
generalises: a pair that skips the arm has *read one arm twice, always agreeing
with itself, which is why nobody notices*. Two readers for one definition, both
written the same week, is that failure one level up - the arithmetic is checked
and the definition never is. So the adjudicator here is a parser this repository
did not write.

[`../unjudged/RESULT-9-verilog.md`](../unjudged/RESULT-9-verilog.md) is where
`stretch` and `airy` were born, and it is the honest one - it says outright that
nothing adjudicates the sentence. [`../budge/`](../budge/README.md) is the sibling
argument that a column which has only ever held one value is an assertion wearing
a measurement's clothes, which is why `warp` has a tripwire against reading zero.

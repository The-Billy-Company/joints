# Result 10 - the mutant population, pointed at a second instrument

Scores [`PREDICTION-3`](PREDICTION-3-price.md) job 4, and answers the question
the sibling sweep lane is currently building for: **which of `rack`'s reported
fields can actually take more than one value, and over what.**

[`liveness.py`](liveness.py) is 150 lines and reuses
[`rederive.brood`](rederive.py) unchanged. That is the whole claim about cost:
`brood` is a pure `bytes -> list[(tag, bytes)]`, so pointing it at a second
instrument is a temp file and a `plumb.Case`.

```bash
eval "$(python3 tool/pin.py arm shade)"
python3 research/joinery/unjudged/liveness.py           # both populations
python3 research/joinery/unjudged/liveness.py --corpus  # just the thirty rows
python3 research/joinery/unjudged/liveness.py go zig    # two grammars
```

## The bar a sweep sets is the wrong bar

Over the full corpus, **26 of 28 columns take more than one value**. Over 390
mutants, the same 26 do. On that bar the corpus looks like a perfectly good
population and the mutants buy nothing, which is why the report prints a second
number beside it.

**`firing` is how many rows the column is non-zero on**, and it is the bar that
matters:

| column | corpus | mutants | |
|---|---|---|---|
| `unjudged` | **2 of 30** | 146 of 390 | 73× the evidence |
| `mute` | **2 of 30** | 106 of 390 | 53× |
| `unwindowed` | **3 of 30** | 49 of 390 | 16× |
| `renamed` | **0 of 30** | **0 of 390** | dead on both |
| `shelter` | **0 of 30** | **0 of 390** | dead on both, by construction |

`unjudged` clears "takes more than one value" on this corpus with three distinct
numbers, and it stands on **two rows** - verilog and sql, both of them
tree-sitter's own `ERROR` subtrees, which is the previous lane's *two rows out of
thirty*. A column standing on two rows is a column whose next defect is found by
a dossier and not by a gate, and this dossier is the fourth in a row to be that
dossier.

The manufactured population multiplies the evidence under exactly the columns
the corpus starves, and under no others: the arms that fire on damaged input.

## Two columns are dead, and they are dead for opposite reasons

**`renamed` is 0 on all thirty corpus rows and all 390 mutants.** It is the
alias-excusal column - the same extent under a name the grammar's `alias` table
declares equivalent - and no real or manufactured input has ever produced one. It
has a tripwire, and that tripwire is synthetic: it hands `excused()` a
hand-built pair. So the column is exercised by a case somebody wrote and by
nothing else on earth. **This is the exact shape a "every field takes more than
one value" sweep is being built to catch, and neither population catches it** -
a mutant is still valid-ish source, and what `renamed` needs is a grammar that
aliases something the corpus file happens to use.

**`shelter` is 0 by construction and must stay 0.** It is a tripwire column, not
a measurement: how many of the disputed bytes the *active* price still files
`unwindowed`, which under the shipped rule is none. Its liveness is not bought
with inputs at all - `verify --price=sheltered` moves it to 1,486 immediately.

That distinction is the generalisation worth handing on. **A population is not
only a set of inputs.** `rederive.brood` manufactures inputs; `--price` and
`--oracle=<tag>` manufacture *rules*, and a column decided by a rule cannot be
woken by any amount of text. A sweep that only varies the corpus will report
`shelter` dead forever and will be right about the number and wrong about the
column.

## What else would benefit

The generator is cheap enough that the answer is "anything with an arm that only
fires on damaged input". Named, in the order the evidence says:

- **`plumb`** - the same `unjudged`/`ERROR` arms one level down, over the same
  two-row corpus, and it is `rack`'s own denominator.
- **`differential.py spans`** - already converted, and it is the precedent: its
  eighteen fixtures were the *same languages* as mutants that break the old
  reader, and not one had a syntax error in it. That is why the defect survived.
- **`standing.py`'s `spoil`/`rubble`** - both are "what did the parse throw
  away", and the corpus throws away almost nothing.
- **`attest`'s stale/absent arms**, which fire only when an oracle artifact is
  missing or old, and nobody's corpus is ever missing one.

## Predictions, scored

| | claim | |
|---|---|---|
| P4.1 | cheap, because `brood()` is already the whole generator | **right** - 150 lines, no change to `rederive` |
| P4.2 | the `ERROR` arms fire on 2 corpus rows, and on more than 15 mutant rows | **right, twice** - exactly 2, and 146 |
| P4.3 | at least one column that reads alive takes only one value | **right** - `renamed`, and `shelter` for a different reason |

Three of three, and P4.2's first half was the only number in this dossier I
predicted exactly.

## The instrument I trust least

**`rack.py`'s `stretch` and `airy`, and therefore the verilog reconciliation in
[`RESULT-9`](RESULT-9-verilog.md).**

They are the columns I wrote today, they carry the largest number on the board -
79,628 bytes corpus-wide, 63% larger than `damage` itself - and their whole
headline rests on a definition I chose: **a leaf is a token, so whitespace
between two tokens is under no leaf and is not a defect.** Change that one
sentence and verilog's honest damage goes from 62,888 to 67,058 and the corpus
from 129,836 to 206,555. Nothing in the repository adjudicates the sentence.

`verify` holds 28 of 28 and that does not clear it, for the same reason nineteen
tripwires did not clear the branch this lane was sent to fix: **not one of the
twenty-eight asserts anything about `stretch` or `airy`.** They are reported by
`board` and `whole`, they are checked for byte-equality across the two prices by
`reprice`, and that check would pass identically if both were computed wrong in
the same way. The `liveness.py` sweep above says they take 29 distinct values on
30 rows, which proves only that they are not constants.

What does carry a little weight is that `honest` reproduces independently:
[`reconcile.py`](reconcile.py) computes verilog's honest built from `plumb`'s own
node list by a different route and lands on 27,599, giving 67,058 - the same
figure `rack.py board` prints from the leaf mask, to the byte. Two readers, one
number. But both readers are mine and both were written this week, and the
agreeing thing is the arithmetic rather than the definition. **Anybody quoting
`text` should first check what `airy` calls whitespace against a file where it
matters - toml, whose 1,552 source-text stretch bytes are the largest on the
board and which no lane has looked at.**

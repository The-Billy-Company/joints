# Prediction 2 — presence as a node, not as bytes

Written before any of it was measured, on the same pin as Prediction 1.
`tool/absent.py` today, reproduced: **5,198 judgeable spellings, 2,050 present
(39.4%), 3,148 absent**, and 1,319 of 4,099 rules that spell something of their
own called impossible (32.2%).

## The flaw, in its author's own words

> A spelling counts present if its bytes occur anywhere, including inside a
> comment. **34 of 211 multi-byte spellings called present never occur outside
> a comment or string - 16.1%**, and 45.5% for css, 31.7% for scala.
> `ledger.scala` contains `true` 17 times and `false` 16 times and **not one is
> a `boolean_literal`.**

That author declined to intersect with the oracle, and the reason was good:
`absent.py` is the only reading available on the 34,687 built bytes where
tree-sitter itself ERRORs, and an instrument that needs an oracle cannot be
that. So the fix is **not** to replace the bytes reading. It is to add a second
one beside it and let the gap be the finding, exactly as that author asked for
and one step past where they stopped.

## The rule I am going to add

**A spelling is present as a node when some occurrence of its bytes is covered
by an oracle node named by a rule that spells it** - or by the name that
grammar aliases that rule to.

That is the shape that does not repeat the author's own detector's defect. Their
first pass flagged lua `--` at 44 occurrences and css `/*` at 71, which are
comment *openers* and of course sit inside the node they open. Under this rule
they stay present, because `comment` is a rule that spells `--`: the test is not
"is it inside a comment", it is "is it inside the thing that declares it".

Three ways it can be wrong, all of which must be held to the same floor the
bytes reading holds - it may miss an absence, never invent one:

- a rule that can **never be a node** - hidden by a leading `_`, in the
  grammar's `inline` list, or aliased at every use site - cannot witness
  anything, so a spelling whose every speller is one of those is
  **unwitnessable** and counts present, named;
- an occurrence under an oracle `ERROR` has no verdict over it and counts
  present, named;
- a grammar with no oracle at all gets **no node reading**, printed as such
  rather than folded in as agreement.

## The predictions

| | claim | falsified by |
|---|---|---|
| **Q1** | node presence over the oracle-reachable population is **below** the 39.4% the bytes reading gives | it landing at or above 39.4% |
| **Q2** | the drop is **at least 5 percentage points** | a drop under 5pp |
| **Q3** | scala's `true` and `false` come back **absent** as nodes - the row the author reduced by hand | either reading present |
| **Q4** | lua `--` and css `/*` stay **present**. This is the innocent control, and it is the exact pair that fooled the previous detector | either going absent |
| **Q5** | at least two grammars get **no node reading at all**, and my candidates are the two rack already refuses: verilog and sql, 34,687 built bytes between them | every grammar answering |
| **Q6** | **latex stays the lowest** of the twelve whole grammars, at or under its current 9.1% | any of the twelve reading lower |
| **Q7** | corpus-wide `impossible` **rises** above 1,319, because tighter presence starves more rule bodies | it falling or holding |
| **Q8** | **at least 500 spellings are unwitnessable** - spelled only by rules no parse can ever name. tree-sitter grammars hide a great deal behind `_` and `inline`, and if that population is large then the node reading covers materially less of the 5,198 than the bytes reading does, which is a cost and not a win | fewer than 500 |

**Q8 is the one I expect to hurt.** If it holds, the honest headline is not "the
number was 39.4% and is really lower" but "two readings, each blind where the
other sees", and the second is a worse sentence to write and a better one to be
true. I am predicting my own fix buys less coverage than it looks like it buys.

## What would make me distrust the result

A grammar whose node presence *rises*. That is arithmetically impossible under
the rule as stated - a node-covered occurrence is still an occurrence - so if
one rises I have a bug in the alias or unwitnessable handling and the whole
column is suspect, not just that row.

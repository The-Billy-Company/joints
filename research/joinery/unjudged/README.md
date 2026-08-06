# unjudged - the row nobody could score

Verilog carries the largest damage figure in the corpus, 63,937 bytes, and three
lanes spent a day working it. It also contributed **zero adjudicable bytes**:
`rack` asked its oracle for a tree, the oracle's two renders disagreed, and
every one of verilog's 30,720 built bytes was filed `unjudged` - a state the
board printed nowhere. So `damage` was the only instrument left on the row, and
`damage` is outliner's own words about its own forest.

[`PREDICTION-1`](PREDICTION-1-disagreement.md) was written before anything ran
and covers all of it - the diagnosis in P1.1-P1.6, the sweep in P1.7, the
re-pricing in P1.8-P1.9. Every one of the nine is scored in
[`RESULT-1`](RESULT-1-disagreement.md), including the load-bearing one that
named the wrong mechanism. [`RESULT-2`](RESULT-2-repricing.md) carries the
sweep and the re-priced verilog row.

A second lane then re-derived the headline this one asked nobody to trust, and
closed the four loose ends it left. [`PREDICTION-2`](PREDICTION-2-rederive.md) is
its predictions, written first and scored **ten of fourteen**:

| | job | result |
|---|---|---|
| 1 | re-derive the 611 by a route that is not `indents()`, then harden the reader against fixtures nobody chose | [`RESULT-3`](RESULT-3-rederive.md) · [`rederive.py`](rederive.py) |
| 2 | reconcile 63,937 against 49,446, 8,175 and the peel's 6,591 | [`RESULT-4`](RESULT-4-reconcile.md) · [`reconcile.py`](reconcile.py) |
| 3 | the elixir `engulf` tripwire whose precondition a sibling dissolved | [`RESULT-5`](RESULT-5-tripwire.md) |
| 4 | haskell's 1,013 | [`RESULT-6`](RESULT-6-residue.md) · [`unwindowed.py`](unwindowed.py) |

Headlines: **611 survives, exactly**, by a route with no indentation arithmetic
in it. The verilog record's arithmetic was **three instruments and a
counterfactual**, and the 6,316/6,591 match is a coincidence twice over. The
tripwire is re-pointed at the **corpus** rather than a named row and `verify`
holds **19 of 19**, with the press change that killed it confirmed **in flight,
elixir's baseline moved 66.75 points**. And haskell's 1,013 were never
`unjudged` - they are `unwindowed`, which is 97.9% `unframed`'s own population
under a name that reads like silence.

A third lane then made the change the second one escalated rather than made.
[`PREDICTION-3`](PREDICTION-3-price.md) is its twenty claims, written first:

| | job | result |
|---|---|---|
| 1 | charge a byte under a frame we never built, without a flag day | [`RESULT-7`](RESULT-7-price.md) |
| 2 | the tripwire for the branch nobody tested, and the other branch orders | [`RESULT-8`](RESULT-8-branches.md) |
| 3 | reconcile the board's verilog damage with the honest one | [`RESULT-9`](RESULT-9-verilog.md) |
| 4 | point the mutant generator at a second instrument | [`RESULT-10`](RESULT-10-liveness.md) · [`liveness.py`](liveness.py) |

Headlines: **1,486 of 1,512 bytes move from silence to a charge over nine rows,
and `square` does not move on any of the thirty** - the twenty-one untouched
columns are computed from `Seen._fields` rather than claimed. `--price=sheltered`
re-derives any held baseline exactly, every board says which rule priced it and
carries a digest of that rule, and `rack.py against` refuses across a rule change
at exit 4 before it sweeps. `verify` holds **28 of 28**, and restoring the branch
order turns **exactly one row red** while all twenty-seven others stay green. The
same overlap exists in `unjudged` at 3,735 bytes and deliberately does not move,
because 100% of it arrives through the `ERROR` arms. And verilog's honest damage
reconciles at **62,888 bytes of source text**, not 68,119: the missing population
is real and it is **96.3% indentation**.

## What it was

`tree-sitter parse --cst` does not indent two spaces a level. It indents two
spaces a level **plus one further space for a node inside an error subtree that
does not itself carry an error**, and its range prefix is a width the render
never states. Our reader took the body column as pure indentation under a
whole-render `shift` of one or zero, so a clean node inside an error read a
level too deep and the bulleted sibling after it got adopted by the wrong
parent. No constant can undo a per-row perturbation, so `reconciled` tried both
readings, agreed with neither XML, and refused. `indents()` now inverts the
CLI's own arithmetic instead of guessing at it.

Second, smaller defect: `--cst` prints an inserted anonymous token as
`MISSING: "kind"` and `cst_tree` marks it named so repairs stay countable, so it
survived into `named_only()` facing an XML that has no element for it. Twenty-one
inserted semicolons in verilog.

Both are in [`tool/differential.py`](../../../tool/differential.py). Neither is
in the oracle.

## What it cost, and what it bought

| | before | after |
|---|---|---|
| corpus unjudged | 35,837 of 396,158 built - **9.05%** | 5,564 - **1.40%** |
| verilog | 30,720 - **100% of built** | 4,293 - 14.0% |
| sql | 3,967 - **100% of built** | 121 - 3.1% |

Verilog, adjudicated: **611 square** of 30,720 built and of 94,657 bytes on
disk - 2.0% of what it builds, 0.6% of the file - against 13,237 crooked and
12,579 unframed. Half of every judged byte is a right leaf under a wrong parent.

The board grew an `unjudg` column
([`tool/standing.py`](../../../tool/standing.py)) so a row that cannot be scored
says so on its face, and `rack run` grows a `NOT JUDGED` block
([`tool/rack.py`](../../../tool/rack.py)) that names any row over 5% blind, with
its share, and calls out a whole refusal separately. It fires on the share
rather than on the mechanism, because the block it replaces was keyed on
`Seen.why` and so was silent for a row refused byte by byte. Pointed at the
pre-fix reader it says exactly what three lanes needed:

```text
NOT JUDGED - 35837 of 396158 built bytes (9.05%) carry no oracle verdict.
  sql        3967  100.0% of 3967   tree-sitter's CST and XML disagree with each other
  verilog   30720  100.0% of 30720  tree-sitter's CST and XML disagree with each other
  haskell    1013   11.0% of 9192   plumb rule, byte by byte
  2 row(s) above were refused WHOLE: no square, no crooked, no unframed. `damage`
  is then the only instrument left on the row ... Do not rank work off it.
```

## The falsifier

The reader has a gate - `differential.py spans` - and it had eighteen fixtures,
**not one of which contained a syntax error**. The perturbation only exists
inside an error subtree, so the gate could not have caught this and never did.
Five error shapes now live in [`../spans/errors/`](../spans/errors), a
reconciliation refusal is a `BROKE` there rather than a shrug, and each fixture
catches exactly one of the two defects:

| reader | broke |
|---|---|
| as shipped | 0 |
| pre-fix, both defects | 2 |
| pre-fix columns only | 1 (`01-error-under-a-clean-parent`) |
| pre-fix `named_only` only | 1 (`03-missing-token-under-a-named-parent`) |

**Five of those twenty-three fixtures were authored by the lane they cleared**,
which is why the second lane replaced the population instead of adding to it.
`rederive.py mutants` generates it: 390 mutants over 30 grammars, 222 of them
error-bearing over 27, and it is the corpus that turns out to be the weak
population - tree-sitter's own tree has an `ERROR` or a `MISSING` in it on **two
rows out of thirty**. The shipped reader disagrees with the column-free tree on
none of them; the reader at git HEAD, which predates the fix, refuses 21 of 72.
`--was <rev>` prints `VACUOUS` and exits 1 rather than passing when the named
revision answers identically, so the gate says on its own face when it has
stopped being a falsifier.

## Housekeeping for whoever reads this next

- Arm `unjudged`, tree `05a18fcd1`, binary `94d59d9ad`, tree-sitter 0.26.11.
  Before/after are the same arm with only the reader swapped, so no parse
  changed and `built` is identical to the byte on all 30 rows.
- `rack verify` holds **19 of 19**. It held 18 of 19 for a day: elixir's `engulf`
  tripwire, whose precondition (`elixir's unframed > 0`) was dissolved by a press
  change on another lane. It is now asked of the corpus rather than of elixir -
  see [`RESULT-5`](RESULT-5-tripwire.md), which also says what elixir's baseline
  did and whether the press change is committed. **It is not.**
- `indents()` inverts one version's undocumented implementation. If the CLI
  changes its indent rule this reader is wrong again, and `spans` will say so on
  five shapes. That is the trade and it is deliberate.

## The instrument I trust least

**`indents()`, and therefore verilog's 611 square bytes**, because everything
downstream of this lane rests on a reader I wrote today.

It passes `differential.py spans` - 23 shapes, 3 readers, none broke. That does
not clear it, and it is important to say why: **I wrote five of those twenty-three
fixtures, after I had the diagnosis, choosing shapes I already knew the mechanism
would hit.** A gate whose hardest cases were authored by the person who knew the
answer is evidence agreeing with itself by construction, which is the exact
failure this tree has retired six instruments for today. The eighteen fixtures I
did not write are all clean javascript and cannot touch this defect at all - that
is how it survived in the first place.

What does carry weight is the one thing I could not have tuned: swept over all
thirty grammars, the pre-fix oracle refused **exactly** the rows where `cst_tree`
independently reported `hurt`, and read the other 27 byte-identically under both
readers. Biconditional, over a population I did not choose, predicted by the
mechanism before it was run. And the two renders are two faces of one parse, so
`same()` against the XML remains the falsifier the CST has to survive - a reader
that guessed would fail it, not pass it quietly.

But `same()` is a *shape* check. It confirms that the tree I now build has the
named shape the XML nests, and the XML is unambiguous, so a wrong reading is very
unlikely to be a silently plausible one. "Very unlikely" is not "cannot", and
611 is a small number to hang on it. Anyone re-running this should re-derive
verilog's square count from the XML path alone before quoting it.

**That re-derivation happened and 611 stands** - see
[`RESULT-3`](RESULT-3-rederive.md). The second lane's own least-trusted
instrument is a different one and it is named at the end of
[`RESULT-6`](RESULT-6-residue.md)'s neighbourhood: `rack.survey`'s branch order,
which decides `unwindowed` before it ever asks whether the frame is one we
failed to build, and which therefore reads a charge against us as the oracle's
silence. It passes every one of its nineteen tripwires, and passing them cannot
clear it, because not one of them asserts anything about that branch.

**That branch has been re-pointed** - see [`RESULT-7`](RESULT-7-price.md) and
[`RESULT-8`](RESULT-8-branches.md), which also carry the eight assertions that
would have caught it and the audit of the three branches beside it. The third
lane's own least-trusted instrument is named at the end of
[`RESULT-10`](RESULT-10-liveness.md).

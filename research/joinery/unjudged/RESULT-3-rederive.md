# Result 3 - the 611, re-derived without reading a column

Scored against [PREDICTION-2](PREDICTION-2-rederive.md) P1.1–P1.5. Arm
`unjudged` (`outliner 94d59d9ad`, tree `05a18fcd1`, repo `f7ba40004+132`,
tree-sitter 0.26.11, oracle `d85e736fa`). Tool:
[`rederive.py`](rederive.py).

> **611 survives. Exactly 611, on a route with no indentation arithmetic in it,
> and the two readings of tree-sitter's tree are identical over all 48,804 nodes
> of positive width - name, `named` flag, both offsets and depth.**

## The route

`indents()` decides one thing: **parentage**. Every name, every `named` flag and
both offsets of every CST row come from that row's own text and range prefix, so
the only channels by which a wrong indentation can reach `square` are the `depth`
tie-break in `inorder` (which bites only between two rungs sharing an extent) and
`Node.leaf`, which enters the `unjudged` rule as `not them.leaf and t_bad[p]`.
That is P1.1 and it held; the 11-byte drift below arrives through the second
channel exactly as predicted.

So the second reading takes parentage from somewhere else entirely:

| face | what it gives | columns in it |
|---|---|---|
| `parse -x` | every **named** node, nested unambiguously, with `srow/scol/erow/ecol` | none |
| `query` over every anonymous type in `node-types.json` | every **anonymous** node's span | none |

Anonymous nodes are tokens, so they are always leaves, and a leaf's parent is the
narrowest named node containing it. Nothing is guessed and no column is read.

**The XML carries ranges.** That is the fact the first lane missed and the reason
this took an afternoon rather than a week: `xml_tree` already parses
`srow/scol/erow/ecol`, so the named half of the oracle never needed the CST for
anything. `reconciled` asserts the CST's named shape against it on every row that
gets a verdict at all, so `indents()`'s real freedom was always **where anonymous
nodes attach**, and that is precisely what a query settles from the outside.

## Verilog

| | CST reader | XML + query | moves |
|---|---|---|---|
| nodes | 48,883 | 48,883 | - |
| of positive width | 48,804 | 48,804 | 0 in either direction |
| **square** | **611** | **611** | **0** |
| askew | 1,125 | 1,125 | 0 |
| racked | 12,112 | 12,102 | −10 |
| unframed | 12,579 | 12,578 | −1 |
| unjudged | 4,182 | 4,193 | +11 |
| their_nodes / shared | 17,195 / 15,172 | 17,195 / 15,172 | 0 |

The eleven bytes are the **67 zero-width `MISSING` tokens** and nothing else.
A token of no width has no extent for containment to place it by, so the
column-free route attaches it by the only rule available and names it by its
anonymous type (`;`) where the CST names it `MISSING ;`. Neither paints a byte -
`plumb.paint` and `plumb.hurt` both skip an empty span - so neither can reach
`square`; what moves is `Node.leaf` on the named node that adopted one, which
flips eleven bytes into the `not them.leaf and t_bad[p]` arm. Predicted channel,
bounded population, 0.036% of `built`, and `square` is not one of the columns it
touches.

## The corpus, not just verilog

`rederive.py corpus` reads all thirty rows both ways:

- **29 read** (yaml builds nothing, so there is no row to price).
- **0 node-multiset mismatches**, on any row, in either direction.
- **`square` is identical on all 29.**
- **28 of 29 rows are identical in every column**; verilog is the one that moves,
  by the eleven bytes above.
- Two rows - sql and verilog - have an `ERROR` or a `MISSING` in tree-sitter's
  own tree. **Two of thirty.** Which is the next finding.

## Hardening: the population was the whole problem

The gate this reader had is `differential.py spans`. Eighteen of its fixtures are
clean javascript and cannot reach a defect that only exists inside an error
subtree; five were written by the lane that already had the diagnosis. But the
corpus is barely better - it puts an error subtree in the oracle's tree on **two
rows out of thirty**. Neither the fixtures nor the corpus is evidence here.

`rederive.py mutants` manufactures the population instead of choosing it: each
corpus file truncated to 6,000 bytes, then a 24-byte excision and a hostile
insertion at each of six offsets a seeded LCG picks. Whatever error subtrees come
out are the shapes that grammar's own recovery makes.

| | |
|---|---|
| mutants | **390**, across **30 grammars** |
| read | 349 (41 raised - see below) |
| **error-bearing** | **222, across 27 grammars** |
| shipped reader vs the column-free tree | **0 disagreements** |
| `reconciled` refusals | **0** |

And the arm that makes it a gate rather than a decoration - the same mutants read
by `tool/differential.py` **at git HEAD**, which predates the fix:

| population | shipped reader | reader at HEAD |
|---|---|---|
| 78 mutants · 6 grammars (verilog sql javascript kotlin julia zig) | 72 agree, 0 differ | **21 refused** |
| 26 mutants · 2 grammars (sql javascript) | 26 agree | **15 refused** |

**Javascript is the sharp one.** The eighteen fixtures that could not touch this
defect are javascript, and javascript mutants break the old reader on 2 of 13 -
so the shape was reachable from the same grammar the whole time. The fixtures
were not the wrong language. They were the wrong *state*: not one of them had a
syntax error in it.

`mutants` refuses to be vacuous: `--was <rev>` names the other reader, and when
that revision answers exactly as this one does on every mutant, the run **says
`VACUOUS` and exits 1** instead of passing. Once this fix is committed, HEAD
stops being a falsifier and the gate will say so on its own face rather than
going quietly green - which is the failure mode Job 3 was about.

**41 mutants raised rather than answering, and the reason is worth stating.** 28
are one per grammar: the mutant that jams a NUL byte, which makes tree-sitter's
own `-x` output ill-formed XML. That is a limit of the *route*, not of the reader:
the CST reads those files fine, - so the NUL is now `~~` in `NOISE` and a
rerun covers them. The other 13 are yaml, whose scanner does not compile in this
seat at all.

## Scoring

| | claim | verdict |
|---|---|---|
| **P1.1** | `square` is a function of the bracket multiset; `indents()` reaches it only via the `depth` tie-break and `Node.leaf` | **held** - and the only drift on the board arrives through `Node.leaf`, exactly as named |
| **P1.2** | `parse --dot` is an independent route and recomputing `square` from it gives exactly 611 | **failed, and usefully.** The number is right - 611, by another route. The route is wrong: `--dot` prints tree-sitter's **internal** subtree tree, so it carries hidden rules, *unresolved aliases* (`simple_identifier` where the CST has `parameter_identifier` over it), and start offsets padded differently. Reconstructing the visible tree from it means reimplementing tree-sitter's own alias and visibility resolution - a third reader with a third set of defects. Abandoned deliberately; see below. |
| **P1.3** | the first hidden-node filter is necessary and not sufficient, and the extra rule is `MISSING`/`ERROR` spelling **or aliases** | **held on the naming, wrong on the size.** Aliases were the mechanism. But `inline` is not `invisible` - `parameter_identifier` is in verilog's `inline` list *and* visible in the CST, because it is an `ALIAS` over `_identifier` - and once aliases are in play the gap is not one further rule. |
| **P1.4** | the named half was never at risk; anonymous-node parentage is the whole residual freedom; **0** disagreements on verilog | **held, and now measured rather than argued.** The XML's 38,243 named nodes are the CST's 38,310 named nodes minus its 67 `MISSING` tokens, identical including depth; and 0 of verilog's 10,573 anonymous nodes attach differently. |
| **P1.5** | generated cases produce error-bearing trees on **≥ 20 of 30** grammars; the shipped reader survives all; the pre-fix reader breaks on a **minority, 20–60%** | **held on both numbers.** 27 of 30 grammars, and the pre-fix reader refused **21 of 72** (29%) on the six-grammar run. A generator that broke every case would have been one I had tuned. |

Four of five, with P1.2 the interesting failure: it named a route rather than a
mechanism, and the route was the one thing I had not checked before predicting.

## What I would tell the next lane

**Do not use `--dot`.** It looks like the ideal witness - explicit `parent ->
child` edges, byte ranges in the tooltips, no columns anywhere - and it is a
render of a different tree. Two hours went into it. `-x` plus a query is the
route, and it was available the whole time because the XML has carried ranges
since before any of this.

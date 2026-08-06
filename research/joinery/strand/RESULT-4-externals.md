# Result 4 — the external-declaration census, re-measured

The brief: *"`research/joinery/owners/closure.py`'s external-declaration filter
tests `type in ("SYMBOL", "STRING")` and so drops two `PATTERN` externals —
bash's and haskell's `\n`, both of which are walled. The real population is 23
declarations across 9 grammars, not 21 across 8."*

**The count is exactly right. The defect is not there, and the two are not
walled.** What was wrong was the prose describing the code.

## The code was already total

`declared()` reads:

```python
if e.get("type") == "SYMBOL":
    out.update({e["name"]} if "name" in e else ())
elif literals:
    out.update(names(e))
```

A `SYMBOL` answers to its name; **everything else** goes through `names()`,
which renders `PATTERN` fine. There is no `("SYMBOL", "STRING")` filter anywhere
in the tree — `grep` finds none. The docstring two paragraphs down had already
argued against writing one, by name:

> The dossier that found this proposed `type in ("SYMBOL", "STRING")`, which
> still drops the two `PATTERN` externals the corpus holds […] Listing the shapes
> someone has already met is how the first spelling of this line got it wrong.

So the hole was closed before this lane arrived. It looked open because
**`research/joinery/owners/` is entirely untracked** (`git status` reports `??`
on the directory), which is the same reason the brief believed `--holding` had
never existed. Two of this lane's four tasks were briefed off a stale read of an
uncommitted file. That is worth more than either task.

## What was actually stale: the numbers, in two places

The docstring said the narrow read "dropped **21 of them across 8 grammars**".
Measured with `owners.py --externals`:

| unit | count |
|---|---:|
| non-named declarations | **23 across 9 grammars** |
| the spellings they carry | **31** |
| declared by shape | 461 `SYMBOL`, 21 `STRING`, 2 `PATTERN` |

`21 across 8` is neither of those. It is the count **under the
`("SYMBOL", "STRING")` filter the code refuses** — 23 declarations minus the 2
`PATTERN`s, and haskell drops out of the grammar count entirely because its only
non-named external is the pattern. A counterfactual quoted as if it described the
live population.

Both sites are corrected, and `--externals` now prints declarations and spellings
as separate columns with a line saying they are different units, because that
conflation is what produced the stale sentence. It also prints the by-shape
census, so a third shape appearing upstream is visible without anyone re-deriving
it.

## Re-pricing: 0 bytes of 181,588

The brief expected this to be small and cited a 524-byte precedent. It is
smaller than that: **zero.**

Measured over the whole 170-wall survey, through `spellings()` — which is what
`verdict()` actually tests, rather than by reading terminal names:

> walls whose verdict the `("SYMBOL", "STRING")` filter would move: **0**
> bytes re-priced: **0**

Neither `\n` is the terminal of any wall, and no walled terminal's kin set
reaches one. Bash has exactly two walls, `] in state 35` (scanner, 495 B — the
one the docstring already cites) and `[ in state 1163` (stranded, 8 B).
Haskell's 56 walls are all withheld anyway: its control is 94%, below the 95%
floor.

**So "both of which are walled" is false.** Both are *in grammars that have
walls*, which is a much weaker statement and the one now in the docstring.

## Why the shape is still right

Totality is worth 0 bytes today and should be kept anyway. The argument for it
is that a declaration is a declaration whichever shape it is written in — not
that it paid. Bash's `]` is what the same argument was worth the one time it did
pay: 495 bytes published as a grammar gap for an afternoon.

The honest price is now recorded in the docstring beside the argument, so nobody
re-derives it and nobody quotes it as a win.

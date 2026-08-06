# Handoff — `crooked` goes negative because `soft` is drawn from a kind it cannot spend

**Not fixed here.** The arithmetic is one line of `tool/standing.py` reading one
function of `tool/rack.py`, and `rack.py` is another lane's this hour. Which of
the two lines is the wrong one is a semantic call for that lane, not a
subtraction I should make on the way past. Below is the reproduction, the cause
and the cheapest evidence that narrows it.

## It reproduces, and it is much larger than −335

Three of twenty-one boards in `RESULT-8-sighted.md` carry a negative `crooked`.
All three are scala, and all three are arms with **scala's row 4**
(`block_comment/.marrow/.kotlin_block`) ablated:

| arm | grammar | crooked | roots | unframed | soft |
|---|---|---|---|---|---|
| r4 | scala | **−8,669** | 1,273 | 12,287 | 9,687 |
| r0-4 | scala | **−8,279** | 1,261 | 11,115 | 10,217 |
| union | scala | **−8,279** | 1,261 | 11,115 | 10,217 |

The board's own consistency check passes on all three, because the five buckets
still total `built`: `203 + (−8,669) + 9,687 + 12,287 + 42 = 13,550 = built`.
A bucket that overdraws from its neighbour leaves the sum alone, and the check
was written to catch a redefinition of `built`, not a redistribution inside it.

## The cause

`standing.audit()`:

```python
soft = sum(w.width for w in seen.worst
           if not saw.blob[w.start:w.end].strip() or w.ours in was or w.theirs in was)
out[case.name] = Held(seen.square + seen.renamed, seen.crooked - soft, soft, ...)
```

`seen.crooked` is `askew + racked` and **deliberately nothing else** —
`rack.Seen.crooked`'s own docstring says so, so that no quoted figure quietly
grows. But `seen.worst` is `rack.widest()`, which returns the widest runs **of
each kind**, and `unframed` is one of the kinds. So the sample is drawn from
`askew + racked + unframed` and subtracted from `askew + racked`.

`rack.widest()`'s docstring predicts this exactly:

> `soft`, which reads these as its sample of `crooked`, would silently start
> reading a different population than the column it divides into.

It is already reading it. The docstring names the hazard and the caller walks
into it.

**Why scala's row 4 in particular.** Un-seat the block-comment vein and scala's
comment prose stops being recognised, so tree-sitter frames construct after
construct that we never build — `unframed` goes 131 → 12,287. Every one of those
frames is named `comment`, which *is* a declared extra, so `w.theirs in was`
qualifies **all of them** as soft. `soft` becomes an approximate copy of
`unframed` and is charged against a `crooked` of 1,018.

## The measurement, and the number that identifies which line is wrong

`borrow.py` re-runs `standing.audit()`'s soft rule with the run's **kind** kept,
and prints what the charge would be if the sample were restricted to the kinds
`crooked` contains:

```
  grammar    built  askew+racked   soft  charged  restricted   soft drawn from
  scala      13550          1018   9687    -8669         988   askew 30, unframed 9657
             overdraw 9657 bytes from a kind `crooked` does not contain: ['unframed']
```

`charged` is what the board printed. `restricted` is +30. The whole −8,699-byte
excursion is nine thousand six hundred and fifty-seven bytes of `unframed` runs.

## It is not a scala curiosity — six rows of the base board are affected now

Same probe over the **base** arm, where nothing is negative and everything looks
healthy:

| grammar | askew+racked | soft | charged | restricted | drawn from |
|---|---|---|---|---|---|
| cpp | 591 | 38 | 553 | **591** | unframed 38 — *the entire sample* |
| haskell | 2,174 | 799 | 1,375 | **2,074** | unframed 699 of 799 |
| ocaml | 2,184 | 101 | 2,083 | **2,113** | unframed 30 |
| julia | 160 | 3 | 157 | **160** | unframed 3 — *the entire sample* |
| sql | 179 | 3 | 176 | **179** | unframed 3 — *the entire sample* |
| swift | 9,667 | 927 | 8,740 | **8,754** | unframed 14 |

**haskell's `crooked` is understated by 699 bytes — 34% of its real value — on
the board as it stands.** The negative is only the tail that got large enough to
cross zero; the same overdraw is silently shrinking `crooked` on a fifth of the
board, always in the flattering direction.

## What the owning lane has to decide

Two defensible fixes, and they are not equivalent:

1. **Restrict the sample.** `soft` becomes a partition of `crooked` and nothing
   else — `if w.kind in ("askew", "racked")`. Preserves what every quoted
   `crooked` figure has ever meant; blank and extra-named *missing frames* then
   sit in `unframed` uncorrected.
2. **Keep the sample and move the subtraction.** A blank or extra-named
   `unframed` run is arguably soft in exactly the sense the column means, in
   which case the overdraw should come out of `unframed`, not out of `crooked` —
   `soft` becomes a partition of `crooked + unframed`.

Both are one line. The choice is about what `soft` is a sample *of*, which is
`rack.py`'s question. **`borrow.py` prints the number either fix has to produce**
(the `restricted` column), so whichever is chosen can be checked rather than
asserted.

## And one falsifier worth adding while you are in there

The board's fourth assertion now fires on a negative. It fires *after* the
excursion has already crossed zero, so it catches the 8,669 and misses the 699.
The check that would catch both is the one `borrow.py` is: **`soft` must be a
subset of the population it is subtracted from.** That is checkable without
running the oracle twice, and it is not a threshold.

Reproduce:

```
OUTLINER_BIN=.local/sighted/scratch2/.local/pin/r4/bin/outliner \
OUTLINER_WORK=.local/sighted/scratch2/work-r4 \
python3 research/joinery/consort/borrow.py scala
```

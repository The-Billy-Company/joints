# Result 2 — the flattering number inside this fix, and one in the brief

Six lanes have found a flattering number inside their own fix. The brief told
me to expect to be the seventh. I was. There are two here: one I wrote, and one
I was handed.

---

## Mine — a displacement that depended on how you asked for it

The third check prints how far ranking by `roots` moves a grammar from where
`damage` puts it. Shipped, it printed this:

```
default sort   scala 10 place(s) from where `damage` does
--damage       scala  9 place(s) from where `damage` does
```

Same corpus, same binary, same run of the parser. Two numbers.

`checks()` sorted the rows it was handed, and Python's sort is stable, so ties
broke on **the order the rows arrived in** — which is the display order the
`--damage` flag had just set. The check was reading its own presentation back
as a fact about the corpus.

It is small (one place, on one grammar) and it is the exact defect this lane
exists to fix, one bucket lower: a number that reports something about the
instrument while looking like it reports something about the thing measured. A
lane that ran the board twice with different flags and saw 9 and 10 would have
had no way to tell which was true, because neither was.

Fixed by breaking both ties on the **name**. The number is now 10 under all
four sort flags. What makes this worth writing down rather than quietly
correcting is that **no test would have caught it**: the check said `CHECK` in
both runs. It was found by reading two terminal outputs side by side, which is
the same way twenty-one of the twenty-two flattering instruments here were
found.

**The generalisation, which I have not audited:** any board function that takes
`rows` after `table()` has sorted them, and sorts again on a key with ties, has
this bug available. `checks()` was the one I wrote today. `tally()` sorts within
groups by `damage`, which is unique per group here but not by construction. I
have made `tally()`'s sort break ties on the name too rather than leave a second
one standing.

---

## The brief's — 71.30% is a forecast, not a corrected reading

The brief says:

> The corpus headline under the corrected view would read **67.37% → 71.30%.**

The corrected view does not move the headline, and it must not. `damage` is
`size − built`, so `damage / size` is **exactly** `1 − standing`:

```
damage 171,905 / 526,798 = 32.63205251%
1 − standing            = 32.63205251%
```

To the eighth digit, because it is the same subtraction. `damage` redefines
nothing, adds no bucket, and is not a second opinion about the corpus — it is
the headline's own complement, spelled in bytes so it can be sorted. The
headline stays **67.37%**, which is what the brief itself asked for: a headline
that silently redefines itself is the same crime one bucket lower.

So where does 71.30% come from? It is `research/joinery/orphan/`'s **kotlin
ablation, projected onto the corpus**. Blanking kotlin's 45 string literals
moved `built` 14,841 → 35,569, a gain of 20,728 bytes:

```
(354,893 + 20,728) / 526,798 = 71.3027%
```

That is 71.30% to four digits. It is a **repair forecast for one grammar**, and
a good one — but it is contingent on a wall nobody has torn down yet, where the
corrected ranking is arithmetic on a board already taken. Conflating them would
put a number the corpus has never printed next to a number it prints on every
run, and a later lane would reasonably read 71.30% as achieved.

The distinction matters for dispatch. **The re-ranking wins nothing.** It
redirects effort that was already being spent; the corpus is exactly as damaged
as it was this morning and the headline says so. What it buys is that the
effort now goes to kotlin's 20,974 bytes instead of past them.

For the record, the same projection over all three grammars the brief names, if
their orphan became built: 73.41%. Also a forecast, and stated as one.

---

## Near-miss, inherited and re-confirmed

`research/joinery/orphan/RESULT-2-wall.md` found `_import_dot` fires two mends
and is worth **zero bytes** — moving orphan the wrong way — and that it is
exactly the terminal `inquest` names once the strings are gone. A lane
following the verdict line would have confidently fixed nothing.

The board does not repeat that mistake, but it does not detect it either. The
`most` grouping is arithmetic on three columns and the verdict text beside each
row is printed **as the grammar's own words**, not parsed. That means the board
puts `_import_dot`-class rows in the right group by bytes while showing a
stand-in name that may be a guess. It shows the guess and marks it one; it
cannot tell you the guess is wrong. Whoever takes a dispatch off the `orphan`
group should read the verdict as a location, not a diagnosis — which is the
first line of the brief's own list of instruments that lie.

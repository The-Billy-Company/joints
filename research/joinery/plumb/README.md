# plumb — is a `built` byte built *right*?

Every bucket on the board measures **placement**. `built`, `orphan`, `rubble`,
`spoil` all answer *where did this byte end up*, and none of them answers
*should it have*. A wrong tree and a right tree are both trees, so a comment
read as arithmetic costs zero mends, yields one clean root, and scores as a
win — better than honest failure.

This lane measures the gap. `tool/plumb.py` walks every byte the board calls
`built` and asks tree-sitter what *it* puts there.

## The answer

**9.24% of `built` is regrouped** — 33,634 of 363,987 bytes the two parsers cut
apart differently. **97% of it is php**, and 97% of php's share traces to one
blind external, `encapsed_string_chars`, which makes a double-quoted string
underivable and hands the rest of the file to `text`. Ceiling if every
unjudged byte is also wrong: **18.77%**.

Full working, the four failed predictions and the oracle's limits:
[`RESULT-1-askew.md`](RESULT-1-askew.md). Written first, unedited after:
[`PREDICTION-1-askew.md`](PREDICTION-1-askew.md).

## The five buckets

`built` is partitioned, never reduced:

| bucket | means |
|---|---|
| `plumb` | the deepest node over this byte has the same name in both |
| `regrouped` | the extents differ — the bytes were cut apart differently |
| `relabelled` | same extent, different name, no `ALIAS` declares the pair |
| `renamed` | same extent, and the grammar *does* declare the `ALIAS` |
| `interstice` | no oracle **leaf** here; there is no token-kind to compare |
| `unjudged` | the oracle has no verdict — `ERROR` in its own tree, or no oracle |

`regrouped` is the class the lane was opened on. `renamed` is not a defect in
the tree at all, only in what a `highlights.scm` would key on; folding it in
made swift the second-worst grammar in the corpus on a defect that misreads
nothing.

## Verbs

```
python3 tool/plumb.py run            the sweep, per grammar, with totals
python3 tool/plumb.py board          standing.py's board + the five columns
python3 tool/plumb.py show php       the widest misread runs, with their bytes
python3 tool/plumb.py verify         five tripwires
python3 tool/plumb.py list           what each row resolves to
```

`--json` on `run` / `board` / `list`; a positional name or `--grammar=` filters,
and a name that names nothing is an **error** rather than a silent full sweep.

## It does not move the board

`board` reads `standing.py`'s rows and reprints them unmodified, then splices
five columns in and closes with three checks it fails on:

```
CHECK  the four buckets still total the corpus: 526798 bytes
CHECK  the split totals `built` on every row it judged: 363987 bytes
CHECK  and it judged every built byte the board has: 363987 of 363987
```

`standing.py` is untouched, and the scope this walks is `standing.tops` — the
board's own function, not a restatement of it.

## The tripwires

`verify` runs five, and three exist to prove the comparison can say *no*:

- the red case produced a row **at all** — its first version returned `None`
  and the assertion read `None` as agreement;
- the Swift comment reads misread, and the misread run falls **inside the
  comment's own bytes**;
- javascript, which `differential.py` calls byte-exact, reads 0;
- a rename is a declared **pair**, not a name — asked of scala's grammar, so
  it holds whatever the parser does today.

## What it cannot see

A byte-indexed comparison undercounts **structural** misreadings.
`research/joinery/specimen/go/selector-field.go` is 100.0% standing, parses
with zero mends, and reads a function call as a type conversion — and `plumb`
scores it **5 misread bytes of 996**, because the only leaf whose name moves
is `Print`. 9.24% is a floor. A tree-aligned comparison is the next lane and
will report more.

## Specimens this lane added

Under `research/joinery/specimen/`, all failing today, all carrying
tree-sitter's answer rather than joints's:

| specimen | claims | pins |
|---|---|---|
| `php/double-quoted-string.php` | 6 | php cannot lex `"x"` — `encapsed_string_chars` is blind |
| `php/text-swallows-remainder.php` | 4 | 57 of 70 bytes read as inline HTML and counted `built` |
| `go/selector-field.go` | 8 | a call read as a cast, at 100% standing and 0 mends |

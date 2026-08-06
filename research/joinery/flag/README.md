# flag — can outliner say "this region is untrustworthy"?

Tree-sitter's `ERROR` node marks a region as not to be trusted, and gives its
extent. Outliner has mends and damage buckets, and both of them describe bytes
it **failed** to place. Neither can point at a region it placed **confidently
and wrongly** — which is where the damage actually is: swift once read
`/* c\n d */` as a `custom_operator` over a multiplicative expression, with one
root, zero mends, and every instrument on the board scoring it a clean success.

Two rungs, cheap one first.

| | question | answer |
|---|---|---|
| **1** | can the board stop counting wrong structure as success? | **yes**, and the headline falls 22.6 points doing it — [RESULT-1-board.md](RESULT-1-board.md) |
| **2** | does the parser already know which bytes it got wrong? | **no.** Nine signals; the best scores 29.0% precision against an 18.46% base rate, a control reading no parser state at all scores 48.5%, and under a null that scatters guilt at random the top two signals score the same or better — [RESULT-2-signals.md](RESULT-2-signals.md) |

Predictions were written before each rung's results:
[1](PREDICTION-1-board.md) (five of six held) ·
[2](PREDICTION-2-signals.md) (four of six **failed**, and the failures carry the
findings).

## What moved outside this folder

`tool/standing.py` only. Three columns (`trued`, `crooked`, `graded`), a
`--crooked` sort order that is now the default, an `--audit` sweep that writes
`.local/standing/audit.json`, and two checks. Nothing was removed and no
existing column changed what it reads. Full account in
[RESULT-1-board.md](RESULT-1-board.md#what-moved-in-toolstandingpy).

`tool/rack.py` was read-only for this lane, as briefed. It is consumed, never
edited.

## Files

    spans.py    every built byte, filed by what the ORACLE said and by what
                OUTLINER knew. `score` is the signal table, and it closes with
                the NULL — the same slate over guilt scattered at random inside
                each grammar, which is the only column that can tell a signal
                reading position from one reading how often it fires. `check`
                asserts the per-byte walk is rack's walk (81/81); `prove`
                corrupts the scorer to show it can still say no (6/6); `show`
                lists the widest guilty runs with their flags.

    tamper.py   corrupts `audit.json` four ways and requires the board to
                refuse each. 5 of 5 arrive — including the one that does NOT
                get caught, which is reported rather than dropped.

## Running it

The board needs no setup; the audited columns read `—` without a cache.

```sh
python3 tool/standing.py                  # the board, audited columns from cache
python3 tool/standing.py --audit          # refresh the cache (~12 min, builds oracles)
python3 tool/standing.py --damage         # the old work order, still there

python3 research/joinery/flag/spans.py score --cached
python3 research/joinery/flag/spans.py check          # against rack, no cache
python3 research/joinery/flag/tamper.py               # needs an audit.json
```

`--cached` reads `.local/flag/sheets.json`; drop it to re-sweep. The cache is
keyed by a digest of the flag definitions, so adding a signal invalidates it
rather than scoring new flags against old spans.

## The three holes, stated up front

- **34,687 bytes have no oracle verdict.** verilog and sql read `none` on the
  board: tree-sitter's own parse of them has errors in it. Those bytes are
  neither square nor crooked, which is why the board prints a floor (50.4%) and
  a ceiling (61.6%) instead of one number.
- **23,031 crooked bytes are soft** — extras placement. Where a comment hangs is
  a parser's choice, not a claim about structure. The defended number is
  **60,138**, never 83,169.
- **The audit cache is trusted for content.** Its provenance is checked (a
  triple digest of folio, binary and source) and its internal arithmetic is
  checked, but nothing re-derives the verdicts. `tamper.py` demonstrates exactly
  where that ends: swapping a row's `square` and `crooked` preserves the
  identity, passes both checks, and moves the headline by 6,378 bytes.

# adjudicate — the external check on `gap`

> **Acted on 2026-08-05.** The verdict `gap` is retired for **`unowned`**, the
> one-line externals fix in [`RESULT-2-settled.md`](RESULT-2-settled.md) is
> applied, and `GAPS.md` carries a retraction header. This lane's finding is
> the reason; see [`../owners/RESULT-2-relabel.md`](../owners/RESULT-2-relabel.md)
> for what the relabelling moved, which is 524 bytes of 181,588 — the sentence
> was wrong, the arithmetic was not.
>
> Two corrections to what was written here. The withheld fix widened the
> external census to `type in ("SYMBOL", "STRING")`, which still drops the two
> externals declared as **patterns** (bash's and haskell's `\n`, both walled
> grammars): 23 declarations across 9 grammars, not 21 across 8. And it does
> **not** rehabilitate the owners lane's ≥45-scanner prediction — the count
> goes 9 → 10, from 5.0× falsified to 4.5×.

The owners lane labelled 170 walls by owner and put **134,358 B — 74% of the
board — into `gap`**, a verdict meaning *no derivation exists in the vendored
`grammar.json`*. It then said plainly that the test gating those bytes was the
one it trusted least, and that **exactly one hand-checked wall** had ever
exercised that branch.

`gap` is falsifiable and nothing here had falsified it. **Tree-sitter reads the
same `grammar.json`.** If a construct really has no derivation, tree-sitter must
fail on it too. This lane took the 18 real-construct gaps `GAPS.md` prices at
**106,798 B** and asked tree-sitter, one hand-authored witness at a time.

**It fails on 60 of them.**

| verdict | rows | bytes | share |
|---|---:|---:|---:|
| **gap** — tree-sitter refuses it too; genuinely nobody's | 3 | 60 | 0.1% |
| **external** — tree-sitter parses it, and only with its C scanner | 6 | 67,214 | 62.9% |
| **ours** — tree-sitter parses it from `grammar.json` alone | 7 | 39,503 | 37.0% |
| **void** — both parsers take the construct; the wall is peel context | 2 | 21 | 0.0% |

Read [`RESULT-1-gaps.md`](RESULT-1-gaps.md) for the eighteen and the
self-scoring, and [`RESULT-2-settled.md`](RESULT-2-settled.md) for the verdict
on `settled` and the one-line defect that is demonstrable in isolation.
[`PREDICTION-1-gaps.md`](PREDICTION-1-gaps.md) was written before any of it ran.

## Layout

| file | what |
|---|---|
| `locate.py` | Re-runs the peel and keeps the byte offsets `walls.py` throws away, so a `GAPS.md` row can be traced to the line of source it stands in front of. State numbers are not keys here; **(terminal, offset)** is. |
| `adjudicate.py` | The harness. Three arms per row: outliner, tree-sitter, and tree-sitter with every external answered `no`. `run` · `probe` · `prove` · `list`. |
| `witness/` | One hand-authored witness per row, plus an **innocent control per grammar**. Nothing here was produced by a shrinker. |
| `PREDICTION-1-gaps.md` | Seven predictions with named falsifiers, written after locating the constructs and before running anything. |
| `RESULT-1-gaps.md` | The eighteen adjudicated, the revised corpus split, the self-score. |
| `RESULT-2-settled.md` | Whether `settled` holds, over-claims, or should be retired. |

## Running it

```bash
export OUTLINER_BIN=$PWD/.local/pin/adjudicate2/bin/outliner   # a path is not a version
python3 research/joinery/adjudicate/adjudicate.py run          # the table above
python3 research/joinery/adjudicate/adjudicate.py probe php-encapsed   # all three trees
python3 research/joinery/adjudicate/adjudicate.py prove        # the anti-vacuity guards
```

`prove` is the pattern `collate` set: it corrupts a verdict in memory and
confirms the gate still says no. Six guards, and they cover the two ways this
harness could be vacuous — a blinding that does not blind, and an error test
that would call anything clean.

## The three arms, and why the third one exists

An outliner refusal plus a tree-sitter acceptance says the closure was wrong.
It does **not** say whose the work is, because **22 of 28 grammars make
tree-sitter compile a hand-written external scanner**. So each witness is parsed
a third time against a clone of the oracle home whose `scanner.c` has been
replaced by a stub that answers `false` to everything:

- clean with the scanner blinded → `grammar.json` derives it → **ours**;
- broken with the scanner blinded → the scanner is doing the work → **external**.

Six rows need no third arm at all: **zig, verilog and c declare zero
externals**, so nothing can be blinded and those rows cannot be `external`
however they come out. That is the cleanest fact on the board and it was
checkable before anything ran.

## Two things this harness had to learn the hard way

**A whole-file verdict answers a question no row asked.** Blinding a scanner
removes every external at once, so kotlin loses `_automatic_semicolon` and the
file breaks at a function name three statements from the two supertypes under
adjudication. The first table this printed read that as `external` and filed
**35,369 B** on evidence about the word `equals`. Every row now carries the byte
span of its own construct, and only an `ERROR`/`MISSING` that touches that span
counts. `prove` guards both directions.

**A witness that walls is not automatically a witness about the row.** A lane's
shrinker was green while destructive — it deleted a token while the failure
still held and produced sixteen witnesses named after their parent's defect. So
the table carries a **wall** column comparing the terminal outliner actually
refuses against the one `GAPS.md` names. Four rows disagree, all four are
adjacent tokens of the same construct, and all four are reported rather than
quietly accepted.

## What leaves this lane

The six `external` rows are **67,214 B of seatable work** and belong to the
specimen/externals effort, with the responsible token named per row in
`RESULT-1-gaps.md`. The seven `ours` rows are press work. The 60 B of real gap
is verilog preprocessor directives in a module port list, and it is the only
part of the 106,798 that upstream owns.

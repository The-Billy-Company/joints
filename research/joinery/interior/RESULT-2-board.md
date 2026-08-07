# Result 2 — the board, and four predictions that failed

> **Holds, and the oracle settles the one argument this page had to make from
> inside its own forest (2026-08-06).** Every column here is ours, so P2c's defence
> — *`built` up while `describes` falls is consolidation, not reading less* — was
> argued entirely from our own numbers about our own trees. Sighted, in
> `consort/RESULT-8-sighted.md`:
>
> - the seating, `_content_str_1/.marrow/.julia_quoted`, is worth **+8,910
>   `square`** against +5,471 `damage` — **1.6× what this page priced it at**;
> - julia finishes at **24,382 `square` of 27,360 bytes — 89.1% `trued`**, with
>   only 1,025 built bytes uncorroborated, second only to kotlin on the corpus.
>
> **That is the P2c defence, proved rather than argued.** The `keep` trap the
> falsifier was aiming at is `built` rising while the tree gets *wronger*;
> tree-sitter derives nine bytes in ten of julia the way we now do, so the
> consolidation reading is correct and the falsifier really was mis-specified. The
> sharpened rule the page proposes — *`describes` falling is reading less only when
> `covered` falls or `spoil` rises with it* — survives, and there is now a second
> and better test for it that this page could not run: `square`.
>
> **P2e is now cleared on the oracle's columns too.** *Nothing else moved* holds
> across twenty-four columns including five of the oracle's, with elixir still the
> control, and the arms are additionally byte-identical in their parse trees on
> 29 of 30 grammars. The julia pair (`_content_str_1` with `_immediate_paren/.abut`)
> stays **genuinely additive** sighted — residual +589 on `square`, inside the
> pair rule's slack — which is not true of scala's, kotlin's or elixir's pairs.
>
> Nothing here was re-measured.

Baseline `.local/lane-strings/board-before.txt`, 2026-08-05T19:34Z, binary
`joints 9e422a351`. After `.local/lane-strings/board-after.txt`,
2026-08-05T19:56Z, binary `joints e8343caf6`. Both `python3
tool/standing.py --unbound`, both exit 0, both `generation: one generation
each`, so neither table spans artifact generations.

## Whole board

| | before | after | delta |
|---|---|---|---|
| built | 349,259 | 354,893 | **+5,634** |
| orphan | 57,005 | 56,766 | −239 |
| rubble | 29,868 | 27,667 | **−2,201** |
| spoil | 90,666 | 87,472 | **−3,194** |
| unbound | 120,534 | 115,139 | **−5,395** |
| standing | 66.30% | 67.37% | +1.07 |
| covered | 82.8% | 83.4% | +0.6 |
| describes | 97,280 | 95,150 | **−2,130** |
| whole | 12 of 30 | 12 of 30 | — |

## Julia

| | before | after |
|---|---|---|
| covered | 68.6% | **80.3%** |
| standing | 39.0% | **59.6%** |
| built | 10,679 | 16,313 |
| strewn | 8,087 | 5,647 |
| orphan | 2,374 | 2,135 |
| rubble | 5,713 | 3,512 |
| spoil | 8,594 | 5,400 |
| unbound | 14,307 | **8,912** |
| adrift | 52.3% | 32.6% |
| roots | 2,477 | 1,591 |
| **bare leaves** | **1,539** | **897** |
| wall | `lexer on _word_identifier in state 45` | `press? on { in state 136` |

Every whole-board delta above is julia's, to the byte.

## P2e held, and it is the only prediction that did

**29 of 30 rows are byte-identical in every printed column.** Not a sample and
not a folio digest — the board's own per-grammar table, diffed field by field:

```
grammars before/after: 30 30
  MOVED julia
unchanged: 29
```

This is the check that could have failed, and it is the right one because the
press is currently not byte-reproducible for nine of thirty, so a folio
comparison would have proved nothing. Elixir is among the 29, which is the
specific control for P1e: had I widened `matter` instead of writing julia its
own walk, elixir's twenty rows would have moved.

**No persisted field was added.** The brief warns that a folio parity check on
a new field can pass and be unable to fail. That trap does not apply here and
the reason is checkable rather than asserted: `Troupe` and `Cast` appear
nowhere in `src/folio/*` or in `lexicon.zig` — the lexicon block persists the
munch automaton (voices, patterns, DFA transitions) and nothing else. The
seating is rebuilt from the static `troupes` table on every load, so there is
no mint for a field to be dropped at.

## P2a failed — I read the wrong case off `covered`, in a new direction

Predicted: spoil falls by more than 4,000, rubble does **not** fall below 4,000
and may rise. Reasoning: `covered` at 68.6% meant 8,594 unreached bytes, so
this was the haskell case where reaching further converts unreached bytes into
misattributed ones.

Measured: spoil fell **3,194** (under the threshold) and rubble fell to
**3,512** (through it). Both fell, and neither by what I said.

The reason is a case I had not modelled: the bytes that were rubble were
*already reached* — shredded identifiers inside a docstring, lexing correctly
and hanging in the wrong place. Seating the interior did not move them from
unreached to misattributed; it moved them from misattributed to inside a
string. So julia was simultaneously the haskell case (reach grew) and the swift
case (misattribution fell), and the standing note that rubble and spoil "do not
move in a fixed relationship, and I have been wrong in both directions" now has
a third direction: **both can fall at once when the win is re-attribution of
bytes that were reached and shredded.**

## P2b failed — the roots did not collapse, because the wall only moved

Predicted roots below 500 and leaves below 400. Measured 2,477 → **1,591** and
1,539 → **897**. Real movement, nowhere near the number.

The prediction assumed seating the interiors would let the file parse. It did
not; it moved the wall from a lexer wall on `_word_identifier` to `{` at 972 in
state 136, which is `_immediate_brace` — still blind. The parse still mends
1,194 times over 1,232 bytes. Bare leaves are reported explicitly here because
`covered` counts a byte as read when a bare leaf stands over it: 897 is the
honest denominator behind the 80.3%.

## P2c failed, in the exact direction I called invalidating

Predicted: julia's node count rises by more than 20%. Falsifier as written:
"`built` rising while `describes` falls. That is the verilog `keep` trap — a
metric improving by reading less — and it invalidates the result outright."

Measured: `built` +5,634 and `describes` **−2,130**. My own falsifier fired.

I am going to argue the falsifier was mis-specified rather than that the result
is invalid, and here is the evidence that separates the two cases. The verilog
`keep` trap is built up, nodes down, **and reach down** — it lifts `built`
25,457 by declining to read half the file. Julia:

- `spoil` fell 3,194, so the parse reached **more** bytes, not fewer;
- `covered` rose 68.6% → 80.3%;
- `rubble` fell 2,201, so of the bytes it reached, fewer are misplaced.

And the tree says what happened directly. A docstring that was hundreds of bare
identifier leaves is now one node:

```
(string_literal (content))
(string_literal (content) (escape_sequence) (content) (escape_sequence) (content))
```

Those bytes were being counted as nodes while sitting in `strewn`. Now they are
one `content` token inside a `string_literal`, in `built`. Fewer nodes, larger,
correct, over more bytes.

So the rule the board's docstring should carry is sharper than the one I wrote
down: **`describes` falling is not on its own the reading-less signature.** It
is reading less only when `covered` falls or `spoil` rises with it. Falling
nodes with rising reach is consolidation, and it is what a string interior is
*for* — a string is supposed to be one node.

I am reporting this as a failed prediction and not as a passed one, because the
distinction I am drawing was not in the prediction and I would not have drawn
it if the number had gone the other way.

## P2d failed — orphan moved the other way

Predicted julia's orphan **rises**, on the theory that comments buried inside
unparsed regions become top-level leaf roots once the surrounding parse gets
further. Measured: orphan **fell** 2,374 → 2,135. The comments were not sitting
where I modelled them. Reported as a movement rather than smoothed into the
built number: −239 bytes left orphan and are now inside a tree.

The kotlin half of P2d is untested because kotlin was not touched.

## Scoring

| | held | failed |
|---|---|---|
| P1a julia seatable with no carried state | ✓ | |
| P1b no co-admission by shift | ✓ (conclusion wrong) | |
| P1c `_end_str` needs no memory | ✓ | |
| P1d kotlin/swift cannot use the trick | ✓ | |
| P1e a separate walk is required | ✓ | |
| P2a spoil falls, rubble does not | | ✗ |
| P2b roots < 500, leaves < 400 | | ✗ |
| P2c describes rises > 20% | | ✗ |
| P2d julia orphan rises | | ✗ |
| P2e nothing else moves | ✓ | |

## The instrument I trust least

**`state --census`, and specifically the fact that I had to change it before it
could answer my question.**

Not the state row — that was fixed, and it prints shifts and reduce-lookaheads
under separate headers with a footer naming both counts. The census shares its
split function with the row, which is the property the row's own docstring says
is the whole reason it lives in that file. And it was still wrong, because
sharing the split is not the same as reporting both halves: `together` reduced
each pair to one number and the number it chose was co-admission **by shift**,
while the permission set a hand reads is `drive.offer`'s — shift ∪ reduce-
lookahead. For julia's ten terminals those columns are `0` and `3`, and the
difference is whether the seating needs a guard at all.

What makes it the least trustworthy rather than merely the buggiest is that it
was **confidently, quotably wrong in the direction of encouraging work.** It
printed a wall of zeros under a header that reads like a safety clearance, and
zeros are what the previous lane's precedent taught me to look for — "zero here
is what makes 'seat one of the cohort' sound; one is what kept swift's `!`
out." I had the right precedent, the right tool, and the tool answered a
neighbouring question in the vocabulary of mine. If I had not gone to read what
`wanted` actually contains in `scanner.zig` — which I only did to settle
whether `.none` should `continue` or refuse — the seating would have shipped
with no `rival` pair and answered string content over every identifier in the
language, and the board would have told me by getting worse rather than by
naming the cause.

The census now prints `shift` and `set` side by side. That does not retire the
distrust: it is the second time this session that a mechanism and its census
disagreed about which half of a state row they meant, after `lex`'s blind count
called swift blind to a terminal the parser was emitting. Two instances is a
pattern in the codebase, not two bugs, and the shape of it is that **anything
here reporting "what a state admits" as a single number is reporting one of two
facts and not saying which.**

Runner-up, briefly, because it cost less but lied harder: the corpus. `Maps.kt`
and `Chunked.swift` contain no interpolation, no triple-quote and no raw string
between them, so a stateless kotlin string hand would have been byte-perfect on
every measurement this repo takes and unsound in the field. A green board is
not evidence of soundness for a mechanism whose failure mode the corpus does
not contain.

## Final test state

`zig build test -Dtest-shards=1 --summary all`: **11/11 steps succeeded**, both
shards `success`. Standalone, single shard, no filter.

Two of my own marrow tests failed on the way there and both were the test
being wrong rather than the walk, which is worth writing down because both
errors were in the *same* direction — I had written down what I expected julia
to do rather than what the spec does:

- I asserted elixir's `matter` would **refuse** `abc"""rest`, because a heredoc
  close is only a close where a line begins. It does not refuse; it walks past
  the quotes and hands back all 10 bytes, since unterminated is matter to the
  end. The real contrast is wider than the one I claimed, and the test now pins
  `3` against `10`.
- I asserted a raw run yields `4` on `a$b\"c"`, counting the backslash into the
  matter. `mark_end` sits at the **top** of the pass in `scan_content`, so the
  yield is in front of the backslash and the answer is `3` — the `\"` goes to
  the grammar whole.

Neither touched the production walk, so every board number above stands.

## Coworking notes, not chased

- **`zig build test | grep brigade` exits 1 on a passing run.** Brigade prints
  its summary line only when something fails, so a green suite prints nothing,
  grep matches nothing, and the pipeline's exit is grep's. I read that as a
  failure for ten minutes. Instrument nineteen, and it is mine: `--summary all`
  and the step tree are the trustworthy read.
- An earlier full run showed **345 passed, 1 failed** —
  `kernel.lex.lexicon_test.test.every field of an automaton either crosses the
  lexicon block or is a declared loss: FieldLost`. Not mine, and gone by the
  final run. That test walks the fields of `Dfa` through
  `lexicon.freeze`/`thaw`; this change touches no automaton and adds no lexicon
  field. `lexicon.zig` and `lexicon_test.zig` are another lane's, modified at
  12:53 and **13:11:56**, the latter during the test run, and the board's stamp
  flagged `STALE - ./src/kernel/lex/lexicon.zig is newer than the binary` for
  the same reason.
- The board's `after` stamp carries that same STALE line. It means my binary
  predates their edit, which is what makes it the right binary for attributing
  this change and the wrong one for believing anything about theirs.

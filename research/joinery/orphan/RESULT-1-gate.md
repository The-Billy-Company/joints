# Result 1 — the gate holds, the magnitude does not, and two of four failed

> **Holds; both of its named data are worth more than it says (2026-08-06).**
> Every column here is ours, and the ablations move the *input bytes*, so no
> oracle reading of them exists or was taken. The gate argument does not need
> one: *a positive `orphan` iff the file mended* is a fact about one line of
> `gather.zig`, checkable at 30 of 30 rows. And kotlin, its main subject, reads
> **35,324 `square` of 35,571 built — 98.6% `trued`**, so the forest this page
> reasons over is one tree-sitter corroborates.
>
> The two magnitudes are both floors:
>
> - **php's datum, which the page calls undeniable, is 8.3× larger than stated.**
>   One mend costing *"8,091 orphan bytes, twelve percent of its file's structural
>   account"* is, sighted, one mend costing **67,183 `square`** — the entire
>   agreement php has with tree-sitter. Seat the row and php is 67,845 square;
>   un-seat it and php is 662 (`consort/RESULT-8-sighted.md`, arm r9).
> - **the string ablation's +20,728 `built` is +27,143 `square` when the fix is
>   really seated**, so the ablation under-estimated its own subject by 31%. That
>   promotion is recorded on `RESULT-2-wall.md`.
>
> Nothing here was re-measured.

Measured 2026-08-05 against the pinned binary `.local/pin/kdocA` (build
`b6cf8b5a3169`, tree `98abef26d3b6`, commit `f7ba4000`), board
`generation: uniform`, `cache: kept 30`. No production file was edited in this
lane, so every number here is a reading of the tree as it stood.

## P1a — held, thirty of thirty

`gate.py` joins each row's orphan bytes against the mend count the binary
reports on stderr.

| | mends | orphan | roots | leaves |
|---|---|---|---|---|
| css, embedded-template, go, html, java, javascript, json, lua, python, rust, toml, typescript | 0 | 0 | 1 | 0 |
| bash | 2 | 368 | 26 | 17 |
| **php** | **1** | **8,091** | **119** | **50** |
| scala | 4 | 4,046 | 26 | 19 |
| latex | 4 | 1,024 | 72 | 49 |
| zig | 3 | 1,285 | 55 | 35 |
| c / cpp | 5 / 6 | 439 / 330 | 28 / 36 | 18 / 18 |
| ruby | 21 | 344 | 43 | 29 |
| ocaml | 28 | 1,829 | 167 | 60 |
| swift | 31 | 3,997 | 308 | 179 |
| elixir | 34 | 219 | 255 | 106 |
| **kotlin** | **142** | **19,705** | **419** | **237** |
| sql | 273 | 1,635 | 194 | 136 |
| julia | 1,194 | 2,135 | 1,591 | 897 |
| haskell | 1,806 | 8,052 | 2,562 | 1,938 |
| verilog | 2,109 | 3,267 | 3,544 | 2,481 |

Zero mends, zero orphan, **one root**, on twelve of twelve. No file mends and
keeps a top-level extra; no file with a top-level extra mends and scores zero.
The two rows that score zero orphan while mending are the two the board already
labels: `markdown` is `bare` (79 mends, no `extras` declared, so zero is
vacuous) and `yaml` is `void` (no tree at all). Both are documented basis
values, not counterexamples.

The mechanism is `gather.zig`, and it is a one-line gate:

```zig
if (won.ok and x.mends == 0) try x.crown(won.top, @intCast(bytes.len));
```

`crown` is Rule 5 — the only operation that adopts extras no reduction claimed,
because the start production is never reduced and accept fires in its place.
One mend anywhere and `unwind` runs instead, carrying `x.borne.at(x.lead,
x.leads)` straight into `roots`. The board's whole `orphan` column exists on
the far side of that `== 0`.

**php is the datum that makes it undeniable: one mend, one byte skipped,
8,091 orphan bytes and 119 roots.** A single byte the lexer could not read
costs php twelve percent of its file's structural account.

## P1b — FAILED, and this is the finding

I predicted the 19,705 was all-or-nothing: that only reaching zero mends could
move it, because `crown` is gated on zero and 141 of 142 is not zero.

`ablate.py` blanks kotlin's 45 string literals to same-length identifiers,
keeping every byte offset:

| ablation | mends | built | orphan | rubble | spoil | describes | leaves | roots |
|---|---|---|---|---|---|---|---|---|
| baseline | 142 | 14,841 | **19,705** | 333 | 936 | 8,322 | 237 | 419 |
| strings | **3** | **35,569** | **208** | 22 | 16 | **8,580** | 5 | 11 |
| imports | 140 | 14,841 | 19,730 | 311 | 933 | 8,319 | 234 | 416 |
| strings+imports | 1 | 35,569 | 233 | 0 | 13 | 8,577 | 2 | 8 |
| comments | 142 | 14,841 | 203 | 333 | 20,438 | 8,245 | 160 | 342 |

Orphan fell to 208 with **three mends still standing**. The prediction is
dead.

Why it was wrong: I read Rule 2 as leaving every top-level extra unclaimed
until `crown`, and that is only true of the leading and trailing ones. A
`repeat($.statement)` compiles to a left-recursive accumulator, and *that*
reduction has a first and a last symbol, so a KDoc between two top-level
declarations is claimed by it. What orphans a comment is not the file having
mended, it is **the stack being felled while that comment is still a lead** —
which is a per-mend event. 142 fellings orphan 79 comments; 3 fellings orphan
one.

So the gate is binary and the magnitude is graded, and both statements are
true at once. `orphan > 0` is a fact about whether the file mended at all;
`orphan = 19,705` is a fact about how often.

## P1c — half held, half failed

Held: the non-string walls are real and enumerable. `residual.py` walks the
ablations down to nothing and `Maps.kt` has **exactly three** walls, no more:

1. **`_string_start`** and its family — 139 of the 142 mends.
2. **`_import_dot`** — 2 mends, on the `.` at 388 in `import kotlin.contracts.*`.
3. **`press? on , in state 110 (1 dropped, 13 misfolded)`** — 1 mend, on the
   comma in `: Map<Any?, Nothing>, Serializable`. Not an external at all; the
   same verdict family `c` and `cpp` carry.

Failed: I said a string fix would leave `orphan` where it was and move the
board in `rubble`/`spoil` instead. It moved every column at once, `orphan`
hardest.

## P1d — recorded before, and it was the right thing to be afraid of

I wrote down that I had nearly concluded the mends orphan the comments *near*
them, and that believing it would let me claim a proportional share of 19,705
I had not earned. The ablation says the opposite of my correction: the damage
**is** roughly local to each mend. So the thing I nearly believed was closer to
right than the thing I replaced it with, and the falsifier I wrote for it is
what caught me. Both readings survive only because P1a and the ablation
disagree about different questions.

## Reading the movement by the sharper rule

`describes` **rose** 8,322 → 8,580 while `built` rose 20,728. `covered` rose
(spoil 936 → 16) and `spoil` fell, so this is not the reading-less shape at
all — the sharper rule is not even needed here, which is worth saying because
I expected to need it. Bare leaves fell 237 → 5 and roots 419 → 11.

`shape.py` checks the one way a big `built` lies. The ablated tree's eleven
roots are four `file_annotation`s, a `package_header`, an
`object_declaration`, one `source_file` spanning [448, 35814) — and four
code leaves that are the shredded `import` line. The holes at [388,389),
[399,402) and [446,448) sit visibly *outside* every root. It is not one
dishonest root stretched over a gap.

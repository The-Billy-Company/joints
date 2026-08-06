# Result 5 - how much of the board is two rows cooperating

> **Withdrawn verdict, kept page (2026-08-06).** Every arm on this page read
> `square 0` - see `consort/RESULT-5-blindness.md` - so every residual below is
> priced on `damage`, which is outliner's own words about its own forest. Re-taken
> sighted in `consort/RESULT-8-sighted.md`, **no pair on this board is two rows
> cooperating.** Every `square` residual is zero or positive, which is a ceiling:
> two rows that each destroy nearly all of one quantity cannot also sum. scala
> **+6,547**, kotlin **+27,323**, elixir **+23,878** (each of its rows alone costs
> 99.996% of elixir's square, where `damage` sees a 1,472-byte residual and calls
> them nearly additive), julia **+589** and swift **0** are genuinely additive.
> The arithmetic on this page re-derives; the word does not survive it.

Scores the second half of `PREDICTION-2-witness.md`. **Scala is not the only
one. Kotlin's pair is four times worse, and it was hiding in plain sight in a
sentence the previous lane already wrote.** No grammar is in the worst state -
a pair both of whose members read zero alone.

## The powerset does not need running, and here is the argument

Fourteen rows admit 16,369 subsets of size two or more. Almost all of them are
incoherent, and the reason is `seated()`: a cast refuses unless the grammar
declares **every** terminal the row names, so a row can only ever change a
grammar in its **candidate set**, and that set is decidable from the roster and
the grammars' own `externals` with nothing built.

`ablate.py guests` computes it:

| row | seat | terminals it needs | can reach |
|---|---|---:|---|
| 0 | `_indent/.offside/.slashes` | 3 | scala |
| 1 | `_cmd_layout_start/.writ` | 10 | haskell |
| 2 | `_string_start/.fence/.kotlin` | 6 | kotlin |
| 3 | `multiline_comment/.marrow/.swift_block` | 2 | swift |
| 4 | `block_comment/.marrow/.kotlin_block` | 2 | scala |
| 5 | `comment/.marrow/.ocaml_comment` | 2 | ocaml |
| 6 | `_quoted_content_double/.marrow/.elixir_quoted` | 20 | elixir |
| 7 | `_content_str_1/.marrow/.julia_quoted` | 10 | julia |
| 8 | `_immediate_paren/.abut` | 5 | julia |
| 9 | `encapsed_string_chars/.marrow/.php_encapsed` | 5 | php |
| 10 | `_trivia_raw_env_verbatim/.marrow/.latex_verbatim` | 12 | latex |
| 11 | `_implicit_semi/.caesura/.swift` | 3 | swift |
| 12 | `_automatic_semicolon/.caesura/.kotlin` | 2 | kotlin |
| 13 | `_newline_before_do/.caesura/.elixir` | 2 | elixir |

Nine grammars, **five of them reachable by two rows** and none by three:
elixir `{6,13}`, julia `{7,8}`, kotlin `{2,12}`, scala `{0,4}`, swift `{3,11}`.
So the population that matters is **five pairs**, not 16,369 subsets, and P5
held with room (I said fewer than ten).

It is an over-approximation on purpose. It answers *could this row reach that
grammar*, and a candidate too many costs one build where a candidate too few is
a pair nobody looks at. `block_comment/.marrow/.kotlin_block` is the row that
makes the point: its vein is named for kotlin and only **scala** declares the two
terminals, so kotlin is not in its set and scala is.

**The falsifier for the narrowing itself, run first:** every grammar a row was
*measured* to move must be a grammar it can seat. **Zero of fourteen violate it.**
Without that row the candidate sets are an assumption rather than a bound, and
every subset below is the wrong population.

## The five pairs, measured

`attribute.py pairs`, five new isolation arms built from the same snapshot the
fourteen single-row arms came from, each priced against that snapshot's own
board. With `worth(r) = D({r}) - D(none)` and `joint = D(S) - D(none)`:

| grammar | rows | D(none) | D(pair) | joint | sum of solos | **residual** | |
|---|---|---:|---:|---:|---:|---:|---|
| kotlin | 2+12 | 244 | 19,922 | +19,678 | +39,966 | **−20,288** | cooperating |
| scala | 0+4 | 16,883 | 7,087 | −9,796 | −15,296 | **+5,500** | cooperating |
| julia | 7+8 | 1,953 | 16,681 | +14,728 | +14,565 | +163 | additive |
| elixir | 6+13 | 8,795 | 21,354 | +12,559 | +12,736 | −177 | additive |
| swift | 3+11 | 5,337 | 16,250 | +10,913 | +10,913 | 0 | additive |

The residual is exactly the quantity a single-row arm cannot observe, and the
threshold - 1,000 bytes - was written down before the numbers were taken.

**Kotlin, and it is the largest number on this page.** `worth(2)` is +20,737 and
`worth(12)` is +19,229; removing *both* costs +19,678. Each row alone destroys
kotlin, and the two arms between them claim **40 KB of a 20 KB defect**. They are
not two contributions to be summed, they are two permissions the same walk needs,
and single-row attribution double-counts the whole grammar. The previous lane
wrote the sentence - *"Kotlin's two rows are not additive: removing either
restores about 20,000 bytes"* - as an aside in a changelog fragment; this is that
sentence with an arm behind it and a number on it.

**Scala, the case the brief names.** Removing either row *improves* the snapshot
(it is the tree the press regression was live on), and removing both improves it
by 5,500 bytes **less** than the two arms predict. A grammar whose two rows
interact by a third of its own damage has no single-row arm that can price its
next regression.

**Swift's residual is exactly zero, and that is a finding rather than a
non-finding.** `multiline_comment/.marrow/.swift_block` moves swift by 0 bytes
alone, by 0 bytes beside `_implicit_semi`, and the pair arm reproduces the
`_implicit_semi` arm to the byte. It is a **seated row that changes nothing in
any combination available to it** - which is a much stronger statement than the
one-arm family could make, and the honest way to hold it is `--inert`: identity
is the result, not a clearance.

## Is a pair ever invisible?

The worst shape available - **every member reads zero alone and the pair does
not** - is what would leave a defect with no attributable owner at all. The sweep
tests for it by name and **no grammar is in it.** In all five pairs at least one
member moves the grammar on its own, so a single-row arm always *notices*; what
it gets wrong is the size, by up to 20 KB. P8 predicted at least one invisible
pair, and predicted swift; swift is the row that reads zero alone and it also
reads zero in the pair, which is the opposite outcome.

That is worth stating carefully, because the brief's scala sentence sounds like
the invisible case and is a different measurement. *"Both of its own isolation
arms report a 12,733-byte regression as zero"* is about **sensitivity across two
trees**: with either row out, scala reads identically on the pre- and post-press
trees. The residual above is about **magnitude on one tree**. Both follow from
the same non-additivity and they are not the same number, and the two-tree form
is the more alarming one because zero is unfalsifiable. Whether kotlin loses
sensitivity the same way is **not measured here** - it needs the five pair arms
rebuilt against a second tree, and this lane's arms are all one snapshot. That is
the next experiment and it is cheap now that the arms exist.

## The union arm, and why it is not the shortcut it looked like

If a grammar's candidate set is exactly the rows that reach it, then the union
arm - all fourteen out - restricted to grammar g *is* g's own full-subset arm,
because removing rows that cannot reach g cannot move g. That would make every
pair free.

Measured against the previous lane's retained `aud-iso`, it **failed** on four of
five grammars by 226 to 296 bytes. Measured against a union arm built from the
same snapshot as the pairs, it holds **to the byte on all five**. The retained
union arm was pinned from a tree carrying three of another lane's files; the gate
from this lane's other half is what said so. So P6 held, and it held only because
the first answer was wrong in a way that was invisible until a board could say
which tree it read. The two halves of this lane found each other.

The shortcut is real but it is not what the tool implements. `attribute.py pairs`
builds the subsets, because the union arm can only ever answer the *full* set and
a grammar with three candidate rows would need its three pairs anyway.

## Score

| prediction | outcome |
|---|---|
| P5 fewer than ten subsets worth testing; the narrowing's falsifier holds | **held.** Five, and zero of fourteen rows moved a grammar they cannot seat |
| P6 the union arm answers every pair | **held, on the second attempt.** Byte-identical once both arms come from one tree; off by 226-296 B when they do not |
| P7 at least two pairs non-additive, and swift is one | **half.** Two are - kotlin and scala - and **swift is not**; I picked the one row that turns out to be inert in every combination |
| P8 at least one invisible pair, and it is swift | **wrong.** None. Every pair has a member that moves its grammar alone; the failure is mis-sizing, not blindness |

Two for four on the letter, and the one I got most confidently wrong - swift -
was wrong for an interesting reason: I read "moves nothing alone" as the
signature of a hidden partner, and it is also the signature of a row that does
nothing. Those look identical from a single arm, which is the finding this lane
was sent to make, arriving at my own expense.

## What the tooling does now

- `ablate.py guests` - each row's candidate grammars, from the roster and the
  grammars' externals. No build.
- `ablate.py write <dest> 0,4` - a **set**, not a row. The arm no single-row
  family contains.
- `attribute.py pairs [control.json]` - the narrowing, its falsifier, one arm per
  multi-row subset (reusing any pin that already exists), and the residual table
  above. Writes `pairs.json`.

## The instrument I trust least here

`attribute.py pairs` itself, and specifically **`SLACK = 1000`**. It is the only
number on this page that came from a person rather than a measurement, and the
verdict column is a function of it. It happens not to matter today - the two
cooperating residuals are 5,500 and 20,288 and the three additive ones are 0,
163 and 177, so the gap is a factor of thirty and no threshold in that range
changes a single verdict. That is luck about this roster, not a property of the
instrument, and the day a residual lands at 900 the column will be reporting my
threshold rather than the tree's behaviour. The residual is printed on every row
for exactly that reason: read the column, not the word.

## Correction, from `research/joinery/consort/` — the word, not the column

Every number on this page re-derives to the byte and none of it is edited here.
Three **readings** of those numbers did not survive a second fixture, and the
lane that took them wrote its own dossier rather than rewrite this one.

- **"Each row alone destroys kotlin" · verdict *cooperating*.** The two rows are
  mechanically independent: on a kotlin fixture with a statement separator and
  no string, `worth(2)` is **0** exactly; on one with a string, removing row 2
  fails at the same byte whether row 12 is seated or not. The residual is what
  `built` does when two constructs sit **25 bytes apart in the head of one
  file** - `Maps.kt` walls at 245 without the caesura and at 270 without the
  fence, with 35,571 bytes behind both. Moving that string down an otherwise
  identical 200-statement file swings the residual from −12 to −202, and
  removing it makes the pair perfectly additive. `consort/RESULT-1-kotlin.md`.
- **"A seated row that changes nothing in any combination available to it."**
  The specimen tier was a combination available to it, and it was green.
  `swift/multiline-comment.swift` and `swift/nested-comment.swift` both go
  **4/4 → 2/4** against this lane's own `aud-r3` pin. The board reads zero
  because `Chunked.swift` contains no `/*` at all, so no board arm - single,
  pair, or the fourteen-row union - could ever have moved on it. The sentence is
  true of the board and the board is the only thing it was measured over.
  `consort/RESULT-2-swift.md`.
- **Scala's +5,500 · verdict *cooperating*.** Every scala worth on this page is
  negative: both seatings are net harmful on this snapshot, on `built` and on
  node count, so the sub-additivity is two overlapping harms rather than two
  cooperating benefits. And the snapshot carries the press regression named in
  `RESULT-3-press.md` - scala's control here is 16,883 where the fourteen-arm
  table's was 4,150, and elixir's is 8,795 where that table's was 0. The two
  tables are therefore not one measurement, and scala's pair wants re-pricing
  once the press clears. `consort/RESULT-3-scala.md`.

`RESULT-5`'s own closing advice - *read the column, not the word* - turns out to
name its own three defects. All three are in the word.

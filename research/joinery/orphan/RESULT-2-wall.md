# Result 2 — the wall is `_string_start`, and the brief priced it at 6%

> **Holds, and under-priced itself by a third (2026-08-06).** Every column on this
> page is ours — `built`, `orphan`, `unbound`, `standing`, `mends` — so the
> clearance it argues had no second parser in it. Re-read against a sighted board
> it survives on every point, and it is the page that survives *best* on this
> tree, for a reason worth stating: **its subject grammar agrees with tree-sitter
> almost everywhere.** kotlin reads **35,324 `square` of 35,571 built — 98.6%
> `trued`** on the audited base arm, so the orphan-versus-built argument below was
> reasoning about a forest the oracle corroborates, and the mechanism it
> established — *a correctly-recognised extra is an `orphan` and a misread one is
> `built`* — is now the rule every other `damage`-only page on this tree is judged
> by. It is right, and it is what makes the rest of them suspect.
>
> **The estimate is now a measurement, and it went up.** This page's own trust
> note says `+20,728 built` is *"the number I would bet on and not the number I
> would report as measured, and the only way to promote it is to build the
> thing."* The thing was built: `_string_start/.fence/.kotlin` is a seated row,
> and its isolation arm, sighted, prices it at **+27,143 `square`** against
> +20,737 `damage`. The bet was good and low by 31%.
>
> | handed back on this page | priced here | sighted |
> |---|---|---|
> | kotlin `_string_start` | 20,728 `built` (estimate) | **+27,143 square** |
> | php `encapsed_string_chars` | 8,091 orphan bytes | **+67,183 square** |
> | scala `_simple_string_start` | 4,046 orphan bytes | not seated; scala's whole square is 6,739 |
> | swift `multiline_comment` — *"nobody has tried it"* | 3,997 orphan bytes | tried: **0 on the board**, and it flips two specimens |
>
> **php is the row this page mis-sized worst, and it was a footnote.** Handed back
> at 8,091 orphan bytes reached on a single mend, the seating is worth **67,183
> square — 8.3× the figure that put it in a bullet list.** php's whole 67,845-byte
> file is square today; un-seat that row and 662 bytes are. A page cannot be
> blamed for not knowing that, but the next work order can be blamed for reading
> the bullet.
>
> **And swift is the one that went the other way.** *"Nobody has tried it"* was
> answered: the row is seated, and it moves swift by **zero** on every board
> column, because `Chunked.swift` contains no `/*` at all. It is alive — it flips
> two specimens the moment it is un-seated — so the board's zero is a fact about
> the fixture and not about the row (`consort/RESULT-2-swift.md`).
>
> Numbers from `consort/RESULT-8-sighted.md`, arms r2 · r9 · r3, one oracle minted
> per arm. Nothing here was re-measured.

## The wall, named

**`_string_start` / `string_content` / `_string_end`, blind, in `kotlin`.**
139 of `Maps.kt`'s 142 mends stand on them. They are worth **20,728 bytes of
`built`** — kotlin 41.44% → 99.31% standing — and **19,497 of the 19,705
orphan bytes** the brief handed me.

## The impossibility argument — why it is not a neighbour

A verdict is a location, so nothing here rests on one. Each wall was removed
from the input on its own, length-preserving, and measured on the board's own
columns. Three candidates, and only one moves anything:

| removed | mends | built | orphan | reading |
|---|---|---|---|---|
| nothing | 142 | 14,841 | 19,705 | — |
| **the 45 string literals** | **3** | **35,569** | **208** | the wall |
| the `import` lines | 140 | 14,841 | 19,730 | worth 2 mends and **zero** bytes |
| **every comment** | 142 | 14,841 | 203 | the comments carry **nothing** |

The comment ablation is the one that settles it, and it is the control
`standing.py`'s own docstring already established: blank every KDoc to spaces
and `built` stays 14,841 **to the byte**, the wall stays where it was, and the
mend count stays 142. Whatever demotes the KDoc, the KDoc is not it, and no
hand that reads a comment can be it either. The comments are the dye, not the
injury.

`_import_dot` is a neighbour that fires — 2 mends, on the `.` at 388 — and it
is worth *nothing*. Removing it while leaving the strings moves `built` by
zero bytes and moves `orphan` the **wrong way**, 19,705 → 19,730. A lane that
had chased the verdict's own words would have fixed it: `_import_dot` is the
terminal the *first* wall names once the strings are out of the way, and the
`inquest` line for it is as precise and as specific as the one for
`_string_start`.

And the residual is closed, not assumed. With strings and imports both gone,
`Maps.kt` mends exactly once more, on `press? on , in state 110 (1 dropped, 13
misfolded)` — a merge defect, not an external, worth zero bytes of `built`.
Three walls, all three named, one of them load-bearing.

## The instrument that lied — and it is the sentence in the brief

The brief says: *"Kotlin's problem isn't strings at all. Its string interiors
are worth at most 1,269 unbound bytes."*

1,269 is `rubble + spoil` for kotlin, and it is a true number about the wrong
question. `unbound` is defined to exclude `orphan`, for a good reason —
a comment is a leaf in any parse, so charging its bytes to "a token lying where
a tree should be" would make the column track comment density. Correct as a
statement about a comment. Read as a work order it is catastrophic, because
kotlin's `orphan` is not measuring comment density; it is measuring **how many
times the stack was felled**, and the felling is the injury.

So the board's work order and the board's own `standing` column disagree about
kotlin by five places:

| rank | by `unbound` | | by `size − built` | | moved |
|---|---|---|---|---|---|
| 1 | verilog | 60,670 | verilog | 63,937 | 0 |
| 2 | yaml | 18,935 | haskell | 25,048 | +1 |
| 3 | haskell | 16,996 | **kotlin** | **20,974** | **+5** |
| 4 | julia | 8,912 | yaml | 18,935 | −2 |
| 5 | markdown | 3,126 | julia | 11,047 | −1 |
| 6 | elixir | 1,340 | **php** | **8,699** | **+4** |
| 7 | swift | 1,340 | swift | 5,337 | 0 |
| 8 | **kotlin** | **1,269** | **scala** | **4,150** | **+7** |

**`unbound` is blind to structural shredding.** A parse that reads every byte
and hands back 419 roots where one belongs scores `unbound = 1,269` and looks
finished. `standing` sees it at 41.4%; `unbound` cannot, by construction.

And the three rows it demotes hardest — kotlin +5, scala +7, php +4 — are the
same defect. `walls.py` joins every orphaned row to the wall its parse actually
stopped on:

| grammar | orphan | not built | unbound | mends | standing | wall |
|---|---|---|---|---|---|---|
| kotlin | 19,705 | 20,974 | 1,269 | 142 | 41.4% | blind `_string_start` |
| php | 8,091 | 8,699 | 608 | **1** | 87.2% | blind `encapsed_string_chars` |
| scala | 4,046 | 4,150 | 104 | 4 | 79.4% | blind `_simple_string_start` |
| swift | 3,997 | 5,337 | 1,340 | 31 | 81.2% | blind `multiline_comment` |
| haskell | 8,052 | 25,048 | 16,996 | 1,806 | 26.9% | blind `_cond_qual_dot` |
| ruby | 344 | 532 | 188 | 21 | 47.8% | blind `heredoc_beginning` |
| latex | 1,024 | 1,185 | 161 | 4 | 77.4% | blind `_trivia_raw_env_verbatim` |
| verilog | 3,267 | 63,937 | 60,670 | 2,109 | 32.5% | press, state 3438 |
| julia | 2,135 | 11,047 | 8,912 | 1,194 | 59.6% | press, state 136 |
| sql | 1,635 | 2,423 | 788 | 273 | 62.1% | weave, state 256 |
| ocaml | 1,829 | 2,182 | 353 | 28 | 87.1% | lexer, byte 1996 |
| zig | 1,285 | 1,375 | 90 | 3 | 91.5% | press, state 715 |
| elixir | 219 | 1,559 | 1,340 | 34 | 96.6% | blind `_newline_before_binary_operator` |
| c / cpp | 439 / 330 | 572 / 411 | 133 / 81 | 5 / 6 | 60% / 71% | press, states 822 / 907 |
| bash | 368 | 413 | 45 | 2 | 61.3% | blind `_concat` |

**Read the last column by its owner word, not by its name.** `inquest`'s
stand-in name is a guess and this project has caught two separate explanations
of *why* being wrong; what is trustworthy is that the owner is `lexer` with a
blind external behind it, versus `press`, versus `weave`. So the table
partitions the sixteen rows into "a scanner we cannot run" and "a table defect"
and that partition is sound — the specific terminal in each `blind` cell is
`inquest`'s guess, and the only one in this dossier that has been proved
independently is kotlin's, by the ablation and not by the name.

Kotlin, php and scala together are **31,842 orphan bytes and 33,823 not-built
bytes behind three blind string-interior externals**, and the work order the
board prints ranks them 8th, 10th and 15th. That is the 21st flattering
instrument, and unlike most of the twenty it is not wrong about anything — it
is right about a question nobody is asking.

## If the wall came down

Substituting the ablation for kotlin's row, and saying plainly that this is an
**estimate and not a measurement**:

| | now | with kotlin's strings seated |
|---|---|---|
| standing | 67.3679% | **71.3027%** (+3.93 points) |
| built | 354,893 | 375,621 |
| orphan | 56,766 | 37,269 |
| unbound | 115,139 | 113,908 |
| describes | 95,150 | 95,408 |

It is the largest single move available on the board, and it is third on the
work order the board prints.

## Why I am not seating it in this lane, and what it costs

I read the pinned `scanner.c` (`.local/breadth/lang/kotlin/src/scanner.c`, 979
lines) as the spec rather than guessing from the rule shapes. Kotlin's string
is a textbook `fence` — `string_literal` is literally
`seq(_string_start, repeat(choice(string_content, _interpolation)), _string_end)`
— and `fence.Spans` already exists, is already carried on `Carry`, and is
already snapshotted for grafts, so **the memory is free**. What is not free:

1. **`serialize` writes two bytes per frame: `[delimiter|triple, prefix_len]`.**
   `fence.Span` has `triple` and `interpolates` and no `prefix_len`. Kotlin
   2.1's multi-dollar strings make the interpolation sigil a *run* of `$` whose
   required length is fixed at the opener, so the field is load-bearing, not
   decoration.
2. **The triple close is greedy and `fence.read` is not.** `read` closes at the
   first occurrence of the mark; kotlin closes a `"""` on the *last* run, so
   `""""` is one content quote and then the close. Changing that in the shared
   driver is a change to python, ruby, rust\_raw and heredoc at the same time.
3. **The two interpolation starts are emitted terminals, and `Troupe` has no
   slot for them.** `_interpolation_expression_start` and
   `_interpolation_identifier_start` are neither `open`, `body`, `close` nor
   `escape`. They need two new roles on `Troupe` and `Cast` — which the
   reflective "every troupe the eleven rely on can still seat" test will pick
   up for free, and which is also the region another lane holds for the
   `_immediate_*` zero-width work.

There is a smaller rung that avoids (3) entirely and is sound: seat
`open`/`body`/`close` only, and have `read` return `.none` on a `$`-run that
reaches `prefix_len`. Then a plain string parses and an interpolated one walls
at the `$` with a located verdict, which is the fail-closed posture this
package already prefers over a confidently wrong tree. Cost is one `Dialect`
case, an `openKotlin`, one field on `Span`, a kotlin branch in `read`, and one
troupe row keyed on `_by_delegation_hint` to keep it from colliding with Ruby's
`_string_start` anchor the way the original kotlin mis-binding did.

**And whichever rung is taken, this corpus cannot check it.** `Maps.kt` holds
90 quote characters, 45 literals, and **zero** triple quotes, **zero** `$`,
**zero** backslash escapes. Every number in this dossier would be identical
under a stateless `"[^"]*"` regex that is unsound in the field the moment a
string interpolates. The board is not the test for this change; probe files
are, and there are none yet. That is the reason I stopped at the diagnosis: the
seating is a two-hour change and the evidence for it is a day's work that does
not exist, and a fence measured only on `"1.1"` would be the sixth flattering
number found inside a lane's own fix.

## The instrument I trust least in my own work

The ablation. It proves the string family is the wall — that inference is
sound, because removing a construct and watching 139 mends vanish cannot be
explained by anything else in the file. It does **not** measure what seating
would recover. `"1.1"` blanked to `Zzzz` is a `simple_identifier`, and a seated
fence would build `string_literal(string_content)` instead; the node counts
would go up rather than down, so 8,580 `describes` is a floor. But the LR path
differs, and the third wall in this very file — `press? on , in state 110` — is
proof that a state can hold a defect the ablated path never enters. So
`+20,728 built` is the number I would bet on and not the number I would report
as measured, and the only way to promote it is to build the thing.

Second, `mended N over MB` on stderr is the whole basis of `gate.py`, and it
reports the mends of the *last* parse rather than being a property of the tree
the board scored. Both instruments read the same pinned binary against the same
folio in the same run, and the stamp says `uniform`, so they agree here — but a
lane that reruns `gate.py` against a board taken at another time is comparing
two generations, and nothing in `gate.py` would say so.

## Handed back, not chased

- `swift`'s wall is a blind `multiline_comment` — the same terminal the kotlin
  `marrow` row seats on the `kotlin_block` vein. `outside.zig` says scala reuses
  that vein "because the bytes really are the same bytes". Swift's `/* */`
  nests the same way. Nobody has tried it, and swift is 3,997 orphan bytes.
- `scala`'s `_simple_string_start` and `php`'s `encapsed_string_chars` are the
  same defect class as kotlin's, worth 4,046 and 8,091 orphan bytes; php reaches
  its 8,091 on a **single** mend.
- `contract/outliner.zone` still fails `zoning` on `language zig`, and
  `zig fmt --check` still flags `press.zig` and `wall_test.zig`. This lane
  cleared none of them; it edited no production file.

# Result 8 — the whole family re-taken with an oracle in every arm

`vacuity/RESULT-2-arms.md` cleared fourteen single-row arms of collateral and
`RESULT-5-pairs.md` cleared five pairs and the union arm. `RESULT-5-blindness.md`
then established that **every one of those twenty arms read `square 0`**, so the
clearance was taken on `damage` — joints's own words about its own forest,
which cannot see a change that leaves `built` untouched and moves every leaf to
a different parent.

This is the same population, re-taken with `standing.py --audit` paid inside
each arm's own work dir. **Twenty-one arms, 29 of 30 rows sighted in every one.**

## The answer

**The clearance survives, and this is the first time it has been claimed.**

Every arm moves exactly the grammars its own rows seat, and **no arm moves any
other grammar on any column** — 13,728 cells of twenty-four numeric columns
across twenty arms, zero differences (`collateral.py`). Five of those columns
(`square`, `crooked`, `soft`, `unframed`, `trued`) are the oracle's words rather
than ours, where the original clearance had none.

A second, oracle-free check says the same thing byte-for-byte: every arm's
**parse trees** were captured and diffed against base (`verilog/trees.py`). Each
single and pair arm is **tree-identical on 29 of 30 grammars** — the thirtieth
being the one it seats — and the union arm, with all fourteen rows out at once,
is **tree-identical on 21 of 30**, exactly the twenty-one nobody seated. That
check does not consult the oracle at all, so it also covers `yaml`, the one row
no board can grade, and every unaudited byte on the other twenty-nine.

## Per arm, on `square`

Positive worth means the seating is doing good: on `square` that is
`base − arm`, on `damage` it is `arm − base`. Base arm: **311,540 square** over
29 sighted rows, **126,927 damage**.

| arm | seat | grammar | square | worth | damage worth | roots | collateral |
|---|---|---|---|---|---|---|---|
| r0 | `_indent/.offside/.slashes` | scala | 6,739→0 | **+6,739** | +7,763 | 26→315 | none |
| r1 | `_cmd_layout_start/.writ` | haskell | 5→0 | **+5** | +9,168 | 2582→94 | none |
| r2 | `_string_start/.fence/.kotlin` | kotlin | 35,324→8,181 | **+27,143** | +20,737 | 10→424 | none |
| r3 | `multiline_comment/.marrow/.swift_block` | swift | 14,419→14,419 | **+0** | +0 | 128→128 | none |
| r4 | `block_comment/.marrow/.kotlin_block` | scala | 6,739→203 | **+6,536** | +2,407 | 26→1273 | none |
| r5 | `comment/.marrow/.ocaml_comment` | ocaml | 12,165→11,717 | **+448** | **−721** | 167→349 | none |
| r6 | `_quoted_content_double/.marrow/.elixir_quoted` | elixir | 23,879→1 | **+23,878** | +21,525 | 1→3417 | none |
| r7 | `_content_str_1/.marrow/.julia_quoted` | julia | 24,382→15,472 | **+8,910** | +5,471 | 138→934 | none |
| r8 | `_immediate_paren/.abut` | julia | 24,382→8,438 | **+15,944** | +9,094 | 138→1591 | none |
| r9 | `encapsed_string_chars/.marrow/.php_encapsed` | php | 67,845→662 | **+67,183** | +8,699 | 1→119 | none |
| r10 | `_trivia_raw_env_verbatim/.marrow/.latex_verbatim` | latex | 5,246→108 | **+5,138** | +1,185 | 1→72 | none |
| r11 | `_implicit_semi/.caesura/.swift` | swift | 14,419→545 | **+13,874** | +13,101 | 128→1332 | none |
| r12 | `_automatic_semicolon/.caesura/.kotlin` | kotlin | 35,324→4,494 | **+30,830** | +19,229 | 10→1052 | none |
| r13 | `_newline_before_do/.caesura/.elixir` | elixir | 23,879→1 | **+23,878** | +1,329 | 1→217 | none |
| r0-4 | scala's pair | scala | 6,739→11 | +6,728 | +2,798 | 26→1261 | none |
| r2-12 | kotlin's pair | kotlin | 35,324→4,674 | +30,650 | +19,678 | 10→1140 | none |
| r3-11 | swift's pair | swift | 14,419→545 | +13,874 | +13,101 | 128→1332 | none |
| r6-13 | elixir's pair | elixir | 23,879→1 | +23,878 | +21,382 | 1→3376 | none |
| r7-8 | julia's pair | julia | 24,382→117 | +24,265 | +14,728 | 138→2477 | none |
| union | all fourteen | 9 grammars | 311,540→139,371 | **+172,169** | +109,058 | — | none |

**The union decomposes exactly.** Every grammar in the union arm reads the
identical value its own pair arm gives it — union scala = r0-4 scala to the
byte, union julia = r7-8, union kotlin = r2-12, union elixir = r6-13, union
swift = r3-11 = r11, union php = r9, union latex = r10, union ocaml = r5, union
haskell = r1. Fourteen rows removed at once do exactly what they do one at a
time. That is a stronger statement than any single arm makes, and it is the one
statement the original family most wanted and could least support.

## What `square` says that `damage` did not

**One row's sign flips.** ocaml's `comment/.marrow/.ocaml_comment` is the only
seating on the board whose grammar got *worse* on `damage` — the changelog
fragment says so in its first paragraph, and it is the day's one published
regression. Sighted, un-seating it **lowers `damage` by 721 and lowers `square`
by 448**: the seating is a 448-byte *gain* in agreement with tree-sitter, priced
by `damage` as a 721-byte loss. `RESULT-7-witnesses.md` found this on scala's
and ocaml's rows over its own fixtures; it reproduces here on the corpus board
against a control pinned in the same snapshot.

The mechanism is the reason it will keep happening: **a correctly-recognised
comment is an orphan and a misread one is `built`.** Any `damage`-only reading
of a comment, docstring or declared extra is biased in that known direction.

**Five rows are worth more than twice as much on `square` as on `damage`**, and
all five seat an extra or a separator:

| row | seat | square ÷ damage |
|---|---|---|
| r13 | elixir `_newline_before_do/.caesura` | **18.0×** |
| r9 | php `encapsed_string_chars/.marrow` | **7.7×** |
| r10 | latex `_trivia_raw_env_verbatim/.marrow` | **4.3×** |
| r4 | scala `block_comment/.marrow` | **2.7×** |
| r5 | ocaml `comment/.marrow` | **sign flip** |

elixir's `_newline_before_do` row is the extreme: `damage` prices it at 1,329
bytes, which on a 46,089-byte file reads as a rounding error, and `square`
prices it at **23,878 — the entire agreement elixir has with tree-sitter.**

**And one row is worth almost nothing where `damage` is loud.** haskell's
`_cmd_layout_start/.writ` is worth 9,168 on `damage` and **5 on `square`**,
because haskell's whole board square is 5 bytes. A clearance that scored
haskell on `damage` was scoring the one grammar whose agreement with tree-sitter
was already annihilated before the row was seated.

## Every non-trivial pair is a ceiling, and `damage` can only see two of them

Residual = (solo + solo) − joint. Positive means sub-additive: the two rows
overlap rather than add.

| pair | grammar | square residual | damage residual | ceiling |
|---|---|---|---|---|
| r0-4 | scala | **+6,547** | +7,372 | 6,739 (its whole square) |
| r2-12 | kotlin | **+27,323** | +20,288 | 35,324 |
| r6-13 | elixir | **+23,878** | +1,472 | 23,879 |
| r7-8 | julia | +589 | −163 | 24,382 |
| r3-11 | swift | 0 | 0 | — |

**Nothing on this board is super-additive on `square`.** Every residual is zero
or positive, which is the arithmetic signature of a ceiling: two rows that each
destroy nearly all of one quantity cannot also sum. `RESULT-6-scala.md` reached
that for scala; it now holds for kotlin and elixir too, and the word
*cooperating* is wrong for all three.

**elixir's pair is the new one and it is invisible to `damage`.** Each elixir
row alone costs **23,878 of elixir's 23,879 square — 99.996%** — so the square
residual is the whole ceiling, while the `damage` residual is 1,472 on a 46,089-
byte file. A pair sweep run on `damage` would file elixir as roughly additive
and never learn that either row alone is total.

**julia and swift are genuinely additive** and stay that way sighted: julia's
+589 is under the 1,000-byte slack the pair rule uses, and swift's is exactly 0
because r3 is exactly inert.

## Predictions, scored

Written in `PREDICTION-3-sighted.md` before the first arm was built. Four right,
four half, one wrong, one deferred.

- **P1 — the clearance survives, no non-owner `square` moves. RIGHT**, and
  wider than claimed: zero movement on twenty-four columns, corroborated by
  byte-exact trees.
- **P2 — a spurious move would show in more than one arm. NOT TESTED.** No move
  occurred, so the discriminator never fired. It is not a hit.
- **P3 — every worth ≥ 0, exactly one exactly 0, and it is swift's row 3.
  RIGHT.** r3 is 0 on both columns and, better than predicted, **tree-identical
  on all thirty grammars** — the row is invisible to the whole fixture tier,
  which is the stated reason (`Chunked.swift` has no `/*`) proved rather than
  asserted.
- **P4 — `square` silent where `damage` is loud, on at least two rows. HALF.**
  The named row is right (haskell, 5 against 9,168) and it is the **only** one:
  every other row with a loud `damage` also moves `square`.
- **P5 — at least two rows worth > 2× on `square`, and they are extras. RIGHT**
  on the count (five) and on scala's row 4 holding at 2.7×; the guess about
  which third row would join was 1 of 3 (latex yes, elixir r6 and julia r7 no).
- **P6 — kotlin's pair is a ceiling like scala's. HALF.** The conclusion holds
  and the residual is +27,323, well past the predicted +10,000 — but the stated
  reason was that *each* row alone costs more than 85%, and r2 costs 76.8%.
- **P7 — a pair that is additive on `damage` is not on `square`. WRONG** as
  stated on this tree. julia is the only damage-additive pair here (−163) and it
  stays additive on `square` (+589). The prediction survives only against the
  *published* table, where elixir read −177 and additive; on this snapshot
  elixir's damage residual is +1,472. Elixir is the right finding and I got to
  it with the wrong pair and the wrong number.
- **P8 — union loses 150k–230k square and no tenth grammar moves. RIGHT**:
  172,169 lost, nine grammars moved, ten never.
- **P9 — `crooked −335` reproduces on the row-4 arm; one to three arms show a
  negative, all with `roots > 500`. HALF.** Three arms show one (r4, r0-4,
  union — all scala), and all three have `roots > 500`. But the value is
  **−8,669**, not −335, the condition is nowhere near sufficient (56 rows on
  these boards have `roots > 500` and 53 are fine), and the mechanism I named —
  soft attribution running out of room on a shredded parse — is **wrong**. See
  `HANDOFF-crooked.md`.
- **P10 — the blindness reaches ≥ 8 other conclusions, ≥ 3 about extras.**
  Scored in `RESULT-9-reach.md`.

The one I got wrong in the expensive direction was P9's mechanism: I had a story
for the negative and the story was wrong, and I would have shipped it if the
handoff had not been worth a probe of its own.

## How it was taken

`sighted.py` — one snapshot of `src/` for all twenty-one arms, one build tree
per worker, three arms at a time, ~120 s each. Each arm gets its own
`JOINTS_WORK`, pays its own `--audit`, and is required to read its own
verdicts back; an arm whose `src/` differs from the snapshot in anything but
`outside.zig` is dropped by name rather than measured.

Two things about the run that a reader should know:

**The snapshot is not live `src/`.** At 23:50 the quire lane's in-flight
`gather.zig` did not compile, and a family of twenty-one arms cannot be taken
against a tree that will not build. `$SIGHTED_SRC` pointed every arm at an
hour-old whole snapshot instead. That is the fifth house rule doing its job: all
twenty-one arms are in one world, and it is not today's.

**The oracle changed under the sweep and it was checked rather than assumed.**
The rack lane landed a field mid-run and three pair arms died on
`Seen.__new__() missing 1 required positional argument: 'airy'`. They were
re-taken afterwards — which puts three arms on a different `rack.py` than the
other eighteen. So the base arm was re-audited under today's `rack.py` into a
second work dir and compared: **30 of 30 rows identical on all eight columns**
(`boards/base2.json`). The change is measurement-neutral and the family is one
family. Had it not been, all eighteen would have needed re-taking.

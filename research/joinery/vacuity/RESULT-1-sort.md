# Result 1 — the inventory, sorted by whether the clearance could have responded

Scores `PREDICTION-1-inventory.md`. The sort is the lane: a lane that reached for
a responsive instrument is cleared and recorded as cleared, and most of them did.

## The recited list, checked against the tree

I was told to verify the list rather than trust it, and it moved in three places.

| recited | in the tree? |
|---|---|
| php `encapsed` family | **yes** — `encapsed_string_chars/.marrow/.php_encapsed` |
| elixir `caesura` + `_quoted_atom_start` | **yes** — two rows, `.caesura/.elixir` and `.marrow/.elixir_quoted` |
| latex `marrow` family | **yes** — `_trivia_raw_env_verbatim/.marrow/.latex_verbatim` |
| kotlin strings | **yes** — `_string_start/.fence/.kotlin` |
| swift `multiline_comment` | **yes** — `.marrow/.swift_block` |
| haskell layout on `writ` | **yes** — and my prediction that it did not land was wrong |
| scala layout | **yes** — `_indent/.offside/.slashes` |
| julia zero-width `abut` | **yes** — `_immediate_paren/.abut` |
| the scanner's `spot` attribution fix | **yes, but not a seating** — it moves where a wall is reported, not what is parsed |

Short by two. `comment/.marrow/.ocaml_comment` and
`block_comment/.marrow/.kotlin_block` were seated today, are in the roster, and
have no changelog fragment of their own - they are argued in
`research/joinery/bench.report` instead. The ocaml one is the only seating today
whose grammar got *worse*, so the row missing from `changelog.d` is the row
carrying the day's only published cost.

Counting rows rather than headlines: **32 roster rows live, 18 at `HEAD`, 14
seated today**, across nine grammars. **Five of those nine carry two rows each
and none carries three** - scala, kotlin, swift, elixir and julia - which is why
the union arm cannot attribute and fourteen arms were needed. (Recited here
first as two-and-one; `ablate.py guests` computes it from the roster and the
grammars' own externals, and `RESULT-5-pairs.md` measures all five pairs.)

## The sort

A folio is the pressed table. A board or a tree comparison is recomputed from
the binary. So the question for each lane is only *which artifact did it diff*.

### Cleared — the instrument could have said otherwise

| landing | what it offered | why that responds |
|---|---|---|
| php `encapsed` | `rack`'s own without-php split reading 204,921 square identically on both arms | the split is recomputed per arm; php's own row moved 67,685 in the same run |
| latex `marrow` + elixir `caesura` | an isolation build, and the dossier names the folio trap explicitly | `seams/RESULT-2-numbers.md`: "a `Troupe` seat does not change one - latex's folio is byte-identical between the arm scoring 108 and the arm scoring 5,246" |
| kotlin strings | 29 of 30 tree-identical, "compared as trees, not as folio digests" | the sentence is the sort, written by the lane itself |
| swift `multiline_comment` | all 30 grammars tree-identical | an honest `--inert` claim: this one moves the board by zero bytes, and my arm agrees |
| julia `abut` | 29 of 30 tree-identical, julia's wall moved `lexer` → `press` | responsive, and the wall move is a second falsifier |
| the `spot` fix | `survey-before-spot.json` vs `survey-after-spot.json` | 18 of 30 grammars' wall reports changed - an instrument that moved that much was not asleep |
| the resume/splice runtime fix | `probe` byte-identical on four grammars *and* a reproducer that fires under trace | the claim is equivalence, falsified by its own reproducer, which is `--inert` done right |

Seven cleared. That is most of them, and it is a perfectly good result.

### Vacuous — the clearance could not have responded

I could not re-judge the recorded pairs with the gate itself: **`still against`
needs a witness recorded at measurement time, and the historical pins have
none.** A gate that can only judge pairs taken after it existed cannot audit the
pairs that motivated it. So this list is read out of the record rather than
re-taken, and the re-establishment is `RESULT-2`.

1. **Rows 1, 3 and 5 of the recorded six**, per the gate's own restoration - row
   1 because a shared folio cache makes both arms read one artifact, rows 3 and
   5 because a scanner refresh and a lex fix cannot move a pressed table.
2. **Row 6, the case the gate was built for** - `folio!` and nothing else,
   carried while one grammar went 108 → 5,246 square.
3. **A fourth, not in the six:** `verilog/RESULT-3-provenance.md` clears a
   `src/kernel/quire/` edit partly on 27 of 30 folios being byte-identical. A
   quire edit cannot move a pressed table, so that half of the argument is
   vacuous. The other half - 29 of 30 *trees* identical - is responsive and
   carries the conclusion, so the finding is a weak sentence in a sound dossier,
   not a wrong result. It is another lane's file; I have not touched it.

**Four in the record, and the fourth was invisible to the gate's own backward
pass** because that pass enumerated the six recorded cases and this one was
never recorded as a pair.

### Out of reach of this instrument

The `spot` fix and the two runtime lanes changed no roster row, so an ablation
arm cannot isolate them - they sit in both arms. Sorted above on their own
evidence. The `graft.stoop` lift was reverted and ships only its guard; there is
no collateral surface to audit.

## Score

| prediction | outcome |
|---|---|
| **vacuous: 3 of 10** | **4** (three the gate names, one it was built for, one I found in verilog). Under by one, and the reasoning held: the count is just the count of lanes that reached for the folio. |
| **actually wrong: 0** | **0 among the fourteen seatings.** Held. Every arm moves one grammar and it is its own. |
| the recited list is wrong in two places | **half right.** `spot` is not a seating, as predicted. Haskell's `writ` layout *did* land, and it is worth 9,192 bytes of haskell damage - the largest single seating on the board after kotlin's strings. |
| the list is complete | **wrong** - short by ocaml `comment` and scala/kotlin `block_comment`. |
| four arms cannot bear the fourth house rule | **unresolved, and deliberately so.** Rather than adjudicate four historical pairs I replaced them with fourteen arms taken from one snapshot, which is strictly stronger than repairing the old pairs would have been. |
| at most two isolation arms needed | **badly wrong: fifteen.** The union arm cannot attribute when nine grammars carry fourteen rows, so per-row arms were not optional. |

The gap between 4 and 0 is the whole finding: **four unsupported claims, zero
false ones.** The corpus was in better shape than its audit trail proved.

# Result 2 — fifteen isolation arms, and what each seating actually moved

> **Clearance upheld, on a wider instrument (2026-08-06).** Every arm on this
> page read `square 0` (`consort/RESULT-5-blindness.md`), so "no other grammar by
> a single column" was thirty-one columns of joints's own words about its own
> forest. `consort/RESULT-8-sighted.md` re-takes all fourteen singles, the five
> pairs and the union arm with an oracle minted inside each arm: **no arm moves a
> grammar its rows cannot seat, on any of twenty-four columns**, and every arm is
> byte-exact tree-identical on every grammar it does not seat. What did change is
> the *worth* of the rows - haskell's is 9,168 on `damage` and **5** on `square`,
> elixir's `_newline_before_do` is 1,329 on `damage` and **23,878** on `square`,
> and ocaml's row changes sign.

The re-establishment. Every number below was taken by `tool/standing.py` with its
own `JOINTS_BIN`, its own `JOINTS_WORK` and its own `JOINTS_LANE`, from a
binary `tool/pin.py build` minted in a scratch checkout.

## The board had settled

The task's warning was that the board flapped at 20:05 while two lanes edited
`outside.zig` and `gather.zig`. Checked before trusting a row:

```
python3 tool/standing.py --twice=3
STABLE — every one of the 930 numbers is identical across all 3 runs.
```

Re-checked at the end with `--twice=2`: stable again. Thirty grammars × 31
columns, three separate processes, so the folio decisions and the oracle memo are
re-taken rather than inherited.

## The union arm

Today's roster with all fourteen of today's rows deleted and every seam, walk,
dialect and vein left standing. **Nine of thirty grammars move; the remaining
twenty-one are byte-identical in all 31 columns.** The nine are scala, haskell,
kotlin, swift, ocaml, elixir, julia, php and latex - exactly the nine that carry
a row seated today, with no tenth.

That answers *did the day reach a grammar nobody seated* with a no. It cannot
answer *which* row moved scala, because scala carries two.

## The fourteen arms

One arm per seating: today's tree with exactly one row removed. `arm` is that
arm's damage in bytes, `all in` is the un-ablated control's, and the last column
is what the seating is worth. Control tree `9d26ca82e78b`, every arm minted
against it, `--mine` taken by diffing each arm's `src/` against the snapshot and
requiring exactly one changed file.

| seating | grammar | arm | all in | worth |
|---|---|---|---|---|
| `_string_start/.fence/.kotlin` | kotlin | 20,974 | 246 | **−20,728** |
| `_quoted_content_double/.marrow/.elixir_quoted` | elixir | 21,201 | 0 | **−21,201** |
| `_automatic_semicolon/.caesura/.kotlin` | kotlin | 19,450 | 246 | **−19,204** |
| `_implicit_semi/.caesura/.swift` | swift | 16,024 | 5,337 | **−10,687** |
| `_cmd_layout_start/.writ` | haskell | 34,240 | 25,048 | **−9,192** |
| `_immediate_paren/.abut` | julia | 11,047 | 1,953 | **−9,094** |
| `encapsed_string_chars/.marrow/.php_encapsed` | php | 8,699 | 0 | **−8,699** |
| `_indent/.offside/.slashes` | scala | 11,913 | 4,150 | **−7,763** |
| `_content_str_1/.marrow/.julia_quoted` | julia | 7,424 | 1,953 | **−5,471** |
| `block_comment/.marrow/.kotlin_block` | scala | 6,557 | 4,150 | **−2,407** |
| `_newline_before_do/.caesura/.elixir` | elixir | 1,329 | 0 | **−1,329** |
| `_trivia_raw_env_verbatim/.marrow/.latex_verbatim` | latex | 1,185 | 0 | **−1,185** |
| `comment/.marrow/.ocaml_comment` | ocaml | 1,461 | 2,182 | **+721** |
| `multiline_comment/.marrow/.swift_block` | swift | — | — | **0** |

**Thirteen arms move exactly one grammar. One moves none. In every case the
grammar that moved is the grammar the row was seated for.** No arm moved a second
grammar by a single column, and there is no thirty-first column to hide in.

Two readings worth stating because they were the two ways the prediction could
have died:

- **`kotlin_block` reaches scala, and it is supposed to.** Its vein's guest list
  is `{kotlin, scala}`, and that shared vein was the first mechanism I expected a
  silent widening from. It moves scala by 2,407 bytes *in the direction of
  fixing it* and moves nothing else. The guest list is doing its job.
- **ocaml is the only grammar today whose damage rose**, 1,461 → 2,182, standing
  91.34% → 87.07%. That cost is in the record: `research/joinery/bench.report`
  argues it and `orphan/RESULT-2-wall.md` carries the 2,182. So the day's one
  regression was published, argued, and accepted - not hidden by a check that
  could not see it. It is the one row with no changelog fragment of its own,
  which is the wrong row to leave out.

Kotlin's two rows and julia's two are each individually necessary rather than
additive: removing either kotlin row restores ~20,000 bytes of damage, and
removing either julia row restores most of julia's. A seating is not a
contribution to be summed, it is a permission the walk needs.

> **The `worth` column may not be added down, and the kotlin rows are why.**
> Each figure is a **marginal** - what that row buys *given every other row is
> already seated* - so where one grammar owns two rows both marginals price the
> same stretch of file. Kotlin's two, at −20,728 and −19,204, are one 19,678-byte
> gate reported twice; its whole defect is 20 KB and this column claims 40.
> `Maps.kt` walls at byte 245 without the caesura and at byte 270 without the
> fence, and the 35,571 bytes behind both are what each solo arm is measuring.
> The only per-row credit that sums back to the pair is the Shapley split:
> **+10,593** for the fence and **+9,085** for the caesura.
> `research/joinery/consort/RESULT-1-kotlin.md` has the mechanism and the
> falsifiers; `RESULT-5-pairs.md` has the residual for julia and scala too.
>
> Note also that this table's controls are **not** the controls in `arms.json`
> or `RESULT-5-pairs.md`: scala's `all in` is 4,150 here and 16,883 there,
> elixir's is 0 here and 8,795 there. A press regression landed between the two
> days, so figures from the two pages must not be subtracted from each other.

## The sweep was re-taken after a sibling landed, and agreed

`src/kernel/quire/gather.zig` landed from another lane during the first sweep, so
the scratch tree stopped being an isolation arm of the live tree. **The `--mine`
check refused to print a number and named the file**, which is the whole point of
it - it failed at the file, by name, before printing anything. Then two
`src/press/` files landed during the second sweep and it fired again.

Chasing a tree that moves every two minutes is a losing race, so the family was
re-anchored: one pristine snapshot of `src/`, the control minted from it, all
fourteen arms ablated from it, and `--mine` taken against the snapshot rather
than the drifting tree. `ablate.py` reads its roster from the snapshot too, via
`$ABLATE_SRC`, because a row index taken from a file that moved between two arms
names two different seatings under one number.

That second sweep - control tree `92e7faa9b55a`, which contains the `src/press/`
edits - reproduces the structure exactly: **thirteen arms move one grammar, one
moves none, and every moved grammar is its arm's own.** Every arm's own damage
figure is within a few bytes of the first sweep. The magnitudes for scala and
elixir invert, because the control regressed underneath them on an uncommitted
`src/press/` intermediate that has since been withdrawn; that is
`RESULT-3-press.md` and it is not a seating.

The current tree agrees with control A on damage and standing for all thirty
grammars - it differs only in `nodes` on cpp, go and swift - so the `worth` column
above describes the tree as it stands, not just as it stood.

The structural conclusion surviving a 12,733-byte sibling regression landing in
the middle of the sweep is a better robustness statement than a single clean
sweep would have been.

## What it costs in confidence

- **It is a reconstruction.** These arms are today's tree minus a row, not the
  arms the lanes took. They answer the question that matters - does this seating
  break another grammar in the tree as it stands - and say nothing about whether
  the original pairs were sound. Four of them were not, and it did not matter.
- **`--mine` is taken, not asserted**, and it fired twice for real reasons.
- **Fourteen rows, not fourteen lanes.** A lane that changed runtime as well as
  its roster row has only its row audited here; the runtime half is in both arms.
  `RESULT-1` sorts those on their own evidence.
- **The snapshot freezes siblings out.** That is the cost the fifth house rule
  warns about, paid deliberately: with ten lanes editing, a family of fifteen
  arms cannot be taken against a moving control without the arms disagreeing
  about which world they are in. All fifteen share one world; that world is four
  minutes old rather than live.

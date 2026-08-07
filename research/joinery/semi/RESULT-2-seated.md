# The separator seated: swift and kotlin move, scala declines

> **Holds, and it under-priced itself by up to 18× (2026-08-06).** Every column
> below is ours: `built`, `orphan`, `rubble`, `spoil`, `unbound`, `standing`. So
> the attribution proof this page rests on (*exactly two grammars moved*) was
> taken without a second parser in it. Re-taken with one, per row, in
> `consort/RESULT-8-sighted.md`:
>
> | caesura row | priced here | sighted `square` |
> |---|---|---|
> | kotlin `_automatic_semicolon` | part of `unbound −12,712` | **+30,830** |
> | swift `_implicit_semi` | part of the same | **+13,874** |
> | elixir `_newline_before_do` (seated later, same hand) | +1,329 `damage` | **+23,878 — 18×** |
>
> The clearance holds too, and on more than it claimed: twenty-four columns
> including five of the oracle's move for the seated grammar and **nobody else**,
> and the arms are additionally byte-identical in their parse trees on 29 of 30
> grammars. `unbound −12,712` was a floor, not a measurement of the win.
>
> **The kotlin regression this page refused to launder is withdrawn as a
> regression.** *"`built` falling means some bytes that were under a construct are
> not any more, and I am not going to launder that as a metric artifact"* was the
> right discipline and the wrong verdict. Sighted, kotlin's post-seating board is
> **35,324 `square` of 35,571 built — 98.6% `trued`, the highest on the corpus,
> with 247 bytes uncorroborated in total** (their `crooked`/`unframed` split is
> pending the repair in `consort/HANDOFF-crooked.md`; the total is not). The 3,653
> bytes that moved into
> `orphan` are the mechanism `orphan/RESULT-2-wall.md` named and ocaml's row later
> proved: **a correctly-recognised extra is an `orphan` and a misread one is
> `built`**, so a `built` drop on a KDoc-dense file is the shape of getting the
> comments right. `standing` charged it as loss; `square` says it cost nothing
> measurable. The −1,075 arithmetic stands as printed; the words *"a smaller
> regression inside a larger win"* do not.
>
> Nothing here was re-measured.

Twenty-one of swift's 33 externals seated and two of kotlin's ten answered, on
one new mechanism and one existing one. Scala declined with its reason written
down. The board's unbound fell 12,712 bytes and **exactly two grammars moved**,
which is the attribution proof as much as the win.

## What was built

**One new tongue on an existing hand.** `caesura.zig` already answered
javascript's zero-width semicolon by asking the parser two questions its
scanner asks (`is ||` legal here, could a signature end here). Swift and kotlin
need the same *shape* and a different *rule*, so `caesura.Tongue` selects among
three transcriptions rather than parameterising one. That was the right call for
a reason worth recording: **swift's rule is the inverse of ecma's.** JavaScript
suppresses a break before a line resuming with an operator, because `x\n + y` is
one expression. Swift requires a binary operator to sit on the line it
continues - which is precisely why `_plus_then_ws` is external and is named for
its trailing whitespace - so swift *inserts* a separator before a leading `+`.
A single parameterised rule would have had to be wrong for one of them.

A break now carries a width, because a written `;` is the same decision reached
a second way and swift gives it a different terminal (`_explicit_semi`). That is
the `Troupe.spelled` role.

**Nineteen operator rows, transcribed rather than named.** The scanner keeps
three parallel tables - `OPERATORS` for the spelling, `OP_SYMBOLS` for the
terminal, `OP_ILLEGAL_TERMINATORS` for the refusal - and `swift_roll` in
`outside.zig` is those three joined at the index. Every refusal group maps onto
trailing context that `Provision` already had: `never` for the three that forbid
a following byte class, `after` for the one that requires whitespace.

## The board

Baseline is `baseline-board.json`, minted 17:13Z from commit `f7ba40004` with 60
dirty files; treatment is `treatment-board.json`, 17:40Z from the same commit
with 65. Untouched grammars are identical across the pair - verilog's rubble is
14,057 in both, php's unbound 608 in both - so the delta is this change's.

```
grammar         built   orphan   rubble    spoil  unbound    nodes   leaves    roots
swift          +15336    -5202    -4631    -5503   -10134    +2134    -1188    -1571
kotlin          -1075    +3653    -1525    -1053    -2578     +747     -454     -715
TOTAL          +14261    -1549    -6156    -6556   -12712    +2881    -1642    -2286
```

Board: `62.1% -> 64.8% standing`, `81.4% -> 82.6% covered`, unbound
`134,630 -> 121,918`. Twelve grammars still parse whole; none regressed.

### Read as the brief demands

**rubble and spoil as a pair.** Both fell, and that is worth saying because the
brief warned the opposite was likely. When haskell was seated, rubble rose 7,935
while spoil fell 17,056, because bytes entered the metric's reach for the first
time. Swift's did not, because swift's bytes were *already* reached: at 1,879
roots over 813 non-blank lines the parse was touching everything and structuring
almost none of it. So this fix drains both buckets instead of moving one into the
other - rubble 4,931 -> 300, spoil 6,543 -> 1,040.

**`describes`, alongside.** 97,079 nodes, up 2,881. Swift alone went 3,950 ->
6,084. That is the check that matters most here, because `built` rose 15,336 and
a policy that lifts `built` while printing fewer nodes is reading less, not more.
This reads more: +54% nodes on swift for +197% built.

**Bare leaves, explicitly.** Swift 1,367 -> **179**. Kotlin 691 -> **237**. This
was the specific flattery risk - a stand-in that emits tokens without structure
raises `covered` while raising bare leaves - and it went the other way by a
factor of seven. Swift's roots fell 1,879 -> 308 and its mends 836 -> 31.

**Kotlin's `built` fell 1,075 and its `standing` fell 3 points, and that is
real.** Its unbound fell 67% and its code-rubble 82%, but 3,653 bytes moved
*into* `orphan` - bytes under a top-level leaf the grammar calls an extra. Kotlin's
corpus is KDoc-dense, so a parse that now reaches further recognises comments
that were previously unreached, and `standing` charges a recognised comment
sitting at top level exactly what it charges a lost construct. Some of that is
the watermark `standing.py`'s own docstring describes. But `built` falling means
some bytes that *were* under a construct are not any more, and I am not going to
launder that as a metric artifact: it is a smaller regression inside a larger
win, and kotlin's remaining wall is its string troupe (`_string_start`), which is
carried-state work this lane declined.

## Verified

**Tests.** `kernel.lex` whole: 119 passed, 0 failed. `press.`: 96 passed. The
seating table (`scanner:`, 34), the hand (`caesura`, 15 - seven of them new), the
troupe convention (3), and every `swift`/`kotlin` test pass on the current
binary. `zig fmt --check` clean on all three files touched.

Five shards - 7, 11, 13, 14, 15 - went red in the 32-way run and **pass
standalone, 0 failed each**. They are `amend_test.zig`, which embeds
`test/grammar/json.json`, and json declares `externals: []`: zero casts, so
neither the swift rows nor the new tongues can execute there. Their diagnostics
(`child outside its parent`, `expected 772, found 773`) are span arithmetic under
incremental amend, in the `weave.zig`/`settle.zig` files a precedence lane has
open. Not chased, per the brief.

**Folio persistence, by hand, since the gate has not landed.** `Troupe.spelled`
and `Troupe.tongue` are new fields, so this is the check that fails silently in
the direction of no-change. Minted each grammar to a folio and parsed the same
source both ways:

```
swift   291 tree lines   folio == grammar, byte-identical
kotlin  415 tree lines   folio == grammar, byte-identical
scala   307 tree lines   folio == grammar, byte-identical
```

Nothing was dropped at mint. And the grammar the co-admission walk read
(`.local/breadth/lang/swift/src/grammar.json`) hashes identically to the pinned
`upstream/grammars/swift.json`, so the measurement is over the grammar the press
read.

**Scanner-version fidelity, which is the one gap left in the derivation.** No
`scanner.c` is vendored here - the only copy on this machine is a compiled wheel
in uv's cache - so the 19 operator rows were transcribed from the upstream
scanner at HEAD while the press reads a pinned `grammar.json`. Those can drift.
Checked: all 19 transcribed names are declared externals of the pinned grammar,
and every troupe name resolves in the language that declares it
(`_automatic_semicolon` in kotlin and *not* in swift, which is what binds the two
caesura rows to the right tongues).

That check is cheap because the mechanism makes the failure mode safe rather than
silent: `provisionFor` binds a row **by name** against the grammar in hand, so a
row transcribed from a newer scanner than the pinned grammar simply fails to bind
and the terminal stays blind. A stale transcription can cost coverage; it cannot
mis-lex. The remaining exposure is narrower and real - a scanner that kept a
terminal's *name* while changing its *refusal table* would bind and be wrong -
and the only cure for that is vendoring the scanner beside the grammar it was
pinned with, which is a lane of its own.

## Predictions, including the one that failed

Written before the measurement, in the files named for them. The two that
mattered both failed, which is the pattern this session keeps finding.

**Prediction 1 (`PREDICTION-1-cohort.md`) - failed, and it reframed the task.**
The brief states that `outside.Provision` requires a grammar's whole external
cohort: spell all N or spell none. It does not. `provisionFor` requires *a row's
own* cohort - the other terminals the scanner that row was read from emits - and
never the grammar's full list. Measured, eight grammars were already running
partially seated before this lane touched anything: bash spells 3 of 4, ruby 3 of
7, python 1 of 4. So there was no door to get past, and no fail-closed partial
to design. Blindness already *is* the fail-closed mechanism: a blind external is
in no action row at all, so a state waiting for one stops with a located wall
instead of accepting a plausible tree. Swift now has 12 blind terminals and
stops honestly on them.

**Prediction 3 (`PREDICTION-2-mechanism.md`, third section) - falsified by its
own stated test, and it is the prediction that mattered most.** It reads: *"I
predict `_implicit_semi` shares its states with **many** rivals, typically
tens,"* on the reasoning that a statement boundary is where every token able to
start the next statement is legal. It named its own falsifier: *"count shiftable
terminals per state admitting `_implicit_semi`. If the median is ~1, I am wrong
and `writ`'s late protocol transplants directly."* And it drew a design
conclusion from the prediction - that a `caesura`-style hand must answer **early**
from bytes, because a late hand would never fire.

Measured (`population.py` -> `population.json`), all 3416 states:

```
                   in expected set   alone there   shiftable in   only shift
_implicit_semi          1712              0             20             0
_explicit_semi          1706              0             14             0
```

Shiftable in 20 states, and the *entire* company across those 20 is three
terminals: `_explicit_semi` (14 states), `while` (6), `multiline_comment` (4). So
about one other shiftable terminal per state - **median ~1, which is the exact
condition the prediction named for being wrong.** The design conclusion is wrong
with it: the late protocol *is* available, and what shipped answers late, after
the slate, as `caesura` already did. Had I built to the prediction I would have
written an early-answering hand, which is the one shape that reads shared lexical
state per reading and is how GLR forks corrupt each other.

**The reason the prediction's reasoning felt right is the number beside it, and
that number is a different question.** An LR row prints two verbs - `read on` for
a shift, `fold X -> Y` for a reduce on that lookahead - and the union is what a
real tree-sitter scanner reads as `valid_symbols`. On *that* reading
`_implicit_semi` is in 1712 of 3416 states and alone in none, which is the
"tens of rivals" the prediction described. Both numbers are true. Only one
governs whether the slate produces a token to compete with, and it is the narrow
one: at the separator's offset the wide-population rivals are reduce lookaheads,
which fold without consuming a byte, so they never put a token in the hand. The
first pass (`coadmit.json`) measured shifts and got 20; I then re-measured, got
1712, and briefly wrote *that* up as "the number my design had to survive." Both
write-ups were confident and they cannot both be right.

Confirming the brief's own diagnosis: state **1226**, which the brief names as
the wall, is one of the 14 states where *both* spellings are shiftable. That is
why an explicit `;` failed too, and why seating one without the other would have
half-fixed it.

**A third, unwritten, and it failed too.** After seating, swift's wall moved to
`unexpected ) at 1492 in state 141`, and byte 1414 is `!base.isEmpty` - the `!`
being the one operator I declined. I predicted the decline was the cause.
Probed at minimum scale, `if !base.isEmpty { x = 1 }` parses to one root, and so
does `let y = endOfChunk(startingAt: base.startIndex)`. Neither construct is the
defect; the wall needs both. Exactly the nested-wall shape the brief warned
about, and I would have spent the rest of the lane seating a terminal that was
not the problem.

## The instrument I trust least

**`joints state`'s row, because it is the one that actually fooled me, and it
did it by being complete.** The row lists every terminal the state can act on,
one per line, with the verb in a second column: `read on` for a shift, `fold X ->
Y` for a reduce on that lookahead. Nothing is hidden and nothing is wrong. But
the *shape* of the output - one flat list, the distinction carried only in a
column most eyes read as an annotation - means "the terminals of this state" has
two answers differing by 85x, and the instrument does not make you choose.

I wrote **both** of them up as authoritative, hours apart, in this folder. First
20, from a script that filtered to `read on`. Then 1712, from a script that
ignored the verb, at which point I corrected the earlier paragraph and called 20
"the right number for a question I had not asked." That correction was itself
wrong: 20 is the number that governs, because the extra 1692 states admit the
separator only as a *reduce lookahead*, and a fold consumes no byte and so never
puts a token in the hand the caesura competes with. Two confident, contradictory
write-ups from one instrument, and nothing in its output flagged the difference.
A third script, `suppress.py`, shipped a docstring saying "every terminal this
state can shift" over a regex that ignored the verb; it is deleted now.

That is worse than the brief's three named liars, all of which are *known* liars.
`inquest`'s name is flagged. `parse`'s state is flagged. A folio's silent
no-change has a gate coming. `state`'s row is trusted, is accurate, and answers a
question one column away from the one you asked. It does not flatter in a fixed
direction, which is what makes it worse than a biased instrument: whichever
reading a lane happens to parse becomes the number in its report, and both
readings support a fluent argument. Mine supported two opposite ones about the
same design.

The fix is cheap and I did not make it, because the file is not mine: if
`joints state` printed the two sets under separate headers, or closed with
`shift: N  lookahead: M`, none of the three scripts could have drifted. Worth a
lane, and `population.py` reports both columns side by side in the meantime.

**`inquest`'s stand-in name, and not for the reason the brief gives.** The brief
says it picks the first blind external in declaration order, so swift's walls all
print `multiline_comment`. That is true and it is a known lie, which makes it
nearly harmless - a known lie is a warning label.

What I trust less is what that lie did to the *rest* of the sentence, which
reads as evidence and is not. Swift's verdict now says
`[no stand-in for multiline_comment]: a terminal the scanner cannot produce is a
declared extra, so it is in no action row at all and any of its bytes in this
file were read as something else; nothing here says the file holds one, so this
is the best reading`. Every clause is a correct general statement, they are
assembled into a specific-sounding diagnosis, and `Chunked.swift` contains
**zero** `/*`. So the paragraph is reasoning fluently about a construct that is
not in the file. The name is flagged as untrustworthy; the argument built on top
of it is not flagged at all, and it is the more persuasive of the two.

Second, and specific to this lane: **`joints lex`'s blind count is not the
lexer's answer.** It reported swift blind to 13 including `_explicit_semi` while
`_explicit_semi` was being emitted correctly and the probes were passing - the
count reads `Provision` and `claimed`, and `claimed` did not know about the new
`spelled` role. So the instrument said a terminal was unanswerable while the
parser was answering it. It is fixed (12, matching the derivation exactly), but
the shape of the bug is the one to keep: a *census of the mechanism* and *the
mechanism* are two implementations of one fact, and nothing had made them agree.
The board's `describes` count and the probes caught it; the count that exists to
report it did not.

## Still open

- Swift's 12 blind: the raw-string family and nesting comments (carried state -
  `fence`/`marrow` work, not pattern work), `_custom_operator` (a whole-match
  filter `never`/`after` cannot express), `#` and the four `_directive_*` (no
  transcribed refusal, zero occurrences in the corpus), and `_bang_custom`,
  which is now **priced rather than asserted**.

  `_bang_custom` stays declined, and here is what the decline costs. Its scanner
  emits `!` unless `FAKE_TRY_BANG` is wanted - a `valid_symbols` question, which
  is the expected set, which a `Provision` cannot ask. Measured over all 3416
  states: `_bang_custom` and `_fake_try_bang` are **never shiftable in the same
  state**, and share an expected set in **exactly one - state 42**, whose items
  are the three `try_operator -> try .` alternatives. So a bytes-only `!` would
  match the real scanner in 3415 of 3416 states and diverge in one. One is not
  zero, so under this project's bar it stays out; but the honest form of the
  decline is "wrong in one state out of 3416, and that state is not on any wall
  the corpus reaches," not "conditioned on the parse table, therefore
  impossible." If a fail-closed partial is ever built, this is its first
  customer: a row that could name the one state it must refuse in.
- Kotlin's string troupe, worth 936 spoil.
- Scala's layout, which is a troupe lane and not a table row.
- Swift's `)` at 1492, which is not any of the above and needs its own probe.

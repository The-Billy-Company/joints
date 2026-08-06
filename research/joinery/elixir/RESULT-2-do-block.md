# Result 2 — `arguments` where the oracle says `do_block`

**Elixir 22,089 crooked bytes → 0**, corpus 52,635 → 30,573 (**−41.9%**), for
+27 crooked on swift. The elixir specimen slate goes 4/5 → 5/5. Two changes, one
in the press and one in the parse loop, and **neither one does anything
alone** — the press change on its own makes elixir *worse* (+632) and breaks a
control the paired change puts back.

**Both halves are landed.** They sat as a handoff while `gather.zig` and the
press path were under other lanes; those lanes closed, and the diffs below are
now in `src/press/bench.zig` and `src/kernel/quire/gather.zig`. See *What
landed* and *Provenance*.

Elixir is not just a big row. On the three-axis board it is the **single row that
separates coverage from structure from agreement**: seventeen grammars reach
whole, sixteen of them survive both interior questions, and elixir is the one
that falls out — 46,089 bytes in one sound tree whose derivation the oracle
rejects over 22,089 of them. Taking it to zero is what closes the gap between
"17 parse whole" and "16 whole on all three axes", which is the only one of the
two counts that means what the headline sounds like.

## The number moved when the instrument was corrected

This row read **22,210** when the dossier was first written and reads **22,089**
now. Nothing about elixir changed: `plumb.hurt()` was corrected from an
*ancestry* test to the byte's *innermost cover*, so 121 bytes elixir used to
score as crooked are now correctly unadjudicable, and the four arms below are
all taken on the corrected instrument. The corpus figure moved much further —
60,964 → 52,635 on the control — which is why the headline percentage is −41.9%
here and −36.4% in the first draft. **Both are the same repair; only the ruler
changed.** A crooked figure quoted across that correction is not comparable, and
this is the one to quote.

## The witness

`research/joinery/specimen/elixir/do-block-on-inner-call.ex`, 21 bytes, already
in the tree and red since the day it was written:

```elixir
defp f(x) do
  x
end
```

We build the `do ... end` as a second **argument** to `f(x)`. Tree-sitter builds
it as the `do_block` of the `defp`. Every token agrees, every leaf lands where
theirs does; only the parent moves — which is why `plumb` scores elixir a
**perfect 0 askew** and only a derivation comparison sees it at all.

Two controls sit beside it and they are what make the repair believable:

| specimen | what it removes |
|---|---|
| `do-block-without-inner-call.ex` — `defp f do x end` | the inner call, so there is only one candidate for the block and no choice to get wrong |
| `do-block-as-keyword-argument.ex` — `defp(f(x), do: x)` | the `do` token, keeping the same meaning and the same inner call |

Both are green in the base arm. **The press change alone turns the first one
red**, which is how the first attempt was caught before it was believed.

## Attribution: not `inquest`, because there is no stop

`inquest` attributes a parse *stop* to `lexer` / `press` / `weave` / `oracle`.
There is no stop here. Elixir reads `accepted, 1 root` over all 46,089 bytes and
hands back a well-formed tree that is the wrong tree — the one failure mode
whose whole signature is that nothing refused. So the attribution had to be made
by reading the cell, and it lands in the **press**: the table itself contains
the wrong action, before the parse loop ever runs.

## The cell

Elixir state 272, dumped from the base pin:

```text
  items:
    _local_call_with_parentheses -> identifier _call_arguments_with_parentheses_immediate . _newline_before_do do_block
    _local_call_with_parentheses -> identifier _call_arguments_with_parentheses_immediate . do_block
    _local_call_with_parentheses -> identifier _call_arguments_with_parentheses_immediate .

  row — shifts: this state CONSUMES the token, so a lexer competes here
    do                           read on
    _newline_before_do           read on
    ...
  shift 2, lookahead 63 — 65 terminal(s) accepted of 124
```

The inner call `f(x)` is complete on the third item, and the first two are the
*same rule* continuing into its own optional `do_block`. On `do` the state can
either fold the inner call — handing the `do` up to the `defp` that is holding a
dot in front of exactly it — or read on and take the block for `f(x)`. It reads
on. Every one of elixir's 88 `arguments`-under-`do_block` runs is that cell.

Note what the cell is *not*. There is no unwritten precedence being erased, and
no conflict recorded for a lane to resolve: `[prec 0 left]` on every row, and
the shift is not marked contested at all. The `continues` rung in `Ladder.step`
resolves it silently and by construction, because an optional tail written as
two productions always stands the short one complete beside the long one's dot,
and the rung's answer to that shape is *keep reading*. That answer is right
almost everywhere — `defmodule Foo do` has nothing above waiting for the `do`,
so refusing the tail there refuses the sentence — and it is wrong in precisely
the case where the token is what an **enclosing** rule is waiting for.

## Half one — the strand test (`src/press/bench.zig`)

Ask, before letting `continues` keep the tail: would folding this cell actually
strand the terminal? Pop the handle, take the goto, and look for an edge on `t`
in the state you land in, chaining while the answer is another fold (a unit rule
pops straight into a second one). If some enclosing state has an edge on `t`,
the fold does not strand it — it *relocates* it — and the tail rung has no
business erasing that reading.

An **edge** is the question rather than a table row, deliberately: the row that
would answer it belongs to a state this build has not judged yet, and
over-answering would only claim "a reading exists somewhere above", which is
exactly the claim being made.

After it, the same cell reads:

```text
  row — shifts: this state CONSUMES the token, so a lexer competes here
    (none)
  ...
    do                  fold  _local_call_with_parentheses -> identifier …   [unwritten shift_reduce, over read on]
    _newline_before_do  fold  _local_call_with_parentheses -> identifier …   [unwritten shift_reduce, over read on]

  shift 0, lookahead 65 — 65 terminal(s) accepted of 124
```

The table is now right. **The tree is not.** Board with only this change:
elixir 22,089 → 22,721, and `do-block-without-inner-call.ex` goes red.

## Half two — the merge tie-break (`src/kernel/quire/gather.zig`)

With both actions on the cell the parse forks, and `collapse` merges the two
limbs back. Under `OUTLINER_TRACE=quire` they arrive with **equal `heft` and
equal `rank`** — the grammar ranked nothing and neither reading speculated
further than the other — so `Reading.beats` falls through to `a.rank < b.rank`,
which is a strict `<`, which keeps whichever limb was already in `next`. That is
birth order, and birth order here is the shift.

So the press was handing the parse loop a correct choice and the loop was
throwing it away on a tie-break that is not a judgement at all. Naming the
exact-tie case and giving it to the later limb is the smallest change that lets
the fold win:

```zig
const tied = v.heft == k.heft and v.rank == k.rank;
const won = if (v.beats(k.*) or tied) v else k.*;
```

**It sits at the merge, not in `Reading.beats`, and that is deliberate.** The
rung `beats` declines fires wherever `heft` alone ties and reorders readings the
grammar did rank differently; both signs of it were measured and both lose
(`research/joinery/arity/RESULT-3-structure.md`). This fires only where `heft`
**and** `rank` are equal — a case `beats` resolves with a strict `<` and
therefore never separates at all. There is nothing left in either reading to
read: the pick was position in `next`, which is the driver's enqueue order.

Both faces of that coin are measured here, because the control arm *is* the
other face. Keeping the incumbent is what the tree did yesterday; keeping the
challenger is arm D.

## The decomposition

Four arms, one variable each, one pinned binary each, each with its own
`OUTLINER_WORK` and its own minted oracle reading **30 of 30 verdicts live**.
All four share one source snapshot, so the only differences between them are the
two edits.

| arm | change | elixir crooked | swift crooked | corpus crooked | specimens |
|---|---|---|---|---|---|
| **A** | — (control) | 22,089 | 9,536 | 52,635 | 4/5 |
| **B** | strand test only | 22,721 (+632) | 9,536 (—) | 53,267 (+1.2%) | 3/5 |
| **C** | tie-break only | 22,089 (—) | 9,563 (+27) | 52,662 (+0.1%) | 4/5 |
| **D** | both | **0** (−22,089) | 9,563 (+27) | **30,573** (−41.9%) | **5/5** |

**Twenty-eight of the thirty rows are byte-identical across all four arms** —
same `built`, same `square`, same `crooked`. Only elixir and swift move at all,
and verilog (14,133) is stable in all four, which it was not in the first draft's
snapshot.

Elixir's `built` (46,089) and `roots` (1) are unchanged in every arm, so the
22,089 bytes moved from `crooked` into `square` — 23,879 → 46,089 — rather than
falling out of the judged population, which is the trap a falling crooked number
usually is. Its 121 `soft` bytes go to zero as well: **arm D leaves elixir with
46,089 square and nothing in any other bucket.**

Swift's +27 is the whole cost, and no square byte pays it: `square` is 14,419 in
every arm. The 27 come out of `unframed` (1,166 → 1,139) — bytes the oracle had
framed differently and we now stand a wrong parent over. It comes from the
tie-break half alone; the strand test does not touch swift at all.

### Every row, control against paired

| grammar | built | A crooked | D crooked | delta |
|---|---:|---:|---:|---:|
| c | 1,444 | 0 | 0 | — |
| cpp | 1,408 | 0 | 0 | — |
| go | 1,189 | 0 | 0 | — |
| java | 1,258 | 0 | 0 | — |
| javascript | 1,080 | 0 | 0 | — |
| typescript | 1,253 | 0 | 0 | — |
| python | 1,728 | 0 | 0 | — |
| ruby | 576 | 189 | 189 | — |
| rust | 1,434 | 0 | 0 | — |
| bash | 655 | 75 | 75 | — |
| json | 774 | 0 | 0 | — |
| css | 6,138 | 0 | 0 | — |
| elixir | 46,089 | 22,089 | 0 | **−22,089** |
| embedded-template | 6,006 | 0 | 0 | — |
| haskell | 8,919 | 2,029 | 2,029 | — |
| html | 72,288 | 0 | 0 | — |
| julia | 25,405 | 158 | 158 | — |
| kotlin | 35,571 | 186 | 186 | — |
| latex | 5,246 | 0 | 0 | — |
| lua | 3,707 | 0 | 0 | — |
| markdown | 178 | 0 | 0 | — |
| ocaml | 14,696 | 2,113 | 2,113 | — |
| php | 67,845 | 0 | 0 | — |
| scala | 15,957 | 1,938 | 1,938 | — |
| sql | 4,081 | 179 | 179 | — |
| swift | 26,091 | 9,536 | 9,563 | **+27** |
| toml | 3,544 | 0 | 0 | — |
| verilog | 31,805 | 14,133 | 14,133 | — |
| yaml | 0 | 0 | 0 | — |
| zig | 14,750 | 10 | 10 | — |
| **corpus** | **401,115** | **52,635** | **30,573** | **−22,062 (−41.9%)** |

Twenty-eight rows unmoved, one to zero, one +27.

`rack.py verify` reads **38 of 38** and `plumb.py verify` **10 of 10** on the
paired arm, so the instrument that scored the repair is the same one, still able
to say no, that scored the baseline.

## Is it the same defect as swift's trailing closure?

**The shape is identical; the resolution is not, and there is no shared fix.**

Same shape: a block-introducing token arriving where an inner construct is
complete and an outer one is waiting, taken by the inner one. Elixir's `do` for
`f(x)` is swift's `{` for the `if let`, one for one.

Different rung. Swift's site was a *ranked* cell — an unranked fold was erasing
an authored reading, and the repair was to let it **order** that reading instead
of erasing it. Elixir's site is not ranked and holds no conflict record at all:
`[prec 0 left]` throughout, resolved silently by the tail rung. There is no
authored reading here to order. A precedence-ordering fix has nothing to act on,
and the swift repair leaves this cell untouched — the base arm already contains
it.

So: same defect **family** (an implied statement terminator letting a block bind
to the inner call), two different mechanisms producing it, and a lane arriving
here with the swift patch in hand would have found nothing to apply.

## Does it generalise to ocaml, sql, julia?

**No.** All three are byte-identical across all four arms — 2,113 / 179 / 158
crooked, unmoved. They are in the same 0%-same-name group and they are not this
defect:

- **ocaml** is `match_expression` and `function_expression` where the oracle says
  `let_binding` — an expression swallowing its binder, not a block being taken by
  the wrong call.
- **sql** is `select_expression` where the oracle says `identifier`.
- **julia** is `macro_argument_list` where the oracle says
  `parenthesized_expression`, and its whole row is 158 bytes in 4 runs.

The implied-terminator *reading* survives as a description of the group; it does
not survive as a prediction that one repair reaches four rows. This repair
reaches one row, and that row is 42% of the corpus's crooked bytes.

## What landed

Both halves, in this order, because landing the first without the second is a
regression (+632 on elixir and a red control).

**1. `src/press/bench.zig`** — the strand test. Two scratch lists on `Bench`
(`chain`, `walked`, deinit beside `contested`), the `strands` method, and one
line in `decide`:

```zig
-        survey.continues = survey.continues and frayed;
+        survey.continues = survey.continues and frayed and b.strands(state, t);
```

**2. `src/kernel/quire/gather.zig`** — the exact tie in `collapse`, named and
commented in place, with the reason it is not a rung in `Reading.beats`.

Neither file was moved by anyone else between the snapshot the arms were built
from and the moment the patches went in; both were byte-identical, and the live
files now match arm D's exactly.

## Provenance — which tree every figure came from

`7d72a5d` does not build on its own. Its `gather.zig` reads `split.sided`, a
field that exists only in the **uncommitted** `src/press/forks.zig` from the
keyword-regression work, so an archive of the commit fails to compile. A pinned
arm is therefore the working tree with **`src/kernel/lex/{scanner,outside,writ}.zig`
rolled back to `7d72a5d`** and everything else — press, quire, folio, and all of
`tool/` — as committed-plus-working-tree at 2026-08-06 19:29Z. That is the
smallest exclusion that answers the brief: the lex trio is the in-flight
bracket-order seat that refuses a real `do`, and rolling back only those three
files restores elixir to `accepted, 1 root` and 46,089 built on the control.

Keeping the live `tool/` is deliberate and is what makes these the corrected
numbers: `plumb.hurt()`'s ancestry→cover fix and `rack.py`'s matching `blind`
rule are both uncommitted, so an arm built purely from `7d72a5d` would have
re-read the row on the *old* instrument.

Four arms under `.local/lane-elixir/land/{A,B,C,D}`, one source snapshot each,
`zig build -Dcli-optimize=ReleaseFast` into its own `pin.py` pin:

| arm | source tree | binary |
|---|---|---|
| A control | `9043729ee111` | `a046d3858526` |
| B strand | `470aa8a3c085` | `9d3b42e9aa22` |
| C tie-break | `dc141584a80a` | `bbb978704eba` |
| D both | `572f101904b7` | `b2eac71bc20e` |

Each carries its own `OUTLINER_WORK` and its own oracle minted with
`pin.py oracle`, all four reading **30 of 30 verdicts live** — the column that
reads `0` both when thirty grammars agree and when nobody asked. tree-sitter
0.26.11. Specimens under each pin with
`tool/specimen.py run --grammar=elixir`.

### And it holds on the live tree

A fifth pin, `landlive` (tree `bba9635bede5`, binary `b24f2d4525fa`), is the
working tree **with nothing rolled back** and both halves landed, audited at
2026-08-06 20:20Z, 30 of 30 verdicts live. Elixir reads **46,089 built, 46,089
square, 0 crooked, 0 soft, 0 unframed** — byte-identical to arm D — and so does
swift. Exactly one row on the whole board differs between arm D and the live
tree, and it is **haskell** (8,919 → 14,927 built, 2,029 → 5,109 crooked), which
is the externals lane's own row moving under its own change. So the lex trio no
longer refuses elixir's `do`, the rollback in the arms is no longer load-bearing
for this result, and the pinned arms and the live tree agree on every figure
this dossier quotes.

**One arm-setup trap worth writing down.** The board's grammars live under
`.local/breadth/lang/`, and reaching that directory through a *symlink* makes
the tree-sitter CLI silently skip `src/scanner.c` and fail to link every
external-scanner grammar — elixir, swift, ocaml, sql, julia, scala, haskell and
eleven more. The same absolute path, unsymlinked, builds them all. An arm that
gets this wrong reports `square = 0` and `crooked = 0` on eighteen rows, which
is indistinguishable from eighteen perfect grammars; `pin.py oracle`'s
"N of 30 live" line is not the tripwire, because those verdicts are live — they
are live records of a refusal. The `why` field is the one to read. Hardlink the
grammar tree in (`rsync -a --link-dest`) rather than symlinking it.

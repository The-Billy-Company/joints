# RESULT 2 — the numbers, and the two predictions that died on them

Three arms, each with its own empty `OUTLINER_WORK`, all against the frozen
`seat3` oracle:

| arm | binary | what it is |
|---|---|---|
| `before` | `5c962f8d` | the tree when this lane opened |
| `iso` | isolation build | **today's tree with my three rows deleted** |
| `after` | `15c266a9` | today's tree, seated |

The `iso` arm is the one that matters and it was not in the plan. See 2b.

## The board

| | before | iso | after | mine (iso → after) |
|---|---|---|---|---|
| corpus `square` | 272,766 | 272,358 | **300,723** | **+28,365** |
| corpus `unframed` | 41,713 | 41,467 | **12,506** | **−28,961** |
| crooked+unframed / adjudicable | 23.71% | 23.82% | **16.54%** | **−7.28 pt** |
| standing | — | 74.7% | **75.2%** | **+0.5 pt** |
| grammars parsing whole | — | 13 | **15** | **+2** |

| grammar | | before | iso | after |
|---|---|---|---|---|
| elixir | `square` | 1 | 1 | **23,228** |
| | `racked` | 17,654 | 18,290 | 22,724 |
| | `unframed` | 26,756 | 26,105 | **0** |
| | `damage` / `roots` | 1,559 / 255 | 1,559 / 255 | **0 / 1** |
| latex | `square` | 108 | 108 | **5,246** |
| | `racked` | 1,049 | 1,049 | **0** |
| | `unframed` | 2,856 | 2,856 | **0** |
| | `damage` / `roots` | 1,185 / 72 | 1,185 / 72 | **0 / 1** |

Both grammars go from mending to `accepted, 1 root`. latex is 5,246 of 5,246
bytes matching tree-sitter's derivation, 0.0% crooked — php's result over a
smaller file. elixir is 23,228 square with 22,724 still racked, which is
prediction 1d holding: the `defp … do` attachment defect survives and is now the
whole of elixir's remaining charge.

## 2a — elixir passes 30,000 square — **DEAD**

Predicted `square` ≥ 30,000, `roots` ≤ 3, `unframed` ≤ 1,000, `damage` ≤ 200.
Got **23,228 / 1 / 0 / 0**. Three sub-claims held and the headline missed by
6,772 bytes.

The miss is not noise, it is the thing I said I was not counting as a failure and
then priced wrong anyway. 22,724 bytes of `router.ex` are right leaves under a
wrong parent — the `defp f(x) do` attachment — and I set the threshold as if that
class were "a few thousand". It is half the file. The specimen that measures it
(`do-block-on-inner-call.ex`, 4/5) was sitting in the tier the whole time with
the number on it.

## 2b — corpus square passes 305,000 and no other grammar moves — **DEAD, and the measurement was the wrong shape**

Predicted `square` ≥ 305,000. Got **300,723**, short by 4,277 — the same 6,772
elixir bytes, less what latex over-delivered.

The second half died differently and it is the more interesting failure. In the
`before` → `after` pair, **nine** grammars moved: php 67,845 → 67,685 square,
julia 24,382 → 24,058, python 1,701 → 1,728, c 767 → 757, go, kotlin, cpp,
swift's askew and recall, verilog's built. By the letter of the prediction I had
just widened a roster or leaked a mark.

I had not. Up to ten agents share this tree, and between the two builds siblings
landed edits in `admit.zig`, `fence.zig`, `lexicon.zig`, `offside.zig`,
`scanner.zig` and a new `writ.zig` — and in `outside.zig` itself, whose `step`
had gained an argument. A before/after pair across a shared tree cannot
attribute anything.

So I built the `iso` arm: today's tree, with only my three rows deleted
(`_quoted_atom_start` from `roll`, the latex marrow row and the elixir caesura
row from `troupes`), leaving all the plumbing — the widened `Mark`, `Troupe.lone`,
`Troupe.seams`, `caesura.Seam` — in place. Against `iso`, **exactly two grammars
move and no third moves one byte.** php is 67,685 in both. julia is 24,058 in
both.

The prediction about my change was right. The measurement I designed to prove it
could not see it, and it would have read as a failure I did not commit.

The isolation needed a scratch tree because `outside.zig` carries a sibling's
edit as well as mine, so reverting the file was not available — `git show
HEAD:src/kernel/lex/outside.zig` no longer compiles against the working tree's
`scanner.zig`. It is rsynced to a sibling directory of the repo so `../irregex`
still resolves, and deleting three row literals is the smallest edit that
isolates a row from its plumbing.

## 2c — latex's `\iffalse … \fi` is the largest single piece — **HELD**

Predicted latex `square` ≥ 3,000, `unframed` ≤ 300, `damage` ≤ 250, wall gone.
Got **5,246 / 0 / 0 / gone**, and the file is whole.

The member-level claim held too. `ltnews01.tex` is 5,246 bytes and one
`\iffalse … \fi` block is 990 of them, 18.9%, against 51 and 76 for the two
verbatim bodies. The member needing the *extra* rule was worth thirteen times
the two that only needed the string. Implementing the string close and stopping
would have collected 127 bytes and reported a family seated.

## 2d — the widening costs the single-byte families nothing — **HELD, measured**

`Mark.shut` stayed the close's **first** byte and gained a `tail` for the rest.
The three existing walks (`matter`, `quoted`, `encapsed`) never read `tail`;
`outside.shutOf`, which keys a family's closing terminal by that byte, is
untouched.

Measured on the `iso` arm, which carries the widening and none of my rows: php
67,685 square / 0 racked and julia 24,058 / 434 in **both** arms, every column
identical. elixir's twenty quoted-content members are unchanged in the roster pin
and in the rack.

## 2e — bash gains under 120 bytes and its wall does not move — **HALF DEAD**

The wall did not move: still `unexpected [ at 565 in state 1163`, bash
unchanged at 460 square in all three arms, because I seated nothing.

The **attribution** died. I wrote that byte 565 was `_concat`, an `abut`. It is
the `[` of `[0-9]` inside the regex `^-?[0-9]+$`, so this mechanism owns bash's
wall and the price is bash's whole 413-byte damage, not 120. The mechanism is not
php's family and not a `Provision` either; RESULT-1 §1f has the derivation and
`specimen/bash/regex-in-test-command.sh.expect` has the price.

## 2f — the two inherited guard holes

**1. A wrong `mark` on a correctly-named member — CLOSED and proven.**
`scanner_test.zig` now renders every field of `marrow.Mark` into the pinned
claim — `shut`, the `tail`, `xN` for a wide close, then a letter per flag (`i`
interpolates, `a` after-a-variable, `c` command-name) — and pins the rendering.
Unprintable closes go out as `\xNN` so a pin stays a diffable line.

Proven by breaking it. Truncating `_trivia_raw_env_verbatim`'s tail from
`end{verbatim}` to `end` in the scratch tree fails the test by name and by byte:

```
FAIL [31/32] kernel.lex.scanner_test.test.scanner: a row claims the terminals it is pinned to and no others
First difference occurs on line 1:
expected:
_trivia_raw_env_verbatim \end{verbatim}
                             ^ ('\x7b')
found:
_trivia_raw_env_verbatim \end
                             ^ (end of string)
```

One test of that shard's eleven, and the ten beside it pass — so the pin fails on
the corruption rather than on the tree being a scratch copy. The two other shard
failures in that build (`weave:` rows 14/32 and 15/32) are a sibling's lane,
carried in because the scratch tree is rsynced from today's source.

The php lane's name-only pin passed that edit. Four rows are pinned this way now
(php, julia, elixir's twenty, latex's twelve) plus the caesura's three seams,
which are a roster by the same argument — three names a hand can extend by one
line.

**2. A failing specimen has no number below zero — CLOSED for the four I added,
and one addition says out loud that it is not a guard.**

Four new specimens, claims taken from tree-sitter's tree over the same bytes,
each run in **both** directions:

| specimen | seated | unseated (`iso`) |
|---|---|---|
| `elixir/newline-before-operator.ex` | 7/7 | 2/7 |
| `elixir/quoted-atom.ex` | 7/7 | 3/7 |
| `latex/verbatim-body.tex` | 7/7 | 1/7 |
| `latex/iffalse-fi.tex` | 8/8 | 6/8 |

They are built so a weaker implementation cannot pass them. `verbatim-body.tex`
puts `\end{x} $y` inside the body: a close matching one byte or four stops at 17
where the real close reaches 28, and the `$` would build a math node in a run
that was not raw. `quoted-atom.ex` uses `:"a#{b}c"` because an atom with no
interpolation would pass on a close that swallowed the body.

`iffalse-fi.tex` is the honest caveat: unseated it still scores `roots 1` and
`mends 0`, because latex's recovery builds a `block_comment` over [0, 8) rather
than shredding. Only the three `spans` claims fall. A specimen whose structural
claims survive the break is carried by its extents, which is the php lane's
lesson arriving one layer down.

A fifth, `bash/regex-in-test-command.sh`, is 0/6 and its `.expect` opens by
saying it is **a handover, not a falsifier** — it cannot tell a break from a
baseline, and its job is to price the seat and name the mechanism.

## 2g — the folio hazard — **OBEYED, AND THE CHECK I PROPOSED WAS WEAKER THAN I THOUGHT**

Each arm got its own directory, started empty, and every folio carries its
minter's digest. `before/latex.folio.by` records `5c962f8d`, which is
`before-bin`'s hash, so the before arm really did read the before binary.

But the collateral check I built on it does not do what I said. A folio is the
**pressed table**, and a `Troupe` seat does not change it — so latex's folio is
**byte-identical between an arm scoring 108 square and an arm scoring 5,246.**
Only the `roll` provision changed a folio at all, which is why elixir's differs
and latex's does not. Folio identity proves no table moved; it says nothing about
whether a derivation moved.

The check that actually answered "no collateral damage" was the isolation build
in 2b. I inherited a hazard, obeyed the letter of it, and built a second
flattering check on top — one where 28 of 30 grammars agree because the artifact
they agree about is not the artifact under test.

# Result 3 — the prefix half is refused, and the refusal has a one-keystroke witness

Answering [PREDICTION-3-slate.md](PREDICTION-3-slate.md). Four pins, all
`f7ba40004+11x` on this machine, each built by `tool/pin.py` so the arms cannot
read each other's tree:

| pin | what it is |
|---|---|
| `prefix-before` | baseline, tree `15fa62022c2d` |
| `derive-only` | a `holds` decline mounts the ring below instead of grounding |
| `holds-only` | a zero-width recorded token's *offset* is not verified |
| `shun-derive` | both, plus the walk refusing a zero-width token it volunteered |
| `lane-final` | what is in the tree: baseline behaviour, one fatal repaired |

**The prefix half of reuse is worth roughly what the brief said it was, and
`abide` refuses every version of it I could write.** P1, P2, P7 and P8 hold on
the numbers; **P4 fails**, which was the stated revert condition, so the speed
is not in the tree. What is in the tree is a fatal that the attempt found, a
diagnostic that says which pairing an algebra refused, and the account below.

## The speed is real

`derive-only`, one variable, against `prefix-before`:

| grammar | µs/key before | after | read before | after | prefix before | after |
|---|---|---|---|---|---|---|
| verilog | 58,796 | **43,151** | 8,951 | 6,751 | 1.00 | 0.75 |
| scala | 4,575 | **3,608** | 1,277 | 941 | 1.00 | 0.74 |
| haskell | 11,788 | **10,868** | 5,532 | 4,922 | 1.00 | 0.89 |
| lua | 864 | **573** | 505 | 299 | 0.98 | 0.58 |
| markdown | 1,846 | **1,735** | 1,167 | 1,007 | 1.00 | 0.86 |
| latex | 13,166 | **12,962** | 813 | 703 | 1.00 | 0.86 |
| kotlin | 34,608 | 33,777 | 4,817 | 4,688 | 1.00 | 0.97 |
| swift | 35,675 | 34,838 | 3,628 | 3,522 | 1.00 | 0.97 |
| ocaml | 30,883 | 30,621 | 4,192 | 4,130 | 1.00 | 0.98 |

Per-keystroke numbers are the mean of 24 edits, so they understate what a
resume does where it stands: verilog's deep edits fell from 59,481µs and 8,951
tokens to **8,138µs and 1,333** while its shallow ones are unchanged, because
`b.before(firm)` finds no ring below an edit near the top of a file.

- **P1 falsified**, but narrowly and in a way worth naming: six grammars leave
 `prefix = 1.00`, and **swift is not one of the four the slate wholly
 explains** — it went 1.00 → 0.97 for 3% of its tokens. Its rings sit 12,216
 and 13,246 against an edit at 14,000, so descending one ring buys one stride,
 not the half-file the arithmetic assumed. The half-file is only available if
 `holds` starts *holding*, and it does not.
- **P2 falsified.** Swift fell 2.3%, not 40%. See above: the resume stands, and
 it stands 1,030 bytes below the edit rather than 14,000.
- **P3 holds.** `lifts` is 0 on every mended grammar on both arms and unchanged
 on the clean ones. Nothing leaked in from the suffix half.
- **P5 holds** - none of the clean 13 moved more than 15% - and my stated
 expectation of being wrong about it was itself wrong: the sprig line changed
 nothing measurable anywhere.
- **P6 holds.** swift still traces `unheld`; the decline was demoted, not fixed.
- **P7 holds and is the useful half of P1.** lua, a *clean* grammar at 6 of 24
 accepted, is the best row on the board at 0.98 → 0.58 and 864 → 573µs.
 `RESULT-2`'s P1 died on this conflation; this is the other side of it.
- **P8 holds** everywhere the resume stands: verilog reads 25% fewer tokens for
 27% less time, scala 26% for 21%, lua 41% for 34%. Cost is not superlinear in
 the tail the way I guessed, but tokens fall at least as fast as microseconds
 on every row, which is what the prediction was really claiming.

## And `abide` refuses it, on one keystroke

```
outliner amend .local/standing/haskell.folio upstream/sources/Shared.hs '23548..23548=x'
```

against `outliner parse` of the same bytes.

| pin | warm vs cold |
|---|---|
| `prefix-before` | agree |
| `derive-only` | **diverge** |

Not a compounding fault: this is the first edit on a pristine file, so nothing
below it was laid by an earlier resume. `abide` reads haskell **18 of 24** where
baseline reads 24, first disagreement k=17, 1,770 roots amended against 1,781
cold. Every other grammar is unchanged, including the three the board already
had (python 21, toml 23, yaml 0).

The divergence is **above** the resume, which is the part that matters:

```
< (wildcard))          > (variable))     x3
< "="                                    x3
```

`alight` mounted ring 112 at 23,184 after ring 113 declined. haskell's rings 110
through 113 all decline, and all four for the same reason - a zero-width layout
token one to three bytes off where it was recorded:

```
ring 113 at 23244  wanted _cmd_layout_start 23246..23246  got _cmd_layout_start 23244..23244
ring 112 at 23184  wanted _cmd_layout_start 23187..23187  got _cmd_layout_start 23185..23185
ring 111 at 22987  wanted _cmd_layout_start 22988..22988  got _cmd_layout_start 22987..22987
ring 110 at 22808  wanted _cmd_layout_start 22809..22809  got _cmd_layout_start 22808..22808
```

`firm` is 23,548. Nothing between 22,808 and 23,246 moved, so these are not
changed bytes - they are the walk's own slate, admitting a layout terminal the
parse never offered and getting it answered one byte early. Yet mounting the ring
below one of them lands a parse whose layout hand disagrees with a cold one from
the next token on.

**That is the finding.** `holds`'s wide slate is not merely conservative. Where
an external hand's answer *depends on the slate it is handed*, the walk and the
parse are asking different questions of the same bytes, and the walk cannot tell
its own artefact from a real change. Descending past its decline is a bet on
which one it is looking at.

## Two narrowings, both refused, both of which look free

I tried to fix the slate rather than route around it. Both fail, and both are
worth recording because each looks obviously safe.

**Don't verify a zero-width token's offset.** Nothing covers no bytes, so no
edit can have changed it, and where it lands inside a run of whitespace is set
by a slate this walk cannot rebuild. `holds-only`: **haskell 19 of 24**. Those
tokens are *in the tree* - a layout token at 23,244 rather than 23,246 is a
different leaf boundary and a different `r.at`, so the offset is exactly the
thing that must not be let go.

**Refuse a zero-width token the walk volunteers in front of the recorded one.**
This is swift's whole decline: `_implicit_semi` answered at 13,246 where the
parse read `public` at 13,249, in a state whose raw action row admits it and
whose live readings did not. `shun-derive`: **haskell 18 of 24**. It hides the
case where the *bytes* now produce a layout token there, and that is the case the
walk exists to catch.

Both fail the same way, and it is the same way `derive` fails. **The wide slate
cannot be narrowed by a rule about token shapes, because every such rule is a
guess about whether the walk or the bytes are the thing that differs.** What
would settle it is `offer`'s own slate - `shiftable` unioned over the live
readings, plus the sprigs - and that needs the stack, which is mounted after
this question is asked and not before.

One line of the sprig repair *is* in the tree's history and is not in the tree:
`offer` admits every sprig's first terminal unconditionally, and `holds` cannot
find them because no state has a cell for a rule-shaped extra. So `holds`'s slate
is not a superset of `offer`'s, which is a soundness hole rather than a slow one.
It measured as exactly nothing on all 30 grammars, so it went out with the rest
rather than shipping unmeasurable.

## What did ship: a fatal that should have been a decline

`derive` reached this within six keystrokes of verilog, and the second thing it
did was kill the process:

```
outliner amend .local/standing/verilog.folio upstream/sources/picorv32.v '20086..20086=x'
→ error: TrailRefused
```

`distil` folds the move trail into one element per token span and raises on any
composition the algebra refuses, on the stated grounds that *"these are moves a
parse actually made one after the other, so a refusal would mean the algebra
disagrees with the parser about what the parser did."* True of three of its four
call sites. The fourth is a run's **trailing folds being charged onto the last
leaf laid** - and a *resumed* parse that walls before laying a leaf of its own
charges them across the resume, onto a leaf the previous parse laid:

```
trail refused: move 9559 of 29995 at byte 19623: mend onto leaf,
  left.entry=0 right.entry=1, leaves=2990 era=1
```

Byte 19,623 is the resume offset itself and `leaves=2990` is where the kept
tiling ended, so this parse had laid nothing. Those two runs are claimed adjacent
by the resume, not by the parser's account of its own moves, and when the algebra
says they are not, what is false is the claim. Round 14 reached the same verdict
one question over, in the `seam refused` block directly above: *"Declining is
the only honest answer, and it is the one `aligned` already gives an unspliceable
tiling."*

So `distil` now takes the floor - where this parse's own leaves begin - and a
charge below it returns false rather than raising. `Weave.unspun` gains
`charge` beside `off`/`seam`/`win`, for the same reason those three were split:
a cleared tiling without the reason is the shape a verdict hides in.

It cannot fire in the tree as it stands, because it needs a resume where a
decline currently grounds. It is in anyway: a latent fatal one lane away from
being reachable is worth four lines, and the next lane to try the prefix half
will hit it first.

The diagnostic beside it is the part I'd have wanted three hours earlier.
`error.TrailRefused` names neither the move, the byte, nor the operands, and four
sites raise it; finding out which one meant bisecting keystrokes. Under
`OUTLINER_TRACE=weave` each site now says which pairing, at which move of how
many, at which byte, with both entry states.

## The gate, before and after

| | grammars whole | haskell | python | toml | yaml |
|---|---|---|---|---|---|
| `prefix-before` | 27 of 30 | 24 | 21 (k=16) | 23 (k=1) | 0 |
| `lane-final` | **27 of 30** | 24 | 21 (k=16) | 23 (k=1) | 0 |

`probe` on `lane-final` is byte-for-byte the baseline's token counts - swift
3,628, verilog 8,951, ocaml 4,192, scala 1,277, all at `prefix = 1.00`. The
gather change is a comment; the weave change cannot be reached. Nothing moved,
which for this commit is the claim.

## For the next lane, in the order I'd take them

1. **`offer`'s slate, computed where `holds` runs.** Everything above says the
 walk needs `shiftable`, and `shiftable` needs a stack. The stack for ring i−1
 is `b.chain(i-1)` and mounting it into `x.perches` is a memcpy of a stack
 depth - the reason `holds` does not is that the stack *changes* under each
 fold as the walk advances, so it would have to drive `absorb` and not just the
 scanner. Driving `absorb` over a stretch and throwing the result away is a
 third of `remount`'s cost and would answer exactly the parse's question. I did
 not try it; it is the one design left that is not a guess.
2. **haskell's four rings, on their own.** If those declines are artefacts - and
 the bytes say they are - then a walk with the parse's slate holds all four,
 swift's ring 56 holds, and both grammars get the resume without anyone
 descending past a decline. The whole prefix half may be one correct slate.
3. **Do not re-land `derive` without (1).** It is 25% of verilog's keystroke and
 41% of lua's, and it is one keystroke from a wrong tree.

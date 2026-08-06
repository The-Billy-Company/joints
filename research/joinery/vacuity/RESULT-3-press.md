# Result 3 — a ten-minute press intermediate cost scala 63 points, and scala's fragility is the durable part

Not my lane and not one of the seatings I was auditing. Found because a
fifteen-arm sweep needs a control at each end, and the two controls disagreed.
**Already resolved by the lane that owns it** - recorded because the interaction it
exposed is permanent even though the regression was not.

## What the two controls said

Two `tool/pin.py` builds of the same working tree, minted four minutes apart, each
with its own folio cache and its own oracle seat, re-minting all 31 artifacts from
scratch so neither read a folio the other wrote. Their per-file manifests differ in
**exactly two files**:

```
87 files · 2 differ:
   src/press/bench.zig
   src/press/ladder.zig
```

| grammar | damage | Δ | standing |
|---|---|---|---|
| **scala** | 4,150 → 16,883 | +12,733 | 79.36% → **16.03%** |
| **elixir** | 0 → 8,795 | +8,795 | 100% → **80.92%** |
| haskell | 25,048 → 25,086 | +38 | 26.85% → 26.73% |
| kotlin | 246 → 244 | −2 | 99.31% → 99.32% |
| sql | 2,423 → 2,309 | −114 | 62.08% → 63.87% |
| verilog | 63,937 → 62,645 | −1,292 | 32.45% → 33.82% |

Twenty-four grammars byte-identical in all 31 columns. Verilog and sql improved,
which is presumably what the change was for.

## It was an intermediate, and saying otherwise would have been the finding of the week for the wrong reason

A third board taken ten minutes later, from a third pin: **scala back to 4,150 and
79.36%, elixir back to 0 and 100%** - and verilog and sql back to their worse
figures, so the whole two-file delta went out together. The tree now differs from
the first control in `nodes` on three grammars and in nothing else; damage and
standing agree on all thirty.

So the correct account is: an uncommitted `src/press/` intermediate held a
12,733-byte scala regression for roughly ten minutes and the lane took it out
again. I have not touched `src/press/bench.zig`, `src/press/ladder.zig`,
`tool/walls.py`, `tool/cut.py` or `tool/sole.py`, and there is nothing outstanding
to hand back. The pins remain; `pin.py show aud-live2` and `pin.py show aud-base`
reproduce both boards from the binaries.

The lesson is not about that lane. It is that **a board taken once on a tree ten
agents are editing prices a moment, not a change.** Two of my own sweeps' controls
were four minutes apart and disagreed by 63 standing points on one grammar for
reasons belonging to neither sweep.

## The durable part: scala regresses only with both of its rows in

This survives the intermediate going away, because it is a statement about scala's
two seatings rather than about the press edit:

| scala's state | control A | control B (the intermediate) |
|---|---|---|
| both today-seated rows in | 4,150 | **16,883** |
| `_indent/.offside/.slashes` removed | 11,913 | 11,913 |
| `block_comment/.marrow/.kotlin_block` removed | 6,557 | 6,557 |

With either row absent scala is insensitive to the press edit **to the byte**. Only
with both present does it move at all. So scala's good row is produced jointly by
its layout row and its comment vein, and a press change that disturbs either half
of that cooperation costs the whole 12,733 bytes at once. No arm that ablates one
row at a time can see it, and no folio diff of a lex seating could ever have.

That is the shape worth carrying forward: a grammar whose standing depends on two
seatings interacting is a grammar whose next regression will not be attributable to
either of them.

> **The observation holds and the word for it changed (2026-08-06).** Sighted,
> each of those two rows *alone* costs 100.0% and 97.0% of scala's whole 6,739
> `square` (`consort/RESULT-6-scala.md`, `RESULT-8-sighted.md`). So this is not
> two seatings cooperating - it is a **ceiling**, and the blindness it produces
> is the ceiling's consequence: with either row out scala is already on the
> floor, and a grammar on the floor cannot register a further press change. The
> "insensitive to the byte" reading above is exactly right; "cooperation" is the
> wrong name for what causes it.

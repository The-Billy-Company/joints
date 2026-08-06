# Result 1 - the tie-break was worth 44 bytes, and the 29,348 was a blown fuse

Scored against `PREDICTION-1-heft.md`, written before anything was built.

**Headline: the pair works and the brief's diagnosis does not.** B plus a
correct tie-break plus the capacity to hold what B mints is **+6,529 square
bytes** over control, **+4,956** with verilog withheld. W5 and W6 seat. Elixir
is byte-identical to control, which is what the canary was for. But the
tie-break contributed **44 bytes of that**, and the other 6,485 came from a
fuse nobody had swept since the fork population changed underneath it.

## The board

Eight arms, one oracle, one control taken twice.

| arm | `crowd` | `skeins` | B | heft | square | Δ control |
|---|---|---|---|---|---|---|
| `alone` control | 8 | 64 | - | - | 305,011 | - |
| `alone2` control, +9 min | 8 | 64 | - | - | 305,011 | **0** |
| `heft` | 8 | 64 | - | yes | 305,055 | +44 |
| `crowdonly` | 64 | 512 | - | - | 309,016 | +4,005 |
| `bonly` | 8 | 64 | yes | - | 277,388 | -27,623 |
| `bh` | 8 | 64 | yes | yes | 277,432 | -27,579 |
| `skeinsonly` | 8 | 512 | yes | yes | 277,620 | -27,391 |
| `crowd64` | 64 | 64 | yes | yes | 279,884 | -25,127 |
| **`ship`** | **64** | **512** | **yes** | **yes** | **311,540** | **+6,529** |

Per grammar, `ship` against control - every row that moved:

| grammar | control | ship | Δ | whose |
|---|---|---|---|---|
| swift | 10,413 | 14,419 | **+4,006** | capacity |
| verilog | 611 | 2,184 | +1,573 | B · *withheld* |
| kotlin | 34,589 | 35,324 | **+735** | B |
| sql | 2,618 | 2,789 | **+171** | B |
| python | 1,701 | 1,728 | +27 | heft |
| go | 1,172 | 1,189 | +17 | heft |
| **elixir** | **23,879** | **23,879** | **0** | the canary, untouched |
| scala | 6,739 | 6,739 | 0 | |

Nothing lost a byte anywhere. Judged total excluding verilog: **+4,956**.

## What the tie-break turned out to be

`prec.dynamic`, summed over everything a reading has folded, higher wins, `rank`
as the last word. It is the one rank a grammar writes that the press
deliberately cannot spend - a static rank deletes an action while the table is
being built, a dynamic one is left for the moment when both derivations it
orders actually exist - and this runtime carried it through the folio and never
read it. Upstream accumulates the same integer two ways that compose to one add
per fold (`subtree.c:353,407`, `stack.c:164,171`, ordered at `parser.c:284`).

It is structural in the sense the brief demanded: the only input is a number in
the grammar author's own file, no grammar name is read, and a grammar declaring
no dynamic precedence cannot reach the comparison at all.

**And it is worth 44 bytes.** That is the finding, not a disappointment - it is
a correct rule that closes the question of what `collapse` should compare, and
the reason it is small is that these cells only exist where a fork already stood
*and already reached a merge*.

## The 29,348 was fork starvation

`P2` predicted B + tie-break would not recover it, for a stated mechanism, with
a stated falsifier: **the denial counter**. That counter is what broke the lane
open.

```
alone   elixir  split=296  denied=0   merged=10   refuted=286
bonly   elixir  split=66   denied=75  merged=0    refuted=220
alone   scala   split=94   denied=0   merged=0    refuted=98
bonly   scala   split=74   denied=73  merged=3    refuted=143
```

Elixir goes from **denying nothing to denying more forks than it takes**. That
is not a tie-break landing on the wrong side of a coin - a tie-break can only
ever cost you readings that *reached* a merge, and these never opened. B mints
more legitimate forks than the runtime has slots to hold, the later fork that
mattered is refused, and the frame is never built. It is exactly the signature
the brief quotes and reads past: *`racked` drops while `unframed` rises - B
doesn't stop building wrong parents, it stops building the parents.*

**The two fuses are in series**, which is why no previous sweep found this. A
fork needs a `crowd` slot *and* a `skeins` strand; raising either alone just
moves which one blows:

| `crowd` | `skeins` | elixir | scala | swift |
|---|---|---|---|---|
| 8 | 64 | 1 | 534 | 10,413 |
| 8 | 512 | 1 | 722 | 10,413 |
| 64 | 64 | 1 | 534 | 14,419 |
| **64** | **512** | **23,879** | **6,739** | **14,419** |

`gather.zig` recorded, on `crowd`, that "re-measuring the whole board at 8, 32
and 256 moves 13 bytes ... and saturates below 32." That sweep moved one knob,
so it could only ever see the lower fuse. The comment is corrected in place.

**Swift is the part that owes nothing to B.** `crowdonly` carries no press
change and swift still gains 4,006 square bytes, so the cap was costing that
much on today's tables before anyone touched the press.

## Scoring the predictions

| | claim | verdict |
|---|---|---|
| **P1a** | zero-`PREC_DYNAMIC` grammars byte-identical | **held** - only go (7 declarations) and python (3) moved; sql, verilog, rust and every other zero-declaring grammar identical. No implementation bug. |
| **P1b** | small positive, concentrated in **c and cpp** | **failed** - c (10 declarations) and cpp (**29, the most on the board**) moved *zero*. Declaration count does not predict where the tie is actually reached; go and python were the whole delta. The sign and the bound held, the attribution was wrong. |
| **P1c** | corpus-wide under +3,000, "would not be surprised by zero" | **held** - +44 |
| **P2** | B + tie-break does **not** recover the 29,348, and elixir does not come back | **held for the arm it names** (`bh` = -27,579, elixir still 1) - and its stated mechanism and its stated falsifier were both right. Acting on P2's own diagnosis is what produced the recovery. |

P1b is the honest failure: I reasoned from how many dynamic precedences a
grammar declares to where one would decide something, and those are different
questions.

## What cleared what

- **Two controls, nine minutes apart, byte-identical across 930 numbers.** The
  apparatus is inert; nothing a sibling landed in the window moved my board.
- **Seven distinct binary hashes**, one per arm. Every treatment reached the
  artifact - the positive control the fifth house rule asks for.
- `still against alone2 ship --mine …` - **comparable**, subject differs in
  exactly the two files claimed.
- `standing.py --twice=3` - **930/930 identical across three processes.**
- `ship` was built and racked separately from `bhc` and reproduced **311,540**
  exactly, off its own folio cache.
- `zig build test` green. One test moved and is discussed below.
- Witnesses: **7 failing constructs -> 5. W5 and W6 seat. 17/17 controls stand
  on both arms**, none relaxed.
- Cost: throughput flat on all seven timed grammars (python +6.7%, the rest
  inside noise); elixir, the only forker big enough to time honestly, is
  **1.00x**. A fuse costs nothing until a parse reaches for it, and when it
  does the alternative was losing the frame.

## The test that moved

`press.lalr.test "precedence settles a shift-reduce silently and leaves no
conflict behind"` began reporting 2 conflicts against an expected 0.

It is not a bandaid to have changed it, and here is the evidence. The canonical
expression grammar (`+` at 1, `*` at 2, both left) has four contested cells on
two different rungs: two ordered by a rank written about that very pair, and two
- each operator against itself - where the ranks tie and only a side declared
over the whole rule breaks it. **The two that appeared are exactly the
associativity pair**, and all three action assertions still pass unchanged, so
the table did not move; only the recording did. That is precisely what B is for
and it is the discriminator working.

The test was **strengthened, not relaxed**: it now asserts the two addresses
that must be recorded and the two that must not, and checks the count last.
`conflicts.len == 2` is also true if the recorder fires on the precedence pair
and skips the associativity pair, which is the over-reach worth catching, and
the old `== 0` could not tell those apart.

## The instrument I trust least

**`rack`'s verilog row, and passing its own check did not clear it.**

The brief said verilog was 100% `unjudged`; on today's tree it is 4,182 bytes of
94,657, so the adjudication lane landed mid-lane and the column came alive
underneath me. It is self-consistent and it reproduces across three processes -
and none of that speaks to whether the oracle it is now agreeing with is the
right one, because what changed was *the oracle*, not the instrument. A
freshly-repaired reference agreeing with a change is the one shape that looks
identical whether the change is right or the reference drifted toward it. So
verilog's +1,573 is reported and withheld from every total I claim, and the
judged number is +4,956.

Second: **`still against` cleared this pair while `ladder.zig` sat in both
pins.** `Ladder.sided` is compiled into the control and simply never called
there, which is correct and is also why `still` saw two changed files rather
than three. It certifies that I claim what differs, not that what does not
differ is inert.

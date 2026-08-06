# Result 2 — the forest gate is load-bearing, and I found that out by shipping it and being caught

Predictions in `PREDICTION-2-forest.md`, written before the change compiled.
Control pin `holds-trace` (tree `f7c6b3ef0ccf`), treatment pin `stoop-after`
(tree `986eb8ece142`), **built two minutes apart with graft.zig as the only
file between them** - `pin.py show holds-trace` reports its live digest as the
treatment's tree, so no coworker's edit is inside the window and the attribution
is exact.

## The change

`graft.stoop` picks the root that covers the offset instead of assuming there is
one, using the same binary search every step below it already used. Roots are in
source order and do not overlap and `Quire.survey` holds them to it on every
parse, so the pick is sound as a *lookup*. Twelve lines, one new helper.

## It is a very large speed win

| grammar | control µs/key | treatment µs/key | | lifts | read |
|---|---|---|---|---|---|
| zig | 13,783 | **583** | −96% | 0 → 12 | 3,315 → 196 |
| ocaml | 31,165 | **2,369** | −92% | 0 → 14 | 4,192 → 327 |
| html | 3,205 | **304** | −91% | 0 → 2 | 9,516 → 91 |
| elixir | 21,721 | **2,030** | −91% | 0 → 65 | 5,266 → 633 |
| c | 683 | **117** | −83% | 0 → 6 | 276 → 40 |
| latex | 12,982 | **2,397** | −82% | 0 → 22 | 703 → 101 |
| sql | 4,743 | **884** | −81% | 0 → 9 | 892 → 198 |
| rust | 766 | **153** | −80% | 0 → 7 | 323 → 44 |
| scala | 4,543 | **1,326** | −71% | 0 → 23 | 1,277 → 451 |
| java | 396 | **110** | −72% | 0 → 6 | 198 → 44 |
| bash | 332 | **110** | −67% | 0 → 13 | 221 → 56 |
| lua | 875 | **353** | −60% | 0 → 4 | 505 → 174 |
| julia | 25,887 | **11,309** | −56% | 0 → 10 | 5,716 → 2,544 |
| kotlin | 34,439 | **18,560** | −46% | 0 → 3 | 4,817 → 2,538 |
| swift | 36,169 | **23,166** | −36% | 0 → 12 | 3,628 → 2,462 |
| typescript | 614 | **382** | −38% | 0 → 4 | 268 → 148 |
| cpp | 407 | **305** | −25% | 0 → 4 | 135 → 80 |
| ruby | 1,287 | **883** | −31% | 0 → 2 | 245 → 127 |
| verilog | 59,174 | **45,700** | −23% | 0 → 214 | 8,951 → 7,195 |

22 of 29 grammars faster. Median gain over the 17 mended: **1x → 3x**; 15 of 17
were at `gain < 1.5` and 4 remain. Median gain over the clean 12: 6x → 8x, and
**none of the 12 is left at 1x**. `read` falls on 20 grammars. Nothing
regressed by more than jitter except python (96 → 135 µs, one run, unrepeated).

## And it is wrong, and I only know that because of the guard

`research/keystroke/abide.py` compares the amended tree against a **cold parse of
the same bytes**, at every one of the 24 keystrokes, per grammar. Reuse is an
optimization, so those two trees must be equal.

| | control | treatment |
|---|---|---|
| grammars where all 24 amended trees equal a cold parse | **27 of 29** | **23 of 29** |
| html | 24/24 | **13/24**, first at k=4 |
| swift | 24/24 | **22/24**, first at **k=1** |
| verilog | 24/24 | **22/24**, first at **k=1** |
| lua | 24/24 | 23/24 |
| python | 21/24 (pre-existing) | 20/24 |
| toml | 23/24 (pre-existing) | 23/24 |

The disagreement is in the **root count**: verilog 2,974 amended against 2,971
cold, swift 215 against 220, html 5 against 3. A lift carried out from under one
root of a forest and spliced into a parse whose mends fall elsewhere **moves a
hole's boundary, and a hole's boundary is where the roots are.**

The header's two conditions for a safe lift are conditions on the *node* - its
bytes did not move, and the old parse read its symbol from this state. Neither
says anything about the mend structure the node is being replanted into, because
on a clean parse there is none. The `roots.len != 1` line is not an unfinished
descent. It is the only thing standing between those two conditions and a file
that has holes in it.

**html's 91% is the trap the brief named**, arriving exactly on schedule: a
policy that makes a tree cheaper and wronger looks like a win on every speed
number, and 3,205 µs → 304 µs is the most attractive number I produced today.

The change is reverted. What is kept is the `holder` helper (behaviour-identical
with the gate restored, and it makes the descent one search rather than two
spellings of one) and a header saying why the refusal is there, so the next lane
does not read it as a TODO the way I did.

## Predictions, scored

| # | Verdict | |
|---|---|---|
| P1 | **FALSIFIED** | The 12 "clean" grammars moved - java, rust, typescript, lua, html, c all gained 25–91%. My equivalence proof for `roots.len == 1` was correct; my premise was not. A grammar that *opens* clean does not *stay* clean: java, rust and typescript accept only 5 of 24 warm parses, so the gate was blocking them for 19 of 24 keystrokes. I read my own instrument's `open` column as if it were the gate's input. |
| P2 | held | every forest went `offered = 0` → `offered > 0`. The least impressive prediction I made: it says a gate I deleted stopped firing. |
| P3 | held | latex 22 lifts, zig 12, julia 10, kotlin 3 - all > 0. |
| P4 | held | latex −82%, zig −96%, kotlin −46%, julia −56%, all past the 40% line. |
| P5 | **FALSIFIED, both halves** | I predicted swift < 30% and swift staying the worst row. Swift dropped **36%**, and **verilog is now the worst row at 45,700 µs**. I priced swift's two ceilings correctly and then underestimated what was left. |
| P6 | held | median 1x → 3x, and 11 of 17 left the 1x bucket against a floor of 6. |
| P7 | **FALSIFIED** | Trees changed. This is the prediction that mattered, it is the one I argued most confidently, and the argument was structurally incomplete in exactly the way the code comment I was reading did not say. |
| P8 | n/a | Not reached - the change is out before `built` is worth measuring. |

Four of eight predictions I logged, three falsified, and the three failures are
the entire finding. P7's falsification is the result.

## Two defects this lane did not cause and is not fixing

`abide` on the **control** pin (and the reverted tree, identically):

- **toml diverges at k=1.** One keystroke, and the amended tree is not the tree a
  cold parse gives. `root 0 diverges at char 93` - a `(comment)` moves out of a
  `(pair)`'s array and into the table. toml opens clean, has one root, and is on
  the board's perfect list.
- **python diverges at k=16** - 9 roots amended against 1 cold, so the amend
  keeps a forest where a cold parse recovers to a single tree.

Both are reproducible with
`python3 research/keystroke/abide.py toml python`, and neither has anything to do
with forests or lifts.

## What the real ceiling is

The suffix half cannot be turned on for the mended 17 by widening the descent.
It needs the **mend boundaries in the offer** - `Graft` already carries `seam`
for exactly this reason on the prefix side, and the lift side has no equivalent.
A candidate would have to be refused when its span crosses a hole in either the
old tiling or the new one, and `stoop` currently cannot see either.

The prefix half is a smaller and better-shaped job, and it owns Swift: make
`holds` narrow the way `offer` narrows. The clean version of that is not to
reconstruct the slate but to **verify after mounting** - `remount` is a memcpy,
and once mounted `x.live` is real, so `offer()` is exact and the state-0 and
multiple-top failures both vanish. Four memcpys worst case against four re-lex
walks. It does not touch holes, so scala stays broken until the tiling does.

Ordered by what a user feels: `holds`-after-`remount` gets swift, ocaml, scala
and verilog off the cold-parse-per-keystroke floor and onto the `(1 − p)` one,
which is a 2x - not the 10x the forest lift dangled, and it is a 2x that is the
same tree.

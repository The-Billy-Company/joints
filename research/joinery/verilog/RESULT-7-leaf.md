# Result 7 — the leaf gap, partitioned

Every number here was read on isolated arm **`leaflane`** (binary `69c0b9172`,
built from tree `0d4217867`) unless it says otherwise, and cross-read on the
tree's own `zig-out/bin/joints`, which was rebuilt under me three times
(`1570509f7`, `151af229f`, `bfdfe5443` — three other lanes are in these files
tonight). picosoc and spimemio never moved; picorv32 read 59.4 / 59.3 / 58.3 and
simpleuart 86.7 / 86.7 / 87.6. §6 has that table, because it turned out to be a
finding rather than noise.

Yardstick throughout: `verible-verilog-syntax --export_json --printrawtokens`,
which lexes the text as written and needs no parse tree to agree with.

## The headline, up front

**Two defects, and the one that made verilog the widest gap on the board is not
the one that matters.**

- The deficit is **98.0% reach and 2.0% shape.** 590 bytes sit inside a node we
  built with no leaf on them; **29,537 sit under no node of ours at all.** The
  tag histogram everybody would reach for first is a photograph of where
  recovery landed, not a list of constructs we cannot lex.
- **The externals are not starved. There are none.** Verilog declares
  `0 external` terminals. Haskell's disease was a declared protocol nobody
  seated; there is no protocol here to seat, and the haskell playbook does not
  apply. What verilog has instead is **181 declared conflicts**, the most of any
  grammar in the checkout.
- **The construct was already named in this folder; what is new is that it is
  general verilog.** [README.md](README.md) has *"a select inside a
  concatenation … wall `;` in 701"* at 19,928 bytes, priced on picorv32 alone.
  Measured against three further real sources, state 701 is the wall on **two
  of them too**, and parenthesising the construct away takes them from 86.7%
  and 95.0% to **100.0%, deficit zero** — on those files it is not part of the
  leaf gap, it is the whole of it.
- **What makes picorv32 read 59% instead of 87–95% is compiler directives**, and
  that part *is* picorv32's. Blanking its 119 directive lines is worth
  **+6.0 points** and drops the mend count from 1,981 to 1,358. The README
  prices this defect at 21,535 bytes and calls it the larger of the two; on a
  leaf-coverage yardstick and outside this one file, it is the **smaller**.

I shipped no parser change. Three lanes are inside `gather.zig`, `bench.zig` and
`plumb.py` tonight and the seam this lands on is one of theirs; §6 is the
handover. What I did ship is a permanent check, two witnesses, and two
corrections to the instrument that were quietly inflating the answer.

## 1. The 30,127 bytes

`python3 research/joinery/verilog/leaf.py`, on the arm:

```text
# leaf gap — verilog  picorv32.v  94657 B
  verible: 74194 B carry a non-blank token, in 17510 tokens
  joints leafs 44140 B · tree-sitter 73357 B · DEFICIT 30127 B
  of verible's token bytes we stand a leaf on 44097 — 59.4%
  of that deficit: 590 B under a node we built with no leaf on it,
                   29537 B under no node at all
  recovery stepped over 31792 B in 1981 mend(s) — 108% of the unreached half
```

**The brief's figure was 29,283 and it moved to 30,127 under me** — 844 bytes,
in the direction of worse, from siblings' in-flight edits to the mend path. That
is the drift the brief warned about, and it is why every row of the permanent
check records the tree it was read on.

### By what Verible calls them

| verible tag | deficit B | of that tag | whole tokens missed |
|---|---:|---:|---:|
| SymbolIdentifier | 17,345 | 40% | 1,465 |
| TK_DecNumber | 1,483 | 49% | 1,159 |
| `begin` | 1,370 | 93% | 274 |
| `<=` | 1,348 | 95% | 674 |
| TK_BinDigits | 917 | 72% | 201 |
| `;` | 755 | 59% | 755 |
| MacroArg | 564 | 35% | 1 |
| `)` / `(` | 1,110 | 77% | 1,110 |
| TK_EOL_COMMENT | 527 | 26% | 51 |
| … 40 more tags | 4,708 | | |
| **wholly leafed (23 tags)** | 0 | | TK_COMMENT_BLOCK 1,900 B · `parameter` 729 · `wire` 360 · `input` 305 · `assign` 258 · `` `define `` 56 |

**This partition is a dead end and saying so is the point.** The top row is
plain identifiers at 40% missed; the misses are spread across 49 of 72 tags; and
`` `ifdef ``, the construct that actually walls first, is 43 bytes. There is no
lexical category here we cannot stand on. Twenty-three tags — including both
comment shapes and every declaration keyword — are leafed to the byte.

### By region

| | |
|---|---:|
| contiguous deficit runs | **4,693** |
| mean run | 6.4 B |
| median run | **2 B** |
| widest run | **45 B** |
| runs of ≤ 8 B | 3,212 (8,104 B) |

**Nothing is missing in a block.** Thirty thousand bytes in 4,693 runs with a
median of two is a token-by-token dropout across the whole file, and the widest
hole in a 94 KB file is forty-five bytes. That is the signature of a parser that
keeps resynchronising, not one that fails to reach a region.

The two arithmetic facts agree: 1,981 mends over 31,792 bytes is **108% of the
29,537 unreached** (recovery steps over some bytes twice). The deficit *is* the
mend trail.

## 2. Attribution

`inquest`, re-derived on this tree rather than inherited:

```text
joints: picorv32.v: unexpected ` at 3712 in state 3438, 3430 roots,
          mended 1981 over 31792B, supplied 34, spurned 11
joints: verilog: press? on ` in state 3438 (0 dropped, 34 misfolded):
          a merge damaged this terminal's cell elsewhere, and no fold chain
          was supplied to say whether this wall is downstream of it
```

**Not `lexer`.** The brief named `lexer` as the live hypothesis on the grounds
that the wall states hold no contested cell. The wall states hold no contested
cell because *they are downstream*: `press?` with `0 dropped, 34 misfolded` is
inquest saying, correctly, that the cell that did the damage is not this one.
§4 finds it.

Byte 3712 is `` `ifdef RISCV_FORMAL `` **inside a module port list**.

## 3. Externals: absent, not starved

Straight from the press, `joints grammar`:

```text
terminals   398 literal, 46 regex, 0 external
conflicts   181 declared
contested   19329 cells (2607 s/r, 16722 r/r)
            2 repetition, 18710 declared, 136 RESIDUAL
```

Across the twenty grammars in `.local/differential/lang/`:

| grammar | externals | declared conflicts |
|---|---:|---:|
| swift | 33 | 40 |
| scala | 31 | 69 |
| ruby | 30 | 0 |
| bash | 29 | 6 |
| … | | |
| **verilog** | **0** | **181** |
| c · go · java · json · zig | 0 | 17 · 8 · 13 · 0 · 6 |

**Verdict: verilog cannot be starved the way haskell was.** Haskell declared a
layout protocol and left it unseated; seating it on a `writ` troupe was worth
23.8% → 73.6%. Verilog declares no external scanner at all, so there is no blind
list to consult and no troupe to seat. Six of twenty grammars are in the same
position. Verilog's compiler directives are ordinary literal terminals
(`` `ifdef `` is one of the 398), which is why it walls on a *grammar* position
rather than on a lex.

The number to carry forward is the other one: **181 declared conflicts, the most
on the board**, and 18,710 contested cells the author explicitly asked to be
forked. §4 is about one of them.

## 4. The witness, and the cell one level below the one on record

[README.md](README.md) already names this construct and its wall
(`` `a select inside a concatenation` `` → `;` in 701), and
[RESULT-2-witness.md](RESULT-2-witness.md) found it. What follows is not that
discovery again: it is the trace line that says which cell chooses, which the
earlier chapters looked for in state 1701 and 1184 and could not close.

56 bytes, in `witness/lone-select.v`:

```verilog
module m; reg [31:0] a, c; assign c = {a[3]}; endmodule
```

Refused. Add one pair of parentheses (`witness/lone-select-parenthesised.v`) and
it is `accepted, 1 root`. Same tokens, same order.

```text
unexpected ; at 731 in state 701, 18 roots, mended 1 over 1B
press? on ; in state 701 (0 dropped, 34 misfolded)
```

State 701 is one item and accepts **one terminal of 444**:

```text
state 701 of verilog
  items:  casting_type -> constant_primary .
  row — lookahead:
    '        fold  casting_type -> constant_primary
  shift 0, lookahead 1 — 1 terminal(s) accepted of 444
```

By the time the `;` arrives the parse is inside a cast's operand, where a `;`
cannot mean anything. Nothing can be repaired *at* state 701; it is already
over.

### Where it actually goes wrong

`JOINTS_TRACE=quire` on the 56-byte witness, in full — three lines:

```text
split: state 1599 on [ at 727 rank 0 - keeps read on -> 2448,
                                       casts fold generate_block_identifier #4255
split: state 2979 on ] at 729 rank 0 - keeps fold constant_primary #4021,
                                       casts fold primary #4043
refuted: state 701 on ; at 731 rank 0 - keeps nothing, casts nothing
```

**The second line is the defect.** At the `]` that closes the bit-select, the
parse must decide what `a[3]` is. It keeps `constant_primary` — the operand of a
cast — and casts off `primary`, which is the reading a concatenation needs.
**Both sides are `rank 0`**: neither production carries a dynamic precedence, so
nothing in the grammar breaks the tie and the tie is broken anyway.

The grammar author saw this coming. `grammar.json` declares
`['primary', 'variable_lvalue']` and fourteen further conflicts naming both
`primary` and `variable_lvalue`, plus `constant_primary` in eight of them. This
is a cell the author explicitly asked to be forked and adjudicated at runtime,
which is what tree-sitter's GLR does with it.

The static half of the same defect is visible one state over, in 1701, which
holds both completed items:

```text
state 1701:  primary -> _identifier select1 .
             variable_lvalue -> _identifier select1 .

  ,   fold  variable_lvalue -> _identifier select1   [prec 37 left]
  =   fold  variable_lvalue -> _identifier select1   [prec 37 left]
  }   fold  variable_lvalue -> _identifier select1   [prec 37 left]
  ... every other terminal   fold  primary -> _identifier select1
```

Three lookaheads go to `variable_lvalue` because it carries `prec 37 left` and
`primary` carries nothing. **Two of those three — `,` and `}` — are exactly the
tokens that follow an element of a concatenation.** On the left of an `=` the
lvalue reading is right; on the right of one it is wrong; and at this point the
parser cannot know which side it is on. An authored rank on one arm and an
implied zero on the other decides it, with no fork.

This is the same family as
[HANDOVER-wrong-limb.md](HANDOVER-wrong-limb.md) — a legal fork resolved to the
wrong limb — at a different cell, and this is the one that costs the leaf gap.

## 5. What it is worth, measured against a control that can say no

`leaf.py --ablate` parenthesises every concatenation element that is a lone
select and nothing else, then re-measures. Byte-for-byte identical file apart
from the pairs added, so whatever the number does is what the construct cost.

| source | size | as written | lone selects parenthesised | Δ | edits |
|---|---:|---:|---:|---:|---:|
| `picorv32.v` | 94,657 | 59.3% | 59.7% | **+0.4** | 32 |
| `picosoc.v` | 6,891 | 92.2% | 92.2% | **+0.0** | 0 |
| `simpleuart.v` | 3,563 | 86.7% | **100.0%** | **+13.3** | 3 |
| `spimemio.v` | 13,474 | 95.0% | **100.0%** | **+5.0** | 8 |

Those four rows are the tree binary's, taken in one sitting so that both arms of
each counterfactual share a generation; the pinned arm reads picorv32 at 59.4
rather than 59.3 and the other three identically.

**Three rewrites take simpleuart to zero deficit. Eight take spimemio to zero
deficit.** On those two files this construct is not part of the leaf gap, it is
the whole of it. On picosoc it is worth nothing, because picosoc contains none;
picosoc walls on `macro_text` at 916 in state 176, a different defect I did not
chase.

And the walls agree with the counterfactual. Each file's first stop:

| source | first wall | mends | stepped over | mends/KB |
|---|---|---:|---:|---:|
| `picorv32.v` | `` ` `` at 3712, state 3438 | 1,981 | 31,792 B | **20.9** |
| `picosoc.v` | `macro_text` at 916, state 176 | 41 | 489 B | 5.9 |
| `simpleuart.v` | `;` at 2722, **state 701** | 29 | 404 B | 8.1 |
| `spimemio.v` | `;` at 10868, **state 701** | 55 | 557 B | 4.1 |

**State 701 is the wall on two independent files and on the 56-byte witness.**
That is what makes this general verilog rather than a picorv32 artifact.

### The directive half, which is picorv32's

Blanking picorv32's 119 compiler-directive lines to spaces — offsets preserved,
nothing else touched:

| arm | share | mends | stepped over |
|---|---:|---:|---:|
| as written | 59.4% | 1,981 | 31,792 B |
| directive lines blanked | **65.4%** | 1,358 | 26,230 B |
| also every remaining backtick token | 65.4% | 1,358 | 26,230 B |

**+6.0 points, and it moves the first wall to `;` at 12056 in state 701** — the
lone-select wall, on
`assign mem_la_addr = … : {reg_op1[31:2], 2'b00};`. The two defects are stacked:
directives wall first and loudest, the fork walls underneath.

The third row matters: after the directive *lines* are gone, the seven remaining
`` `assert ``-style macro calls cost nothing. It is directives at grammar
positions the tree-sitter grammar does not admit — inside a port list, inside a
statement body — not backticks as such.

**Explicitly: this is picorv32's, not verilog's.** 119 directive lines in 94 KB
is a formally-verified core carrying `` `ifdef RISCV_FORMAL `` scaffolding. The
other three files have essentially none, and none of them is below 86%.

## 6. What I changed

**No parser change.** The seam in §4 is `Reading.beats` in `gather.zig`, where a
lane is adding a structural tie-break tonight; `rank 0` against `rank 0` is
exactly the case that tie-break exists for. I am not going to edit that file
underneath them. An earlier version of this lane did try a repair in
`column.zig` and `bench.zig`, measured no change in the contested count, and
reverted it; that is recorded here so the next lane does not spend the afternoon
the same way.

Three things did land.

**A permanent leaf-coverage check** — `leaf.py --check`, against
`leaf.floor.json`. Four rows, each a share of an external lexer's token bytes,
each with the tree it was measured on. It skips loudly when a source or the
yardstick is absent rather than passing, verifies each second-corpus file's
sha256 before believing it, and carries the two witnesses with their verdicts
written down. A witness whose verdict is `refused` is a defect held in place so
that *repairing* it fails the check and has to be acknowledged, rather than
going quietly green. I proved it can say no on all three failure modes.

**Two instrument corrections**, both of which were flattering us:

- `share` was `our leaf bytes ÷ their token bytes`, which is not a coverage
  number: a leaf span may cover trivia the lexer calls blank, and spimemio
  ablated read **100.2%**. It is now the intersection, so it cannot exceed 100
  and it is consistent with the deficit it is quoted beside. Every figure on
  this page is 0.06 to 0.3 points below the same figure taken this morning for
  that reason alone.
- The counterfactual was parenthesising concatenations in **lvalue** position,
  where a parenthesis is not legal verilog. It manufactured its own third wall
  at `{(mem_rdata_q[31:25]), …} <= …` and I nearly reported it as a third
  defect. `assigned()` now leaves those alone, conservatively, so the experiment
  can only understate.

**A second verilog corpus.** Three more real sources from the same upstream
repo, digested and recorded in `leaf.floor.json` with their URLs. They are the
reason §5 can distinguish verilog from picorv32 at all.

### What the check caught in its first hour, which is the argument for it

The tree's binary was rebuilt three times while I was setting the floors. On the
18:41 build — with `gather.zig` newer than the binary, so this is a lane
mid-edit and not a settled reading:

| source | pinned arm | 18:41 tree | Δ |
|---|---:|---:|---:|
| `picorv32.v` | 59.4% | **58.3%** | **−1.1** |
| `simpleuart.v` | 86.7% | **87.6%** | **+0.9** |
| `picosoc.v` | 92.2% | 92.2% | 0 |
| `spimemio.v` | 95.0% | 95.0% | 0 |

**One binary, one point down on one file and one point up on another.** That is
a plausible shape for a structural tie-break at a `rank 0` cell, which is what
`Reading.beats` is getting tonight, and it is exactly the trade nothing on the
board could have shown: `standing`, `damage` and `square` are all identical
across that pair, because the spans did not move — only which leaf sits under
them.

To whoever owns that change: the two files disagree about your patch, and §4's
56-byte witness is the cheapest place to see which way. It is worth running
`leaf.py --check` on the arm you are about to land, if only to know the number
before somebody else finds it.

It is also why the picorv32 row carries a point and a half of headroom where the
rest carry half a point. That asymmetry is temporary, its reason is written into
`leaf.floor.json`, and it retires the day `gather.zig` settles.

### Where the check is not yet wired

It is a committed floor, a manifest, and a script that exits 1 — and I did not
add it to `.github/workflows/ci.yml`. Two reasons, both worth someone's
attention rather than mine tonight. Verible is a prebuilt binary a lane
installed by hand and is not pinned by `tool/grammars.py`, so three of four rows
would skip in CI and the step would be asserting only the witnesses. And the
natural home for a coverage number is the board itself, in `standing.py` beside
`spoil` — which is 2,392 lines with a lane sweeping `plumb.hurt()` through its
neighbour tonight. Both are one coordinated step; neither needs any of this
re-derived.

## 7. What I trust least

1. **The three second-corpus files are from the same repository as the first.**
   Same author, same house style, same decade. `{a[3]}` being their common wall
   is strong evidence it is general verilog; it is not evidence about
   SystemVerilog written by anyone else. A UVM testbench or an OpenTitan module
   would test this properly and I did not fetch one.
2. **Picosoc's wall is unexplained.** `macro_text` at 916 in state 176 costs it
   450 bytes and I did not chase it. It is the one row of the four where I
   cannot name the construct.
3. **The 2.0% shape half.** 590 bytes are under a node with no leaf and I have
   not looked at a single one of them. They are 2% of the deficit, so ignoring
   them was right for this lane, and it does mean the reach story is 98% of a
   story.
4. **Verible's token stream is a lexer's opinion.** It calls `` `ifdef `` a
   token and does not resolve it, which is exactly what makes it a fair
   yardstick for "there is a token here" — but a preprocessing verilog tool
   would produce a different denominator, and "98.8% of Verible" is not the same
   claim as "98.8% of the verilog".
5. **Every figure moved under me at least once, and one moved 1.1 points in the
   last hour.** The deficit went 29,283 → 30,127 between the brief and this page
   from siblings' edits; the tree binary changed generation three times, once
   mid-run (the stamp caught it and said `SPLIT`); and the 18:41 build moved
   picorv32 down a point while moving simpleuart up one. The arm figures are one
   generation and are the authority here; the tree figures are labelled as such.
   **If you are reading this a day later, re-run `leaf.py --check` before
   quoting any number on the page** — that is what it is for.

Nothing on this page depends on `crooked`, `square`, `trued`, `standing`, or
`damage`. It is Verible's token stream, our leaf spans, and `joints state`.

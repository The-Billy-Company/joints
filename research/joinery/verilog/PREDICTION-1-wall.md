# Prediction 1 — what is standing on verilog's 63,937 bytes

Written before running a single ablation. Everything quoted below is a board I
already hold, taken against the pinned binary `.local/pin/mendlane`
(`33a3dac8b195`, tree `bd7b3e9399d9`, commit `f7ba40004`+92 dirty):

```
verilog   94,657 bytes   32.5% standing   30,720 built
          63,937 damage = 3,267 orphan + 14,057 rubble + 46,613 spoil
          unexpected ` at 3712 in state 3438, 3544 roots, mended 2109 over 32992B
```

Byte 3712 is the `` `ifdef RISCV_FORMAL `` **inside `module picorv32`'s port
list**. The file holds 126 backticks over 12 distinct directive words
(`endif` 25, `debug` 22, `ifdef` 21, `assert` 14, `define` 13, `else` 13,
`FORMAL_KEEP` 10, `ifndef` 4, and four singletons).

Read-only facts I am *not* predicting, because I already measured them: the
cold peel at depth 400 names 40 distinct walls at `voice 52.7`, and 12 of the
first 12 it prints are `in state 0` — a tail resumed mid-expression refusing its
own first token. The peel is noisy on this file and I am not going to build an
argument on it.

---

## P1 — the wall is the directive family, and it is worth most of the damage

**Predicted:** blanking every `` ` ``-directive *line* to same-length filler
raises `built` by **at least 25,000 bytes** on a file that is 94,657 bytes and
currently builds 30,720.

**Falsified by:** under 25,000. If the directives are worth five thousand bytes,
"the wall is preprocessor directives" is a correlation and I have to go find the
real one.

126 backticks against 2,109 mends is 17 mends per backtick, so I already know
the directives cannot be mending *once each*. Either one directive fells the
stack repeatedly, or the directives are not the whole story. I expect the first
and I am prepared to be wrong.

---

## P2 — the negative control: comments are the dye, not the wall

`research/joinery/orphan/` earned its Kotlin result by pairing the positive
ablation with a negative one — blanking every comment left `built` unchanged
**to the byte**, which is what made "the wall is strings" an impossibility
argument instead of a correlation. `picorv32.v` carries 94 line comments (2,034
bytes) and 11 block comments (1,900 bytes).

**Predicted:** blanking all 3,934 bytes of comment leaves `built` at 30,720 **to
the byte** and the mend count at 2,109.

**Falsified by:** any movement in either. Which would be the more interesting
result: it would mean verilog's damage is partly comment-shaped, unlike kotlin's,
and my positive ablation would need a comment-blanked baseline to be read against.

---

## P3 — `--mend=keep` is a describing-less trap and `covered`/`spoil` catch it

The board's own docstring says `--mend=keep` buys **25,457 bytes** of apparent
improvement on `picorv32.v` while printing **9,550 fewer nodes**. An earlier
lane earned the sharper rule: *falling node counts are only reading-less when
`covered` falls or `spoil` rises alongside them.*

**Predicted, all three:** under `--mend=keep`, `built` rises by ≥ 20,000,
`describes` falls by ≥ 5,000 nodes, **and** at least one of `covered` falling or
`spoil` rising fires.

**Falsified by:** `covered` rising *and* `spoil` falling while `describes` falls.
That combination would mean `keep` reads more of the file with fewer nodes — a
genuine improvement wearing a trap's clothes — and the board's warning about
this policy would be the thing that is wrong.

---

## P4 — the tail is repetition, not depth, and the corrected `voice` says so

Now that `mends` reports truthfully, `voice` = mends / distinct walls is
readable for the first time. At depth 60 it read 211×; at depth 400, 52.7×.

**Predicted:** the *warm* peel — which keeps the accumulated state a cold resume
throws away — names **fewer than 40** distinct walls in 400 rounds, i.e. fewer
than the cold peel, because most of the cold peel's 40 are `in state 0`
artifacts of resuming mid-expression rather than walls the parser meets.

**Falsified by:** the warm peel naming 40 or more. That would mean the cold
count is a floor here as `walls.py`'s own docstring expects, the tail really is
layered, and verilog is a second project rather than one loud defect.

This is the prediction I am least confident in. `walls.py` documents the cold
peel as a **floor** on wall variety and I am predicting it behaves as a ceiling
on this one file. If I am wrong the finding is that verilog is the grammar the
instrument's own caveat was written for.

---

## P5 — my own flattering number, named in advance

An ablation that raises `built` by 25,000 bytes has an obvious cheat available:
`built` is bytes under a top-level root **with at least one child**, so one
dishonest root stretched across a hole scores the whole hole. Blanking a
directive line to filler could give the table a token it happily shifts into one
enormous construct that describes nothing.

**Predicted:** every ablation row I report prints `describes` (nodes), `leaves`
(bare top-level tokens) and `spoil` beside `built`, and the winning ablation
raises `built` while `describes` **also rises**.

**Falsified by:** the winning ablation raising `built` while `describes` falls.
If that happens the ablation is the same trap as `--mend=keep` wearing my name,
the byte number is worthless, and I have to say so as the headline rather than
in a footnote.

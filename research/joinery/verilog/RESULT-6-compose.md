# Result 6 — A and B composed. They concatenate; they do not compose

Three lanes converged on this pair and none ran it. I ran it. **The composition
is not a repair**, and the run turned up something larger than the question it
was asked: the grammar all three lanes were arguing about **cannot be
adjudicated by the oracle at all**, so every verilog number in this thread —
including the 63,937 in my own brief — is a claim no second parser has ever
checked.

| arm | verilog | scala | elixir | corpus damage | describes | **square** | controls |
|---|---|---|---|---|---|---|---|
| **isolation control** | 63,937 | 4,150 | 0 | 130,640 | 107,763 | **301,782** | 17/17 |
| **A** host's rank wins the splice | 67,349 | 4,150 | 0 | 134,052 | 106,138 | **301,782** | **13/17** |
| **B** record the side-rung cell | **62,645** | 16,883 | 8,795 | 150,798 | 104,762 | **272,434** | 17/17 |
| **A+B** | 67,774 | 16,883 | 8,795 | **155,927** | **102,059** | **272,434** | **13/17** |

A+B is the **worst arm on every column of the board**. It is worse than A on
verilog, carries B's whole scala and elixir cost, and reads 5,704 fewer nodes
than the control.

## The two findings that matter more than the table

**A buys nothing.** Not "a little"; zero. `square` — the only column not made
out of the thing it checks — is **301,782 under the control and 301,782 under
A**, byte for byte, on all thirty grammars. A's entire visible effect is 3,412
built bytes moving *out* of `unjudged` (35,837 → 32,425), which is to say A
changed only bytes the oracle could not have an opinion about. It also breaks
four controls. There is no reading of A on which it is a repair.

**B is not "the best result anyone got".** RESULT-2 ranked B highest because it
seats the most witnesses at 17/17 controls, judged on `built`. On `square` B
**destroys 29,348 bytes of oracle-agreed derivation** — and per grammar it is
not a shave, it is a demolition:

| grammar | square, control | square, B |
|---|---|---|
| elixir | 23,879 | **1** |
| scala | 6,739 | 534 |

Elixir goes from 23,879 bytes of structure tree-sitter agrees with to **one
byte**. The board's damage column reports that as `elixir 0 → 8,795`, because
`damage` is `size − built` and a forest of 731 roots still covers its bytes.

The tell is in the split. Under B, `racked` (right leaf, wrong parent) falls
42,496 → 15,069 while `unframed` (agrees rung for rung under a frame we never
built) rises 12,101 → 40,934. B does not stop building wrong parents. **It stops
building the parents.** That is the shredding, and `built` cannot see it.

## The mechanism: why the composition was never going to work

RESULT-5's hypothesis was *A so the cell answers `fold`, B so the forks A
deletes come back as forks*. The two repairs act on disjoint rungs, and the
press's own census prices the overlap exactly.

| verilog | contested | s/r | r/r | declared | residual | LR(0) states | frayed |
|---|---|---|---|---|---|---|---|
| control | 18,850 | 2,128 | 16,722 | 18,710 | 136 | 9,763 | 3,509 |
| A | 9,928 | 1,759 | 8,169 | 9,900 | 24 | 9,276 | 7,056 |
| B | 19,329 | **2,607** | 16,722 | 18,710 | 136 | 9,763 | 3,509 |
| A+B | 10,394 | **2,228** | 8,166 | 9,900 | 24 | 9,276 | 7,056 |

**A removes 8,922 contested cells**, 8,810 of them declared, and collapses 487
LR(0) states. It does that at **rung 2**: with the host's 37 restored, the
reading polls *above* the fold and precedence answers. A decided cell is not a
recorded cell, so the fork is gone.

**B adds 479 shift/reduce cells and changes nothing else** — reduce/reduce,
declared, residual, states and frayed are all byte-identical to the control.
That is "purely additive by construction" holding exactly as claimed. But B
records cells **rung 3** decided, and A's 8,922 never reach rung 3.

On A's table B contributes **+469** cells. **B replaces 5.3% of what A deletes**,
and those 469 make verilog *worse* than A alone (67,774 vs 67,349) because
`gather` takes the wrong limb on them — the same second defect
`HANDOVER-wrong-limb.md` names.

The folios say the same thing without a board run. Against the isolation
control, **A moves 3 tables** (bash, scala, verilog) and **B moves 24**; A+B
differs from B in exactly A's 3 and from A in exactly B's 24. The composition is
set union with no interaction term.

## Verilog is 100% unjudged, and that is the real headline

```
verilog   30720 built   0 judged   0 square   —  tree-sitter's CST and XML disagree
```

Under every arm. Verilog contributes **zero adjudicable bytes**, so `square`
cannot rank these repairs on the grammar they were designed for. The only
instrument that can speak about verilog is `damage`, and `damage` is
`size − built`, which one root stretched over a hole buys outright — precisely
the failure mode `rack.py` was built to catch and cannot catch here.

So: three lanes spent three dossiers optimising a number on the one grammar
where the honest metric is structurally unavailable. That is worth more than my
A/B table.

## Corrections to the record

**A is not 17/17 on controls.** RESULT-2 and RESULT-3 both record it that way.
Against today's suite A fails **four**: W10, W12, W13, W16. Three of them are
dead-plain procedural Verilog whose controls fail at `macro_text in 1359` —
`case (1'b1) eq: x = 1; default: x = 0; endcase` and `x = eq ? a : a;` and
`x = eq ? a : b;`. A witness beside a failing control proves nothing, so A also
voids four rows of the evidence it was credited with. I cannot prove the suite
is unchanged (`smallest.py` is untracked), but A reproduced verilog **67,349
exactly**, so the binary is behaving as RESULT-2's A did.

**A's provenance is inert.** I built A twice — once carrying the host's
`spliced` bit with the host's rank, once flipping `prec` alone. Identical:
67,349, same four control failures, same folios. The `Step.spliced` bit RESULT-3
shipped and repair A do not interact.

**B is unchanged by the provenance bit.** I predicted B would be much cheaper
today because the cells it was buying with are already forks. Wrong: B reproduces
verilog **62,645** and scala **16,883** exactly, pre- and post-provenance. The two
touch disjoint cells.

**The scala witness does not isolate.** RESULT-2 attributes B's scala cost to
`@SerialVersionUID(0) class Some[+A] …` splitting its annotation off. Written out
on its own — and lifted verbatim from `Option.scala:617-620` — that construct
**stands under all four arms, one root**. What actually happens is upstream:
B moves the file's first wall from **line 627 to line 303**
(`def flatten[B](implicit ev: A <:< Option[B]): Option[B] =`, an `_end_keyword`
external), and the file goes from **26 roots to 281**. The `Some` site looks
shredded because it is 300 lines downstream of a mend cascade, not because it is
contested. The symptom was reported correctly and the cause was not.

## Is A+B a good trade? No, and here is the next cheapest thing

It buys verilog damage nothing (it is *worse* than baseline by 3,837 and worse
than A by 425), pays 12,733 scala and 8,795 elixir, gives up 29,348 square bytes
and 5,704 nodes, and breaks four controls. Reject.

The next cheapest repair is not on this rung at all. **B's press behaviour is
correct and its consumer is not.** B offers 479 legitimate forks, seats W5 and
W6 at zero control cost, and every byte it loses is lost *downstream* — `gather`
picking the wrong limb of a fork the press was right to offer. RESULT-2 said
this, RESULT-5 said this, and both then went looking for a different press
change. The measurement now prices it: **fixing the limb choice is worth 29,348
square bytes** — that is what B would stop costing — and it is the only work in
this thread with a number attached that `built` cannot flatter.

Before that, someone should find out **why verilog is unadjudicable**. A CST/XML
disagreement in one grammar's oracle is a tooling defect, and until it is fixed
no verilog repair in this dossier — mine, A, B, or the three before them — can be
judged by anything but a metric a stretched root can buy.

## How this was measured

Four arms, each a pinned binary (`tool/pin.py`) with its own folio cache and its
own oracle seat. The control is an **isolation arm** — today's live tree with my
rows removed and the plumbing left in — pinned **after** the arms, so sibling
drift cancels rather than having to be outrun. It is the only arm whose stamp
carries no `DRIFT` line, which is the check: the other three measure trees that
no longer exist, by construction.

**Positive control on the press.** A press change must move a pressed table, so
before spending a board run I confirmed every arm mints folios that differ from
the control's — A on 3 grammars, B and A+B on 24. An arm pressing byte-identical
tables has not been applied. (This check is real here and vacuous for a scanner
or runtime arm.)

**One frozen oracle**, `attest.py freeze c7-compose`, digest `d85e736fa` over 30
grammars, named in all four rack reports.

**Stability**: `standing.py --twice=3` on the composed arm — 930 numbers over 3
runs, all identical. Every figure above was also taken independently in an
rsynced scratch tree an hour earlier, against a private clone of
`.local/differential/`, and **reproduced exactly** — two worlds, same numbers.

No production change was made. The tree is byte-identical to how I found it
(`src` digest `cfb624e3a02d`), so there is no changelog fragment: this lane
measured and rejected, and the argument lives here.

## The instrument I trust least

`damage`, and by extension every headline number in this thread including the
one in my brief. It is `size − built`, both terms are joints's own words about
its own forest, and one root stretched over a hole moves it the flattering way.
B is the proof: it *improves* verilog damage by 1,292 while giving up 29,348
bytes of agreement with a second parser and reducing elixir to a single square
byte. On verilog, where `square` is unavailable, `damage` is the **only**
instrument — which means the grammar this thread cares most about is the one
where its numbers are least worth believing.

Second least: `smallest.py`'s control column. It is the right idea and it caught
A, but it is untracked, so a claim of 17/17 in an older dossier cannot be
checked against the suite that produced it.

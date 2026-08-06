# Result 4 - the 6,316 and the 6,591 are not the same bytes, and neither is a residue

Scored against [PREDICTION-2](PREDICTION-2-rederive.md) P2.1–P2.3. Arm
`unjudged` (`outliner 94d59d9ad`, tree `05a18fcd1`), one whole-file parse per row.
Tool: [`reconcile.py`](reconcile.py).

> **They are provably different bytes, on two independent grounds. The 6,477
> `macro_text` bytes live entirely inside `[3,712, 14,782)`, which is inside
> `picorv32`; the 6,316 is what is left over *outside* `picorv32`. And 6,163 of
> the peel's 11,070 `behind` bytes are bytes verilog **built**, so `behind` is
> not a slice of `damage` even in principle.**
>
> **The record is double-counting, and not where the hand-off guessed.** The
> `6,316 ≈ 6,591` coincidence is a red herring. The real defect is that 8,175 and
> 49,446 were quoted as if they partitioned 63,937, and they cannot: one is a
> census of real bytes and the other is a counterfactual about a file that does
> not exist.

## What each of the four numbers actually is

| number | instrument | unit | extent |
|---|---|---|---|
| **63,937** | one whole-file parse | `size − built`, real bytes | the file |
| **49,446** | the same parse, clipped | `size − built`, real bytes | `picorv32` `[1,863, 71,067)` |
| **8,175** | three ablations of a **file that does not exist** | Δ *honest built* | no extent - a delta |
| **6,477** (was 6,591) | `walls.py`, 400 peel rounds | `behind`, a tiling by wall-reachability | `[3,712, 14,782)` |

Three of the four reproduce on this arm to the byte. The fourth does not, and
that is the finding.

## The census is exact; the counterfactual is not even stable

```text
  damage, whole file                        63,937
  damage inside picorv32 [1863, 71067)       49,446   <- the census, to the byte
  damage outside it                          14,491
  ablation delta, honest built               +9,422   <- the "8,175", today
  ablation delta, raw built                 +13,341   <- the same ablation, in DAMAGE's units
```

**P2.1 held exactly.** 49,446 is `size − built` clipped to one module, and
`63,937 − 49,446 = 14,491`, and `14,491 − 8,175 = 6,316`. So the "residue" was
never a gap in the record: it is *unattributed damage in the other seven modules*,
which nobody had claimed and which the arithmetic then presented as missing.

But the third term is **the same ablation measured on a different binary**. On
`mendlane` (`33a3dac8b`) A+B+C was `+11,529` built / `+8,175` honest; on this arm
it is `+13,341` / `+9,422`. The parser got better at the ablated file while
`63,937` and `49,446` did not move by a byte. Redo the subtraction today and the
residue is **5,069**, not 6,316 - and nothing about the file changed.

A term that moves 1,247 bytes between two arms while the other two terms are
byte-stable is not a part of a partition. It is a measurement of a different
world.

## Two units wearing one word

`8,175` is Δ *honest built* - `built` minus `stretch`, bytes with a token
actually standing on them. `63,937` and `49,446` come from raw `built`. Verilog's
baseline honest built is 26,538 against a `built` of 30,720, so **honest damage
is 68,119, not 63,937**. Subtracting a Δhonest from a raw-`built` damage mixes
two definitions of the same word across a 4,182-byte gap.

Done in one unit throughout - raw `built`, the unit 63,937 is in - the same
three terms give `63,937 − 49,446 − 13,341` = **1,150**, not 6,316. So the
"residue" is 5,166 bytes of unit mismatch plus an arm difference, and none of it
is a fact about the file.

## And the delta is not disjoint from the census

Even granted the units, the subtraction only works if the ablation's gain lands
outside `picorv32` - otherwise it is being taken off bytes 49,446 already counted.
`named.py` says wall A fires in `picorv32`, `picorv32_axi` and `picorv32_wb`, so
the answer is visibly no. In situ, clipped per module:

| module | bytes | built | damage | Δ built under A+B+C |
|---|---|---|---|---|
| **picorv32** | 69,204 | 19,758 | **49,446** | **+2,242** |
| picorv32_regs | 343 | 143 | 200 | +200 |
| picorv32_pcpi_mul | 2,949 | 988 | 1,961 | +1,961 |
| picorv32_pcpi_fast_mul | 2,545 | 1,869 | 676 | +676 |
| picorv32_pcpi_div | 2,404 | 413 | 1,991 | +939 |
| picorv32_axi | 6,223 | 3,374 | 2,849 | +2,849 |
| picorv32_axi_adapter | 1,978 | 896 | 1,082 | +1,082 |
| picorv32_wb | 6,074 | 2,917 | 3,157 | +3,157 |
| between the modules | 2,937 | 362 | 2,575 | +235 |

**2,242 of the 13,341 is inside `picorv32`**, so at least that much of the third
term is bytes the second term already owns. (In honest units, 1,426.) The
clip is in situ - one parse of the whole file - because that is the only reading
in the same world as 63,937; `named.py`'s per-module table parses each module
alone, which is the right instrument for *is this module fixable* and the wrong
one for *how does the whole-file number decompose*.

## The peel figure, and why it was never a candidate

`walls.py run --grammar verilog` on this arm reproduces the reprice lane exactly:

```text
  behind, priced across 40 walls           11,070
  of which `macro_text`                     6,477   <- == the 6,591's own sub-figure
  the whole priced extent               [3,712, 14,782)   INSIDE picorv32
  of those 11,070 bytes, BUILT              6,163
  of those 11,070 bytes, damage             4,907
```

Two independent falsifiers, either one sufficient:

1. **Extent.** The entire priced region is `[3,712, 14,782)`, inside `picorv32`.
   The three `macro_text` walls stand at bytes 3,733 / 3,771 / 6,216. The 6,316
   is what is left over in the **25,453 bytes outside** `picorv32`. Disjoint.
   **P2.2 held.**
2. **Impossibility, which is stronger.** `behind` is a partition of the file by
   *which wall you would have to get past to reach each stretch* - it counts
   built bytes too, and 6,163 of the 11,070 are built. There are only **4,907**
   damage bytes anywhere in that extent, so a 6,477-byte figure **cannot** be a
   subset of damage no matter where you put it. `Depth.behind`'s own docstring
   says it is not damage; this is that sentence with a number on it.

## Who was mixing them, and it was us

The reprice lane closed [RESULT-3](../reprice/RESULT-3-verilog.md) with a
prediction it scored as wrong:

> *"I predicted I would find at least one place already doing it and looked for
> one; every citation of 6,591 keeps it a peel figure. That prediction was wrong
> and the tree was cleaner than I guessed."*

That was true when written. The first citation to mix them is
[RESULT-2](RESULT-2-repricing.md) in **this** dossier, hours later - *"leaving
6,316 - close enough to the parallel lane's finding … that the two should be
reconciled by whoever owns `walls.py`"*. It was hedged and handed off rather
than asserted, which is why it is a hand-off and not a defect in that result. But
the lane that predicted nobody would do this was falsified by the next lane
along, and the record should say so rather than leave the reprice lane's
self-scored miss standing as a miss.

## What the verilog record should say instead

Not "63,937 = 49,446 + 8,175 + 6,316". Three separate sentences, each true:

- **63,937 bytes of damage**, of which **49,446 are inside `picorv32`** and
  **14,491 are in the other seven modules and the gaps between them.** Both are
  `size − built` off one parse and they partition exactly.
- **Neutralising three named constructs would raise `built` by 13,341 and honest
  built by 9,422 on this arm** (11,529 / 8,175 on `mendlane`). That is a
  counterfactual, it is arm-dependent, and **2,242 of it is inside the 49,446**.
- **The peel prices 11,070 bytes behind 40 walls, 6,477 of them `macro_text`, all
  inside `[3,712, 14,782)`, and 6,163 of them are built.** Not damage, not a
  term in anything above.

And the sentence that outlives all of them: on the 30,720 bytes verilog *did*
build, the oracle defends **611**.

## Scoring

| | claim | verdict |
|---|---|---|
| **P2.1** | 49,446 is a census of damage inside `picorv32`; 8,175 is an ablation delta; damage outside `picorv32` is exactly 14,491 and `14,491 − 8,175 = 6,316` | **held, to the byte, on all four.** The residue is unattributed damage in the other seven modules. |
| **P2.2** | the 6,591/6,477 lies inside `picorv32` and the 6,316 outside it, so they are provably different bytes and the proximity is coincidence | **held, and then improved on.** Extent settles it; the built-byte count settles it *without* needing the extent, which is the falsifier I did not predict. |
| **P2.3** | the record is double-counting, but at 8,175-against-49,446 rather than 6,316-against-6,591 | **held** - and the arm-dependence of 8,175 is a second, independent reason the subtraction was never admissible. |

Three for three, which after Job 4's nought-for-two is worth stating plainly:
these three were predictions about **what a number was measured by**, and that is
a question you can answer by reading the instrument. Job 4's were predictions
about **what a population would turn out to be**, and I got those by guessing
from a column name.

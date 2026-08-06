The verilog record quoted three numbers about `picorv32.v` as if they partitioned
one thing — 63,937 `damage`, 8,175 "grammar limitations", 49,446 "four defects in
procedural blocks" — got 6,316 left over, and matched that against a **fourth**
number from a different instrument entirely: the peel's 6,591 `behind` bytes,
since re-priced to 6,477 as `macro_text`. `research/joinery/unjudged/reconcile.py`
prices all four on one arm.

**They are not the same bytes, on two independent grounds.**

```text
behind, priced across 40 walls           11,070
of which `macro_text`                     6,477
the whole priced extent               [3,712, 14,782)   INSIDE picorv32
of those 11,070 bytes, BUILT              6,163
of those 11,070 bytes, damage             4,907
```

The extent settles it — the whole peel-priced region is inside `picorv32`, while
the 6,316 is what is left over in the 25,453 bytes **outside** it. But the byte
counts settle it without needing the extent: `behind` is a partition of the file
by *which wall you would have to get past to reach each stretch*, so it counts
built bytes too, and there are only **4,907 damage bytes anywhere in that
extent**. A 6,477-byte figure cannot be a subset of damage no matter where you
put it. `Depth.behind`'s docstring already said it is not damage; this is that
sentence with a number on it.

**The real double-count is the other pair, and it is a category error rather than
an arithmetic one.**

```text
damage, whole file                        63,937
damage inside picorv32 [1863, 71067)       49,446   <- the census, to the byte
damage outside it                          14,491
ablation delta, honest built               +9,422   <- the "8,175", today
ablation delta, raw built                 +13,341   <- the same ablation in DAMAGE's units
of that raw delta, inside picorv32         +2,242   <- not disjoint from the census
```

49,446 is `size − built` clipped to one module and reproduces exactly, so
`63,937 − 49,446 = 14,491` and `14,491 − 8,175 = 6,316`: **the "residue" was
never a gap in the record, it is unattributed damage in the other seven
modules**, which nobody had claimed and the arithmetic then presented as missing.

The third term is inadmissible three times over. It is a **counterfactual** —
a delta from six ablations of a file that does not exist, so it has no bytes to
be a part of. It is in **different units**: Δ *honest built* against two figures
computed from raw `built`, and verilog's honest built is 26,538 against a `built`
of 30,720, so honest damage is 68,119 rather than 63,937. Done in one unit
throughout the same three terms give `63,937 − 49,446 − 13,341 =` **1,150**. And
it is **not disjoint** from the second term: 2,242 of the raw delta lands inside
`picorv32`, on bytes 49,446 already counted.

**It is not even arm-invariant.** A+B+C was `+11,529` built / `+8,175` honest on
`mendlane` (`33a3dac8b`); on `94d59d9ad` it is `+13,341` / `+9,422`, while 63,937
and 49,446 did not move by a byte. Redo the subtraction today and the residue is
**5,069**. A term that moves 1,247 bytes between two arms while the other two are
byte-stable is not part of a partition of anything.

What the record should say is three separate sentences: 63,937 bytes of damage,
of which 49,446 are inside `picorv32` and 14,491 are in the other seven modules
and the gaps between them, and those two partition exactly. Neutralising three
named constructs would raise `built` by 13,341 on this arm, 2,242 of it inside
the 49,446. The peel prices 11,070 bytes behind 40 walls and 6,163 of them are
built. And on the 30,720 bytes verilog *did* build, the oracle defends 611.

Also recorded, because the tree keeps score of this: the reprice lane closed by
scoring itself wrong for predicting somebody was mixing `damage` with `behind`
— *"every citation of 6,591 keeps it a peel figure"*. That was true when
written. The first citation to mix them is this dossier's own `RESULT-2`, hours
later. Hedged and handed off rather than asserted, but the lane that predicted
nobody would do it was falsified by the next lane along.

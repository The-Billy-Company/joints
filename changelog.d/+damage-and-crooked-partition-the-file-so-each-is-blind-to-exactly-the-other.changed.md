`crooked` is inside `built`. `damage` is `size - built`. They are **complements
over the same file** — every byte in one is outside the other by construction —
so each is blind to exactly the other and neither is the work order.

The exhibit is verilog: `crooked 0` against `damage 63,937`, the largest damaged
row on the board, scored clean by the ranking column. That is not a quirk of
verilog. Ranked by `crooked`, verilog is 29th of 30; ranked by `damage`, php is
4th while carrying 24,539 bytes it built and got **wrong**. On this corpus the
two orders disagree by up to **28 places**, and eight rows cost more wrong than
missing. Ranking a worklist by a column that scores the largest damage row as
clean is how this board has been fooled four times.

The default is now `max(damage, crooked)` with a **`by`** column saying which key
placed each row (`dmg` / `crk`), and the two stay in their own columns —
**neither is added to the other**, because a fused score is the thing that got
us here. `--damage` and `--crooked` still rank by one, and each now names what
it sinks: `--crooked` warns it is blind to the unbuilt bytes exactly as
`--damage` already warned about the misbuilt ones. `widest by DAMAGE` stops
calling itself "the work order" whenever there is an audit live and calls itself
half of one, naming the byte count it cannot see.

With no audit, `crooked` is zero everywhere and `max` degrades to exactly
`--damage`, so an unaudited board opens on the order it always did. `--standing`
keeps the old ratio default, which is blind to file size and is now something
you ask for rather than something you get.

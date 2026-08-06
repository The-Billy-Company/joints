# Prediction 2 — the folio cache, and what the board should rank by

Written before measuring. Scored in [`RESULT-2-cache.md`](RESULT-2-cache.md).

## The cache lie, staged rather than argued

`order.miss` decides a cached folio is usable when
`folio.st_mtime >= BIN.st_mtime`. That answers *was this made before the binary*
and it is asked of a **path**, not of a version. Two pinned binaries sharing one
`OUTLINER_WORK` are **both** older than a folio either of them minted five
minutes ago, so the freshness rule never fires for either and both arms read
whichever folio was written last.

> **Prediction.** Point pin A and pin B at one `OUTLINER_WORK`, let A mint, then
> run B. B reports `cache: kept 30`, reads thirty folios A minted, and the board
> moves on at least one row — while every stamp on the page reads clean.

The error is always in the flattering direction, because two runs of the same
table always agree. A before/after that shares a work directory cannot report a
difference that exists.

I also predict the reverse is *not* true: this is not a folio-format problem,
`accepts()` will happily read A's folio under B, because the format is stable
across these two trees. The refusal path is not what is broken; the freshness
path is.

## What I intend to change

**`order.py` — a folio records the binary that minted it.** Not an mtime, a
digest, in a sidecar beside the folio. `miss` then asks *did this binary mint
this folio* instead of *is this folio younger than this binary*. An mtime cannot
answer the first question and never could.

**`pin.py` — a pin owns its folio cache.** A pin is already a binary plus the
record that makes it a version; the folio cache is derived from that binary and
belongs to it. `pin.py arm <name>` should hand a lane all three exports at once
so that sharing a work directory between two arms is something you have to go
out of your way to do.

**`standing.py` — the audit cache carries the oracle.** See prediction 1.

**`standing.py --twice[=N]`** — the thing a lane can run to know its two numbers
are comparable: survey N times, diff every column, name what moved.

Prediction on the fix: **the sidecar closes the two-pin hazard completely** and
costs nothing measurable, because it is one small write per press and one small
read per row against a board that already spends ~136 ms asking the binary
whether it can read its own folios.

## The other half of the brief: should `--damage` stay the default order?

The owners lane flagged that `crooked` scores verilog at **0** against
`damage 63,937`, while verilog carries 24% of the corpus's walls and 40% of its
stranded bytes. It called `crooked` blind to verilog. It is right, and the
board's own `NOTE` already says the converse about `damage`.

> **Prediction: neither should be the default, and the board should refuse to
> have one.**

Not a hedge — a claim with a shape. `damage = size − built` and
`crooked ⊆ built`. They are **complements over the same file**: every byte in
one is outside the other by construction. So "which is the work order" has no
answer that is not a policy about whether being wrong costs more than failing,
and this board has been fooled four times by a single-key ranking already.

What I expect the measurement to show, and what would kill it:

- **Expect:** ranking by `damage` and by `crooked` disagrees by more than ten
  places on at least one row (verilog, in the direction the owners lane found;
  php in the other).
- **Kills it:** if the two orders substantially agree, then one of them is
  redundant and the board should just keep the survivor.

If they disagree as I expect, the default should be a **two-keyed order** that
sorts on `max(damage, crooked)` and prints which key put each row where. That is
not a fused score — the two numbers stay in their own columns and neither is
added to the other. It is a work list that cannot bury a row for being wrong in
the bucket the sort is blind to, which is the failure mode all four previous
corrections shared.

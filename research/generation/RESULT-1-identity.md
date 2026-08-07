# Result 1 — what identity turned out to have to mean

`python3 research/generation/stage.py mint` — each of the thirty grammars
pressed **six times by the current binary** and once by the older one, into
scratch paths, every result digested and its length recorded.

## Prediction 1 is falsified

> **Prediction:** minting is deterministic - the same binary pressing the same
> `grammar.json` twice produces byte-identical folios.
> *Falsifier:* sha256 of two consecutive `mint` runs over one grammar differ.

It differs for **at least fourteen of thirty**, and the measurement is worse
than that sentence:

```
6 mints of each of 30 grammars, one binary, one machine
reproducible: 16   NOT reproducible: 14
  cpp       3 distinct folios in 6 mints, 3 distinct length(s)
  css       3 distinct folios in 6 mints, 2 distinct length(s)
  elixir    4 distinct folios in 6 mints, 3 distinct length(s)
  go        2 distinct folios in 6 mints, 2 distinct length(s)
  haskell   3 distinct folios in 6 mints, 2 distinct length(s)
  javascript 3 distinct folios in 6 mints, 3 distinct length(s)
  julia     2 distinct folios in 6 mints, 2 distinct length(s)
  latex     4 distinct folios in 6 mints, 3 distinct length(s)
  ocaml     2 distinct folios in 6 mints, 2 distinct length(s)
  python    3 distinct folios in 6 mints, 3 distinct length(s)
  scala     3 distinct folios in 6 mints, 3 distinct length(s)
  sql       3 distinct folios in 6 mints, 3 distinct length(s)
  swift     3 distinct folios in 6 mints, 3 distinct length(s)
  verilog   3 distinct folios in 6 mints, 2 distinct length(s)
```

Three things in there, in rising order of how bad they are.

**The count depends on how hard you look.** Two mints each called nine grammars
unstable; six called fourteen. Two samples can only catch a wobble that happens
to land on different sides, so the first number was an undercount and the second
is a floor, not a total. `stage.py mint` presses six times and says out loud
that six agreeing mints is evidence and not proof.

**The count is not even stable across runs of the measurement.** A second
six-mint pass found thirteen — the same set minus `julia`, which produced one
folio six times running that day and two folios six times running the day the
list above was taken. The union of two runs is fourteen. So "fourteen of thirty"
is what has been observed, not what is true.

**The folios differ in length.** Seven of the fourteen produce three distinct
byte-lengths from six presses of one grammar by one binary. Same-length,
different-byte would be an ordering artefact — a table interned out of a seeded
hash map, ugly but inert. Different lengths is a *different amount of data*
being written for one grammar, which is not an ordering artefact and not
cosmetic, and `stage.py mint` now reports the two separately for that reason.

The older binary (`.local/ink/base/bin/joints`, built out of this same tree at
08:35 today) presses different bytes for 16 of 30, but most of those are
grammars whose press wobbles anyway, so the honest count of what a *different
build* changes is the five over the reproducible set — `bash, c, julia, ruby,
rust`.

### What that costs the design

The prediction file already named the consequence, so it stands as written:

> If minting is **not** deterministic, then every re-mint is a new generation by
> this definition, the reconciliation will be noisy in a tree ten agents
> rebuild, and I will have to say so and price it rather than call the noise a
> finding.

So: **the ledger has a false-alarm floor of fourteen grammars, nearly half the
board.** Any instrument that re-presses `sql` while the board is reading `sql`
splits the board, and nothing was wrong. That is not the ledger being wrong —
those really are two different folios and nobody can tell you they parse the
same — but it is a channel that will fire for a reason the reader cannot act on,
and channels that do that get scrolled past. The `stale` warning in this same
file already had to stop counting `*_test.zig` for exactly that failure mode.

The right response is to fix the press, not to soften the rule, and that is
somebody's real bug rather than a line of mine: a folio that is not a function
of its grammar cannot be content-addressed, cannot be cached across machines,
and makes every "byte-identical" claim about folios unstable — including the
board's own `30 grammars byte-identical, 0 moved`, which is on this project's
list of instruments that lied. `tool/order.py` already round-trips mint→readback
for all thirty; it does not compare two mints, and nothing else in the tree does
either, which is how this survived. The varying *length* rules out the tidy
explanation (hash-map iteration order over a fixed table) and points at
something that writes a different amount per run — a capacity or a spill, not an
ordering.

## Which mechanism the measurement chose

| candidate | verdict |
|---|---|
| mtime | rejected. It already failed twice here, and the stage measured it failing a third way: in the `blind` trial it called **5 of 31** artifacts moved where the content rule called **4**, and in `control` it called **16** where content called **2** |
| schema signet | rejected without measuring. Two generations minted a second apart by two different builds share it, which is exactly the event of 2026-08-05 |
| sha256 of the bytes at read time | taken |

The `republished` field in `stamp.Ledger` exists to keep that first row visible
after the argument for it has been read once: every entry in it is an artifact a
stat would have called a split and the digest called the same file. In the
control trial that is fourteen artifacts.

## Prediction 1's second half held

> **Prediction:** a binary replaced mid-run with unchanged sources produces *no*
> warning from today's stamp.
> *Falsifier:* swap `zig-out/bin/joints` mid-run without touching `src/` and
> see any of TOLD / STALE / DRIFT / MOVED / FED fire.

`stage.py binary` swaps a real older binary over the running one at 0.5s of a
3.8s board, giving the replacement an mtime **older** than the folios so the
cache's freshness rule stays quiet:

```
today's source detectors: nothing  ← none of them re-reads the binary
```

Sixteen of thirty rows had already been measured by the build that is no longer
there, and the board reported 62.1% standing with no mark on it. So yes, the
binary needed its own identity, and that is why `stamp.ask` feeds both the folio
and the binary on every row rather than the folio alone. It is also most of the
cost — see RESULT-3.

The older-mtime detail is the case being tested, not a convenience. A binary
that lands *newer* than the cache is already caught twice over: the freshness
rule re-mints everything, and if the swap falls between a press and its
read-back the previous lane's `Refused` guard stops the run outright (observed,
first attempt at this trial). The gap is the other half — a binary installed
without a fresher mtime, which is every pinned build, every `cp -p`, and every
`JOINTS_BIN` pointed at somebody else's tree.

Haskell's 1,013 bytes were quoted as `unjudged` for a day. **Haskell's `unjudged`
is 0.** No plumb rule fires on any of them; all 1,013 are `unwindowed`, and the
board printed the pair as one number under `unjudged`'s sentence — *"carry no
oracle verdict"* — with the reason column reading *"plumb rule, byte by byte"* on
a row whose plumb count is zero.

`unwindowed` is the `not t_sp[k]` branch of `rack.survey`: *the oracle has nothing
strictly inside this window here and outliner does*. Its docstring is right that
the oracle's silence inside a window is not a verdict. What the column cannot say
is **why** the oracle has nothing inside — and on every one of haskell's 295 runs
the narrowest oracle bracket covering the window is the oracle's own root.
`within` drops a rung that spans the window, correctly, because a forest and a
tree disagree about a root's extent by construction; what is left inside is empty.
So the oracle's structure at those bytes **is** the frame we did not build.

`research/joinery/unjudged/unwindowed.py` measures that rather than asserting it,
and it is not haskell-specific:

| row | `unwindowed` | of those, under a frame we never built |
|---|---|---|
| haskell | 1,013 | **1,013** (100%) |
| verilog | 111 | 110 |
| cpp | 42 | 38 |
| swift | 35 | 35 |
| ocaml | 27 | 27 |
| ruby | 23 | 2 |
| julia | 8 | 8 |
| sql | 3 | 3 |
| bash · kotlin | 1 each | 1 · 0 |
| **corpus** | **1,264** | **1,237 — 97.9%** |

So it is a third mechanism, and not the kind this dossier was collecting. The
other two entries are **reader defects** — our arithmetic against tree-sitter's
renders. This one is a **classification**, and it leans the flattering way:

> Building **more** structure under a frame you are missing moves bytes out of
> `unframed`, which is a charge, and into `unwindowed`, which reads as silence.

Same bytes, same missing frame; the column depends only on whether we put
something of our own underneath. Haskell's own deepest node over those bytes is
`apply` (172 runs), `variable` (107), `case` (12), `negation` (3), `match` (1),
and 221 of the 295 runs sit one level below the frame. In content they are two
things: whitespace runs we hung under a node, and token-interior positions where
we split an identifier tree-sitter keeps whole.

The report now splits them and derives the reason from each row's own numbers
instead of printing a constant:

```text
NOT JUDGED — 5564 of 396158 built bytes (1.40%) got no verdict: 4300 `unjudged`, where the
oracle had nothing to say, and 1264 `unwindowed`, where it framed the window from outside
and we built inside it. Only the first is the oracle's silence about the byte; most of the
second is `unframed`'s own population under another name. ...
  verilog   4293  14.0% of 30720  unjudged 4182  unwindowed 111   plumb rule, byte by byte
  haskell   1013  11.0% of 9192   unjudged 0     unwindowed 1013  no oracle refusal at all
                                                                  — every byte is unwindowed
```

**No judged column moved.** Charging these bytes `unframed` would be the stricter
and probably the correct rule, and it is a one-line change — test `missing[p]` in
the `not t_sp[k]` branch as the two branches around it already do. It is
deliberately not made here: it moves `unframed` on ten rows while three lanes are
holding baselines against this board, and a re-price is not one lane's to spend
on another's behalf without saying so first. The finding is written down, the
report no longer misreads it, and the change belongs to whoever wants to re-pin
for it.

# Prediction 1 — what happens to the board when `built` stops meaning `right`

Written before any corpus-wide sweep of this lane. What I have read first:
`tool/standing.py` (the board), `tool/rack.py` and `tool/plumb.py` (the two
oracle comparisons), `research/collate/` (the scoreboard against tree-sitter),
and one `rack run go javascript` on two small grammars — 17 crooked bytes on
go's specimen, 0 on javascript. Nothing corpus-sized has been measured.

The brief hands me three numbers off rack: **60,138 defended crooked bytes,
15.63% of `built`, 39,110 of them right-leaf-wrong-parent**, and one off the
board: **69.09% standing**. Everything below is what I expect when the second
number is recomputed with the first subtracted out of it.

## What the split is

`built` becomes five, and they have to total it:

    square     both spines identical                      proven right
    renamed    identical once the grammar's own ALIAS applies   proven right
    hard       crooked, minus extras placement            proven WRONG
    soft       crooked, and it is where a comment hangs   not defended
    unjudged   the oracle had no verdict here             not proven either way

So the honest headline is a **range**, not a number: a floor of
`(square + renamed) / size` and a ceiling of everything not proven wrong. The
old `standing` is that ceiling with `soft` and `unjudged` folded in too — it is
`built / size`, and `built` is the whole of the first four columns plus the
fifth.

## P1 — the floor falls by more than 8 points from 69.09%

`crooked` is 15.63% of `built` and `built` is 69.09% of the corpus, so the
arithmetic alone is 10.8 points before `unjudged` takes any more. Defended-only
is 60,138 rather than 83,169, so call it ~7.9 points from `hard` and the rest
from `unjudged`.

**Falsifier:** a corrected floor above 61.1%. That would mean either `unjudged`
is near zero corpus-wide (it is not — sql and verilog alone are ~34,687 bytes
the oracle will not adjudicate) or rack's 15.63% does not survive being asked
per row and re-totalled.

## P2 — at least six of the twelve grammars the board reads at 100.0% lose bytes

`rack.py whole` exists precisely because a grammar at 100.0% standing has no
column that can ever redden, and the go exhibit (`fmt.Print("x")` as a cast, at
100.0% standing and zero mends) is one of them. I have not run `whole`.

**Falsifier:** five or fewer of the twelve carry a crooked byte. That would make
"the board scores wrong structure as success" a claim about broken grammars
rather than about the metric, and would considerably weaken the whole rung.

## P3 — at least one grammar's `crooked` exceeds its `damage`

`damage` is `size - built`, the bytes the tree failed to place. `crooked` is
bytes it placed wrongly. I predict at least one row where being confidently
wrong costs more than visibly failing — php is my candidate (87.2% standing,
25,338 bytes plumb calls misread), and any of the twelve whole grammars is a
free second candidate since their `damage` is zero by construction.

**Falsifier:** every row has `crooked <= damage`. Then the existing work order
already ranks the real defects and the split only rescales it.

## P4 — the work order reorders by three places or more for at least three rows

The board's work order is `--damage`. Adding proven-wrong bytes to it should
move rows, and the ones it should move are the ones that parse cleanly and
wrongly.

**Falsifier:** every grammar sits within two places of where `--damage` puts it.
Then the split is a headline correction and not a work order correction, which
is a smaller claim than I am making.

## P5 — the four-bucket identity survives, and the split totals `built` on every row

`size = built + orphan + rubble + spoil` must not move by one byte, and
`square + renamed + hard + soft + unjudged` must equal `built` per row. This is
arithmetic and I expect it to hold; it is written down because it is the
assertion that catches me having recomputed `built` instead of splitting it.

**Falsifier:** any row where the five do not total, or any corpus total that
differs from today's board.

## P6 — the soft share lands within five points of rack's 27.7%

`soft` is computed here from `standing.extras()` (all declared extras, by node
name) where `rack.soft` uses SYMBOL extras only. A `PATTERN` extra's value is a
regex and can never be a node name, so the two sets should differ by inert
members and the totals should agree.

**Falsifier:** a soft share outside 22.7–32.7%. That would mean the two extras
readings are not equivalent and my `hard` is not rack's defended number.

## What I most expect to be wrong about

P2. It is the one where I am reasoning from a single exhibit that was chosen
*because* it was surprising, and the twelve are the grammars that work. If ten
of twelve come back clean, the honest statement is that the board's blind spot
is real, small, and concentrated — not that every green row is a lie.

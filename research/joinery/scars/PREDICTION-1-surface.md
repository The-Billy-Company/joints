# Prediction 1 — the shape of the surface, and what it must not disturb

Written after reading `src/kernel/quire/`, `src/kernel/weave/`, `tool/walls.py`,
`tool/stamp.py` and the `../reprice/` dossier, and **before building anything**.
No parse has been run for this lane yet. Everything below is falsifiable against
the tree.

## What I found in the runtime, and why it decides the shape

`gather.mended()` is the only place a mend happens, and it is reached from
exactly two callers in the round-1 loop: a lexer wall (`stray` bytes nobody can
tokenise) and a parser wall (a token no live root can shift). It resolves both
the same way — **it deletes**. It skips forward to the next token that some root
can act on, and under the default policy it fells the stack and restarts at
state 0. It never inserts the token the grammar was waiting for.

That single fact settles most of the API argument:

- **A mend is not a node.** It has no production, no children, and no place in
  any parent's kid list. It spans bytes that were *removed from consideration* —
  the tree's own claim about them is that nothing covers them. Putting a node
  there would mean inventing a parent for text the parser explicitly refused,
  and would move `built` on every board that counts bytes under nodes.
- **A mend is not an annotation on a node either.** There is no node to annotate.
  The nearest node is whatever got built *before* the refusal and whatever got
  built *after* the restart, and those are two different subtrees that a mend
  sits between. An annotation would have to pick one and lie about the other.
- **A mend is a seam between two spans of tree.** So it is a side channel:
  a sorted, disjoint list, parallel to the node array, indexed by nothing.

I am calling one record a **scar**. Not `Mend` (taken: the policy enum
`none/keep/fell/relent`), not `Seam` (taken: `weave` uses `.seam` for an unspun
edit boundary), not `Error` (it is not one — the parse succeeded, that is the
point).

**P1 — the side channel disturbs no byte on the board.** `built`, `covered`,
`damage` and `square` are byte-identical for all 30 rows between my arm and the
isolation arm. Falsifier: any row moves. If a row moves I have put a mend in the
tree by accident and the design argument above is wrong in implementation.

## What a consumer needs at a scar, and what I will actually record

Six fields, each because a named caller cannot work without it:

| field | why it is not optional |
|---|---|
| `at` | the byte the parser refused at — the peel's entire join key |
| `over` | the byte it resumed at; `over - at` is the cost in bytes |
| `why` | refused-by-lexer vs refused-by-parser; the two have different owners |
| `felled` | did the stack reset, or did the surrounding structure survive? This *is* "how confident is the structure around it" |
| `roots` | how many live parses stood at the break — a 308-root break is a different animal from a 1-root break |
| `tokens` | tokens shifted since the previous scar; zero means this scar is the previous one re-reported against the next token, which is exactly the cascade `../reprice/` caught the warm peel doing |

`tokens` is the field I expect to earn its keep. The re-price needed a whole
second parse with a byte blanked to decide whether a wall was real or a cascade
of the one before it. If `tokens` is honest, the same question is answered from
**one** parse without touching the file.

**P2 — one mending parse subsumes the warm peel.** For each of the four
budget-bound grammars (haskell, sql, swift, verilog), a single
`--mend=keep --scars` parse enumerates **at least as many distinct refusal bytes
as the warm peel's whole 400-round seat**, in **under 1%** of its wall clock.
Falsifier: fewer bytes, or not at least 100x faster. I expect this to hold
because warm's 400 rounds are 400 process spawns and 400 whole-file parses,
against my one.

**P3 — `tokens == 0` finds the cascade.** Swift's probe in
`../reprice/PREDICTION-2-alias.md` showed `)` 1492 and `}` 1498 are the same
refusal re-reported. Under `--mend=keep`, I predict the scar list for
`Chunked.swift` shows a first scar at 1492 and a **run of scars with
`tokens == 0`** immediately after it. Falsifier: every swift scar shifts at
least one token, in which case `tokens` is measuring something other than what
I think and the cascade needs the two-parse probe after all.

## Cost

**P4 — free on a clean parse, under 3% on the worst.** Zero mends means zero
appends, so a grammar that parses clean cannot pay. Haskell mends the most; I
predict the whole-corpus `standing.py --twice=3` wall clock moves by **under
3%**, and that no single grammar moves more than 10%. Falsifier: any grammar
over 10%, which would mean the append is in a hot loop I did not find.

## What I am not predicting

Whether `felled` is the right confidence signal for an editor. It is the right
one for *this* runtime because it is what the policy actually does, but a
consumer wanting "is this subtree trustworthy" wants a per-node answer, and a
per-node answer needs a node-to-scar join this lane is not building. I expect
that to be the next lane's finding, and I would rather ship the honest seam list
than a per-node confidence number I cannot derive.

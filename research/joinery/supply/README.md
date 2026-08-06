# supply — the second move

`../scars/` made repairs visible and found that all of ours are the same one.
**Every mend this runtime performed was a deletion**: drop the token, or put the
stack down and stand it up in state zero. Tree-sitter also *inserts* — it
materialises the terminal the grammar wanted, zero-width, and calls it
`MISSING` — and it does so 70 times across the same corpus. The dossier priced
our half of the vocabulary at **1,929 scars over twelve grammars tree-sitter
derives clean**: c, cpp, ruby, bash, haskell, julia, kotlin, markdown, ocaml,
scala, swift, zig. Defects with no grammar-gap excuse available.

This directory is the lane that added the move.

| file | what it is |
|---|---|
| `PREDICTION-1-insert.md` | the rule, written before an arm was pinned, with five falsifiers |
| `RESULT-1-insert.md` | the per-grammar scoreboard, the residue, and the two predictions that failed |
| `residue.py` | every refusal the arm meets, partitioned by *why* the second move did or did not fire |
| `reach.py` | the localization lead, control against arm — and `--spans`, the join key for a scar-aware `square` column |

## The one-line answer

Under `--mend=keep` the corpus gains **+2,592 `square`** and sheds **5,308
`crooked`** on **2,540 fewer built bytes** (tree `83cf2f249d8b`, both arms in one
sweep). Under `--mend=fell`, the default, `square` does not move at all and
`crooked` rises 798. The twelve this lane was aimed at are **24.8%** of the
movement and net **+642**; verilog, which is not on the list because tree-sitter
fails on it too, is +1,669 by itself.

**Two of the twelve lose.** c gives back 396 `square` and cpp 134, for exactly
the case the rejected fourth clause was aimed at — a *unique* candidate that is
nonetheless the wrong one. That charge was measured, then published as dead
after a sibling's press change stopped both grammars refusing at all, then came
back on the re-pin. It is live and it is 45% of what swift gains.

## The two things worth reading the dossier for

**A supply is a node *and* a scar, and those are different claims.** A deletion
must not be a node — it would invent a parent for text the parse explicitly
refused. An insertion is the opposite: the parse is asserting structure, so the
assertion belongs in the tree or the tree is not the derivation performed. It is
zero-width, which is what keeps `built` honest. It is *also* a scar, under a
`gave` field naming the terminal, because a zero-width anonymous node is
indistinguishable by inspection from one a grammar legitimately produces, and
"which tokens are here only because the parser said so" is a provenance question
about the parse rather than a structural fact about the file.

**Repairs are not independently scorable.** The rule nearly carried a fourth
clause requiring the supply to *close* something already standing rather than
open something new — which would have prevented c's 396-point regression
exactly. With that clause the corpus gains **+0** and the parse supplies ten
terminals; without it, +3,124 on the tree the pair was measured on. Half the
clause is worse than either whole. What a supply is worth here is not whether its
node is right but whether the parse stays synchronised, and a parse that
resynchronises at some walls and not others follows a worse trajectory than one
that never tries — so the fix for c and cpp is a *tie-break*, not a gate.

## Running it

```sh
eval "$(python3 tool/pin.py arm <name>)"
python3 research/joinery/supply/residue.py --mend keep
PYTHONPATH=research/joinery/supply python3 research/joinery/supply/reach.py \
    --mend keep --spans .local/supply/spans-keep.json
```

Both take `--mend {keep,fell,relent}` and say which they read, because the
answer is different in each and the number the dossier quotes is `fell`'s.
`residue.py --all` widens past the twelve. The control arm is the same binary
with `--no-supply`, which is a stronger control than two pins: the tree drift
the house rules guard against is structurally unavailable when both halves are
one executable.

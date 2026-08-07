Every repair this runtime performed was a deletion. Tree-sitter has two moves and
70 `MISSING` nodes across the same corpus; we had none, which
`research/joinery/scars/` priced at **1,929 scars over twelve grammars
tree-sitter derives clean** - our defects, with no grammar-gap excuse.

There is now a second move. At a refusal the parse may **supply** a terminal the
file does not contain and re-read the same token, under a rule the parse tables
justify rather than a heuristic:

1. the terminal is **anonymous** - a literal the grammar spells itself, so "a
   `}` is missing" is a complete statement. A zero-width instance of a *named*
   terminal is a token no lexer could produce, and swift's `_implicit_semi` and
   haskell's layout hand are the scanner's to make, not recovery's to invent;
2. shifting it makes **the token the file actually holds** shiftable - not "it
   is legal here". That is the justification and the termination proof at once:
   a supply is always immediately followed by a real shift, so the offset
   advances and no byte is supplied into twice;
3. **exactly one** such terminal exists. Two is the table declining to say
   which, and that is counted as `spurned` rather than resolved.

Plus a guard on the empty stack: an omission is only a thing relative to
something the author began, and a prefix that makes a refused token legal on the
ground manufactures a construct rather than completing one. **No constant is
introduced** - the virtual walk reuses `climb` and `chase`, the two bounds
`shiftable` was already spending on every token of every parse.

A supply is **both** a zero-width node and a scar, and those are two different
claims. A deletion must not be a node - it would invent a parent for text the
parse refused. An insertion is the opposite: the parse is claiming structure, so
the claim belongs in the tree or the tree is not the derivation performed. It is
also a scar, under a new `gave` field naming the terminal, because a zero-width
anonymous node is indistinguishable by inspection from one a grammar
legitimately produces, and "which tokens are here only because the parser said
so" is provenance, not shape. `mends` and `skipped` deliberately do not count
supplies - a supply resynchronises nothing and skips no bytes.

```text
--mend=keep, 30 grammars, tree 83cf2f249d8b, oracle supply-lane, one binary two flags
  square   323,871 -> 326,463   +2,592     the twelve  115,007 -> 115,649  +642
  crooked                       -5,308     verilog +1,669  swift +1,172  sql +281
  built                         -2,540     c -396  cpp -134
--mend=fell (the default)
  square   311,540 -> 311,540       +0     the twelve      +0
  crooked                          +798
```

**Two predictions failed.** Five grammars move in the whole corpus, three up and
two down, and **both losers are on the target list** - which is the worst place
for them. Of the twelve this was aimed at, one gains, nine do not move, and two
lose; under the default policy not one of them moves at all. The twelve are
**24.8%** of the corpus movement. Verilog, which is not on the list because
tree-sitter fails on it too, is +1,669 by itself.

The c and cpp charge was **published as dead once and it is not.** An early
measurement had c at -396 `square` and cpp at -134; a sibling's `src/press/`
change then stopped both grammars refusing under `keep` at all, and with no
refusal there is no supply and no charge, so the record was corrected to say the
case was unobserved. A re-pin on `83cf2f249d8b` with both arms in one run puts
both back exactly where they were. Calling a regression dead off one sweep,
against a tree ten agents are editing, is the same error as pinning a number -
and it fell the flattering way twice.

**verilog is the finding.** Under `keep` it is +1,669 `square`, -1,669 `crooked`,
+0 `built` - a pure reclassification, every byte already built, now under the
right parent. Under `fell` the same rule on the same grammar gives +0 `square`,
+713 `crooked`, +284 `built`: new structure, all of it wrong, and it is the whole
of the corpus `fell` regression. Same supplies, one policy apart. It was **not**
gated to `keep`; a policy-conditioned boolean is a single-knob-tuned constant with
a nicer name, and one sweep is not enough to hard-code a mode into a recovery
rule. `--no-supply` is the control.

**The localization lead widens rather than merely holding.** verilog's scars
covered 52% of its file under `keep` and now cover **23%**, against tree-sitter's
100% over the same bytes. Corpus-wide the bytes handed back as untrustworthy fall
23.8% to 14.2%.

**It is also the wrong thing to judge on, and the same sweep proves it.** c's
scar reach falls 34 B to 4 B and cpp's 18 B to 0 B - the two tightest rows in the
table - and those are the two grammars that *lose* `square`. A tighter repair
surface is the parse repairing less and claiming more, and what it claims can be
wrong. Read the reach table without `square` beside it and this lane's two
regressions score as its two best rows.

**The clause that was argued for, measured, and removed.** The rule nearly carried
a fourth demand - that folds run on both legs of the walk, the table's way of
saying the supply *closes* something already standing rather than opening
something new. It would have prevented c's regression exactly. With it, corpus
`square` moves **+0** and the parse supplies ten terminals; without it, +3,124 -
one sweep on the tree of the day, and the clause has not been re-measured since.
Half the clause is worse than either whole. What a supply is worth here is not
whether its node is right but whether the parse stays synchronised, and a parse
that resynchronises at some walls and not others follows a worse trajectory than
one that never tries. Repairs are not independently scorable, so a rule admitting
a subset has to earn it by measurement.

The clause is the wrong instrument, but the defect it was aimed at is real and
priced: **a unique candidate that is nonetheless the wrong one costs 530 `square`
across c and cpp**, which is why the twelve net +642 rather than swift's +1,172.
Closing that wants a *ranking* rule - prefer a closer over an opener when both
are unique - and it is the same brief as the 54 `spurned`, from the other side.

`Gather.init` leaves the move **off** and `joints parse` turns it on. The
incremental path replays a trail whose alignment marks are one per `read`; a
supply keeps that index 1:1, but the mark it adds points at a byte where re-lexing
yields the real token and not the ghost, and no test in this tree has ever offered
a graft a zero-width token to land on. The argument for the second move is a
`square` measurement over whole files and it says nothing about resume, so `weave`
keeps exactly the behaviour it had until that has evidence of its own.

Per-grammar tables, the residue, and the scored predictions in
`research/joinery/supply/RESULT-1-insert.md`.

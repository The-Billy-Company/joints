# Prediction 2 - re-deriving the 611, and four loose ends

Written before anything in `RESULT-3` .. `RESULT-6` was run. One honesty note
first, because it is the kind of thing this dossier exists to catch:

> **P3.1 was measured before it was written.** I established that the press
> change which killed elixir's `engulf` tripwire is uncommitted while still
> reading the tree, before this file existed. It is recorded below so the claim
> has a stated shape, but it is scored **no credit** - it is a measurement
> wearing a prediction's clothes, which is exactly the construction the previous
> lane retired five instruments for.

Everything else here is genuinely ahead of its measurement.

## Job 1 - get verilog's `square` by a route that is not `indents()`

**P1.1 - `square` is a function of the oracle's *bracket multiset*, not of its
topology, so most of `indents()` cannot reach it.** `cover()` picks the rungs
covering a byte by **extent** (`r.end > p`, `r.start <= p`) out of a flat pile,
and `inorder()` sorts that pile by `(start, -end, depth)`. Parentage appears
nowhere in either. `indents()` decides parentage and nothing else - the name,
the `named` flag and both offsets of every row come from the row's own text and
range prefix. So I predict the only two channels by which a wrong `indents()`
could move `square` are:

1. the `depth` **tie-break** in `inorder`, which only bites between two rungs
   that share an extent exactly; and
2. `Node.leaf` (`not node.kids`), which enters the `unjudged` rule as
   `not them.leaf and t_bad[p]`.

Falsifier: permute the oracle tree's parentage while holding its bracket
multiset fixed and re-measure. If `square` moves by more than those two channels
can account for, this is wrong.

**P1.2 - `tree-sitter parse --dot` is an independent route and it will agree.**
The graphviz source the CLI pipes into `dot` carries a `label` per node, a
`range: a - b` in **bytes** in the tooltip, and explicit `parent -> child`
edges. Nesting from edges is not nesting from columns, so reading it involves no
indentation arithmetic at all. I predict the visible-node projection of that
graph is identical to the CST tree `indents()` builds for verilog **node for
node**, and that `square` recomputed from it is **exactly 611**.

**P1.3 - the DOT graph is a superset and the reconciliation will need more than
one rule.** It prints hidden rules and supertypes the CST never shows
(javascript's `statement` and `declaration` sit in it at `state: 65535`). I
predict the first filter - hidden = leading `_`, or listed in `grammar.json`'s
`supertypes`, or `inline` - is necessary and **not sufficient**, and that I will
need at least one further rule before the two trees line up. My guess at the
extra rule is `MISSING`/`ERROR` spelling, or aliases.

**P1.4 - the named half was never at risk.** `reconciled` asserts
`same(full.named_only(), theirs)` against the XML, and `same()` is total: name,
`named`, both offsets, arity, recursively. So on any grammar that gets a verdict
at all, `indents()` has **zero** freedom over where a *named* node attaches. I
predict the residual freedom is exactly anonymous-node attachment, and that on
verilog the number of anonymous nodes whose parent the DOT graph and the CST
disagree about is **0**.

**P1.5 - hardening: generated error cases, and the pre-fix reader will not break
on all of them.** A generator that perturbs each corpus file at many offsets
will produce error-bearing oracle trees on **at least 20 of the 30** grammars. I
predict the shipped reader survives all of them (`same()` holds), the pre-fix
reader breaks on a **minority** - I will say **20-60%** - and not on all of
them, because the extra space only misreads a tree when a *clean* node sits
inside an error subtree **and** a bulleted sibling follows it at the parent's
level. A generator that broke every case would be a generator I had tuned.

## Job 2 - two numbers that are probably not the same bytes

**P2.1 - the sum is a category error and the 6,316 is its artifact.** I predict
49,446 is a **census of damage bytes inside one module** (`picorv32`) and 8,175
is an **ablation delta** - a counterfactual gain in `built` from removing two
constructs. Adding a census to a delta and subtracting from `damage` is not a
partition. Concretely I predict damage outside `picorv32` is
`63,937 - 49,446 = 14,491`, and that `14,491 - 8,175 = 6,316` exactly, which
makes the "residue" *unattributed damage in the other seven modules* rather than
anything missing from the record.

**P2.2 - the 6,591 is somewhere else in the file, and that is checkable.** It is
a `behind` figure from the peel over a different run, already re-priced to 6,477
under the name `macro_text`. I predict its bytes lie **inside** `picorv32`'s
extent, and the 6,316 lies **outside** it, so the two are provably different
bytes and the numerical proximity is a coincidence. Falsifier: the byte offsets
of the `macro_text` walls against the module extents.

**P2.3 - the record IS double-counting, but not where the hand-off guessed.**
Not 6,316-against-6,591. It is that 8,175 and 49,446 are quoted side by side as
if they partitioned 63,937, and one of them is a counterfactual.

## Job 3 - the falsifier whose precondition vanished

**P3.1 (no credit - measured first).** The change is **in flight**, not
committed, and elixir's baseline has already moved more than once today.

**P3.2 - what the tripwire was guarding, and where to re-point it.** The
assertion `fat.engulf > fat.unframed * 0.9` exists so that `engulf` can be seen
to tell **one file-wide frame** apart from **N missing constructs** - haskell
supplies the "N constructs" pole immediately above it. I predict php still
supplies the other pole (its corpus file is one `declaration_list` over 67,146
of 67,845 bytes), and - the part that matters - that php's precondition can be
**asserted from the two trees** rather than assumed, so that the next time a
press change dissolves it the tripwire fails loudly instead of going vacuous.

**P3.3 - and I predict the same latent vacuity is not unique to this row.** I
predict at least one other assertion in `rack verify` is guarded by an
unasserted precondition of the same shape (a corpus row's current parse), and
that naming them is worth more than fixing the one.

## Job 4 - haskell's 1,013

**P4.1 - it is the ERROR-taint arm, and it is not a third mechanism.** `plumb`'s
rule has three arms: no oracle node over the byte, a non-leaf deepest node under
an `ERROR`, or a deepest node that *is* an `ERROR`/`MISSING`. I predict **at
least 90%** of haskell's 1,013 bytes come from the taint arms rather than from
`them is None`, which means tree-sitter's own tree over haskell's corpus file
has an `ERROR` in it. That is the same rule that produces the 137 bytes on cpp ·
ocaml · swift · ruby · julia · bash · kotlin, at a larger size - so I predict
the honest answer is **"the oracle cannot parse its own corpus file here"**, and
that it does **not** belong in the dossier as a third mechanism beside the two
reader defects.

**P4.2 - and it will not be one wide node.** I predict the 1,013 bytes are a
small number of runs rather than scattered singletons - fewer than 20 maximal
runs - because an `ERROR` taints a contiguous span.

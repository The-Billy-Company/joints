# The `keep`/`fell` split is a publishing rule, not a supply rule

`../supply/RESULT-1-insert.md` landed the second move and reported a result that
split by mend policy on the same rule and the same grammar: a **pure
reclassification** under `--mend=keep` (+1,669 square, +1,669 crooked shed, **+0
built**) and **284 bytes of new wrong structure** under `--mend=fell`, the
default. Verilog was the entire corpus `fell` regression, so every board taken
at the default carried it.

One rule cannot have two behaviours. This lane found where the two policies
part, and it is four lines of `unwind`.

## The mechanism

**A supply is a hypothesis with a one-token warrant.** Clause 2 is the
termination proof - "a supply is always immediately followed by a real shift" -
and that is exactly how much it establishes. What happens *after* that shift is
the parse's answer about whether the omission was real:

- a fold takes the ghost as a child → the answer arrived, the construct closed
- a second refusal arrives first → the answer never arrived

Under `keep` the chain is never put down, so a ghost stays live until something
folds over it. Under `fell` the second refusal calls `unwind`, which carries the
standing chain into `roots` - **ghost included**.

The defect has a shape you can count: **a zero-width node at depth 0.** A node
covering no bytes, standing under no parent. `plant`'s own anchor rule says the
supply offset "is the only offset at which a zero-width child is inside its
parent", so a supply that ends up a *root* completed nothing and asserts a
terminal at a position where the file holds no bytes.

| `--mend=fell` | zero-width **roots** | zero-width **inside a parent** |
|---|---|---|
| control (`--no-supply`) | 0 | 0 |
| verilog | **11** | 22 |
| haskell | **115** | 140 |
| julia | **1** | 1 |

Under `--mend=keep`, verilog's 59 supplies produce **59 ghosts, every one of
them inside a parent, and zero roots.** That is the pure reclassification, and
it is the same rule.

Seen directly in the forest, verilog at 14709 - two roots the control never
built, a parentless ghost and the construct it opened:

    NEW    14709..14709      0B  [
    NEW    14709..14758     49B  constant_expression

## Whose defect the +713 is

**A `fell` defect the supply revealed.** Not a supply defect, and `keep` is not
hiding one:

- the identical rule, on the identical grammar, produces 59 correctly-parented
  ghosts under `keep` and *buys* 1,669 square with them. A wrong supply would
  land inside a *wrong* parent and cost square; it gains it.
- the arm with no second move builds no zero-width node anywhere on the corpus,
  so nothing here is a pre-existing shape being blamed on recovery.
- what differs is not which sites are supplied but what is done with the result:
  `fell` converts a provisional node into published structure **at the exact
  moment the parse produces the evidence it was wrong**, because that evidence
  *is* the next refusal.

## Two hypotheses this lane held and killed

Both are recorded because a lane that only reports its surviving hypothesis is
reporting a preference.

**Recovery-founded stacks.** The `ground` guard refuses at depth 0 on the
reasoning that "an omission is only a thing relative to something the author
began" - and depth is a proxy for authorship that `fell` invalidates, since a
mend stands a fresh perch up in state zero and depth is 1 again after one shift.
`founded.py` measured it off the scar stream's own `+N tokens`:

| `--mend=` | supplies | on ground | ≤ 8 tokens since the last fell | median |
|---|---|---|---|---|
| `fell` | 163 | **0** | 139 (85%) | haskell **1**, verilog 13 |
| `keep` | 66 | 0 | **0** | verilog **4,302** |

The contrast is real - under `keep` a supply is asked about the derivation the
file built, under `fell` about a stump a mend erected - **but it does not repair
into anything.** After `bare()` the mend's perch *is* index 0, so "depth from
the segment floor" and "depth from the ground" are the same number, and the only
way to strengthen the guard is a depth threshold, which is a new constant of
exactly the kind this repo is auditing. The hypothesis explains haskell (median
1) and fails on verilog (median 13), which is the row carrying the number.

**Clause 3's untellable rivals.** The residue-closure lane found clause 3's
predicate is "exactly one *said yes*", not "exactly one exists": a rival whose
walk gave up is untellable, and 1,468 refusals under `fell` are in that
position. A supply resting on that basis could plausibly be right often enough
to look harmless under `keep` and wrong under `fell`. `untellable.py` joins the
runtime's own `unsure` line to the supply that follows it - the join is the
immediately preceding line, which is exact, because verilog emits **1,139
`unsure` lines against 34 supplies** and a carried flag would attribute one
refusal's rival to another's supply.

| `--mend=fell` | supplies | with an untellable rival |
|---|---|---|
| confirmed (ghost inside a parent) | 152 | **0** — 0% |
| unproven (ghost parentless) | 12 | **0** — 0% |

**The two populations are disjoint.** Every `unsure` line on this corpus sits at
a refusal that supplied nothing, which is where you would expect a walk to give
up. So clause 3 does not hold *by construction* and holds *everywhere it is
currently exercised* - two different statements, both worth having - and it
explains none of the split.

## The repair

`unwind` stops publishing `own` runs at the first unconfirmed supply on the
chain. `lead` runs still go out at every perch: a perch's leading extras are
comments the file really holds, and they belong to the forest whatever the parse
decided about the structure over them.

Reading a ghost back off a perch is exact rather than a guess, and **clause 1 is
why**: a supply is always anonymous, and the terminals that are legitimately
zero-width - swift's `_implicit_semi`, haskell's layout hand - are named and the
scanner's to produce. So a zero-width perch holding an anonymous node is one
this runtime wrote in, and one still standing is one nothing reduced over.

| `--mend=fell`, arm vs control | before | after |
|---|---|---|
| corpus `crooked` | **+688** | **+112** |
| verilog `crooked` | +713 | +137 |
| verilog `built` | +284 | **−369** |
| corpus `unbuilt` | +255 | **−348** |
| **`--mend=keep` corpus `square`** | **+3,124** | **+3,124** |

`keep`'s headline does not move. That is what makes this a repair rather than a
policy boolean wearing a different hat - it fires only where a supply was left
unconfirmed, and under `keep` that essentially never happens.

## The default should stay `fell`

Priced across all thirty rows, every policy against the default, on one arm
(`board.py --price`). `unbuilt` is `crooked + unframed`, because a policy that
trades a frame it never built for one it built wrong has moved a byte between
two columns and repaired nothing:

| against `--mend=fell` | `square` | `crooked` | `unbuilt` |
|---|---|---|---|
| `keep` | +8,573 | **+81,639** | +44,128 |
| `keep`, verilog excluded | +7,546 | **+26,347** | −7,152 |
| `relent` | +4,933 | **+30,251** | +5,601 |
| `none` | −65,672 | −24,528 | −58,490 |

**Do not change the default.** The supply's `+3,124 square` under `keep` is a
delta *within* `keep`; the *level* of `keep` is 81,639 crooked worse than
`fell`, on 52,977 more built bytes. This is precisely the trap `rack.py guard`
exists to catch - a policy that buys `square` and pays `built`. The conclusion
survives deleting verilog entirely (+26,347 crooked for +7,546 square), so it is
not one row's story.

The honest qualifier: minus verilog, `keep`'s **`unbuilt` is 7,152 better**,
almost all of it haskell. `keep` trades frames it never built for frames it
builds wrong. `crooked` is the column every figure quoted off this instrument
means, and on it `keep` is far worse - but a reader who cares about "did we
build the frame at all" should know the sign flips.

## `spurned`: still decline, and now for a stated reason

The arm implementing clause 3 returned the instant it found a second candidate,
so it never reached the `unsure` line and a decline carried no untellable count.
The loop runs to the end now; **no decision moves** (two candidates declined
before and decline now, `give` is still the first yes), and the population is
visible for the first time:

- **71 spurned refusals** under `fell`, and **40 of them have more than two
  candidates**. `spurned` is "two or more", and the majority are more.
- **3 carry an untellable rival**, so even the decline rests on a set the walk
  did not establish.

**Continue declining.** Not for want of trying to rank - because the measurement
says a rank would be worse than the bucket is worth:

1. **It is not a tie-break.** 40 of 71 need a choice among three-plus. Every
   principled rank available here - prefer the closer, prefer the one that
   closes rather than opens - is a two-way comparison generalised by fiat.
2. **The one structural rank with a warrant was measured and removed.** The
   authoring lane's fourth clause (close rather than open) is exactly the
   candidate a ranking rule would reach for first, and it cost the entire
   +3,124. Its conclusion holds here: what a supply is worth is not whether its
   node is right but whether the parse stays synchronised - and *that* is not a
   property of the candidate, so no ordering over candidates can express it.
3. **The bucket is 71 refusals and the failure is asymmetric.** A wrong
   delimiter builds a real subtree over bytes the author grouped differently -
   the same defect this lane just spent its whole warrant removing 127 instances
   of. Declining costs a scar; choosing wrong costs a tree.

The `rivals:` line is what makes this reversible: when some grammar shows a
spurned population that is mostly genuine two-way ties, the count will say so.

## What I trust least

**verilog's `--mend=keep` row.** It moved by roughly 13,000 bytes between the
two pins this lane used (`unproven`, tree `ace700af2993` → `felled`, tree
`b78d53779933`) on a change that is not this one - siblings were landing in
`src/press/` and rebuilding grammars throughout, and the sweeps printed
`waiting on verilog: another lane is building it`. The `fell` numbers are stable
across both trees (+95/+120 → +112/+137) and are this lane's claim. The `keep`
verilog figure is recorded and **not** attributed.

Second, **haskell's ghost counts do not reconcile**: 128 supplies produce 255
zero-width nodes, so the per-anchor join double-counts and haskell's
confirmed/unproven split in `untellable.py` is unreliable. verilog's is exact
(33 supplies = 22 + 11). Haskell's board row does not move before or after the
repair, so nothing here rests on it - but the instrument is wrong there and
should be fixed by identity rather than by offset before anyone reads it.

## Running it

```sh
eval "$(python3 tool/pin.py arm <name>)"     # check it says 30 of 30 verdicts
python3 research/joinery/felled/board.py --mend fell --mend keep
python3 research/joinery/felled/board.py --price
python3 research/joinery/felled/founded.py --mend fell
python3 research/joinery/felled/untellable.py --mend fell
```

Both arms are one executable a single `--no-supply` flag apart, so the tree
drift the house rules guard against is structurally unavailable between them.
Every render stamps the tree it was read on.

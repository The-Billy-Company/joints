# Result 1 — the second move

The runtime inserts now. Two predictions failed, one of them the headline, and
the regression I twice talked myself out of is real. All of it goes first.

## The number I got wrong twice, in the flattering direction both times

**Read this before the tables. It is the only part of the document that was
published wrong.**

My first complete measurement had **c losing 396 `square` and cpp losing 134**
under `--mend=keep`, and I wrote both into a runtime comment as the price this
rule pays. Then they vanished: a sibling lane landed a `src/press/` change
partway through my sweeps, after which **c and cpp stopped refusing under `keep`
at all** — no refusal, no supply, no charge. I removed the charge from the
record and wrote that the case the fourth clause was aimed at was "unobserved
rather than disproven".

**It is observed again.** A re-pin on tree `83cf2f249d8b`, both arms in one run,
puts c back at **−396** and cpp at **−134**. Whatever made them stop refusing
stopped being true. I do not know which commit did either, and I am not going to
guess: the finding is that I called the same charge dead once, on one sweep, and
it outlived the call.

The consequences for the headline are not small. **The twelve gain +642, not
+1,174** — swift's +1,172 less c and cpp's −530 — and the **corpus gains +2,592,
not +3,124**. Every table below is re-derived from the re-pin.

What caught the first version was `rack` recording the tree it read: a
`--mend=fell` pair came back **`3c8d995c5be2` against `e6d3fe044216`**, a
cross-tree comparison the board would have refused at exit 4 had I asked it to
diff them. What caught the second was not vigilance at all — it was re-running
the sweep for an unrelated reason. **The house rule that saved this twice is
"pin the control after the arm"; the rule it is still missing is "a null result
against sibling churn expires".**

## The predictions, scored

**P1 failed.** I predicted the rule would fire on 15–45% of the 1,929. It fires
on **130 of 1,914** under `fell` — **6.8%**. That clears the 5% floor I set for
"ornamental", but only just. Under `keep` on the same twelve it fires **4**
times against 17,506 refusals, which is *inside* my own ornamental falsifier and
would be the whole story if the twelve were the corpus. They are not: verilog
takes 59, and it is not one of the twelve because tree-sitter fails on it too.

**P2 failed on breadth and failed on safety.** I predicted at least six of the
twelve would gain and that no grammar anywhere would lose more than 200 B.
**One** of the twelve gains — swift, +1,172. Nine do not move. **Two lose**, and
one of them loses 396, which is twice my own falsifier. Under `--mend=fell`, the
default and the mode the 1,929 was counted in, **not one of the twelve moves at
all**.

**P3 held, by more than predicted.** verilog's scars covered 52% of its file
under `keep`; they now cover **23%**. The second move does not cost the
localization lead, it widens it. Tree-sitter's `ERROR` nodes cover 100% of the
same bytes. Corpus-wide, bytes handed back as untrustworthy fall from **23.8%
to 14.2%**. One grammar's reach widens rather than tightening — swift, 490 B to
514 B — and it is the one of the twelve that gains the most `square`, so the
sprawl is buying something.

**And P3 holding is worth less than it looks, which is the sharpest thing in
this document.** c's scar reach falls from 34 B to **4 B** and cpp's from 18 B
to **0 B** — on the same tree, in the same sweep, where they lose 396 and 134
`square`. The two grammars whose repair surface improves the most are the two
whose *agreement* gets worse. A tighter scar surface is the parse repairing less
and therefore claiming more, and what it claims can be wrong. **Localization is
not a proxy for correctness and this pair proves it**; anyone reading the reach
table without the `square` column beside it would score this lane's two
regressions as its two best rows.

**P4 held.** Corpus `built` moves **+0.09%** under `fell` and **−0.55%** under
`keep`. The sign under `keep` is worth saying out loud — the arm builds *less*
and agrees *more*, which is the opposite of the failure mode the brief warned
about. A parse limping on through nonsense would show the reverse.

**P5 held, and the correction made it hold by more.** The twelve are **24.8%**
of the corpus `square` movement (+642 of +2,592) against a predicted bound of
40%. It read 37.6% before the re-pin. I recorded this prediction because its
flattering direction is the opposite of the brief's framing, and the correction
moved it the *unflattering* way for the lane and the *passing* way for the
prediction — which is worth naming, because a prediction that gets easier to
pass as the result gets worse is a badly written prediction.

## The scoreboard

Same binary both arms, one flag apart (`--no-supply`), same frozen oracle
`supply-lane` (tree-sitter 0.26.11), same folio cache, each pair run back to
back with the tree checked after. Control and arm cannot differ by more than
the flag here, because they are the same executable behind two shims — the
drift the house rule guards against is structurally unavailable, which is a
stronger control than two pins.

### `--mend=keep` · tree `83cf2f249d8b`

Every row in both tables is from the same four-arm sweep: one binary, one pin
(`fourth`), one tree, `cut` and `arm` back to back per policy.

| grammar | square ctl | square arm | Δ`square` | Δ`built` | Δ`crooked` |
|---|---:|---:|---:|---:|---:|
| verilog | 8,087 | 9,756 | **+1,669** | +0 | −1,669 |
| swift *(of the twelve)* | 11,174 | 12,346 | **+1,172** | −2,204 | −3,377 |
| sql | 3,437 | 3,718 | **+281** | +0 | −273 |
| cpp *(of the twelve)* | 319 | 185 | **−134** | +2 | +64 |
| c *(of the twelve)* | 1,163 | 767 | **−396** | −338 | −53 |
| **the twelve** | 115,007 | 115,649 | **+642** | −2,540 | −3,366 |
| **corpus (30)** | 323,871 | 326,463 | **+2,592** | −2,540 | **−5,308** |

Five grammars move in the whole corpus; three up, two down. Twenty-five are
untouched, and nine of the twelve are among them. **Both losers are on the
target list**, which is the worst place for them to be: the rule was aimed at
the twelve and its only two regressions are inside them.

### `--mend=fell`, the default · tree `83cf2f249d8b`

| | square ctl | square arm | Δ`square` | Δ`built` | Δ`crooked` |
|---|---:|---:|---:|---:|---:|
| the twelve | 109,227 | 109,227 | **+0** | +84 | +85 |
| corpus (30) | 311,540 | 311,540 | **+0** | +368 | **+798** |

**Under the default policy the second move buys no agreement and costs a
little**, and verilog is +284 built / +713 crooked of it by itself. 130 supplies
fired on the twelve; not one changed a leaf's parent.

## The same grammar, opposite signs, one policy apart

verilog is the exhibit and the finding. Under `keep`: **+1,669 `square`,
−1,669 `crooked`, +0 `built`** — a pure reclassification, every byte already
built, now under the right parent. Under `fell`, the same rule on the same
grammar: **+0 `square`, +713 `crooked`, +284 `built`** — new structure, all of
it wrong. It is the whole of the corpus `fell` regression.

That is a controlled comparison of the mechanism rather than a story about it:
same supplies, same tables, one policy apart. `fell` answers a refusal by
disowning the stack; a supply is the opposite claim, that the stack is right and
one token is missing from it. Run both and the parse completes a construct and
then throws it away at the next wall, leaving the node the supply built standing
over bytes nothing afterwards confirmed.

**I did not gate the supply to `keep`.** A policy-conditioned boolean is a
single-knob-tuned constant with a nicer name, and this repository is auditing
those right now because two were found wired in series. The structural argument
above is a hypothesis the verilog pair corroborates; it is not a proof, and one
sweep is not enough to hard-code a mode into a recovery rule. The `fell`
behaviour is reported as a negative and left as a brief. `--no-supply` is the
control and it stays.

## Where the movement is, and the part no instrument watched

`../scars/` bounded the blind spot: **27.9% of `built` is downstream of a
repair** and `square`'s exposure is **19.9–23.0%**, with no column anywhere
separating agreement standing on repaired ground from agreement that is not.
This lane moved `square` by +2,592 under `keep`, and **some unknown part of that
is inside exactly that region.** I cannot say how much.

What I can say is which way the un-instrumented part leans, and it is not the
flattering way. All three movers are among the four grammars with the heaviest
repair, so the repaired region is *over*-represented in the movement. A
scar-aware column would most likely show a larger share than 23% of the gain
standing on repaired ground.

`tool/rack.py` belongs to another lane, so the capability is handed over rather
than built into their board. `reach.py --spans` writes every repair site of a
run as `{at, over, gave, felled, why}` keyed by grammar — **34,419** sites under
`keep`, **4,196** under `fell`. Joining a per-leaf `square` attribution against
those spans is a column rack can add without re-deriving a parse.

## Which of the 1,929 an insertion could never have fixed

`residue.py` partitions every refusal the arm meets, off two channels that are
cross-checked on every row: a `quire` trace saying why `supply` declined, and
the scar channel saying what the parse actually did. Supplies announced must
equal supplies printed, and deletions must equal strays plus traced declines.
The `adrift` column is that check, and it read **0** on all twenty-four rows
when this table was taken. **That reading turned out to be worthless and the
table no longer reproduces — read the two subsections after it before quoting
any number in it.**

`--mend=fell`, the twelve, 1,936 refusals, tree `e6d3fe044216`:

| | count | whose brief |
|---|---:|---|
| **supplied** | 130 | closed |
| **none** | 1,288 | no anonymous literal resumes the parse |
| **stray** | 444 | no terminal was refused at all |
| **spurned** | 54 | several literals resume it; the table declines to say which |
| **ground** | 20 | the stack is empty, so nothing was begun and nothing omitted |

**1,806 of 1,936 are out of this rule's reach, and they are four different
briefs, not one:**

- **`stray` (444) is out of reach of *any* insertion rule.** The lexer could not
  make a token out of the byte, so there is no refused terminal for a supply to
  make readable — `supply` is never even asked. markdown's entire repair
  population is this, 79 of 79, and half of ocaml's. A lexer brief.
- **`none` (1,288) is the largest and is mostly one cause.** Almost all of it is
  haskell, whose refusals are `_cond_qual_dot` and its neighbours — terminals
  the grammar hands to an external scanner we cannot run. No anonymous literal
  exists to stand for them, and clause 1 refuses to invent a zero-width instance
  of a named pattern. The verdict line already prints this ("blind to 34
  externally scanned terminals"). An external-scanner brief.
- **`spurned` (54, and 55 under `keep`) is the only part that is arguably this
  lane's unfinished business**, and closing it is a **ranking** rule rather than
  a richer vocabulary. Two literals each resume the parse and the table declines
  to choose; so did I.
- **`ground` (20) is a deliberate refusal.** An empty stack has begun nothing,
  so a prefix that makes the refused token legal manufactures a construct rather
  than completing one. Without the guard the two moves eat each other: `fell`
  stands the parse up in state zero, and the very next thing the ground refuses
  invites a supply that re-opens what the fell just closed.

`fuse` and `unseated` read 0 everywhere. Both are real paths; neither was
reached on this corpus.

### That table no longer reproduces, and the check that used to clear it is why

**Re-run on tree `83cf2f249d8b`, `residue.py` exits 1 on ten of the twelve
grammars.** `none` reads **0** where it read 1,288, and `adrift` — the
cross-channel closure column — reads **+1,337**. Every event that used to be
bucketed as "no anonymous literal resumes the parse" now produces **no trace
line at all**, so the scar channel counts a deletion the trace cannot explain.
The two accounts of the same parse disagree about 1,337 repairs.

I have not chased where they go. `supply` has exactly one untraced early return
(`!x.supplying or x.mend == .none`), and neither holds here — 135 supplies fired
in the same run — so the refusals are not reaching `supply` at all, which puts
the change upstream in `absorb`/`blame` rather than in this rule. That is
plausibly a sibling's in-flight work in the same files, and diagnosing it on a
tree ten agents are editing is a fresh lane's job, not a footnote on this one.

**The honest status of the residue table above is: measured, published, and
currently unreproducible.** It is the shape of the answer — the residue really
is four different briefs and not one — but the counts are an older tree's, and
`none` in particular is the bucket that has gone to zero, which is the bucket I
had already named as the one I trusted least. It went wrong in a way I did not
predict: not "`none` is silently absorbing walk failures", but "`none` stopped
being written and nobody upstream noticed".

## The shape argument: tree, channel, or both

**Both, and they are not the same claim.**

A deletion must not be a node. It is the parse *refusing text*, so a node over
those bytes invents a parent for text the parser explicitly declined, and moves
`built` on every board counting bytes under nodes. That is `../scars/`'s
argument and it holds.

An insertion is the opposite. The parse is *claiming structure* — asserting the
author finished a construct and omitted its terminator — and that claim belongs
in the tree or the tree is not the derivation the parse performed. So a supply
gets a real node, at the anonymous terminal's own name, and **zero-width**.
Zero-width is what keeps `built` honest: it covers no bytes, so nothing the
author did not write ends up under structure because of it. P4's −0.53% is that
holding.

It is *also* a scar, under a new `gave: ?g.Symbol` field naming the terminal,
because the tree cannot answer the question a consumer actually asks. A
zero-width anonymous node is indistinguishable by inspection from one a
*grammar* legitimately produces, and "which tokens are here only because the
parser said so" is a provenance question about the parse rather than a
structural fact about the file. Tree-sitter answers it by rendering `MISSING:`
in one CLI view, which puts provenance in a print format; putting it in the
channel that already enumerates repairs means one sorted list answers both
halves — which bytes nobody derived, and which tokens nobody wrote.

The two spellings differ on the printout on purpose. A deletion says how many
bytes it walked past and what it did with the stack; a supply walked past none
and did neither, so it reads `scar 24594 gave ";"` rather than three fields of
nothing.

`mends` and `skipped` deliberately do **not** count supplies. Folding them in
would move a number every board here already reads for a repair that is not what
that number means — a supply resynchronises nothing and skips no bytes.
`supplied` and `spurned` are their own counters on the verdict line.

## The rule

At a refusal, supply terminal `m` and re-read the same token when, and only
when:

1. `m` is **anonymous** — a literal the grammar spells itself, so "a `}` is
   missing" is a complete statement. A zero-width instance of a *named* terminal
   is a token no lexer could produce, and supplying one asserts text is missing
   while declining to say which text. The layout terminals that legitimately are
   zero-width (swift's `_implicit_semi`, haskell's layout hand) are named, and
   they belong to the scanner.
2. Shifting `m` makes **the token the file actually holds** shiftable — not "`m`
   is legal here". This is the justification and the termination proof at once:
   a supply is always immediately followed by a real shift, so the offset
   advances and no byte can be supplied into twice.
3. **Exactly one** such `m` exists, across the standing stack. Two is the table
   declining to say which, and choosing there is worse than not choosing.

Plus the ground guard. **No constant is introduced**: the walk reuses `climb`
and `chase`, the two bounds `shiftable` was already spending on every token of
every parse. The capacity lane auditing constants gains nothing new to audit.

The rule is asked of `x.spent` — the perch the table's own reading died on,
after the folds this token forced — because that is the configuration the
refusal genuinely stands in and the one `mended`'s `keep` would re-seat on.

### The clause I argued for, measured, and removed

The rule nearly carried a fourth demand: that folds run on **both** legs of the
walk, which is the table's way of saying the supply *closes* something already
standing rather than opening something new. It is the clause that would have
prevented c's regression exactly — c paid its 396 for supplying a `{` in front
of a file's last `}`, building a compound statement neither byte is inside.

The corpus refuted it. With the clause, corpus `square` moves **+0** and the
parse supplies ten terminals. Without it, +3,124. Requiring the fold on the
first leg only is worse than either whole, costing 4,995 `square`, because
verilog's 48,339 deletions become 15,953 when every supply lands and stay 48,339
when only some do.

Those three readings are **one sweep on the tree of the day** and the clause has
not been re-measured since; the +3,124 is the figure the re-pin later restated
as +2,592. The gap between the three is far larger than the drift between those
two, so the conclusion survives — but it is a conclusion drawn on an older tree
and it is owed a re-measurement before anyone leans harder on it than this.

That last number is the finding. What a supply is worth on this corpus is not
whether its node is right — it is whether the parse stays **synchronised**, and
a parse that resynchronises at some walls and not others follows a worse
trajectory than one that never tries. **Repairs are not independently
scorable**, so a rule admitting a subset has to earn that subset by measurement
rather than by argument.

**And the case it was aimed at is live**, not hypothetical: the re-pin puts c
back at −396 and cpp at −134. That is 530 of swift's 1,172, and it is why the
twelve net +642 rather than +1,172. The clause is still the wrong instrument —
it buys the two grammars back by refusing nearly every supply everywhere — but
"a unique candidate that is nonetheless the wrong one" is now a measured defect
with a price on it rather than a thing I argued might happen.

### Where the second move is off, and why that is scoping and not gating

`Gather.init` leaves `supplying` **false**; `outliner parse` turns it on. The
one caller measured is the CLI, and it is also the only one that reads a file
once. The **incremental** path does not: an amend replays a recorded trail whose
alignment marks are one per `read`, indexed by token count and offered to a
later parse as "resume here, in this state". A supply scribes a `read` that
keeps that index 1:1 — which is the whole reason `plant` lays its own leaf
rather than reusing `perch` — but the mark it adds points at a byte where
re-lexing yields the *real* token and not the ghost, and no test in this tree
has ever offered a graft a zero-width token to land on.

The argument for the second move is a measurement of `square` against a
tree-sitter oracle over whole files. That measurement says nothing whatever
about resume. Turning it on for `weave` wants its own evidence.

## What it looks like when it fires

sql, missing a `)` before a statement terminator — three of them in one file,
and the grammar names the omission rather than the parser guessing at it:

```text
supplied: ) at 2963 so state 743 can read ;
scar 2963 gave ) unexpected ; in state 743, 1 heads, +13 tokens
```

**It does not close an unterminated file**, and that is a boundary rather than a
bug in the rule. `supply` is reached from `absorb`'s refusal; a file that simply
ends mid-construct stops as `truncated`, which is not a refusal and has no
refused token for clause 2 to be asked about. Tree-sitter's `MISSING` does cover
that case. Closing it means asking the same question of the *end column* instead
of a token, which is a second rule with its own justification and its own
evidence — not a widening of this one.

## What the next lane inherits

1. **A ranking rule, and it is now the biggest single item.** Two sides of one
   problem: the 54 `spurned` are *two* candidates and no way to choose, and
   c/cpp are a *unique* candidate that is nonetheless the wrong one. The second
   side is priced at **530 `square`** — 45% of everything swift gains — and is
   reproducible on `83cf2f249d8b`. The shape that would fix both is a
   preference for a supply that *closes* a standing construct over one that
   opens a new one; the fourth clause tried to express that as a hard demand and
   cost the whole result. As a *tie-break* rather than a gate it is unmeasured.
2. **Why `fell` gets nothing.** +368 `built`, +798 `crooked`, +0 `square` on the
   default policy, +284/+713 of it verilog. Either a supply should stand down
   when the stack is about to be disowned, or `fell` should stop disowning
   stacks a supply just completed. The second is the more interesting question.
3. **`residue.py` does not close on this tree — exit 1, ten of twelve grammars,
   1,337 repairs the two channels disagree about.** The refusals that used to
   trace as `none` now trace as nothing, and `supply` is not being reached for
   them, so the change is upstream in `absorb`/`blame`. Whoever picks this up
   gets a working falsifier and a real failure to point it at.
4. **Supply under `weave`.** The trail interaction above, with a test that
   offers a graft a zero-width token.
5. **A scar-aware `square` column.** The join key exists (`reach.py --spans`);
   the board is rack's.
6. **The external-scanner residue.** Not an insertion problem — but its size is
   currently unknown, because item 3 is the bucket that used to hold it.
7. **The truncated file.** Tree-sitter's `MISSING` closes one; this rule cannot
   be asked, because there is no refused token at the end column.

## The instrument I trust least

**`residue.py`'s reason census — and this section is now a postmortem, because
it broke in the interval between me naming it and me re-running it.**

I named the `none` bucket for a structural reason and I stand by the reason:
`none` is whatever is left after four positive tests fail, so every way
`follows` can be wrong lands in it. `Ahead.take` returns `.unsure` for a full
`climb` overlay, a spent `chase` budget, and a declared fork alike, and `follows`
maps `.unsure` to false by design, so a budget exhaustion is
**indistinguishable from an honest miss**. A partition check verifies the
partition is complete, not that any bucket is correctly named. All of that is
still true.

**What I got wrong is the sentence after it: "it passes its own check."** Two
things have since happened to that claim, and both are worse than the hazard I
was worried about.

**First, the check was vacuous when I cited it.** `adrift` was computed as
`cut + gave − sum(seen.values())` — and `seen` is the counter every trace line
is put into, so that expression is identically zero whether the channels agree
or not. It read 0 on all twenty-four rows because it could only ever read 0. The
column lived inside the failing branch of a test that could therefore never
report its own failure. It has since been rewritten as a signed quantity with a
three-case self-test that *shows it failing* (`residue.py --selftest`), which is
the shape it should always have had: a check that only passes is not one.

**Second, with the check repaired, the census fails.** `residue.py --mend=fell`
on tree `83cf2f249d8b` exits **1** on ten of twelve grammars with **+1,337**
unaccounted repairs, and `none` — the bucket in question — reads **0**. So the
number I published as this lane's largest residue no longer exists on this tree,
and I would not have known, because the thing I offered as evidence of the
census's soundness was incapable of saying otherwise.

The generalisable lesson is not "check your arithmetic". It is that **I gave a
falsifier as my reason for trusting a number without ever having seen it fail.**
`rack`'s tree stamp caught the c/cpp error twice precisely because it *had* been
seen to fire. A green check whose red state nobody has observed is a claim about
the check's author, not about the thing checked — and naming the bucket as
least-trusted while quoting a vacuous check as its clearance is exactly the
flattering shape this project keeps finding.

# toml — the row that scored 100% while not handing back a tree

toml read **100% standing, zero damage** on every board this project has ever
printed, and it was not a tree. `pair [27, 45)` held `comment [47, 56)`: a child
with no byte in common with its parent.

Three tools had said so. `Quire.survey` said it on every parse, into a verdict
line nothing read as a failure. A census kept a second copy of the walk and said
it there. `standing.py` printed a `sound` line under the board. Nothing failed,
so nothing changed, and the row kept its perfect score for as long as anyone had
looked.

This dossier holds three findings. The third is the one that outlives toml.

---

## 1. The disjoint child — a span computed from the recipe, children taken from the parse

### What the bytes actually say

`upstream/sources/Cargo.toml`:

| bytes | text | node |
|---|---|---|
| `[27, 45)` | `version = "15.2.0"` | `pair` |
| `[45, 47)` | `  ` | — |
| `[47, 56)` | `#:version` | `comment`, a child of that `pair` |

Reduced to the smallest thing that reproduces it (`b = "2"  # c` on its own
line): outliner mints `pair [8, 15)` holding `comment [17, 20)`. Tree-sitter, on
the same bytes and the same pinned grammar, mints `pair 1:0 - 1:12` = `[8, 20)`.

**The two trees have identical children.** Only the parent's extent differs. We
adopt the trailing comment exactly where tree-sitter adopts it, and then decline
to cover it.

### Root cause

`Gather.reduce` (`src/kernel/quire/gather.zig`) computes a node's span and
assembles its children in two separate passes that never meet.

The span pass walks `p.rhs` against the perches the reduction popped. It has to
skip a perch that consumed nothing, and the reason is sound: a nullable child's
perch carries a bare offset sitting *ahead* of the preceding whitespace, which
is a position rather than a span, and letting one set an edge drags thirty
grammars' nodes back over their own leading trivia. That refusal is correct and
is the same rule the [stretch adjudication](../stretch/) found tree-sitter
spelling in `ts_subtree_summarize_children`.

The child pass is where extras arrive. Rule 2 — "the extras between this symbol
and the next belong to this node" — reads them out of the *next* perch's `lead`
and carries them into `x.born`. For toml's `pair -> _inline_pair
_line_ending_or_eof`, `_line_ending_or_eof` is a zero-width external token that
owns nothing, so the span pass skips it, while the comment sitting in its lead
rides into the child list. `end` stays at the string's 15. The comment lands at
17.

So the defect is not extras *placement* — the comment is under the right parent.
It is that **a node's extent was derived from the production's symbols while its
children were derived from the parse**, and nothing reconciled the two. Any
grammar whose last right-hand-side symbol is nullable and can be preceded by an
extra has the same hole; toml is simply the one in the corpus that exercises it.

### The repair

One pass, after the children exist, widening the span to cover the children the
node actually holds — over minted **nodes**, never over perches, which is the
whole difference from the rule the first pass had to refuse. A node's job is to
cover what hangs beneath it.

Measured as two arms of the same source tree, differing only in this hunk,
sharing one oracle seat (`pin.py arm tomllane`, 30 of 30 verdicts):

| | before | after | Δ |
|---|---|---|---|
| `square` | 313,440 | 313,469 | **+29** |
| `crooked` | 52,359 | 52,343 | **−16** |
| `soft` (extras placement) | 8,634 | 8,621 | **−13** |
| `unaudited` | 4,784 | 4,784 | 0 |
| `built` | 401,787 | 401,787 | 0 |
| `sound` | 1 of 30 UNSOUND | 30 of 30 hand back a tree | — |
| toml `trued` | 99% | 100% | — |

No other row moves. The feared regression — the comment in `reduce` records that
keying the span on `owns` cost 3,561 `square` — does not occur, because widening
over a child node's real span is a different rule from widening to a nullable
perch's offset.

Landed. `zig build test` green; the arm is pinned as `tomlfix`.

---

## 2. `Quire.survey`'s advisory mode — the CLI was right, the callers were missing

The obvious diagnosis is wrong. This was not wired advisory during bring-up and
forgotten. `parse.zig` refuses to move the exit code **deliberately**, and says
why: the family is published three values wide (0 accepted, 1 stopped early, 2
nothing could be read or pressed), and an unsound tree is none of them. toml
accepts, reads whole, and hands back a forest with one child outside its parent.
Overloading `2` would make every reader report "toml cannot be pressed", which
is false — and false in exactly the flattering-instrument shape the check exists
to end.

That argument holds. The defect is one level up: **the fact reached every
instrument and no instrument treated it as a failure.** `Quire.survey` had
exactly three callers — `Quire.verify` (reached only by the amend fuzz),
`census_test.zig` (prints into a census line), and `parse.zig` (prints into a
verdict line). Not one of them could say no about the corpus.

So the promotion is of the **reader**, not the exit code: `tool/sound.py`, wired
into CI as a hard gate. It asks the roster — so a grammar added tomorrow is asked
tomorrow — reads the answer through `stamp.ask` (the single place an instrument
reads outliner's stderr, so the gate and the board cannot drift into two
regexes), refuses to pass vacuously when nothing could be asked, and reports
skips as skips rather than as clearances. Ten seconds over thirty grammars, and
no oracle: it asks the tree about itself.

### The triaged red list

Run against the tree as it stood before the repair, all thirty asked, none
skipped:

```
sound: 1 of 30 asked grammars hand back a forest that is NOT a tree:
  toml: 1 loose, 0 disorder, 0 torn [child outside its parent: comment [47, 56) in pair [27, 45)]
```

**One row. toml, and only toml.** Every other grammar in the corpus was already
sound. With the repair landed the gate reads 30 of 30 and exits 0.

### It went quiet because the tree changed

The gate file is byte-identical across both runs; only the parser binary differs,
and it says no on one and yes on the other. That proves the check looked *this
time*. It does not stop it rotting quiet later — delete the `survey` call and
thirty rows read sound.

So the durable guard is `src/kernel/quire/survey_test.zig`: hand-built arenas
that make `survey` say no on demand, covering all four violation classes plus
the two legal shapes a naive containment check would wrongly flag (a zero-length
child at its parent's edge, an empty forest). Verified by planting a wrong
expectation and watching the suite fail on it by name. These trees are not a
grammar, so no repair to the corpus can dissolve them — which is the failure mode
that cost two lanes their falsifiers this week.

---

## 3. The generalisation — the hole is definitional, and it reaches every row

**Yes. `standing` and `damage` can read perfect on an unsound tree in general,
and it is not a bug in either — it is what they are.**

Not an argument from toml. From the arithmetic:

- `built` is the union of the spans of **top-level roots that have a child**.
  `standing = built / size`; `damage = size - built`, which is `1 - standing` in
  bytes and redefines nothing.
- `standing.py`'s `tops()` keeps column-zero rows and **discards every indented
  row before `built` is computed**. Every node below the root frontier is thrown
  away unread.

So both headline metrics are functions of the root frontier alone. On any file
one root covers whole, `built` **is** the file size, `standing` is 100% and
`damage` is 0 — no matter what the tree underneath looks like. A child outside
its parent contributes its bytes to `built` exactly as a well-placed one does.
So does a child out of source order. So does a node reached twice, which prints
as two nodes and is counted once. So does an entire subtree hung under the wrong
parent.

toml is the witness, not the case. Any grammar can carry any interior structural
defect at 100% standing and zero damage, and 76.3% of this corpus's bytes sit in
rows those two columns are the headline for.

Two instruments can see inside:

| | sees | costs | reaches |
|---|---|---|---|
| `crooked` (`standing.py --audit`) | derivation disagreement with tree-sitter | an oracle seat per arm; minutes | 29 of 30 rows, 4,784 bytes unaudited |
| `Quire.survey` (`tool/sound.py`) | the tree contradicting itself | ~10s, no oracle | every grammar that parses at all |

They answer different questions and neither subsumes the other — `crooked` finds
a well-formed tree that is *wrong*, `survey` finds a tree that is not a tree.
toml showed up in both (16 crooked bytes; 1 loose), which is why one row was
enough to find the hole and not enough to size it.

**The tripwire is `tool/sound.py`**, corpus-shaped by construction: it iterates
the roster rather than naming toml, and it is oracle-free, so it is the one
structural gate that still runs when a grammar library will not build.

---

## Complaint 2 — withdrawn, and independently corroborated here

The 1,552 "source-text stretch" bytes were adjudicated away by the
[stretch lane](../stretch/) before this dossier closed. This lane had reached the
same place from the other side and the number is recorded because it agrees.

`.local/tomllane/owed.py` asked the oracle which of our unleaved bytes tree-sitter
stands a leaf on. toml's 1,972 unleaved bytes — 1,552 of them genuinely
non-whitespace, so the arithmetic reproduced exactly — are **0 bytes owed**.
tree-sitter's own CST puts `string [4, 13)` over two quote leaves and nothing on
the body between them. Corpus-wide over the 18 rows whose oracle seat would build:
77,018 unleaved bytes, **110 owed** (julia 41, swift 63, kotlin 6).

One trap worth recording: read through `tree-sitter parse -x` instead of `--cst`,
the same script reports **1,422 owed for toml**. The XML writes an anonymous node
as bare text with no range, so a `string` whose only children are two quote
tokens reads there as childless — and a childless node is a leaf, silently
painting its whole span as leafed. An oracle comparison is only as good as which
of the oracle's renders you read.

---

## What I trust least

**That `sound.py` stays honest once every grammar is green.** Its counterexample
was toml and toml is fixed, so from here it is a gate with nothing live to prove
it still works. `survey_test.zig` is the answer and I believe it, but it tests
the walk, not the wiring: if `parse.zig` stopped calling `survey`, or the
`UNSOUND:` clause were reworded out from under `stamp.ask`, the unit tests stay
green and thirty rows read sound. The clean fix is a positive signal — the parse
saying it surveyed rather than only saying when it disliked what it found — and
that is a CLI contract change I did not make.

Second: the corroborating `owed` sweep skipped 12 of 30 rows whose oracle seat
would not build under contention. The 110 is a floor over 18 rows, not a corpus
total, and the stretch lane's `warp` arithmetic is the number to quote.

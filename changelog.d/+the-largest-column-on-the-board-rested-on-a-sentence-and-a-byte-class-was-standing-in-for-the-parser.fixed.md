`stretch` and `airy` arrived yesterday carrying 79,628 bytes between them - 63%
larger than `damage` itself, the largest number on the board - and both rested on
one sentence the lane that shipped them chose: *a leaf is a token, so whitespace
between two tokens is under no leaf and is not a defect.* Its own closing words
were **"nothing in the repository adjudicates the sentence,"** and it was right:
none of its 28 tripwires asserted anything about either column. The two prices it
left standing were **77,000 bytes apart** in the corpus headline, and three lanes
were already optimising verilog against one of them.

**Tree-sitter adjudicates it, and it makes the same claim.** A parent takes its
first child's padding and adds every later child's `padding + size` to its own
`size` (`ts_subtree_summarize_children`, `subtree.c:374-379`); each later child's
node is minted *after* the position advances past that padding
(`ts_node_child_iterator_next`, `node.c:93-102`); a node ends at `start + size`
(`node.c:449-451`). So on tree-sitter's own tree the space between two tokens is
inside every ancestor's byte range and inside **no leaf**. On
`research/joinery/corpus/ledger.go` the gap `[784, 786)` between `}` and `var`
sits inside `source_file`, `method_declaration`, `block` and `statement_list`, and
inside nothing else. Outliner's `quire.Node` says the same thing in its own
words - *a node spans from its first token to its last, so the extras between
them are inside it and the ones around it are not* - and `Gather.reduce`
implements it by refusing to let a child that consumed nothing set the start.
Two independently written parsers, one rule, the same stated reason.

**So the sentence survives and the column resting on it does not.** `airy` asks
whether a byte is a **space**; the sentence asks whether a **token** stands on it.
`survey` now asks the second parser instead of the byte, and splits `stretch`
three ways, exhaustively on every row (`stretch == warp + slack + veiled`,
asserted for all 29): **`warp`** a token the oracle built and we did not,
**`slack`** bare on both trees, **`veiled`** the oracle declining - `plumb`'s own
blind rule, not a fourth one. Beside them, **`padding`**: the same `built` scope's
bytes that tree-sitter's own tree leaves under no leaf of *its* own.

The oracle has the same hole and it is not close: **79,913 against our 79,992**,
and on **24 of 29 rows the two counts are byte-for-byte identical** - the same
number, not the same magnitude - including html 25,241, php 12,229, elixir 6,690
and ocaml 5,387. Corpus-wide **99.80%** of our bare bytes are bare on both trees.
`sql` is the row where the oracle leaves *more* bare than we do (934 against 850),
so `padding` is not a ceiling and nobody should read it as one.

What is left is **163 bytes**, over five rows, and by the oracle's own name for
them they are real: swift `..<` 54 and `...` 9, bash `variable_name` 51, julia
`"""` 36 and `"` 5, kotlin `is` 6, and one byte each of ruby `heredoc_content`
and bash `string_content`. So the adjudicated reconciliation is
**`owed = damage + warp`**: every term is a byte some parser put a token over and
we did not.
**Corpus 125,011 → 125,174, +0.13%.** The 77,000-byte swing closes at 163.

**The byte class was wrong in both directions and mostly in the charging one.**
Of the 163 we owe, **161 are non-whitespace**, so `airy` was already charging
them - its over-excusing costs exactly **2 bytes**. Against that, **2,324** bytes
are non-whitespace, bare on our tree, and bare on tree-sitter's too, and `text`
charges every one: toml 1,552, rust 269, scala 171, markdown 142. rust is the
clean illustration - `damage` **0** on the board, and `text` prices it **269**,
a file nothing is wrong with billed by a rule that mistook "not a space" for "a
token should be here". And the widest of them, toml's 1,552, is the previous
lane's own headline: the bytes it named the corpus's largest "source-text
stretch" and kept charging are bare on tree-sitter's tree too.
`text` is kept and relabelled rather than deleted, because
a lane holds a baseline in it and a baseline nobody can re-derive is a number
rather than a measurement.

**verilog gets nothing from either price.** Its entire 4,644-byte `stretch` is
`veiled` - every byte under an oracle node in recovery, so tree-sitter has no
verdict on any of it - and its own tree leaves the same 4,644 bare. `warp` is
**0**. The reconciliation the previous lane flipped to 62,888 was derived from a
column the oracle is blind on; verilog's adjudicated damage is its board
`damage`, **62,180**, unchanged.

**Eight tripwires in `adjudged()`, plus two that prove they bite - all ten green,
and the whole `verify` slate green with them (38 of 38 the last time it ran; the
count is a sibling's to move, the ten rows are mine).**
All corpus-shaped, none naming a grammar, because two lanes had falsifiers
dissolved this week by siblings fixing the product the witness stood on. The
load-bearing ones: the oracle's hole must exist and be the same order as ours
(red in exactly the world where the sentence is false and `honest` is right);
`warp` must not read zero everywhere, or it is an assertion wearing a
measurement's clothes; `airy` must differ from `slack`, or `owed` measures nothing
`text` did not; and `warp`/`slack`/`veiled`/`padding` join `shaded`'s price-move
set, because the oracle's answer about a byte must not move with *our* pricing
policy. The can-say-no rows hand `adjudged` a constructed board where the oracle
leaves no hole: three rows go red and the population row stays green, so the red
is about the oracle's answer and not about having measured nothing. That board
cannot be produced by editing the corpus, which is why it is constructed rather
than found.

Two instruments repaired on the way. `hollow()` divided by `damage`, so
`rack.py run <any clean grammar>` died with `ZeroDivisionError` - a clean board
was the one input the reconciliation report could not print, and had been since
the column shipped. And `verify` swept the corpus **twice**, once inside
`shaded()`; two sweeps are two populations whenever a sibling lands mid-run, and
the two corpus-shaped gates would then disagree about a board they both call "the
corpus". One sweep now, passed to both, which also halves an 80-second `verify`.

The dossier is `research/joinery/stretch/`, with the source citations, the
real-bytes witness, the full 29-row cross-tab, what I now trust least (`veiled`
is 96% verilog, so `owed` prices those bytes at zero by default rather than by
verdict), and my own predictions scored - four held, and **two failed together**
because I predicted the two error directions backwards. I said whitespace inside
a leaf would be thousands of bytes concentrated in html and php, and
non-whitespace with no oracle leaf would be tens; it is **2** and **2,324**, and
html and php owe **0** apiece. The reason is worth writing down: the `text` nodes
we fail to build are outside `built` entirely, so they are `damage` and never
candidates for this column, and I predicted them into it because they were the
largest thing nearby. The previous lane predicted from a column's **name**; I
predicted from its **size**. Same mistake one step out, and the same fix: read
the code that puts a byte in the bucket before forming a view about the bucket.

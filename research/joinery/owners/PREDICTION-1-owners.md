# Prediction 1 — who owns the corpus's 181 walls

Written before the closure has been pointed at a single wall outside verilog.
Everything in this section is a board I already hold and am **not** predicting.

The pinned binary is `.local/pin/owners` (`OUTLINER_BIN`), so nothing below moves
when another lane rebuilds `zig-out`.

Read-only facts:

- `tool/standing.py`: `built + orphan + rubble + spoil = 526,798`, headline
  **69.09% standing**. Damage board by `damage = size − built`: verilog 63,937,
  haskell 25,048, kotlin 20,974, yaml 18,935.
- `research/joinery/verilog/README.md` labelled four named walls by hand, off
  `reach.py`: `` ` `` in 1108 **gap**, `;` in 701 **conflict**, `(` in 3772
  **conflict**, `=` in 2394 **conflict**. `reach.py` itself prints six rows and
  says *two gaps, four conflicts*.
- **Externals, counted off the vendored `grammar.json` files just now.** Seven of
  thirty grammars declare none at all: c, embedded-template, go, java, json,
  **verilog**, zig. The other twenty-three do, and the three grammars directly
  below verilog on the damage board declare 49 (haskell), 10 (kotlin) and
  **113** (yaml, against 202 rules).

That last one is a fact about the instrument's reach, not about the corpus, and
it is why P1 is first.

---

## P1 — the two-owner taxonomy is verilog-shaped, and a third owner takes a quarter of the corpus

`reach.py` sorts a wall into `gap` (no derivation in `grammar.json`) or
`conflict` (a derivation exists and we refuse it anyway). That is a **complete**
partition on verilog, and verilog is one of the seven grammars in this corpus
where it can be, because verilog hands nothing to an external scanner.

A symbol declared in `externals` has **no rule body**. So the closure sees no
derivation for it and — run naively — would label every wall standing in front of
an external terminal a `gap`. That verdict would be wrong in the direction that
costs most: tree-sitter runs the C scanner and parses the construct fine, so the
gap list handed to the competitive lane would be padded with constructs we are
simply **behind** on, presented as places to get ahead.

`src/press/inquest.zig` already carries the third owner — `Owner.lexer` with
`Because.awaited_external` / `nothing_lexes` — and its own header says six
grammars whose walls are the scanner's came back `weave` before it existed.

**Predicted:** at least **45 of the 181 walls** (25%) are the scanner's — a
lexical stray, or a state wall whose inquest owner is `lexer` — and therefore
belong to neither `gap` nor `conflict`. The corpus gap/conflict ratio can only
be taken over the remainder, and I will report it that way.

**Falsified by:** fewer than 20 such walls. That would mean externals barely
reach the walls the peel actually meets, the two-way split is complete corpus-wide
after all, and the brief's framing needed no third column.

---

## P2 — the closure reproduces verilog's hand verdicts from a state number alone

`reach.py` is handed its governing nonterminal **by hand** (`CASES` carries
`list_of_port_declarations`, `statement_item`, `variable_lvalue`, …). Corpus-wide
there is nobody to hand it 181 of those, so the position has to come off the
wall's own LR state: `outliner state <grammar> <n>` prints the state's items, and
the symbols after the dot are what the position can still consume.

That substitution is the whole risk in Item 1. If the frontier I read out of a
state dump is not the position the hand-written nonterminal named, every verdict
on 181 walls is a different measurement wearing the same word.

**Predicted:** run over verilog's four labelled walls, the mechanical frontier
reproduces all four verdicts — `` ` `` in 1108 gap, `;` in 701 conflict,
`(` in 3772 conflict, `=` in 2394 conflict.

**Falsified by:** any disagreement. One is enough. A mechanical `conflict` where
the hand said `gap` means my frontier is too generous and the corpus conflict
count is inflated; the other direction means it is too narrow and I am about to
hand the competitive lane gaps that are ours. If they disagree I report the
disagreement as the result and do **not** publish a corpus split.

---

## P3 — the row-admitted control: the table and the closure must agree, per wall

Verilog's control was authored: `simple_text_macro_usage` is reachable from
expression position, which is why `` x = `WIDTH; `` parses. Authoring one of those
per grammar is eighteen judgment calls, and a control I chose is a control I can
choose wrongly.

There is a control the automaton hands over for free. **Every terminal a wall
state's own action row admits is, by construction, a terminal that position can
take.** So under a correct closure, every one of them must be reachable from that
state's frontier. The closure has no excuse to miss one, and the fraction it does
find is a per-wall, oracle-free score on my frontier extraction and my
name-bridge together.

**Predicted:** across the corpus the closure finds **≥ 95%** of row-admitted
terminals reachable from the frontier of the state that admits them, and I will
watch this number **collapse** first — by feeding a deliberately wrong state
number — before believing any run where it is high.

**Falsified by:** under 80%. That is not a corpus finding, it is my instrument
failing, and the gap/conflict board does not get published on top of it. Between
80 and 95 I publish per-grammar control rates beside every verdict and say which
grammars are load-bearing on a shaky bridge.

---

## P4 — bytes and counts disagree in most walled grammars, not just verilog

Verilog's `witness.py` found the disagreement twice on one file: `` ` `` in 1108
leads by statements stopped (nine), `` ` `` in 1953 leads by bytes (one statement,
16,289), and state 2394 takes seven of nine warm-only walls while costing
**−167 bytes** and landing twelfth of thirteen.

**Predicted:** with the peel priced in bytes, the wall that leads by byte cost is
**not** the wall that leads by recurrence in **at least 6 of the 18 walled
grammars**.

**Falsified by:** two or fewer. That would make the recurrence ordering an
adequate proxy corpus-wide, verilog the exception rather than the exemplar, and
Item 2 a change worth making for verilog alone — which I would have to say
plainly, because the brief is built on the opposite.

---

## P5 — my own flattering number, named before I can be tempted by it

A byte price is trivially inflatable: overlap the segments, or hand a wall the
bytes of the whole remainder, and every wall gets expensive. The cold peel makes
this easy to do by accident, because round *i* re-parses everything round *i+1*
also parses.

So the price is a **partition**. Wall *i* sits at absolute byte `A_i` and owns
`[A_i, A_{i+1})`, the file it stands in front of before the next wall takes over.
That has an arithmetic consequence nothing else here has:

    Σ (every wall's bytes) + (the clean prefix before the first wall) == file size

**Predicted:** that identity holds **to the byte on every grammar**, it is printed
on every run rather than checked once, and a grammar where it fails prints as
failed instead of printing a price.

**Falsified by:** any grammar where the sum and the size disagree. Which would
mean my prices double-count, and the byte ordering I am asking a whole project to
rank by is the same class of number as the one it replaces.

---

## P6 — what I expect to get wrong

The peel resumes **cold**, in state 0, from an arbitrary byte. So some of the 181
walls are a fragment starting mid-construct rather than a construct the grammar
cannot express, and a `gap` verdict on one of those is a true statement about the
automaton and a misleading statement about the language.

**Predicted:** I cannot separate those two with the closure alone, so every gap I
hand the competitive lane carries the peel round it came from and whether the
*warm* peel — which never restarts — reaches it too. Gaps the warm peel confirms
are the ones I flag as real-world constructs; the rest ship labelled as
cold-peel-only and therefore weaker evidence.

**Falsified by:** finding that the warm peel confirms essentially all of them, in
which case the caveat was cheap and I say so.

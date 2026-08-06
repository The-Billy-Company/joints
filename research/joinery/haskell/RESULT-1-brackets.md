# Haskell's bracket orders, and the elixir accusation

Measured on `7d72a5d` plus the live working tree, arms built
`-Dcli-optimize=ReleaseFast`, 2026-08-06 ~19:30Z. Both arms are the same tree
with one two-row data field deleted and restored; the restore was verified
byte-identical to the first treatment run before anything here was written.

## The accusation came first, so it goes first

Two lanes reported that elixir had stopped parsing as one tree under the
in-flight `src/kernel/lex/{scanner,outside,writ}.zig` trio - `unexpected do at
29624`, 119 roots, `square` collapsing 23,879 to 1. That trio is mine.

**It is not mine, and the arm that says so is the one I was going to have to
build anyway.** The control deletes the two-row `.brackets` field from haskell's
troupe, which makes the entire seat inert rather than merely unused: nothing
resolves, both loops run over an empty list, and - the part that matters -
nothing ever pushes a marker frame, so `bracketed` cannot fire and `standing`'s
`>= marker` collapses to exactly the `== sealed` it replaced. There is no path
left by which the diff can change a byte for a grammar that declares no
brackets.

Over nineteen grammars with a real corpus source, control and treatment are
**identical on eighteen rows**, haskell alone excepted:

```text
$ diff control treatment
haskell  roots=2683 mended=1661 mendB=1872 supplied=128 seen=4691 nodes=6868
haskell  roots=2003 mended=873  mendB=906  supplied=46  seen=5526 nodes=12051
```

Elixir reads `roots=1 seen=7071 nodes=9477` in **both** arms, and on the live
tree it parses `accepted, 1 root`. php reads `roots=1` in both. scala reads
`roots=26` in both. So the seat did not break elixir, and elixir is not
currently broken.

### Why the isolation that named me was sound reasoning and still wrong

The elixir lane's fifth arm carried base plus its strand test plus the live
`gather.zig`/`quire.zig`, parsed elixir whole, and concluded the break lay in
what that arm did *not* carry. That is the right method. The gap is in the
population it eliminated from: the live tree at the time also carried
uncommitted `src/press/{settle,forks,lalr,bench}.zig` and
`src/folio/{bind,impose,leaf}.zig`, and a press change rebuilds the action table
for every grammar. "Not quire, therefore lex" holds only if press and folio are
clean, and they were not.

The window also contains a committed event. `7d72a5d` - *drop a merge rung that
cost square bytes in both directions* - is authored `12:23:47 -0700`, which is
**19:23Z**, after the 18:10Z break measurement, and it removes the `folds` rung
from `Reading.beats` outright. Its own message records that this rung in one
direction "drops markdown to no tree at all," so the rung was demonstrably
capable of collapsing a row to nothing. I am not claiming it as the cause - the
lane measured strand-plus-`folds` at elixir 22,861, which is not a collapse -
only that a table-shaped change entered and left that window and that the
elimination never covered press.

**The actionable half: elixir parses whole right now. Re-measure before
believing any arm pinned inside that window.**

## What the seat is worth

One row moves, and it moves in one direction on every column:

| column | control | treatment | delta |
|---|---|---|---|
| roots | 2683 | 2003 | **−680** (−25%) |
| mended | 1661 | 873 | **−788** (−47%) |
| mend bytes | 1872 | 906 | **−966** (−52%) |
| supplied | 128 | 46 | **−82** (−64%) |
| surveyed | 4691 | 5526 | **+835** |
| nodes | 6868 | 12051 | **+5183** (+75%) |

The last row is the one to read first, because it is the one the refusal columns
cannot say. The tree is not merely less mended - it is **75% larger**. Structure
that previously was not built at all is now built, which is what a seat for a
zero-width parser order should do and what a mend-suppression would not.

The `supplied 128 → 46` line has a second reader: the Mend policy lane found
haskell's 128 supplies producing 255 zero-width nodes, and named that as the
join where an offset key double-counts. The seat removes 64% of that population
at its source.

### Rows held permanently in the arm, and why

php, scala and elixir are in `arms.py` for good, not for this measurement. The
keyword lane has twice measured that touching how a named terminal relates to
the slate is catastrophic *outside* the grammar being repaired: extracting
keywords seated verilog and took php from 67,697 square bytes to 662 and scala
from 6,739 to 201, because 21 of 30 grammars name a `word` and their literals
are not all reserved. A corpus total would have shown that as a win. So each row
is printed, and an unmoved row is evidence in its own right - it is the claim
that a seat keyed on `troupe.kind == .writ` is confined to the one troupe that
declares it.

## The warrant, which is a rule the codebase already enforces

A zero-width node is a hypothesis, and the standing rule is that **a supply is a
hypothesis with a one-token warrant.** The Mend policy lane reached that from the
runtime side: `fell`'s `unwind` was publishing unconfirmed hypotheses as finished
structure - 127 zero-width nodes at depth 0, covering no bytes, under no parent,
against 1 under `keep` - and its repair took corpus crooked from +688 to +112 by
publishing provisional structure *late* rather than by deciding it earlier.

The bracket family is the case where the warrant is granted outright rather than
hoped for. All four terminals - `_cmd_texp_start`, `_cmd_texp_end`,
`_cmd_brace_open`, `_cmd_brace_close` - are the sole shift in every state that
admits them, with zero co-admission, and `unrivalled` re-derives that from the
live table on every call rather than trusting the census. So the seat issues a
zero-width node only where the table has already said no other token can stand
there. It is not a hypothesis published early; it is the one case where there is
nothing to hypothesise about.

`_phantom_bar` is the counter-example that makes the rule bite. It appears in 33
states and is sole in **zero** of them, always beside `,` `=` `|` `::`. It is the
`parse-error(t)` family, where GHC's rule is "insert a close if the parse would
otherwise fail" - a condition about the *future* of the parse, not about the
current cell. `writ.zig` declines it, and it must stay declined: seating it would
be exactly the unconfirmed publication the mend repair removed. The discriminator
is not the terminal's name or its family but whether the table grants the warrant
in the cell, which is why `unrivalled` reads `named` rather than `wanted` - the
extras are auto-admitted and would dilute a warrant they never earned.

## The tally guard, and why an instrument must be able to say "I did not answer"

`refusing.py` reported **936 of 936 refusals in the `clear` bucket** on its first
run - "no blind external was admitted by this state." That is a coherent-looking
answer and it was entirely an artefact: `admitted()` was handing a compiled
`.folio` to `outliner state`, which exits 2 and prints nothing, and an empty
stdout parsed cleanly into an empty admitted set.

It was caught by a claim the data cannot make: **a state in which a refusal
happened cannot admit zero terminals.** A refusal means the parser was somewhere,
and somewhere has a row. So "admits nothing" is not a rare reading, it is an
impossible one, and 936 impossible readings is an instrument reporting its own
silence as a finding.

The guard is now a `TALLY` regex against `^shift \d+, lookahead \d+`, and a
missing tally line raises rather than returning empty. `arms.py` carries the same
shape for the same reason: a row with no verdict line prints `NO-VERDICT`, never
`roots=0`, because zero roots and no answer are opposite facts and must not share
a cell. This is the same failure the `adrift` column had - a bucket whose
emptiness was structural rather than measured - and the general form is that any
bucket meaning "not the thing I was looking for" needs a positive test before its
count is quoted.

## What I trust least

1. **The 53 `clear` refusals.** Now that the tally guard is real the bucket is
   measured rather than artefactual, but it is still defined by exclusion, and
   this project has twice found the small residual bucket to be the honest one.
   It has no positive account yet.
2. **`nodes 6868 → 12051` is a count, not a correctness claim.** A bigger tree
   is what a working seat produces and also what a runaway one produces. The
   refusal columns fell together with it, which is the corroboration, but nothing
   here checks the new nodes against the oracle - and `standing`/`damage` are
   structurally blind to interior structure, so they cannot check it either.
3. **The elixir exoneration is an identity argument backed by nineteen rows, not
   a proof about all inputs.** It is strong because the control is inert by
   construction rather than merely unused, but the corpus is one source per
   grammar.

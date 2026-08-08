# What this parser actually does

Three axes describe where joints stands on its own terms - how much of the
corpus it really understands, what an edit costs it, and what its one safety cap
is worth. The tree-sitter comparison is further down and unchanged.

The first axis changed metric while this pass was being written. It was aimed at
`standing`; `standing` turned out to price comment density rather than lost
structure, so the axis leads on **`rubble`** instead, and the falsifier that
moved it (`tool/shear.py`) is new and reproduced here. The note on which axis I
trust least is at the end, and it is the most useful thing in the document.

Everything in the first four sections was re-measured for this pass rather than
carried over. One binary, one stamp:

```
joints 8e69456aa at .local/lane-report/out/bin/joints
built 2026-08-05T10:21:47Z from . 8e40d3ebc · repo f7ba40004+55
```

That binary stamps `STALE`, because another lane touched
`src/surface/face/joints/main.zig` after it was built. It is not stale in the
way that matters: a fresh `zig build` from the live tree produces a
byte-identical executable, `8e69456aa186…` all three ways, so the flag is an
mtime and not a drift. Checking that was cheaper than arguing about it.

## The headline metric is `rubble`, and it is 7.4% of the corpus

Four numbers in this project describe "how much of the corpus does it read",
they disagree by ninety points, and every one of them has been the headline at
some point. Over the same thirty grammars and the same 526,798 bytes:

| number | what it counts | over the corpus |
|---|---|---:|
| `reach` | the furthest byte any root covers | 96.4% |
| `covered` | bytes under *some* root, including a bare leaf token | 73.1% |
| `standing` | bytes under a root that actually has children | 56.1% |
| **`rubble`** | **bytes left unstructured that are code, not comments** | **7.4% lost** |
| **`trued`** | **bytes under the construct *tree-sitter* puts them under** | **59.1%** |

I came into this pass told to lead on `standing`, and `standing` did not survive
contact. It fails in the same shape `covered` does, one level down, and the
falsification is cheap enough that I should have run it before writing the
number down.

> **Correction, 2026-08-06 — there is a fifth number, and it is the only one on
> this list not made out of our own forest.** `reach`, `covered`, `standing` and
> `rubble` are four cuts of one question — *what did joints put under
> something* — so all four are answered by joints alone and none of them can
> see a byte we structured **wrongly**. `trued = square / size` is answered by a
> second parser: bytes we put under the same construct real tree-sitter puts them
> under, renames excused (`tool/rack.py`). Over the same thirty grammars and the
> same 526,798 bytes it reads **311,540 square — 59.1%**, against 399,871 built.
> **88,331 bytes of this corpus are built and not corroborated.**
>
> That is not a fifth opinion about the same axis; it is the first number here
> that could fall while every other one rose. The section below is right that
> `covered − standing` prices comment density, and right that `rubble` is the
> better of the four — and `rubble` inherits the whole family's blind spot
> anyway, because a construct folded over prose that *is* recognised as code
> reads as neither rubble nor damage. It reads as structure.
>
> Taken from the audited base arm of
> [`consort/RESULT-8-sighted.md`](consort/RESULT-8-sighted.md) - 29 of 30 rows
> sighted, `.local/sighted/boards/base.json`, `joints 68e8f0e395e8`. Nothing in
> this report was re-measured for it; the board it needed already existed.
> `python3 research/joinery/consort/askance.py --grammars` prints it per grammar.

### `covered - standing` prices comment density, not lost structure

The mechanism is a single reduce. One token the tables refuse, *anywhere* in the
file, prevents the top-level reduce from firing. So the parse cannot hand back
one root over everything; it hands back a forest of the highest constructs it
did finish. Every declared extra sitting *between* those constructs - every
comment, every docstring - was going to be a child of the node that never
closed, and becomes a childless root instead. It is a leaf in a healthy parse
too. It has no subtree to be missing.

So the gap column punishes a grammar for having comments, and I can cut a file
to prove it. `tool/shear.py` walks each file's own top-level construct
boundaries, finds the first one the same grammar stops accepting, and re-parses
the prefix below it:

```
                whole file                        prefix, identical grammar
  python    1,728 B   54 roots   76.3% standing  ->    438 B   1 root   100%   0 rubble
  scala    20,107 B  1267 roots   66.1% standing  ->     75 B   1 root   100%   0 rubble
  ocaml    16,878 B   349 roots   91.3% standing  ->     76 B   1 root   100%   0 rubble
  c         1,444 B    28 roots   60.4% standing  ->  1,215 B   1 root   100%   0 rubble
```

**Eleven of the nineteen forests in the corpus do this**, across both sets: one
root over every byte of the prefix, 100% standing, zero rubble, on identical
bytes and an identical grammar. Nothing about the parser changed between the two
columns.

> **Correction, 2026-08-05 — `shear` is instrument #10, and this passage used to
> claim more than it measures.**
>
> What it measures is real and I am leaving it in: those prefixes are genuine, they
> really do parse to one root, and the point they were raised to make - that a
> childless root is often a comment orphaned by a wall somewhere else, so the gap
> column punishes a grammar for having comments - still stands on its own evidence.
>
> What it does not license is the sentence that used to end this paragraph:
> *"2,206 childless roots sit downstream of a single refusal."* That reads a count
> of **walls** out of a measurement of **prefixes**, and the prefix column above is
> its own refutation once you take the ratio. scala keeps **75 bytes of 20,107**
> (0.4%); ocaml **76 of 16,878** (0.5%). "One root over every byte" is trivially
> true of a short enough prefix - the limit case is a single construct, one root by
> definition - so at those fractions the flip is evidence about the cut, not about
> the file.
>
> **The cross-check that settles it comes from the other loop.** `zig build census`
> reports, per grammar, how many times quire had already put the stack down and
> resumed before reaching the wall the verdict names: **scala 549, sql 273, ocaml
> 87, python 13, go 8.** A cut at byte 75 sits upstream of all 549, not one. Two
> independent instruments, and the mend counter was never asked.
>
> **And it moved.** Re-run against the same corpus the next day, `shear` flipped
> *twelve* grammars rather than eleven, with verilog newly inside the list on a
> 1,717-byte prefix of 94,657 (1.8%). Nothing in `shear` is nondeterministic; it
> is a pure function of a tree ten agents are editing, so it is reproducible
> within a run and unstable between them. That is the lesson in the trust note.
>
> The work order this passage was carrying has been redone from the census, which
> answers the same question without a prefix: see **Who owns each wall** below.

Two corrections to the version of this proof I was handed, neither of which
changes its conclusion.

**Cutting "immediately before the wall" does not work.** The verdict names only
the *last* token refused, so cutting there leaves every earlier refusal in the
file: c comes back with 13 roots, cpp with 24, go with 15, bash with 20, all
still `truncated`. Cutting at the wall *byte* is worse - it lands mid-construct
and proves only that half a function is half a function. Scanning up from the
front is what locates the first refusal, and that is the cut that flips.

**The five it flips on are not quite the five I was given.** In the corpus set I
get c, cpp, go, python and bash, five for five. **ruby does not flip** - no
prefix of it stands alone, because it breaks at byte 367 before a single
top-level construct closes. So ruby belongs in the second group below, and the
claim is stronger without it: eleven for eleven across both sets.

`python3 tool/shear.py`, machine copy `walls/shear-audit.json`.

**A second falsifier, from the opposite direction, agrees.** `shear` holds the
content fixed and shortens the file; the control in `tool/README.md` holds the
length and every byte offset fixed and blanks the comments to spaces. kotlin's
`built` stays **15,319 to the byte**, its wall stays `unexpected @ at 245 in state
944`, its mend count stays 426 - while `covered` falls 91.5% -> 48.1% and `strewn`
falls 17,464 -> 1,891. swift holds 7,794 built either way, verilog 28,337. The
comments were carrying nothing. That control is a sibling lane's and I did not
re-run it; I am citing it because two independent constructions landing on the
same mechanism is worth more than either alone.

### So the board is `rubble`, and verilog owns it

```
89,364 strewn = 50,486 orphaned extras + 38,878 rubble
```

**56% of the "strewn" headline is comments.** The honest figure for lost code
shape is 38,878 of 526,798, or **7.4% of the corpus** - a fourteenth, not the
sixth the old line claimed.

| grammar | bytes | covered | standing | strewn | orphan | **rubble** | share of all damage |
|---|---:|---:|---:|---:|---:|---:|---:|
| **verilog** | 94,657 | 49.3% | 29.9% | 18,348 | 3,267 | **15,081** | **39%** |
| elixir | 46,089 | 87.7% | 71.9% | 7,324 | 340 | **6,984** | 18% |
| julia | 27,360 | 67.2% | 35.0% | 8,800 | 2,374 | **6,426** | 17% |
| swift | 28,468 | 77.0% | 27.4% | 14,134 | 9,199 | **4,935** | 13% |
| scala | 20,107 | 76.7% | 66.1% | 2,126 | 0 | **2,126** | 5% |
| kotlin | 35,815 | 91.5% | 42.8% | 17,464 | 15,573 | **1,891** | 5% |
| markdown | 3,304 | 17.9% | 5.4% | 415 | 0 | 415 | 1% |
| ocaml | 16,878 | 93.1% | 91.3% | 293 | 0 | 293 | <1% |
| haskell | 34,240 | 23.8% | 0.0% | 8,133 | 8,123 | **10** | ~0% |

Six grammars carry 96% of it. **verilog alone is 39% of every genuinely
unstructured byte in the corpus**, and its gap column is small only because the
file is comment-poor - which is exactly the trap. kotlin was the poster row for
the gap at 91.5% covered against 42.8% standing; 15,573 of its 17,464 strewn
bytes are KDoc, so its real damage is 1,891 bytes and it is near the bottom of
the board. scala looked like the reverse: 2,126 strewn with **zero** orphans, so
every byte of it was called code.

The split was checked rather than asserted. A sibling lane validated it against
an independent comment scanner on three grammars - swift +1.8%, haskell -1.2%,
kotlin conservative by 4,220 bytes that live inside built subtrees.

> **Correction, 2026-08-05 — scala's zero was the bug, not a property of the
> file.** `Option.scala` is **79% block comment** by byte (15,912 of 20,107,
> across 36 Scaladoc blocks; 83% counting `//` lines). A file that is four-fifths
> prose cannot have zero orphaned extras, and "every byte of it is code" is the
> single most wrong sentence on this board.
>
> The mechanism is worth more than the row. `rubble` classifies a childless root
> by asking the grammar whether that node is a declared `extra` - and scala
> declares `block_comment` as one, so the list was never the problem. **The
> lexer had no stand-in for it, so no comment node was ever built to ask about.**
> The bytes were read as code, folded into constructs, and the extras test was
> offered nothing to classify. This report already carried the caveat that
> `rubble` is "exactly as good as each grammar's `extras` list"; it is in fact
> as good as the *token*, which is a strictly weaker guarantee and fails silently
> and one-directionally - always toward calling prose code.
>
> **Where else this bites:** the four rows above with a suspiciously round zero
> or near-zero orphan column against a comment-bearing file. ocaml read 0 and is
> now 1,829. markdown still reads 0. That is the check to run before quoting any
> row of this table.
>
> Seating scala's and ocaml's comment scanners (below) moves scala to **476
> rubble against 10,415 orphans** and ocaml to **88 against 1,829**.

That check was run, with an oracle in it.

> **Correction, 2026-08-06 — two rows have left this table without getting any
> better at agreeing, and the table cannot say so.**
>
> `rubble` is `damage`'s sibling: both are computed from what joints built, so
> a grammar leaves this board by **building** bytes and not by building them
> right. Sighted, two of the nine rows above have done exactly that.
>
> | grammar | then | now, sighted | |
> |---|---|---|---|
> | elixir | 6,984 rubble · 71.9% standing · **18% of all damage** | 0 rubble · **100% standing · 0 damage** · 51.8% trued | **22,210 bytes built and not corroborated** |
> | verilog | 15,081 rubble · 29.9% standing · **39% of all damage** | 13,979 rubble · 34.0% standing · 62,464 damage · **2.3% trued** | 30,009 built and not corroborated; **7.9% of its adjudicated bytes are square** |
>
> **elixir is off this table entirely and is not a fixed grammar.** It builds
> every one of its 46,089 bytes, has no rubble left to name, and derives 22,089
> of them under a different parent than tree-sitter. Anything in this document
> that reads a fallen `rubble` or a risen `standing` as progress is reading a
> column that was never asked whether the structure was right.
>
> **verilog's 39% share stands and re-points.** It is still the largest genuinely
> unstructured row on the board, and the 32,193 bytes it *does* build carry only
> 2,184 square. So work that converts verilog's damage into `built` is, on
> tonight's evidence, work that converts unbuilt bytes into misderived ones —
> which is a real result rather than a smaller version of the same win.
> `verilog/RESULT-1-wall.md` carries the same re-pointing over its own ablations.
>
> The 7.9% is `square / (built − unaudited)` and is deliberately **not** quoted
> off `crooked`, which is under repair tonight (`consort/HANDOFF-crooked.md`).
> Both candidate fixes only redistribute bytes among `crooked`, `soft` and
> `unframed`, so their sum — and therefore this ratio — is invariant under
> whichever the rack lane picks.

### The delimited-span fix, measured — and `standing` got worse

Six grammars were named as one cause: the refused terminal is *the inside of a
delimited span*, because `joints` had no external-scanner stand-in for the
comment or string body, so the parser read the prose as code. Two of the six
were bounded runs a `marrow` vein can answer whole - scala's nesting `/* */` and
ocaml's nesting `(* *)` - and those two are seated. Control: the live tree with
only this lane's rows reverted, everything else identical, **28 of 30 grammars
byte-identical**, 16 of 16 pinned controls holding.

| | control | after | |
|---|---:|---:|---|
| scala rubble | 2,126 | **476** | −1,650 |
| ocaml rubble | 293 | **88** | −205 |
| corpus rubble | 31,459 | **29,604** | −1,855 |
| corpus covered | 74.0% | **74.8%** | +0.8 |
| corpus **standing** | 58.5% | **57.4%** | **−1.1** |

**The last row is the honest cost and it is not a regression in disguise - it is
the removal of fake structure.** scala's `built` falls 13,295 → 8,204 because
those bytes were constructs folded *over Scaladoc prose read as code*. A tree
spanning a doc comment's innards was never structure; deleting it has to show up
as a loss on a column that counts bytes under constructs. `rubble`, the column
this report says to trust, moves the other way in both grammars, and `covered`
rises because comment bytes are finally covered by comment leaves. If you want
one number: 1,855 bytes stopped being called unstructured code, and 5,812 bytes
stopped being called structure they never had.

> **Upheld, 2026-08-06, and this is the one claim on the page a second parser has
> now confirmed rather than a mechanism argued for.** *"The last row is the honest
> cost and not a regression in disguise"* was an argument from what a comment is.
> Sighted, ocaml's `comment/.marrow/.ocaml_comment` row is worth **+448 square**:
> un-seating it **lowers** `damage` by 721 and **lowers** agreement with
> tree-sitter by 448 bytes. The board's own words call the seating a 721-byte
> loss; the oracle calls it a 448-byte gain, and they are the same change.
>
> So the whole day's one published regression is not one. Its changelog fragment
> is corrected in place (`+ocamls-comments-are-comments-now-…`), and the mechanism
> this section reasoned from is now the rule to apply everywhere: **a
> correctly-recognised comment is an orphan and a misread one is `built`**, so any
> `damage`-only reading of a comment, docstring or declared extra is biased in
> that one known direction.
>
> scala's `block_comment/.marrow` vein carries **+6,536 of scala's 6,739 square**
> on today's tree by the same instrument. That is a statement about today's tree
> and not a re-derivation of the −1.1 above, because scala's layout troupe landed
> after this section was written and the two rows share a ceiling
> (`consort/RESULT-8-sighted.md`). The direction is the same; the arithmetic
> belongs to a different snapshot.
>
> `consort/RESULT-8-sighted.md`, arms r5 and r4, oracle minted inside each arm.

The other four of the six are **not** the same cause wearing the same label, and
saying so is the more useful half of this result. c and lua refuse on a
string-body *pattern* (`(?:[^\\"\n]+)`, `(?:[^"\\]+)`) with **no external
declared at all** - the leak is the grammar's own contextual rule firing where
no parse state gates it, which no scanner row can fix. bash's blind terminal is
`_concat`, a zero-width adjacency signal with no delimiters to run between.
latex's is `_trivia_raw_env_verbatim`, delimited by a *named environment* rather
than a fixed pair. php's wall is not a lexer wall at all. One cause explained
two; four need four answers.

And scala's wall moved rather than vanished: it now stops on `_automatic_semicolon`,
which is the next unrunnable external in the same file.

### Two different failures wear the same forest

`shear` separates them, and the separation is a real one - but read the first
group as *"a prefix of this file stands alone"* and nothing more. It is **not**
"one refusal's shadow", which is what it said here until the correction above.

**A prefix stands alone.** Eleven grammars, on prefixes running from 84% of the
file (c) down to 0.4% (scala). Four of the five I was pointed at in the corpus
are here - c 81, cpp 23, go 48, bash 24 - and with ruby's 147 the five carry
**323 rubble bytes between them.** For c, at 1,215 bytes of 1,444, the flip is
close to a statement about the file. For scala, at 75 of 20,107 against 549
mends, it is a statement about the cut.

**Never completes one construct.** No prefix stands alone, because the file
breaks before a single top-level construct closes. Eight grammars, and they are
where the rubble is:

| grammar | rubble | first refusal |
|---|---:|---|
| verilog | 15,081 | byte 1,041 of 94,657 |
| elixir | 6,984 | byte 127 of 46,089 |
| julia | 6,426 | byte 108 of 27,360 |
| swift | 4,935 | byte 619 of 28,468 |
| kotlin | 1,891 | byte 244 of 35,815 |
| markdown | 415 | byte 861 of 3,304 |
| ruby | 147 | byte 367 of 1,020 |
| haskell | 10 | no construct closes anywhere |

### Who owns each wall

The work order above is a prefix measurement. This one is not: `inquest` presses
each grammar, walks the oracle to the wall the parse actually stopped on, and
argues from the automaton who owns it - **naming the counts you would need to
refute it**, and printing `?` rather than a verdict when the evidence its answer
depends on was never supplied. `zig build census` runs it over all thirty, and
since 2026-08-05 the `parse` verdict prints the same line for whatever file you
hand it. All thirty, one line each:

| owner | n | grammars |
|---|---:|---|
| **whole** | 5 | css, embedded_template, html, json, toml |
| **lexer** | 15 | bash, elixir, haskell, javascript, julia, kotlin, latex, markdown, ocaml, ruby, rust, scala, swift, typescript, yaml |
| **weave** | 7 | c, go, java, lua, php, sql, verilog |
| **press** | 1 | zig |
| **oracle** | 2 | cpp, python |

Stamped, because this board is a reading of a tree ten agents are editing and
that is the lesson two sections down: **2026-08-05, `zig build census`.** It
moved once inside this round - python was `weave` an hour earlier and is
`oracle` here, because a sibling lane narrowed a rung in `settle.zig` while I
was measuring. Quote it with the date or re-run it.

**Half the corpus stops in the lexer, and until this round none of it was
filed there.** The same board before the fix read 2 lexer / 20 weave: thirteen
grammars were being blamed on the parse loop for a token no lexer here can make.
`inquest` had no way to see it, because it only ever consulted the table - a
terminal the scanner cannot produce still has a perfectly ordinary action row, so
the cell looked fine and the residual bucket caught the file. It now takes the
scanner's blind list and makes two arguments the table cannot: **the wall state
was waiting on an unrunnable external** (twelve grammars, `[no stand-in for X]`),
and **an unrunnable external is a declared `extra`**, which is worse - it is in
no action row at all, so its bytes are read as something else *everywhere* in the
file and the terminal the row refused is not the terminal the file holds (ocaml).

Read the small rows as the honest ones they are: zig is **press** on a
`read_dropped` cell still open after seven folds, and cpp and python are
**oracle** - the tables offer the token, a live fork still admits it, and the
walk did not take it.

And `weave` is now a smaller, more suspicious bucket than a clean one. Two of its
seven refuse on a *string-body pattern* - c on `(?:[^\\"\n]+)` in state 1146,
lua on `(?:[^"\\]+)` in state 0 - which is the delimited-span leak wearing a
weave label, because neither grammar declares an external for `inquest` to point
at. The classifier can only argue from what a grammar declares; where the leak
comes from the grammar's own contextual pattern rather than an external, it still
files under the residual. That is the next thing to falsify here.

### haskell is not on this axis at all

Its rubble is **10 bytes**. It fails at byte 681 and its `covered` is 23.8%, so
**it never reaches 76% of its own file** - the damage is upstream of anything
`standing` or `rubble` can price, and the row belongs to `covered`.

And the zero is the lexer's, not the tables'. Counted off the pinned
`grammar.json` myself: haskell declares **49 externals, and dropping
tree-sitter's `error_sentinel` leaves 48 externally scanned terminals.** Only
four of those are ordinary tokens with a fixed byte shape - `comment`,
`haddock`, `cpp`, `pragma`. The other 44 are layout-sensitive or zero-width
signals a hand-written scanner has to *compute*: nineteen `_cmd_layout_*` /
`_phantom_*` openers and closers, twenty-one `_cond_*` conditionals,
`_varsym`, `_consym`, `quasiquote_body`, and the bare newline the layout
algorithm consumes. We compute none of them. (The newline is the one judgment
call in that split - it has a byte shape but no meaning without the layout
stack. Count it as lexable and it is 45 against 3.)

The sibling lane's reading of state 186 agrees from the other direction: eight
lookaheads, all of them reduces, six of them external terminals. I did not
re-derive that one. Either way it is a missing scanner, and no amount of table
work moves it.

### Press debt does not predict parse quality

Worth saying plainly, because it is the axis I would have drawn if nobody had
checked: **go has zero residual table refusals and the worst standing ratio in
the eleven-grammar corpus set; scala carries the largest table debt at 1,221
refusals and one of the better standings.** The surfaced `lalr.Floor` partition on haskell is 0
agreed, 55 alone, 0 stuck, 0 open - every refusal sealed under any split - and
haskell still builds nothing. Those three figures are the press lane's and I
took them as given rather than re-deriving the partition; what I can say from my
own table is that the two rows they turn on hold - go is 29.3% standing with 48
rubble bytes, scala is 66.1% with 2,126. There is no correlation here to report,
and any figure that implies one is reading two unrelated axes as one.

**And the 96.4% is `reach` wearing the word `covered`, in the top-line
scoreboard.** `census.py` sums each grammar's `reach` and prints the total as
"bytes covered"; `TESTING.md` carries it as "all thirty, bytes covered 96.4%".
`reach` was retired for being a watermark. It is still the headline, and
**122,888 bytes it counts sit under no root at all.** verilog is the clean
exhibit: census reads `94656 of 94657, 100.0%`, and fewer than half of those
bytes are under any root.

```
bytes: 295,595 built + 89,364 strewn = 384,959 of 526,798
       56.1% standing against 73.1% covered, 38,878 rubble
       10 of 30 grammars parse whole - one root, no gap by construction
```

`python3 tool/standing.py --rubble`, machine copy `standing-audit.json`.

Re-measured 2026-08-05 on a stamped binary, after the two comment scanners and
several sibling lanes' work landed - quoted for the trend only, since more than
this lane's change is in it:

```
bytes: 302,174 built + 92,068 strewn = 394,242 of 526,798
       57.4% standing against 74.8% covered, 29,604 rubble
       11 of 30 grammars parse whole
```

## Incremental: rust and java save about 85%, json is the floor at 71%

What an incremental parser claims is that an edit reads less than a re-parse
would. Measured as **median tokens read per edit, against the tokens a cold
parse of the same bytes reads** - `python3 tool/repair.py reuse`.

The generator is one distribution, fixed before any grammar was named and not
conditioned on the grammar in any way: sixty edits, each undone on the next
beat, either a delete of 1-12 bytes or an insert of 1-8 bytes drawn from a
random slice of the file's own bytes, at a uniform offset.

| grammar | cold | median read | **saved** | mean read | saved on the mean | broke |
|---|---:|---:|---:|---:|---:|---:|
| rust | 327 | 48 | **85.3%** | 79.0 | 75.8% | 30/60 |
| java | 203 | 32 | **84.2%** | 66.0 | 67.5% | 30/60 |
| json | 288 | 82 | **71.5%** | 105.9 | 63.2% | **50/60** |

Both columns are here because they answer different questions and a grammar
whose breaks are expensive is exactly where they diverge. The median is what a
keystroke costs; the mean is what a session of them costs.

**json is the worst row and it is not close to unmoved.** It breaks on 50 of 60
edits where rust and java break on 30, and that break rate is the whole story of
its cost. Split by edit kind, so it is not an artifact of deletes:

```
rust   13 of 24 deletes broke,  17 of 36 inserts       ~50%
java   13 of 25 deletes broke,  17 of 35 inserts       ~50%
json   23 of 27 deletes broke,  27 of 33 inserts       ~83%
```

### I could not reproduce the numbers this axis was handed

This axis came to me as **rust −20% tokens read, java −12%, json essentially
unmoved.** I get −85%, −84% and −72%. That is a four-fold disagreement and I am
not going to talk it into agreement, so here is what I ruled out.

- **Not the fuse.** "One line flipped in a scratch copy of the whole tree"
  describes the mend budget, so I built that scratch copy - the byte share
  swapped back to the count cap it replaced - and re-ran. The delta is **exactly
  0.0%** on all three grammars: rust 48/48, java 32/32, json 82/82 tokens.
- **Not a cold-baseline mix-up.** `amend.py` prints a column headed `cold` that
  is *microseconds*, not tokens, which is worth knowing before comparing the two
  instruments. Read as tokens it would look like a contradiction and is not.
- **Not the escape bug**, which was mine and which I fixed. My generator drew
  random inserts from the file's own bytes, `amend` unescaped them, `\X` arrived
  one byte shorter than it left, and the undo - sized on the original slice -
  cut a byte too few. A hundred beats later the buffer was scrap. **json was the
  only grammar to notice**, because `ledger.json` is the only seed here holding
  string escapes, and it read as json specifically degrading under an edit
  stream: 21.0% saved with the bug against 78.5% with escapes doubled, while
  rust and java were 86.9% and 82.5% either way. 123 of json's undos had failed
  to restore and nothing was checking.

That last one is the reason `repair.py` now asserts rather than assumes: one
cost line per edit sent, and every undo must come back `accepted`. Both are hard
stops, because numbers past a drifted buffer look like a grammar degrading under
load, which is a far more interesting story than the truth and therefore the one
that gets published.

So the handed figure was produced by a definition I do not have, and I am
publishing mine with the definition spelled out rather than reconciling to a
number whose method I cannot see.

## The json mechanism: it breaks least often and cascades furthest

The reuse table says json costs most. It does not say why, and the why inverts
the obvious reading. `python3 tool/repair.py cascade` drops one stray `}` at
**every byte offset** of each seed and asks two things: does the parse stop
being accepted, and if so how many leaves does the repair re-derive.

| grammar | offsets | broke | rate | p50 | p90 | max | file's leaves | max ÷ leaves | runs |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| rust | 1,435 | 1,022 | 71.2% | 32 | 52 | 89 | 327 | 0.27x | **9** |
| java | 1,259 | 847 | 67.3% | 23 | 43 | 176 | 203 | 0.87x | **6** |
| json | 775 | 377 | **48.7%** | 42 | **193** | **485** | 288 | **1.68x** | **59** |

**json breaks at the lowest rate on the board and pays the most when it does.**
A `}` is often a legal-looking token to json, so half its offsets survive; rust
and java refuse it at seven offsets in ten. Then the tail inverts: json's p90
cascade is 3.7x rust's and its worst is 5.5x, and it is the only grammar whose
worst cascade **re-mints more leaves than the file has** - 485 re-mints over 288
leaves, so the repair is re-deriving the same leaves more than once.

The `runs` column is the mechanism made visible, and it is the prediction I care
most about landing. It counts contiguous stretches of breaking offsets. json's
377 breaks come in **59 short runs**; rust's 1,022 come in **9 long ones**. json
re-grounds expecting a *value*, so a file of `"key": value,` pairs alternates
legal-value / illegal-separator and the break positions interleave with the
survivors. rust and java re-ground expecting a *declaration* and resynchronise
at the next real boundary, so they break in stretches that end where a boundary
token is.

Which gives the shape of the cost: **the repair pays in proportion to how much
of the file is not broken.** That is the editing-session case, and json is its
pathological floor - not a third of a three-grammar average.

**Where my prediction missed.** I predicted json's median cascade at least 3x
rust's and its maximum at least an order of magnitude past it. The direction
landed; the magnitude did not. p50 is 42 against 32, only **1.3x**. The
divergence is entirely in the tail. So "json cascades much further" is true of
the p90 and the max and false of the median, and a report that quotes only a
median ratio would make this look like a rounding difference.

I did not measure whether json's cascade grows with seed length faster than
rust's. The only scaling helper here wraps a file in `[...]`, which is json-only,
so there is no like-for-like length axis across grammars and I am not going to
build one out of a claim.

**Three of json's 775 offsets cannot be measured at all.** The `amend` session
dies with `error.TrailRefused` out of the effect algebra, first at offset 379,
and every remaining edit in that session is never applied. rust and java lose
none. The sweep now runs in batches and restarts past a death, recording the
offset it lost, because a single-session sweep silently measures a prefix of the
file and calls it the file. json's row is 772 of 775 offsets, and it says so.

## The fuse: it fires on nothing, and its stated rationale did not survive

The mend budget caps how much of a file recovery may walk past. It was a count
(`1 << 14` mends) and is now a share of the file (3/4 of its bytes). The change
is strictly better and the reason is sound: a count cap is a length cap in
disguise. What did not survive is the rationale written beside it.

Measured with **the fuse held wide** - rebuilt in a scratch copy of the tree
with the cap lifted to a million times the file, because `gather.zig` is another
lane's live file and I am not touching it. A budget that has already fired
truncates the number that would calibrate it. `python3 tool/fuse.py`.

### What was demonstrated: four roots on haskell

I built the count cap back, in a second scratch tree, and swept every grammar on
its own file:

```
haskell, count cap 1<<14    90 roots, 16,385 mends over 17,061B
haskell, byte share 3/4     94 roots, 16,635 mends over 17,314B
```

**Four roots, on one grammar, and it is the only one of thirty where the two
caps disagree at all.** That is the whole demonstrated benefit of the change.
It is real and it is small, and it should not be described as anything else.

### What was disconfirmed

**The populations do not separate.** The source comment says three quarters is
"where the measurement separates". Over 140 (grammar, file) pairs - every
grammar on its own file, plus a full wrong-language block across the corpus -
they overlap almost completely:

```
highest right-language row    haskell on its OWN file        50.6%
lowest wrong-language row     bash reading json               0.0%
wrong-language rows below the highest right-language row     105 of 110
right-language rows above the lowest wrong-language row       19
```

No threshold separates them. A grammar reading its own file can skip half of it
while a grammar reading a language it has never seen skips none.

**And "wrong language means high skip share" is not a property of wrongness.**
It is a property of the json grammar's tiny terminal set. Every high
wrong-language row on the board is json reading something else (42.2% to 69.6%);
**every other grammar reading a wrong language sits at or below 14.8%.** The
comment also names "julia and haskell" as the worst real rows - haskell is
right, but verilog is second at 35.7% and julia is fourth at 11.4%.

**Skip share does not grow with length.** The json grammar reading rust, from
1.4 KB to 1 MB:

```
      bytes  skipped   share    secs   us/KB
       1434      658   45.9%   0.006    4213
      11472     5264   45.9%   0.006     544
      91776    42112   45.9%   0.011     126
     367104   168448   45.9%   0.030      84
     734208   336896   45.9%   0.054      75
    1032480   473760   45.9%   0.074      74
```

**45.9% at every length, spread 0.0%.** Three orders of magnitude and the share
does not move a tenth of a point. If it does not climb, a share cap is not what
stands between this parser and a runaway.

**There is no runaway.** A megabyte of the wrong language costs **0.074 s**, and
the per-byte rate *falls* across the sweep - 84 to 72 us/KB over the tail, 0.86x
- because the small rows are dominated by pressing the grammar, which has
nothing to do with length. Cost is linear. The comment's "runs away toward the
whole file" describes something that is not there.

### So the fuse never fires

The largest skip share anywhere on the board is **69.6%**, json reading ruby.
The fuse sits at 75%. I ran all 140 pairs on both builds and compared verdicts:

```
rows where the 3/4 fuse changed the answer:  0 of 140
lengths where it changed the answer:         0 of 6, out to 1 MB
```

**The wide build is indistinguishable from the shipped one on every row I can
construct.** That is not a defect - it is what "set above every real row" means,
and it is better evidence for the fuse being a statement than any diff would be.
What the fuse says is *the file was skipped*. It is not runaway protection,
because nobody has demonstrated a runaway for it to protect against, and this
report is not going to imply one.

## Which axis I trust least

**The cascade depth column**, and by some distance. Four reasons, in order of
how much they should bother a reader:

1. **It exceeds its own denominator.** json's worst cascade re-mints 485 leaves
   in a file with 288. So `minted` is a *work counter*, not a fraction of the
   file, and the natural reading - "the repair re-derived N% of the file" - is
   wrong. I have kept the `max ÷ leaves` column visible precisely so the unit
   cannot be misread, but nothing stops the number being quoted without it.
2. **It disagrees with the previous lane's figure by 4.7x and I cannot explain
   why.** That lane reported json's p50 depth at 9 and rust's at 3; I get 42 and
   32 on nominally the same quantity. Their sweep sampled 129 positions where
   mine walks all 775, which explains a different *population* but not a median
   four times higher. Two of the eight instruments this project has caught lying
   were found exactly here, in an unexplained factor between two runs of the
   same thing.
3. **Three offsets refuse to be measured.** `error.TrailRefused` kills the
   session, so json's row is 772 of 775 offsets. I report it, and the
   batch-and-restart that gets the other 772 is mine and unproven at scale.
4. **The batching is load-bearing and it is my own.** An offset's cost should
   not depend on how many edits preceded it. Batches of 128 make that roughly
   true and a single session would make it false, but "roughly" is doing work in
   that sentence and I have not measured the residual.

The reuse table sits in the middle. Its instrument now checks itself in two
places it did not before, and both checks were added because the axis had
already published a false reading.

The fuse table I trust most, which is a low bar: it has a clock in it, but every
claim it makes is a comparison of two builds on identical inputs, and the two
builds agree on all 140 rows. Agreement is a much weaker thing to have to get
right than a duration.

**`rubble` I trust more than what it replaced, and less than the confidence a
headline number invites.** Two independent constructions agree on the mechanism
behind it, and a third checked the split against a dumb comment scanner on three
grammars. But it inherits one open assumption: it classifies a childless root by
asking the grammar whether that node is a declared extra, so it is exactly as
good as the grammar's own `extras` list. A grammar that spells a comment as an
ordinary rule - or a docstring that is a real expression, as in python - lands in
`rubble` and inflates it. The kotlin validation already caught the reverse bias
worth 4,220 bytes. So treat 38,878 as an upper bound on lost code shape, and
verilog's 15,081 as the one row big enough that it would survive any plausible
misclassification.

**That assumption is weaker than stated, and scala is the proof (2026-08-05).**
The test is not "does the grammar declare this an extra" - scala declares
`block_comment` and still read 2,126 rubble against zero orphans. It is "did a
node get built to ask the question of". No stand-in for the comment scanner
means no comment node, means nothing to classify, means 15,912 bytes of Scaladoc
counted as code with no signal that anything was wrong. **A zero in the orphan
column is not evidence of a comment-free file; it is equally consistent with a
lexer that cannot see comments at all**, and the two are indistinguishable from
this table. Check the file before quoting the row. Seating the two scanners took
the corpus to 29,604 rubble; markdown's remaining 0 orphans is the next row that
should be assumed guilty until read.

### What I trusted most until three hours ago was `standing`

I had this section written with `standing` at the top of it, for the boring
reason that it is a byte count off a deterministic tree walk with no clock in
it: it reproduces exactly, and the only thing that can move it is the tree
moving. Every word of that is still true. It reproduces exactly. It is also
measuring comment density, and the reproducibility was never evidence about
*what* it counts.

That is the whole lesson and it is worth more than the number it replaced. A
deterministic instrument with no clock in it can be wrong in the one way you
cannot catch by running it twice.

**`standing` is the ninth instrument this project has caught overclaiming, and
the chain has not broken in our favour once.** Every correction has gone the
same direction: `reach` was a watermark printed as `covered`; the ASI ablation
was invalid; the "sixth of everything" was a fourteenth; the fuse's stated
rationale did not survive contact; the incremental numbers this pass was handed
could not be reproduced; and `standing` counts a comment demoted by a wall
somewhere else as a token lying where a tree should be. Nine for nine, always in
the direction of the project having claimed too much.

I do not think that is nine unlucky draws. Nine one-directional errors is a
process fact: the instruments were built by people who wanted a number to be
good, checked against the hypothesis that it was good, and shipped when it was.
The measurement that catches this is never a re-run - it is asking what the
number would look like if the thing it claims were false, and then building
*that*. `shear.py` exists because I asked what a childless root would look like
if it were harmless, and the answer was "cut the file and it stops being one".

So the most honest line the report has is not any of its figures. It is that the
error bar on this project's self-assessment is one-sided, and the next number to
fall will most likely be one nobody has thought to falsify yet. If you are
picking up this dossier: the candidates are the ones with no falsifier written
next to them.

### #10 was `shear` itself, and it is a new failure mode

The paragraph above ends by saying the next number to fall is one nobody has
falsified. It fell in the same document: `shear.py` - written *as* the falsifier
for `standing`, and cited three sections up as this report's work order - is the
tenth. The correction is at the top; what belongs here is the part that is not
just "another overclaim".

It repeated the exact error `reach` made as #1. `reach` printed a watermark and
called it comprehension; `shear` printed "one root over every byte" of a prefix
and called it a count of walls. Both are true statements about a smaller thing,
read as claims about a larger one, and in both cases **the refutation was already
in the printed output** - `shear`'s own prefix column says 75 of 20,107, and
nobody took the ratio. A falsifier is not a different kind of instrument. It
needs its own falsifier, and the fact that it was built to catch a lie is not
evidence that it does not tell one.

**The new lesson is about stability, not determinism.** #9's lesson was that a
deterministic instrument with no clock in it can be wrong in the way running it
twice cannot catch. `shear` is worse than that: run against the same corpus on
two days it flipped **eleven grammars and then twelve**, verilog appearing in the
second run on a 1.8% prefix. Nothing in it is nondeterministic - it is a pure
function of a working tree that ten agents are editing, so *within* a run it
reproduces perfectly and *between* runs it does not measure the same thing. So:

> **Reproducibility is not stability.** A number that reproduces on demand can
> still be a different number tomorrow, and a report quoting it has no way to
> tell. An instrument reading a moving corpus has to stamp what it read - which
> is what `tool/stamp.py` is for, and `shear` does not use it.

The one habit that caught all three of these is worth stating once: **the check
came from a different loop.** `shear` reads the oracle's verdict; the mend
counter lives in quire. Asking the second what the first had already skipped past
took one command and cost the claim its life. Where a number has no second
opinion available, that absence is the finding.

`inquest` now answers the question `shear` was written to guess at, on the parse
verdict itself, and it is the better instrument for a reason worth copying: it
does not sample, it states an argument about the whole automaton and prints the
counts you would need to refute it - and it prints `?` when nobody supplied the
evidence its answer depends on.

### #11 is `rubble`, and it was caught by exactly the habit named above

*"Where a number has no second opinion available, that absence is the finding."*
`rubble` had none. It is `damage`'s sibling — both are arithmetic over the spans
joints itself built — and the section above chose it over `standing` on the
strength of a mechanism, which was the right call among four numbers that all
answer the same question.

The second opinion arrived as `square`, and it is the eleventh one-directional
correction in a row: **elixir leaves the `rubble` board at zero while building
22,210 bytes nobody corroborates**, and verilog's 39% share turns out to sit on
32,193 built bytes that are 7.9% square. Both corrections are above. Neither is
a re-run and neither is a new instrument built for the purpose; the board that
answers it (`consort/RESULT-8-sighted.md`) was taken for something else and had
the column in it.

What makes this a *twelfth* lesson rather than a repeat of the eleventh is where
the blindness lived. #9 and #10 were instruments that measured the wrong thing.
`rubble` measures exactly what it says. The defect is that **twenty-eight of the
thirty-three boards retained on this disk had never read a `square` byte**, so
the column existed, was implemented, was correct, and was empty everywhere anyone
looked — because oracle sight is not inherited from a shared cache and every
private work dir starts blind (`consort/RESULT-5-blindness.md`,
`tool/pin.py oracle`). An instrument nobody can run in the place they measure is
indistinguishable from one that does not exist, and it fails silently in the same
direction as all the others: toward the project having claimed too much.

## Reproducing these four

```
python3 tool/standing.py --rubble         # the board, 30 grammars, honest order
python3 tool/standing.py --audit          # ...and the `trued` column, which needs an oracle
python3 research/joinery/consort/askance.py --grammars   # built against square, per grammar
zig build census                          # who owns each of the 30 walls, with the argument
python3 tool/shear.py                     # cut at the first refusal - and read the prefix column
python3 tool/shear.py --set=corpus        # the five the standing argument was made on
python3 tool/repair.py reuse              # tokens one edit reads, against a cold parse
python3 tool/repair.py cascade            # one stray brace at every byte offset
python3 tool/fuse.py share                # right language against wrong, 140 rows
python3 tool/fuse.py length               # share and cost against file length
python3 tool/fuse.py length --wide        # and refuse to report if the cap bound
```

`fuse.py` takes `--wide` as an assertion rather than a promise: if any row lands
at or above a 74% share it refuses to print a calibration, names the row, and
says to rebuild with the cap lifted. That is the mistake this axis was making
before, so the instrument now declines to make it.

---

# Against tree-sitter, on every axis

Taken twice with `tool/bench.py` at `-Dcli-optimize=ReleaseFast`, against
tree-sitter 0.26.11, on the same 128 KB files. Every row carries a stamp. The
two sweeps do **not** carry the same stamp, and that is disclosed below rather
than smoothed over.

## The row we lose worst

```
incremental typescript @98%    66,224 us    vs    430.6 us    153.8x
```

One space typed and deleted at byte 128,925 of 131,565. Our first keystroke after
the open costs 66,497 us; our own cold open of the same file is 75,206 us. The
edit costs **88% of reopening the file** - the incremental path on this grammar is
not slow, it is barely incremental.

**Re-taken on a current binary, and it now stands alone.** The earlier draft of
this row read 9,210,623 us and 14,746x, with javascript beside it at 10,066x and
java at 326x. Those were measured before the weave lane's `torn` fix gave each
live reading its own strand, and they are dead:

| `@98%` | first keystroke as % of a cold open | ratio vs tree-sitter |
|---|---|---|
| java | 99.2% → **1.6%** | 326x → **3.0x** |
| javascript | 94.0% → **1.1%** | 10,066x → **1.2x** |
| rust | 1.0% → 2.7% | 5.0x → 7.1x |
| json | - → 1.7% | 0.80x → 0.89x |
| **typescript** | - → **88.4%** | 14,746x → **153.8x** |

So the "the incremental path does not engage at all" defect was three grammars
and is now **one**. java and javascript joined rust in the sub-3% band, which is
what an incremental parser is supposed to look like. typescript did not, and it
is the same shape it always was rather than a new one - which makes it a much
better bug than the three-grammar version, because whatever is different about
typescript is now the whole question.

That is the headline. It is not a tuning gap, and the cause below is attributed
by profile and by controlled experiment rather than by the name of a terminal.

## Retraction: the ASI story was wrong, and the ablation behind it was invalid

An earlier draft of this report led with a newline ablation:

```
javascript-122.js as-is                 18,237.0 ms
javascript-122.js, \n replaced by ' '       11.9 ms     "1,533x from one byte class"
```

and concluded that `_automatic_semicolon` was the cause, and that 90 ns/B was
roughly where a fix would leave us. **Both halves are withdrawn. The experiment
did not measure what I said it measured.**

`javascript-122.js` holds 244 line comments, the first at byte 251. Replacing
every `\n` with a space turns everything after byte 251 into **one line
comment**. The byte count is identical, which is what made the ablation look
controlled, but the program is not:

```
as-is         131,760 B    4,579 ms    tree: 39,407 lines
\n -> space   131,760 B       20 ms    tree:      17 lines
```

The fast run parses seventeen lines of tree. It did not remove a cost, it removed
99.96% of the program. Holding bytes constant is not the same as holding the work
constant, and I checked the wrong one.

The direct test settles it. Bytes **and** node count held constant, only the
number of line terminators varied:

```
2000 statements, 24,890 B, 28,001 nodes throughout
 newlines 2000      987 ms
 newlines 1000      924 ms
 newlines  500      910 ms
 newlines  125      932 ms
 newlines   32      942 ms
 newlines    1    2,248 ms      (worse, not better)
```

**Line terminator count does not matter.** ASI is not the cause. The "three
instruments pointing at one terminal" was one real census row plus two readings
of my own broken experiment.

## The cause, attributed

### The profile: 98.2% is in the scanner, and it is not the fold path

`/usr/bin/sample`, 12 seconds of a single 18-second run, 2,354 samples:

```
2354  parse.run                                      parse.zig:178
2312    kernel.quire.gather.Gather.run               gather.zig:544
2312      kernel.lex.scanner.Scanner.nextKeeping     scanner.zig:704
2312        kernel.lex.scanner.Scanner.read          scanner.zig:801
2312          kernel.regex.linear.program.munch.Munch.longestAmong
   3    kernel.quire.gather.Gather.fold              gather.zig:1642
   1    kernel.quire.gather.Gather.mint              gather.zig:1766
```

**98.2% under the scanner's longest-match, 0.13% under the fold path, 0.04%
under minting.** `scanner.zig:801` is `s.reach(...)`, the slate walk - not
`s.refusing(...)` on line 799. Of the three candidates it is **(a)**; (b) and (c)
are ruled out by measurement rather than by argument.

### It is not raw scanning; it is scanning under a per-position `Expected`

The same scanner over the same bytes with **no** admitted set, via `joints lex`:

```
lex     104,000 B       483 us      one token, no parser context
parse   104,000 B    14,508 ms      same bytes, same scanner, per-position Expected
```

30,000x. Whatever is expensive lives in what `Expected` does to the search inside
`reach`'s tier loop, not in walking bytes.

### The growth law: per-token cost climbs with the prefix already read

Both grammars are quadratic, and it is the per-node cost that rises:

```
javascript    5,890 B    3,501 nodes       83 ms     23.8 us/node
javascript   24,890 B   14,001 nodes      987 ms     70.5 us/node
javascript  102,890 B   56,001 nodes   25,426 ms    454.0 us/node
rust          6,904 B    3,010 nodes       61 ms     20.3 us/node
rust        118,904 B   48,010 nodes    5,005 ms    104.3 us/node
rust        500,904 B  192,010 nodes   65,615 ms    341.7 us/node
```

### The witness: identical bytes, identical nodes, 4.4x from order alone

This is the one to hand over, and it is now committed rather than found:
**`research/joinery/order/`** holds the pair, `tool/order.py` holds the
construction that makes it, and `python3 tool/order.py` is the gate that holds
the ratio. Two files of **152,010 bytes** producing **28,011 nodes** each; the
only difference is which end the 100 KB single token sits at.

```
4000 statements, then a 100 KB string literal     16,503 ms
a 100 KB string literal, then 4000 statements      3,742 ms      4.4x
100 KB string literal alone                           11.8 ms
4000 statements alone                              3,626 ms
```

Reading that tail **after** 28,001 tokens costs 12,877 ms. Reading the same tail
**first** costs 116 ms. **111x for the same bytes.** The cost of scanning a byte
is proportional to how much has already been read, which is exactly the shape
that makes the whole parse quadratic.

### What separates the fast grammars from the slow ones

The order effect is not universal, and what it tracks is checkable:

All five now carry the swing as a measured row rather than two of them carrying
a dash, because that column is the thing that separated the two groups and it is
the cheapest early warning if a fix only helps javascript. From
`python3 tool/order.py`, best ratio of two replicates each:

| grammar | blind externals | order swing | many-then-one | one-then-many | 128 KB throughput |
|---|---:|---:|---:|---:|---:|
| rust | 3 | **4.0x** | 3,779 ms | 933 ms | 3,151 ns/B |
| typescript | 4 | **4.0x** | 7,974 ms | 1,985 ms | 49,337 ns/B |
| javascript | 2 | **3.8x** | 16,175 ms | 4,232 ms | 39,760 ns/B |
| json | 0 | 0.9x | 9 ms | 10 ms | 114.7 ns/B |
| java | 0 | 0.8x | 2,368 ms | 2,956 ms | 487.6 ns/B |

**Both grammars with zero blind externals are flat; all three with blind
externals swing about 4x.** The separation is total, and it is now the two
groups rather than three rows and two dashes: java, which had no measured swing
before, lands at 0.8x beside json's 0.9x. Neither has any order effect to find.

I want to be exact about how strong that is: presence separates the two groups
cleanly, and **count does not order them inside a group** - rust has three blind
terminals and is 12x cheaper than javascript's two. So the blind-external
machinery is where I would look first, and it is not proven to carry the whole
magnitude.

### The gate, and the surface that would have hidden this forever

The pair used to be two files in `/tmp`. It is now
`research/joinery/order/{many-then-one,one-then-many}.js`, written by the same
construction in `tool/order.py` that the gate re-derives them from, so a fixture
that drifts from its generator is caught by `order.py verify` in the job that
has no toolchain to wait on. The committed bytes are byte-identical to the two
files this finding was originally made on.

The gate asserts a **ratio, not a duration** - two parses on the same machine in
the same process, over the same bytes and the same nodes, differing only in
order. The ceiling is **1.6x**, taken from what the flat grammars already
achieve: json ran 0.96 / 1.01 / 1.00 over three replicates and java ran 0.88 /
0.96 / 0.99, so 12% is the widest excursion without the defect, and 1.6x leaves
about five times that in headroom against the 4.3x load swing that moved four
wall-clock rows elsewhere in this report. Today's tree fails it at 2.8x to 4.1x.
It is `continue-on-error` in CI for the same reason rung 1 reports its thirty
refusals without blocking - the defect is owned and being fixed - and that comes
off the day all five rows are under the ceiling.

**`lex` is a false-negative surface for this entire class, and that is the trap
worth writing down.** The bare lexer over the same 152,010 bytes:

```
joints lex  many-then-one.js      46 ms
joints lex  one-then-many.js      47 ms      1.0x
joints parse many-then-one.js  16,175 ms
joints parse one-then-many.js   4,232 ms     3.8x
```

Flat, and **350x** cheaper than the slow order of the same bytes. The defect needs the per-position admitted
set that the parse loop supplies, and the lexer has none to supply, so a gate
built on `lex` would have looked exactly like health while `parse` stayed
quadratic - forever. The gate goes through `stamp.ask`, which parses, and it
re-runs the lexer over the worst pair on every run and prints both, so the trap
is demonstrated on each invocation rather than recorded once here and forgotten.

One thing the gate cannot do is prove the ratio means what it says, so it checks
the construction instead of trusting it: bytes and node counts are re-compared
on every run, and if the two orderings ever stop matching, it says the pair
proves nothing and to fix the construction - rather than reporting the ratio as
a defect. Holding bytes constant is not holding work constant. That sentence is
the reason for the retraction above, and it is the reason this pair is checked
on both axes rather than one.

### What prices a position is walk length, and it came from the other lane

I had started measuring whether per-position cost tracks the size of the
admitted set - java and json are both flat under the order test, yet java cost
217x more per byte, so "flat" and "fast" are plainly not the same property and
`|admitted|` was the obvious suspect. **That measurement is withdrawn**, because
the scanner lane answered the question by mechanism instead, and a mechanism
beats a rank correlation over eleven points every time.

`Munch` groups the slate into **voices**, each a union DFA over up to 64
patterns, and the walk exits only at the union's dead state. `permitted` filters
which accepts are *recorded*; it never bounds how far the walk *runs*. So if any
one member of a voice stays alive to end-of-file, every pattern sharing that
voice pays a walk to end-of-file - **including when the permissive member is not
permitted at all**. In javascript the member is
`unescaped_single_jsx_string_fragment`, `([^'&]|&[^#A-Za-z])+`, which excludes
two bytes and therefore survives to EOF on almost any file, and it shares a
voice with `return`, `throw`, `=`, `[`, `]`, `case`, `class`, `function`, `=>`
and `new` - the terminals a statement parse asks for at nearly every position.

Per-position cost is therefore governed by **walk length, set by voice
composition**, not by how many terminals are permitted. A correlation against
admitted-set population would at best have found a confound: grammars with big
admitted sets tend to have more voices and more chances to contain a permissive
member, which is a different fact wearing the same shape. Anyone tempted to
re-run it should read this paragraph instead.

**And it finally explains the 350x `lex`/`parse` split**, which read as
impossible for weeks. With everything permitted, the to-EOF match is both
recorded *and taken*: the file is swallowed in a handful of enormous wrong
tokens and there are about **ten positions in the whole file**. With a narrow
`allow`, the identical walk happens, the giant match is discarded, the parse
takes a three-byte keyword, advances three bytes, and pays the same to-EOF walk
again - about **28,000 times**. `Expected` never made a call cost more. It made
the correct number of calls, and every one of them was always this expensive.
That is why `lex` is a false-negative surface for this class, and it is a better
reason than the one recorded above it.

### The synthetic table is per-grammar, not real code, and not java's alone

The other half of the question stands on its own and is answered:
`python3 tool/likeness.py` prices every corpus grammar twice on one axis - real
corpus code inflated to the throughput target, and the generated half of its
order pair - and asks whether the generator measures something real code does
not. Five grammars read both files whole and are the only ones counted; the rest
mended on real code, which is less work than a whole parse and not the same job
priced twice.

| grammar | real ns/B | generated ns/B | gap |
|---|---:|---:|---:|
| rust | 932 | 25,563 | **27x** |
| java | 715 | 12,847 | **18x** |
| javascript | 42,917 | 137,594 | 3x |
| typescript | 50,818 | 54,925 | 1x |
| json | 183 | 100 | 1x |

**Neither pole.** java's self-discrepancy is real and it is not java's - rust is
worse - and it is not universal, because typescript and json price generated
code the same as real code. So an absolute number taken off the generated table
needs a **per-row** caveat, not a blanket one, and no grammar's gap is evidence
about another's. A second run an hour later on a differently-built binary moved
every magnitude (rust 153x, typescript 0x) and left that shape intact, which is
the only part worth quoting.

**The 217x was the fixture, not the grammar.** On real corpus code java costs
715 ns/B against json's 183 - **3.9x**, and `bench.py`'s own independent figures
(487.6 and 114.7) put it at 4.3x. Nothing like 217x.

#### java has three numbers on three corpora. Quote the second one.

They are all true and they are answers to different questions, so anyone
arguing from one of them should have to say which:

| number | corpus | what it prices | quote it? |
|---|---|---|---|
| **217x** vs json | `research/joinery/order/*.js`-style generated statements | four thousand statements of one shape, which real java never writes | **no - retracted.** It measures the generator |
| **3.9x** vs json | `.local/bench/in/java-105.java`, real 128 KB of java | java as a language costs about four times json | **yes.** This is the one |
| **9.4x** | the scanner lane's own walk-length harness | mean bytes walked per scanner call, before its mask | no - it is a scanner-internal unit, not ns/B, and not comparable to either above |

The trap is that all three are "java against json" in shape, so they read as
three attempts at one measurement where they are three measurements. **3.9x on
real corpus code is java's cost.** The 217x is the fixture's, and it is
retracted above rather than deleted so the retraction stays findable. The 9.4x
is the lane's and belongs beside its other walk-length figures, not in a ns/B
table.

### A prediction, recorded before the fix lands

Written 2026-08-05, while the scanner lane is building the reachability mask and
before any of it is in a binary I have measured. It is here rather than in a
message because a prediction made in advance is worth more than any amount of
explanation afterwards, and because a fix that lands without one can always be
narrated into a success.

The real-code column above separates cleanly along one line, and it is the same
line the order swing separated on:

| grammar | real ns/B, today | blind externals | predicted after the mask |
|---|---:|---|---|
| javascript | **42,917** | yes | **700-900**, a collapse of one to two orders |
| typescript | **50,818** | yes | **700-900**, same |
| rust | 932 | no | barely moves |
| java | 715 | no | barely moves |
| json | 183 | no | barely moves |

The mechanism says this and not something weaker. `unescaped_single_jsx_string_fragment`
survives to end-of-file and shares a voice with the terminals a statement parse
asks for at nearly every position, so javascript pays a to-EOF walk about 28,000
times over a 128 KB file. Bound the walk and that cost is not reduced, it is
**removed**, which is why the prediction is a collapse to the band of the
grammars that never had the defect rather than a percentage improvement.

**What each outcome means, decided now rather than after seeing the number:**

- **javascript and typescript land in the 700-900 band.** The throughput axis
  had one defect and it is closed. The remaining 60x-280x spread on real code
  was this and nothing else.
- **They improve but stall an order of magnitude high** (say 4,000-8,000 ns/B).
  The mask bounds the walk but something still scales - a second defect on the
  same axis, and `order.py`'s ratio is the instrument that will still be red.
- **They barely move.** The mask is not on the path the parse loop takes, and
  the 98.2% profile attribution needs re-taking on the new binary before
  anything else is designed.
- **rust or java move materially.** Unexpected in either direction and worth a
  look: they have no blind externals, so a large change means the mask touched
  something the mechanism does not describe.

`python3 tool/likeness.py` is the re-run, and it prices real code beside
generated in one pass, so the same command answers the prediction and re-checks
the fixture bias. The comparison must be against **this table**, not against the
generated column, which carries a per-grammar caveat the real column does not.

### Collected: the prediction is met, and collecting it found a second defect

The mask landed. Measured on `joints 60f59cb48`, real corpus code, marginal
cost (the small corpus file's time subtracted from the 128 KB file's, so the
grammar import both pay is not charged to either):

| grammar | predicted | before | **after** | move | |
|---|---|---:|---:|---:|---|
| javascript | 700-900 band | 42,917 | **320** | **134x** | met, and below the band |
| typescript | 700-900 band | 50,818 | **478** | **106x** | met, and below the band |
| rust | barely moves | 932 | 608 | 1.5x | met |
| java | barely moves | 715 | 267 | 2.7x | met in kind, larger than "barely" |
| json | barely moves | 183 | 64 | 2.8x | met in kind |

The 60x-280x spread that made javascript and typescript outliers on real code
is **gone**. Every grammar now sits between 64 and 608 ns/B, and the two blind-
external grammars are no longer at the top of the table - they are at the
bottom. That is the throughput axis' single largest defect, closed, and the
prediction that it would close was on the page before the fix was.

Two honest caveats, neither of which changes the verdict:

- **These are marginal costs.** Charging grammar import to the file instead
  gives javascript 1,138 and typescript 3,724 ns/B - still a 38x and 14x
  collapse, but only javascript lands near the band. The `before` numbers were
  taken through a folio, which pays no import, so marginal is the like-for-like
  comparison and total-with-import is the pessimistic one. Both agree the
  collapse happened; they disagree about the last factor of three.
- **The machine was loaded.** Several concurrent builds were running. Ratios and
  collapses survive that; the absolute ns/B should be re-taken on a quiet
  machine before anyone quotes a single number out of this table.

### The fix is live on one path and absent on the other - a folio does not carry it

Collecting the prediction took four wrong readings first, and the reason is a
defect worth more than the prediction was.

**Same binary, same file, two ways of naming the grammar:**

```
joints parse upstream/grammars/javascript.json  many-then-one.js   0.14 s
joints parse <a folio minted by that same binary> many-then-one.js  15.40 s
```

**110x, from the same executable.** The reachability mask is applied when a
grammar is imported from `grammar.json` and is **not carried into a minted
folio**. A folio pressed by the fixed binary still parses at the pre-fix cost.

That is why the scanner lane measured `slow.js` at 165 ms and every instrument
in this directory measured 15.7 s on the same afternoon: `bench.py`,
`order.py`, `likeness.py` and `walls.py` all parse through a folio, because a
folio is the artifact the product ships. Neither measurement was wrong. They
were of two different code paths, one of which has the fix.

**It is the folio path that matters for the product**, since minting is the
whole point of pressing a grammar once and parsing many times. So the fix is
not collectable by a user until the folio carries it. Routing it to the scanner
lane as the same work rather than a new bug: whatever the mask is derived from
at import needs to be written into the folio and read back, or re-derived on
load.

The cheapest possible regression test already exists and would have caught this
on the day: `python3 tool/order.py` runs through a folio and still reports
javascript at 4.4x and 15,654 ms, while the grammar path is flat. Until those
two agree, the fix is half-landed.

#### Closed, 34 minutes later, and the folio is now the faster path

The scanner lane landed the round-trip. Same file, same command, binary
`79741763d` in place of `60f59cb48`:

```
                                          60f59cb48      79741763d
parse via upstream/grammars/javascript.json     0.14 s        0.14 s
parse via a folio minted by that binary        15.40 s        0.04 s
```

The folio now costs **less** than the grammar path, which is what a pressed
artifact was always supposed to do: it skips the import the grammar path pays on
every invocation. `order.py` is flat on **both** paths - ten rows, five grammars
times two ways of naming them, every swing 1.0x - and javascript's folio row went
15,654 ms to 45 ms. The whole gate now runs in 1.9 s where it took 50.

Two things this leaves behind rather than resolves. The gate now **keys each path
separately and judges each on its own**, because the obvious way to write it -
take the better of the two - would have reported 1.0x on the afternoon one path
was 4.4x, which is precisely the failure it exists to make impossible. And the
class is broader than the mask: anything derived at import and not written
through is the same shape, which is why dynamic precedence is being audited
beside it.

**And `folio_for` was compounding it.** It cached a folio forever, so every
instrument here was reading an artifact minted at 20:49 by a binary from before
the fix - a stale cache with no invalidation against the thing that produced it.
It now re-mints whenever the binary is newer. That one is mine, it is fixed, and
it is the same failure as the peel reading `reach`: an instrument quietly
answering about a different tree.

**What that costs my own gate, stated rather than buried.** `order.py` proves
superlinearity on a synthetic pair, and that proof stands: the ratio is between
two orderings of the *same* generated bytes, so a construction unlike real code
cannot forge it. But rust reads real code at 932 ns/B, better than java, while
its generated pair costs 27x that - so for rust the gate is catching a
superlinearity real rust barely pays. For javascript and typescript the two
agree, real code being independently catastrophic at 42,917 and 50,818 ns/B, and
there the gate measures the thing that hurts. The gate keeps all five rows
because a fix must hold on all of them; it is not a claim that all five are
equally broken on real input.

### A shrinking family beside a growing total is what a real fix looks like

Written here rather than only in the wall board, because the next person to see
the total go up will not derive it and the obvious reading is a regression.

Re-surveying the walls after the mask landed: **permissive body pattern fell
105 → 33 while the total rose 257 → 269.** Both numbers are the same event. A
pattern that no longer swallows to end-of-file stops being refused *and* stops
hiding what is behind it, so the parse reaches further into every file and meets
walls that were never previously reachable. The fix closed two thirds of the
family it targeted and paid for it by exposing terrain.

This is the final argument for quoting **families and the rate, never the
total**: under the total metric, the largest win of the night reads as a
regression of twelve. A total counts what the parse has *met*, which rises as
the parser gets better; a family counts distinct causes, which is the thing that
falls when one is fixed.

### Five hypotheses tested and discarded

So nobody re-runs them:

- **ASI / line terminators.** Retracted above; newline count is flat at fixed
  bytes and nodes.
- **Mending.** All five throughput grammars parse **whole, 0 mends, 1 root**.
- **Folio size.** rust's folio is 2x javascript's and parses 40x faster.
- **Identifier vocabulary.** One distinct identifier against 4,000, at fixed
  bytes and nodes: 3,564 ms against 3,772 ms. 6%.
- **Sibling count at one level.** 4,000 siblings in one group against 400 groups
  of ten, at fixed bytes and nodes: 6,942 ms against 3,106 ms. 2.2x - real, and a
  rounding error against 111x.

### The whitespace pathology now shares a signature with this

A file of nothing but whitespace is quadratic under the rust folio:

```
 25,600 B of whitespace       295 ms
102,400 B                   4,346 ms
409,600 B                  73,393 ms      16x bytes -> 249x time, n^2.0
```

Space, tab, newline and CRLF cost the same; json is 102 ns/B where rust is 44,610
and javascript is 409,850 - **the same json-against-the-rest split as the order
test**. I logged this as a separate finding last pass because collapsing
whitespace in a real rust file changes nothing (144 ms to 139 ms). It may still
be separate, but it now shares a signature with the main defect and should be
retested against the same fix rather than chased on its own.

## Closed, 2026-08-08: both decision axes now sweep

Everything in the section below this one is history. The two axes it documents
losing - the ones that decide adoption - were re-taken on a current binary and
both now go 9 of 9 to joints, every measurable grammar, no row excused:

| axis | span | ratio | worst row | best row |
|---|---|---:|---|---|
| throughput | 9 grammars | **0.64x - 0.97x** | cpp 72.8 vs 74.8 ns/B | json 32.8 vs 51.6 ns/B |
| incremental | 9 grammars | **0.17x - 0.85x** | json 86.5 vs 101.2 us | c 87.0 vs 517.4 us |

```
stamp: joints 7a109218d built 2026-08-08T21:26:30Z · tree-sitter 0.26.11
tool/bench.baseline.json re-recorded from this run: 60 rows over 7 axes, 50 to joints
```

The 724x typescript throughput and the 153.8x typescript incremental below both
fell to the chain of fixes this pass landed, in cause order:

- **The quadratic scan died with the `Expected` rebuild.** A state's slate is
  memoized per stack context (`Slate`/`Record`, 16-way associative, walk answers
  in a 512-bit mask), and the permission set a veil describes is interned once
  as a whole `Expected` (`Look`) and worn **by pointer** - the scan reads the
  snapshot where it lies, so a token under a known veil copies nothing at all.
- **`reduce` stopped paying the round trip through `born`.** In a lone parse the
  popped runs already tile `borne` in order, so a fold with no alias applies
  fields in place - a left-recursive list is O(n) in its own length now, not O(n²).
- **`roost` rebuilds only the divergence.** A `keel` watermark pins where the
  readings forked; a conflict refuted three tokens after it opened repays three
  tokens of copying, not the whole stack - which it was doing 5,015 times over
  one 129 KB C++ file.
- **The lexer's per-byte loop lost two branches.** Pattern attribution is a
  dense O(1) row instead of a run scan, and the final-byte table selection was
  hoisted out of the DFA walk.
- **Incremental was a different defect** - the veil replay in `holds`
  (round 22) plus the `torn` fix already documented below - and the numbers
  above are what those are worth once the throughput chain stopped hiding them.

Two consequences worth naming. The startup axis unblocked itself - the section
below that says it is "blocked behind the throughput defect" is now stale, and
it measures: 7 of 9 to joints, tree-sitter keeping rust (1.35x) and typescript
(1.55x), which is folio-mapping cost and a real open row. And memory is now the
one axis tree-sitter wins broadly (7 of 9, worst typescript 2.67x) - the memo
structures above are not free, and nobody has spent a pass on them yet. Both are
in the re-recorded baseline with their real numbers.

`tool/order.py run` holds the complexity claim the first fix makes: same bytes,
same nodes, opposite order, every swing at or under 1.6x - the parse is linear
in what it has read.

## Where we lose (superseded 2026-08-08 - kept as the record of the defect)

Two sweeps, and the second is the one to read. `incremental` was re-taken on a
current binary after the `torn` fix; `throughput` has not been re-taken since the
mask reached the folio, and the marginal re-measurements in the path audit show
where it now stands. Superseded rows are struck rather than deleted.

| axis | case | ours | theirs | ratio |
|---|---|---:|---:|---:|
| incremental | typescript @98% | 66,224 us | 430.6 us | **153.8x** |
| incremental | rust @98% | 1,847 us | 261.6 us | **7.1x** |
| incremental | java @98% | 574.5 us | 191.0 us | **3.0x** |
| incremental | javascript @98% | 527.5 us | 445.2 us | **1.2x** |
| incremental | json @98% | 93.0 us | 104.0 us | 0.89x |
| ~~incremental~~ | ~~typescript @98%, pre-`torn`~~ | ~~9,210,623 us~~ | ~~625 us~~ | ~~14,746x~~ |
| ~~incremental~~ | ~~javascript @98%, pre-`torn`~~ | ~~4,706,895 us~~ | ~~468 us~~ | ~~10,066x~~ |
| ~~incremental~~ | ~~java @98%, pre-`torn`~~ | ~~64,314 us~~ | ~~197 us~~ | ~~326x~~ |
| throughput | typescript 128 KB | 52,614 ns/B | 72.7 ns/B | **724x** |
| throughput | javascript 128 KB | 39,760 ns/B | 69.0 ns/B | **576x** |
| throughput | rust 128 KB | 3,151 ns/B | 67.3 ns/B | **46.8x** |
| throughput | java 128 KB | 487.6 ns/B | 61.8 ns/B | **7.9x** |
| throughput | json 128 KB | 114.7 ns/B | 100.2 ns/B | 1.14x |
| memory | typescript 128 KB | 17,367,040 B | 15,024,128 B | 1.16x |

**The incremental defect is a second, different defect from the quadratic, and
the cleanest evidence was java itself.** java has **zero blind externals** and no
order effect, so it was nowhere near the quadratic above - and its incremental
was still 326x, a first keystroke of 63,912 us against a 64,425 us cold open,
**99.2%**: the edit reparsed the file. javascript was 94.0%, rust 1.0%.

**Superseded: those three numbers were pre-`torn`.** Re-taken on a current
binary, java is 1.6% and javascript 1.1%, and the argument they were used to make
survives intact - the incremental defect really was independent of the
throughput one, which is why fixing the mask did nothing for it and fixing
strands did everything. What remains is typescript at **88.4%**, carried as its
own row in handoff 3 below. It is probably a predicate, not an algorithm.

The one incremental row we win is one of the two grammars in the set with no
blind externals at all:

```
incremental json @98%     83.0 us    vs    104.0 us     0.80x
```

## Where we win

| axis | span | ratio | what it is |
|---|---|---:|---|
| press | 11 grammars | **0.01x - 0.50x** | grammar.json to a usable parser. ruby 148 ms vs 12,429 ms; cpp 359 ms vs 19,762 ms |
| artifact | 11 grammars | **0.14x - 0.68x** | folio vs compiled `.so`. cpp 779,024 B vs 5,636,440 B - 7.2x smaller |
| install | tooling | **0.19x** | one binary + N folios (6.4 MB) vs the CLI + N dylibs (34.3 MB) |
| install | runtime | 0.45x | our whole binary stands in for a library we do not ship yet, so this flatters *them* |
| memory | 4 of 5 | 0.60x - 0.98x | peak RSS per parse |

The artifact win is structural rather than incidental: we never emit or compile
C. cpp's grammar is 25,860,012 bytes of generated C on their side against
779,024 bytes of folio on ours, and the same folio deflates to 229,205 B.

**press is the widest gap on the board and nobody asked about it.** 0.01x on ruby
means a grammar change is a 148 ms edit-compile loop instead of a 12.4 second one.

## Not measurable, and why

`startup` was skipped on every grammar but one. It is a fixed cost subtracted
from a slope, and where the parse is slow the subtraction is noise:

```
startup javascript   skipped: the 5,239 ms parse swamps the fixed cost (-207 ms, +-809%)
startup typescript   skipped: the 6,922 ms parse swamps the fixed cost (-174 ms, +-1499%)
startup rust         skipped: the   416 ms parse swamps the fixed cost (-183 ms, +-75%)
```

The one that survived, on the second sweep only, is
`startup json 128 KB = 4.124 ms, ratio 0.65`. One row is not an axis. **The
startup axis is blocked behind the throughput defect** - it becomes measurable
the day the quadratic scan is gone and not before. Three honest "skipped" lines with
the arithmetic on them beat a published negative duration.

Six grammars are skipped from the timing axes outright because joints stops
early on the 128 KB file - bash, c, cpp, go, python, ruby - each with its wall
printed on its row. **The throughput table is the five grammars we can parse
whole, which is the flattering subset.** Read it that way.

## Taken twice

| | sweep A | sweep B |
|---|---|---|
| binary | `b507c8f4b` | `cb6322624` |
| source | `6299a98a6` | `bda7ca06f` |
| repo | `f6018936c+28` | `f6018936c+30` |
| load | 14.5 | 61.7 |

**The two sweeps are not the same tree, and the stamp is what said so.** Another
lane's `src/kernel/lex/scanner.zig` landed between them; both runs also printed
`MOVED` naming the file that moved underneath them. So this is a weaker check
than the census's one-byte-different double take, and calling it the stronger one
is precisely what this dossier exists to prevent.

35 of 39 guarded numbers held across a **4.3x change in machine load**. Four
moved past slack:

```
press/cpp                     0.0181 -> 0.02416
press/typescript              0.1026 -> 0.2041
throughput/javascript 128 KB   576.2 -> 729
incremental/rust @98%          4.973 -> 8.528
```

All four are wall-clock rows. Every ratio row that carries an argument held
inside 8%: memory within 4.3%, incremental json/java/typescript within 3.2%,
throughput typescript/json/java within 8%. That a 4.3x load swing moved four
rows and left thirty-five is the strongest evidence here that the ratios are
worth quoting and the absolute times are not.

## Which numbers are hardware-independent

**Independent.** Byte counts; these reproduce exactly on any machine with the
same two versions:

- the whole `artifact` axis - 11 rows of folio bytes against `.so` bytes
- the whole `install` axis - binary and dylib sizes
- the section breakdowns (`widest section groupref 23%`) and deflated sizes
- the mend, root and verdict columns behind every skipped row

**Nearly independent.** Ratios of two timings taken back to back on one machine.
Load cancels to first order, and the two sweeps agree within 8% across a 4.3x
load change:

- `throughput`, `incremental`, `press`, `startup` **as ratios**
- the **4.4x order swing** and the growth-law tables - same binary, same byte
  count, same node count, same minute, one variable moved
- the profile's **98.2% / 0.13% / 0.04%** split. Sample proportions within one
  run are a property of the code, not the clock
- the **blind-external table**. Zero against non-zero is a folio fact

**Laptop-specific; do not quote these off this machine:**

- every absolute duration: `9,210,623 us`, `18,237 ms`, `487.6 ns/byte`,
  `press ruby 148.3 ms`
- the whole `memory` axis. Peak RSS is allocator, page-size and OS dependent;
  `macOS-26.5.1-arm64 x16` with 16 KB pages will not match a 4 KB-page Linux
  box. The ratios travel better than the bytes, but I would not defend either
  across an OS boundary
- anything taken at load 14.5 or 61.7, which is all of it. There was a monorepo
  build on this machine throughout both sweeps

`bench.py` prints a `±` spread beside each timing, so a reader can see which rows
were quiet without taking my word for it.

## Which path each number is on

Until tonight nobody knew there were two, so no number in this file said. A
grammar can be named to `joints parse` two ways, and for one afternoon they
disagreed by 110x. Every number here is now labelled, because a report that
silently prices the dev path answers a real question nobody asked.

| Instrument | Path | What it feeds |
|---|---|---|
| `bench.py` | **folio** (press-skip checked) | every axis: throughput, artifact, incremental `@98%` relative, memory, press |
| `order.py` | **both**, keyed separately | the order swing and its ceiling |
| `likeness.py` | **folio** | real-against-generated, and the real-code ns/B table |
| `walls.py` | **folio**, parity-checked against grammar | the wall board |
| `breadth.py`, `resync.py` | **folio** | reach and mend counts |
| `census.py`, `recover.py`, `rung1.py`, `differential.py` | **grammar** | correctness against tree-sitter, where import cost is not being measured |

**So the performance axes were all on the folio path already** - the shipping
one. That is the reassuring half, and it is luck rather than design: `bench.py`
chose folios because a folio is what a user has, not because anyone knew the
choice was load-bearing.

**The uncomfortable half is that the exceptions were tonight's.** The
prediction-collection numbers - javascript 320 ns/B, typescript 478, the 134x
and 106x collapses - were hand-taken through `grammar.json`, and they are exactly
the numbers that looked good. They are labelled as such where they appear. Re-taken
on the folio path with the same marginal method, against `79741763d`, which now
carries the mask through the round-trip:

| grammar | grammar path | folio path |
|---|---|---|
| javascript | 335 ns/B | **322 ns/B** |
| typescript | 490 ns/B | **466 ns/B** |
| rust | 599 ns/B | **600 ns/B** |
| java | 260 ns/B | **266 ns/B** |
| json | 59 ns/B | **63 ns/B** |

Within measurement noise on all five, so **the collapse is real on the path that
ships** and nothing in the prediction section needs withdrawing. On real corpus
code through folios, `likeness.py` now reads 109-777 ns/B across eleven grammars,
javascript at 407 and typescript at 565 against the 42,917 and 50,818 recorded
before the fix. The 60-280x spread is gone on both paths.

**Everything above this section, dated before `79741763d`, is a folio-path number
taken while the folio did not carry the mask.** They are left standing rather than
restated: they are what the product actually cost, and the retraction habit here is
to mark rather than delete.

### An incremental number needs two labels, not one

Path is not enough on this one axis. The weave lane found its own incremental
numbers were taken at **absolute byte 100**, which is 7% of rust's file, 9% of
javascript's and 13% of json's - four different relative positions compared as
though they were one edit. And position is not a detail here, it is the dominant
term:

| rust, cut at | 1.4 KB | 5.7 KB | 23 KB | over 16x size |
|---|---:|---:|---:|---|
| 2% | 608 us | 2,731 | 10,788 | 17.7x - linear |
| 50% | 323 | 1,382 | 5,869 | 18.2x - linear |
| 98% | 187 | 260 | 355 | **1.9x - flat** |

Cost is the bytes *above* the cut, less what lifts recover. Below the cut is
reused, and reused correctly. So 2%, 50% and 98% are three different claims about
the same parser and all three are true.

**Every incremental row in this report is `@98%`, and the `%` is relative to that
file's length** - never an absolute byte. That is stated in `keystroke()` and it
was chosen because an edit near the bottom pays for every byte before it, which is
where an author actually types and the only position where an incremental parser
can quietly stop being one. On the weave lane's new table that is the *flat*
regime; its own measurements were in the linear one.

**So the rust anomaly is not reconciled here, it is declared incomparable.** Our
`rust @98%` at 1.0% of a cold open and weave's 64% differ in cut position *and*
in clock - ours is read off each side's own instrumented edit counter, over 25
insert/delete pairs, because differencing two 20 ms process runs to find 40 us
comes back negative on a loaded laptop. Two numbers that differ in two dimensions
should not be talked into agreeing. Weave's own 98% row for rust is 187 us against
a 1,002 us open, or 19%.

**What this does not excuse.** typescript at **88.4%** of a cold open is an
`@98%` row in the flat regime, where java, javascript, rust and json all cost
under 3% on the identical harness. Position does not explain it, and the weave
lane's measured fixed cost of 13-16 us cannot either. (java's 99.2% and
javascript's 94.0% *were* on this list and are now 1.6% and 1.1% - stale, not
position-confused.) That row stands as its own defect, and with the fixed cost
now shown not to exist, **lift granularity is the ranking** for incremental work
rather than an item queued behind it.

### The folio rows are folios, checked rather than assumed

A folio path that quietly re-pressed would hand back the grammar path's numbers
wearing a folio label - the same class of error as everything else found tonight,
and invisible in the output. The press-skip timing says which:

```
mint javascript.json -> a folio                       0.12 s
parse via grammar.json  (pays the import every time)  0.14 s
parse via that folio                                  0.04 s
```

A silent re-press cannot cost **less** than the press. At 0.04 s against a 0.12 s
mint the press is genuinely skipped, so these rows are folio rows.

### The 15.40 s is historical, and that settles a non-reproduction

The weave lane could not reproduce the 110x split on any of its four grammars via
`amend`, and reported it as a non-reproduction rather than a contradiction. Of its
two live explanations - those grammars not carrying the import-derived fact, or
the round-trip fix having landed underneath it - **it is the second.** Same file,
same command, same machine:

```
60f59cb48 (05:17Z)   folio 15.40 s   grammar 0.14 s
677643927 (05:38Z)   folio  0.04 s   grammar 0.14 s
```

So there is no blast radius to map: no grammar carries the dependency any more.
The 15.40 s stays on the page as what the product cost for one afternoon, marked
rather than deleted.

## Handoffs

### 1. Scanner lane, `src/kernel/lex/scanner.zig` - the parse is quadratic and the time is in `reach`

**The claim.** Scanning a byte costs in proportion to how much has already been
read, which makes every parse quadratic. It is not ASI, not newlines, not
mending, not folio size, not vocabulary, not sibling count - all five are
measured and discarded in the section above.

**Where.** 98.2% of 2,354 samples land under `Scanner.read` at
`scanner.zig:801`, which is `s.reach(...)`, into
`Munch.longestAmong`. `s.refusing(...)` on line 799 is *not* the hot line, and
`gather.fold` takes 0.13%.

**The witness, and the check that says you are done.** It is committed now, so
nothing here depends on a `/tmp` that a reboot empties:

```
python3 tool/order.py            # all five grammars, held to a 1.6x ceiling
python3 tool/order.py --grammar javascript --calibrate --reps 3
```

The pair is `research/joinery/order/{many-then-one,one-then-many}.js` -
**152,010 bytes each, 28,011 nodes each**, differing only in the order of their
two halves, and byte-identical to the files this was found on. Same bytes, same
nodes, **3.8x-4.4x**. Isolated, the tail costs 12,877 ms when it follows the
statements and 116 ms when it precedes them - **111x**.

**This needs no instrumentation to read.** When the ratio comes back under 1.6x
on all five rows the defect is gone, and the two flat grammars in the same table
are what tells you the gate itself still works. Do not check it with `lex`: the
same pair through the bare lexer is 46 ms and 47 ms today - flat in *both*
orders, 350x cheaper - because the
lexer never sees the admitted set this defect lives in.

Taken four times, across three binaries, because the scanner lane rebuilt twice
while this was being written and the stamp caught it: `16,516 / 3,749 = 4.4x`
and `17,035 / 3,636 = 4.7x` on `joints f6419542c`; `18,103 / 3,667 = 4.9x` and
`16,026 / 5,732 = 2.8x` on `17ab2293d`; `16,175 / 4,232 = 3.8x` on `4bcfadacc`.
All five at 152,010 B and 28,011 nodes. The spread across binaries is the honest
reason the ceiling is 1.6x rather than 1.2x. The **ratio** is the number to
hold; the absolute milliseconds are laptop-specific.

**The counter that will tell you it is fixed.** Two, and the first is enough:

1. **`python3 tool/order.py` green on all five rows.** Today three of them are
   2.8x to 4.1x apart against a 1.6x ceiling. This needs no instrumentation at
   all, and it is wired into CI so it cannot quietly come back once it goes.
2. **Mean walk length per `reach` call**, which the scanner lane is already
   printing before and after its fix. That is the quantity the mechanism names,
   so it is the one that closes rather than corroborates.

**And the mechanism is no longer mine to guess at.** The scanner lane found it:
voice composition sets walk length, one permissive member surviving to
end-of-file makes every pattern sharing its voice pay a to-EOF walk, and
`permitted` filters what is *recorded* rather than how far the walk *runs*. The
section above carries it in full, along with the reason the `lex`/`parse` split
is 350x. The admitted-set correlation I had queued behind this is **withdrawn**,
not merely negative: it would have measured a confound, since a grammar with a
large admitted set has more voices and more chances to hold a permissive member.

**The narrowing that is yours to confirm or refute.** Every grammar with zero
blind externals is flat (json 0.9x order swing, java 0.8x); all three with blind
externals swing about 4x (rust 4.0x, typescript 4.0x, javascript 3.8x). All five
are now measured rows in `order.py` rather than three rows and two dashes, so if
a fix helps javascript and leaves rust alone, that shows up in the same table on
the same run. Presence separates the groups, count does not order them within
one, so the blind-external stand-in machinery is the first place to look and is
**not proven** to carry the whole magnitude.

### 2. Parse loop - ruled out as the site, not yet as the origin

The fold path is 0.13% of samples, so the time is not being spent there. But
`reach` is handed its `Expected` **by the parse loop**, once per position per live
limb, and neither of the two shapes below is excluded by anything I measured:

- the scanner is called the right number of times and each call has grown, or
- each call is cheap and the loop is making more of them as limbs accumulate.

Counter (1) above distinguishes them in one run. If calls-per-byte is flat and
`allow` has grown, it is wholly the scanner's; if calls-per-byte climbs, the
origin is the loop even though the time shows up in `lex`.

### 3. Weave - the incremental path engages on four grammars and not on typescript

**Two thirds of this handoff was a stale table, and saying so is the finding.**
It previously read "does not engage at all on java or javascript", off java at
99.2% of a cold open and javascript at 94.0%. Those were taken before the `torn`
fix gave each live reading its own strand; before it, java built no tiling at
all, so 99.2% is precisely what a cold parse per keystroke looks like. On a
binary built in the last hour, at the same `@98%` relative cut, **java is 1.6%
and javascript 1.1%** - beside rust's 2.7% and json's 1.7%.

**What survives is typescript, alone, at 88.4%** - a 66,497 us first keystroke
against a 75,206 us cold open, 153.8x tree-sitter. The shape is unchanged: fine
on the cold path, near-total re-read on the warm one, with four grammars on the
identical harness doing it right. That still reads as **a predicate rather than
an algorithm** - a guard deciding this edit cannot be spliced and falling back to
a full re-read - and the question is now much sharper than it was, because it is
one grammar rather than three and typescript's difference from javascript is a
short list. Counter: whether the re-mint window widens to `whole` on typescript,
and what condition widens it.

**Position does not explain this one, which is worth saying because it explains
the neighbouring anomaly.** All five rows are `@98%` **relative** to each file's
own length, so typescript is compared with the four that work at the same
relative cut, in what the weave lane's position table shows is the *flat* regime.
The rust-versus-weave disagreement was two different cut positions; this is not.
And the fixed per-amend cost that might have absorbed it is measured at 13-16 us,
which cannot account for 66,497. **Lift granularity is therefore the ranking for
incremental work**, not a lever queued behind a fixed cost that does not exist.

**Two caveats on the re-take, since it is one run.** `MOVED` fired - a lane
changed `src/kernel/quire/gather.zig` during the 114 s the sweep took - so this
describes a tree that was moving, and the binary is `bench.py`'s own ReleaseFast
build (`c42e5259c`), which is why `TOLD` fires by design. Both are on the run's
own last line rather than reconstructed here. The ratios are large enough that
neither changes the conclusion, but typescript at 88.4% deserves a second take
on a quiet tree before anyone sizes work from it.

### 4. Press or scanner - pure whitespace, probably the same bug as 1

A file of nothing but whitespace is quadratic under the rust and javascript
folios (`n^2.0`, 409,600 B in 73 s) and linear under json's (102 ns/B) - **the
same json-against-the-rest split as the order test**. Retest it against the fix
for 1 before chasing it separately. I have not proven they are one bug and am not
claiming it.

## Reproducing

```
python3 tool/bench.py run       # every axis
python3 tool/bench.py verify    # and hold them to tool/bench.baseline.json
python3 tool/bench.py list      # the axes, and which grammars each one can run

python3 tool/order.py           # the order swing, all five, held to 1.6x
python3 tool/order.py status    # the same table, gating nothing
python3 tool/order.py verify    # the committed pair is what the construction makes
python3 tool/order.py --calibrate --reps 3   # the spread the ceiling came from
```

`bench.py` builds and stamps its own ReleaseFast binary under `.local/bench/build`,
so `TOLD` fires on every run by design and the stamp names both that binary and
the tree's own. A benchmark taken against a scratch build says so on its own last
line.

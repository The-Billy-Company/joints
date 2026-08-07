# C++ - the reading tree-sitter takes was never on the table

**The sentence.**

> We build `declaration` over a `parenthesized_declarator` where tree-sitter
> builds `expression_statement` over a `call_expression` and an `argument_list`.
> We read every unqualified call as a declaration of a variable whose type is
> the callee - C++'s most vexing parse, resolved the wrong way every time.

**And the sentence behind it, which is the one that matters, because the first
one reads like a ranking bug and it is not.**

> At the cell that decides it, **three** readings of a bare `identifier`
> complete at once - `_declarator`, `type_specifier` and `expression` - and a
> contested cell records exactly **one** loser. So the runtime forks, correctly
> and on purpose, into the two *declaration* readings, and the expression
> reading is dropped with no record that it existed. The fork is binary; the
> ambiguity is ternary. Nothing downstream of that cell can recover a reading
> that was never a strand.

That is also why the dynamic-precedence lane moved cpp zero bytes, and the
non-result is now a positive finding rather than a puzzle: dynamic precedence
**orders the readings that are on the table**. Both of cpp's are declarations.
No ranking of two declarations produces a call.

---

## Where these numbers come from

Two arms, each with its own binary, its own folio cache and its own oracle seat
(third house rule), and each sighted before use:

| arm | binary | tree | oracle |
|---|---|---|---|
| `pin-fz-control` | `b2c0a6696ed7`, built 05:51Z | `fb23995200c6` · repo `f7ba40004774`+136 | `d85e736faf9d`, tree-sitter 0.26.11, **30 of 30 verdicts live** |
| `pin-cpplane` | built later the same session | same repo, later | same oracle digest, 30 of 30 |

**`pin-fz-control` reproduces the row in the brief exactly**, which is how I know
which board the brief was quoting:

```
cpp   unexpected " at 690 in state 907, 36 roots, mended 6 over 6B
rack  size 1408 · built 997 · square 185 · askew 589 · racked 2 · unframed 217
      ours 145 · theirs 391 · shared 115 · recall 0.2941 · crooked share 59.5%
```

36 roots, 6 mends over 6 bytes, `"` at 690 in state 907, ~29% recall. Every
number below is from that arm unless it says otherwise.

---

## 1. What the crooked bytes are

The whole file is a confound, so the answer comes from a minimal pair instead
(`vexing.py`, fourteen probes, each about one token from its neighbour). The
smallest input that is wrong is **nineteen bytes**:

```cpp
void g() { f(y); }
```

| ours | tree-sitter's |
|---|---|
| `declaration [11:16]` | `expression_statement [11:16]` |
| `  type_identifier [11:12]` | `  call_expression [11:15]` |
| `  parenthesized_declarator [12:15]` | `    identifier [11:12]` |
| `    ( [12:13]` | `    argument_list [12:15]` |
| `    identifier [13:14]` | `      ( [12:13]` |
| `    ) [14:15]` | `      identifier [13:14]` |
| `  ; [15:16]` | `      ) [14:15]` |

Same spans, byte for byte, to the leaf. Only the parents differ. That is
`racked` by definition - and this file parses **whole, one root, zero damage**.
Nineteen bytes of a perfectly healthy `damage` column over a tree that disagrees
with the oracle at every interior node of the statement.

The fork is offered by the **callee's shape**, not by the argument's:

| probe | verdict |
|---|---|
| `f(y)` | parses; **wrong tree**, as above |
| `f(1)` · `f("x")` · `f(y, z)` · `f(y, "x")` | **wall** |
| `a.f("x")` · `std::f("x")` | parses, **byte-identical to the oracle** |
| `int f(y);` (a real declaration) | parses, correct |

A `field_expression` or `qualified_identifier` callee cannot begin a declarator,
so no fork is offered and those calls are right today. A bare identifier callee
always takes the declaration reading. When the argument happens to be
declarator-shaped (`f(y)`) the declaration reading is *legal* and the parse
finishes, quietly wrong. When it is not (`f(1)`, `f("x")`) there is nothing to
back out to and the parse walls.

**On today's binary the same event surfaces under different labels**, which is
worth knowing before anyone quotes a confusion matrix: on `pin-cpplane` the
widest family is `compound_statement -> function_definition` at 53% of charged
bytes, because the misread declarator's body swallows the class and every member
function is left as a bare `compound_statement` with no definition frame over
it. Same defect, one remove downstream.

---

## 2. The 28.9% is one token

Not a repeated confusion, not a systematically missing frame, not an off-by-one.
Cut the file at the wall (`confuse.py --verb where --cut 690`):

| | judged | charged | square |
|---|---:|---:|---:|
| before 690 | 299 | 114 (all `unframed`) | **185** |
| from 690 | 698 | **698 - 100%** | **0** |

Every square byte in `ledger.cpp` lies before byte 690. Not one byte after it is
square. The same split holds on the second arm (330/185 before, 709 judged and
709 charged after), so this is a property of the parse and not of one recovery
strategy.

And `ledger.cpp` contains **exactly one** `call_expression` whose callee is a
bare identifier (`confuse.py --verb price`, counted on the *oracle's* tree,
since ours does not contain the nodes in question):

```
[  685,   726)  L25  'push("seed" + std::to_string(i), seed[i])'
```

Byte 690 is the `"` of `"seed"` - the first argument of the only call in the
file that offers the fork. 723 of 1,408 bytes lie at or after byte 685.

So the recall is not 28.9% because thirty things are wrong. It is 28.9% because
one token is wrong and it is 51% of the way into the file, and everything after
it is inside the recovery rather than inside the language. On the pre-supply
binary the remainder is swallowed into one runaway `string_literal` - which is
where `askew 589` comes from, and 63% of the charged bytes read `string_literal
-> «something real»`.

---

## 3. Where it is owned - press tables, and the runtime is doing its job

Six routes, three of which could have contradicted the other three.

**(a) The trace, which is the direct witness.** `JOINTS_TRACE=quire`, on the
two probes that differ by one token:

```
void g() { f(y); }
  split:   state 2572 on ( at 12 rank 0 — keeps fold _declarator #426, casts fold type_specifier #590
  refuted: state 159  on ; at 15 rank 0

void g() { f("x"); }
  split:   state 2572 on ( at 12 rank 0 — keeps fold _declarator #426, casts fold type_specifier #590
  refuted: state 907  on " at 13 rank 0
  refuted: state 438  on " at 13 rank 1
```

The runtime **does** fork. Two live strands. **Both are declarations**, and on
`f("x")` both die. The expression reading is not among them.

**(b) The state, which says why.** State 2572's kernel holds all three readings
of a bare identifier at once:

```
_declarator    -> identifier .
type_specifier -> identifier .
expression     -> identifier .
```

**(c) The grammar, which declared it.** `cpp.json` carries 39 conflicts, twelve
of which name `expression`, `call_expression` or `argument_list` - including
`['expression', '_declarator', 'type_specifier']` (three-way, the exact kernel
above), `['parameter_list', 'argument_list']` and `['type_specifier',
'call_expression']`. Tree-sitter's contract for a declared conflict is to fork
the stack and let all readings run.

**(d) The source, which admits the limit in a comment.**
`settle.Conflict.other` is a single `Action`, documented as *"One of the readings
that lost, for the report. **There may have been more.**"*, and
`forks.Forks.Split` is `{ cell, other: Action }` - one rival per cell. A cell
that lost two readings can hand one back.

**(e) The lexer is exonerated, twice.** `joints state cpp.json --census '"'`
says `"` shifts in **517 of 4,466 states**; state 907 is
`parameter_list -> ( . parameter_declaration …` and correctly refuses a string
literal, because a string cannot begin a parameter declaration. The token exists
and lexes; the state we are standing in is the wrong state.

**(f) It is not a runtime budget either.** No `denied` line appears in either
trace, so neither the `crowd` cap nor the `skeins` birth budget bound. The third
strand was not refused for want of room - it was never proposed.

**Attribution: press tables.** Not the lexer, and not fork *selection* - the
runtime selects correctly among what it is given. The defect is upstream of
selection, in what a contested cell is able to carry.

**The corroborating instrument that could have contradicted this and didn't:**
`research/joinery/TESTING.md` already records the same minimal pair for **C**,
attributed to `offer()` "wearing a lexer's clothes", where the verdict is
`stray byte at 17` rather than a named state. Same construct, different face:
C's `['type_specifier', 'expression']` is a **two**-way declared conflict, which
a binary fork covers exactly. C++'s is three-way. That is the cleanest statement
of why the two grammars fail differently on identical source.

---

## 4. The price, and the cheapest first repair

**Recoverable square, on `ledger.cpp`:** the 698 charged bytes after 690 are all
downstream of one token, and the 114 `unframed` bytes before it are the frames
that one root fails to close. Ceiling **1,197 of 1,408 bytes**; conservative
floor (post-wall only) **883**. Against today's 185 that is **4.8x to 6.5x**,
and it is the largest single-repair square gain available on the corpus - the
next-largest rows (scala 6,739/15,957, swift 14,419/25,279) are already past half.

**Rank against the corpus**, so whoever picks it up knows what they are buying.
cpp on the 1.4 KB ledger program: **185 square of 997 built - 19%**. On the same
program in C: **767 of 872 - 88%**. Same corpus, same author, same twenty-line
algorithm.

**The cheapest first repair is not the most vexing parse.** It is:

> Let a contested cell carry more than one dropped reading. `Conflict.other`
> becomes a small set rather than one `Action`; `Forks.Split` follows; the
> runtime's fork loop already takes a list of strands and needs no new concept.

Three properties make it the cheap one:

- **It changes no cell's `chosen`.** Every grammar whose declared conflicts are
  all two-way is bit-identical afterwards - **17 of the 30 board rows**: bash,
  css, elixir, embedded-template, html, json, julia, latex, lua, markdown,
  ocaml, python, ruby, sql, toml, yaml, zig.
- **It is press-side and additive**, so the runtime change is a loop bound.
- **It is testable on a nineteen-byte file** before anything larger is run.

The thirteen rows that can move at all, by widest declared conflict group
(`>=3-way` / `widest`): verilog 76/9 · typescript 14/4 · kotlin 11/5 · **cpp
9/4** · scala 7/3 · java 4/4 · go 3/4 · swift 3/7 · c 2/3 · javascript 2/3 ·
haskell 1/3 · php 1/4 · rust 1/3.

**Two things to measure before shipping it**, and neither is optional:
a third strand per cell costs fan-out on verilog's 76 wide groups, and
`crowd`/`skeins` will start binding somewhere. Price both halves.

**And one negative worth having:** no amount of precedence work will move cpp.
The ordering machinery can only permute two readings that are present. This is
the mechanism behind the zero-byte dynamic-precedence result, and it predicts
that any future ranking change will also read zero on cpp until the arity
changes.

---

## 5. cpp is not alone, and `damage` is blind by construction

The signature - quiet on `damage`, ruinous on `square` - over the 30-row board
(`blind.py`, on `pin-fz-control`):

| grammar | damage | crooked | recall | square / built |
|---|---:|---:|---:|---|
| **cpp** | 29.2% | 59.5% | 29.4% | 185 / 997 = **19%** |
| scala | 20.6% | 57.0% | 96.4% | 6,739 / 15,957 = 42% |
| elixir | **0.0%** | 48.2% | 97.7% | 23,879 / 46,089 = 52% |
| swift | 11.2% | 38.2% | 97.4% | 14,419 / 25,279 = 57% |

**elixir is the purest exhibit**: zero damage - the board's own words say the
parse is flawless - and 48% of its adjudicable bytes disagree with the oracle.
(The brief warns elixir's baseline is unstable and it is not to be used as a
reference point; it is listed as an exhibit of the blindness, not as a target.)

**But the sharpest exhibit is the c/cpp pair**, because it is the same program:

```
c     1444 B   damage 572   square 767   crooked  0.0%   recall 100.0%
cpp   1408 B   damage 411   square 185   crooked 59.5%   recall  29.4%
```

**cpp has less damage than c and one quarter the square.** A board sorted by
`damage` puts cpp ahead of c. There is no reading of the `damage` column under
which that is a useful sentence, and that is the mechanism the brief asked about
stated as a single comparison.

**Two more instrument warnings the scan turned up**, offered because this
project's habit is to name them:

- **`markdown` reads recall 100.0% with `square` 0.** It builds 178 of 3,304
  bytes; everything is `unframed`, so the shared-bracket denominator is a
  window almost nothing is inside. Node-weighted recall is not safe to read
  beside a low `built`.
- **`c` reads 0.0% crooked with 39.6% damage** - the exact inverse of cpp, and
  the healthy failure: it stops, and everything it did build is right.

**Fixture caveat, and it is large.** `absent.py` puts cpp's corpus reach at
**28% of 270 judgeable spellings**, against a 39.4% corpus mean, with **120 of
257 rules unable to occur in `ledger.cpp` at all**. cpp is the 5th-thinnest row
on the board by reach. Every absolute byte figure above is a floor over one
fixture; the *shares* and the mechanism are what should be quoted.

---

## Predictions, scored: 4 of 9

Written in `PREDICTION-1-crooked.md` before any parse was run. The misses are the
useful half and three of them are one fact.

| | claim | verdict |
|---|---|---|
| P1 | declarator chain where tree-sitter builds an expression | **hit**, to the node name |
| P2 | `racked` beats `askew` by 2:1 | **miss** - 589 askew to 2 racked on the brief's binary |
| P3 | one frame repeated at every level of a recursion | **miss** - one token, once |
| P4 | press-owned; the runtime is never handed two actions | **miss on the mechanism**, hit on the owner |
| P5 | the single fixture under-represents cpp badly | **hit** - 28% reach against a 39.4% mean |
| P6 | the deciding state holds no contested cell at all | **miss** - it holds one and the runtime split on it |
| P7 | at least two other rows share the signature | **hit** - scala, elixir, swift (but **not** c, which I named) |
| P8 | the top confusion is worth over 50% of crooked bytes | **miss** - 47.8%, by 2.2 points |
| P9 | the crooked clusters after byte 690 | **hit** - 100% of it |

**P4 and P6 are the load-bearing misses and they are the same fact.** I predicted
the runtime never sees a fork here, reasoning backwards from dynamic precedence
moving zero bytes. It sees one. The zero was not "no fork offered" but "the fork
offered has the wrong two members", which is a strictly better finding than the
one I went looking for and I would not have got to it by trusting the prediction.

**P2 is the miss that indicts `damage` again.** I reasoned that 411 bytes of
damage meant the leaves were largely right, so a wrong parent over a right leaf
had to dominate. It does not: the pre-supply recovery reads 700 bytes as one
`string_literal`, so the *deepest* node is wrong too, and `damage` counted that
runaway string as built. Low damage did not imply right leaves. It implied
almost nothing.

---

## A control worth recording, because it separates two numbers people will
## otherwise fuse

Between the two arms, cpp's recall moves **0.2941 -> 0.9391** and the crooked
share moves **59.5% -> 65.4%**. `square` is **185 on both**. The fourteen probes
fork on the **identical six inputs** on both binaries.

So whatever landed between those builds bought *reach* - the parse now recovers
into a plausible forest instead of a runaway string, and the verdict changes from
`mended 6 over 6B` to `supplied 3, spurned 0` - and bought **zero agreement**.
That is the shape to expect from every recovery improvement: recovery can restore
how much of the file gets nodes, and it cannot restore whether they are the right
nodes. The two arms differ by more than one lane's work, so I am not attributing
the movement to a named lane - only recording that recall moved 3.2x while square
did not move one byte, and that the fix this dossier recommends is upstream of
both.

---

## Reproducing any of it

```sh
eval "$(python3 tool/pin.py arm fz-control)"     # read the `oracle: N of N` line
python3 research/joinery/cpp/vexing.py           # the fourteen minimal pairs
python3 research/joinery/cpp/vexing.py --tree 0  # the nineteen-byte exhibit
python3 research/joinery/cpp/confuse.py --verb price
python3 research/joinery/cpp/confuse.py --verb where --cut 690
python3 tool/rack.py run --json > board.json
python3 research/joinery/cpp/blind.py board.json
joints state upstream/grammars/cpp.json 2572
JOINTS_TRACE=quire joints parse "$JOINTS_WORK/cpp.folio" <probe>
```

Nothing here writes outside `stdout` and `.local/`. No file under `src/` or
`tool/` was modified by this lane.

---

## The instrument I trust least, and it is mine

**`vexing.py`'s `MATCH` verdict.** It compares the two forests at depth 0 only,
so it prints `MATCH` for `void g() { f(y); }` - the file whose tree is the
central exhibit of this document being wrong. It passed its own check and cleared
nothing, for precisely the reason `damage` clears nothing: **a comparison that
only looks at whether a root exists cannot see what is under it.** I built the
instrument that reproduces the defect I was sent to diagnose, in the same
session, and did not notice until the interiors were printed by hand.

It is kept as-is rather than tightened, because it is doing the job it is for -
locating *which token* moves the parse - and a `MATCH` that meant "the trees
agree" would be a fifteenth instrument in this document claiming more than it
measured. But no `MATCH` in that output is evidence of agreement, and the two
probes that are genuinely byte-identical to the oracle (`a.f("x")`, `std::f("x")`)
are only known to be so because their interiors were read.

The runner-up is `rack`'s `unframed` column under recovery: 217 bytes of it on
the pre-supply arm, 174 on the post-supply one, over a file where the frames in
question are the ones the wall destroyed. It is charged neither square nor
crooked, which is the correct call, and it means the crooked *share* has a
denominator that moves with the recovery strategy. The shares in section 5 are
comparable across grammars measured on one arm and are **not** comparable across
arms; the byte counts are.

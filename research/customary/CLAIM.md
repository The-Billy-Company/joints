# Customary - the scanner becomes data

**Status: rungs 0 and 1 measured, the instruction set below is the frozen set
plus the four widenings rung 1 forced, rung 2 next.**
[`CENSUS.md`](CENSUS.md) is the evidence this document rests on: eight scanners
read against what their own `serialize` writes, which is the only definitive
statement of what a scanner remembers.
[`RESULT-1-algebra.md`](RESULT-1-algebra.md) is what happened when two of them
were transcribed and run.

---

## The claim in one paragraph

tree-sitter's original sin is that **a grammar becomes a C program**. joints
answered that with *a grammar becomes a table*, and then kept one exception: the
externally-scanned terminals, answered by a fixed roster of hand-written Zig
scanners with per-language tables compiled into the binary. The claim is that
the exception is unnecessary - that a scanner's *memory* is two stacks and a
register bank, its *decisions* are a conjunction of tests over bytes,
line facts, the parse state's own permission set, and those organs, and its
*effects* are pushes, pops, register writes and one emit. Given that, a scanner
is a **program in data**: a customary, pressed into the folio beside the parse
table, run by one interpreter. One binary and one folio is then every language
including the six that keep state, with no C in the loop and nothing
per-language in the binary at all.

The claim is not that an interpreter is faster than C at reading bytes. It is
that **the state a customary keeps is a stack effect**, so it hangs on the same
spine M2 already hangs on - and an edit inside a heredoc, a yaml document or a
markdown blockquote costs `O(log n)` where tree-sitter deserializes a capped
snapshot and re-lexes forward.

---

## Why this and not the four alternatives

**Keep growing hands.** The status quo. Each new convention is a Zig lane, each
new language's spelling table is bytes in the binary, and the roster is already
seven kinds with eight discriminator fields between them
(`dialect`/`tongue`/`vein`/`family`/`sight`/`line`/`note`/`sort`). yaml alone
would add three organs nobody else uses. This is the design that made the
ceiling, so it cannot be the design that lifts it.

**Iguana-style data-dependent desugaring.** Named in
[`../joinery/PRIOR_ART.md`](../joinery/PRIOR_ART.md) as the principled
replacement, and it is - for a grammar you *write*. It cannot consume the three
hundred maintained `grammar.json` files, because the scanner's body is not in
`grammar.json` at all. Adopting it means giving up the import story, which is
the reach the whole package is built on.

**Compile `scanner.c` to WASM.** Ships per-language compiled code with opaque
state. It kills the size claim, the composition claim, and the one sentence the
package exists to be able to say.

**Fork on every ambiguity instead of remembering.** Measured and refused:
`../joinery/markdown/RESULT-1-stack.md` found `_line_ending` and
`_soft_line_ending` co-admitted by shift in 133 of 201 states, so this is the
same stack deferred and paid for in limbs.

---

## The frozen algebra

Frozen by the census, which is to say: every organ, test and action below is
here because at least one of the eight scanners needs it, and nothing is here
speculatively. A future language that needs a fourth organ gets one by measuring
its `serialize` and widening this list on purpose - never by a rule quietly
reaching for something the list does not name.

**Rung 1 widened it four times, and each one is a case the census recorded
without naming who would execute it.** They are the rung's real result, because
the kill condition was a mismatch no edit could fix and this is what the edits
turned out to be:

| widening | who forced it | what the census had already seen |
|---|---|---|
| `pass` - a bounded sweep over **one organ**, its body chosen by the entry's own kind | markdown | `while (s->matched < open_blocks.size) match(...)`: not a loop over bytes but over the block stack, bounded by its depth |
| `nest` - a balanced run | kotlin, and swift and scala the same way | "swift's `multiline_comment` depth lives on the C stack... it is a counter; a register holds it" - true, and this is the guard that moves it |
| `abstain` - end the ask, answer nothing | kotlin | every `return false` that follows a state write; without it the rule behind answers at an offset the rule in front had just accounted for |
| `span k` - the width of a group of the guard's own match | kotlin, swift | `prefix_len` and `ongoing_raw_str_hash_count` are both the length of a run the scanner just read |

None of them adds an unbounded computation: `pass` is bounded by a stack depth,
`nest` by the bytes it claims, and the other two are reads. The invariant in
[What this is not](#what-this-is-not) is unchanged.

### Organs - the memory

```text
frames : stack of { width: i32, kind: u16 }        // indentation regions
marks  : stack of { kind: u16, count: u16, tag: [32]u8 }  // delimited spans
regs   : [8] i32                                   // counters, flags, saved widths
```

Both stacks are **fixed capacity**, for the reason `offside.Columns` already is:
it keeps the whole external seam infallible, so `Scanner.next` stays the
infallible function every caller relies on and nothing allocates mid-scan.

Two stacks rather than one wider one, because they nest independently. A file can
be inside a heredoc and inside three indentation regions at once, and the
innermost of each answers a different question.

`regs` is the organ no hand has today, and four of the six stateful scanners
need it: markdown's five `uint8_t`, scala's five `int16_t`, yaml's five
`int16_t`, haskell's newline block, swift's hash count.

### Inputs - what a test may read

Nothing else. This list *is* the kill condition of rung 0, restated as a
permission:

- the bytes at the offset and after it, through a **probe** (a pressed pattern,
  matched at the offset, answering a length)
- the line facts `grain` already measures: is this offset at a line start, the
  measured leading width, whether the line is blank, the column
- the parse state's own permission set: `wanted` (the union of non-error
  actions), `named` (the same with the auto-admitted extras taken back out),
  and whether a terminal is the *sole* shiftable admission
- the organs above
- whether the offset is the end of input, and whether repair is running

### Tests - a guard is a conjunction

| test | reads |
|---|---|
| `probe P` | a pressed pattern matches where the guard has read to; binds its length |
| `no_probe P` | it does not - a negative lookahead spelled as a test |
| `soak [to V] [one] [from V]` | the blanks at the offset, up to a target the organs name; binds how far the budget got |
| `nest OPEN CLOSE` | a **balanced** run from the opener the guard already matched, to where it is paid off or to end of input |
| `pass N [after] [until V]` | one bounded sweep of the `matched` rules over the open frames from a stated cursor; binds how far it got, the budget, the bytes, the offset |
| `fires G` / `no_fires G` | whether any rule in a named group would hold here, guard only, on a frozen copy of the organs |
| `wanted S` / `!wanted S` | `S` is (not) in the permission set |
| `named S` / `!named S` | the same over the set without auto-extras |
| `sole S` | `S` is the only shiftable admission - the unanimity warrant |
| `fresh` | no extra has been stepped over since the last token |
| `bol` | the offset is at a line start |
| `blank` | the line at the offset is whitespace to its end |
| `lull` | the line *before* this one was blank |
| `eof` | the offset is the end of input |
| `mending` | repair is running (tree-sitter's `valid_symbols[error]`) |
| `lead OP n` \| `lead OP frames.top.width` | the measured leading width against a literal or the frame |
| `frames.depth OP n` · `marks.depth OP n` | stack depth |
| `frames.top.kind IN {…}` · `marks.top.kind IN {…}` | the innermost element's kind |
| `frames.at.kind i IN {…}` · `frames.at.width i OP n` | the element under a `pass` cursor, which is not the top |
| `marks.top.count OP n` | its count |
| `marks.top.tag matches` | the bytes at the offset equal the stored tag, optionally case-folded |
| `marks.has kind K` · `frames.has kind K` | anywhere in the stack, for html's dig-deeper close |
| `reg R OP n` | a register against a literal |

`OP` is one of `= ≠ < ≤ > ≥`. A guard holds when every test holds; a rule with an
empty guard always holds, which is how a phase's default arm is spelled. Any `n`
above may instead be a **value**: a register, a stack depth, a frame's width, the
measured `lead`, `± n` or `max`/`min` of two of them, or `span k` - the width of
one group of the guard's own match, which is how a rule reads a run it just
counted (swift's `#`s, kotlin's `$`s, a fence's backticks) without arithmetic.

### Actions - what a rule may do

| action | effect |
|---|---|
| `emit S` | answer terminal `S` over the extent the rule established |
| `emit S width 0` | answer zero-width, subject to the progress ledger |
| `emit S classified by C` | answer the terminal `C` selects from the matched text - yaml's schema resolver, and the one action a `Provision` structurally cannot have |
| `push frames {width, kind}` | open a region; `width` may be `lead`, a literal, or a register |
| `pop frames` · `pop frames until kind K` | close one, or dig to a kind |
| `push marks {kind, count, tag}` | open a span; `tag` may be a slice of the match |
| `pop marks` · `pop marks until kind K` | the same over spans |
| `set reg R` to a literal, `lead`, a probe length, a stack depth, or `R ± n` | a register write |
| `skip n` | step over bytes without claiming them - tree-sitter's `advance(lexer, true)` |
| `refuse` | this rule declines; the next in its phase is tried |
| `abstain` | the whole **ask** ends, answered with silence - the C's `return false` after a state write, and the difference between "not me" and "nothing here" |

A rule with no `emit` is **effect-only**: it remembers something about bytes it
does not claim, and the ask carries on behind it unless it also abstains. Every
one of the eight has these - each path that writes the delimiter stack or a
register and then returns false.

### Phases - where in the ask a rule is tried

The order is `outside.offer`'s and it is not per-language: what is inside an open
span first, because its body owns those bytes until it says otherwise; then the
line's layout; then a commanded open; then a span opening; then an element
close; then a bounded run; and last, after the slate has already found nothing,
the orders the parse licensed by having no other move.

```text
inside · layout · commanded · opening · enclosing · bounded · ordered
```

A rule declares its phase. Rules within a phase are tried in declaration order,
which is the order the scanner they were read from tries them in - the census
records that order per grammar because it is load-bearing (scala's three arms
are INDENT, OUTDENT, AUTOMATIC_SEMICOLON, in that order, and reversing two of
them changes the tree).

### Provenance - three tiers, fail-closed

A terminal is answered from exactly one of these, and the honesty surface does
not change:

- **derived.** The convention proves itself from the grammar's own
  declarations - today's cohort test - and the customary fragment is generated.
  No file to author, no chance to author it wrongly.
- **transcribed.** A committed customary, read from the scanner as a
  specification, cohort-gated exactly as a troupe is: every part must resolve or
  none of them do. Half a shape is worse than none, and the reasons are already
  written down in `outside.seated`.
- **absent.** Still `blind`, still a located wall, still
  `inquest.awaited_external`. A token we cannot produce beats a token we produce
  wrongly, and this design does not soften that line - it moves where the line
  falls.

---

## The falsifiers

Each rung has one, and it can be measured before the rung above it exists.

**Rung 1a - expressiveness.** Draft customaries executed by an offline
interpreter against tree-sitter's own token stream over the corpus. *Kill: a
mismatch no customary edit fixes* - which means the frozen algebra is short a
test or an action, and the census missed it. **Held**: markdown 10,568 answers
and kotlin 139, none missing, none the parse table would not have asked for.

**Rung 1b - composition.** Organ effects, taken per segment and composed as
stack effects, must reproduce the whole-file organ state no matter how finely
the file is cut. This is rung 1 of the joinery claim asked about the lexer, it
needs no parser and no oracle, and it is what the `O(log n)` edit rests on.
*Kill: a cut where the product disagrees with the whole.* **Held** at 3,306 of
3,306 cut schedules over 551 files, compared at every cut.

**Rung 2 - zero cost when absent.** A grammar with no customary must lex
byte-identically and within noise of the time it takes today. *Kill: a
measurable regression on the eleven that need no customary.*

**Rung 3 - the board.** Each grammar's customary is gated by tree agreement
against tree-sitter over the corpus (`tool/plumb.py board`), never by "it
parses". *Kill: a grammar whose `trued` share falls.*

**Rung 5 - the speed claim.** Forward throughput against the C scanners, and
the keystroke bench extended to edits *inside* stateful regions. *Kill: the
`O(log n)` edit is not observable, or forward lexing loses and the loss is not
explained.*

---

## What this is not

It is not a general-purpose bytecode. There is no arithmetic beyond `±`, no
loops, no calls, and no way to write a rule whose cost is not bounded by the
bytes it consumed plus a constant. That is deliberate: the interpreter runs per
offset in the hot path of every parse, and a language that can express an
unbounded computation is a language a grammar author can hang the lexer with.
Every rule terminates because every rule is a guard and a finite action list,
and every zero-width answer still passes `outside.Spent`.

It is also not a claim that transcription is free. Reading a scanner and writing
its customary is careful work, and the tier system exists because the failure
mode of doing it carelessly is a confidently wrong tree - the one outcome this
package holds to be worse than silence.

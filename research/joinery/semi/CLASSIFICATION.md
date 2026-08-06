# Sixty-eight externals, classified by mechanism

Swift's 33, kotlin's 10 and scala's 25, sorted by what a stand-in for each would
have to *be*. The brief framed the axis as "carried state versus
context-sensitive pattern" and that turned out to be the right axis asked at the
wrong place: **the grammar cannot answer it, and the scanner answers it in one
line.**

## Where the answer actually lives

An earlier pass in this lane tried to derive the memory axis out of
`grammar.json`, reasoning that a terminal co-derivable with a sibling in some
`SEQ` was probably a span with a remembered opener. It produced false positives
immediately - bash's `file_descriptor` and `heredoc_start` came back as one
span needing memory, and `file_descriptor` is `[0-9]+` before a `>`. The
structure a terminal appears in says what the *parser* does with it and is
silent about what the scanner had to remember to produce it.

The scanner is not silent. tree-sitter requires an external scanner to declare
its whole memory through `serialize`/`deserialize`, because the runtime
snapshots it at every GLR fork. So the memory axis is exactly:

> **What does `serialize` write?**

For swift, `struct ScannerState` is one field:

```c
typedef struct { uint32_t ongoing_raw_str_hash_count; } ScannerState;
```

Four bytes, one number: how many `#` opened the raw string currently being read.
For kotlin it is a `Stack` of `Delimiter`s with their prefix lengths - which
string opened, and how deeply. Both are the same shape as the memories this
lexer already keeps (`offside.zig`'s column stack, `fence.zig`'s open marks),
and neither has anything to do with a statement separator: kotlin's
`scan_automatic_semicolon` never dereferences `payload` at all.

That is the finding. **Two of swift's 33 need memory and neither is the
separator**, and the other 31 are a function of the bytes at one offset plus
"what would the parser accept here" - which is the question tree-sitter's
`valid_symbols` is, and which a state-directed lexer holds for free.

So the cohort rule was never the obstacle it looked like. (It also is not the
rule the brief describes; see `RESULT-1-cohort.md` - `provisionFor` requires a
*row's own* cohort, never the grammar's whole external list, and eight grammars
were already running partially seated before this lane started.)

## Swift, all 33

Three mechanisms, and the derivation for each is named rather than eyeballed.

### Carried state — 4 terminals, all one family, all declined

`raw_str_part` · `raw_str_continuing_indicator` · `raw_str_end_part` ·
`multiline_comment`

The first three are the raw-string family `ongoing_raw_str_hash_count` exists
for: `#"..."#` and `###"..."###` differ only in a count the closer must match,
which is memory by construction. `multiline_comment` needs a nesting depth,
which swift's scanner tracks on the C stack through recursion rather than in
`ScannerState` - a memory either way, and a `Provision` has none.

This is the php shape exactly, and it is declined for the php reason. There is a
`marrow` vein for nesting block comments already (kotlin and scala share
`marrow/kotlin_block`) and a `fence` for delimiter-captured closes, so these
four are seatable work - just not pattern work, and not this lane's.

### Context-sensitive pattern — 21 terminals, 19 seated

Derived from the scanner's own three parallel tables, joined at the index:
`OPERATORS` gives the spelling, `OP_SYMBOLS` gives the terminal, and
`OP_ILLEGAL_TERMINATORS` gives the refusal. So `where_keyword` is spelled
`where` because index 13 of `OPERATORS` says so, not because the name ends in
`_keyword`; that join is transcribed as the `swift_roll` table in
`src/kernel/lex/outside.zig` and is the whole derivation.

Four refusal groups, and every one of them is trailing context - which is what
`Provision.never` and `Provision.after` already spell:

| group | refuses when followed by | members |
|---|---|---|
| `OPERATOR_SYMBOLS` | any of `/ = - + ! * % < > & \| ^ ? ~` | `->` `&&` `\|\|` `??` `=` `==` `as?` `as!` (`!`) |
| `OPERATOR_OR_DOT` | those, or `.` | `.` |
| `ALPHANUMERIC` | an alphanumeric | `throws` `rethrows` `default` `where` `else` `catch` `as` `async` |
| `NON_WHITESPACE` | anything but whitespace | `+` `-` |

These terminals are external for a reason that reads as exotic and is not:
swift lets you *define* operators, so `=~` is a user's operator and `=` is
assignment, and the only thing separating them is the byte after the `=`. The
scanner spells that as a refusal. So do we.

`_custom_operator` is the same mechanism and is **declined** - not for memory
but because its acceptance is a whole-match filter (`RESERVED_OPS`, 31 entries)
rather than trailing context, and `never`/`after` cannot say "matched, but not
if the match equals one of these". It costs little: `...` and `..<` are literals
in swift's own grammar, so the two custom operators the corpus actually contains
are spelled by the grammar and lex without it.

`_bang_custom` (`!`) is the one **refusal inside a group otherwise seated**, and
the reason is worth stating precisely because it is the only place the mechanism
genuinely runs out. `OP_SYMBOL_SUPPRESSOR` conditions it on `FAKE_TRY_BANG` *not*
being wanted - the `!` of `try!` belongs to the grammar, not to the scanner. That
is a question about the parse table, and a `Provision` is a function of bytes
with no access to one. Seating it anyway would lex `try!`'s bang as a postfix
operator: a tree that parses and is wrong, which is the exact thing this table
exists to refuse.

`_hash_symbol_custom` and the four `_directive_*` are also declined. They are
not in `OPERATORS`, so they have no transcribed refusal - `find_possible_compiler_directive`
is a separate walk - and the corpus contains zero `#if`. Blind rather than
guessed.

### Zero-width, answered by the parser's own expected set — 2 terminals, seated

`_implicit_semi` · `_explicit_semi`

The target. Neither needs memory; both need the answer to "did a line end here",
and `_explicit_semi` needs it *because swift's scanner reads `;` as whitespace*
(`should_treat_as_wspace` returns `iswspace(c) || c == ';'`). That is why the
brief's probe found even a written `;` failing: nothing else in swift's member
and statement rules spells a separator, so a file cannot say what the scanner
refuses to hear.

Seated on `caesura`, the existing zero-width hand, as a third tongue.

`_fake_try_bang` is the 33rd and is a **phantom**: no bytes at all, existing only
to be *asked about*. It is used here as the swift caesura's `kin` - the evidence
that this grammar is swift's - and stays blind, which is correct: a terminal the
scanner never emits is one no stand-in should emit either.

## Kotlin, all 10

| mechanism | terminals |
|---|---|
| carried state | `_string_start` `_string_end` `string_content` `_interpolation_expression_start` `_interpolation_identifier_start` |
| nesting, already seated | `multiline_comment` (via `marrow/kotlin_block`) |
| zero-width + expected set, **seated** | `_automatic_semicolon` |
| context-sensitive pattern, declined | `_primary_constructor_keyword` `_import_dot` `_by_delegation_hint` |

Kotlin's `serialize` writes the delimiter stack, and the five string terminals
are what reads it. `scan_automatic_semicolon` takes `payload` and never touches
it - the separator is stateless here too, and it is one terminal rather than
swift's two because kotlin's scanner consumes a written `;` and reports the same
symbol.

The three declined are pattern work someone could do; two of the three
(`_import_dot`, `_by_delegation_hint`) are one byte and a word, and
`_by_delegation_hint` is now load-bearing as this row's `kin`, so seating it
would want care.

## Scala, all 25 — declined, and this one is a refusal rather than a gap

Scala's `_automatic_semicolon` looks like kotlin's and is not. Its externals
include `_indent`, `_outdent`, `_comma_outdent`, `_colon_eol`, `_end_keyword`
and `_control_tail_gate`, which is Scala 3's optional-braces layout: whether a
newline ends a statement **depends on the indentation region the newline is
in**, and the region is a stack. So the separator here is downstream of a
memory, where swift's and kotlin's are not, and no `caesura` tongue can answer
it.

That is a real difference in the language, not a shortfall in the reading. Scala
wants a layout troupe - and there are now two models for one in this tree,
python's detecting stack (`offside.zig`) and haskell's commanded one
(`writ.zig`) - which is a lane, not a table row. Scala's board row is
**byte-identical** before and after this change, which is what declining looks
like when it is done honestly.

## What this says about the cohort rule

The rule is upheld and untouched. Every row seated here carries a cohort of
swift-only or kotlin-only names (`_implicit_semi` + `_fake_try_bang` for the 19
operators; `_fake_try_bang` and `_by_delegation_hint` as the two caesura kin),
and the proof that the gating works is on the board: **exactly two grammars
moved.** Scala declares `_automatic_semicolon` and moved zero bytes. Php
declares it and moved zero bytes. Javascript and typescript declare it and moved
zero bytes.

No fail-closed partial was needed, because the thing the brief suspected might
require one - swift's 33 as an all-or-nothing block - was not the rule. What
remains unseated in swift is 12 terminals that each fail closed on their own
already: a blind external is in no action row, so a state waiting for one stops
with a located wall rather than accepting a plausible tree. That is the
refusal mechanism, and it was here before this lane.

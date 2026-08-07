# Result 1 — the three string interiors, classified from their own `serialize`

Measured 2026-08-05, binary `joints e8343caf6`, against the pinned scanners
under `.local/breadth/lang/<name>/src/scanner.c` and the pressed tables of the
thirty vendored grammars.

## The answer in one table

| Grammar | `create` | `serialize` writes | Organ | Verdict |
|---|---|---|---|---|
| julia | `return NULL` | `return 0` | none | **seated** — 8 interiors + 2 closes |
| kotlin | `Array(char)` | the whole stack, 2 bytes a frame: `[delimiter\|triple, prefix_len]` | a stack | **declined** |
| swift | one struct | 4 bytes, `uint32_t ongoing_raw_str_hash_count` | a scalar | **declined** |

The axis is `serialize` and nothing else. Tree-sitter requires a scanner to
declare its entire memory through `serialize`/`deserialize` so the runtime can
snapshot it at every GLR fork, so a scanner that writes zero bytes has no
answer that can depend on which reading asked. Julia writes zero bytes:

```c
void *tree_sitter_julia_external_scanner_create() { return NULL; }
unsigned tree_sitter_julia_external_scanner_serialize(void *p, char *b) { return 0; }
void tree_sitter_julia_external_scanner_deserialize(void *p, const char *b, unsigned n) {}
```

That is the whole soundness argument, met by construction rather than by
inspection of sixteen call sites.

## Julia — seated

`scan_content(lexer, symbol, end_char, n_delim, interp)` is
`marrow.Mark{ .shut, .wide, .interpolates }` with the arguments renamed, and
the eight `_content_{str,cmd}_{1,3}[_raw]` terminals are eight rows of that
table. But it is **a family with its own walk, not eight rows under elixir's**,
and that correction is the finding of P1e. Four of julia's decisions are its
own, and three of them would have been silently wrong under `matter`:

- **End of input refuses.** Julia's loop is `while ((next = lexer->lookahead))`
  and falls out of the bottom with no `result_symbol` set, so a file stopping
  mid-string yields no content token at all. elixir hands back matter to the
  end. Inheriting elixir's charity would have had the hand answer where the
  specification stays silent.
- **The interpolating sigil is a bare `$`, sharing its arm with `\`.**
- **The raw arm stops at `\\` as well as at an escaped delimiter**, because a
  raw string still spells `\\` for one backslash.
- **The close is the same walk's other answer.** Julia emits `_end_str` /
  `_end_cmd` from *inside* `scan_content`, when the delimiter is already there
  and no matter stands in front of it. The extent is the delimiter's own width,
  which is knowable in that pass and nowhere else — so `marrow.walk` returns
  `Run{ matter | close | none }` rather than an optional length.

`Mark.wide = 3` now means "three of them" and what that *implies* belongs to
the walk: elixir reads three as a heredoc (only a line may begin the close),
julia reads three as three quotes anywhere. Putting the reading in the field
would have forced julia's `"""` to inherit a rule julia's scanner does not have.

## What the census said, including where it contradicted me

Run **before** the mechanism was chosen, on all ten terminals over julia's
1,175 states. P1b predicted zero co-admission-by-shift among the eight, and
`_end_str` meeting only str-content. Both held exactly:

```
_content_str_1  _content_str_3   shift 0
_content_str_1  _content_cmd_1   shift 0     (all 28 content pairs: 0)
_content_str_1  _end_str         shift 2  (first: state 44)
_content_cmd_1  _end_str         shift 0
```

**And the prediction was true while its conclusion was false.** I wrote "so no
byte has to separate them", meaning no guard was needed. The permission set a
hand actually reads is not the shift column. `drive.offer` admits every
terminal the state has *any* non-error action for — shifts and reduce-
lookaheads alike, because that is tree-sitter's `valid_symbols` — and the
census printed only co-admission by shift. So the census was answering a
question next to mine, in the same 85× split the state row prints under two
headers.

`state --census` now prints both columns, and the second one says:

```
_content_str_1  _content_str_3   shift 0   set 3  (first set: state 1)
_content_str_1  _content_cmd_1   shift 0   set 3  (first set: state 1)
_content_str_1  _end_str         shift 2   set 11 (first shift: state 44)
```

Six of the ten sit together in **three** states. State 1 is `shift 0,
lookahead 103`, where 103 terminals all fold `identifier -> _word_identifier`.
A hand reading only the shift column would have answered string content over
an identifier, everywhere in the language.

The three loose states and the eight real interiors are disjoint — state 44 is
`shift 4, lookahead 0` and holds no command terminal at all — so the elixir
`rival` guard covers it exactly: `{_content_str_1, _content_cmd_1}` are
admitted together in the three loose states and in none of the eight. That
pair is in the seating because the census contradicted the design, not because
it confirmed it.

### The question the first census did not ask: plain before raw

`spelt` walks the roster in the specification's dispatch order and takes the
first member the state admits, which puts `_content_str_1` ahead of
`_content_str_1_raw`. If a state inside a **raw** string also admitted the
plain terminal, the hand would run the interpolating walk over a raw run —
stopping at a `$` that raw julia treats as ordinary matter. That is a
mis-lexing the board could not have shown me, because neither corpus file has
a raw string in it. Censused after the fact rather than assumed:

```
_content_str_1      _content_str_1_raw    shift 0   set 0
_content_str_1_raw  _content_str_3        shift 0   set 0
_content_str_1_raw  _content_cmd_1        shift 0   set 0
_content_str_3      _content_str_3_raw    shift 0   set 0
_content_cmd_1      _content_cmd_1_raw    shift 0   set 0
```

**Every pair involving a raw terminal is `set 0`** — not merely never shifted
together, but never in one permission set at all, including in the three loose
states. So the four raw terminals are each admitted alone or not at all, the
roster's order cannot reach a wrong member, and the `rival` guard cannot
wrongly refuse a raw run either, because neither of its two members is ever
present where a raw one is.

This went looking for a flattering gap in my own fix and did not find one. It
is recorded anyway, because "the members are mutually exclusive by
construction" was a claim inherited from elixir's header and reused for julia
on the strength of the four plain terminals; the four raw ones were covered by
the sentence and not by the measurement.

## Kotlin and swift — declined, and the corpus cannot tell you why

Both declared memories are for constructs the interior re-enters far from its
opener. `"a ${ f("b") } c"` resumes content after the `}`, arbitrarily far from
the `"` that opened it, which is why kotlin keeps a stack with depth and swift
keeps a live hash count. `marrow` gets away with a captured close (c++
`R"tag(`, lua `[==[`) only because the opener sits immediately behind the
content offset by construction; here it does not, so the backwards walk cannot
recover `is_triple` or `prefix_len`. These are `fence` shapes — a mark stack —
and `fence` is where they belong if anyone builds them.

**The falsifier I named for that turned up something better.** I said the
prediction would break if every string-content offset in `Maps.kt` and
`Chunked.swift` sat immediately behind its own opener. Measured:

```
kotlin Maps.kt        "${"  0 occurrences      '"""'  0 occurrences
swift  Chunked.swift  '#"'  0 occurrences      '\('   0 occurrences
```

Neither corpus file contains interpolation, a triple-quote, or a raw string at
all — 40 and 25 lines of plain `"…"` between them. So **on this corpus a
stateless kotlin hand would match the real scanner on every byte**, because the
stack is always depth one with `is_triple = false, prefix_len = 0`. It would
diverge the instant a file spelled `${`, which is exactly the stand-in that
silently mis-lexes what it cannot handle.

That is the argument for the classification method rather than against it: the
corpus cannot distinguish a correct kotlin seating from an unsound one, and
`serialize` can. A lane grading itself on this corpus would have shipped the
unsound one and seen it go green.

### The cost of the decline, stated

Read off the board of 2026-08-05T19:56Z:

| grammar | bytes | rubble | spoil | unbound | share | mend |
|---|---|---|---|---|---|---|
| kotlin | 35,815 | 333 | 936 | **1,269** | 3.5% | 142 over 142B |
| swift | 28,468 | 300 | 1,040 | **1,340** | 4.7% | 31 over 61B |

Those are each grammar's *entire* remaining unbound, string troupe included, so
the string organ is worth at most that and certainly less. Against julia's
14,307 before seating, both are rounding error.

Kotlin's headline number misleads in the other direction and is worth naming:
41.4% standing on a 97.4% covered file is not a string problem. Its `orphan` is
**19,705 of 35,815 bytes — 55% of the file** — KDoc sitting as top-level leaf
roots, which is the interaction the previous kotlin lane reported plainly. No
string seating touches it.

Swift's wall reads `lexer? on ) in state 141 [no stand-in for
multiline_comment]`, and `multiline_comment` is the declared extra that wins
every stand-in scan in that language. The verdict says so itself — "this is the
best reading rather than a proof". The name is not evidence for a raw-string
wall or against one.

## The next wall, classified but not built

Julia's remaining five blind terminals are `_immediate_{paren,bracket,brace,
string_start,command_start}`, and they are the wall now (`{` at 972 in state
136). They are **stateless** — the same zero-memory scanner, three lines each:

```c
if (valid_symbols[IMMEDIATE_PAREN] && lexer->lookahead == '(') {
    lexer->result_symbol = IMMEDIATE_PAREN; return true;
}
```

Census, run:

```
_immediate_paren     _immediate_bracket        shift 14  set 236 (first shift: state 31)
_immediate_paren     _immediate_string_start   shift 0   set 10
_immediate_string_start _immediate_command_start shift 9  set 10 (first shift: state 120)
```

They are heavily co-admitted and it does not matter, because the discriminator
is the byte and the five bytes are distinct — the inverse of the trap where
three arms of one `switch` look like three terminals fighting for an offset.

They are not seated here because they need a **new mechanism, not a new row**.
Each answers **zero-width** — `advance` is never called — and moves no memory,
and `outside.step`'s pin refuses a zero-width answer whose `Carry.shape()` did
not move. Every zero-width hand in the file today proves progress by popping a
column or a tag or pushing a frame; these prove it by having been shifted.
That needs a new `kind`, its own slot in `offer`'s priority order (the
specification runs this cohort *first*, before even the block comment), a
`fresh` gate, and a reckoning with the pin. That is a lane, not an addendum,
and it is handed over with its census already run.

---
doc_radar:
  paths_exist:
    - tool/customary.py
    - customary/markdown.json
    - customary/kotlin.json
  sentinels:
    - file: tool/customary.py
      contains:
        - 'if op == "nest":'
        - 'elif head == "abstain":'
        - 'asks: str = "line"'
---

# Rung 1 - the algebra holds, and here is what it cost

**Both falsifiers held.** Two customaries, written by reading two `scanner.c`
files and nothing else, executed by an interpreter of the frozen instruction set
over 551 files: **10,707 answers, none missing, none the parse table would not
have asked for**, and organ state that composes at **3,306 of 3,306** cut
schedules.

Re-run rather than trust it:

```bash
python3 tool/customary.py check markdown        # 531 files
python3 tool/customary.py check kotlin          #  20 files
python3 tool/customary.py compose markdown
python3 tool/customary.py compose kotlin
```

---

## 1a - expressiveness

**The question.** A customary is a program over two stacks and a register bank.
Run against real bytes, does it answer the terminals tree-sitter's own scanner
answers, at the same offsets? The oracle is the tree-sitter CLI's tree read for
its leaves: a leaf named by an external terminal *is* that scanner's answer,
positioned, and no instrumentation of the C is needed to get it.

**The kill condition.** A mismatch no customary edit fixes - which would mean the
frozen algebra is short a test or an action and the census missed it.

### markdown - 47 externals, the grammar that made the ceiling

| terminal | agreed | missed | recall |
|---|---:|---:|---:|
| `block_continuation` | 6167 | 0 | 100.0% |
| `atx_h2_marker` | 1631 | 0 | 100.0% |
| `fenced_code_block_delimiter` | 1068 | 0 | 100.0% |
| `list_marker_minus` | 767 | 0 | 100.0% |
| `atx_h1_marker` | 310 | 0 | 100.0% |
| `list_marker_dot` | 260 | 0 | 100.0% |
| `atx_h3_marker` | 204 | 0 | 100.0% |
| `block_quote_marker` | 120 | 0 | 100.0% |
| `list_marker_star` | 31 | 0 | 100.0% |
| `atx_h4_marker` | 7 | 0 | 100.0% |
| `list_marker_parenthesis` | 3 | 0 | 100.0% |
| **total** | **10,568** | **0** | **100.0%** |

66,812 further answers are terminals a tree cannot show - `_line_ending`,
`_block_close`, `_blank_line_start` and the rest are hidden in every grammar that
declares them - so they are counted and left for the differential once the engine
exists. Recall is over what is observable, which is the honest denominator.

**183 answers over 27 of the 531 files are extra**, and all of them are one
thing: this side has no permission set. `check` asks at every offset a block
scanner's caller could ask at, so a `1.` mid-sentence gets offered as a list
marker where tree-sitter's parse table would never have asked. Measured under an
**envelope** - the ask refused where a lexer is structurally not called (interior
to a leaf) and where the innermost grammar rule covering the offset cannot reach
that terminal - the residue is **0 missed and 0 spurious**. The envelope is
derived from `grammar.json` and the oracle's own tree shape, never from the
expected answer, so it can refuse an ask but cannot supply one.

### kotlin - the string family and the nested comment

| terminal | agreed | missed | recall |
|---|---:|---:|---:|
| `multiline_comment` | 77 | 0 | 100.0% |
| `string_content` | 59 | 0 | 100.0% |
| `interpolation_expression_start` | 2 | 0 | 100.0% |
| `interpolation_identifier_start` | 1 | 0 | 100.0% |

**Zero spurious with no envelope at all**, asked at every byte of every file. The
delimiter stack decides where a string ends without help from the parse table,
which is the strongest form the 1a question has: the organs are sufficient, not
merely adequate once filtered.

The cohort is the six string-and-comment terminals. Automatic-semicolon
insertion, the import dot and the primary-constructor keyword are the other four,
and every branch of all three is gated on `valid_symbols` - they are a caller's
question, and counting them here would report the *scope* of the transcription as
a defect in the algebra.

Six of the twenty files are the adversarial specimens written against this exact
scanner: an embedded quote, an escaped quote, a greedy `"""` close, an
interpolation, a nested interpolation, and an unterminated string. Two of those
found real transcription errors before they found nothing (below).

---

## 1b - composition

**The question.** An organ effect over a segment is a stack effect - pop *k*,
push a suffix, and a register map - and stack effects compose. Cut a file, take
each segment's effect from the state at its own left edge, and the product has to
be what the whole file produced.

**Compared at every cut, not at end of input.** A file that closes what it opens
has an empty state at EOF, so an end-state comparison would pass a customary
whose middle was wrong everywhere - and since strings and blocks close, that is
most files. The whole-file walk journals the state on arrival at every offset it
moves the cursor to; a product has to match that entry the moment it gets there.

| grammar | files | schedules | disagreed |
|---|---:|---:|---:|
| markdown | 531 | 3,186 | **0** |
| kotlin | 20 | 120 | **0** |

Six schedules per file - 2, 3, 7, 16, 64 and 256 cuts - so a 30 KB file is cut
every 120 bytes at the finest.

**Cuts land where the whole-file walk asked, not on arbitrary bytes**, and that
is a definition rather than a weakening. Lexer state is defined *between* tokens:
it is where tree-sitter reuses a token, and it is where weave will re-enter. A
cut through the middle of `"""` asks what half a delimiter means, which is a
question about a token and not about composition. The one thing this rules out is
also the one thing no incremental lexer does.

---

## What the rung cost: four widenings, all recorded

The kill condition was a mismatch no edit could fix. These are the edits.

| widening | forced by | what the census had already seen |
|---|---|---|
| `pass` - a bounded sweep over **one organ**, its body chosen by the entry's kind | markdown | `while (s->matched < open_blocks.size) match(...)`: a loop over the block stack, bounded by its depth, not over bytes |
| `nest` - a balanced run to where the opener is paid off | kotlin (and swift, scala the same way) | "swift's comment depth lives on the C stack... it is a counter; a register holds it" - true, and this is the guard that moves it |
| `abstain` - end the ask, answer nothing | kotlin | every `return false` that follows a state write. Without it the rule behind answers at an offset the rule in front just accounted for, which is exactly how a `}` closing an interpolation became string content |
| `span k` - the width of one group of the guard's own match | kotlin, swift | `prefix_len` and `ongoing_raw_str_hash_count` are both the length of a run the scanner had just read |

None adds an unbounded computation. `pass` is bounded by a stack depth, `nest` by
the bytes it claims, and the other two are reads, so
[`CLAIM.md`](CLAIM.md)'s "no rule whose cost is not bounded by the bytes it
consumed plus a constant" still holds.

**Three of the four are effects, not inputs**, which matters for rung 0's kill
condition: it asked whether a decision could need an input outside the named set,
and after two full transcriptions the answer is still no. What was missing was
never *what a rule may read*.

## Three things the transcriptions got wrong first, and how

Worth writing down, because the tier system exists for exactly this and the
failure mode is a confidently wrong tree.

1. **An interpolation's closing brace became string content.**
   `interpolation.kt` answered `} b` where tree-sitter answered `b`, space
   included. The rule that noticed the brace and reopened the string did its
   remembering and then let the rule behind it answer at the same offset.
   `abstain` is the C's own shape restored.
2. **An unterminated string answered content the C refuses.** `scan_string_content`
   only returns when it *reaches* a stopper; at end of input it breaks and returns
   false, so `"abc<eof>` has no content token at all and the parser re-lexes
   `abc` as an identifier. The probe now requires the stopper it stops at.
3. **`"aa\$"` is one `STRING_END`, not content plus an end.** The C consumes the
   backslash, the dollar *and* the quote in one token, and its own comment calls
   this an edge case. It is not gated on the delimiter being single, so a
   triple-quoted string closes on it too - transcribed as the C decides it, not
   as Kotlin means it. A customary is a reading of a scanner, and where the
   scanner is wrong about its own language the reading has to be wrong with it or
   the trees diverge.

## What rung 1 does not settle

- **The permission set.** markdown's 183 extra answers are the measure of how
  much of its scanner the bytes and organs decide alone: 98.3% of the observable
  answers, and the rest wants `valid_symbols`. That is rung 2's, where the seam
  has it.
- **Where the asks happen.** A book declares `asks` here - `line` for a block
  scanner's two ask points, `token` for a scanner called between adjacent tokens.
  That field is harness scaffolding and does not exist in the engine, where
  `Scanner.read` is called where it is called.
- **Cost.** Nothing here is timed. Rung 5 owns that, and an interpreter in Python
  says nothing about one in Zig.
